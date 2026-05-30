// Genera el fondo del instalador DMG (flecha + texto "Drag to Applications").
// Uso: swiftc make-bg.swift -o mkbg -framework Cocoa && ./mkbg salida.png
import Cocoa

let W = 660, H = 420
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Fondo: degradado suave con acento verde Flubber.
let cs = CGColorSpaceCreateDeviceRGB()
let colors = [
    NSColor(calibratedWhite: 0.99, alpha: 1).cgColor,
    NSColor(red: 0.90, green: 0.96, blue: 0.91, alpha: 1).cgColor,
] as CFArray
if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
}

// Flecha (coords origen abajo-izquierda; los íconos van a x≈180 y x≈480).
let green = NSColor(red: 0.20, green: 0.65, blue: 0.36, alpha: 1)
green.setStroke(); green.setFill()
let y: CGFloat = 210
let shaft = NSBezierPath()
shaft.lineWidth = 10
shaft.lineCapStyle = .round
shaft.move(to: CGPoint(x: 258, y: y))
shaft.line(to: CGPoint(x: 398, y: y))
shaft.stroke()
let head = NSBezierPath()
head.move(to: CGPoint(x: 420, y: y))
head.line(to: CGPoint(x: 392, y: y + 17))
head.line(to: CGPoint(x: 392, y: y - 17))
head.close()
head.fill()

// Título.
let para = NSMutableParagraphStyle(); para.alignment = .center
func drawCentered(_ s: String, size: CGFloat, weight: NSFont.Weight, white: CGFloat, atTopY: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(calibratedWhite: white, alpha: 1),
        .paragraphStyle: para,
    ]
    let ns = NSAttributedString(string: s, attributes: attrs)
    let sz = ns.size()
    ns.draw(at: CGPoint(x: (CGFloat(W) - sz.width) / 2, y: CGFloat(H) - atTopY))
}
drawCentered("Drag Flubber into Applications", size: 21, weight: .semibold, white: 0.13, atTopY: 64)
drawCentered("to install", size: 13, weight: .regular, white: 0.45, atTopY: 92)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try data.write(to: URL(fileURLWithPath: outPath)); print("✅ background → \(outPath)") }
catch { FileHandle.standardError.write("no pude escribir \(outPath)\n".data(using: .utf8)!); exit(1) }
