# -*- coding: utf-8 -*-
"""从随包数据枚举全部生效配置，生成 docs/全部设置清单.md（与 App 内解析逻辑一致）。

用法: python3 tools/gen_settings_doc.py
"""
import os, io
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent  # 本仓库根，输出与输入都在里面，不依赖外部目录
ROOT = str(REPO)
SHARED = os.path.join(ROOT, "dist/Xpier.app/Contents/SharedSupport")

# 与 App 内 V10 parseFile 完全一致：只挡编译期指令与方案身份元数据，
# 其余全部列出（需求是「所有配置都能编辑」）。
SKIP = set(["__build_info", "schema"])

def group_title(fname, section):
    """与 App 内 groupTitle 完全一致：把碎段落并成有意义的标签页。

    原始 YAML 段落很碎（status_icon / menu / key_binder / recognizer 各自只有 1~3 项），
    一段一页会出现一堆「只有 1 个选项」的标签页。这里按「用户想干什么」归并，
    并允许跨层合并（selector 只在通用层，recognizer 方案层与通用层都有）。
    """
    if section in ("style", "status_icon"):
        return "外观"
    if section in ("speller", "translator", "menu", "ascii_composer",
                   "key_binder", "selector", "switcher"):
        return "输入 · 按键 · 方案"
    if section in ("punctuator", "tradition"):
        return "标点与简繁"
    if section in ("reverse_lookup", "recognizer", "repeat_last_input"):
        return "反查与造词"
    if section == "preset_color_schemes":
        return "主题配色"
    if section == "app_options":
        return "常用 APP 关联"
    return {"schema": "方案", "default": "通用"}.get(fname, "外观") + " · " + section


GROUP_ORDER = ["外观", "输入 · 按键 · 方案", "标点与简繁",
               "反查与造词", "主题配色", "常用 APP 关联"]

def yaml_unquote(s):
    t = s.strip()
    if len(t) < 2 or t[0] != t[-1]:
        return t
    if t[0] == "'":
        return t[1:-1].replace("''", "'")
    if t[0] != '"':
        return t
    table = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"'}
    out = []
    esc = False
    for ch in t[1:-1]:
        if esc:
            out.append(table.get(ch, ch)); esc = False
        elif ch == "\\":
            esc = True
        else:
            out.append(ch)
    return "".join(out)

NOTE = {
 "style/color_scheme": "浅色主题；共 22 个预设可选",
 "style/color_scheme_dark": "深色主题（跟随系统外观时使用）",
 "style/candidate_list_layout": "linear=横排 / stacked=竖排",
 "style/text_orientation": "horizontal=横排文字 / vertical=竖排文字",
 "style/inline_preedit": "候选直接嵌在光标处显示（内嵌编码）",
 "style/inline_candidate": "内嵌显示首选候选",
 "style/memorize_size": "记住每个输入框的候选窗大小",
 "style/mutual_exclusive": "候选窗与内嵌编码互斥显示",
 "style/translucency": "候选窗半透明",
 "style/show_paging": "候选窗显示翻页按钮",
 "style/corner_radius": "候选窗圆角",
 "style/hilited_corner_radius": "选中项圆角，0=方角",
 "style/border_height": "上下边框留白，负数=按字号推算",
 "style/border_width": "左右边框留白，负数=按字号推算",
 "style/line_spacing": "候选行间距（竖排时明显）",
 "style/spacing": "候选之间水平间距",
 "style/shadow_size": "候选窗阴影，0=无",
 "style/font_face": "候选字体",
 "style/font_point": "候选字号（本机重点需求项）",
 "status_icon/show": "菜单栏显示中/英状态图标",
 "menu/page_size": "每页候选数",
 "speller/max_code_length": "五笔四码上屏",
 "speller/auto_select": "四码唯一时自动上屏",
 "translator/dictionary": "所用码表",
 "translator/enable_charset_filter": "过滤生僻字（常用字集）",
 "translator/enable_completion": "显示未输完整编码的词条（联想）",
 "translator/enable_sentence": "句子输入模式（五笔应保持关闭）",
 "translator/enable_user_dict": "用户词典：记录字词频与自造词（即时调频的基础）",
 "translator/enable_encoder": "自动造词",
 "translator/encode_commit_history": "把已上屏内容自动造成词",
 "tradition/opencc_config": "简转繁所用 OpenCC 方案",
 "tradition/option_name": "对应的开关名（zh_trad）",
 "ascii_composer/good_old_caps_lock": "Caps Lock 行为兼容旧习惯",
 "ascii_composer/switch_key/Shift_L": "commit_code=原样输出编码（本机要求）",
 "ascii_composer/switch_key/Shift_R": "commit_code=原样输出编码（本机要求）",
 "ascii_composer/switch_key/Caps_Lock": "clear=大写锁定时清空未上屏编码",
 "switcher/caption": "方案选单标题",
 "switcher/fold_options": "方案选单折叠开关项",
 "switcher/abbreviate_options": "方案选单缩写开关项",
 "switcher/option_list_separator": "方案选单分隔符",
}

