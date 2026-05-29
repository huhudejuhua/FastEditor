import SwiftData
import SwiftUI

/// 历史浏览视图：搜索框 + 列表 + 底部快捷键提示。
///
/// 数据/选中全部来自注入的 HistoryViewModel（单一数据源）——视图只负责渲染 + 双向绑搜索框。
/// ↑↓ 选择 / ⏎ 进编辑器 / ⌘⏎ 贴回原框 / ⌫ 删除 这些键由 HistoryPanelController 的
/// AppKit keyMonitor 统一拦（在 nonactivatingPanel + 浮窗里，AppKit 监听比 SwiftUI .onKeyPress 稳）。
///
/// 列表不用 `List`：List 的行有自带选中样式，和我们自定义的高亮打架。改用 ScrollView + LazyVStack
/// 完全掌控行背景；ScrollViewReader 负责把选中行滚进可视区。
struct HistoryListView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listBody
            Divider()
            footerHints
        }
        .onAppear { viewModel.refresh() }
        .onChange(of: viewModel.search) { _, _ in
            viewModel.selectedIndex = 0
            viewModel.refresh()
        }
    }

    // MARK: - Header（标题 + 搜索框）

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("历史 (\(viewModel.entries.count))")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文本…", text: $viewModel.search)
                    .textFieldStyle(.plain)
                if !viewModel.search.isEmpty {
                    Button {
                        viewModel.search = ""
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
    }

    // MARK: - 列表

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 标识统一用 index 一套：ForEach 的 id 和 scrollTo 的 .id 必须一致，
                    // 否则两套 identity 打架会让 SwiftUI 漏刷某些行（旧选中行高亮卡死）。
                    ForEach(viewModel.entries.indices, id: \.self) { index in
                        row(viewModel.entries[index], index: index)
                            .id(index)
                    }
                }
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.createdAt.formatted(.dateTime.month().day().hour().minute()))
                    if let app = entry.sourceApp {
                        Text("· \(app)")
                    }
                }
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            Spacer()
            // 鼠标用户保留：常显删除按钮（键盘用户用 ⌫）。
            Button(role: .destructive) {
                viewModel.select(index)
                viewModel.deleteSelected()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(isSelected ? Color.white : Color.red)
            }
            .buttonStyle(.borderless)
            .help("删除此条")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.select(index)
        }
    }

    // MARK: - 底部快捷键提示

    private var footerHints: some View {
        HStack(spacing: 14) {
            hint("↑↓", "选择")
            hint("⏎", "进编辑器")
            hint("⌃⏎", "贴回原框")
            hint("⌫", "删除")
            Spacer()
            hint("esc", "关闭")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).fontWeight(.semibold)
            Text(label)
        }
    }
}
