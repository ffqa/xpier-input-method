#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建期给五笔方案加上 z 万能键。

背景：五笔 86 的编码只用 a–y，z 空着。当年 极点五笔 就把 z 当万能键 ——
某一位记不清时用 z 代替，例如记得 t ? f u，就输 tzfu，把所有形如 t?fu 的字列出来。
本机此前**完全没有**这个功能：实测 tzfu 出 0 个候选，只有 tffu 能出字。

为什么不用 librime 现成的机制：
  · table_translator 只会拿整串去精确查表（src/rime/gear/table_translator.cc
    的 Query 里直接 dict_->LookupWords(code)），查询期没有通配逻辑；
  · speller/algebra 是在**编译词典时**改编码的（src/rime/dict/dict_compiler.cc
    第 310 行起），不是改用户输入 —— 所以「把 z 派生到 a-y」那种写法完全无效，
    方向反了；
  · 正确的方向是反过来：给每个编码再派生一条「把某一位换成 z」的别名。
    derive 的语义正是「在原有编码基础上增加新的编码」，编译进 prism 后，
    输 tzfu 就能查到 tffu 那一批词条。

只做第 2/3/4 位，不做第 1 位：第一位以 z 开头的输入已经被
recognizer/patterns/reverse_lookup（^z[a-z]*'?$）整体吃掉，用作拼音反查
（不会写的字先打 z 再打拼音，查出它的五笔码）。两者不能同时占用第一位。

代价：prism（编码索引）从约 650KB 涨到约 8MB，table.bin 不变。
      内存和部署时间都略有增加，实测可以接受。

用法: python3 tools/patch_wubi_wildcard.py <wubi86_jidian.schema.yaml>
幂等：内容无需变化时不写文件（保持 mtime 稳定，避免每次构建都触发用户端重新部署）。
"""
import re
import sys
from pathlib import Path

# (正则, 替换) —— 逐位把某一位换成 z。
# 不加 $ 锚尾，是为了让 3 位/4 位编码也都能匹配到对应位置。
# (正则, 注释)
RULES = [
    ("derive/^([a-y])[a-y]/$1z/",
     "第 2 位万能键：输 tzfu 列出所有形如 t?fu 的词条"),
    ("derive/^([a-y])([a-y])[a-y]/$1$2z/",
     "第 3 位万能键：输 tfzu 列出所有形如 tf?u 的词条"),
    ("derive/^([a-y])([a-y])([a-y])[a-y]/$1$2$3z/",
     "第 4 位万能键：输 tffz 列出所有形如 tff? 的词条"),
]


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_wubi_wildcard.py <wubi86_jidian.schema.yaml>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成方案文件）" % path, file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

    # 定位顶层 speller: 段
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^speller:\s*$", ln):
            start = i
            break
    if start is None:
        print("error: 方案里没有顶层 speller: 段", file=sys.stderr)
        return 1

    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].strip() and not lines[j][:1].isspace():
            end = j
            break

    want = ["    - \"%s\"   # %s\n" % (rule, note) for rule, note in RULES]

    # 已经有 algebra 就整体替换（保持幂等）
    alg = None
    for j in range(start + 1, end):
        if re.match(r"^\s+algebra:\s*$", lines[j]):
            alg = j
            break

    if alg is None:
        lines[end:end] = ["  algebra:\n"] + want
        path.write_text("".join(lines), encoding="utf-8")
        print("ok: 已写入 speller/algebra（%d 条万能键规则）" % len(RULES))
        return 0

    alg_end = end
    for j in range(alg + 1, end):
        if lines[j].strip() and (len(lines[j]) - len(lines[j].lstrip())) <= 2:
            alg_end = j
            break

    if lines[alg + 1:alg_end] == want:
        print("ok: speller/algebra 已是万能键规则，跳过")
        return 0
    lines[alg + 1:alg_end] = want
    path.write_text("".join(lines), encoding="utf-8")
    print("ok: 已更新 speller/algebra（%d 条万能键规则）" % len(RULES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
