// Generates the app icon (master 1024 PNG) reproducing EXACTLY the same
// pixel-art logic used to draw the slime in Sources/main.swift
// (elliptical body, dark border, highlight, shine, happy face and cheeks).
// Usage: swiftc -O make-icon.swift -o mkicon -framework Cocoa && ./mkicon output.png [size]
import Cocoa

// ----- Green slime palette (identical to Pal.skins[0] / Pal.* in main.swift) -----
let body  = NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 1)
let dark  = NSColor(srgbRed: 0.20, green: 0.62, blue: 0.40, alpha: 1)
let light = NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1)
let shine = NSColor(srgbRed: 0.92, green: 1.00, blue: 0.95, alpha: 1)
let eye      = NSColor(srgbRed: 0.10, green: 0.16, blue: 0.18, alpha: 1)
let eyeWhite = NSColor.white
let mouth    = NSColor(srgbRed: 0.15, green: 0.40, blue: 0.28, alpha: 1)
let blush    = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.62, alpha: 0.55)

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master.png"
let N = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: N, pixelsHigh: N,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let n = CGFloat(N)

// ----- Background: rounded square (app style) with mint→white gradient -----
ctx.setShouldAntialias(true)
let radius = n * 0.2235
let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: n, height: n),
                cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(bg); ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    NSColor(srgbRed: 0.91, green: 0.98, blue: 0.93, alpha: 1).cgColor,   // light mint at top
    NSColor.white.cgColor,                                               // white at bottom
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: n), end: CGPoint(x: 0, y: 0), options: [])

// ----- Slime grid geometry (same as PetView: 32×32, cx=16, footY=3) -----
let cx = 16.0
let footY = 3
let baseHalf = 11.0, baseHeight = 17.0
let halfW = baseHalf, height = baseHeight

// Fit the slime (bbox grid x≈5..27, y≈3..20) centered, with room for the shadow.
let widthCells = 24.0
let cell = n * 0.56 / widthCells
let originX = n / 2 - cx * cell
let originY = n / 2 - 11.0 * cell        // vertical center of the slime ≈ grid y 11

func fill(_ gx: Int, _ gy: Int, _ c: NSColor) {
    ctx.setShouldAntialias(false)
    ctx.setFillColor(c.cgColor)
    ctx.fill(CGRect(x: originX + CGFloat(gx) * cell, y: originY + CGFloat(gy) * cell,
                    width: cell + 0.5, height: cell + 0.5))
}

// ----- Soft shadow under the slime -----
ctx.setShouldAntialias(true)
let shCenter = CGPoint(x: originX + cx * cell, y: originY + 2.4 * cell)
let shRect = CGRect(x: shCenter.x - 11 * cell, y: shCenter.y - 2 * cell, width: 22 * cell, height: 4 * cell)
ctx.saveGState()
ctx.addEllipse(in: shRect); ctx.clip()
let shGrad = CGGradient(colorsSpace: cs, colors: [
    NSColor(white: 0, alpha: 0.16).cgColor, NSColor(white: 0, alpha: 0).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(shGrad, startCenter: shCenter, startRadius: 0,
                       endCenter: shCenter, endRadius: 11 * cell, options: [])
ctx.restoreGState()

// ----- Body (same elliptical formula + border + highlight as drawSlime) -----
for gy in 0..<Int(height) {
    let t = Double(gy) / height
    var w = halfW * (max(0, 1 - pow(t, 2.2))).squareRoot()
    w += sin(t * 3) * 0.25          // tick=0 (static)
    let xw = Int(w.rounded()); let y = footY + gy
    for dx in -xw...xw {
        let gx = Int(cx) + dx
        let edge = dx <= -xw + 1 || dx >= xw - 1 || gy == 0 || gy >= Int(height) - 1
        if edge { fill(gx, y, dark) }
        else if dx < 0 && t > 0.45 && t < 0.85 && dx > -xw + 3 { fill(gx, y, light) }
        else { fill(gx, y, body) }
    }
}

// shine
let shineY = footY + Int(height * 0.72)
fill(Int(cx) - 4, shineY, shine); fill(Int(cx) - 5, shineY, shine); fill(Int(cx) - 4, shineY - 1, shine)

// ----- Happy face, looking forward (drawFace: open eyes + smile + cheeks) -----
let faceY = footY + Int(height * 0.45)
let leftX = Int(cx) - 4, rightX = Int(cx) + 4
func eyeOpen(_ ex: Int) {
    for oy in 0..<4 { for ox in 0..<3 { fill(ex + ox, faceY + oy, eyeWhite) } }
    for oy in 0..<2 { for ox in 0..<2 { fill(ex + 1 + ox, faceY + 1 + oy, eye) } }   // centered pupil
}
eyeOpen(leftX); eyeOpen(rightX)
// wide smile (happy state)
for ox in -2...2 { fill(Int(cx) + ox, faceY - 3, mouth) }
for ox in -1...1 { fill(Int(cx) + ox, faceY - 4, mouth) }
// cheeks
fill(leftX - 1, faceY - 2, blush); fill(rightX + 2, faceY - 2, blush)

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try data.write(to: URL(fileURLWithPath: outPath)); print("✅ icon → \(outPath) (\(N)px)") }
catch { FileHandle.standardError.write("no pude escribir \(outPath)\n".data(using: .utf8)!); exit(1) }
