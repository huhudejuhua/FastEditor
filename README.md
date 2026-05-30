# FastEditor

一个 macOS 菜单栏工具：在任意应用的文本框里按全局热键，弹出干净编辑器，编辑完一键回填到原文本框，并自动存档为可检索历史。

**核心场景**：给 AI agent 写长提示词时，不再受限于网页端那个小输入框。

## 功能概览

| 操作 | 快捷键 | 说明 |
|------|--------|------|
| 抓取 + 编辑 | `⌃⌘E` | 读取当前焦点文本框内容，弹出编辑器 |
| 提交回填 | `⌃Enter` | 编辑器内容写回原文本框，自动留档 |
| 历史面板 | `⌃⌘H` | 打开历史记录，可搜索、复用、删除 |

**历史面板内快捷键**：`↑↓` 选择、`⏎` 送进编辑器、`⌃⏎` 直接回填到原框、`⌫` 删除、`esc` 关闭。

## 需求

- macOS 14 (Sonoma) 或更高版本
- 需要授予两项系统权限（首次启动会自动弹出引导）：
  - **辅助功能** — 读取焦点文本框的内容
  - **输入监控** — 监听全局热键

## 构建 & 运行

零依赖，纯 SwiftPM 工程，不需要 Xcode。

```bash
# 构建 + 打包 .app（debug）
./build-app.sh

# 或 release 构建
./build-app.sh release

# 运行
open FastEditorApp.app

# 停止
pkill -x FastEditorApp
```

打包 DMG（用于分发）：

```bash
./build-app.sh dmg
```

> **注意**：当前使用 ad-hoc 签名（未公证）。从网络下载的 DMG 会被 Gatekeeper 拦截，需右键 → 打开，或执行：
> ```bash
> xattr -dr com.apple.quarantine /Applications/FastEditorApp.app
> ```

查看日志：

```bash
/usr/bin/log stream --predicate 'subsystem == "com.fasteditor.app"' --info
```

## 工作原理

```
⌃⌘E → 抓取焦点文本框内容（AX API，剪贴板兜底）
    → 弹出 nonactivating 编辑面板（不抢焦点）
    → 用户编辑
    → ⌃Enter：隐藏编辑器 → 原 App 自动恢复焦点 → 剪贴板回填 → SwiftData 留档
```

编辑器使用 `nonactivatingPanel`（`NSPanel`），不会激活本 App，从而保证回填时焦点自然回归到原来的文本框。

## 目录结构

```
Sources/FastEditorApp/
├── FastEditorApp.swift          # @main App + MenuBarExtra
├── AppDelegate.swift            # 权限闸门 + 热键注册
├── Core/                        # 权限管理 / 焦点读取 / 回填 / 全局热键
├── Editor/                      # 编辑面板 (NSPanel + SwiftUI TextEditor)
├── History/                     # SwiftData 历史记录 + 检索面板
├── Flow/                        # 核心协调器 (EditingFlow)
├── Onboarding/                  # 首次启动权限引导
└── Log.swift
```

## 技术栈

- SwiftUI + AppKit（`NSPanel` / Carbon 全局热键）
- SwiftData（历史持久化）
- Accessibility API（AXUIElement 读取焦点文本）
- SwiftPM 构建（无 Xcode 工程，无第三方依赖）

## 限制

- 密码框（secure text field）无法读取/回填（macOS 安全策略）
- 未公证 —— 见上方「构建 & 运行」说明
- 仅支持 macOS，无 iOS 版本

## 许可

MIT
