import SwiftUI

/// 权限状态的「桥」对象：AppKit 层（Timer）写，SwiftUI 层（@ObservedObject）读。
///
/// 类比 Java：相当于一个持有可观察状态的单例 ViewModel（@Component + 两个
/// observable property）。SwiftUI View 订阅它，@Published 一变就重渲。
///
/// 关键认知（CLAUDE.md §6）：用户在系统设置里勾选后 macOS **不回调** App，
/// 所以靠 Timer 每秒反复调 PermissionManager 的检测函数轮询，自己发现状态翻转。
/// ——类比 Android：没有 onRequestPermissionsResult 回调，只能反复 checkSelfPermission。
final class PermissionState: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false

    private var timer: Timer?

    var allGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    /// 开始每秒轮询。窗口显示时调；幂等（重复调不会起多个 Timer）。
    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        Log.info("permission polling started (每 1s)")
    }

    /// 停止轮询。窗口隐藏/完成时调，别让 Timer 永久空转。
    func stopPolling() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        Log.info("permission polling stopped")
    }

    /// 读一次两项状态（静默 preflight，不弹框）。仅在值变化时 log，避免每秒刷屏。
    func refresh() {
        let ax = PermissionManager.isAccessibilityGranted()
        let im = PermissionManager.isInputMonitoringGranted()

        if ax != accessibilityGranted {
            Log.info("轮询翻转：辅助功能 \(accessibilityGranted ? "✅" : "⚠️") → \(ax ? "✅ 已授权" : "⚠️ 待授权")")
            accessibilityGranted = ax
        }
        if im != inputMonitoringGranted {
            Log.info("轮询翻转：输入监控 \(inputMonitoringGranted ? "✅" : "⚠️") → \(im ? "✅ 已授权" : "⚠️ 待授权")")
            inputMonitoringGranted = im
        }
    }
}
