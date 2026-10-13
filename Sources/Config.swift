// 配置文件：~/.config/GamepadMouse/config.json
// 用户只需写想改的部分，其余沿用默认值。

import Foundation
import CoreGraphics

// MARK: - 文件格式

/// 按键绑定：字符串 "key:cmd+c"，或对象 {"action": "key:up", "repeat": true}
struct Binding: Codable, Equatable {
    var action: String
    var `repeat` = false

    init(_ action: String, repeat r: Bool = false) { self.action = action; self.repeat = r }

    private enum CodingKeys: String, CodingKey { case action, `repeat` }

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) { action = s; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(String.self, forKey: .action)
        self.repeat = try c.decodeIfPresent(Bool.self, forKey: .repeat) ?? false
    }

    func encode(to encoder: Encoder) throws {
        if !self.repeat {
            var c = encoder.singleValueContainer()
            try c.encode(action)
        } else {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(action, forKey: .action)
            try c.encode(true, forKey: .repeat)
        }
    }
}

struct ModeConfig: Codable {
    var label: String?
    var stick: String?          // 左摇杆用途：scroll / flick / cursor / none
    var tap: Binding?           // 轻点模式键（没动摇杆、不到 0.3 秒）
    var up: Binding?, down: Binding?, left: Binding?, right: Binding?   // stick=flick 时甩摇杆
    var buttons: [String: Binding]?   // 按键层：按住模式键时覆盖这些按键
}

struct Config: Codable {
    var layout: String?
    var cursorSpeed: Double?
    var scrollSpeed: Double?
    var deadzone: Double?
    var invertScroll: Bool?
    var leftStick: String?
    var rightStick: String?
    var buttons: [String: Binding]?
    var modes: [String: ModeConfig]?

    static var defaults: Config {
        let appsPath = FileManager.default.fileExists(atPath: "/System/Applications/Apps.app")
            ? "/System/Applications/Apps.app" : "/System/Applications/Launchpad.app"
        return Config(
            layout: "xbox", cursorSpeed: 1600, scrollSpeed: 2200, deadzone: 0.15, invertScroll: false,
            leftStick: "cursor", rightStick: "scroll",
            buttons: [
                "X": Binding("leftClick"),
                "Y": Binding("mode:twoFinger"),
                "A": Binding("mode:threeFinger"),
                "B": Binding("mode:fourFinger"),
                "LB": Binding("key:cmd+["),
                "RB": Binding("rightClick"),
                "LT": Binding("precision"),
                "RT": Binding("turbo"),
                "L3": Binding("key:cmd+space"),
                "R3": Binding("middleClick"),
                "Up": Binding("key:up", repeat: true),
                "Down": Binding("key:down", repeat: true),
                "Left": Binding("key:left", repeat: true),
                "Right": Binding("key:right", repeat: true),
                "Start": Binding("key:return"),
                "Select": Binding("key:escape"),
                "Home": Binding("toggle"),
            ],
            modes: [
                "twoFinger": ModeConfig(
                    label: "2指", stick: "scroll", tap: Binding("rightClick"),
                    buttons: [
                        "Up": Binding("media:volumeUp", repeat: true),
                        "Down": Binding("media:volumeDown", repeat: true),
                        "Left": Binding("media:previous"),
                        "Right": Binding("media:next"),
                    ]),
                "threeFinger": ModeConfig(
                    label: "3指", stick: "flick", tap: Binding("key:ctrl+cmd+d"),
                    up: Binding("app:/System/Applications/Mission Control.app"),
                    down: Binding("key:ctrl+down"),
                    left: Binding("key:ctrl+left"), right: Binding("key:ctrl+right")),
                "fourFinger": ModeConfig(
                    label: "4指", stick: "flick",
                    up: Binding("key:f11"), down: Binding("app:\(appsPath)"),
                    left: Binding("appSwitchPrev"), right: Binding("appSwitchNext")),
            ])
    }
}

// MARK: - 解析后的配置

enum Btn: String, CaseIterable {
    case A, B, X, Y, LB, RB, LT, RT, L3, R3, Up, Down, Left, Right, Start, Select, Home
}

enum Layout: String { case xbox, nintendo }
enum StickUse: String { case cursor, scroll, flick, none }

enum Action: Equatable {
    case none, leftClick, rightClick, middleClick, precision, turbo, toggle
    case appSwitchNext, appSwitchPrev
    case mode(String)
    case key(CGKeyCode, CGEventFlags)
    case media(Int32)
    case app(String)
}

struct Bound: Equatable { var action: Action; var repeats: Bool }

struct Mode {
    var name: String
    var label: String
    var stick: StickUse
    var tap: Action?
    var flick: [Dir: Action]
    var buttons: [Btn: Bound]
}

