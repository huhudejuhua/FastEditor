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
    private let viewModel: HistoryViewModel
    private var panel: HistoryPanel?
    private var keyMonitor: Any?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.viewModel = HistoryViewModel(modelContainer: modelContainer)
    }

    // MARK: - Public

    /// 面板当前是否可见。EditingFlow 用它做 toggle 判断 + 决定是否捕获目标域。
    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // 每次呼出都从最新数据 + 第一条选中开始（条目可能被 ⌃⌘E 留档刷新过）。
        viewModel.selectedIndex = 0
        viewModel.refresh()

        centerOnActiveScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        Log.info("history panel shown (entries=\(viewModel.entries.count))")
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
            // 用 panel.isKeyWindow 而不是 NSApp.keyWindow === panel：
            // ⌃⌘H 是全局热键，按下时前台还是原 App，nonactivatingPanel 让面板成 key 但不激活
            // 本 App → NSApp.keyWindow 此刻为 nil，会导致方向键被放行给 ScrollView 滚动。
            // panel.isKeyWindow 是窗口自身属性，nonactivating 也准。
            guard let self = self,
                  let panel = self.panel,
                  panel.isVisible,
                  panel.isKeyWindow else {
                return event
            }
            return self.handleKey(event)
        }
    }

    /// 历史面板键位分发。返回 nil = 吞掉事件（不让搜索框等再处理）；返回 event = 放行。
    /// 设计：↑↓/⏎/⌘⏎ 全局拦截（即使焦点在搜索框，方向键在单行框里也没用途）；
    /// ⌫ 仅在搜索框为空时当「删除条目」，搜索框有内容时放行让它退格编辑文本——
    /// 这样「边搜边删字」和「删条目」不打架（CLAUDE.md：先验证，卡了再调）。
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let vm = viewModel
        switch Int(event.keyCode) {
        case kVK_Escape:
            Log.info("⎋ Esc → hide history panel")
            hide()
            return nil

        case kVK_UpArrow:
            vm.moveSelection(-1)
            return nil

        case kVK_DownArrow:
            vm.moveSelection(1)
            return nil

        case kVK_Delete: // Mac「delete」键（退格）
            if vm.search.isEmpty {
                vm.deleteSelected()
                return nil
            }
            return event // 搜索框非空 → 放行，退格编辑搜索文本

        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let entry = vm.selectedEntry else { return nil }
            let text = entry.text
            if event.modifierFlags.contains(.control) {
                // ⌃⏎ → 直接把这条贴回最终输入框（跳过编辑器）。与编辑器提交键一致。
                Log.info("history ⌃⏎ → 贴回原框 (\(text.count)字)")
                EditingFlow.shared.pasteHistoryToField(text: text)
            } else {
                // ⏎ → 把这条送进编辑器（已开则覆盖，有内容先确认）。
                Log.info("history ⏎ → 进编辑器 (\(text.count)字)")
                EditingFlow.shared.useHistoryInEditor(text: text)
            }
            return nil

        default:
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

        // 视图的数据/选中全部走注入的 viewModel（单一数据源），不再用 @Query / 环境 context。
        // viewModel 自己持 ModelContext（同 container），所以这里不需要 .modelContainer 注入。
        let view = HistoryListView(viewModel: viewModel)
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
