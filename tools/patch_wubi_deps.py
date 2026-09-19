#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建期给五笔方案补上 pinyin_simp 依赖，让 z 开头的拼音反查能用。

现象：方案里 reverse_lookup/dictionary 写的是 pinyin_simp，但
schema/dependencies 里那一行被上游注释掉了：

    dependencies:
    #    - pinyin_simp

后果是 rime 部署时根本不会去编译 pinyin_simp 这张码表，
反查翻译器运行时加载不到它 —— 输 z + 拼音什么都不会出。
（实测：修之前 zni → 0 候选；修之后 zni → 你/拟/尼/呢/泥，且每个都带五笔编码。）

注意不能用「把 pinyin_simp 加进 schema_list」来修：那样它会被当成一个
可选的输入方案出现在方案选单里。dependencies 才是正确的位置 ——
它只声明「本方案要用这张码表」，编译它，但不进选单。

用法: python3 tools/patch_wubi_deps.py <wubi86_jidian.schema.yaml> [依赖名...]
幂等：内容无需变化时不写文件。
"""
import re
import sys
from pathlib import Path

DEFAULT_DEPS = ["pinyin_simp"]


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_wubi_deps.py <schema.yaml> [依赖名...]", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    deps = sys.argv[2:] or DEFAULT_DEPS
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成方案文件）" % path, file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

    # 定位 schema: 段
    s_start = None
    for i, ln in enumerate(lines):
        if re.match(r"^schema:\s*$", ln):
            s_start = i
            break
    if s_start is None:
        print("error: 方案里没有顶层 schema: 段", file=sys.stderr)
        return 1
    # schema: 段结束 = 下一个顶格的非注释行。
    # 同样要跳过注释行 —— 上游那句被注释掉的依赖是顶格的，不跳会把它当成段落结束，
    # 于是它落在所有切片范围之外，永远清理不掉。
    s_end = len(lines)
    for j in range(s_start + 1, len(lines)):
        body = lines[j].strip()
        if not body or body.startswith("#"):
            continue
        if not lines[j][:1].isspace():
            s_end = j
            break

    dep = None
    for j in range(s_start + 1, s_end):
        if re.match(r"^  dependencies:\s*$", lines[j]):
            dep = j
            break

    if dep is None:
        lines[s_end:s_end] = ["  dependencies:\n"] + ["    - %s\n" % d for d in deps]
        path.write_text("".join(lines), encoding="utf-8")
        print("ok: 已新建 schema/dependencies，写入 " + ", ".join(deps))
        return 0

    # 依赖列表结束 = 缩进回到 <= 2 的非注释行。
    # 注意必须跳过注释行：上游把它写成了顶格的「#    - pinyin_simp」，
    # 缩进是 0 —— 不跳的话会被当成段落结束，那行就永远清理不掉。
    dep_end = s_end
    for j in range(dep + 1, s_end):
        body = lines[j].strip()
        if not body or body.startswith("#"):
            continue
        if (len(lines[j]) - len(lines[j].lstrip())) <= 2:
            dep_end = j
            break

    active = set()
    for j in range(dep + 1, dep_end):
        m = re.match(r"^\s+-\s*(\S+)\s*$", lines[j])
        if m:
            active.add(m.group(1))

    missing = [d for d in deps if d not in active]

    # 顺手删掉被注释掉的同名行，免得看着像「已经配了」
    cleaned = [ln for ln in lines[dep + 1:dep_end]
               if not re.match(r"^\s*#\s*-\s*(\S+)\s*$", ln) or
               re.match(r"^\s*#\s*-\s*(\S+)\s*$", ln).group(1) not in deps]
    changed_body = cleaned != lines[dep + 1:dep_end]

    if not missing and not changed_body:
        print("ok: schema/dependencies 已包含 " + ", ".join(deps) + "，跳过")
        return 0

    lines[dep + 1:dep_end] = cleaned + ["    - %s\n" % d for d in missing]
    path.write_text("".join(lines), encoding="utf-8")
    print("ok: schema/dependencies 写入 " + ", ".join(missing or deps))
    return 0


if __name__ == "__main__":
    sys.exit(main())
