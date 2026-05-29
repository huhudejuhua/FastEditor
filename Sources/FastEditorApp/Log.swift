import Foundation
import os

/// 用 os.Logger 而不是 print()。
/// 原因：当 .app 通过 LaunchServices (`open Foo.app`) 启动时，
/// stdout 不会被 unified logging 捕获，`log stream` 看不到 print() 输出。
/// 而 os.Logger 写入的内容能被 `log stream --predicate 'subsystem == "..."'` 抓到。
///
/// 同时也直接 print 一份到 stdout，方便「直接跑二进制」的调试模式。
enum Log {
    private static let logger = Logger(subsystem: "com.fasteditor.app", category: "app")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func ts() -> String { formatter.string(from: Date()) }

    static func info(_ msg: String) {
        print("[\(ts())] \(msg)")
        logger.info("\(msg, privacy: .public)")
    }

    static func warn(_ msg: String) {
        print("[\(ts())] ⚠️  \(msg)")
        logger.warning("⚠️  \(msg, privacy: .public)")
    }

    static func error(_ msg: String) {
        print("[\(ts())] ❌ \(msg)")
        logger.error("❌ \(msg, privacy: .public)")
    }

    /// 多行原文输出（如抓取到的文本内容）。
    static func dump(_ msg: String) {
        print(msg)
        logger.info("\(msg, privacy: .public)")
    }

    static func banner() {
        let text = """
        ────────────────────────────────────────────────────────────
        FastEditor · 整合工程
        全局热键 → 抓焦点文本 → 临时编辑器 → 回填 + 历史留档
        ────────────────────────────────────────────────────────────
        """
        print(text)
        logger.info("\(text, privacy: .public)")
    }
}
