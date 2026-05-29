# CLAUDE.md — FastEditor / FastEditorApp（整合工程）

> 你正在接手 **FastEditor 的整合工程**：把上层目录里五个已验证的 demo（Backfill / FocusRead / EditorWindow / HistoryStore / Onboarding）合并成一个完整可用的产品。请先读完本文档再动手。
>
> ✅ **实现状态（2026-05-30 更新）**：§6 第 1~7 步**全部完成并逐项验证通过**，核心产品功能完整可用（任意文本框 ⌃⌘E 抓取→编辑→⌃Enter 回填+留档→⌃⌘H 检索）。源码在 `Sources/FastEditorApp/`，git 一步一 commit。**仅剩第 8 步签名公证**——硬阻塞于 Apple 开发者账号（见 §8），ad-hoc 顶着。下面的规划/接口/风险说明仍是有效参考。各步完成详情见 §6 状态标记。
>
> 🆕 **第 7 步之后的增强（2026-05-30，commit 694cffe）**：历史面板做成**键盘驱动复用**——`↑↓` 选条 / `⏎` 送进编辑器（已开且有内容先弹覆盖确认）/ `⌃⏎` 跳过编辑器直接贴回原框 / `⌫` 删除（搜索框空时）。两种呼出场景（直接 ⌃⌘H、编辑器中 ⌃⌘H）统一走 `EditingFlow.toggleHistory` 捕获/复用目标域。详见 §6 增强条目。

---

## 1. 这是什么

五个验证 demo 各自验证了**一个孤立的技术风险**，全部通过（见上层 `项目交接文档_FastEditor.md` §6 和 `PROGRESS.md`）：

| demo | 验证了什么 | 权限 | 整合时搬走的核心件 |
|---|---|---|---|
| `../BackfillDemo/` | 回填通用性（剪贴板备份→写入→模拟⌘V→恢复） | 辅助功能 + 输入监控 | `PasteHelper` |
| `../FocusReadDemo/` | 抓取焦点文本（AX 主路径 + 剪贴板兜底 + 终端跳过） | 辅助功能 + 输入监控 | `FocusReader` + `ClipboardCapture` + `PermissionManager` |
| `../EditorWindowDemo/` | 编辑窗口形态（NSPanel + NSHostingView + SwiftUI TextEditor） | 零 | `EditorPanelController` + `EditorView` + `EditorTextStore` |
| `../HistoryStoreDemo/` | SwiftData 历史留档 | 零 | `HistoryEntry`(@Model) + `HistoryListView` + `HistoryPanelController` |
| `../OnboardingDemo/` | 权限引导（检测→deeplink→轮询→重启生效） | 引导两项 | `PermissionManager`(最全) + `PermissionState` + `OnboardingWindowController` + `OnboardingView` + `relaunchApp()` |

**本工程 = 把这些验证过的件搬进一个新工程，重构布线，做成一个连贯的产品。**

产品形态（交接文档 §0）：在任意应用的文本框里按全局热键 → 弹出干净的临时编辑器（带进原有内容）→ 编辑完按热键 → 自动回填进原文本框 + 自动留档为可检索历史。核心场景：给 AI agent 写长提示词。

---

## 2. 已锁定的关键决策（本规划会话定的，别推翻）

1. **构建方式：SPM + `build-app.sh`**（不是 Xcode 工程）。和五个 demo 完全一致，直接复用打包脚本和工作流。SwiftData / MenuBarExtra / SwiftUI App 在 SPM 下都能跑（demo 已证，§3 骨架也实测过）。
   - 代价：App 图标 / Asset Catalog / entitlements 这些「成品 App」配置要手动塞进 build 脚本。等真要上架/分发再考虑迁 Xcode，现在不迁。

