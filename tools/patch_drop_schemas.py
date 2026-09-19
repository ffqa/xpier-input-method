#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建期从 default.yaml 的 schema_list 里摘掉指定的输入方案。

背景：schema_list 里列着 quick5，但它时常没被 Xcode 拷进
SharedSupport（pbxproj 的 Copy 阶段里有它，包里却没有，疑似增量构建漏拷），
于是每次部署都报一条 missing input schema: quick5，无害但吵。
本机是自用五笔，速成并不需要，摘掉后方案选单也更干净。

和 patch_default_schema.py 的分工：那个负责「把 wubi86_jidian 放进首位」，
这个负责「把不需要的摘掉」。两个都是幂等的（无变化不写文件）。

用法: python3 tools/patch_drop_schemas.py <default.yaml> <schema...>
例:   python3 tools/patch_drop_schemas.py data/plum/default.yaml quick5
"""
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print("用法: patch_drop_schemas.py <default.yaml> <schema...>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    drop = set(sys.argv[2:])
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成默认配置）" % path, file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^schema_list:\s*$", ln):
            start = i
            break
    if start is None:
        print("ok: 文件无 schema_list，无需摘除")
        return 0

    end = len(lines)
    for j in range(start + 1, len(lines)):
        body = lines[j].strip()
        if not body or body.startswith("#"):
            continue
        if not lines[j][:1].isspace():
            end = j
            break

    kept, removed = [], []
    for ln in lines[start + 1:end]:
        m = re.match(r"^(\s*-\s*schema:\s*)(\S+)\s*$", ln)
        if m and m.group(2) in drop:
            removed.append(m.group(2))
            continue
        kept.append(ln)

    if not removed:
        print("ok: schema_list 里没有 %s，跳过" % ", ".join(sorted(drop)))
        return 0
    lines[start + 1:end] = kept
    path.write_text("".join(lines), encoding="utf-8")
    print("ok: 已从 schema_list 摘掉 " + ", ".join(removed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
