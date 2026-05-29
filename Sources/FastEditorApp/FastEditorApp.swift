import SwiftUI
import AppKit

@main
struct FastEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单项不挂 .keyboardShortcut：⌃⌘E / ⌃⌘H 已由 Carbon 全局热键处理，
        // 标签里只显示提示文案，避免与全局热键双重绑定。
        MenuBarExtra("FastEditor", systemImage: "square.and.pencil") {
            Button("打开编辑器  ⌃⌘E") { EditingFlow.shared.toggle() }
            Button("历史记录  ⌃⌘H") { AppDelegate.shared?.toggleHistory() }
            Divider()
            Button("权限设置…") { OnboardingWindowController.shared.show() }
            Divider()
            Button("退出 FastEditor") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
