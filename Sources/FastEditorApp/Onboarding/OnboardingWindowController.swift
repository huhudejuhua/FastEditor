import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 引导窗口的 AppKit 容器控制器。
///
/// 与 Step 3 的悬浮 NSPanel **不同**（CLAUDE.md §2 设计点）：引导页要让用户
/// 点按钮、读文字、与之交互，需要是普通可聚焦的 key window。所以用
/// `.titled` 的 NSWindow + NSHostingView，配 NSApp.activate 带到前台。
/// activationPolicy 仍是 .accessory（无 Dock 图标），.accessory 下也能成为 key window。
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    let state = PermissionState()
    private var window: NSWindow?
    private var keyMonitor: Any?

    private init() {}

    // MARK: - 重启生效（授权后某些情况需重启才生效，CLAUDE.md §6）

    /// 退出并重新启动同一个 .app。
    /// 典型场景：输入监控勾选后，运行中的进程 preflight 仍返回 false，要重启才认。
    static func relaunchApp() {
        Log.info("relaunch requested → 启动新实例后退出当前进程")
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                Log.error("relaunch failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Public

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        state.startPolling()                  // 显示期间每秒轮询，自动发现授权翻转
        centerOnActiveScreen(window)
        NSApp.activate(ignoringOtherApps: true) // .accessory 策略下也能把窗口带到前台
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        // keyWindow 的赋值在下一个 runloop tick 才结算，所以延后一拍再读才是真值。
        DispatchQueue.main.async {
            Log.info("onboarding window shown (key=\(NSApp.keyWindow === window), visible=\(window.isVisible))")
        }
    }

    func hide() {
        guard let window = window, window.isVisible else { return }
        removeKeyMonitor()
        state.stopPolling()
        // orderOut 而非 close()：保留窗口与状态，下次直接 makeKeyAndOrderFront。
        window.orderOut(nil)
        Log.info("onboarding window hidden")
    }

    func toggle() {
        if let w = window, w.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Key handling (Esc → hide)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  window.isVisible,
                  NSApp.keyWindow === window else {
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                Log.info("⎋ Esc → hide onboarding window")
                self.hide()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    // MARK: - Build

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(state: state)
        let hosting = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],   // 普通可聚焦窗口（非 borderless panel）
            backing: .buffered,
            defer: false
        )
        window.title = "FastEditor 权限设置"
        window.contentView = hosting
        // 关掉时只 orderOut，不释放对象 —— 下次 toggle 还能复用。
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        // 多显示器：窗口出现在鼠标当前所在屏幕。
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = window.frame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
