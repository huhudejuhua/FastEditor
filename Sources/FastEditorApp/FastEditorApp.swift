import SwiftUI
import AppKit

@main
struct FastEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 第1步先只放退出；后续补「打开编辑器 / 历史 / 设置」。
        MenuBarExtra("FastEditor", systemImage: "square.and.pencil") {
            Text("FastEditor")
            Divider()
            Button("退出 FastEditor") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        // 第6步接历史时，可在这里挂： .modelContainer(sharedContainer)
        // 或单独用 Window/Settings scene 承载历史列表 + 设置页。
    }
}
