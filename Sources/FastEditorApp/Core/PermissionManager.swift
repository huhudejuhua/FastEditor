import AppKit
import ApplicationServices

/// 两项权限的检测 / 请求 / deep-link 跳转。
///
/// 设计要点（CLAUDE.md §6）：
///   - 「检测」用静默 preflight（prompt: false），轮询专用，不弹系统对话框。
///   - 「请求 / deep-link」只在用户点「去授权」按钮时调，会弹框或跳系统设置。
///
/// 类比 Java/Android：检测 ≈ checkSelfPermission（只读状态），
/// 请求 ≈ requestPermissions（触发系统 UI）。但 macOS 授权后**不回调**，
/// 所以靠上层 Timer 反复调检测函数轮询（见 PermissionState）。
enum PermissionManager {

    // MARK: - 检测（静默，不弹框 —— 轮询专用）

    /// 辅助功能 (Accessibility)：prompt: false → 只检测、不弹「打开系统设置？」对话框。
    static func isAccessibilityGranted() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: false] as CFDictionary)
    }

    /// 输入监控 (Input Monitoring)：preflight 是「只检测」，不弹框。
    static func isInputMonitoringGranted() -> Bool {
        return CGPreflightListenEventAccess()
    }

    // MARK: - 去授权（点「去授权」按钮时才调）
    //
    // 两项的注册行为不同（实测）：
    //   - 辅助功能：启动时调 AXIsProcessTrustedWithOptions(preflight) 就会把 App
    //     注册进列表 → deep-link 跳过去用户能直接看到并勾选。
    //   - 输入监控：CGPreflightListenEventAccess(只检测) **不会**把 App 注册进列表！
    //     必须先调一次 CGRequestListenEventAccess(请求) 才会出现条目（首次还会弹框）。
    //     所以输入监控的「去授权」= 先 request 注册 + 再 deep-link 导航。

    /// 辅助功能「去授权」：App 已在列表里，直接 deep-link 跳过去。
    static func authorizeAccessibility() {
        openAccessibilitySettings()
    }

    /// 输入监控「去授权」：先 request 把 App 注册进列表（首次弹框），再 deep-link 跳过去。
    static func authorizeInputMonitoring() {
        let granted = CGRequestListenEventAccess()
        Log.info("CGRequestListenEventAccess → \(granted ? "granted" : "待勾选(已注册进输入监控列表)")")
        openInputMonitoringSettings()
    }

    // ⚠️ deep-link URL scheme 在不同 macOS 小版本上偶有变化（CLAUDE.md §6）。
    // 跳不到具体子面板时退化到「隐私与安全性」根页。

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
             label: "辅助功能")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
             label: "输入监控")
    }

    private static func open(_ urlString: String, label: String) {
        guard let url = URL(string: urlString) else { return }
        let ok = NSWorkspace.shared.open(url)
        if ok {
            Log.info("deep-link → \(label) 面板 (\(urlString))")
        } else {
            // 退化：跳「隐私与安全性」根页，让用户自己点进去。
            Log.warn("deep-link 跳 \(label) 失败，退化到隐私与安全性根页")
            if let root = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(root)
            }
        }
    }
}
