import SwiftUI

/// 编辑窗口的 SwiftUI 内容。
/// - TextEditor 绑到外部 store.text，AppKit 层可读可写。
/// - @FocusState 自动获焦。
/// - Esc / ⌘Enter 不在 SwiftUI 层处理——由 EditorPanelController
///   通过 NSEvent.addLocalMonitorForEvents 在 AppKit 层拦截（更稳）。
struct EditorView: View {
    @ObservedObject var store: EditorTextStore
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $store.text)
            .font(.system(size: 14))
            .focused($focused)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .padding(8)
            .onAppear {
                // 给一拍 layout 时间再请求焦点；
                // 没这个延迟，在 NSHostingView 第一次挂载时 focused = true 偶发不生效。
                DispatchQueue.main.async {
                    focused = true
                }
            }
    }
}
