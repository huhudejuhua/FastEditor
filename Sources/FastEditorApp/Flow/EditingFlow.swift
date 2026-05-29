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
}
