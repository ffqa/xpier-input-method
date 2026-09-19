#!/bin/bash
# 把构建产物打成可安装包（dist/Xpier.app），并做一遍验收检查。
#
# 为什么要固化成脚本：以前这一步是手工 cp 的，于是「装的到底是哪一次构建」
# 全靠猜 —— 已经不止一次出现「改了代码、也装了、界面却没变」，
# 排查半天发现装的是旧包。这里每次打出包都强制自检一遍关键项。
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/build/Build/Products/Debug/Xpier.app"
DST="$ROOT/dist/Xpier.app"
XCENT="$ROOT/build/Build/Intermediates.noindex/Squirrel.build/Debug/Squirrel.build/Xpier.app.xcent"

if [ ! -d "$SRC" ]; then
  echo "错误：找不到构建产物 $SRC —— 先跑 make debug"
  exit 1
fi

echo "==> 1/3 复制构建产物"
rm -rf "$DST"
mkdir -p "$(dirname "$DST")"
cp -R "$SRC" "$DST"

echo "==> 2/3 重新签名（临时签名，本机自用）"
if [ -f "$XCENT" ]; then
  codesign --force --deep --sign - --entitlements "$XCENT" "$DST" 2>&1 | sed 's/^/    /'
else
  codesign --force --deep --sign - "$DST" 2>&1 | sed 's/^/    /'
fi
codesign --verify --deep "$DST" && echo "    签名校验通过"

echo "==> 3/3 验收检查"
BIN="$DST/Contents/MacOS/Xpier"
fail=0
check() {  # check <描述> <期望> <实际>
  if [ "$2" = "$3" ]; then
    printf "    ✔ %s\n" "$1"
  else
    printf "    ✘ %s（期望 %s，实际 %s）\n" "$1" "$2" "$3"
    fail=1
  fi
}

check "CFBundleName 是「Xpier五笔」" "Xpier五笔" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$DST/Contents/Info.plist")"

# 控制器类名必须真实存在：曾把 Xpier.XpierInputController 误写成
# Xpier.XpierInputController（类没改名，只改了模块），结果按键全直通英文。
# 这里双向确认：plist 的值正确，且该符号确实在 dylib 里。
check "控制器类是 Xpier.XpierInputController" "Xpier.XpierInputController" \
  "$(/usr/libexec/PlistBuddy -c 'Print :InputMethodServerControllerClass' "$DST/Contents/Info.plist")"
if python3 - "$DST/Contents/MacOS/Xpier.debug.dylib" <<'PY'
import sys, pathlib
b = pathlib.Path(sys.argv[1]).read_bytes()
sys.exit(0 if b'Xpier.XpierInputController' in b else 1)
PY
then
  printf "    ✔ 控制器类符号在 dylib 里存在\n"
else
  printf "    ✘ dylib 里找不到 Xpier.XpierInputController\n"; fail=1
fi

# 这两个是本机需求，被上游默认值覆盖过两次，每次打包都必须确认
n=$(grep -c 'commit_code' "$DST/Contents/SharedSupport/default.yaml" || true)
if [ "$n" -ge 2 ]; then printf "    ✔ Shift 左右键都是 commit_code（%s 处）\n" "$n"
else printf "    ✘ Shift 不是 commit_code（只找到 %s 处）\n" "$n"; fail=1; fi

# 硬编码的旧路径是输入法名字显示成 "Squirrel - Simplified" 的根因，不能回来
if strings "$BIN" | grep -qx "/Library/Input Methods/Xpier.app"; then
  printf "    ✘ 二进制里还有硬编码的旧安装路径\n"; fail=1
else
  printf "    ✔ 没有硬编码的旧安装路径\n"
fi

# opencc 必须以静态/内嵌方式进来，不能是可选的动态库依赖
if otool -L "$BIN" | grep -qi 'libopencc'; then
  printf "    ✘ 引入了 libopencc 动态依赖\n"; fail=1
else
  printf "    ✔ 没有 libopencc 动态依赖\n"
fi

# 菜单文案的检查用 python3 读字节 —— grep 对多字节 UTF-8 字面量不可靠：
# 同一个二进制，grep 查「设置…」得到 0 次，python 数出来是 1 次。
# 判据是「NUL 分隔的独立字符串」而不是子串：配置文件的 YAML 注释里
# 合法地含有「由 Xpier 设置维护」这类文字，按子串判会误报。
if python3 - "$DST/Contents/MacOS/Xpier.debug.dylib" <<'PY'
import sys, pathlib
b = pathlib.Path(sys.argv[1]).read_bytes()
strs = [s for s in b.split(b'\x00') if s]
bad = [s for s in strs if s.startswith('Xpier 设置'.encode())]
ok = any(s == '设置…'.encode() for s in strs)
sys.exit(0 if ok and not bad else 1)
PY
then
  printf "    ✔ 菜单项文案是「设置…」（不带 Xpier 前缀）\n"
else
  printf "    ✘ 菜单项文案不对（应有一条正好是「设置…」，且不应有以「Xpier 设置」开头的串）\n"; fail=1
fi

# 输入法菜单里的快捷开关。这几条是「打字时随手切」的入口，掉了用户就只能进设置翻。
# 当前四项：输简出繁/全角形状/英文标点/引号配对。「全角标点」已改名全角形状
# （旧名误导：full_shape 是全套变宽，连临时英文都变，不是只变标点），
# 所以既查三者存在，也查旧名 absence。「生僻字」虽已从菜单删除，
# 但设置说明文字里还有它，这里不查（要查只会误报）。
if python3 - "$DST/Contents/MacOS/Xpier.debug.dylib" <<'PY'
import sys, pathlib
b = pathlib.Path(sys.argv[1]).read_bytes()
need = ['输简出繁', '全角形状', '英文标点', '引号配对']
gone = ['全角标点']
ok = all(s.encode() in b for s in need) and not any(s.encode() in b for s in gone)
sys.exit(0 if ok else 1)
PY
then
  printf "    ✔ 输入法菜单四开关齐（输简出繁/全角形状/英文标点/引号配对，无旧名残留）\n"
