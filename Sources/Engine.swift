// 核心引擎：每秒 120 次读取手柄状态，按配置翻译成鼠标 / 键盘事件。

import Cocoa
import GameController

struct Snap {
    var lx: Float = 0, ly: Float = 0, rx: Float = 0, ry: Float = 0, lt: Float = 0, rt: Float = 0
    var pressed: Set<Btn> = []
    subscript(b: Btn) -> Bool { pressed.contains(b) }
}

func read(_ g: GCExtendedGamepad, layout: Layout) -> Snap {
    var s = Snap()
    s.lx = g.leftThumbstick.xAxis.value;  s.ly = g.leftThumbstick.yAxis.value
    s.rx = g.rightThumbstick.xAxis.value; s.ry = g.rightThumbstick.yAxis.value
    s.lt = g.leftTrigger.value; s.rt = g.rightTrigger.value
    // GameController 的 A/B/X/Y 按“位置”定义：A=下 B=右 X=左 Y=上（Xbox 印字）
    // 任天堂印字（8BitDo SN30 等）：X=上 Y=左 A=右 B=下
    let face: [(Btn, GCControllerButtonInput?)] = layout == .xbox
        ? [(.A, g.buttonA), (.B, g.buttonB), (.X, g.buttonX), (.Y, g.buttonY)]
        : [(.A, g.buttonB), (.B, g.buttonA), (.X, g.buttonY), (.Y, g.buttonX)]
    let rest: [(Btn, GCControllerButtonInput?)] = [
        (.LB, g.leftShoulder), (.RB, g.rightShoulder),
        (.L3, g.leftThumbstickButton), (.R3, g.rightThumbstickButton),
        (.Up, g.dpad.up), (.Down, g.dpad.down), (.Left, g.dpad.left), (.Right, g.dpad.right),
        (.Start, g.buttonMenu), (.Select, g.buttonOptions), (.Home, g.buttonHome),
    ]
    for (b, input) in face + rest where input?.isPressed == true { s.pressed.insert(b) }
    if s.lt > 0.3 { s.pressed.insert(.LT) }
    if s.rt > 0.3 { s.pressed.insert(.RT) }
    return s
}

@MainActor
final class Engine {
    let store: ConfigStore
    var onStateChange: (() -> Void)?
    private var cfg: Compiled { store.compiled }

    private(set) var enabled = true { didSet { onStateChange?() } }
    private(set) var controllerName: String?
    var modeLabel: String? { activeMode?.label }

    private var pad: GCExtendedGamepad?
    private var prev = Snap()
    private var last = CACurrentMediaTime()
    private var lastConfigCheck: CFTimeInterval = 0

    private var moveRemainder: [CGPoint] = [.zero, .zero]   // 左 / 右摇杆各一份
    private var scrollRemainder: [CGPoint] = [.zero, .zero]

    /// 按下时解析出的动作，松开时执行同一个（中途切换模式也不会错乱）
    private var held: [Btn: Action] = [:]
    private var repeatAt: [Btn: CFTimeInterval] = [:]

    // 单击 / 双击 / 拖动
    private var leftHeld = false
    private var lastClickAt: CFTimeInterval = 0
    private var lastClickPos = CGPoint.zero
    private var clickCount: Int64 = 1

    // 模式（双指 / 三指 / 四指 …）
    private var modeStack: [(btn: Btn, name: String)] = []
    private var activeMode: Mode? { modeStack.last.flatMap { cfg.modes[$0.name] } }
    private var modeDownAt: CFTimeInterval = 0
    private var modeUsed = false
    private var flickArmed = true
    private var cmdHeld = false   // 应用切换器期间保持 ⌘

    // Start / Select：松开时才触发，留给“同时长按 = 暂停”
    private var comboDownAt: CFTimeInterval = 0
    private var comboUsed = false