enum Dir { case up, down, left, right }

struct Compiled {
    var layout: Layout
    var cursorSpeed: Double, scrollSpeed: Double, deadzone: Double
    var invertScroll: Bool
    var leftStick: StickUse, rightStick: StickUse
    var buttons: [Btn: Bound]
    var modes: [String: Mode]
}

struct ConfigError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func fail(_ s: String) -> ConfigError { ConfigError(message: s) }

extension Config {
    /// 合并默认值并校验，任何不合法的值都报错，不会带着错误配置运行
    func compile() throws -> Compiled {
        let d = Config.defaults
        guard let layout = Layout(rawValue: layout ?? d.layout!) else { throw fail("layout 只能是 xbox 或 nintendo") }
        let cursor = cursorSpeed ?? d.cursorSpeed!, scroll = scrollSpeed ?? d.scrollSpeed!, dz = deadzone ?? d.deadzone!
        guard (100...10000).contains(cursor) else { throw fail("cursorSpeed 需在 100–10000 之间") }
        guard (100...10000).contains(scroll) else { throw fail("scrollSpeed 需在 100–10000 之间") }
        guard (0...0.9).contains(dz) else { throw fail("deadzone 需在 0–0.9 之间") }

        func stick(_ s: String, _ field: String) throws -> StickUse {
            guard let u = StickUse(rawValue: s), u != .flick else { throw fail("\(field) 只能是 cursor / scroll / none") }
            return u
        }
        let ls = try stick(leftStick ?? d.leftStick!, "leftStick")
        let rs = try stick(rightStick ?? d.rightStick!, "rightStick")

        // 同名模式整体替换默认模式
        let rawModes = (d.modes ?? [:]).merging(modes ?? [:]) { _, user in user }
        let modeNames = Set(rawModes.keys)

        func bound(_ b: Binding, _ ctx: String, inMode: Bool) throws -> Bound {
            do {
                return Bound(action: try parseAction(b.action, modes: modeNames, inMode: inMode), repeats: b.repeat)
            } catch let e as ConfigError {
                throw fail("\(ctx)：\(e.message)")
            }
        }
        func buttonMap(_ m: [String: Binding], _ ctx: String, inMode: Bool) throws -> [Btn: Bound] {
            var out: [Btn: Bound] = [:]
            for (k, v) in m {
                guard let b = Btn(rawValue: k) else {
                    throw fail("\(ctx) 里的按键名 \"\(k)\" 不认识，可用：\(Btn.allCases.map(\.rawValue).joined(separator: " "))")
                }
                out[b] = try bound(v, "\(ctx).\(k)", inMode: inMode)
            }
            return out
        }

        let buttons = try buttonMap((d.buttons ?? [:]).merging(buttons ?? [:]) { _, user in user }, "buttons", inMode: false)

        var compiledModes: [String: Mode] = [:]
        for (name, m) in rawModes {
            let ctx = "modes.\(name)"
            guard let st = StickUse(rawValue: m.stick ?? "flick") else { throw fail("\(ctx).stick 只能是 scroll / flick / cursor / none") }
            var flick: [Dir: Action] = [:]
            for (dir, b) in [(Dir.up, m.up), (.down, m.down), (.left, m.left), (.right, m.right)] {
                if let b { flick[dir] = try bound(b, "\(ctx) 方向", inMode: true).action }
            }
            compiledModes[name] = Mode(
                name: name, label: m.label ?? name, stick: st,
                tap: try m.tap.map { try bound($0, "\(ctx).tap", inMode: true).action },
                flick: flick,
                buttons: try buttonMap(m.buttons ?? [:], "\(ctx).buttons", inMode: true))
        }

        return Compiled(layout: layout, cursorSpeed: cursor, scrollSpeed: scroll, deadzone: dz,
                        invertScroll: invertScroll ?? false, leftStick: ls, rightStick: rs,
                        buttons: buttons, modes: compiledModes)
    }
}

// MARK: - 动作字符串解析

private let simpleActions: [String: Action] = [
    "none": .none, "leftclick": .leftClick, "rightclick": .rightClick, "middleclick": .middleClick,
    "precision": .precision, "turbo": .turbo, "toggle": .toggle,
    "appswitchnext": .appSwitchNext, "appswitchprev": .appSwitchPrev,
]

private let mediaKeys: [String: Int32] = [
    "volumeup": 0, "volumedown": 1, "brightnessup": 2, "brightnessdown": 3, "mute": 7,
    "playpause": 16, "next": 17, "previous": 18,
]

