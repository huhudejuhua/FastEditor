# CLAUDE.md — FastEditor / FastEditorApp（整合工程）

> **这是什么**：把上层目录里五个已验证的 demo（Backfill / FocusRead / EditorWindow / HistoryStore / Onboarding）合并成的完整产品。SPM 工程，`@main` SwiftUI App + MenuBarExtra + `NSApplicationDelegateAdaptor`，Bundle ID `com.fasteditor.app`。
>
> ✅ **实现状态（2026-05-30）**：核心产品功能完整可用并逐项验证通过——任意文本框 `⌃⌘E` 抓取 → 编辑 → `⌃Enter` 回填+留档 → `⌃⌘H` 检索/复用。源码在 `Sources/FastEditorApp/`，git 一步一 commit。**仅剩签名公证（§8）硬阻塞于 Apple 开发者账号**，ad-hoc 顶着。
>
> 本文档现在是**维护参考**（不是实现指南）：记录架构、关键决策、非显然的坑、稳定接口、协作风格。具体实现以源码为准。

---

## 1. 产品与来源

产品形态：在任意应用的文本框里按全局热键 → 弹出干净的临时编辑器（带进原有内容）→ 编辑完按热键 → 自动回填进原文本框 + 自动留档为可检索历史。**核心场景：给 AI agent 写长提示词。**

五个 demo 各验证了一个孤立技术风险，整合时各搬走核心件（详见上层 `项目交接文档_FastEditor.md` §6 / `PROGRESS.md`）：

| demo | 验证了什么 | 搬走的核心件 |
|---|---|---|
| BackfillDemo | 回填（剪贴板备份→写入→模拟⌘V→恢复） | `PasteHelper` |
| FocusReadDemo | 抓取焦点文本（AX 主路径 + 剪贴板兜底 + 终端跳过） | `FocusReader` + `ClipboardCapture` |
| EditorWindowDemo | 编辑窗口（NSPanel + NSHostingView + SwiftUI TextEditor） | `EditorPanelController` + `EditorView` + `EditorTextStore` |
| HistoryStoreDemo | SwiftData 历史留档 | `HistoryEntry`(@Model) + `HistoryListView` |
| OnboardingDemo | 权限引导（检测→deeplink→轮询→重启生效） | `PermissionManager`(最全) + `PermissionState` + `OnboardingWindowController` + `OnboardingView` |

---

## 2. 关键决策（已锁定，别推翻）

1. **构建：SPM + `build-app.sh`**（不是 Xcode 工程）。SwiftData / MenuBarExtra / SwiftUI App 在 SPM 下都能跑。代价：App 图标 / Asset Catalog / entitlements 要手动塞进 build 脚本（图标已落地：`build-app.sh` 组装时拷 `Resources/AppIcon/AppIcon.icns` 进 bundle，源与重做步骤见该目录 README）；等真要上架再考虑迁 Xcode。
2. **生命周期：`@main SwiftUI App` + `MenuBarExtra` + `NSApplicationDelegateAdaptor`**（不是 demo 的 `main.swift` + `NSApplication.shared.run()`）。无 Dock 图标靠 `LSUIElement=true`；`MenuBarExtra` 给状态栏入口（打开编辑器 / 历史 / 权限设置 / 退出）。不需手动 `setActivationPolicy(.accessory)`。
3. **全新 Bundle ID `com.fasteditor.app`**——独立 TCC 身份，用户需重新授权一次辅助功能 + 输入监控（跟 demo 互不影响），引导页接管。

---

## 3. 三块整合风险（为什么代码这么写）

这三件事没有任何 demo 单独验过，是整合期才出现的真问题，已全部实现并验证。记在这里是解释现有设计的由来。

### 风险 A（最关键）：核心链路串联 + 焦点回归
核心动作是一条链（协调器 `EditingFlow`）：
```
⌃⌘E → FocusReader.readFocusedText()（抓焦点框内容 + source 标记，记住 source/sourceApp）
     → EditorPanelController.show(initialText:source:)（灌进编辑器）
     → 用户编辑 → ⌃Enter → onCommit：
          hide 编辑器 → 原 App 重新成为前台 → PasteHelper.paste(text, source)（回填）
          → HistoryStore.shared.save(text, sourceApp:)（留档）
```
**焦点回归是难点**：编辑器是 `nonactivatingPanel`（设计上不抢焦点、不激活本 App），所以**原 App 始终保持"活动应用"地位**，hide(orderOut) 后原文本框自然重新拿到焦点，⌘V 才落回它。
> ⚠️ **延伸坑**：任何会**激活本 App** 的调用（如 `NSApp.activate(ignoringOtherApps:)`）都会抢走原 App 的活动态、断掉这条回归链 → 回填贴空。曾因覆盖确认弹窗用了它踩过（见 §6③，改 sheet 解决）。

