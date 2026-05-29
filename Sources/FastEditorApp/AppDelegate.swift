import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // 注册主热键 ⌃⌘E → 呼出/关闭编辑器。
        // 第3步：开空编辑器；第4步起 readFocusedText 抓内容预填（见 EditingFlow）。
        let manager = HotKeyManager()
        if manager.register(handler: { EditorPanelController.shared.toggle() }) {
            self.hotKeyManager = manager
            Log.info("hotkey ⌃⌘E registered → toggle 编辑器")
        } else {
            Log.error("⌃⌘E 注册失败（可能被占用）。")
        }
    }
}
