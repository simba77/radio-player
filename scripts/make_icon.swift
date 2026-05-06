#!/usr/bin/env swift
import AppKit

let size = 1024
let s = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let cx = s / 2
let antennaBaseY = s * 0.64
let antennaTipY  = s * 0.36

// — Background (rounded rect + gradient) —
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                   cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
ctx.clip()
let gradColors = [
    CGColor(colorSpace: cs, components: [0.20, 0.45, 0.95, 1.0])!,
    CGColor(colorSpace: cs, components: [0.06, 0.18, 0.72, 1.0])!,
] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(grad, start: CGPoint(x: cx, y: s), end: CGPoint(x: cx, y: 0), options: [])
ctx.restoreGState()

// — White strokes —
ctx.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 0.93])!)
ctx.setLineCap(.round)
let sw: CGFloat = s * 0.042

// Mast
ctx.setLineWidth(sw)
ctx.move(to: CGPoint(x: cx, y: antennaBaseY))
ctx.addLine(to: CGPoint(x: cx, y: antennaTipY))
ctx.strokePath()

// Base
ctx.move(to: CGPoint(x: cx - sw * 2.8, y: antennaBaseY))
ctx.addLine(to: CGPoint(x: cx + sw * 2.8, y: antennaBaseY))
ctx.strokePath()

// Waves (concentric arcs from antenna tip)
let waveC = CGPoint(x: cx, y: antennaTipY)
let radii: [CGFloat] = [s * 0.13, s * 0.22, s * 0.31]
let pi = CGFloat.pi
for (i, r) in radii.enumerated() {
    ctx.setLineWidth(sw * (1.0 - CGFloat(i) * 0.12))
    ctx.addArc(center: waveC, radius: r, startAngle: 22*pi/180, endAngle: 68*pi/180, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: waveC, radius: r, startAngle: 112*pi/180, endAngle: 158*pi/180, clockwise: false)
    ctx.strokePath()
}

// — Export PNG —
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    .representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
print("Created Resources/AppIcon.png")