### 风险 B：`PasteHelper` 按 `source` 分情况回填
`FocusReader` 返回的 `source` 区分了语义，`PasteHelper.paste(_ text:source:)` 据此分支：

| source | 含义 | 回填动作 |
|---|---|---|
| `.axSelection` / `.clipboardSelection` | 用户选了一段 | `⌘V`（替换选区） |
| `.axValue` / `.clipboardSelectAll` | 拿的是全文 | `⌘A` 再 `⌘V`（替换全部） |
| `.skippedTerminal` / `.failed` | 终端/没抓到 | 直接 `⌘V`（贴光标处） |

剪贴板备份/恢复 + `isBusy` 防重入保留。

### 风险 C：App 生命周期切换
§2.2 的入口写法和 demo 不同，已验证可跑。

---

## 4. 目录结构（实际）

```
FastEditorApp/
├── Package.swift                # swift-tools 5.9，executableTarget，macOS v14
├── build-app.sh                 # ad-hoc 打包 + identifier-based DR（§7.A）
├── Resources/
│   ├── Info.plist               # CFBundleIdentifier=com.fasteditor.app，LSUIElement=true，CFBundleIconFile=AppIcon
│   └── AppIcon/                 # App 文件图标源（make-icon.swift 生成 → make-icns.sh 切 .icns），README 有重做步骤
└── Sources/FastEditorApp/
    ├── FastEditorApp.swift       # @main App + MenuBarExtra
    ├── AppDelegate.swift         # 首启权限闸门 + 注册热键 + 持有 historyController
    ├── Log.swift                 # os.Logger，subsystem com.fasteditor.app
    ├── Core/
    │   ├── PermissionManager.swift   # 检测 + 请求 + deep-link
    │   ├── FocusReader.swift         # readFocusedText() → (text, source)
    │   ├── ClipboardCapture.swift
    │   ├── PasteHelper.swift         # paste(text, source) 按 source 分支（§3.B）
    │   ├── HotKeyManager.swift       # 可注册多个全局热键（handler 只装一次）
    │   └── LoginItemManager.swift    # 开机自启开关（SMAppService.mainApp 登记/注销）
    ├── Editor/
    │   ├── EditorPanelController.swift  # show/hide/toggle/loadText/bringToFront/confirmOverwrite/onCommit
    │   ├── EditorView.swift
    │   └── EditorTextStore.swift        # ObservableObject「桥」
    ├── Onboarding/
    │   ├── OnboardingWindowController.swift  # 含 relaunchApp()
    │   ├── OnboardingView.swift
    │   └── PermissionState.swift             # ObservableObject + 1s 轮询
    ├── History/
    │   ├── HistoryEntry.swift         # @Model：id/text/createdAt/sourceApp
    │   ├── HistoryListView.swift      # 搜索 + 列表 + 选中高亮 + 快捷键提示
    │   ├── HistoryPanelController.swift  # 持 viewModel，keyMonitor 拦 ↑↓/⏎/⌃⏎/⌫/esc
    │   ├── HistoryStore.swift         # 单例，持 ModelContainer + save(text:sourceApp:)
    │   └── HistoryViewModel.swift     # ObservableObject「桥」：数据+过滤+选中下标（§6）
    └── Flow/
        └── EditingFlow.swift          # 核心协调器：串风险 A 那条链 + 历史面板协调
```

> **重要约定**：源文件是从 demo **搬进来重构**的，**不要 `import` 任何 demo 包**——不是加依赖。`Log.swift` / `HotKeyManager.swift` 各合并成一份；`PermissionManager` 以 OnboardingDemo 版为准。

---

## 5. 实现状态 + 落地差异 + 工作流

**工作流**：`./build-app.sh` 打包 → `open FastEditorApp.app` → 看日志 → `pkill -x FastEditorApp` 停。
> 子命令：`./build-app.sh release`（release 构建）、`./build-app.sh dmg`（release + 封 `FastEditorApp.dmg`，hdiutil 零依赖，自带「拖进 Applications」布局，见 §8）、`./build-app.sh clean`（清 .app/.dmg + SwiftPM 产物）。
> ⚠️ `log` 是 zsh 内建命令，会盖掉 `/usr/bin/log`，跑日志流务必用全路径：
> `/usr/bin/log stream --predicate 'subsystem == "com.fasteditor.app"' --info`
> 重测引导可先 `tccutil reset Accessibility com.fasteditor.app && tccutil reset ListenEvent com.fasteditor.app`。

