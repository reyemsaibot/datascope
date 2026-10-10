import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("Usage: swift make-icon.swift SOURCE.png OUTPUT.icns\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[2])
// These chunk identifiers are the names macOS uses when it chooses an app
// icon for the Dock. `icp4`/`icp5` look plausible but are legacy names and
// are not a reliable replacement for the modern Retina entries below.
let variants: [(String, Int)] = [
    ("ic04", 16),
    ("ic05", 32), ("ic11", 32),
    ("ic12", 64),
    ("ic07", 128),
    ("ic08", 256), ("ic13", 256),
    ("ic09", 512), ("ic14", 512),
    ("ic10", 1024)
]

func be32(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

var chunks = Data()
for (type, size) in variants {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let png = bitmap.representation(using: .png, properties: [:])!
    chunks.append(type.data(using: .ascii)!)
    chunks.append(be32(UInt32(png.count + 8)))
    chunks.append(png)
}

var icon = Data("icns".utf8)
icon.append(be32(UInt32(chunks.count + 8)))
icon.append(chunks)
try icon.write(to: output, options: .atomic)
