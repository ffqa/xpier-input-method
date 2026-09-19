// tis-name：列出系统当前认得的输入源（id / 显示名称 / 类别 / 启用 / 选中）。
// update 脚本的自检靠它（grep 显示名称|当前选中），probe 排错也靠它。
// 默认只列自家 bundle（原来就是这么干的：老版写死过滤 im.rime...Squirrel），
// 输出短才看得清；要看别的传 bundle id 参数。
// 输出格式固定，别改 —— 有脚本在 parse。
// 用法：swiftc -o tools/tis-name tools/tis-name.swift -framework Carbon
import Carbon
import Foundation

let bundleID = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1] : "com.xpier.inputmethod.Xpier"

func prop(_ s: TISInputSource, _ k: CFString) -> CFTypeRef? {
  guard let raw = TISGetInputSourceProperty(s, k) else { return nil }
  return unsafeBitCast(raw, to: CFTypeRef.self)
}

func str(_ o: CFTypeRef?) -> String {
  guard let o = o else { return "?" }
  if CFGetTypeID(o) == CFStringGetTypeID() { return (o as! CFString) as String }
  return "?"
}

func bool(_ o: CFTypeRef?) -> String {
  guard let o = o else { return "?" }
  if CFGetTypeID(o) == CFBooleanGetTypeID() {
    // swiftlint 嫌 as! 多余，但 CFTypeRef -> CFBoolean 只能这么转。
    return CFBooleanGetValue((o as! CFBoolean)) ? "true" : "false"
  }
  return "?"
}

let list = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
print("系统当前认得的输入源名称：")
for s in list {
  let id = str(prop(s, kTISPropertyInputSourceID))
  // 只列自家：全系统几百个键盘布局全打出来没人看。
  guard id.hasPrefix(bundleID) else { continue }
  let cat = str(prop(s, kTISPropertyInputSourceCategory))
  print("  id       = \(id)")
  print("  显示名称 = \(str(prop(s, kTISPropertyLocalizedName)))")
  print("  类别     = \(cat)   启用=\(bool(prop(s, kTISPropertyInputSourceIsEnabled)))  当前选中=\(bool(prop(s, kTISPropertyInputSourceIsSelected)))")
  print()
}
