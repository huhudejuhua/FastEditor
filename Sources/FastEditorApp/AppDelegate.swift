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

        // 接好核心链路协调器：⌘Enter 提交 → 回填。
        EditingFlow.shared.install()

        // 注册主热键 ⌃⌘E → 抓焦点文本 + 呼出/关闭编辑器（链路入口）。
        let manager = HotKeyManager()
        if manager.register(handler: { EditingFlow.shared.toggle() }) {
            self.hotKeyManager = manager
            Log.info("hotkey ⌃⌘E registered → EditingFlow.toggle")
        } else {
            Log.error("⌃⌘E 注册失败（可能被占用）。")
        }
    }
}