2. **App 生命周期：`SwiftUI App(@main)` + `MenuBarExtra` + `NSApplicationDelegateAdaptor`**（不是 demo 的 `main.swift` + `NSApplication.shared.run()`）。
   - 这是按交接文档 §8 目标架构走。`MenuBarExtra` 给用户一个状态栏图标入口（打开编辑器 / 历史 / 设置 / 退出）。
   - ⚠️ **这是唯一一处「demo 验证过的形态」≠「产品目标形态」**。§3 已**实测确认这套在 SPM 下能跑**（@main + MenuBarExtra + adaptor，无 Dock 图标靠 `LSUIElement=true`），骨架代码见 §7.A，照抄即可。

3. **全新 Bundle ID：`com.fasteditor.app`**。和五个 demo 的 ID 都区分开 → 一个**全新 TCC 身份** → 用户**要重新授权一次**辅助功能 + 输入监控（跟 demo 的授权互不影响）。属正常，引导页正好接管这件事。

---

## 3. 真正的新工作：三块「整合期才出现」的风险

五个 demo 各自孤立验过，但**这三件事没有任何 demo 验证过**，是整合的真风险。实现时重点盯这三块：

### 风险 A（最大）：核心链路串联 + 焦点回归
产品核心动作是一条链：
```
按主热键
  → FocusReader.readFocusedText()              // 抓当前焦点框内容 + source 标记
  → EditorPanelController.show(initialText:source:)  // 灌进编辑器
  → 用户编辑 → ⌘Enter
  → onCommit 闭包：
       hide 编辑器
       → 让原 App 重新成为前台          ← ⚠️ 难点
       → PasteHelper.paste(text, source)        // 回填
       → HistoryStore.save(text, sourceApp:)    // 留档
```
**难点 = 焦点回归**：我们的编辑器弹出后，⌘Enter 提交时必须保证「原来那个文本框」重新是前台，⌘V 才会落回它。编辑器用的是 `nonactivatingPanel`（设计上就不抢焦点，对我们有利），但「编辑完贴回原处」这条端到端**从没跑过**。必须在 Chrome 网页框 / 原生 App / Electron 各实测一遍。

### 风险 B：`PasteHelper` 要按 `source` 分情况回填
现在 `PasteHelper`（`../BackfillDemo/.../PasteHelper.swift`）只会无脑 `⌘V` 贴一段固定文本。但 `FocusReader` 返回的 `source`（`FocusReader.CaptureSource`）区分了语义，回填要分支：

| source | 含义 | 回填动作 |
|---|---|---|
| `.axSelection` / `.clipboardSelection` | 用户选了一段 | `⌘V`（替换选区） |
| `.axValue` / `.clipboardSelectAll` | 拿的是全文 | `⌘A` 再 `⌘V`（替换全部） |
| `.skippedTerminal` / `.failed` | 终端或没抓到 | 直接 `⌘V`（贴光标处） |

这段分支 + 把 `paste(...)` 改成接收 `(text: String, source: CaptureSource)` 是**新写的代码**。

### 风险 C：App 生命周期切换
见 §2.2。已实测可跑，骨架照 §7.A 抄，但仍是和 demo 不同的入口写法，实现第 1 步要单独验掉。

> 类比 Java：前五个是五个独立 PoC `main`；整合是新开 module，把验证过的类逐个搬进来重构布线。**布线层（风险 A、B）才是新代码**，搬运本身是体力活。

---

## 4. 计划的目录结构

