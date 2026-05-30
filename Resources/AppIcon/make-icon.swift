// 生成 App 文件图标的源图（1024×1024 PNG）。
// 纯 macOS 自带能力（AppKit + CoreGraphics + SF Symbols），不引第三方依赖。
//
// 用法： swift make-icon.swift
// 产出： icon-1024.png（同目录）
//
// 设计：现代 macOS 风格——居中圆角方块（squircle 比例近似 Apple 模板），
//       竖向渐变底色，白色 square.and.pencil 符号居中（与菜单栏图标呼应）。
// 想换样式只改下面几个常量：BG_TOP / BG_BOTTOM（底色渐变）、SYMBOL（SF 符号名）。

import AppKit

let CANVAS: CGFloat = 1024
let MARGIN: CGFloat = 100          // 画布到圆角方块的留白（让图标在 Finder 里不顶满）
let BG_TOP    = NSColor(srgbRed: 0.38, green: 0.40, blue: 0.95, alpha: 1) // 顶部：靛蓝
let BG_BOTTOM = NSColor(srgbRed: 0.55, green: 0.30, blue: 0.92, alpha: 1) // 底部：紫
let SYMBOL = "square.and.pencil"
let SYMBOL_POINT: CGFloat = 470    // 符号大小
let outPath = (CommandLine.arguments.count > 1)
    ? CommandLine.arguments[1]
    : (NSString(string: #filePath).deletingLastPathComponent as String) + "/icon-1024.png"

let image = NSImage(size: NSSize(width: CANVAS, height: CANVAS))
image.lockFocus()

// ---- 圆角方块 + 渐变底 ----
let side = CANVAS - 2 * MARGIN
let rect = NSRect(x: MARGIN, y: MARGIN, width: side, height: side)
let radius = side * 0.2237         // Apple squircle 近似圆角比例
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
if let grad = NSGradient(colors: [BG_TOP, BG_BOTTOM]) {
    grad.draw(in: squircle, angle: -90)
}

// ---- 白色 SF 符号居中 ----
let cfg = NSImage.SymbolConfiguration(pointSize: SYMBOL_POINT, weight: .semibold)
if let raw = NSImage(systemSymbolName: SYMBOL, accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    // 把符号染成纯白
    let sz = raw.size
    let tinted = NSImage(size: sz)
    tinted.lockFocus()
    raw.draw(in: NSRect(origin: .zero, size: sz))
    NSColor.white.set()
    NSRect(origin: .zero, size: sz).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let drawRect = NSRect(x: (CANVAS - sz.width) / 2,
                          y: (CANVAS - sz.height) / 2,
                          width: sz.width, height: sz.height)
    tinted.draw(in: drawRect)
}

image.unlockFocus()

// ---- 写 PNG ----
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("❌ 生成 PNG 失败\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("✅ wrote \(outPath)")
