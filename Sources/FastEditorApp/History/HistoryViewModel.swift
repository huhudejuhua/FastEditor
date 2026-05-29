import Foundation
import SwiftData

/// 历史浮窗的「桥」对象（类比 Editor 那边的 EditorTextStore）：
/// 同时被 SwiftUI 视图（渲染 + 高亮选中行）和 AppKit 键盘监听器（↑↓ 选择 / ⌫ 删除 / ⏎ 取条目）
/// 读写，所以把「数据 + 搜索过滤 + 选中下标」收进同一个 ObservableObject，做单一数据源。
///
/// 为什么不用 @Query：@Query 的结果只活在 SwiftUI 视图里，HistoryPanelController 的
/// AppKit keyMonitor 够不到那份数组、拿不到「当前选中的是哪条」。改成自己持 ModelContext
/// 主动 fetch——show 时、搜索变化时、删除后各刷一次。面板是临时浮窗，不需要 @Query 的实时性。
///
/// 用容器自建的 ModelContext（同 HistoryStore 的写入 context 不是同一个，但都连同一个 store）：
/// save() 落盘后，本 context 的 fetch 会读到——所以每次 show 刷新就能看到新留档的条目。
final class HistoryViewModel: ObservableObject {
    private let context: ModelContext

    /// 搜索词。视图里 TextField 双向绑定它；变化时视图调 refresh()。
    @Published var search: String = ""
    /// 当前过滤+排序后的列表（按 createdAt 倒序）。AppKit 监听器按 selectedIndex 索引它。
    @Published private(set) var entries: [HistoryEntry] = []
    /// 选中行下标。↑↓ 改它，视图据此高亮 + 滚动。
    @Published var selectedIndex: Int = 0

    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
    }

    /// 当前选中的条目（越界则 nil）。
    var selectedEntry: HistoryEntry? {
        guard entries.indices.contains(selectedIndex) else { return nil }
        return entries[selectedIndex]
    }

    /// 重新 fetch + 应用搜索过滤。每次 show / 搜索变化 / 删除后调。
    func refresh() {
        let descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        if search.isEmpty {
            entries = all
        } else {
            entries = all.filter { $0.text.localizedCaseInsensitiveContains(search) }
        }
        clampSelection()
    }

    /// ↑↓ 移动选中（边界夹紧，不循环）。
    func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), entries.count - 1)
    }

    /// 鼠标点选某行。
    func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// 删除当前选中条目，落盘后刷新。
    func deleteSelected() {
        guard let entry = selectedEntry else { return }
        let preview = entry.text.prefix(40)
        context.delete(entry)
        do {
            try context.save()
            Log.info("history delete \"\(preview)\" → saved")
        } catch {
            Log.error("history delete failed: \(error)")
        }
        refresh()
    }

    private func clampSelection() {
        if entries.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(selectedIndex, 0), entries.count - 1)
        }
    }
}
