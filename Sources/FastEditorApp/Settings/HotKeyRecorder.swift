import AppKit
import Carbon.HIToolbox
import Combine

/// 哪个热键槽位在录制。
enum HotKeySlot {
    case editor, history
}

/// 热键录制器（ObservableObject 桥）：点一下进入录制 → 用本地事件监听抓下一个按键组合。
///
/// 为什么用 `addLocalMonitorForEvents`：设置窗是本 App 的 key window，本地监听能在
/// SwiftUI 之前截获 keyDown 并 `return nil` 吞掉它（不让窗口里别的控件响应）。
/// 比起包一个 NSView 抢 firstResponder，这条更轻、生命周期好管。
///
/// 只做「键盘层」校验（至少一个 ⌘/⌃/⌥；Esc 取消）；与另一槽位是否冲突、注册是否成功
/// 这类「语义层」校验交给 SettingsView 在 `onCapture` 里做。
@MainActor
final class HotKeyRecorder: ObservableObject {
    /// 当前正在录制的槽位；nil = 没在录制。
    @Published private(set) var recording: HotKeySlot?
    /// 录制中的即时提示（如「请至少含一个修饰键」）。
    @Published var hint: String?

    /// 抓到一个合法组合时回调（槽位 + 配置）。由 SettingsView 装上做后续处理。
    var onCapture: ((HotKeySlot, HotKeyConfig) -> Void)?

    private var monitor: Any?

    func start(_ slot: HotKeySlot) {
        // 切换到另一槽位前先收掉旧监听。
        stop()
        recording = slot
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
            return nil // 录制期间吞掉所有 keyDown，避免触发窗口里别的响应
        }
    }

    func stop() {
        recording = nil
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard let slot = recording else { return }

        // Esc 取消录制，保留原值。
        if Int(event.keyCode) == kVK_Escape {
            stop()
            return
        }

        let mods = HotKeySymbols.carbonModifiers(from: event.modifierFlags)
        let cfg = HotKeyConfig(keyCode: Int(event.keyCode), carbonModifiers: mods)

        // 纯字母 / 纯 ⇧ 做全局热键会抢占正常输入 → 不接受，停在录制态等用户重按。
        guard cfg.hasRequiredModifier else {
            hint = "请至少含一个 ⌘ / ⌃ / ⌥ 修饰键"
            return
        }

        onCapture?(slot, cfg)
        stop()
    }
}
