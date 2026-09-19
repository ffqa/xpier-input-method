#!/bin/bash
# 出厂质检：装完跑它，确认“装的就是这次的包、输入法真能接管”。
# 只读（不动系统），退出码 0=全过，1=有失败。
# 用法：make doctor。比 make check 多三样：dist 与已装包是否同一份、
# 输入源启用/选中状态、用户配置目录是否就绪。
set -u
FAIL=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DIST="$ROOT/dist/Xpier.app"
INST="$HOME/Library/Input Methods/Xpier.app"
TIS="$ROOT/tools/tis-name"

ok() { printf "    ✔ %s\n" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf "    ✘ %s\n" "$1"; }

echo "== 1/5 进程 =="
if pgrep -x Xpier >/dev/null 2>&1; then ok "Xpier 在跑（pid $(pgrep -x Xpier | tr '\n' ' ')）"
else bad "Xpier 没在跑（切到本输入法会自动拉起；还不起来就 killall Xpier 重试）"; fi

echo "== 2/5 装的是这次的包吗 =="
if [ ! -d "$DIST" ]; then
  bad "dist/ 里没包（先跑 make dist）"
elif [ ! -d "$INST" ]; then
  bad "还没装（先跑 make install-user）"
elif [ "$(md5 -q "$DIST/Contents/MacOS/Xpier" 2>/dev/null)" = "$(md5 -q "$INST/Contents/MacOS/Xpier" 2>/dev/null)" ]; then
  ok "已装包和 dist 是同一份（构建时间 $(stat -f "%Sm" -t "%m-%d %H:%M" "$INST/Contents/MacOS/Xpier"))"
else
  bad "已装包和 dist 不是同一份 —— 装的是旧包，重跑 make install-user"
fi

echo "== 3/5 输入源状态 =="
if [ -x "$TIS" ]; then
  OUT="$("$TIS" 2>/dev/null)"
  echo "$OUT" | grep -q "Xpier.Hans" || { bad "系统里没找到 Xpier 输入源（去键盘设置手动添加，见 README）"; }
  if echo "$OUT" | grep -A2 "Xpier.Hans" | grep -q "启用=true"; then ok "Xpier五笔（简体）已启用"
  else bad "Xpier五笔（简体）未启用（键盘设置里勾上）"; fi
  if echo "$OUT" | grep -A2 "Xpier.Hans" | grep -q "当前选中=true"; then ok "当前正选中它"
  else echo "    · 当前没选中它（点菜单栏图标切过去）"; fi
else
  bad "探针还没编（跑 make tools；跳过这一项）"
fi

echo "== 4/5 码表产物 =="
N=0
for f in wubi86_jidian.prism.bin wubi86_jidian.table.bin wubi86_jidian.reverse.bin wubi86_jidian.schema.yaml; do
  if [ -f "$HOME/Library/Xpier/build/$f" ]; then N=$((N + 1)); fi
done
if [ "$N" -eq 4 ]; then ok "码表四件套齐"
else bad "码表缺 $((4 - N)) 件（切回本输入法等重建，再跑一次）"; fi

echo "== 5/5 用户目录 =="
[ -f "$HOME/Library/Xpier/user.yaml" ] && ok "~/Library/Xpier/user.yaml 在（开关有地方存）" \
  || echo "    · user.yaml 还没生成（切过去打几个字就有，不碍事）"

echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "✘ $FAIL 项没过。"
  exit 1
fi
echo "✔ 全过。打 tffu 出“等”即收工。"
