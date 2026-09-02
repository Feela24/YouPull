import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case failed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "Proces se nepodařilo spustit: \(message)"
        case .failed(let exitCode, let message):
            return message.isEmpty ? "Proces skončil s chybou \(exitCode)." : message
        }
    }
}

final class LockedDataBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class LineAccumulator {
    private let lock = NSLock()
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: .newlines))
            }
        }
        lock.unlock()
        for line in lines where !line.isEmpty { onLine(line) }
    }

    func flush() {
        lock.lock()
        let remainder = buffer
        buffer.removeAll()
        lock.unlock()
        if let line = String(data: remainder, encoding: .utf8), !line.isEmpty {
            onLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Bezpečně propojí Swift Task cancellation s právě běžícím externím procesem.
/// Pokud uživatel zastaví frontu, Task se zruší a tento objekt pošle SIGTERM
/// běžícímu yt-dlp (a pokud je to bezpečné, celé jeho process group včetně ffmpeg).
/// Pokud ke zrušení dojde těsně před spuštěním procesu, požadavek si zapamatuje
/// a proces ukončí hned po startu.
final class RunningProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldCancel = cancellationRequested
        lock.unlock()

        if shouldCancel {
            terminateProcessTree(process)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let runningProcess = process
        lock.unlock()

        if let runningProcess {
            terminateProcessTree(runningProcess)
        }
    }

    func detach() {
        lock.lock(); defer { lock.unlock() }
        process = nil
    }

    private func terminateProcessTree(_ process: Process) {
        guard process.isRunning else { return }

        #if os(macOS)
        // Foundation na macOS dokumentuje terminate() jako ukončení Processu
        // i jeho subtasks, takže se spolu s yt-dlp zastaví také spuštěný ffmpeg.
        process.terminate()
        #else
        // Fallback pro vývojové/testovací prostředí mimo macOS.
        let pid = process.processIdentifier
        let processGroup = getpgid(pid)
        if processGroup == pid {
            _ = kill(-pid, SIGTERM)
        } else {
            _ = kill(pid, SIGTERM)
        }
        #endif
    }
}

enum ProcessRunner {
    static func run(executable: URL, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            let outBuffer = LockedDataBuffer()
            let errBuffer = LockedDataBuffer()

            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = outPipe
            process.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { outBuffer.append(data) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { errBuffer.append(data) }
            }

            process.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let outTail = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errTail = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !outTail.isEmpty { outBuffer.append(outTail) }
                if !errTail.isEmpty { errBuffer.append(errTail) }

                let result = ProcessResult(exitCode: p.terminationStatus,
                                           stdout: outBuffer.string(),
                                           stderr: errBuffer.string())
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }

    static func runStreaming(executable: URL,
                             arguments: [String],
                             onLine: @escaping (String) -> Void) async throws -> Int32 {
        let cancellation = RunningProcessCancellation()

        let exitCode: Int32 = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let pipe = Pipe()
                let accumulator = LineAccumulator(onLine: onLine)

                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty { accumulator.append(data) }
                }

                process.terminationHandler = { p in
                    cancellation.detach()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let tail = pipe.fileHandleForReading.readDataToEndOfFile()
                    if !tail.isEmpty { accumulator.append(tail) }
                    accumulator.flush()
                    continuation.resume(returning: p.terminationStatus)
                }

                do {
                    try process.run()
                    cancellation.attach(process)
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    cancellation.detach()
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                }
            }
        }, onCancel: {
            cancellation.cancel()
        })

        // Zrušený proces skončí nenulovým kódem. Tímto z něj uděláme
        // CancellationError, aby UI neukazovalo vědomé zastavení jako chybu.
        try Task.checkCancellation()
        return exitCode
    }
}