**已完成（每步一 commit，逐项验证通过）**：① 工程骨架 + SwiftUI App 生命周期 → ② 权限闸门（引导窗/deeplink/轮询/重启）→ ③ 编辑器 + 主热键 → ④ 接抓取 → ⑤ 接回填（焦点回归在原生 App / Chrome 网页框 / 终端实测通过）→ ⑥ 接历史（留档 + 检索 + 删除 + 持久化）→ ⑦ MenuBarExtra 菜单补齐。⏸️ ⑧ 签名公证见 §8（阻塞）。

**与原规划的落地差异（已生效）**：
- **主热键 `⌃⌘E`、副热键 `⌃⌘H`、提交键 `⌃Enter`**（不用 ⌘Enter / 单 ⌃E——单 ⌃E 是系统级「光标移到行尾」绑定）。
- **编辑器面板默认 480×340**。
- **HotKeyManager 可注册多个热键**（全局 event handler 只装一次，每实例唯一 id）。
- **HistoryStore 是单例**（`.shared`，持 ModelContainer + `save(text:sourceApp:)`），不走 demo 那种 AppDelegate 注入。
- **TCC 跨重建保权限的真正修法**见 §7.A（ad-hoc 必须显式设 identifier-based DR）——五个 demo 都有的隐患，本工程已修。
- **开机自启（可配置）**：用 macOS 13+ `SMAppService.mainApp`（零依赖，不违反 §9），不做老式 helper 子 bundle。状态栏菜单加可勾选项「开机自动启动」，绑 `LoginItemManager.shared.isEnabled`，菜单 `onAppear` 刷新以同步用户在「系统设置 → 登录项」里的手动改动。⚠️ 两个 ad-hoc 坑：① 登记的是 App **当前路径**，挪进 /Applications 后需重勾一次；② 偶尔被系统标「需批准」，登录项列表里手动开即可。

---

## 6. 历史面板键盘驱动复用（commit 694cffe / 36fe0d1）

把历史面板从「只能看 + 鼠标删」做成键盘流转，让「复用旧提示词」成为一等操作。

- **键位**（`HistoryPanelController` 的 AppKit keyMonitor 统一拦）：`↑↓` 选择、`⏎` 送进编辑器、`⌃⏎` 跳过编辑器直接贴回原框、`⌫` 删除（仅搜索框为空时；非空放行让退格编辑搜索文本，避免冲突）、`esc` 关闭。
- **`HistoryViewModel`**（ObservableObject，类比 `EditorTextStore` 的「桥」）：单一数据源持「数据+搜索过滤+选中下标」，同时供 SwiftUI 渲染高亮和 AppKit 监听器索引选中条目。**弃用 `@Query` 改主动 fetch**（自持 `ModelContext(container)`，每次 show 刷新）——`@Query` 结果只活在视图里、AppKit 监听器够不到。
- **两种呼出场景统一**走 `EditingFlow.toggleHistory()`：编辑器**关**时 ⌃⌘H → 当场抓当前焦点框为目标域；编辑器**开**时 ⌃⌘H → 复用 ⌃⌘E 已捕获的目标域（不会误抓到自己的编辑器）。之后 `⏎`/`⌃⏎` 都基于同一份 `lastSource/lastSourceApp`。`⌃⏎` 在「编辑器开」场景会先收历史面板再收编辑器，让焦点回落原 App 再回填。

**三个整合期 bug（已修，都不直观，记下防复发）**：
1. keyMonitor guard 用 `panel.isKeyWindow` 替代 `NSApp.keyWindow === panel`——nonactivatingPanel + 全局热键下本 App 未激活时后者为 nil，方向键会漏拦被 ScrollView 当滚动吃掉。
2. 列表 `ForEach` 标识与 `scrollTo` 的 `.id` 必须统一用 index 一套，否则两套 identity 打架致旧选中行高亮卡死。
3. **覆盖确认弹窗别用 `NSApp.activate(ignoringOtherApps:)`**——会把本 App 变活动应用、抢走原 App 活动态，致确认后 ⌃Enter 回填贴空（即 §3.A 的延伸坑）。改用挂在编辑器面板上的 window-modal sheet（`beginSheetModal(for:)`）。

---

## 7. 关键参考