    init(store: ConfigStore) {
        self.store = store
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pickController() }
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pickController() }
        }
        pickController()

        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    func toggle() {
        releaseAll()
        enabled.toggle()
        log("enabled = \(enabled)")
    }

    private func pickController() {
        let c = GCController.controllers().first { $0.extendedGamepad != nil }
        if pad !== c?.extendedGamepad { releaseAll() }
        pad = c?.extendedGamepad
        // 让 Home 键归我们用，不弹系统游戏面板
        pad?.buttonHome?.preferredSystemGestureState = .disabled
        controllerName = c.map { $0.vendorName ?? "手柄" }
        log("controller: \(controllerName ?? "none")")
        onStateChange?()
    }

    func releaseAll() {
        for (_, a) in held { up(a) }
        held.removeAll()
        repeatAt.removeAll()
        if leftHeld { Out.mouse(.leftMouseUp, at: Out.cursor(), clicks: clickCount); leftHeld = false }
        releaseCmd()
        modeStack.removeAll()
        onStateChange?()
    }

    // MARK: 主循环

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.05)
        last = now

        if now - lastConfigCheck > 1 {
            lastConfigCheck = now
            if store.reloadIfChanged() { releaseAll() }
        }

        guard let pad else { prev = Snap(); return }
        let s = read(pad, layout: cfg.layout)
        defer { prev = s }
        if debug { logRaw(s) }

        // 兜底开关：Select+Start 同时长按 0.8 秒（防止配置写错后无法暂停）
        if s[.Start] && s[.Select] {
            if comboDownAt == 0 { comboDownAt = now }
            if !comboUsed && now - comboDownAt > 0.8 { comboUsed = true; toggle() }
        }

        for b in Btn.allCases {
            let rising = s[b] && !prev[b], falling = !s[b] && prev[b]
            if b == .Start || b == .Select {
                // 两个都松开后，才判断是否当作单键使用
                if falling && !s[.Start] && !s[.Select] {
                    if !comboUsed && enabled { tapButton(b, now: now) }
                    comboUsed = false
                    comboDownAt = 0
                }
                continue
            }
            if !enabled {
                if rising && cfg.buttons[b]?.action == .toggle { toggle() }
                continue
            }
            if rising { press(b, now: now) }
            if falling { release(b, now: now) }
        }
        guard enabled else { return }

        repeatHeld(now: now)

        // 摇杆
        let leftUse = activeMode?.stick ?? cfg.leftStick
        if activeMode != nil && magnitude(s.lx, s.ly) > 0 { modeUsed = true }
        useStick(leftUse, s.lx, s.ly, index: 0, dt: dt, s: s)
        useStick(cfg.rightStick, s.rx, s.ry, index: 1, dt: dt, s: s)
    }

    // MARK: 按键

    private func binding(for b: Btn) -> Bound? {
        activeMode?.buttons[b] ?? cfg.buttons[b]
    }

    private func press(_ b: Btn, now: CFTimeInterval) {
        guard let bound = binding(for: b) else { return }
        held[b] = bound.action
        if bound.repeats { repeatAt[b] = now + 0.35 }
        if case .mode(let name) = bound.action {
            modeStack.append((b, name))
            modeDownAt = now
            modeUsed = false
            flickArmed = false   // 摇杆先回中才能甩
            moveRemainder = [.zero, .zero]
            onStateChange?()
            return
        }
        if activeMode != nil { modeUsed = true }
        down(bound.action)
    }

    private func release(_ b: Btn, now: CFTimeInterval) {
        repeatAt[b] = nil
        guard let a = held.removeValue(forKey: b) else { return }
        guard case .mode = a else { up(a); return }

        let wasTop = modeStack.last?.btn == b
        let mode = activeMode
        modeStack.removeAll { $0.btn == b }
        if wasTop {
            if let mode, !modeUsed, now - modeDownAt < 0.3, let tap = mode.tap { fire(tap) }
            releaseCmd()
            modeUsed = true   // 露出来的下层模式不再触发轻点
        }
        onStateChange?()
    }

    /// Start / Select 松开时触发一次完整按键
    private func tapButton(_ b: Btn, now: CFTimeInterval) {
        guard let bound = binding(for: b) else { return }
        if case .mode = bound.action { return }
        fire(bound.action)
    }

    private func repeatHeld(now: CFTimeInterval) {
        for (b, t) in repeatAt where now >= t {
            switch held[b] {
            case .key(let code, let flags)?: Out.key(code, flags, down: true); repeatAt[b] = now + 0.05
            case .media(let k)?: Out.media(k); repeatAt[b] = now + 0.12
            default: repeatAt[b] = nil
            }
        }
    }

    // MARK: 动作

    private func down(_ a: Action) {
        switch a {
        case .leftClick:
            let p = Out.cursor()
            let now = CACurrentMediaTime()
            let close = hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < 6
            clickCount = (now - lastClickAt < NSEvent.doubleClickInterval && close) ? min(clickCount + 1, 3) : 1
            lastClickAt = now
            lastClickPos = p
            Out.mouse(.leftMouseDown, at: p, clicks: clickCount)
            leftHeld = true
        case .rightClick: Out.mouse(.rightMouseDown, at: Out.cursor(), button: .right)
        case .middleClick: Out.mouse(.otherMouseDown, at: Out.cursor(), button: .center)
        case .key(let code, let flags): Out.key(code, flags, down: true)
        case .media(let k): Out.media(k)
        case .app(let path): Out.openApp(path)
        case .toggle: toggle()
        case .appSwitchNext, .appSwitchPrev:
            if !cmdHeld { Out.key(Key.cmd, .maskCommand, down: true); cmdHeld = true }
            Out.key(Key.tab, a == .appSwitchNext ? .maskCommand : [.maskCommand, .maskShift], down: true)
            Out.key(Key.tab, .maskCommand, down: false)
        case .none, .precision, .turbo, .mode: break
        }
    }

    private func up(_ a: Action) {
        switch a {
        case .leftClick:
            if leftHeld { Out.mouse(.leftMouseUp, at: Out.cursor(), clicks: clickCount); leftHeld = false }
        case .rightClick: Out.mouse(.rightMouseUp, at: Out.cursor(), button: .right)
        case .middleClick: Out.mouse(.otherMouseUp, at: Out.cursor(), button: .center)
        case .key(let code, let flags): Out.key(code, flags, down: false)
        case .appSwitchNext, .appSwitchPrev: releaseCmd()
        default: break
        }
    }

    /// 一次完整的按下 + 松开。应用切换器例外：⌘ 保持到模式键松开
    private func fire(_ a: Action) {
        down(a)
        if a != .appSwitchNext && a != .appSwitchPrev { up(a) }
    }

    private func releaseCmd() {
        if cmdHeld { Out.key(Key.cmd, [], down: false); cmdHeld = false }
    }

    // MARK: 摇杆

    private func useStick(_ use: StickUse, _ x: Float, _ y: Float, index: Int, dt: Double, s: Snap) {
        switch use {
        case .cursor: moveCursor(x, y, index: index, dt: dt, s: s)
        case .scroll: scroll(x, y, index: index, dt: dt)
        case .flick:
            if let dir = flick(x, y), let a = activeMode?.flick[dir] { fire(a) }
        case .none: break
        }
    }

    private func moveCursor(_ x: Float, _ y: Float, index: Int, dt: Double, s: Snap) {
        let (v, m) = curve(x, y)
        guard m > 0 else { moveRemainder[index] = .zero; return }
        var speed = cfg.cursorSpeed * m
        speed *= 1 - 0.75 * analog(.precision, s)
        speed *= 1 + 1.5 * analog(.turbo, s)
        // 摇杆 y 向上为正，屏幕 y 向下为正
        let rem = moveRemainder[index]
        let raw = CGPoint(x: v.x * speed * dt + rem.x, y: -v.y * speed * dt + rem.y)
        let d = CGPoint(x: raw.x.rounded(.towardZero), y: raw.y.rounded(.towardZero))
        moveRemainder[index] = CGPoint(x: raw.x - d.x, y: raw.y - d.y)
        guard d != .zero else { return }

        let old = Out.cursor()
        let p = clampToScreens(CGPoint(x: old.x + d.x, y: old.y + d.y), from: old)
        Out.mouse(leftHeld ? .leftMouseDragged : .mouseMoved, at: p, clicks: clickCount, delta: d)
    }

    private func scroll(_ x: Float, _ y: Float, index: Int, dt: Double) {
        let (v, m) = curve(x, y)
        guard m > 0 else { return }
        let speed = cfg.scrollSpeed * m * dt * (cfg.invertScroll ? -1 : 1)
        // 摇杆上推 = 看上面的内容；右推 = 看右边的内容
        let rem = scrollRemainder[index]
        let raw = CGPoint(x: -v.x * speed + rem.x, y: v.y * speed + rem.y)
        let d = CGPoint(x: raw.x.rounded(.towardZero), y: raw.y.rounded(.towardZero))
        scrollRemainder[index] = CGPoint(x: raw.x - d.x, y: raw.y - d.y)
        Out.scroll(dx: Int32(d.x), dy: Int32(d.y))
    }

    /// 精准 / 加速键的力度：扳机取模拟量，普通键按下即 1
    private func analog(_ a: Action, _ s: Snap) -> Double {
        var v: Float = 0
        for (b, bound) in cfg.buttons where bound.action == a {
            v = max(v, b == .LT ? s.lt : b == .RT ? s.rt : (s[b] ? 1 : 0))
        }
        return Double(v)
    }

    /// 摇杆“甩一下”：推过 0.75 触发一次，回到 0.35 以内才能再次触发
    private func flick(_ x: Float, _ y: Float) -> Dir? {
        let m = hypot(x, y)
        if m < 0.35 { flickArmed = true; return nil }
        guard flickArmed && m > 0.75 else { return nil }
        flickArmed = false
        return abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
    }

    // MARK: 工具

    private func magnitude(_ x: Float, _ y: Float) -> Double { curve(x, y).1 }

    /// 圆形死区 + 曲线：小幅推动更精细，推到底更快
    private func curve(_ x: Float, _ y: Float) -> (CGPoint, Double) {
        let dead = cfg.deadzone
        let m = min(Double(hypot(x, y)), 1)
        guard m > dead else { return (.zero, 0) }
        let n = (m - dead) / (1 - dead)
        return (CGPoint(x: Double(x) / m, y: Double(y) / m), pow(n, 2.2))
    }

    private func clampToScreens(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        let rects = ids.map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        guard let r = rects.first(where: { $0.contains(old) }) ?? rects.first else { return p }
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }

    private func logRaw(_ s: Snap) {
        for b in Btn.allCases where s[b] != prev[b] { log("[按键] \(b.rawValue) \(s[b] ? "按下" : "松开")") }
    }
}
