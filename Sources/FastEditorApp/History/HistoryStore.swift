import Foundation
import SwiftData

/// 历史留档的应用级单例（类比 JPA：≈ EntityManagerFactory + 一个写入用 Repository）。
///   - 持有 ModelContainer：HistoryPanelController 拿它注入 SwiftUI 环境给 @Query 用。
///   - 提供 save(text:sourceApp:)：EditingFlow 提交成功时写一条。
///
/// store 显式钉到 ~/Library/Application Support/com.fasteditor.app/default.store，
/// 不用 SwiftData 默认目录（会污染共享根目录、不便清理）。
final class HistoryStore {
    static let shared = HistoryStore()

    /// 可能为 nil：store 初始化失败时降级（save 变 no-op，历史浮窗不可用），不崩主流程。
    private(set) var container: ModelContainer?
    private var context: ModelContext?

    private init() {
        do {
            let schema = Schema([HistoryEntry.self])
            let url = try Self.storeURL()
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            self.container = container
            self.context = ModelContext(container)
            let count = (try? ModelContext(container).fetchCount(FetchDescriptor<HistoryEntry>())) ?? -1
            Log.info("HistoryStore ready. store=\(url.path) count=\(count)")
        } catch {
            Log.error("HistoryStore 初始化失败，历史功能降级：\(error)")
        }
    }

    /// 提交成功时写一条。空文本不写，避免污染历史。显式 save 到磁盘（不靠 autosave）。
    func save(text: String, sourceApp: String?) {
        guard !text.isEmpty else { return }
        guard let context = context else {
            Log.error("HistoryStore 未就绪，save 跳过")
            return
        }
        let entry = HistoryEntry(text: text, sourceApp: sourceApp)
        context.insert(entry)
        do {
            try context.save()
            Log.info("history saved: \(text.count)字 from \(sourceApp ?? "?")")
        } catch {
            Log.error("history save failed: \(error)")
        }
    }

    /// ~/Library/Application Support/com.fasteditor.app/default.store
    /// 提前 mkdir 父目录——SwiftData 不会替我们建，缺目录直接报错。
    private static func storeURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("com.fasteditor.app", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }
}
