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
        // 已开 → 关；未开 → 先抓当前焦点框内容再带进编辑器预填。
        // 第5步把「抓→编辑→⌘Enter→回填+留档」整条链抽进 EditingFlow。
        let manager = HotKeyManager()
        if manager.register(handler: { Self.handleHotKey() }) {
            self.hotKeyManager = manager
            Log.info("hotkey ⌃⌘E registered → 抓取焦点文本 + 呼出编辑器")
        } else {
            Log.error("⌃⌘E 注册失败（可能被占用）。")
        }
    }

    /// 主热键动作：编辑器已开则关；否则抓当前焦点框文本，带进编辑器预填。
    private static func handleHotKey() {
        let editor = EditorPanelController.shared
        if editor.isVisible {
            editor.hide()
            return
        }
        // 抓取必须在 show 之前：此刻原 App 仍是前台，FocusReader 读的是它的焦点框。
        let (text, source) = FocusReader.readFocusedText()
        Log.info("抓取结果：source=\(source.rawValue), 内容=\(text?.count ?? 0)字")
        editor.show(initialText: text, source: source.rawValue)
    }
}