```
FastEditorApp/
├── Package.swift                     # SPM，name=FastEditorApp，executableTarget，macOS v14（§7.A）
├── build-app.sh                      # 抄 ../OnboardingDemo/build-app.sh，改 APP_NAME/BUNDLE_ID（§7.E）
├── CLAUDE.md                         # 你正在读的这份
├── .gitignore                        # .build / *.app / .DS_Store / .swiftpm
├── Resources/
│   └── Info.plist                    # CFBundleIdentifier=com.fasteditor.app，LSUIElement=true（§7.D）
└── Sources/FastEditorApp/
    ├── FastEditorApp.swift           # @main App + MenuBarExtra + NSApplicationDelegateAdaptor（§7.A）
    ├── AppDelegate.swift             # 桥接层：首启权限闸门 + 注册主热键 + 持有各 controller
    ├── Log.swift                     # 抄任一 demo，subsystem 改 com.fasteditor.app
    ├── Core/                         # 系统底层（与 UI 框架无关）
    │   ├── PermissionManager.swift   ← OnboardingDemo（最全：检测 + 请求 + deep-link）
    │   ├── FocusReader.swift         ← FocusReadDemo（整段，readFocusedText() 接口已稳）
    │   ├── ClipboardCapture.swift    ← FocusReadDemo
    │   ├── PasteHelper.swift         ← BackfillDemo（★改造：paste(text, source) 按 source 分支，见 §3.B）
    │   └── HotKeyManager.swift       ← 任一 demo（keyCode 改成产品主热键）
    ├── Editor/
    │   ├── EditorPanelController.swift  ← EditorWindowDemo（show/hide/toggle/onCommit 已就位）
    │   ├── EditorView.swift          ← EditorWindowDemo
    │   └── EditorTextStore.swift     ← EditorWindowDemo（ObservableObject 桥）
    ├── Onboarding/
    │   ├── OnboardingWindowController.swift  ← OnboardingDemo
    │   ├── OnboardingView.swift              ← OnboardingDemo
    │   └── PermissionState.swift             ← OnboardingDemo（ObservableObject + 1s 轮询）
    ├── History/
    │   ├── HistoryEntry.swift         ← HistoryStoreDemo（@Model，字段含 sourceApp，已留好）
    │   ├── HistoryListView.swift      ← HistoryStoreDemo
    │   ├── HistoryPanelController.swift ← HistoryStoreDemo（或整合进 MenuBarExtra，见 §6 第6步）
    │   └── HistoryStore.swift         # ★新增：封装「提交成功时写一条」+ ModelContainer 持有
    └── Flow/
        └── EditingFlow.swift          # ★新增：把 §3.A 那条链串起来的协调器（核心布线层）
```

★ = 全新写的件（不是搬运）。其余都是从对应 demo 搬过来改 import / 改命名空间。

**搬运注意**：五个 demo 各有一份 `Log.swift` / `HotKeyManager.swift`，合并成各一份。`PermissionManager` 以 OnboardingDemo 版为准（它检测+请求+deeplink 最全），其它 demo 的同名文件不要重复搬。**不要 `import XxxDemo`**——是把源文件搬进来，不是依赖 demo 包。

---

## 5. 搬运 / 改造清单（实现时逐项核对）

- [ ] `Log.swift`：抄任一 demo，`subsystem` 改 `com.fasteditor.app`，banner 文案改成产品的。
- [ ] `HotKeyManager.swift`：抄任一 demo。产品主热键建议 `⌃⌥E`（或别的，避开系统占用）。**keyCode 可考虑做成可配置**（整合后期目标），第一版先硬编码。
- [ ] `PermissionManager.swift`：搬 OnboardingDemo 版（含 `isAccessibilityGranted` / `isInputMonitoringGranted` / `authorizeAccessibility` / `authorizeInputMonitoring` / `open*Settings` deep-link）。
- [ ] `PermissionState.swift` / `OnboardingWindowController.swift` / `OnboardingView.swift`：整段搬 OnboardingDemo，命名空间改掉即可。`relaunchApp()` 在 `OnboardingWindowController` 里，保留。
- [ ] `FocusReader.swift` / `ClipboardCapture.swift`：整段搬 FocusReadDemo。`readFocusedText() -> (text: String?, source: CaptureSource)` 就是稳定接口，直接用。
- [ ] `EditorPanelController.swift` / `EditorView.swift` / `EditorTextStore.swift`：整段搬 EditorWindowDemo。`show(initialText:source:)` / `hide()` / `toggle()` / `var onCommit: ((String)->Void)?` 已经是整合形状，直接接。
- [ ] `HistoryEntry.swift`：整段搬 HistoryStoreDemo（`@Model`，`id/text/createdAt/sourceApp`，`sourceApp` 已留好）。
- [ ] `HistoryListView.swift`：搬 HistoryStoreDemo。
- [ ] **★`PasteHelper.swift`**：搬 BackfillDemo，**改造**：`pasteFixedText()` → `paste(_ text: String, source: FocusReader.CaptureSource)`，按 §3.B 表分支 `⌘V` / `⌘A+⌘V` / 光标处 `⌘V`。剪贴板备份/恢复 + `isBusy` 防重入逻辑保留。
- [ ] **★`HistoryStore.swift`**：新增，持有 `ModelContainer`，提供 `save(text:sourceApp:)`。ModelContainer 建法参考 HistoryStoreDemo 的 `AppDelegate`（显式 store URL 到 `~/Library/Application Support/com.fasteditor.app/`），或用 SwiftUI `.modelContainer(for:)` 挂 scene（见 §7.A 注释）。
- [ ] **★`EditingFlow.swift`**：新增协调器，串 §3.A 那条链。`EditorPanelController.shared.onCommit = { text in ... }` 在这里设。

