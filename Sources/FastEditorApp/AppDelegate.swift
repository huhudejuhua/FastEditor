import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 后续往这里挂：hotKeyManager / 各 controller / 首启权限闸门
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.banner()
        Log.info("FastEditor launched. Bundle = \(Bundle.main.bundleIdentifier ?? "<nil>")")
        Log.info("LSUIElement=true → 无 Dock 图标；MenuBarExtra → 状态栏有图标。")
    }
}
