// 菜单栏图标：手柄剪影（模板图，自动适配浅色 / 深色菜单栏）

import Cocoa

enum StatusIcon {
    static let normal = make(slash: false)
    static let disconnected = make(slash: true)

    private static func make(slash: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            NSColor.black.setFill()

            // 机身 + 左右握把
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 6, width: 17, height: 8.5), xRadius: 4.25, yRadius: 4.25).fill()
            for (cx, angle) in [(CGFloat(5.6), CGFloat(-28)), (CGFloat(16.4), CGFloat(28))] {
                let grip = NSBezierPath(roundedRect: NSRect(x: -2.7, y: -5, width: 5.4, height: 10), xRadius: 2.7, yRadius: 2.7)
                var t = AffineTransform(translationByX: cx, byY: 6.5)
                t.rotate(byDegrees: angle)
                grip.transform(using: t)
                grip.fill()
            }

            // 挖空十字键和四个按键
            ctx.setBlendMode(.clear)
            let d = CGPoint(x: 6.9, y: 10.2)
            NSBezierPath(rect: NSRect(x: d.x - 2.3, y: d.y - 0.75, width: 4.6, height: 1.5)).fill()
            NSBezierPath(rect: NSRect(x: d.x - 0.75, y: d.y - 2.3, width: 1.5, height: 4.6)).fill()
            let b = CGPoint(x: 15.1, y: 10.2)
            for (dx, dy) in [(0.0, 1.6), (1.6, 0.0), (0.0, -1.6), (-1.6, 0.0)] {
                NSBezierPath(ovalIn: NSRect(x: b.x + dx - 0.85, y: b.y + dy - 0.85, width: 1.7, height: 1.7)).fill()
            }

            // 未连接：加一道斜杠（先挖出缝隙，再画线）
            if slash {
                let line = NSBezierPath()
                line.move(to: CGPoint(x: 3, y: 15))
                line.line(to: CGPoint(x: 19, y: 1))
                line.lineCapStyle = .round
                line.lineWidth = 3.6
                line.stroke()
                ctx.setBlendMode(.normal)
                NSColor.black.setStroke()
                line.lineWidth = 1.4
                line.stroke()
            }
            ctx.endTransparencyLayer()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "gc2mouse"
        return img
    }
}
