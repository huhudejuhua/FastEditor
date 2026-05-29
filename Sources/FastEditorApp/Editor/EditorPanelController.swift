import AppKit
import Carbon.HIToolbox
import SwiftUI

/// NSPanel 子类。
/// nonactivatingPanel 默认不会成为 keyWindow，需要显式 override 才能接键盘。
final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 编辑窗口的 AppKit 容器控制器。
/// 类比 Java：相当于一个持有 JDialog 的 Singleton Controller。
///
/// Public 接口按 CLAUDE.md §8 的「整合后形状」预留：
///   show(initialText:source:) / hide() / toggle() / onCommit
/// 当前 Step 阶段 initialText/source 还没接通，先占位；onCommit 在 Step 5 起被 ⌘Enter 触发。
final class EditorPanelController {
    static let shared = EditorPanelController()

    private var panel: EditorPanel?
    private let store = EditorTextStore()

    /// keyDown 监听器句柄。show 时装、hide 时卸——避免在窗口不可见时拦键。
    private var keyMonitor: Any?

    /// ⌘Enter 触发的「确认」回调。整合后会接 PasteHelper.paste(_:)。
    /// demo 阶段：未设置时，下方默认实现里只打 log。
    var onCommit: ((String) -> Void)?

    private init() {}

    // MARK: - Public

    /// 面板当前是否可见。热键处理用它区分「已开→关 / 未开→抓取并开」。
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(initialText: String? = nil, source: String? = nil) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // 用户选择：每次呼出都从空白开始。
        // initialText 当前 demo 阶段一直为 nil；整合后 FocusReader 抓到的文本会从这里灌入。
        store.text = initialText ?? ""

        centerOnActiveScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        Log.info("panel shown (initialText=\(initialText?.count ?? 0)字, source=\(source ?? "nil"))")
    }

    func hide() {
        guard let panel = panel, panel.isVisible else { return }
        removeKeyMonitor()
        // orderOut 而不是 close()：避免触发 windowWillClose 通知链，
        // 状态保留干净，下次 makeKeyAndOrderFront 直接显示。
        panel.orderOut(nil)
        Log.info("panel hidden")
    }

    func toggle() {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Key handling
    //
    // 设计选择（见 CLAUDE.md §6）：Esc / ⌘Enter 在 AppKit 层用 local monitor 拦，
    // 不走 SwiftUI 的 .onKeyPress——SwiftUI 在 nonactivatingPanel + TextEditor
    // 焦点路由下，键位钩子有时不触发。AppKit local monitor 更稳。

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let panel = self.panel,
                  panel.isVisible,
                  NSApp.keyWindow === panel else {
                return event
            }
            return self.handleKey(event)
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // Esc → 隐藏窗口
        if event.keyCode == UInt16(kVK_Escape) {
            Log.info("⎋ Esc → hide")
            hide()
            return nil
        }
        // ⌃Enter / ⌃NumpadEnter → 触发 commit
        let isReturn = event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
        if isReturn && event.modifierFlags.contains(.control) {
            let text = store.text
            Log.info("⌃↩ Enter → commit (\(text.count) chars): \"\(text.prefix(120))\"")
            if let handler = onCommit {
                handler(text)
            }
            return nil
        }
        return event
    }

    // MARK: - Build

    private func makePanel() -> EditorPanel {
        let panel = EditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        // 让窗口在所有 Space / 全屏辅助层都能跟随出现。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 避免 orderOut 后被自动 release（macOS Panel 默认会）。
        panel.isReleasedWhenClosed = false

        let view = EditorView(store: store)
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting

        return panel
    }

    private func centerOnActiveScreen(_ panel: EditorPanel) {
        // 选择鼠标所在屏幕；多显示器场景下窗口跟着用户当前注意力。
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = panel.frame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
