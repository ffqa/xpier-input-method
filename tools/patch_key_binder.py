#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建期去掉 Ctrl+Shift+数字 开关组（numbered_mode_switch）。

背景：default.yaml 的 key_binder 用 __patch 引入了
key_bindings:/numbered_mode_switch，里面是：
  Ctrl+Shift+2 切 ascii_mode / 3 切 full_shape / 4 切 simplification / 5 切 extended_charset
  （外加 exclam/at/numbersign/dollar/percent 五个符号双胞胎）
这组键在终端复用器（tmux/cmux 之类重度 Ctrl+Shift 用户）里随手就按出来，
属于「隐形平行开关」：
  - 它调的是 set_option 直写会话，不落盘、不经过菜单，菜单勾和实际对不上；
  - 其中 simplification 还是个死开关（本方案 simplifier 认的是 zh_trad，
    simplification 没人读，按了什么都不发生，纯 confusion）；
  - full_shape 被误触就是「卡在全角退不出」的循环：菜单关了，按键又打开。
菜单现在是唯一的控制面（能点、能看勾、能落盘），这组键盘暗门直接拆掉。
保留 .next（单方案下无害）？不：整组引用只此一行，去掉该行即全组失效，
emacs_editing / 两个 paging 组不受影响。
用法: python3 tools/patch_key_binder.py data/plum/default.yaml
幂等：内容无需变化时不写文件。
"""
import re
import sys
from pathlib import Path

DROP = "key_bindings:/numbered_mode_switch"


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: patch_key_binder.py <default.yaml>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    if not path.exists():
        print("error: %s 不存在（需先执行 plum-data 生成默认配置）" % path, file=sys.stderr)
        return 1
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    kept = [ln for ln in lines if DROP not in ln]
    if len(kept) == len(lines):
        print("ok: 已无 %s 引用，跳过" % DROP)
        return 0
    # 自检：只允许删引用行，且 key_binder 段里必须还剩其它引用（别把整段掏空）。
    removed = [ln for ln in lines if DROP in ln]
    assert all(re.match(r"^\s*-\s*key_bindings:/numbered_mode_switch\s*$", ln) for ln in removed), \
        "只删整行引用，不碰其它内容：%r" % removed
    path.write_text("".join(kept), encoding="utf-8")
    print("ok: 已去掉 %d 行 %s" % (len(removed), DROP))
    return 0


if __name__ == "__main__":
    sys.exit(main())