APP_NOTE = {
 "ascii_mode": "在该 App 中默认英文输入",
 "no_inline": "该 App 中不显示内嵌编码",
 "inline": "该 App 中强制显示内嵌编码",
 "vim_mode": "Vim 模式（Esc 切英文）",
 "force_marked_text_for_direct_commit": "终端类直接提交（兼容用）",
}

rows = []

def parse_file(path, fname, layer):   # noqa: 已停用，见下方 dump_from_app 的说明
    if not os.path.exists(path):
        return
    t = io.open(path, encoding="utf-8").read()
    section = ""; sub = ""
    seq_indent = -1   # 列表项内部字段属于元素，不是配置项（如 switches 下的 reset）
    for raw in t.split("\n"):
        tr = raw.strip()
        if not tr or tr.startswith("#"):
            continue
        ind = len(raw) - len(raw.lstrip())
        if tr.startswith("-"):
            seq_indent = ind
            continue
        if seq_indent >= 0:
            if ind > seq_indent:
                continue
            seq_indent = -1
        if ":" not in tr:
            continue
        c = tr.index(":")
        key = tr[:c].strip()
        val = tr[c + 1:].strip()
        if val == "":
            if ind == 0:
                section = yaml_unquote(key); sub = ""
            elif ind == 2:
                sub = yaml_unquote(key)
            continue
        if val.startswith("#"):
            continue
        if " #" in val:
            val = val.split(" #")[0].strip()
        if val == "":
            continue
        key = yaml_unquote(key)
        raw_val = val   # 解码前先留一份：判断流式集合必须看原文是否带引号
        val = yaml_unquote(val)
        if section == "" or section in SKIP:
            continue
        if section.startswith("__") or sub.startswith("__") or key.startswith("__"):
            continue
        # 键里含 "/" 的项无法用点路径寻址：Rime 的 patch 路径就以 "/" 作分隔符，
        # 且无转义写法。如标点映射里键本身是 "/" 的两条，写进 patch 会解析成多一层空键。
        if "/" in key:
            continue
        # 带引号的标量即使以 [ { 开头也不是流式集合：
        # recognizer 的 uppercase 值 "[A-Z]…"、style 的 candidate_format 值 "[label]…"
        # 都是这种，只看解码值会误删。
        if not (raw_val.startswith('"') or raw_val.startswith("'")) and \
           (val.startswith("{") or val.startswith("[")):
            continue
        p = section + "/" + key
        if ind >= 4 and sub:
            p = section + "/" + sub + "/" + key
        if fname == "schema":
            p = section + "/" + (key if not sub else sub + "/" + key)
        rows.append((layer, group_title(fname, section), p, val))

