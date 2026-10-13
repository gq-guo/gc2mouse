// 向系统发送鼠标 / 键盘 / 媒体键事件。需要「辅助功能」权限。

import Cocoa

enum Key {
    static let left: CGKeyCode = 0x7B, right: CGKeyCode = 0x7C, down: CGKeyCode = 0x7D, up: CGKeyCode = 0x7E
    static let tab: CGKeyCode = 0x30, cmd: CGKeyCode = 0x37
    static let arrows: Set<CGKeyCode> = [left, right, down, up]
}

enum Out {
    static let src = CGEventSource(stateID: .hidSystemState)

    static func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func mouse(_ type: CGEventType, at p: CGPoint, button: CGMouseButton = .left,
                      clicks: Int64 = 1, delta: CGPoint = .zero) {
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: clicks)
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y.rounded()))
        e.post(tap: .cghidEventTap)
    }

    static func scroll(dx: Int32, dy: Int32) {
        guard dx != 0 || dy != 0,
              let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                              wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags = [], down: Bool) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
        var f = flags
        if Key.arrows.contains(code) { f.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        e.flags = f
        e.post(tap: .cghidEventTap)
    }

    /// 媒体键（音量、播放等）走 NSSystemDefined 事件，普通 keycode 无效
    static func media(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let ev = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int((key << 16) | (state << 8)), data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func openApp(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
