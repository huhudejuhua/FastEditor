import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

/// NSPanel 子类。`nonactivatingPanel` 默认不会成为 keyWindow，需显式 override。
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 历史浮窗的 AppKit 容器。
/// 参数照抄 EditorWindowDemo 的 `EditorPanelController`——那一套是 Step 3 验证出来的最稳 NSPanel 配置。
/// 区别：
///   - 不用单例（`.shared`），让 AppDelegate 持有实例并注入 ModelContainer；hotkey 闭包直接 capture 此实例。
///   - 没有 `EditorTextStore` / `onCommit` / `⌘Enter` 拦截——本 demo 不做编辑、不接 PasteHelper。
///   - 保留 `Esc → orderOut` 拦截，避免触发 windowWillClose 通知链、保持状态干净。
final class HistoryPanelController {
    private let modelContainer: ModelContainer
    private var panel: HistoryPanel?
    private var keyMonitor: Any?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        centerOnActiveScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        Log.info("history panel shown")
    }

    func hide() {
        guard let panel = panel, panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
        Log.info("history panel hidden")
    }

    func toggle() {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let panel = self.panel,
                  panel.isVisible,
                  NSApp.keyWindow === panel else {
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                Log.info("⎋ Esc → hide history panel")
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

    private func makePanel() -> HistoryPanel {
        // 尺寸 700×500 见 CLAUDE.md §2——列表+搜索+toolbar 才好看。
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        // 关键的桥：`.modelContainer(_:)` 把 container 灌进 SwiftUI 环境，
        // HistoryListView 内的 @Query / @Environment(\.modelContext) 才能拿到 context。
        // 类比 JPA：相当于在「没有 Spring App」的纯 AppKit 容器里手动把 EntityManager 注进一个孤立 Pane。
        let view = HistoryListView()
            .modelContainer(modelContainer)
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting

        return panel
    }

    private func centerOnActiveScreen(_ panel: HistoryPanel) {
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
