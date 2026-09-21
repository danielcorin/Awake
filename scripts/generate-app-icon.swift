#!/usr/bin/env swift
// TEMPLATE from the app-icon skill. Copy to <repo>/scripts/generate-app-icon.swift
// and customize the PER-APP parts (the color constants, drawGlyph, and the SVG
// emission at the bottom, which must mirror drawGlyph's geometry). Keep the
// render/write plumbing as is. Run with:
//   swift scripts/generate-app-icon.swift
//
// Keep the design minimal per current (macOS/iOS 26) icon guidance: a single
// white glyph on a brand-color gradient. The example glyph is three rounded
// horizontal bars.
//
// Outputs:
// - Sources/App/AppIcon.icon/Assets/glyph.svg — the Liquid Glass foreground
//   layer used by the Icon Composer package (icon.json lives alongside it).
//   The system supplies the squircle mask, lighting, and appearance modes,
//   so the layer is full-bleed with no baked-in shape or shadow.
// - Sources/App/Assets.xcassets/AppIcon.appiconset — legacy macOS (15 and
//   earlier) PNGs: same artwork inside the HIG rounded rect with margins
//   and a drop shadow, re-rendered per size so small sizes stay crisp.
// - Sources/App/Assets.xcassets/AppIcon-iOS.appiconset — legacy iOS
//   full-bleed 1024 for a future iOS target.

import AppKit
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let gradientTop = RGB(0xFFCB4D)
let gradientBottom = RGB(0xEF6C12)
let glyphWhite = RGB(0xFFFFFF)

// A sun, matching the active menu bar state. Geometry as fractions of a 1024
// canvas, shared by the SVG layer and the legacy PNGs. Every part is a closed
// filled shape: an open stroke would pick up a hairline through the glass mask.
let discRadius: CGFloat = 118 / 1024
let rayInner: CGFloat = 168 / 1024
let rayOuter: CGFloat = 278 / 1024
let rayHalf: CGFloat = 31 / 1024
let rayCount = 8

func drawGlyph(_ ctx: CGContext, in content: CGRect) {
    let s = content.width
    let center = CGPoint(x: content.midX, y: content.midY)
    ctx.setFillColor(glyphWhite.cg())
    ctx.addEllipse(in: CGRect(x: center.x - discRadius * s, y: center.y - discRadius * s,
                              width: 2 * discRadius * s, height: 2 * discRadius * s))
    ctx.fillPath()
    let ray = CGRect(x: rayInner * s, y: -rayHalf * s,
                     width: (rayOuter - rayInner) * s, height: 2 * rayHalf * s)
    for index in 0..<rayCount {
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(index) * 2 * .pi / CGFloat(rayCount))
        ctx.addPath(CGPath(roundedRect: ray, cornerWidth: rayHalf * s, cornerHeight: rayHalf * s,
                           transform: &transform))
        ctx.fillPath()
    }
}

func render(pixels: Int, macStyle: Bool) -> CGImage {
    let S = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels,
                        bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    let content: CGRect
    let bgPath: CGPath
    if macStyle {
        let inset = S * 100 / 1024
        content = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
        let radius = content.width * 185 / 824
        bgPath = CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.010), blur: S * 0.022,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
        ctx.addPath(bgPath)
        ctx.setFillColor(gradientBottom.cg())
        ctx.fillPath()
        ctx.restoreGState()
    } else {
        content = CGRect(x: 0, y: 0, width: S, height: S)
        bgPath = CGPath(rect: content, transform: nil)
    }

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb,
                        colors: [gradientTop.cg(), gradientBottom.cg()] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg,
                           start: CGPoint(x: content.midX, y: content.maxY),
                           end: CGPoint(x: content.midX, y: content.minY),
                           options: [])
    drawGlyph(ctx, in: content)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! data.write(to: url)
    print("wrote \(path)")
}

func writePNG(_ image: CGImage, to path: String) {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to encode \(path)") }
    write(data as Data, to: path)
}

let root = FileManager.default.currentDirectoryPath
let macSet = "\(root)/Sources/App/Assets.xcassets/AppIcon.appiconset"
let iosSet = "\(root)/Sources/App/Assets.xcassets/AppIcon-iOS.appiconset"

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(render(pixels: pixels, macStyle: true), to: "\(macSet)/icon_\(pixels).png")
}
writePNG(render(pixels: 1024, macStyle: false), to: "\(iosSet)/icon_1024.png")

// Liquid Glass foreground layer for AppIcon.icon, mirroring the geometry
// above. Rays are emitted as explicit capsule paths rather than rotated rects:
// absolute coordinates avoid depending on SVG transform support in actool.
func capsulePath(angle: CGFloat) -> String {
    let c: CGFloat = 512
    let r = rayHalf * 1024
    let d = CGPoint(x: cos(angle), y: sin(angle))
    let n = CGPoint(x: -d.y, y: d.x)
    let a = CGPoint(x: c + d.x * rayInner * 1024, y: c + d.y * rayInner * 1024)
    let b = CGPoint(x: c + d.x * rayOuter * 1024, y: c + d.y * rayOuter * 1024)
    func f(_ value: CGFloat) -> String { String(format: "%.2f", value) }
    return "M \(f(a.x + n.x * r)) \(f(a.y + n.y * r)) "
        + "L \(f(b.x + n.x * r)) \(f(b.y + n.y * r)) "
        + "A \(f(r)) \(f(r)) 0 0 0 \(f(b.x - n.x * r)) \(f(b.y - n.y * r)) "
        + "L \(f(a.x - n.x * r)) \(f(a.y - n.y * r)) "
        + "A \(f(r)) \(f(r)) 0 0 0 \(f(a.x + n.x * r)) \(f(a.y + n.y * r)) Z"
}
var svgRays = ""
for index in 0..<rayCount {
    let angle = CGFloat(index) * 2 * .pi / CGFloat(rayCount)
    svgRays += "  <path d=\"\(capsulePath(angle: angle))\" fill=\"#FFFFFF\"/>\n"
}
let svg = """
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <circle cx="512" cy="512" r="\(Int(discRadius * 1024))" fill="#FFFFFF"/>
\(svgRays)</svg>
"""
write(Data(svg.utf8), to: "\(root)/Sources/App/AppIcon.icon/Assets/glyph.svg")
