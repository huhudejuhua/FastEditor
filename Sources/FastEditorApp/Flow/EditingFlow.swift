import AppKit

/// 核心链路协调器（CLAUDE.md §3.A）：
///   主热键 → 抓焦点文本(记 source) → 编辑器预填 → ⌘Enter
///         → 收起编辑器 → 焦点回到原 App → 按 source 回填
///
/// onCommit 只回传 text，所以抓取时记下的 source 由本协调器持有，提交时取用。
final class EditingFlow {
    static let shared = EditingFlow()

    private var lastSource: FocusReader.CaptureSource = .failed
    private var lastSourceApp: String?

    /// 历史浮窗控制器（AppDelegate 持有，这里弱引用以便协调 hide / show）。
    weak var historyController: HistoryPanelController?

    private init() {}

    /// 启动时调一次：把编辑器的 ⌘Enter 提交回调接到本协调器。
    func install() {
        EditorPanelController.shared.onCommit = { [weak self] text in
            self?.commit(text)
        }
        Log.info("EditingFlow installed (onCommit 已接 PasteHelper)")
    }

    /// 主热键动作：编辑器已开则关；否则抓焦点文本、记住 source、带进编辑器预填。
    func toggle() {
        let editor = EditorPanelController.shared
        if editor.isVisible {
            editor.hide()
            return
        }
        // 抓取必须在 show 之前：此刻原 App 仍是前台，FocusReader 读的是它的焦点框。
        lastSourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let (text, source) = FocusReader.readFocusedText()
        lastSource = source
        Log.info("抓取结果：source=\(source.rawValue), app=\(lastSourceApp ?? "?"), 内容=\(text?.count ?? 0)字")
        editor.show(initialText: text, source: source.rawValue)
    }

    /// ⌘Enter 提交：先收起编辑器让焦点回到原 App，再按 source 回填。
    private func commit(_ text: String) {
        let source = lastSource
        Log.info("commit → hide 编辑器，准备按 source=\(source.rawValue) 回填 (\(text.count)字)")
        EditorPanelController.shared.hide()
        // hide(orderOut) 后，原 App 的焦点框重新成为系统焦点。
        // PasteHelper 内部 0.05s 延时既等剪贴板写好、也给焦点回归留结算时间。
        PasteHelper.paste(text, source: source)
        // 回填成功即留档（空文本 HistoryStore 内部跳过）。
        HistoryStore.shared.save(text: text, sourceApp: lastSourceApp)
    }

    // MARK: - 历史面板协调（⌃⌘H）
    //
    // 统一两种呼出场景（CLAUDE.md 用户需求 §2）：
    //   场景 A：编辑器没开时直接 ⌃⌘H —— 此刻原 App 的焦点框是前台，捕获它作为「最终输入框」目标。
    //   场景 B：⌃⌘E 开了编辑器后再 ⌃⌘H —— 目标域已由 ⌃⌘E 捕获，复用即可（不能重捕，否则会抓到自己的编辑器）。
    // 之后历史面板里的 ⏎/⌘⏎ 都基于这同一个 lastSource/lastSourceApp 工作，两场景逻辑一致。

    /// ⌃⌘H：开/关历史面板。开之前按场景捕获（或复用）目标输入框上下文。
    func toggleHistory() {
        guard let history = historyController else {
            Log.error("historyController 未设置，⌃⌘H 无效")
            return
        }
        if history.isVisible {
            history.hide()
            return
        }
        if EditorPanelController.shared.isVisible {
            // 场景 B：复用 ⌃⌘E 捕获的目标域。
            Log.info("⌃⌘H(编辑器开) 复用 ⌃⌘E 目标域 source=\(lastSource.rawValue) app=\(lastSourceApp ?? "?")")
        } else {
            // 场景 A：编辑器没开，现在抓当前焦点框作为目标域（text 丢弃，只要 source/app）。
            lastSourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
            let (_, source) = FocusReader.readFocusedText()
            lastSource = source
            Log.info("⌃⌘H(编辑器关) 捕获目标域 source=\(source.rawValue) app=\(lastSourceApp ?? "?")")
        }
        history.show()
    }

    /// 历史面板按 ⏎：把这条历史送进编辑器。
    ///   - 编辑器没开 → 新开并预填（source 用刚捕获的目标域，将来 ⌃Enter 回填到原框）。
    ///   - 编辑器已开且为空 → 直接覆盖。
    ///   - 编辑器已开且有内容 → 置前 + 弹 sheet 确认（异步），「覆盖」才载入、「取消」保留原内容。
    func useHistoryInEditor(text: String) {
        let editor = EditorPanelController.shared
        guard editor.isVisible else {
            historyController?.hide()
            editor.show(initialText: text, source: lastSource.rawValue)
            return
        }
        // 编辑器已开：先收起历史面板，让编辑器成为最前。
        historyController?.hide()
        guard !editor.currentText.isEmpty else {
            editor.loadText(text)
            return
        }
        // 有内容 → 置前后弹 sheet 确认（不激活 App，保住原 App 活动态 → ⌃Enter 仍能回填）。
        editor.bringToFront()
        editor.confirmOverwrite { ok in
            if ok {
                editor.loadText(text)
            } else {
                Log.info("用户取消覆盖，保留编辑器原内容")
            }
        }
    }

    /// 历史面板按 ⌘⏎：把这条历史直接贴回最终输入框，跳过编辑器。
    /// 先收起历史面板（必要时连编辑器一起收），让焦点回落到原 App，再按 source 回填。
    func pasteHistoryToField(text: String) {
        let source = lastSource
        historyController?.hide()
        if EditorPanelController.shared.isVisible {
            // 场景 B：编辑器还开着，它在历史面板下面挡着焦点回归路径 → 一并收起。
            EditorPanelController.shared.hide()
        }
        Log.info("历史直贴：收起面板，按 source=\(source.rawValue) 贴回原框 (\(text.count)字)")
        PasteHelper.paste(text, source: source)
    }
}
