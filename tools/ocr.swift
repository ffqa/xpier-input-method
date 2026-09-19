// tools/ocr.swift —— 设置界面离屏截图的 Vision 文字识别工具。
//
// 为什么需要它：当前模型没有视觉能力，describe_image 也没配后端，
// 设置截图只能靠 OCR 读文字 + 归一化坐标（同一行的标签和控件，midY 应该几乎相等，
// 可用来判断基线对齐）。配 tools/png_ascii.py 做字符画/逐行像素剖析。
//
// 构建：swiftc -o /tmp/ocr tools/ocr.swift -framework Vision -framework AppKit
// 用法：/tmp/ocr /tmp/shots/01-外观22.png
//
// 注意：编译产物放 /tmp（或别处），不要提交二进制，只版本管理本源码文件。
import Foundation
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else { print("usage: ocr <image>"); exit(1) }
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  print("无法读取图片: \(path)"); exit(1)
}
print("图片尺寸: \(cg.width) x \(cg.height)")
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
req.usesLanguageCorrection = false
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([req])
let obs = req.results ?? []
print("识别到 \(obs.count) 段文字\n")
// 按 y 从高到低（即从上到下）排序后再打印
let sorted = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
for o in sorted {
  guard let c = o.topCandidates(1).first else { continue }
  let b = o.boundingBox
  print(String(format: "y=%.3f x=%.3f w=%.3f  conf=%.2f  | %@",
               b.midY, b.minX, b.width, c.confidence, c.string))
}
