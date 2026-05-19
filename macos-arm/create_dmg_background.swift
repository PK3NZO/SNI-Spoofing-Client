import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let outputPath = args.first ?? "background.png"
let appName = args.dropFirst().first ?? "SNI-Spoofing Client"

let visibleSize = NSSize(width: 820, height: 460)
let size = NSSize(width: 1300, height: 800)
let image = NSImage(size: size)
let topOffset = size.height - visibleSize.height

func y(_ value: CGFloat) -> CGFloat {
    value + topOffset
}

func drawText(
    _ text: String,
    at point: NSPoint,
    size fontSize: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    alignment: NSTextAlignment = .center,
    width: CGFloat = 760
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(
        in: NSRect(x: point.x, y: point.y, width: width, height: fontSize * 1.8),
        withAttributes: attributes
    )
}

func drawRoundedRect(_ rect: NSRect, fill: NSColor, stroke: NSColor, radius: CGFloat = 26) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    stroke.setStroke()
    path.lineWidth = 1.5
    path.stroke()
}

image.lockFocus()

NSColor(calibratedRed: 0.95, green: 0.965, blue: 0.985, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.995, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.97, alpha: 1)
])
gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 90)

drawText(
    "Install \(appName)",
    at: NSPoint(x: 30, y: y(382)),
    size: 28,
    weight: .bold,
    color: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.24, alpha: 1)
)
drawText(
    "Drag the app into Applications",
    at: NSPoint(x: 30, y: y(348)),
    size: 16,
    weight: .medium,
    color: NSColor(calibratedRed: 0.34, green: 0.38, blue: 0.45, alpha: 1)
)

let leftRect = NSRect(x: 96, y: y(138), width: 214, height: 174)
let rightRect = NSRect(x: 510, y: y(138), width: 214, height: 174)
drawRoundedRect(
    leftRect,
    fill: NSColor(calibratedWhite: 1, alpha: 0.55),
    stroke: NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.58, alpha: 0.30)
)
drawRoundedRect(
    rightRect,
    fill: NSColor(calibratedWhite: 1, alpha: 0.55),
    stroke: NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.58, alpha: 0.30)
)

drawText(
    "1",
    at: NSPoint(x: 142, y: y(252)),
    size: 54,
    weight: .bold,
    color: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.30, alpha: 0.16),
    width: 122
)
drawText(
    "2",
    at: NSPoint(x: 556, y: y(252)),
    size: 54,
    weight: .bold,
    color: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.30, alpha: 0.16),
    width: 122
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 335, y: y(226)))
arrow.line(to: NSPoint(x: 485, y: y(226)))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.92, alpha: 1).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 485, y: y(226)))
head.line(to: NSPoint(x: 462, y: y(246)))
head.move(to: NSPoint(x: 485, y: y(226)))
head.line(to: NSPoint(x: 462, y: y(206)))
head.lineWidth = 5
head.lineCapStyle = .round
head.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Unable to render DMG background")
}

try png.write(to: URL(fileURLWithPath: outputPath))