else
  printf "    ✘ 输入法菜单快捷开关不对（应为输简出繁/全角形状/英文标点/引号配对）\n"; fail=1
fi

# zh_trad 不在 save_options 里的话，输简出繁切了不跨会话保持，
# 表现是「切到别的 App 又变回简体」。
if grep -q '^    - zh_trad$' "$DST/Contents/SharedSupport/default.yaml"; then
  printf "    ✔ 方案已把 zh_trad 列入 save_options\n"
else
  printf "    ✘ save_options 缺 zh_trad，输简出繁不会被记住\n"; fail=1
fi

# z 万能键靠方案里的 speller/algebra 派生编码实现。这一项掉了，
# tzfu 这种「某一位记不清」的输入就直接变成零候选，而界面上完全看不出来。
if grep -q 'derive/' "$DST/Contents/SharedSupport/wubi86_jidian.schema.yaml"; then
  printf "    ✔ 五笔方案带 z 万能键（speller/algebra）\n"
else
  printf "    ✘ 方案缺 z 万能键规则，tzfu 这类输入会无候选\n"; fail=1
fi

# pinyin_simp 不在 schema/dependencies 里的话，z 开头的拼音反查会静默失效
# （反查翻译器加载不到那张码表）。上游把这一行注释掉了，是构建期补回来的。
if grep -q '^    - pinyin_simp$' "$DST/Contents/SharedSupport/wubi86_jidian.schema.yaml"; then
  printf "    ✔ 方案声明了 pinyin_simp 依赖（z 拼音反查可用）\n"
else
  printf "    ✘ 方案缺 pinyin_simp 依赖，z 开头反查会查不到词\n"; fail=1
fi

# 候选后面显示编码靠 reverse_lookup_filter，且只在输入含 z 时显示
# （wubi_code/show_if_input_contains，段输入含 z 才挂 filter；需新编 librime
# 并进包，否则旧引擎忽略该键、编码常显）
if grep -q 'reverse_lookup_filter@wubi_code' "$DST/Contents/SharedSupport/wubi86_jidian.schema.yaml"; then
  printf "    ✔ 候选后显示五笔编码（reverse_lookup_filter）\n"
else
  printf "    ✘ 缺编码提示过滤器\n"; fail=1
fi
if grep -q 'show_if_input_contains' "$DST/Contents/SharedSupport/wubi86_jidian.schema.yaml"; then
  printf "    ✔ 编码提示只在万能键时显示（show_if_input_contains）\n"
else
  printf "    ✘ 编码提示缺收窄配置，平时打字也会常显编码\n"; fail=1
fi

# schema_list 里的每一项，包里必须有对应的 .schema.yaml。
# 曾经 schema_list 列着 quick5，但包里没有它，每次部署报 missing input schema。
# 用 python 读 YAML 的 schema_list 段（不用 grep，是因为缩进/注释容易误判）。
if python3 - "$DST/Contents/SharedSupport" <<'PY'
import re, sys, pathlib
d = pathlib.Path(sys.argv[1])
lines = (d / 'default.yaml').read_text(encoding='utf-8').splitlines()
ins = False
missing = []
for ln in lines:
    if re.match(r'^schema_list:\s*$', ln):
        ins = True
        continue
    if ins:
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        if not ln[:1].isspace():
            break
        m = re.match(r'^-\s*schema:\s*(\S+)\s*$', s)
        if m and not (d / (m.group(1) + '.schema.yaml')).exists():
            missing.append(m.group(1))
if missing:
    print('缺文件: ' + ', '.join(missing))
    sys.exit(1)
PY
then
  printf "    ✔ schema_list 每一项在包里都有对应方案文件\n"
else
  printf "    ✘ schema_list 有的项在包里缺文件（见上行）\n"; fail=1
fi

# macOS 自带 bash 3.2 里 $VAR 后面不能直接跟中文/全角符号（会被当成变量名
# 的一部分，set -u 下报 unbound variable）。凡是后面跟非 ASCII 的变量必须写
# ${VAR}。犯过两次（XCODE_VER（、WUBI_DIR；），用 python 扫（grep 对多字节不可靠）。
if python3 - "$HERE" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
bad = []
for f in sorted((root).glob('*.sh')):
    for i, ln in enumerate(f.read_text(encoding='utf-8').splitlines(), 1):
        for m in re.finditer(r'\$[A-Za-z_][A-Za-z0-9_]+', ln):
            nxt = ln[m.end():m.end()+1]
            if nxt and ord(nxt) > 127:
                bad.append('%s:%d' % (f.name, i))
if bad:
    print('裸变量后跟全角字符: ' + ', '.join(bad))
    sys.exit(1)
PY
then
  printf "    ✔ 脚本里没有裸 $VAR+全角字符（bash 3.2 坑）\n"
else
  printf "    ✘ 脚本有裸 $VAR 后跟全角字符（见上行），改成 ${VAR} 形式\n"; fail=1
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "✘ 有检查项未通过，先别装。"
  exit 1
fi
echo "✔ 打包完成：$DST"
echo "  构建时间 $(date -r "$BIN" '+%m-%d %H:%M')"
echo ""
echo "接下来跑：make install-user（需本机执行，见 README）"