### A. `build-app.sh` 的 TCC 跨重建保权限修法（实测纠正）
ad-hoc 签名默认 designated requirement 是 `cdhash H"..."`，二进制一重编译 hash 就变 → TCC 当成新 App → 每次重新授权。光加 `--identifier` **不够**（只改 Identifier 字段，DR 仍是 cdhash）。必须显式把 DR 设成 identifier-based：
```bash
codesign --force --sign - --identifier "$BUNDLE_ID" \
    -r="designated => identifier \"$BUNDLE_ID\"" "$APP_DIR"
```
这样 TCC 按 bundle ID 认身份，重编译后已授权的「辅助功能 / 输入监控」持续生效。五个 demo 都没这条 `-r`，所以一直有「重建即失权」毛病，本工程已修。

### B. 核心件稳定接口
```swift
// FocusReader —— 抓取主接口
static func readFocusedText() -> (text: String?, source: CaptureSource)
enum CaptureSource { case axSelection, axValue, clipboardSelection, clipboardSelectAll, skippedTerminal, failed }

// EditorPanelController
static let shared: EditorPanelController
func show(initialText: String? = nil, source: String? = nil); func hide(); func toggle()
var currentText: String; func loadText(_:); func bringToFront(); func confirmOverwrite(_ completion: @escaping (Bool)->Void)
var onCommit: ((String) -> Void)?     // ⌃Enter 触发，EditingFlow 在这里接回填+留档

// PasteHelper
static func paste(_ text: String, source: FocusReader.CaptureSource)   // 按 source 分支（§3.B）

// HistoryStore（单例）
static let shared: HistoryStore; var container: ModelContainer?; func save(text:sourceApp:)

// EditingFlow（单例协调器）
func install(); func toggle(); func toggleHistory()
func useHistoryInEditor(text:); func pasteHistoryToField(text:); weak var historyController

// PermissionState（ObservableObject）
@Published var accessibilityGranted / inputMonitoringGranted; var allGranted
func startPolling() / stopPolling()   // 1s Timer，窗显示时开、关时停
```

---

## 8. 签名 + 公证（当前硬阻塞）

⚠️ **当前不执行**。用户**没有 Apple 开发者账号**（99 美元/年），钥匙串里没有 "Developer ID Application" 证书，跑任何 `codesign --sign "Developer ID..."` / `notarytool` / `stapler` 都会失败。
- 第一版 build 用 **ad-hoc 签名**（`build-app.sh` 现有逻辑，含 §7.A 的 DR 修法）。`build-app.sh` 末尾保留了 `release-notarize` 注释占位块。
- **dmg 打包可独立于公证进行**：`./build-app.sh dmg` 用系统自带 `hdiutil` 把 ad-hoc 签名的 .app 封进磁盘镜像（实测 ~180K），不需账号。**但镜像里的 App 仍未公证**——自用/本机拷贝无碍；对方从网络下载（带 `com.apple.quarantine`）会被 Gatekeeper 拦，需右键→打开或 `xattr -dr com.apple.quarantine /Applications/FastEditorApp.app`。要「公开随便下就能开」仍卡公证（本节阻塞）。
- 完整公证流水线在 `../OnboardingDemo/CLAUDE.md` §7 和 `项目交接文档_FastEditor.md` §5.3 已写好，账号到位后另开会话照跑，把 Bundle ID `com.fasteditor.app` 和 Developer ID 证书替进去。
- **不要催用户现在买账号**，按用户节奏来。

---

## 9. 范围边界（别越界）

- ❌ 不做（除非另有要求）：第三方依赖（KeyboardShortcuts / Sparkle / SwiftUIIntrospect 等都不要）；自动更新；多语言；产品级插画/动图引导；语法高亮/Markdown 预览（MVP 用原生 `TextEditor`，进阶再 `NSViewRepresentable` 包 `NSTextView`）。
- ❌ 不要 `import` 任何 demo 包——是搬源文件。
- 密码框无法读取/回填是平台硬限制（交接文档 §5.1），不影响目标场景，不处理。

---

## 10. 与用户协作的默认风格

- 用户是 **Java 后端工程师**，Swift / macOS / TCC / 代码签名都不熟——**用 Java / Android / Spring 类比解释**新概念。
- **全程用中文**回复。
- 偏好「**先验证再扩展**」，不加用不上的抽象、不预埋桩。
- UI 类改动用户能看见、你看不见——**每步建完让用户视觉确认再进下一步**（逐步骨架法）。
- 改完报告：说**改了什么、为什么、还需要用户做什么验证动作**。
