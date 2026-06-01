import Foundation
import Carbon.HIToolbox

/// 全局热键配置的持久化 + 单一数据源（ObservableObject「桥」，类比 LoginItemManager）。
///
/// 存哪：UserDefaults（类比 Android 的 SharedPreferences），两个热键各存一段 JSON。
/// 没存过 → 用默认值（= 整合期锁定的 ⌃⌘E / ⌃⌘H），保证升级上来的老用户行为不变。
///
/// 谁来重注册：本类只管「数据 + 存盘」，不碰 Carbon。改完由设置界面调
/// `AppDelegate.shared?.reregisterHotKeys()` 读这里的最新值去重注册——存储与注册解耦。
@MainActor
final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()

    /// 主热键（抓焦点 + 呼出编辑器）。默认 ⌃⌘E。
    @Published var editor: HotKeyConfig { didSet { persist(editor, key: Keys.editor) } }
    /// 副热键（呼出历史浮窗）。默认 ⌃⌘H。
    @Published var history: HotKeyConfig { didSet { persist(history, key: Keys.history) } }

    static let defaultEditor = HotKeyConfig(
        keyCode: kVK_ANSI_E,
        carbonModifiers: UInt32(controlKey) | UInt32(cmdKey))
    static let defaultHistory = HotKeyConfig(
        keyCode: kVK_ANSI_H,
        carbonModifiers: UInt32(controlKey) | UInt32(cmdKey))

    private enum Keys {
        static let editor = "hotkey.editor"
        static let history = "hotkey.history"
    }

    private init() {
        editor = Self.load(Keys.editor) ?? Self.defaultEditor
        history = Self.load(Keys.history) ?? Self.defaultHistory
    }

    /// 恢复出厂默认（设置界面「恢复默认」按钮用）。
    func resetToDefaults() {
        editor = Self.defaultEditor
        history = Self.defaultHistory
    }

    private func persist(_ config: HotKeyConfig, key: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load(_ key: String) -> HotKeyConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyConfig.self, from: data)
    }
}
