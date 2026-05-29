import SwiftUI

/// 容纳编辑文本的「桥」对象。
/// SwiftUI 的 @State 是 view 私有的、AppKit 层读不到，所以用一个 ObservableObject
/// 作为「容器持有 + SwiftUI 绑定」共享的中转。
///
/// 类比 Java：相当于一个 SimpleStringProperty 实例，
/// Controller (AppKit) 持有引用，View (SwiftUI) 绑到上面渲染——
/// 任一侧改 text，另一侧立刻看到。
final class EditorTextStore: ObservableObject {
    @Published var text: String = ""
}
