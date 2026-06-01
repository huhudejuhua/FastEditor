import AppKit
import Carbon.HIToolbox

/// Carbon 全局热键封装（抄自 demo，整合期改造为可注册多个热键）。
///
/// 产品热键：
///   - 主热键 ⌃⌘E：抓焦点文本 + 呼出/关闭编辑器
///   - 副热键 ⌃⌘H：呼出/关闭历史浮窗
/// 不用单 ⌃E：那是系统级「光标移到行尾」的 emacs 绑定，全局抢占会破坏文本框里的行尾跳转。
///
/// 一个进程可注册多个热键：事件 handler 只全局装一次（避免回调被多个 handler 重复触发），
/// 每个 HotKeyManager 实例分配唯一 id，回调按 id 在静态映射里查。
/// keyCode/modifiers 由调用方传入，现在来自 `HotKeySettings`（用户可配置）；
/// 改键后 AppDelegate.reregisterHotKeys() 调 unregister() 注销旧的再注册新的。
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var id: UInt32 = 0

    // 静态映射 id -> 回调，避免在 C 回调里捕获 self。
    private static var handlersByID: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x46454454 // 'FEDT' = FastEditor

    // 事件 handler 全局只装一次。
    private static var sharedHandlerRef: EventHandlerRef?

    /// 注册一个全局热键。返回是否成功。
    /// - keyCode: Carbon 虚拟键码（如 kVK_ANSI_E）
    /// - modifiers: Carbon 修饰键（如 controlKey | cmdKey）
    @discardableResult
    func register(keyCode: Int,
                  modifiers: UInt32,
                  handler: @escaping () -> Void) -> Bool {
        Self.installSharedHandlerOnce()

        let id = Self.nextID
        Self.nextID += 1
        self.id = id
        Self.handlersByID[id] = handler

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let regStatus = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            Log.error("RegisterEventHotKey failed: \(regStatus)")
            Self.handlersByID[id] = nil
            return false
        }
        return true
    }

    /// 安装分发用的事件 handler——只装一次。
    private static func installSharedHandlerOnce() {
        guard sharedHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, _) -> OSStatus in
                guard let eventRef = eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if err == noErr, let cb = HotKeyManager.handlersByID[hkID.id] {
                    cb()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &sharedHandlerRef
        )
        if status != noErr {
            Log.error("InstallEventHandler failed: \(status)")
        }
    }

    /// 注销本热键（重配置时先注销旧的再注册新的）。可重复调用、幂等。
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if id != 0 {
            Self.handlersByID[id] = nil
            id = 0
        }
    }

    deinit {
        unregister()
    }
}
