import AppKit
import Carbon.HIToolbox

/// Carbon 全局热键封装（抄自 demo）。
/// 产品主热键：⌃⌘E（Control + Command + E）。
/// 不用单 ⌃E：那是系统级「光标移到行尾」的 emacs 绑定，全局抢占会破坏文本框里的行尾跳转。
/// 加 Command 后不踩任何系统文本编辑键。keyCode 第一版硬编码；可配置是后期目标（CLAUDE.md §5）。
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    // 用静态映射把 hotKeyID -> 回调串起来，避免在 C 回调里捕获 self。
    private static var handlersByID: [UInt32: () -> Void] = [:]
    private static let signature: OSType = 0x46454454 // 'FEDT' = FastEditor

    /// 注册主热键 ⌃⌘E。返回是否成功。
    @discardableResult
    func register(handler: @escaping () -> Void) -> Bool {
        self.handler = handler

        let id: UInt32 = 1
        Self.handlersByID[id] = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, _) -> OSStatus in
                guard let eventRef = eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr, let cb = HotKeyManager.handlersByID[hkID.id] {
                    cb()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if installStatus != noErr {
            Log.error("InstallEventHandler failed: \(installStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let modifiers: UInt32 = UInt32(controlKey) | UInt32(cmdKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_E)

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            Log.error("RegisterEventHotKey failed: \(regStatus)")
            return false
        }
        return true
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}
