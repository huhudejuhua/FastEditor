import AppKit
import ApplicationServices

/// 抓取「当前焦点文本框」内容的核心模块。
///
/// 抓取策略（按优先级）：
///   0. 终端类 App（Terminal / iTerm / Warp ...）→ 直接跳过 → .skippedTerminal
///      （⌘A 会全选整个 buffer，抓回来的内容对编辑当前命令毫无意义）
///   1. AX 主路径（零侵入、最快）
///      ├─ kAXSelectedTextAttribute 非空且与 value 不同 → 用户选了一段 → .axSelection
///      ├─ kAXValueAttribute 非空                       → 完整内容       → .axValue
///   2. 剪贴板兜底（需要 Input Monitoring 权限）
///      ├─ ⌘C 探测：用户有选区就拿到选区 → .clipboardSelection
///      └─ ⌘A+⌘C：用户没选区就替他全选 → .clipboardSelectAll
///   3. 都失败 → .failed
///
/// `source` 字段非常重要：第 3 步整合时，回填逻辑要根据 source 决定
/// 「⌘V 替换选区」/「⌘A+⌘V 替换全部」/「直接 ⌘V 贴光标处」。
enum FocusReader {

    enum CaptureSource: String {
        case axSelection         = "ax/selectedText"
        case axValue             = "ax/value"
        case clipboardSelection  = "clipboard/selection (⌘C 探测)"
        case clipboardSelectAll  = "clipboard/selectAll (⌘A+⌘C 兜底)"
        case skippedTerminal     = "skipped/terminal (终端类 App 不抓)"
        case failed              = "failed"
    }

