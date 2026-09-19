// 生成 Rime.icon/Assets/logo.svg：App 图标，粉底 + 白色真字形「五」。
// 血泪史：手画几何五 -> 左倾6°+笔画移位+小圆点，活脱脱一个"E"，根本不是五。
// 教训跟菜单图标一样（见 mkicon.swift）：别手画，用真字形。
// 做法：本机用 Hiragino Maru Gothic ProN（跟菜单图标同款圆体）取字形描边，
// 把贝塞尔路径写进 SVG —— 仓库里只留路径，不依赖字体，CI 也能编。
// 注意人肉跑（改完跑一遍，产物进仓库），CI 不跑它。
// 用法：swiftc -o /tmp/mkappicon tools/mkappicon.swift -framework AppKit && /tmp/mkappicon
import AppKit
import CoreText

let S: CGFloat = 1024
let fontSize: CGFloat = 800
let font = NSFont(name: "Hiragino Maru Gothic ProN", size: fontSize)
  ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
print("用字体：\(font.fontName)")

let ctFont = CTFontCreateWithName(font.fontName as CFString, fontSize, nil)
var glyph = CTFontGetGlyphWithName(ctFont, "uni4E94" as CFString)
if glyph == 0 {
  let chars: [UniChar] = [0x4E94]  // 五
  var g = [CGGlyph](repeating: 0, count: 1)
  CTFontGetGlyphsForCharacters(ctFont, chars, &g, 1)
  glyph = g[0]
}
guard glyph != 0, let cgPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
  print("取字形描边失败"); exit(1)
}
let bbox = cgPath.boundingBox
// 目标：字形占 68%，居中。SVG y 朝下，CG y 朝上，翻转。
let target = S * 0.68
let scale = target / max(bbox.width, bbox.height)
let tx = (S - bbox.width * scale) / 2 - bbox.minX * scale
let ty = (S - bbox.height * scale) / 2 + bbox.maxY * scale

func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
var d = ""
let t: (CGPoint) -> String = { p in "\(f(p.x * scale + tx)),\(f(-p.y * scale + ty))" }
cgPath.applyWithBlock { el in
  let p = el.pointee
  switch p.type {
  case .moveToPoint: d += "M\(t(p.points[0]))"
  case .addLineToPoint: d += "L\(t(p.points[0]))"
  case .addQuadCurveToPoint: d += "Q\(t(p.points[0])) \(t(p.points[1]))"
  case .addCurveToPoint: d += "C\(t(p.points[0])) \(t(p.points[1])) \(t(p.points[2]))"
  case .closeSubpath: d += "Z"
  @unknown default: break
  }
}
let svg = """
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 1024 1024" version="1.1" xmlns="http://www.w3.org/2000/svg" style="fill-rule:evenodd;clip-rule:evenodd;">
    <!-- Xpier：粉底（选中候选条同款粉 #FFAAB8）+ 白色真字形「五」。 -->
    <!-- 字形取自 Hiragino Maru Gothic ProN（跟菜单图标同款），描边由 tools/mkappicon.swift 生成。 -->
    <!-- 别手画！上次手画版被认成 E（见交接文档）。底色铺满整幅，圆角由 iconcomposer 按系统规范切。 -->
    <rect x="0" y="0" width="1024" height="1024" style="fill:#ffaab8;"/>
    <path d="\(d)" style="fill:#fff;"/>
</svg>
"""
let url = URL(fileURLWithPath: "Rime.icon/Assets/logo.svg")
try! svg.write(to: url, atomically: true, encoding: .utf8)
print("已写入 \(url.path)，路径长度 \(d.count)")
