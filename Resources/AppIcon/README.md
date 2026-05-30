# App 文件图标

`FastEditorApp.app` 在 Finder / dmg 里显示的图标。纯 macOS 自带工具生成，零第三方依赖（守 CLAUDE.md §9）。

> 注：本 App `LSUIElement=true`（无 Dock 图标），所以这个图标主要在 **Finder 和 dmg** 里出现，Dock 不显示。

## 文件

| 文件 | 作用 | 是否入库 |
|---|---|---|
| `make-icon.swift` | 生成 1024 源图（AppKit 画圆角渐变底 + SF 符号）| ✓ |
| `icon-1024.png` | 源图（实际渲染 2048×2048，Retina 友好）| ✓ |
| `make-icns.sh` | 把源图切 10 档尺寸 → 编译成 `.icns`（sips + iconutil）| ✓ |
| `AppIcon.icns` | 最终图标，`build-app.sh` 拷进 `.app/Contents/Resources/` | ✓ |

## 怎么改图标

1. 调样式：编辑 `make-icon.swift` 顶部常量——`BG_TOP`/`BG_BOTTOM`（渐变底色）、`SYMBOL`（SF 符号名，如 `pencil.and.outline` / `text.cursor`）、`SYMBOL_POINT`（符号大小）。
   - 想换成自己的图：直接拿一张 1024×1024（或更大）透明背景 PNG 覆盖 `icon-1024.png`，跳过这步。
2. 重生成源图：`swift make-icon.swift "$PWD/icon-1024.png"`（必须传绝对路径，否则 `#filePath` 解析成相对路径会写到只读根目录）。
3. 重生成 icns：`./make-icns.sh`
4. 重新打包：`../../build-app.sh release`（或 `dmg`），会自动把新 `AppIcon.icns` 拷进 bundle。
5. Finder 可能缓存旧图标 —— 看不到更新时把旧 `.app` 拖进废纸篓重 build，或直接在新挂载的 dmg 里看（不吃缓存）。

## 接入点

- `Resources/Info.plist`：`CFBundleIconFile = AppIcon`
- `build-app.sh`：assemble 阶段 `cp Resources/AppIcon/AppIcon.icns .../Contents/Resources/`
