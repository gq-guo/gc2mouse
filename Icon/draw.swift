// 生成 1024×1024 的 App 图标 PNG：swift Icon/draw.swift <输出.png>
// 紫色圆角方块 + 白色手柄 + 鼠标指针

import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// 背景：macOS 图标网格，824×824 圆角方块，带投影
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35).cgColor)
rgb(0x3B32C8).setFill()
tilePath.fill()
ctx.restoreGState()

ctx.saveGState()
tilePath.addClip()
NSGradient(colors: [rgb(0x7C6CFF), rgb(0x4B3FE0), rgb(0x2A2296)])!.draw(in: tile, angle: -60)
// 顶部高光
NSGradient(colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)])!
    .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
ctx.restoreGState()

// 手柄：机身 + 左右两个握把
let pad = NSBezierPath()
pad.append(NSBezierPath(roundedRect: NSRect(x: 222, y: 448, width: 580, height: 236), xRadius: 118, yRadius: 118))
for (cx, angle) in [(CGFloat(300), CGFloat(-28)), (CGFloat(724), CGFloat(28))] {
    let grip = NSBezierPath(roundedRect: NSRect(x: -78, y: -150, width: 156, height: 300), xRadius: 78, yRadius: 78)
    var t = AffineTransform(translationByX: cx, byY: 448)
    t.rotate(byDegrees: angle)
    grip.transform(using: t)
    pad.append(grip)
}
pad.windingRule = .nonZero

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x14104F, 0.45).cgColor)
rgb(0xFFFFFF).setFill()
pad.fill()
ctx.restoreGState()
// 机身下缘一点阴影，增加体积感
ctx.saveGState()
pad.addClip()
NSGradient(colors: [rgb(0xD9D6FF, 0), rgb(0xC9C4FF, 0.9)])!
    .draw(in: NSRect(x: 150, y: 290, width: 724, height: 260), angle: -90)
ctx.restoreGState()

// 十字键
let ink = rgb(0x3B32C8)
ink.setFill()
let dc = CGPoint(x: 362, y: 566)
NSBezierPath(roundedRect: NSRect(x: dc.x - 66, y: dc.y - 22, width: 132, height: 44), xRadius: 10, yRadius: 10).fill()
NSBezierPath(roundedRect: NSRect(x: dc.x - 22, y: dc.y - 66, width: 44, height: 132), xRadius: 10, yRadius: 10).fill()

// 四个功能键（Xbox 配色）
let bc = CGPoint(x: 662, y: 566)
for (dx, dy, color) in [(CGFloat(0), CGFloat(50), 0xF2B705), (50, 0, 0xE5484D), (0, -50, 0x30A46C), (-50, 0, 0x3E8BF2)] {
    rgb(UInt32(color)).setFill()
    NSBezierPath(ovalIn: NSRect(x: bc.x + dx - 23, y: bc.y + dy - 23, width: 46, height: 46)).fill()
}

// 鼠标指针：经典箭头，黑底白边，尖端落在手柄中下部
let tip = CGPoint(x: 530, y: 525)
let k: CGFloat = 16.5
let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13), (7, 19.5), (9.6, 18.4), (6.7, 12.1), (12, 12)]
let arrow = NSBezierPath()
for (i, p) in pts.enumerated() {
    let q = CGPoint(x: tip.x + p.0 * k, y: tip.y - p.1 * k)
    i == 0 ? arrow.move(to: q) : arrow.line(to: q)
}
arrow.close()
arrow.lineJoinStyle = .round
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.4).cgColor)
rgb(0xFFFFFF).setStroke()
arrow.lineWidth = 30
arrow.stroke()
ctx.restoreGState()
rgb(0x16141F).setFill()
arrow.fill()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