---

## 6. 实现顺序（逐步骨架法，每步 `./build-app.sh` + `open` + `log stream` 看到预期再进下一步）

> 工作流和五个 demo 一致：`./build-app.sh` 打包 → `open FastEditorApp.app` → `/usr/bin/log stream --predicate 'subsystem == "com.fasteditor.app"' --info` 看日志 → `pkill -x FastEditorApp` 停。
> ⚠️ `log` 是 zsh 内建命令，会盖掉 `/usr/bin/log`，跑日志流务必用**全路径** `/usr/bin/log`。

> **✅ 进度（2026-05-29）：第 1~7 步全部完成并验证通过，一步一 commit。第 8 步账号阻塞未动。**
> 实现期与原计划的几处落地差异（已生效）：
> - **主热键 ⌃⌘E**（不是规划里随手写的 ⌃⌥E）、**副热键 ⌃⌘H**（历史）。不用单 ⌃E：那是系统级「光标移到行尾」绑定。
> - **提交键 ⌃Enter**（不是 ⌘Enter，用户偏好）。
> - **编辑器面板默认 480×340**。
> - **HotKeyManager 已改造为可注册多个热键**（全局 event handler 只装一次，每实例唯一 id）。
> - **HistoryStore 是单例**（`.shared`，持有 ModelContainer + `save(text:sourceApp:)`），不走 demo 那种 AppDelegate 注入。
> - **TCC 跨重建保权限的真正修法**见 §7.E（ad-hoc 必须显式设 identifier-based DR，仅 `--identifier` 无效）——这是五个 demo 都有的隐患，本工程已修。

