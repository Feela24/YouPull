import AppKit
import SwiftUI

final class OpenPullAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        } else {
            NSApp.applicationIconImage = makeFallbackIcon()
        }
    }

    private func makeFallbackIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let background = NSRect(x: 18, y: 18, width: 476, height: 476)
        NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: background, xRadius: 112, yRadius: 112).fill()

        NSColor.white.setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 42
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 256, y: 350))
        arrow.line(to: NSPoint(x: 256, y: 190))
        arrow.move(to: NSPoint(x: 178, y: 258))
        arrow.line(to: NSPoint(x: 256, y: 180))
        arrow.line(to: NSPoint(x: 334, y: 258))
        arrow.stroke()

        let tray = NSBezierPath()
        tray.lineWidth = 34
        tray.lineCapStyle = .round
        tray.move(to: NSPoint(x: 154, y: 135))
        tray.line(to: NSPoint(x: 358, y: 135))
        tray.stroke()

        return image
    }
}

@main
struct OpenPullApp: App {
    @NSApplicationDelegateAdaptor(OpenPullAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button(model.t("menu.pasteURL")) {
                    model.importClipboardURL()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
