import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: generate-default-icon.swift /path/to/output.png\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSRect(x: 36, y: 36, width: 952, height: 952)
NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.96, alpha: 1).setFill()
NSBezierPath(roundedRect: background, xRadius: 224, yRadius: 224).fill()

NSColor.white.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 84
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 512, y: 700))
arrow.line(to: NSPoint(x: 512, y: 380))
arrow.move(to: NSPoint(x: 356, y: 516))
arrow.line(to: NSPoint(x: 512, y: 360))
arrow.line(to: NSPoint(x: 668, y: 516))
arrow.stroke()

let tray = NSBezierPath()
tray.lineWidth = 68
tray.lineCapStyle = .round
tray.move(to: NSPoint(x: 308, y: 270))
tray.line(to: NSPoint(x: 716, y: 270))
tray.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render icon PNG\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
