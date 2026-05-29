import SwiftData
import SwiftUI

/// 历史浏览视图：搜索框 + 列表 + 逐条删除。
///
/// `@Query` 类比 JPA：≈ 声明式 `@NamedQuery` + 自动 refresh 的 binding——
/// SwiftData 监听 ModelContext 变更后自动重 fetch 并触发 SwiftUI 重渲。
///
/// `@Environment(\.modelContext)` 拿到的是 `.modelContainer(_:)` 注入的 viewContext。
/// 搜索不用 `.searchable`：无 NavigationStack 的纯 panel 形态下它渲染不可控，
/// 直接 TextField 最简、最贴合无标题栏浮窗。
struct HistoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HistoryEntry.createdAt, order: .reverse) private var entries: [HistoryEntry]
    @State private var search = ""

    /// 纯内存 filter。数据量大了再换 `@Query(filter: #Predicate)` 在 SQL 层过滤。
    private var filtered: [HistoryEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Text("历史 (\(filtered.count)/\(entries.count))")
                        .font(.headline)
                    Spacer()
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索文本…", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("清空")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List {
                ForEach(filtered) { entry in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.text).lineLimit(2)
                            HStack(spacing: 6) {
                                Text(entry.createdAt.formatted(.dateTime.month().day().hour().minute()))
                                if let app = entry.sourceApp {
                                    Text("· \(app)")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // macOS 上鼠标拖拽 ≠ swipe-to-delete，给一个常显按钮最稳。
                        Button(role: .destructive) {
                            deleteEntry(entry)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("删除此条")
                    }
                }
            }
        }
        .onAppear {
            Log.info("HistoryListView appeared. @Query 拿到 \(entries.count) 条 entries。")
        }
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        let preview = entry.text.prefix(40)
        context.delete(entry)
        do {
            try context.save()
            Log.info("delete \"\(preview)\" → saved (count = \(entries.count))")
        } catch {
            Log.error("delete failed: \(error)")
        }
    }
}
