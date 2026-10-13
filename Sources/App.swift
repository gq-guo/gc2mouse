// 菜单栏界面

import Cocoa

let debug = ProcessInfo.processInfo.environment["GC2MOUSE_DEBUG"] == "1"
func log(_ s: String) { if debug { print(s); fflush(stdout) } }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    var engine: Engine!
    var item: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        engine = Engine(store: store)
        engine.onStateChange = { [weak self] in self?.refreshTitle() }
        refreshTitle()

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            log("需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能")
        }
    }

    func refreshTitle() {
        guard let button = item.button else { return }
        let connected = engine.controllerName != nil
        button.image = connected ? StatusIcon.normal : StatusIcon.disconnected
        button.imagePosition = .imageLeft
        // 暂停或未连接时图标变灰
        button.appearsDisabled = !connected || !engine.enabled
        let label = engine.enabled ? engine.modeLabel.map { " " + $0 } ?? "" : ""
        button.title = label + (store.error == nil ? "" : " ⚠️")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let cfg = store.compiled
        menu.removeAllItems()
        menu.addItem(withTitle: engine.controllerName.map { "已连接：\($0)" } ?? "未检测到手柄", action: nil, keyEquivalent: "")
        if !AXIsProcessTrusted() {
            menu.addItem(add("⚠️ 未授权辅助功能（点此打开设置）", #selector(openAXSettings)))
        }
        if let err = store.error {
            menu.addItem(add("⚠️ 配置有误，仍在使用上一份配置", #selector(openConfig)))
            let e = NSMenuItem(title: "    " + err, action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
        }
        menu.addItem(.separator())

        menu.addItem(add(engine.enabled ? "暂停（Home / Select+Start 长按）" : "启用", #selector(toggle)))

        let speed = NSMenuItem(title: "光标速度", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, v) in [("慢", 900.0), ("中", 1600.0), ("快", 2600.0)] {
            let i = add(title, #selector(setSpeed(_:)))
            i.representedObject = v
            i.state = cfg.cursorSpeed == v ? .on : .off
            sub.addItem(i)
        }
        speed.submenu = sub
        menu.addItem(speed)

        let layout = NSMenuItem(title: "按键印字", action: nil, keyEquivalent: "")
        let lsub = NSMenu()
        for (l, t) in [(Layout.xbox, "Xbox（X 在左，Y 在上）"), (Layout.nintendo, "任天堂 / 8BitDo（X 在上，Y 在左）")] {
            let i = add(t, #selector(setLayout(_:)))
            i.representedObject = l.rawValue
            i.state = cfg.layout == l ? .on : .off
            lsub.addItem(i)
        }
        layout.submenu = lsub
        menu.addItem(layout)

        let inv = add("反转滚动方向", #selector(toggleInvert))
        inv.state = cfg.invertScroll ? .on : .off
        menu.addItem(inv)

        menu.addItem(.separator())
        menu.addItem(add("编辑按键配置…", #selector(openConfig)))
        menu.addItem(add("在访达中显示配置文件", #selector(revealConfig)))
        menu.addItem(add("恢复默认配置", #selector(resetConfig)))
        menu.addItem(add("当前按键映射…", #selector(showHelp)))
        menu.addItem(.separator())
        menu.addItem(add("退出", #selector(quit)))
    }

    private func add(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func toggle() { engine.toggle() }
    @objc func setSpeed(_ i: NSMenuItem) { let v = i.representedObject as! Double; store.update { $0.cursorSpeed = v } }
    @objc func setLayout(_ i: NSMenuItem) { let v = i.representedObject as! String; store.update { $0.layout = v } }
    @objc func toggleInvert() { let v = !store.compiled.invertScroll; store.update { $0.invertScroll = v } }
    @objc func quit() { engine.releaseAll(); NSApp.terminate(nil) }
    @objc func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openConfig() {
        // 没有 .json 默认打开方式时，退回到访达里选中
        if !NSWorkspace.shared.open(store.url) { revealConfig() }
    }
    @objc func revealConfig() { NSWorkspace.shared.activateFileViewerSelecting([store.url]) }

    @objc func resetConfig() {
        let a = NSAlert()
        a.messageText = "恢复默认按键配置？"
        a.informativeText = "当前配置会备份为 config.json.bak。"
        a.addButton(withTitle: "恢复默认")
        a.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            store.resetToDefaults()
            engine.releaseAll()
        }
    }

    @objc func showHelp() {
        let raw = store.raw
        let d = Config.defaults
        let buttons = (d.buttons ?? [:]).merging(raw.buttons ?? [:]) { _, u in u }
        let modes = (d.modes ?? [:]).merging(raw.modes ?? [:]) { _, u in u }
        func fmt(_ b: Binding?) -> String { b.map { $0.action + ($0.repeat ? "（连发）" : "") } ?? "—" }

        var lines = ["左摇杆　\(raw.leftStick ?? d.leftStick!)　　右摇杆　\(raw.rightStick ?? d.rightStick!)", ""]
        for b in Btn.allCases { lines.append("\(b.rawValue)\t\(fmt(buttons[b.rawValue]))") }
        for (name, m) in modes.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            lines.append("【\(m.label ?? name)】\(name)　左摇杆：\(m.stick ?? "flick")")
            if m.tap != nil { lines.append("  轻点 → \(fmt(m.tap))") }
            for (t, b) in [("↑", m.up), ("↓", m.down), ("←", m.left), ("→", m.right)] where b != nil {
                lines.append("  \(t) → \(fmt(b))")
            }
            for (k, b) in (m.buttons ?? [:]).sorted(by: { $0.key < $1.key }) { lines.append("  \(k) → \(fmt(b))") }
        }

        let a = NSAlert()
        a.messageText = "当前按键映射"
        a.informativeText = lines.joined(separator: "\n") + "\n\n配置文件：\(store.url.path)"
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