> **🆕 第 7 步之后的增强（2026-05-30，commit 694cffe）：历史面板键盘驱动复用。**
> 原历史面板只能看 + 鼠标删。本次做成键盘流转，让「复用旧提示词」成为一等操作：
> - **键位**（在 `HistoryPanelController` 的 AppKit keyMonitor 里统一拦）：`↑↓` 选择、`⏎` 送进编辑器、`⌃⏎` 跳过编辑器直接贴回原框、`⌫` 删除（仅搜索框为空时；非空放行让退格编辑搜索文本，避免冲突）、`esc` 关闭。
> - **新增 `HistoryViewModel`**（ObservableObject，类比 `EditorTextStore` 的「桥」）：单一数据源持「数据+搜索过滤+选中下标」，同时供 SwiftUI 渲染高亮和 AppKit 监听器索引选中条目。**弃用 `@Query` 改主动 fetch**（自持 `ModelContext(container)`，每次 show 刷新）——因为 @Query 结果只活在视图里、AppKit 监听器够不到。
> - **两种呼出场景统一**走 `EditingFlow.toggleHistory()`：编辑器**关**时按 ⌃⌘H → 当场抓当前焦点框为目标域；编辑器**开**时按 ⌃⌘H → 复用 ⌃⌘E 已捕获的目标域（不会误抓到自己的编辑器）。之后 `⏎`/`⌃⏎` 都基于这同一份 `lastSource/lastSourceApp`。`⌃⏎` 在场景 B 会先收起历史面板再收起编辑器，让焦点回落到原 App 再回填。
> - **三个整合期 bug（已修）**：① keyMonitor guard 用 `panel.isKeyWindow` 替代 `NSApp.keyWindow === panel`——nonactivatingPanel + 全局热键下本 App 未激活时后者为 nil，方向键会漏拦被 ScrollView 当滚动吃掉；② 列表 `ForEach` 标识与 `scrollTo` 的 `.id` 必须统一用 index 一套，否则两套 identity 打架致旧选中行高亮卡死；③ **覆盖确认弹窗别用 `NSApp.activate(ignoringOtherApps:)`**（commit 36fe0d1）——它会把本 App 变成活动应用、抢走原 App 的活动态，导致确认后 ⌃Enter 回填时焦点回不到原框、⌘V 贴空。改用挂在编辑器面板上的 window-modal sheet（`beginSheetModal(for:)`）即可避开。**这是风险 A（焦点回归）的延伸坑：任何会激活本 App 的调用都会断掉 nonactivatingPanel「原 App 始终活动 → hide 后焦点自然回归」这条链。**

1. ✅ **工程骨架 + 切 SwiftUI App 生命周期**（验风险 C）：`Package.swift` + `Info.plist` + `build-app.sh` + `Log.swift` + `FastEditorApp.swift`(@main App + 空 MenuBarExtra 只放退出) + `AppDelegate.swift`(只打 log)。验：能 build、`pgrep -x FastEditorApp` 在跑、状态栏有图标、无 Dock 图标、log 有启动行。**§7.A 给了实测可跑的骨架代码，照抄。**
2. ✅ **搬权限闸门**：`PermissionManager` + `PermissionState` + `OnboardingWindowController` + `OnboardingView`。首启检测两项，缺则弹引导窗。验：同 OnboardingDemo（检测 / deeplink / 1s 轮询翻转 / 重启生效）。先 `tccutil reset Accessibility com.fasteditor.app && tccutil reset ListenEvent com.fasteditor.app` 重测。
3. ✅ **搬编辑器 + 主热键**：`HotKeyManager` + `EditorPanelController` + `EditorView` + `EditorTextStore`。主热键(⌃⌘E)开空编辑器，Esc / ⌃Enter 通（onCommit 先只打 log）。验：浮窗 nonactivatingPanel 不抢焦点、Esc 关、⌃Enter 触发 log。
4. ✅ **接抓取**（风险 A 上半）：搬 `FocusReader` + `ClipboardCapture`。主热键 → `readFocusedText()` → `show(initialText:source:)`。验：编辑器打开时预填了当前焦点框内容，log 出 source。
5. ✅ **接回填**（★风险 A 下半 + 风险 B，最关键）：写 `EditingFlow`，`onCommit` → 改造后的 `PasteHelper.paste(text, source)`。**焦点回归**：原生 App / Chrome 网页框 / 终端各场景实测「抓→编辑→⌃Enter→内容正确回填到原框」通过。
6. ✅ **接历史**：`HistoryEntry` + `HistoryStore`(单例持 ModelContainer) + 提交成功时 `save(text:sourceApp:)`。浏览 UI 用 `HistoryListView`，挂副热键 ⌃⌘H。验：每次提交写一行（含 sourceApp），列表可检索、可删除、落盘持久化。
7. ✅ **打磨**：MenuBarExtra 菜单补齐（打开编辑器 ⌃⌘E / 历史记录 ⌃⌘H / 权限设置 / 退出）。
8. ⏸️ **签名公证**：见 §8，**当前硬阻塞**（没 Apple 开发者账号），ad-hoc 顶着。

