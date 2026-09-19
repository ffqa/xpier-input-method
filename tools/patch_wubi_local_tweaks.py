#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把原来对码表仓库的 4 处本地修改，转成构建期补丁。

背景：以前这 4 处是直接改上游文件（rime-wubi86-jidian 的 5 个本地提交），
代价是码表仓库必须 fork，否则陌生人 clone 到的是纯上游、行为不对还不报错。
现在上游保持纯净，这 4 处每次构建现打：

1. zh_trad 去掉 reset: 0 —— librime 建引擎先 RestoreSavedOptions（读存档）
   再 InitializeOptions（带 reset 的强制复位），写了等于每个新输入框都把
   繁体掰回简体，「点了也白点」。ascii_mode 的 reset: 0 是故意的（回中文）。
2. translator/enable_charset_filter: true -> false —— 五笔精确码不需要
   拼音那层过滤，过滤只会拦扩展区字（如 𡋤）。想滤回去设置里有「只出常用字」。
3. translator/enable_user_dict: false -> true —— 用户词典记动态字词频，
   置顶等功能的前置条件。
4. punctuator 补 full_shape/half_shape：\\ -> 、，/ -> ／（半角）——
   中文里敲这两个键直出中文标点，不断行。

用法: python3 tools/patch_wubi_local_tweaks.py <wubi86_jidian.schema.yaml>
幂等：已是目标状态就只打印跳过，不写文件（上游改了措辞也能对上，
因为匹配只认键和值，不认注释）。
"""
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_wubi_local_tweaks.py <wubi86_jidian.schema.yaml>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    if not path.exists():
        print("error: %s 不存在（需先执行 wubi86-data 拷码表）" % path, file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")
    orig = text

    # 1. zh_trad 去 reset: 0（只动 zh_trad 段内顶着 4 格缩进的那一行）。
    text, n1 = re.subn(
        r"(?m)(^  - name: zh_trad\n(?:^  [^\s-].*\n|^\s+#.*\n)*?)    reset: 0[^\n]*\n",
        r"\1",
        text,
    )
    print(("ok: 已去掉 zh_trad 的 reset: 0" if n1 else "ok: zh_trad 已无 reset，跳过"))

    # 2/3. translator 两处布尔值（限定在 translator 段内，顶格段结束为止）。
    def fix_translator(key: str, want: str) -> None:
        nonlocal text
        m = re.search(r"(?m)^translator:\n((?:^[ \t]+.*\n|\s*\n|\s*#.*\n)*)", text)
        if not m:
            print("error: 找不到 translator 段" % (), file=sys.stderr)
            sys.exit(1)
        seg = m.group(1)
        new_seg, n = re.subn(
            r"(?m)^(\s*%s:\s*)(true|false)(\s*(?:#.*)?)$" % re.escape(key),
            lambda mm: mm.group(1) + want + mm.group(3),
            seg,
            count=1,
        )
        if n and new_seg != seg:
            text = text[: m.start(1)] + new_seg + text[m.end(1):]
            print("ok: translator/%s 已改为 %s" % (key, want))
        else:
            print("ok: translator/%s 已是 %s，跳过" % (key, want))

    fix_translator("enable_charset_filter", "false")
    fix_translator("enable_user_dict", "true")

    # 4. punctuator 补中英文两套 \ 和 /（有就不动）。
    # 上游是光杆 import_preset，目标是在它后面跟两组映射（顺序无关，行为一致）。
    if '"/": "／"' in text:
        print("ok: punctuator 已有全角映射，跳过")
    else:
        lines = text.splitlines(keepends=True)
        hit = None
        for i, ln in enumerate(lines):
            if ln.startswith("punctuator:"):
                hit = i
                break
        done = False
        if hit is not None:
            for i in range(hit + 1, len(lines)):
                ln = lines[i]
                if re.match(r"^[^\s#]", ln):
                    break  # 顶格新段，punctuator 结束了
                if ln.startswith("  import_preset: default"):
                    block = ('  full_shape:\n    "\\\\": "、"\n    "/": "／"\n'
                             '  half_shape:\n    "\\\\": "、"\n    "/": "/"\n')
                    lines.insert(i + 1, block)
                    text = "".join(lines)
                    done = True
                    break
        print(("ok: punctuator 已补 full/half shape" if done else "warn: punctuator 段没对上，没改（检查上游格式）"))

    if text != orig:
        path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
