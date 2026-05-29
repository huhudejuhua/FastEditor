import AppKit
import Carbon.HIToolbox

/// 把编辑结果回填到原焦点框：剪贴板备份 → 写入 → 模拟按键 → 延时恢复。
///
/// 按 FocusReader 抓取时记录的 source 分情况回填（CLAUDE.md §3.B）：
///   - .axSelection / .clipboardSelection  用户选了一段 → 直接 ⌘V（替换选区）
///   - .axValue / .clipboardSelectAll      拿的是全文   → ⌘A 再 ⌘V（替换全部）
///   - .skippedTerminal / .failed          终端/没抓到  → 直接 ⌘V（贴光标处）
enum PasteHelper {

    // 回填进行中的标志位。整条流程都在主线程（Carbon 回调 + asyncAfter），无需加锁。
    private static var isBusy = false

    /// 主入口：按 source 决定是否先 ⌘A 全选，再走「备份→写入→⌘V→恢复」。
    static func paste(_ text: String, source: FocusReader.CaptureSource) {
        guard !isBusy else {
            Log.warn("回填忽略：上一次尚未结束（避免剪贴板被污染）")
            return
        }
        isBusy = true

        let selectAllFirst: Bool
        switch source {
        case .axValue, .clipboardSelectAll:
            selectAllFirst = true   // 抓的是全文 → 先全选再贴，替换全部
        case .axSelection, .clipboardSelection, .skippedTerminal, .failed:
            selectAllFirst = false  // 选区/终端/失败 → 直接贴（替换选区 或 贴光标处）
        }
        Log.info("回填开始 source=\(source.rawValue) selectAllFirst=\(selectAllFirst) (\(text.count)字)")

        let pb = NSPasteboard.general
        let backup = backup(pasteboard: pb)
        Log.info("  ① backed up clipboard (\(backup.count) item(s))")

        pb.clearContents()
        pb.setString(text, forType: .string)
        Log.info("  ② wrote text to clipboard")

        // 给系统时间把剪贴板写好，也给 hide 后的焦点回归留出结算时间。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if selectAllFirst {
                postCmd(kVK_ANSI_A)
                Log.info("  ③a posted ⌘A (替换全部)")
            }
            // ⌘A 后给 App 一点响应时间再 ⌘V；不需全选时立即贴。
            DispatchQueue.main.asyncAfter(deadline: .now() + (selectAllFirst ? 0.04 : 0)) {
                postCmd(kVK_ANSI_V)
                Log.info("  ③ posted ⌘V")

                // 等目标 App 完成粘贴再恢复剪贴板（0.3~0.5s 比较稳）。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    restore(pasteboard: pb, items: backup)
                    Log.info("  ④ restored original clipboard\n")
                    isBusy = false
                }
            }
        }
    }

    // MARK: - 模拟按键（⌘ + 指定键）

    private static func postCmd(_ keyCode: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(keyCode)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        // cghidEventTap：把事件注入到 HID 层，几乎所有 App 都能收到。
        let tap = CGEventTapLocation.cghidEventTap
        down?.post(tap: tap)
        up?.post(tap: tap)
    }

    // MARK: - 剪贴板备份 / 恢复

    private struct PBItem {
        let data: [NSPasteboard.PasteboardType: Data]
    }

    private static func backup(pasteboard pb: NSPasteboard) -> [PBItem] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) {
                    dict[type] = d
                }
            }
            return PBItem(data: dict)
        }
    }

    private static func restore(pasteboard pb: NSPasteboard, items: [PBItem]) {
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
