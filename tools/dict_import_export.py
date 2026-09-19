#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FR-5 词库导入/导出工具（v1，纯文本层）

原理：
  极点 86 方案的用户词存储在文本词库 wubi86_jidian_user.dict.yaml（被主码表
  import_tables 引入，librime 部署时编译）。本工具在该文本层做导入/导出，
  无需改动 librime userdb；FR-4 的动态词频(userdb)另行处理（enable_user_dict 相关）。

词条规范（librime .dict.yaml）：
  字词<TAB>编码[<TAB>权重]   （编码为 a-z；'#' 注释行与 '##' 分组行原样保留）

极点导出常见两种顺序，本工具自动识别：  "编码 字词" 或 "字词 编码"（空白分隔）。

用法：
  python3 tools/dict_import_export.py import <极点导出.txt> <用户词库.yaml> [--invert]
  python3 tools/dict_import_export.py export <用户词库.yaml>
"""
import re
import sys
from pathlib import Path

CODE_RE = re.compile(r"^[a-z]{1,6}$")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")

def parse_entries(path: Path) -> set:
    """从用户词库中提取 (text, code) 集合，忽略注释/分组/头部。"""
    entries = set()
    in_body = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip("\r")
        if not in_body:
            if line == "...":
                in_body = True
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 2 and not parts[0].startswith("#") and re.match(r"^[a-z]{1,6}$", parts[1]):
            entries.add((parts[0].strip(), parts[1].strip()))
    return entries

def normalize_polaris_line(line: str):
    """极点导出行 → (text, code) 或 None。自动识别顺序。"""
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = re.split(r"[\t ]+", line, maxsplit=2)
    if len(parts) < 2:
        return None
    a, b = parts[0], parts[1]
    if CODE_RE.match(a) and CJK_RE.search(b):
        return (b.strip(), a)
    if CODE_RE.match(b) and CJK_RE.search(a):
        return (a.strip(), b)
    return None

def do_import(src: Path, dst: Path, invert: bool) -> int:
    existing = parse_entries(dst)
    added, skipped = 0, 0
    body = dst.read_text(encoding="utf-8")
    additions = []
    for raw in src.read_text(encoding="utf-8").splitlines():
        item = normalize_polaris_line(raw)
        if item is None:
            continue
        if invert:
            item = (item[1], item[0])
        # 保证 (字词, 编码) 顺序存储
        if not (CJK_RE.search(item[0]) and CODE_RE.match(item[1])):
            item = (item[1], item[0])
        if item in existing:
            skipped += 1
            continue
        existing.add(item)
        additions.append(f"{item[0]}\t{item[1]}")
        added += 1
    if additions:
        sep = "" if body.endswith("\n") else "\n"
        with dst.open("a", encoding="utf-8") as fh:
            fh.write(sep + "\n".join(additions) + "\n")
    return added, skipped

def do_export(path: Path) -> None:
    body = path.read_text(encoding="utf-8")
    in_body = False
    for raw in body.splitlines():
        line = raw.rstrip("\r")
        if not in_body:
            if line == "...":
                in_body = True
            continue
        if line and not line.startswith("#"):
            parts = line.split("\t")
            if len(parts) >= 2:
                print(f"{parts[0]}\t{parts[1]}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "import" and len(sys.argv) >= 4:
        added, skipped = do_import(Path(sys.argv[2]), Path(sys.argv[3]), "--invert" in sys.argv)
        print(f"imported={added} skipped_dup={skipped} -> {sys.argv[3]}")
    elif cmd == "export" and len(sys.argv) >= 3:
        do_export(Path(sys.argv[2]))
    else:
        sys.exit(__doc__)
