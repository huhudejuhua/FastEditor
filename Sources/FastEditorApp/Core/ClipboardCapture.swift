import AppKit
import Carbon.HIToolbox

/// 当 AX 拿不到焦点框内容时（VS Code Monaco / Qoder 这类不暴露文本的 App），
/// 退化到「让 App 自己把内容写到剪贴板」的兜底路径。
///
/// 两段式探测，尊重用户已选的范围：
///   ① 备份剪贴板 → 清空 → 发 ⌘C（不 ⌘A）
///      ├─ 剪贴板变了 → 用户原本就选了一段，拿到的就是选区
///      └─ 剪贴板没变 → 用户没选，进入 ②
///   ② 发 ⌘A 全选 → 发 ⌘C
///      └─ 剪贴板变了 → 拿到的是全部内容（标记 selectAll，回填时上层应再 ⌘A 一次）
///   ③ 恢复原剪贴板
///
/// 必须在主线程调用（Carbon 热键回调本来就在主线程）。
enum ClipboardCapture {

    enum Outcome {
        case selection(String)    // ⌘C 直接拿到 → 用户原本就选了
        case selectAll(String)    // ⌘A+⌘C 拿到 → 我们替用户全选了
        case failed               // 两段都失败
    }

    static func capture() -> Outcome {
        let pb = NSPasteboard.general
        let backup = backupPasteboard(pb)
        defer { restorePasteboard(pb, items: backup) }

        // —— ① ⌘C 探测选区 ——
        pb.clearContents()
        let baseline1 = pb.changeCount
        postKey(kVK_ANSI_C, modifiers: .maskCommand)
        if waitForClipboardChange(baseline: baseline1, timeout: 0.15),
           let text = pb.string(forType: .string), !text.isEmpty {
            return .selection(text)
        }

        // —— ② ⌘A 全选后 ⌘C ——
        pb.clearContents()
        let baseline2 = pb.changeCount
        postKey(kVK_ANSI_A, modifiers: .maskCommand)
        waitMS(30) // 给 App 响应 ⌘A 的时间
        postKey(kVK_ANSI_C, modifiers: .maskCommand)
        if waitForClipboardChange(baseline: baseline2, timeout: 0.2),
           let text = pb.string(forType: .string), !text.isEmpty {
            return .selectAll(text)
        }

        return .failed
    }

    // MARK: - 模拟按键

    private static func postKey(_ keyCode: Int, modifiers: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(keyCode)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = modifiers
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = modifiers
        // cghidEventTap：把事件注入到 HID 层，几乎所有 App 都能收到。
        let tap = CGEventTapLocation.cghidEventTap
        down?.post(tap: tap)
        up?.post(tap: tap)
    }

    // MARK: - 等待

    /// 轮询 changeCount，发现变化或超时返回。
    /// 用 RunLoop.run(until:) 让主线程仍能处理事件（CGEvent 反馈、剪贴板回写都靠它）。
    private static func waitForClipboardChange(baseline: Int, timeout: TimeInterval) -> Bool {
        let pb = NSPasteboard.general
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if pb.changeCount != baseline { return true }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        return pb.changeCount != baseline
    }

    private static func waitMS(_ ms: Int) {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: Double(ms) / 1000.0))
    }

    // MARK: - 剪贴板备份/恢复（搬自 BackfillDemo.PasteHelper）

    private struct PBItem {
        let data: [NSPasteboard.PasteboardType: Data]
    }

    private static func backupPasteboard(_ pb: NSPasteboard) -> [PBItem] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) { dict[type] = d }
            }
            return PBItem(data: dict)
        }
    }

    private static func restorePasteboard(_ pb: NSPasteboard, items: [PBItem]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { backup in
            let item = NSPasteboardItem()
            for (type, data) in backup.data {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(restored)
    }
}