# 配置项一律以 App 自己吐出的数据为准：
#     Xpier.app/Contents/MacOS/Xpier --settings-list
#
# 上面那个 parse_file 曾经是本脚本自己的一套 YAML 解析器，与 App 内那份各写各的，
# 久了必然走岔 —— 实测它数出 371 项而 App 实际 398 项，漏了
# recognizer/patterns/uppercase、style/candidate_format 这类设置，还把
# translator/comment_format/dictionary 这种根本不存在的路径写进了文档。
# 维护两份解析器没有任何好处，直接问 App。parse_file 保留仅作参考，不再调用。
LAYER_NAME = {"squirrel": "外观 / 常规", "schema": "方案", "default": "通用"}
APP_BIN = os.path.join(ROOT, "dist/Xpier.app/Contents/MacOS/Xpier")


def dump_from_app():
    import subprocess
    r = subprocess.run([APP_BIN, "--settings-list"], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        raise SystemExit("调用 --settings-list 失败：%s" % r.stderr[-500:])
    items = []
    for line in r.stdout.split("\n"):
        f = line.split("\t")
        if len(f) >= 5 and line.strip():
            items.append((LAYER_NAME.get(f[1], f[1]), f[0], f[2], f[4]))
    return items


rows = dump_from_app()

groups = {}
for layer, s, p, v in rows:
    groups.setdefault(s, []).append((layer, p, v))
order = sorted(groups.keys(),
               key=lambda a: (GROUP_ORDER.index(a) if a in GROUP_ORDER else len(GROUP_ORDER), a))

out = []
W = out.append
W("# 全部设置清单（Xpier 输入法）")
W("")
W("> 本文件由 `tools/gen_settings_doc.py` 从随包配置自动生成，不是手写；")
W("> 数据来源 `dist/Xpier.app/Contents/SharedSupport/` 下的")
W("> `squirrel.yaml`（外观）、`wubi86_jidian.schema.yaml`（方案）、`default.yaml`（通用）。")
W("")
W("## 怎么打开")
W("")
W("点菜单栏输入法图标 → **Xpier 设置…** —— 打开的就是完整设置，下面每组一个标签页。")
W("标签页标题不带条目数，干净。")
W("")
W("窗口标题与状态栏会显示「构建 MM-dd HH:mm」：换包后如果这个时间没变，")
W("说明输入法进程还是旧的，执行 `killall -9 Xpier` 再切一次输入法即可。")
W("")
W("改完点「保存并部署」。**只写入改动过的项**，没动过的不会进 custom.yaml。")
W("")
W("## 三层配置的关系")
W("")
W("| 层 | 文件 | 作用 | 改后写到 |")
W("| --- | --- | --- | --- |")
W("| 外观 / 常规 | `squirrel.yaml` | 候选窗外观、状态图标、各 App 行为 | `~/Library/Xpier/squirrel.custom.yaml` |")
W("| 方案 | `wubi86_jidian.schema.yaml` | 五笔码表、翻译器、简繁 | `~/Library/Xpier/wubi86_jidian.custom.yaml` |")
W("| 通用 | `default.yaml` | Shift / Caps 行为、翻页键、方案选单 | `~/Library/Xpier/default.custom.yaml` |")
W("")
W("`.custom.yaml` 优先级最高；重新安装输入法不会丢失，也不会改动内置默认值。")
W("")
W("## 全部条目")
W("")
for sec in order:
    W("### %s（%d 项）" % (sec, len(groups[sec])))
    W("")
    W("| 配置项 | 当前值 | 来源 | 说明 |")
    W("| --- | --- | --- | --- |")
    for layer, p, v in groups[sec]:
        note = NOTE.get(p, "")
        if not note and p.startswith("app_options/"):
            rest = p[len("app_options/"):]
            app, _, kk = rest.rpartition("/")
            n2 = APP_NOTE.get(kk, "")
            note = ("%s：%s" % (app, n2)) if n2 else ""
        W("| `%s` | `%s` | %s | %s |" % (p, v, layer, note))
    W("")
W("")
W("主题不是靠 @@style/color_scheme@@ 选名字就完事：每个主题要写全下面这些键才不会有看不见的字。")
W("**最容易踩的坑**：只写 @@hilited_text_color@@ 而漏掉 @@hilited_back_color@@，")
W("编码选中段就会变成「白字压在极浅背景上」——完全看不见。")
W("")
W("| 配色键 | 作用 |")
W("| --- | --- |")
W("| @@text_color@@ | 候选窗里未选中段的编码文字 |")
W("| @@hilited_text_color@@ | 候选窗里选中段的编码文字 |")
W("| @@hilited_back_color@@ | 上面这段编码的背景（不写 = 没有背景，极易看不见） |")
W("| @@candidate_text_color@@ | 未选中候选的文字 |")
W("| @@candidate_back_color@@ | 未选中候选的背景（一般留空） |")
W("| @@hilited_candidate_text_color@@ | 选中候选的文字 |")
W("| @@hilited_candidate_back_color@@ | 选中候选的背景 |")
W("| @@comment_text_color@@ | 候选注释文字 |")
W("| @@hilited_comment_text_color@@ | 选中候选的注释文字 |")
W("| @@label_color@@ / @@hilited_candidate_label_color@@ | 候选序号（不写则按前景/背景自动混色） |")
W("| @@border_color@@ | 候选窗描边 |")
W("")
W("> 注意：**内联显示编码**（@@style/inline_preedit: true@@）时，编码由客户端 App 自己画，")
W("> 用的是 App 自身文字色 + 下划线，上面这些颜色一律不参与，也无法由主题控制。")
W("> 但 Terminal / iTerm2 / MacVim / Emacs 在 @@app_options@@ 里带 @@no_inline: true@@，")
W("> 会被强制改成「编码显示在候选窗里」，此时这里的配色就直接决定看不看得清。")
W("")
W("### 当前两个 Xpier 主题的实际取值")
W("")
W("| 配色键 | Xpier / 默认（浅色） | Xpier / 暮色（深色） |")
W("| --- | --- | --- |")
# --- 主题配色键表（用 PyYAML 读，失败则跳过） ---
try:
    import yaml
    SY = os.path.join(SHARED, "squirrel.yaml")
    _d = yaml.safe_load(io.open(SY, encoding="utf-8")) or {}
    _p = _d.get("preset_color_schemes", {}) or {}
    _keys = ["text_color", "hilited_text_color", "hilited_back_color",
             "candidate_text_color", "candidate_back_color",
             "hilited_candidate_text_color", "hilited_candidate_back_color",
             "comment_text_color", "hilited_comment_text_color",
             "label_color", "hilited_candidate_label_color", "border_color"]
    _ci = out.index("### 当前两个 Xpier 主题的实际取值")
    _rows = []
    for _k in _keys:
        _a = _p.get("xpier_default", {}).get(_k, "—")
        _b = _p.get("xpier_dark", {}).get(_k, "—")
        if isinstance(_a, int): _a = "0x%08x" % _a
        if isinstance(_b, int): _b = "0x%08x" % _b
        _rows.append("| @@%s@@ | @@%s@@ | @@%s@@ |" % (_k, _a, _b))
    out[_ci + 4:_ci + 4] = _rows
    W("")
    W("> 本机共 %d 个可用主题预设，完整列表见 @@preset_color_schemes@@。" % len(_p))
except Exception as _e:
    W("")
    W("> （未能读取主题配色表：%s）" % _e)

W("## 图形界面已提供的开关")
W("")
W("「Xpier 设置…」主界面直接提供：主题、字体、候选字号、候选框样式、候选窗位置、")
W("每页候选数、显示未输完整编码的词条、Shift 原样上屏、词库导入/导出。")
W("其余条目通过「全部配置项…」逐项调整。")
W("")

path = os.path.join(ROOT, "docs/全部设置清单.md")  # 输出进仓库，随版本走
io.open(path, "w", encoding="utf-8").write("\n".join(out).replace("@@", chr(96)))
print("生成 %s" % path)
print("共 %d 项 / %d 个标签页" % (len(rows), len(order)))
for sec in order:
    print("   %-14s %3d 项" % (sec, len(groups[sec])))