任一步卡住，先回退上一步隔离问题——权限 / 时序 / 焦点类 bug 报错不直观，逐步隔离好排查。

---

## 7. 已验证可跑的骨架代码（第 1 步直接抄）

> 下面这套在本规划会话里**实测构建成功 + 启动成功**（`@main` App + MenuBarExtra + adaptor 在 SPM 下能跑，无 Dock 图标，applicationDidFinishLaunching 正常触发并打日志）。照抄即可，不用再试错。

### A. `Sources/FastEditorApp/FastEditorApp.swift`
```swift
import SwiftUI
import AppKit

@main
struct FastEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 第1步先只放退出；后续补「打开编辑器 / 历史 / 设置」。
        MenuBarExtra("FastEditor", systemImage: "square.and.pencil") {
            Text("FastEditor")
            Divider()
            Button("退出 FastEditor") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        // 第6步接历史时，可在这里挂： .modelContainer(sharedContainer)
        // 或单独用 Window/Settings scene 承载历史列表 + 设置页。
    }
}
```
> ⚠️ SPM 用 `@main` 时**不能有名为 `main.swift` 的文件**（那是特殊文件名，会被当顶层代码）。入口文件叫 `FastEditorApp.swift`，用 `@main` 注解 struct。

### B. `Sources/FastEditorApp/AppDelegate.swift`（第1步骨架）
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 后续往这里挂：hotKeyManager / 各 controller / 首启权限闸门
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.banner()
        Log.info("FastEditor launched. Bundle = \(Bundle.main.bundleIdentifier ?? "<nil>")")
        Log.info("LSUIElement=true → 无 Dock 图标；MenuBarExtra → 状态栏有图标。")
    }
}
```
> 不需要手动 `setActivationPolicy(.accessory)`——`LSUIElement=true` 已让它是 agent app。MenuBarExtra 自己管状态栏呈现。

### C. `Package.swift`
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastEditorApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FastEditorApp", path: "Sources/FastEditorApp")
    ]
)
```

### D. `Resources/Info.plist`（关键字段）
```
CFBundleExecutable     = FastEditorApp
CFBundleIdentifier     = com.fasteditor.app
CFBundleName / DisplayName = FastEditor
LSMinimumSystemVersion = 14.0
LSUIElement            = true     ← 无 Dock 图标
CFBundlePackageType    = APPL
```

### E. `build-app.sh`
抄 `../OnboardingDemo/build-app.sh`，改两个变量：`APP_NAME="FastEditorApp"` / `BUNDLE_ID="com.fasteditor.app"`，删掉 onboarding 特有的 echo 文案。`release-notarize` 注释占位块原样保留（见 §8）。

> ⚠️ **TCC 跨重建保权限的真正关键（实测纠正）**：ad-hoc 签名默认的 designated requirement 是 `cdhash H"..."`，二进制一重编译 hash 就变 → TCC 当成新 App → 每次都要重新授权。光加 `--identifier` **不够**（那只改 Identifier 字段，DR 仍是 cdhash）。必须显式把 DR 设成 identifier-based：
> ```
> codesign --force --sign - --identifier "$BUNDLE_ID" \
>     -r="designated => identifier \"$BUNDLE_ID\"" "$APP_DIR"
> ```
> 这样 TCC 按 bundle ID 认身份，重编译后已授权的「辅助功能 / 输入监控」持续生效。五个 demo 的脚本都没这条 `-r`，所以 demo 期一直有「重建即失权」的毛病。本工程 build-app.sh 已修。

