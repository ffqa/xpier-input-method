#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建期把方案里的 zh_trad 开关加入 switcher/save_options。

为什么需要：输入法菜单里新加了「输简出繁」这一项，直接改的是 Rime 的
zh_trad 选项。而 Rime 只会把 save_options 里列出的选项记住并跨会话保持，
其余选项每换一个输入框（新会话）就回到方案默认值 —— 表现就是
「在 A 里切成繁体，切到 B 又变回简体」，看着像没生效。

上游 default.yaml 的 save_options 已经有 full_shape / ascii_punct /
extended_charset，但没有 zh_trad（那是本方案自己起的开关名，
见 wubi86_jidian.schema.yaml 的 switches 与 tradition/option_name）。

用法: python3 tools/patch_save_options.py <default.yaml> [选项名...]
幂等：内容无需变化时不写文件（保持 mtime 稳定，避免每次构建都触发用户端重新部署）。
"""
import re
import sys
from pathlib import Path

DEFAULT_OPTIONS = ["zh_trad"]


def section_range(lines, name):
    """返回顶层段落 name: 的 [起, 止) 行号；找不到返回 (None, None)。"""
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^%s:\s*$" % re.escape(name), ln):
            start = i
            break
    if start is None:
        return None, None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].strip() and not lines[j][:1].isspace():
            end = j
            break
    return start, end


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_save_options.py <default.yaml> [选项名...]", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    wanted = sys.argv[2:] or DEFAULT_OPTIONS
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成默认配置）" % path, file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    s_start, s_end = section_range(lines, "switcher")
    if s_start is None:
        print("error: default.yaml 里没有顶层 switcher: 段", file=sys.stderr)
        return 1

    # save_options: 必须是 switcher 下的直接子项
    so = None
    for j in range(s_start + 1, s_end):
        if re.match(r"^  save_options:\s*$", lines[j]):
            so = j
            break
    if so is None:
        block = ["  save_options:\n"] + ["    - %s\n" % w for w in wanted]
        lines[s_start + 1:s_start + 1] = block
        path.write_text("".join(lines), encoding="utf-8")
        print("ok: switcher 下没有 save_options，已新建并写入 " + ", ".join(wanted))
        return 0

    # 列表结束 = 缩进回到 <= 2 的行
    so_end = s_end
    for j in range(so + 1, s_end):
        if lines[j].strip() and (len(lines[j]) - len(lines[j].lstrip())) <= 2:
            so_end = j
            break

    existing = set()
    for j in range(so + 1, so_end):
        m = re.match(r"^\s+-\s*(\S+)\s*$", lines[j])
        if m:
            existing.add(m.group(1))

    missing = [w for w in wanted if w not in existing]
    if not missing:
        print("ok: save_options 已包含 " + ", ".join(wanted) + "，跳过")
        return 0

    for w in missing:
        lines.insert(so_end, "    - %s\n" % w)
        so_end += 1
    path.write_text("".join(lines), encoding="utf-8")
    print("ok: save_options 补入 " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
