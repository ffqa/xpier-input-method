#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""FR-1: 构建期把 wubi86_jidian 设为分发 default.yaml 的首选方案。

用法: python3 tools/patch_default_schema.py <default.yaml> wubi86_jidian
幂等：已存在则不改；schema_list 缺失则追加。
"""
import re
import sys
from pathlib import Path

def main() -> int:
    path, schema = Path(sys.argv[1]), sys.argv[2]
    if not path.exists():
        print(f"error: {path} 不存在（需先执行 plum-data 生成默认配置）", file=sys.stderr)
        return 1
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if any(re.search(r"^\s*-\s+schema:\s*" + re.escape(schema) + r"\s*$", ln) for ln in lines):
        print(f"ok: {schema} 已在 schema_list 中，跳过")
        return 0
    for i, ln in enumerate(lines):
        if re.match(r"^schema_list:\s*$", ln):
            indent = "  "
            # 找到列表中首个元素行以确定缩进（若列表为空则用 2 空格）
            for j in range(i + 1, len(lines)):
                if re.match(r"^\s*-\s+", lines[j]):
                    indent = re.match(r"^(\s*)", lines[j]).group(1)
                    break
                if lines[j].strip() and not lines[j].startswith(("#", " ")):
                    break
            lines.insert(i + 1, f"{indent}- schema: {schema}\n")
            path.write_text("".join(lines), encoding="utf-8")
            print(f"ok: 已将 {schema} 插入 schema_list 首位")
            return 0
    # 无 schema_list：追加
    with path.open("a", encoding="utf-8") as fh:
        fh.write(f"\nschema_list:\n  - schema: {schema}\n")
    print(f"ok: 文件无 schema_list，已追加 {schema}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
