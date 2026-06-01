import SwiftUI
import AppKit

@main
struct FastEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var loginItem = LoginItemManager.shared
    @StateObject private var hotKeys = HotKeySettings.shared

    var body: some Scene {
        // 菜单项不挂 .keyboardShortcut：全局热键已由 Carbon 处理，标签里只显示提示文案，
        // 避免与全局热键双重绑定。文案从 HotKeySettings 取，用户改键后菜单同步刷新。
        MenuBarExtra("FastEditor", systemImage: "square.and.pencil") {
            Button("打开编辑器  \(hotKeys.editor.displayString)") { EditingFlow.shared.toggle() }
            Button("历史记录  \(hotKeys.history.displayString)") { AppDelegate.shared?.toggleHistory() }
            Divider()
            // 可勾选的开机自启开关（Toggle 在菜单里渲染成带 ✓ 的菜单项）。
            // 每次菜单打开 onAppear 刷一次，反映用户在系统设置里的手动改动。
            Toggle("开机自动启动", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .onAppear { loginItem.refresh() }
            Button("快捷键设置…") { SettingsWindowController.shared.show() }
            Button("权限设置…") { OnboardingWindowController.shared.show() }
            Divider()
            Button("退出 FastEditor") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
