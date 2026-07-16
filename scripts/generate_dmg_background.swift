#!/usr/bin/env swift
// Draws a simple background image for the installer DMG (see
// scripts/make_dmg.sh): a light canvas with an arrow pointing from where
// the app icon sits towards the /Applications shortcut, plus a short
// instruction. Run as a plain script (no Xcode project needed) via
// `swift generate_dmg_background.swift <output.png> <width> <height>` —
// keeps this self-contained with no dependency beyond Xcode's command
// line tools, which the project already requires for everything else.
//
// The arrow's coordinates are deliberately kept in sync (by comment, not
// by shared code — AppleScript and Swift don't share values easily here)
// with the icon positions make_dmg.sh sets via Finder scripting. If you
// change one, change the other.

import AppKit

let arguments = CommandLine.arguments
guard
    arguments.count >= 4,
    let width = Double(arguments[2]),
    let height = Double(arguments[3])
else {
    FileHandle.standardError.write(
        Data("Usage: generate_dmg_background.swift <output.png> <width> <height>\n".utf8)
    )
    exit(1)
}

let outputPath = arguments[1]
let size = NSSize(width: width, height: height)

let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedWhite: 0.97, alpha: 1.0).setFill()
NSRect(origin: .zero, size: size).fill()

// Matches make_dmg.sh's icon positions: the app icon sits around x=160,
// the Applications shortcut around x=(width-160), both roughly mid-height.
let arrowY = height * 0.52
let startX = width * 0.34
let endX = width * 0.66

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: startX, y: arrowY))
shaft.line(to: NSPoint(x: endX - 16, y: arrowY))
shaft.lineWidth = 3
NSColor(calibratedWhite: 0.55, alpha: 1.0).setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: endX - 22, y: arrowY + 11))
head.line(to: NSPoint(x: endX, y: arrowY))
head.line(to: NSPoint(x: endX - 22, y: arrowY - 11))
head.lineWidth = 3
NSColor(calibratedWhite: 0.55, alpha: 1.0).setStroke()
head.stroke()

let text = "Drag XDragMover onto Applications to install it."
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13),
    .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
]
let textSize = text.size(withAttributes: attributes)
let textPoint = NSPoint(x: (size.width - textSize.width) / 2, y: height * 0.12)
text.draw(at: textPoint, withAttributes: attributes)

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("error: failed to render background PNG\n".utf8))
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write(Data("error: failed to write \(outputPath): \(error)\n".utf8))
    exit(1)
}
