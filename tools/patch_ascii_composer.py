#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""FR-3: 构建期固定 Shift 键的提交行为（防止「按 Shift 出首字」回归）。

librime 的 AsciiComposer 依据 default.yaml 的 ascii_composer/switch_key 决定
「有编码时」按下 Shift 的动作：
  inline_ascii -> 进入临时英文模式
  commit_text  -> ConfirmCurrentSelection()，提交当前选中的候选（= 上屏首字）
  commit_code  -> ClearNonConfirmedComposition() + Commit()，提交原始编码（= 原样输出编码）

上游 default.yaml 给的是 Shift_L: inline_ascii / Shift_R: commit_text，
这正是「没选字按 Shift 却输出首字」的根因，因此在构建期强制改写为本机要求的：
  Shift_L / Shift_R = commit_code

本脚本只改这两行，其余绑定（Control_L/Control_R/Caps_Lock/Eisu_toggle）一律保留。
用法: python3 tools/patch_ascii_composer.py <default.yaml>
幂等：内容无需变化时不写文件（保持 mtime 稳定，避免每次构建都触发用户端重新部署）。
"""
import re
import sys
from pathlib import Path

WANT = (("Shift_L", "commit_code"), ("Shift_R", "commit_code"))


def main() -> int:
    path = Path(sys.argv[1])
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成默认配置）" % path, file=sys.stderr)
        return 1
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

    # 1) 定位顶层 ascii_composer: 段
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^ascii_composer:\s*$", ln):
            start = i
            break
    if start is None:
        text = "".join(lines)
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\nascii_composer:\n  switch_key:\n"
        for k, v in WANT:
            text += "    %s: %s\n" % (k, v)
        path.write_text(text, encoding="utf-8")
        print("ok: 无 ascii_composer 段，已追加 Shift_L/Shift_R = commit_code")
        return 0

    # 段结束 = 下一个顶格非空行
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].strip() and not lines[j][:1].isspace():
            end = j
            break

    # 2) 定位 switch_key:
    sw = None
    for j in range(start + 1, end):
        if re.match(r"^\s+switch_key:\s*$", lines[j]):
            sw = j
            break
    if sw is None:
        ins = ["  switch_key:\n"] + ["    %s: %s\n" % (k, v) for k, v in WANT]
        lines[start + 1:start + 1] = ins
        path.write_text("".join(lines), encoding="utf-8")
        print("ok: 已插入 ascii_composer/switch_key (Shift_L/Shift_R = commit_code)")
        return 0

    # switch_key 子段结束 = 缩进回到 <= 2 的行
    sw_end = end
    for j in range(sw + 1, end):
        if lines[j].strip() and (len(lines[j]) - len(lines[j].lstrip())) <= 2:
            sw_end = j
            break

    # 3) 改写 Shift_L / Shift_R
    remaining = [list(kv) for kv in WANT]
    changed = []
    for j in range(sw + 1, sw_end):
        m = re.match(r"^(\s+)(Shift_L|Shift_R):\s*(\S*)\s*$", lines[j])
        if not m:
            continue
        indent, key, old = m.group(1), m.group(2), m.group(3)
        want = dict(WANT)[key]
        remaining = [kv for kv in remaining if kv[0] != key]
        if old == want:
            continue
        lines[j] = "%s%s: %s\n" % (indent, key, want)
        changed.append("%s: %s -> %s" % (key, old, want))

    for k, v in remaining:
        lines.insert(sw_end, "    %s: %s\n" % (k, v))
        sw_end += 1
        changed.append("%s: (缺失) -> %s" % (k, v))

    if changed:
        path.write_text("".join(lines), encoding="utf-8")
        print("ok: 已固定 Shift 提交行为 -> " + "; ".join(changed))
    else:
        print("ok: Shift_L/Shift_R 已是 commit_code，跳过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
