import SwiftUI
import AppKit

@main
struct FastEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var loginItem = LoginItemManager.shared

    var body: some Scene {
        // 菜单项不挂 .keyboardShortcut：⌃⌘E / ⌃⌘H 已由 Carbon 全局热键处理，
        // 标签里只显示提示文案，避免与全局热键双重绑定。
        MenuBarExtra("FastEditor", systemImage: "square.and.pencil") {
            Button("打开编辑器  ⌃⌘E") { EditingFlow.shared.toggle() }
            Button("历史记录  ⌃⌘H") { AppDelegate.shared?.toggleHistory() }
            Divider()
            // 可勾选的开机自启开关（Toggle 在菜单里渲染成带 ✓ 的菜单项）。
            // 每次菜单打开 onAppear 刷一次，反映用户在系统设置里的手动改动。
            Toggle("开机自动启动", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .onAppear { loginItem.refresh() }
            Button("权限设置…") { OnboardingWindowController.shared.show() }
            Divider()
            Button("退出 FastEditor") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
