import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 让 MenuBarExtra 菜单项能调到 AppDelegate 持有的控制器（历史浮窗）。
    static private(set) weak var shared: AppDelegate?

    private var editorHotKey: HotKeyManager?
    private var historyHotKey: HotKeyManager?
    private var historyController: HistoryPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Log.banner()
        Log.info("FastEditor launched. Bundle = \(Bundle.main.bundleIdentifier ?? "<nil>")")

        // 首启权限闸门（静默 preflight，不弹系统框）。
        let ax = PermissionManager.isAccessibilityGranted()
        let im = PermissionManager.isInputMonitoringGranted()
        Log.info("初始权限检测：")
        Log.info("  辅助功能 / Accessibility:     \(ax ? "✅ granted" : "⚠️  NOT granted")")
        Log.info("  输入监控 / Input Monitoring:  \(im ? "✅ granted" : "⚠️  NOT granted")")

        // 任一项缺 → 自动弹引导窗；两项都有 → 不弹，仅 log ready。
        if ax && im {
            Log.info("all permissions granted, ready（不自动弹引导窗）")
        } else {
            Log.warn("缺权限 → 自动弹出引导窗口。")
            OnboardingWindowController.shared.show()
        }

        // 初始化历史留档容器（单例，提交成功时写一条）。
        _ = HistoryStore.shared

        // 接好核心链路协调器：⌃Enter 提交 → 回填 + 留档。
        EditingFlow.shared.install()

        // 历史面板控制器（副热键和菜单都用它）。容器就绪才建。
        if let container = HistoryStore.shared.container {
            let controller = HistoryPanelController(modelContainer: container)
            self.historyController = controller
            // 让 EditingFlow 能协调历史面板（⌃⌘H 捕获目标域 + ⏎/⌘⏎ 动作）。
            EditingFlow.shared.historyController = controller
        }

        // 按当前配置（默认 ⌃⌘E / ⌃⌘H，或用户在设置里改过的）注册两个全局热键。
        reregisterHotKeys()
    }

    /// 按 `HotKeySettings` 的当前值（重新）注册两个全局热键。
    /// 设置界面改完热键后调它即时生效：先注销旧的，再按新配置注册。
    /// 返回是否「全部尝试注册的热键都成功」——失败一般是组合被系统/别的 App 占用，供 UI 反馈。
    @discardableResult
    @MainActor
    func reregisterHotKeys() -> Bool {
        let settings = HotKeySettings.shared
        var allOK = true

        // 主热键 → 抓焦点文本 + 呼出/关闭编辑器（链路入口）。
        editorHotKey?.unregister()
        let editorKey = HotKeyManager()
        let eCfg = settings.editor
        if editorKey.register(keyCode: eCfg.keyCode, modifiers: eCfg.carbonModifiers,
                              handler: { EditingFlow.shared.toggle() }) {
            self.editorHotKey = editorKey
            Log.info("主热键已注册 \(eCfg.displayString) → EditingFlow.toggle")
        } else {
            self.editorHotKey = nil
            allOK = false
            Log.error("主热键 \(eCfg.displayString) 注册失败（可能被占用）。")
        }

        // 副热键 → 呼出/关闭历史浮窗。容器未就绪（无历史面板）则跳过。
        guard historyController != nil else { return allOK }
        historyHotKey?.unregister()
        let historyKey = HotKeyManager()
        let hCfg = settings.history
        if historyKey.register(keyCode: hCfg.keyCode, modifiers: hCfg.carbonModifiers,
                               handler: { EditingFlow.shared.toggleHistory() }) {
            self.historyHotKey = historyKey
            Log.info("副热键已注册 \(hCfg.displayString) → 历史浮窗 toggle")
        } else {
            self.historyHotKey = nil
            allOK = false
            Log.error("副热键 \(hCfg.displayString) 注册失败（可能被占用）。")
        }
        return allOK
    }

    /// 供 MenuBarExtra「历史记录」菜单项调用。走 EditingFlow 以统一两种呼出场景的目标域捕获。
    func toggleHistory() {
        EditingFlow.shared.toggleHistory()
    }
}
