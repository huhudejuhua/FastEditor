import Foundation
import SwiftData

/// 历史留档条目——FastEditor 最终产品里「一次成功的回填」会写一条进来。
///
/// 字段按整合期形状定型（CLAUDE.md §2 / §8）：demo 阶段 sourceApp 永远 nil，
/// 整合时 FocusReader 抓到的来源 App 名字会写进来——schema 提前留好，避免后期 migration。
///
/// 类比 JPA：`@Model` ≈ `@Entity` + Lombok `@Data`，属性自动持久化、
/// 变更后 SwiftData 自动通知 `@Query` 重 fetch 并刷新视图。
@Model
final class HistoryEntry {
    var id: UUID
    var text: String
    var createdAt: Date
    var sourceApp: String?

    init(text: String, sourceApp: String? = nil) {
        self.id = UUID()
        self.text = text
        self.createdAt = .now
        self.sourceApp = sourceApp
    }
}
