// GamepadMouse — 把游戏手柄变成鼠标 / 触控板（菜单栏常驻）

import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