    /// 终端类 App 白名单：整个 App 都是终端 → 直接跳过。
    /// 如果你常用的终端没在这里，看日志里 `Frontmost App: ... bundle=xxx` 加进来即可。
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",       // 系统 Terminal
        "com.googlecode.iterm2",    // iTerm2
        "dev.warp.Warp-Stable",     // Warp
        "co.zeit.hyper",            // Hyper
        "net.kovidgoyal.kitty",     // Kitty
        "org.alacritty",            // Alacritty
        "com.github.wez.wezterm",   // WezTerm
        "com.mitchellh.ghostty",    // Ghostty
        "org.tabby",                // Tabby
    ]

    /// 「可能内嵌终端」的宿主 App：bundle ID 跟代码编辑共用，必须看 AX 父链
    /// 才能判断焦点是不是在终端面板里。
    private static let hostsWithEmbeddedTerminal: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92cl3",  // Cursor
        "com.exafunction.windsurf",          // Windsurf
    ]

    /// 父链中任一节点的 desc/title/identifier 含这些词 → 视为终端上下文。
    /// VS Code 中文 UI 是「终端」，英文是「Terminal」，顺手把日韩繁也加上。
    private static let terminalContextKeywords = ["terminal", "终端", "終端", "ターミナル"]

    private static func isTerminalApp() -> Bool {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return terminalBundleIDs.contains(bid)
    }

    /// 完整的终端判定：App 级 + 内嵌级。内嵌级用 AX 父链关键词搜索实现。
    private static func isTerminalContext() -> Bool {
        if isTerminalApp() { return true }
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              hostsWithEmbeddedTerminal.contains(bid),
              let elem = focusedElement() else { return false }
        return parentChainContainsTerminalKeyword(elem)
    }

    /// 沿 kAXParentAttribute 往上爬最多 12 层，看 role description / description /
    /// title / identifier 任一字段是否包含终端关键词。
    /// 12 层是经验值：VS Code 终端到 AXApplication 的深度大约 6~10。
    private static func parentChainContainsTerminalKeyword(_ start: AXUIElement, maxDepth: Int = 12) -> Bool {
        let fields = [
            kAXRoleDescriptionAttribute as String,
            kAXDescriptionAttribute as String,
            kAXTitleAttribute as String,
            "AXIdentifier",
        ]
        var current: AXUIElement? = start
        var depth = 0
        while let cur = current, depth < maxDepth {
            for f in fields {
                if let s = (copyAttr(cur, f) as? String)?.lowercased() {
                    for kw in terminalContextKeywords where s.contains(kw.lowercased()) {
                        return true
                    }
                }
            }
            current = copyAttr(cur, kAXParentAttribute).map { $0 as! AXUIElement }
            depth += 1
        }
        return false
    }

    /// 给热键回调用：打印完整诊断日志，方便验证各 App 的兼容性。
    static func dumpFocusedText() {
        Log.info("──── ⌃⌘E 触发，开始抓取焦点文本 ────")

        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontDesc = frontApp.map { "\($0.localizedName ?? "?") (pid=\($0.processIdentifier), bundle=\($0.bundleIdentifier ?? "?"))" } ?? "<unknown>"
        Log.info("Frontmost App: \(frontDesc)")

        // App 级终端直接跳过：AX/兜底都没意义，提前结束
        if isTerminalApp() {
            Log.info("→ 识别为终端类 App，跳过抓取（上层应打开空编辑器，⌘V 贴在光标处）")
            Log.info("→ 决策结果：source = \(CaptureSource.skippedTerminal.rawValue)")
            Log.info("──────────────────────────────────────")
            return
        }

        // —— AX 探测，先打元信息 ——
        if let elem = focusedElement() {
            let role     = (copyAttr(elem, kAXRoleAttribute)            as? String) ?? "<none>"
            let subrole  = (copyAttr(elem, kAXSubroleAttribute)         as? String) ?? "<none>"
            let roleDesc = (copyAttr(elem, kAXRoleDescriptionAttribute) as? String) ?? "<none>"
            Log.info("Role: \(role) / Subrole: \(subrole) / Desc: \(roleDesc)")

            let selected = copyAttr(elem, kAXSelectedTextAttribute) as? String
            let value    = copyAttr(elem, kAXValueAttribute)        as? String
            Log.info("AX selected = \(describe(selected)) | AX value = \(describe(value))")

            // IDE 宿主里：父链命中终端关键词 → 内嵌终端，跳过抓取
            if let bid = frontApp?.bundleIdentifier,
               hostsWithEmbeddedTerminal.contains(bid),
               parentChainContainsTerminalKeyword(elem) {
                Log.info("→ 识别为 IDE 内嵌终端，跳过抓取")
                Log.info("→ 决策结果：source = \(CaptureSource.skippedTerminal.rawValue)")
                Log.info("──────────────────────────────────────")
                return
            }
        } else {
            Log.warn("AX: 拿不到 kAXFocusedUIElementAttribute（焦点在 Finder/桌面，或 App 没暴露 AX）")
        }

        // —— 走完整决策链 ——
        let (text, source) = readFocusedText()
        Log.info("→ 决策结果：source = \(source.rawValue)")
        if let text = text {
            Log.info("→ 抓到内容 (\(text.count) chars):")
            Log.dump(quote(text))
        } else {
            Log.warn("→ 三条路径都失败，没拿到内容")
        }
        Log.info("──────────────────────────────────────")
    }

    /// 第 3 步整合用的稳定接口：返回抓到的文本 + 来源标记。
    /// - text=nil 可能是 .skippedTerminal（主动跳过）或 .failed（尝试后失败）
    /// - source 告诉回填逻辑该用「⌘V 替换选区」/「⌘A+⌘V 替换全部」/「直接 ⌘V 贴光标处」
    static func readFocusedText() -> (text: String?, source: CaptureSource) {
        // ⓪ 终端类（App 级 + IDE 内嵌级）：⌘A 会全选整个 buffer，抓回来无意义，直接跳过
        if isTerminalContext() {
            return (nil, .skippedTerminal)
        }

        // ① AX 主路径
        if let elem = focusedElement() {
            let selected = (copyAttr(elem, kAXSelectedTextAttribute) as? String) ?? ""
            let value    = (copyAttr(elem, kAXValueAttribute)        as? String) ?? ""

            // 选区非空 且 与完整内容不同 → 用户选了一段
            if !selected.isEmpty && selected != value {
                return (selected, .axSelection)
            }
            // 完整内容非空 → 用 value
            // （此分支也覆盖了「选区 == 完整」这种 App 把无选区报成全选的情况，
            //   用 axValue 语义更准、回填时上层知道要 ⌘A+⌘V）
            if !value.isEmpty {
                return (value, .axValue)
            }
            // 只有选区有内容（极少见），也接受
            if !selected.isEmpty {
                return (selected, .axSelection)
            }
            // AX 元素存在但内容全空（典型：VS Code Monaco） → 落到 ②
        }

        // ② 剪贴板兜底
        switch ClipboardCapture.capture() {
        case .selection(let t):  return (t, .clipboardSelection)
        case .selectAll(let t):  return (t, .clipboardSelectAll)
        case .failed:            return (nil, .failed)
        }
    }

    // MARK: - helpers

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let focused = copyAttr(system, kAXFocusedUIElementAttribute) else { return nil }
        return (focused as! AXUIElement)
    }

    /// AXUIElementCopyAttributeValue 的 Swift 友好封装。
    /// 最后一个参数是 UnsafeMutablePointer<CFTypeRef?>，需要 var result: CFTypeRef? 再传 &result。
    private static func copyAttr(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
        var result: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &result)
        return err == .success ? result : nil
    }

    private static func describe(_ s: String?) -> String {
        guard let s = s else { return "nil" }
        if s.isEmpty { return "\"\" (empty)" }
        return "\"\(s.prefix(40))\"\(s.count > 40 ? "…" : "") (\(s.count) chars)"
    }

    private static func quote(_ s: String) -> String {
        let max = 500
        let body = s.count > max ? String(s.prefix(max)) + "…(truncated, total \(s.count) chars)" : s
        let indented = body.split(separator: "\n", omittingEmptySubsequences: false).map { "    │ \($0)" }.joined(separator: "\n")
        return "    ┌──────\n\(indented)\n    └──────"
    }
}
