#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建期给五笔方案挂上 reverse_lookup_filter，让候选后面显示它的五笔编码。

需求原话：「非首字符，并且输入 z 后，应该需要显示编码，这样才能让用户知道
正确的编码，方便以后可以记住该编码。」

先用 rime_probe 实测过效果（这是唯一可信的验证手段，见 tools/rime_probe.c）：

    输入 tzfu  →  徒劳无益 tafu / 等 tffu / 徒增 tffu / 生境 tgfu / 处境 thfu

为什么不用 translator/comment_format：码表里**根本没有注释这一列**。
把编译好的 wubi86_jidian.table.bin 反编译出来看，每行只有「词条 / 编码 / 权重」，
DictEntry.comment 始终为空，所以 comment_format 无论怎么写都变不出编码来。

reverse_lookup_filter 走的是另一条路：拿到候选的文字，回主码表反查它的编码，
再写进 comment。这一步是纯配置，不用改引擎。

只在输入含 z 时显示：wubi_code 块里再加一行 show_if_input_contains: "z"。
引擎侧 ReverseLookupFilter::AppliesToSegment 会看当前段的输入里有没有 z，
有才挂 filter，没有就跳过 —— 首位 z（拼音反查 zni）和中间位 z（万能键 tzfu）
都显示编码，平时打字（tffu/ni）完全干净。注意这是 librime 源码改动
（src/rime/gear/reverse_lookup_filter.*），改完要重编 librime 并重新打包
App 才生效；旧引擎会忽略这个不认识的键，保持常显。

用法: python3 tools/patch_wubi_code_hint.py <wubi86_jidian.schema.yaml> [主码表名]
幂等：内容无需变化时不写文件。
"""
import re
import sys
from pathlib import Path

FILTER = "reverse_lookup_filter@wubi_code"


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_wubi_code_hint.py <schema.yaml> [主码表名]", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    dict_name = sys.argv[2] if len(sys.argv) > 2 else "wubi86_jidian"
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成方案文件）" % path, file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    changed = []

    def section(name):
        start = None
        for i, ln in enumerate(lines):
            if re.match(r"^%s:\s*$" % re.escape(name), ln):
                start = i
                break
        if start is None:
            return None, None
        end = len(lines)
        for j in range(start + 1, len(lines)):
            body = lines[j].strip()
            if not body or body.startswith("#"):
                continue
            if not lines[j][:1].isspace():
                end = j
                break
        return start, end

    # 1) engine/filters 追加
    e_start, e_end = section("engine")
    if e_start is None:
        print("error: 方案里没有顶层 engine: 段", file=sys.stderr)
        return 1
    f_start = f_end = None
    for j in range(e_start + 1, e_end):
        if re.match(r"^  filters:\s*$", lines[j]):
            f_start = j
            break
    if f_start is None:
        lines[e_end:e_end] = ["  filters:\n", "    - %s\n" % FILTER]
        changed.append("新建 engine/filters")
    else:
        # 列表结束的位置 = 最后一个列表项之后。
        # 不能简单取「本段结束」，因为 filters 下面跟着一大段注释，
        # 那样会把新项插到注释后面 —— YAML 上仍能解析，但看着像写坏了。
        f_end = f_start + 1
        for j in range(f_start + 1, e_end):
            body = lines[j].strip()
            if not body or body.startswith("#"):
                continue          # 空行/注释不改变列表归属
            if re.match(r"^\s+-\s", lines[j]):
                f_end = j + 1     # 还是列表项，插到它后面
                continue
            f_end = j             # 遇到别的键，列表到此为止
            break
        if not any(FILTER in lines[j] for j in range(f_start + 1, f_end)):
            lines[f_end:f_end] = ["    - %s\n" % FILTER]
            changed.append("engine/filters 追加 " + FILTER)

    # 2) 顶层 wubi_code: 配置块
    w_start, w_end = section("wubi_code")
    want = [
        "wubi_code:\n",
        "  tags: [abc]\n",
        "  overwrite_comment: true\n",
        "  dictionary: %s\n" % dict_name,
        "  show_if_input_contains: \"z\"\n",
    ]
    if w_start is None:
        # 插到文件末尾之前；rime 不要求顺序
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append("\n")
        lines.extend(want)
        changed.append("新建 wubi_code 配置块")
    elif lines[w_start:w_end] != want:
        lines[w_start:w_end] = want
        changed.append("更新 wubi_code 配置块")

    if not changed:
        print("ok: 编码提示已配置，跳过")
        return 0
    path.write_text("".join(lines), encoding="utf-8")
    print("ok: " + "; ".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
