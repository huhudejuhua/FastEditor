import AppKit
import Carbon.HIToolbox

/// 一个全局热键的配置：Carbon 虚拟键码 + Carbon 修饰键掩码。
///
/// Codable，以便整条存进 UserDefaults（类比 Java 里把对象序列化成 JSON 塞进 SharedPreferences）。
/// 只存「键码 + 修饰键」两个原始值，显示用的符号串（如「⌃⌘E」）由 `HotKeySymbols` 现算，
/// 不冗余存字符串，避免两份数据不一致。
struct HotKeyConfig: Codable, Equatable {
    /// Carbon / NSEvent 虚拟键码（如 kVK_ANSI_E = 14）。注意它跟键盘布局无关、是物理键位。
    var keyCode: Int
    /// Carbon 修饰键掩码：`controlKey | cmdKey` 等的位或。注意这是 Carbon 常量，不是 Cocoa 的 NSEvent.ModifierFlags。
    var carbonModifiers: UInt32

    /// 是否含至少一个「主修饰键」（⌘ / ⌃ / ⌥）。
    /// 纯字母 / 纯 ⇧ 组合做全局热键会抢占正常输入，录制时必须挡掉。
    var hasRequiredModifier: Bool {
        let required = UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
        return (carbonModifiers & required) != 0
    }

    /// 给 UI 显示的符号串，如「⌃⌘E」。
    var displayString: String {
        HotKeySymbols.modifierString(carbonModifiers) + HotKeySymbols.keyName(keyCode)
    }
}

/// 键码 / 修饰键 ↔ 显示符号 + Cocoa↔Carbon 修饰键转换的工具集。
enum HotKeySymbols {
    /// 把 Cocoa 的 `NSEvent.ModifierFlags`（录制时从键盘事件拿到）转成 Carbon 修饰键掩码（注册热键要用）。
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    /// 修饰键符号串，按 Apple 习惯顺序 ⌃⌥⇧⌘。
    static func modifierString(_ carbonModifiers: UInt32) -> String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    /// 键码 → 显示名。覆盖字母 / 数字 / 常用特殊键；查不到回退成「Key\(code)」。
    static func keyName(_ keyCode: Int) -> String {
        if let name = specialKeys[keyCode] { return name }
        if let letter = letters[keyCode] { return letter }
        return "Key\(keyCode)"
    }

    private static let letters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]
}
