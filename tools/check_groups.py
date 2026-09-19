#!/usr/bin/env python3
"""核对 subGroups 分组表与 app 实际解析出的配置项是否逐字对齐。

为什么需要它：分组表是手写的，配置项是 app 解析出来的。两者一旦不一致，
界面底部就会冒出一个叫「其他」的兜底块，里面全是 style/xxx 这种原始路径 ——
而且只有人肉看截图才发现得了。这个脚本把这件事变成一条命令。

还要注意分工：决定一项属于哪个标签页的是 groupTitle()，不是 subGroups。
往 subGroups 里写一个不属于本页的键没有任何效果，那一项仍留在原页 ——
表现为「分组表里明明写了，界面上却没有」。本脚本只查「页内分组是否覆盖完整」。

用法：check_groups.py [settings-list.tsv]
不给参数时自己去跑 app 的 --settings-list。
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / 'squirrel-fork/build/Build/Products/Debug/Xpier.app/Contents/MacOS/Xpier'
SRC = ROOT / 'squirrel-fork/sources/SquirrelApplicationDelegate.swift'

# 标题里可能有空格和括号，键里可能有 " 和 \ 的转义
BLOCK_RE = re.compile(r'\("([^"]+)",\s*(?:true|false),\s*\[(.*?)\]\)', re.S)
TAB_RE = re.compile(r'"([^"]+)": \[\n(.*?)\n    \],', re.S)


def load_rows(path=None):
    if path:
        text = pathlib.Path(path).read_text(encoding='utf-8')
    else:
        text = subprocess.run([str(APP), '--settings-list'],
                              capture_output=True, text=True).stdout
    rows = []
    for line in text.split('\n'):
        f = line.split('\t')
        if len(f) >= 5 and line.strip():
            rows.append({'tab': f[0], 'path': f[2], 'type': f[3]})
    return rows


def load_blocks():
    src = SRC.read_text(encoding='utf-8')
    start = src.index('private static let subGroups')
    body = src[start:src.index('\n  ]', start)]
    out = {}
    for tab, blk in TAB_RE.findall(body):
        blocks = []
        for title, keys in BLOCK_RE.findall(blk):
            keys = re.findall(r'"((?:[^"\\]|\\.)*)"', keys)
            blocks.append((title, [k.replace('\\"', '"').replace('\\\\', '\\') for k in keys]))
        out[tab] = blocks
    return out


def main():
    rows = load_rows(sys.argv[1] if len(sys.argv) > 1 else None)
    blocks = load_blocks()
    paths = {}
    for r in rows:
        paths.setdefault(r['tab'], set()).add(r['path'])

    bad = 0
    for tab in sorted(paths):
        real = paths[tab]
        blks = blocks.get(tab)
        if not blks:
            print(f'  · {tab}（{len(real)} 项）未分组，按平铺渲染')
            continue
        listed = set()
        for _, keys in blks:
            listed |= set(keys)
        missing, extra = real - listed, listed - real
        print(f'  {"✔" if not missing and not extra else "✘"} {tab}'
              f'（{len(real)} 项，{len(blks)} 组）')
        if missing:
            bad = 1
            print('      漏掉（会掉进「其他」块）：')
            for m in sorted(missing):
                print('        ', m)
        if extra:
            bad = 1
            print('      分组表里多写、实际不存在的键：')
            for e in sorted(extra):
                print('        ', e)
    unknown = set(blocks) - set(paths)
    if unknown:
        bad = 1
        print('  ✘ 分组表里的这些页 app 里没有：', sorted(unknown))
    print()
    print('全部对齐' if not bad else '有不一致 —— 改 subGroups 后重跑')
    sys.exit(bad)


if __name__ == '__main__':
    main()
