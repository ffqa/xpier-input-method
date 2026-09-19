#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""主词库 import_tables 里保证有自有词表（默认 wubi86_xpier）。

背景：加字加词都进 dict/wubi86_xpier.dict.yaml（咱们自己仓），构建时拷进
data/plum；但主词库（上游原样拷过来）得 import 它才会一起编译 —— 就是这一行：

    import_tables:
      - wubi86_jidian_user
      - wubi86_xpier               # ← 保证有这一行

用法: python3 tools/patch_wubi_overlay_import.py <wubi86_jidian.dict.yaml> [表名...]
幂等：已有就不动。
"""
import sys
from pathlib import Path

DEFAULT_TABLES = ["wubi86_xpier"]


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_wubi_overlay_import.py <wubi86_jidian.dict.yaml> [表名...]", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    tables = sys.argv[2:] or DEFAULT_TABLES
    if not path.exists():
        print("error: %s 不存在（需先执行 wubi86-data 拷码表）" % path, file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    have = set()
    anchor = None
    j = None  # import 段内最后一个 "- " 行，插它后面
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("import_tables:"):
            anchor = i
        elif anchor is not None:
            if s.startswith("- "):
                have.add(s[2:].split()[0])
                j = i
            elif s and not s.startswith("#"):
                break  # import 段结束（后面 encoder/rules 里也有 "- "，不许越界）
    if anchor is None or j is None:
        print("error: 找不到 import_tables 段", file=sys.stderr)
        return 1

    missing = [t for t in tables if t not in have]
    if not missing:
        print("ok: import_tables 已有 %s，跳过" % ", ".join(tables))
        return 0
    ins = "".join("  - %-32s # Xpier 自有词表（dict/ 目录，构建期挂入）\n" % t for t in missing)
    lines.insert(j + 1, ins)
    path.write_text("".join(lines), encoding="utf-8")
    print("ok: import_tables 已挂入 %s" % ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
