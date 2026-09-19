// 生成 resources/rime.pdf：菜单/设置列表里的「五」字形图标。
// 血泪史：
// 1. 手画几何 -> 比例不对被认成王；
// 2. 系统字体黑五 -> 字形对了；
// 3. 粉徽章白五 -> 系统把这个槽位当模板蒙版，只取形状不取颜色，
//    整块粉底变成纯黑板（悬停纯白）。颜色在这里活不了。
// 4. 定稿：Hiragino Maru Gothic ProN（丸ゴ，圆体）—— 单色槽位里
//    字形负责俏皮（清歌输入法的歌同款路子）。用户钦定。
// 透明底 + 黑字，跟原版松鼠一个路子：菜单里黑五，悬停变白五。
// 颜色留给出厂图标（Rime.icns 粉底白字）。
// 规格：22x16pt 横版（跟原文件一致，方图会撑坏菜单布局）。
// 注意 mkicon 是人肉跑的（改完跑一遍，产物进仓库），CI 不跑它 ——
// 所以字体只要求本机有，丸ゴ是 macOS 自带，不用装。
// 用法：swiftc -o /tmp/mkicon tools/mkicon.swift -framework AppKit && /tmp/mkicon
import AppKit
import CoreGraphics

let url = URL(fileURLWithPath: "resources/rime.pdf")
var box = CGRect(x: 0, y: 0, width: 22, height: 16)
guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
  print("建 PDF 上下文失败"); exit(1)
}
let size: CGFloat = 15
let font = NSFont(name: "Hiragino Maru Gothic ProN", size: size)
  ?? NSFont.systemFont(ofSize: size, weight: .semibold)
let attrs: [NSAttributedString.Key: Any] = [
  .font: font, .foregroundColor: NSColor.black,
]
let s = "五" as NSString
let adv = s.size(withAttributes: attrs)
let origin = NSPoint(x: (22 - adv.width) / 2,
                     y: (16 - adv.height) / 2 - 1)
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
ctx.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
s.draw(at: origin, withAttributes: attrs)
NSGraphicsContext.restoreGraphicsState()
ctx.endPDFPage()
ctx.closePDF()
print("已写入 \(url.path)")
