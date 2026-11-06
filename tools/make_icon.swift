// Generates a 1024x1024 modern macOS squircle icon for Forza Horizon 2 (Apple Silicon Launcher)
// Usage: swift tools/make_icon.swift <out.png>

import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// macOS Big Sur+ squircle tile (824x824 centered in 1024x1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Subtle outer shadow before clipping
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: rgb(0, 0, 0, 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0.06, 0.07, 0.10))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Deep slate/twilight Mediterranean sky gradient
let horizon: CGFloat = 460
let skyGrad = CGGradient(
    colorsSpace: space,
    colors: [
        rgb(0.055, 0.067, 0.098),   // #0E1119 top
        rgb(0.090, 0.145, 0.235),   // deep navy-cyan
        rgb(0.85, 0.31, 0.44),      // Horizon sunset rose
        rgb(1.00, 0.60, 0.24)       // warm golden horizon
    ] as CFArray,
    locations: [0.0, 0.45, 0.80, 1.0]
)!
ctx.drawLinearGradient(skyGrad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: horizon), options: [])

// Cyan-gold ambient glow around horizon center
let sunCenter = CGPoint(x: 512, y: horizon + 36)
let sunGlow = CGGradient(
    colorsSpace: space,
    colors: [
        rgb(1.0, 0.88, 0.55, 0.90),
        rgb(1.0, 0.45, 0.30, 0.35),
        rgb(0.125, 0.745, 1.0, 0.0)
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawRadialGradient(sunGlow, startCenter: sunCenter, startRadius: 0, endCenter: sunCenter, endRadius: 340, options: [])

// Stylized Horizon Sun Disc
ctx.setFillColor(rgb(1.0, 0.88, 0.54, 0.95))
ctx.fillEllipse(in: CGRect(x: sunCenter.x - 135, y: sunCenter.y - 135, width: 270, height: 270))

// Layered Riviera Hills
func drawHills(baseY: CGFloat, amp: CGFloat, phase: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.move(to: CGPoint(x: 100, y: 100))
    var x: CGFloat = 100
    while x <= 924 {
        let norm = (x - 100) / 824.0
        let y = baseY + amp * sin(norm * .pi * 2.1 + phase) + (amp * 0.38) * cos(norm * .pi * 4.7 + phase * 1.7)
        ctx.addLine(to: CGPoint(x: x, y: y))
        x += 6
    }
    ctx.addLine(to: CGPoint(x: 924, y: 100))
    ctx.closePath()
    ctx.fillPath()
}

drawHills(baseY: horizon + 26, amp: 32, phase: 0.5, color: rgb(0.18, 0.12, 0.24))
drawHills(baseY: horizon - 12, amp: 22, phase: 2.2, color: rgb(0.08, 0.09, 0.14))

// Ground plane
let groundGrad = CGGradient(
    colorsSpace: space,
    colors: [
        rgb(0.08, 0.09, 0.14),
        rgb(0.04, 0.05, 0.08)
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(groundGrad, start: CGPoint(x: 512, y: horizon - 10), end: CGPoint(x: 512, y: 100), options: [])

// Perspective Highway converging to vanishing point
let vanish = CGPoint(x: 512, y: horizon - 14)
ctx.setFillColor(rgb(0.07, 0.08, 0.11))
ctx.move(to: vanish)
ctx.addLine(to: CGPoint(x: 890, y: 100))
ctx.addLine(to: CGPoint(x: 134, y: 100))
ctx.closePath()
ctx.fillPath()

// Kaggle Cyan-Blue (#20BEFF) glowing outer road rails
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 16, color: rgb(0.125, 0.745, 1.0, 0.75))
ctx.setStrokeColor(rgb(0.125, 0.745, 1.0, 0.95))
ctx.setLineWidth(9)
ctx.move(to: vanish)
ctx.addLine(to: CGPoint(x: 882, y: 100))
ctx.move(to: vanish)
ctx.addLine(to: CGPoint(x: 142, y: 100))
ctx.strokePath()
ctx.restoreGState()

// Center perspective dashes in warm white/gold
ctx.setFillColor(rgb(0.96, 0.98, 1.0, 0.92))
var t: CGFloat = 0.08
while t < 1.0 {
    let t2 = min(t + 0.065 + t * 0.065, 1.0)
    let y1 = vanish.y - (vanish.y - 100) * t
    let y2 = vanish.y - (vanish.y - 100) * t2
    let w1 = 3.5 + 24.0 * t
    let w2 = 3.5 + 24.0 * t2
    ctx.move(to: CGPoint(x: 512 - w1 / 2, y: y1))
    ctx.addLine(to: CGPoint(x: 512 + w1 / 2, y: y1))
    ctx.addLine(to: CGPoint(x: 512 + w2 / 2, y: y2))
    ctx.addLine(to: CGPoint(x: 512 - w2 / 2, y: y2))
    ctx.closePath()
    ctx.fillPath()
    t = t2 + 0.045 + t * 0.075
}

// Subtle inner border rim (1px glass highlight)
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(1.0, 1.0, 1.0, 0.16))
ctx.setLineWidth(4)
ctx.strokePath()

ctx.restoreGState()
NSGraphicsContext.current = nil

let pngData = rep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: out))
