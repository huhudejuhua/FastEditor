import Foundation
import ServiceManagement

/// 开机自动启动开关（可配置）。
///
/// 用 macOS 13+ 的 `SMAppService.mainApp`：把本 App 主 bundle 登记进 launchd，
/// 登录时由系统拉起。类比 Linux 的 systemd 用户级开机项 / Windows 注册表启动项——
/// 「登记」一次后系统记着，不需要常驻进程去维护。
///
/// 是 ObservableObject「桥」（类比 EditorTextStore）：菜单里的 Toggle 绑 `isEnabled`，
/// 切换走 `setEnabled`，状态变化推回 SwiftUI 刷新勾选。
@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    /// 当前是否已登记开机自启。供菜单 Toggle 显示勾选。
    @Published private(set) var isEnabled: Bool = false

    private init() {
        refresh()
    }

    /// 从系统读最新状态（外部可能在「系统设置 → 通用 → 登录项」里改过）。
    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// 开/关开机自启。失败只记日志、不崩（如 ad-hoc 签名或被用户在系统设置里拦下）。
    func setEnabled(_ enable: Bool) {
        do {
            let service = SMAppService.mainApp
            if enable {
                if service.status != .enabled { try service.register() }
                Log.info("开机自启已开启（status=\(service.status.rawValue)）")
            } else {
                if service.status == .enabled { try service.unregister() }
                Log.info("开机自启已关闭（status=\(service.status.rawValue)）")
            }
        } catch {
            Log.error("开机自启切换失败：\(error.localizedDescription)")
        }
        refresh()
    }
}