### F. 整合后核心件的稳定接口（搬运时认这些签名）
```swift
// FocusReader（搬 FocusReadDemo）—— 抓取主接口
static func readFocusedText() -> (text: String?, source: CaptureSource)
enum CaptureSource { case axSelection, axValue, clipboardSelection, clipboardSelectAll, skippedTerminal, failed }

// EditorPanelController（搬 EditorWindowDemo）—— 已是整合形状
static let shared: EditorPanelController
func show(initialText: String? = nil, source: String? = nil)
func hide(); func toggle()
var onCommit: ((String) -> Void)?     // ⌘Enter 触发，EditingFlow 在这里接回填+留档

// PasteHelper（★改造 BackfillDemo）
static func paste(_ text: String, source: FocusReader.CaptureSource)   // 按 source 分支，见 §3.B

// HistoryEntry（搬 HistoryStoreDemo，@Model）
init(text: String, sourceApp: String? = nil)   // sourceApp 已留好

// PermissionState（搬 OnboardingDemo，ObservableObject）
@Published var accessibilityGranted / inputMonitoringGranted; var allGranted
func startPolling() / stopPolling()   // 1s Timer，窗显示时开、关时停
```

---

## 8. 签名 + 公证（当前硬阻塞，账号到位后照交接文档 §7 跑）

⚠️ **当前不执行**。用户**没有 Apple 开发者账号**（99 美元/年），钥匙串里没有 "Developer ID Application" 证书，跑任何 `codesign --sign "Developer ID..."` / `notarytool` / `stapler` 都会失败。

- 第一版 build 用 **ad-hoc 签名**（`build-app.sh` 现有逻辑）。
- 完整公证流水线在上层 `../OnboardingDemo/CLAUDE.md` §7 和 `项目交接文档_FastEditor.md` §5.3 已写好，账号到位后另开会话照跑，把产品 Bundle ID（`com.fasteditor.app`）和 Developer ID 证书替进去。
- 这是 §5.3「Release 包静默失败」风险的最终解，也是 FastEditor 交到用户手里的最后一公里。
- **不要催用户现在买账号**，按用户节奏来。

---

## 9. 范围边界（实现时别越界）

- ✅ 做：把五个 demo 验证过的件搬进来，按 §6 顺序串成完整产品。
- ❌ 不做（除非另有要求）：第三方依赖（KeyboardShortcuts / Sparkle / SwiftUIIntrospect 等都不要）；自动更新（Sparkle 是后续话题）；多语言；产品级插画/动图引导；语法高亮/Markdown 预览（MVP 用 SwiftUI 原生 `TextEditor`，进阶再 `NSViewRepresentable` 包 `NSTextView`）。
- ❌ 不要 `import` 任何 demo 包——是搬源文件，不是加依赖。
- 密码框无法读取/回填是平台硬限制（交接文档 §5.1），不影响目标场景，不用处理。

---

## 10. 与用户协作的默认风格（同一个用户，五个 demo 一路下来）

- 用户是 **Java 后端工程师**，Swift / macOS / TCC / 代码签名都不熟，**用 Java / Android / Spring 类比解释**新概念。
- **全程用中文**回复。
- 偏好「**先验证再扩展**」，不加用不上的抽象、不预埋桩。
- **规划与实现分会话**：用户要规划时只给规划/文档，不要直接开写实现（本工程就是规划产物，实现是另一个会话）。
- UI 类改动用户能看见、你看不见——**每步建完让用户视觉确认再进下一步**（逐步骨架法）。
- 改完报告：说**改了什么、为什么、还需要用户做什么验证动作**。

---

> **一句话总结**：本工程把五个验证过的 demo 搬进一个 SPM 新工程（`@main` SwiftUI App + MenuBarExtra + adaptor，Bundle ID `com.fasteditor.app`），按 §6 八步逐步串成完整 FastEditor。搬运是体力活，**真风险只有三块**（§3：核心链路焦点回归、PasteHelper 按 source 分支、生命周期切换），其中焦点回归（第5步）最关键。签名公证（第8步）因没开发者账号硬阻塞，ad-hoc 顶着，账号到位后照交接文档 §7 跑。
