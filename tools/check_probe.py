#!/usr/bin/env python3
"""probe 矩阵断言：读 rime_probe 的输出，不过就 exit 1。

用法：rime_probe ... > probe.log 2>&1 && python3 tools/check_probe.py probe.log
断言（ Transaction: 2026-09-17 probe 实测）：
  tffu 第一候选是“等”（基本打字）；tzfu 第一是“徒劳无益”（z 万能键）；
  zni 第一是“你”（z 开头拼音反查）。
多字节比较用 python（grep/cut 对 UTF-8 不可靠，见交接文档雷区）。
"""
import re
import sys

EXPECT = {
    "tffu": "等",
    "tzfu": "徒劳无益",
    "zni": "你",
}

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/probe-test.log"
text = open(path, encoding="utf-8", errors="replace").read()

sections = re.split(r'===\s*输入\s*"([^"]+)"\s*===', text)
# sections[0] 是文件头，随后 key/body 交替
found = {}
for i in range(1, len(sections) - 1, 2):
    key, body = sections[i], sections[i + 1]
    m = re.search(r"^\s*1\.\s*(\S+)", body, re.M)
    found[key] = m.group(1) if m else None

failed = 0
for key, want in EXPECT.items():
    got = found.get(key)
    if got == want:
        print(f"  ✔ {key} → {got}")
    else:
        failed += 1
        print(f"  ✘ {key}：期望 {want}，实际 {got}")

if failed:
    print(f"✘ {failed} 项没过（完整输出见 {path}）。")
    sys.exit(1)
print("✔ 探针矩阵全过。")
