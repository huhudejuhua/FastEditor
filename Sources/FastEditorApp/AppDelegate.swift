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

        let ctrlCmd = UInt32(controlKey) | UInt32(cmdKey)

        // 主热键 ⌃⌘E → 抓焦点文本 + 呼出/关闭编辑器（链路入口）。
        let editorKey = HotKeyManager()
        if editorKey.register(keyCode: kVK_ANSI_E, modifiers: ctrlCmd,
                              handler: { EditingFlow.shared.toggle() }) {
            self.editorHotKey = editorKey
            Log.info("hotkey ⌃⌘E registered → EditingFlow.toggle")
        } else {
            Log.error("⌃⌘E 注册失败（可能被占用）。")
        }

        // 副热键 ⌃⌘H → 呼出/关闭历史浮窗。容器未就绪则不注册。
        if let container = HistoryStore.shared.container {
            let controller = HistoryPanelController(modelContainer: container)
            self.historyController = controller
            let historyKey = HotKeyManager()
            if historyKey.register(keyCode: kVK_ANSI_H, modifiers: ctrlCmd,
                                   handler: { controller.toggle() }) {
                self.historyHotKey = historyKey
                Log.info("hotkey ⌃⌘H registered → 历史浮窗 toggle")
            } else {
                Log.error("⌃⌘H 注册失败（可能被占用）。")
            }
        }
    }

    /// 供 MenuBarExtra「历史记录」菜单项调用。
    func toggleHistory() {
        historyController?.toggle()
    }
}
