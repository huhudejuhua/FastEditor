import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 设置窗口的 AppKit 容器控制器（照搬 OnboardingWindowController 的模式）。
///
/// 跟编辑器悬浮 NSPanel 不同：设置页要让用户点、读、交互（第 3 步还要录键），
/// 需是普通可聚焦的 key window，所以用 `.titled` NSWindow + NSHostingView + NSApp.activate。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var keyMonitor: Any?

    private init() {}

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        centerOnActiveScreen(window)
        NSApp.activate(ignoringOtherApps: true) // .accessory 策略下也能把窗口带到前台
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        Log.info("settings window shown")
    }

    func hide() {
        guard let window = window, window.isVisible else { return }
        removeKeyMonitor()
        window.orderOut(nil)
        Log.info("settings window hidden")
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
        let view = SettingsView(settings: HotKeySettings.shared)
        let hosting = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FastEditor 设置"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
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