private let modifierNames: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand,
    "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
    "alt": .maskAlternate, "option": .maskAlternate, "opt": .maskAlternate, "⌥": .maskAlternate,
    "shift": .maskShift, "⇧": .maskShift,
    "fn": .maskSecondaryFn,
]

let keyCodes: [String: CGKeyCode] = {
    var m: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
        "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "backspace": 0x33,
        "escape": 0x35, "esc": 0x35, "forwarddelete": 0x75, "home": 0x73, "end": 0x77,
        "pageup": 0x74, "pagedown": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
    let fkeys: [CGKeyCode] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
                              0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]
    for (i, c) in fkeys.enumerated() { m["f\(i + 1)"] = c }
    return m
}()

func parseAction(_ raw: String, modes: Set<String>, inMode: Bool) throws -> Action {
    let s = raw.trimmingCharacters(in: .whitespaces)
    guard let colon = s.firstIndex(of: ":") else {
        guard let a = simpleActions[s.lowercased()] else { throw fail("不认识的动作 \"\(s)\"") }
        if inMode && (a == .precision || a == .turbo) { throw fail("precision / turbo 只能绑在基础按键上") }
        return a
    }
    let kind = s[..<colon].lowercased()
    let arg = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    switch kind {
    case "mode":
        if inMode { throw fail("模式里不能再切换到别的模式") }
        guard modes.contains(arg) else { throw fail("模式 \"\(arg)\" 未在 modes 中定义") }
        return .mode(arg)
    case "key":
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        for part in arg.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let f = modifierNames[part] { flags.insert(f) }
            else if code == nil, let c = keyCodes[part] { code = c }
            else { throw fail("\"\(raw)\" 里的 \"\(part)\" 不是有效按键") }
        }
        guard let code else { throw fail("\"\(raw)\" 缺少主键，例如 key:cmd+c") }
        return .key(code, flags)
    case "media":
        guard let k = mediaKeys[arg.lowercased()] else {
            throw fail("媒体键 \"\(arg)\" 不认识，可用：volumeUp volumeDown mute playPause next previous brightnessUp brightnessDown")
        }
        return .media(k)
    case "app":
        let path = (arg as NSString).standardizingPath
        guard path.hasPrefix("/"), path.hasSuffix(".app") else { throw fail("app: 需要 .app 的绝对路径") }
        guard FileManager.default.fileExists(atPath: path) else { throw fail("找不到应用 \(path)") }
        return .app(path)
    default:
        throw fail("不认识的动作类型 \"\(kind):\"")
    }
}

// MARK: - 读写与热重载

@MainActor
final class ConfigStore {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/GamepadMouse/config.json")
    private(set) var raw = Config.defaults
    private(set) var compiled: Compiled = try! Config.defaults.compile()
    private(set) var error: String?
    private var mtime: Date?

    init() {
        if !FileManager.default.fileExists(atPath: url.path) { try? write(Config.defaults) }
        load()
    }

    /// 读取失败时保留上一份可用配置，错误显示在菜单里
    func load() {
        mtime = modDate()
        do {
            var text = try String(contentsOf: url, encoding: .utf8)
            // 文本编辑器可能自动替换成弯引号，先改回来
            for (a, b) in [("“", "\""), ("”", "\""), ("‘", "'"), ("’", "'")] { text = text.replacingOccurrences(of: a, with: b) }
            let cfg = try JSONDecoder().decode(Config.self, from: Data(text.utf8))
            compiled = try cfg.compile()
            raw = cfg
            error = nil
            log("配置已加载")
        } catch let e as DecodingError {
            error = "JSON 格式错误：\(describe(e))"
        } catch {
            self.error = error.localizedDescription
        }
        if let error { log("配置错误：\(error)") }
    }

    /// 文件有改动就重新加载，返回是否重新加载过
    func reloadIfChanged() -> Bool {
        guard modDate() != mtime else { return false }
        load()
        return true
    }

    /// 菜单里的快捷设置：改动后写回文件
    func update(_ change: (inout Config) -> Void) {
        var c = raw
        change(&c)
        guard (try? c.compile()) != nil else { return }
        try? write(c)
        load()
    }

    func resetToDefaults() {
        let bak = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)
        try? write(Config.defaults)
        load()
    }

    private func write(_ c: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(c).write(to: url, options: .atomic)
    }

    private func modDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func describe(_ e: DecodingError) -> String {
        switch e {
        case .dataCorrupted(let c): return (c.underlyingError as NSError?)?.userInfo["NSDebugDescription"] as? String ?? c.debugDescription
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c):
            return "\(c.codingPath.map(\.stringValue).joined(separator: "."))：\(c.debugDescription)"
        @unknown default: return "\(e)"
        }
    }
}
