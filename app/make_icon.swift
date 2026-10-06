// 生成 app 图标: 红色渐变圆角方块 + 白色"红果"
// 用法: swift make_icon.swift icon_1024.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size: CGFloat = 1024

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// macOS 11+ 图标规范: 内容留边距(约 100/1024)
let content = NSRect(x: 100, y: 100, width: size - 200, height: size - 200)
let shape = NSBezierPath(roundedRect: content, xRadius: 185, yRadius: 185)

let grad = NSGradient(colors: [
    NSColor(red: 1.00, green: 0.32, blue: 0.26, alpha: 1),
    NSColor(red: 0.85, green: 0.10, blue: 0.14, alpha: 1),
])!
grad.draw(in: shape, angle: -70)

// 高光弧线增加质感
NSColor.white.withAlphaComponent(0.18).setStroke()
let hl = NSBezierPath()
hl.move(to: NSPoint(x: content.minX + 60, y: content.maxY - 150))
hl.curve(to: NSPoint(x: content.maxX - 150, y: content.maxY - 60),
         controlPoint1: NSPoint(x: content.minX + 320, y: content.maxY - 90),
         controlPoint2: NSPoint(x: content.maxX - 90, y: content.maxY - 90))
hl.lineWidth = 26
hl.stroke()

// 文字
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 400, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
]
let s = NSAttributedString(string: "红果", attributes: attrs)
let ts = s.size()
s.draw(in: NSRect(x: 0, y: (size - ts.height) / 2 - 10, width: size, height: ts.height))

img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("icon written: \(out)")
