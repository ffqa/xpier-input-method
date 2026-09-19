#!/bin/bash
# Xpier 一键安装：覆盖安装 + 重新注册 + 自检
#
# 必须由本机用户亲自执行（代理/CI 写不进 ~/Library）。
#
# 顺序很关键：必须「先覆盖文件，再杀进程」。
# 反着来 —— 先 killall 再复制，系统可能在文件还没覆盖完时
# 就把输入法拉起来，那个新进程读到的仍是旧文件，表现就是
# 「换了包却毫无变化」。
#
# 「重新注册」也是必须的：注册信息里带着 bundle 的名字，
# 不重注册的话系统一直用最初那份缓存。
#
# 和官方鼠须管的关系：包名 Xpier.app、bundle id com.xpier.inputmethod.Xpier、
# 用户目录 ~/Library/Xpier，全都分开，两者可以共存，互不覆盖。
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../dist/Xpier.app"
DST="$HOME/Library/Input Methods/Xpier.app"
BIN="$DST/Contents/MacOS/Xpier"
TIS="$HERE/../tools/tis-name"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [ ! -d "$SRC" ]; then
  echo "错误：找不到 $SRC —— 先跑 make dist"
  exit 1
fi
if [ ! -x "$TIS" ]; then
  echo "提示：输入源探针还没编（先跑 make tools），自检那一步会跳过名字显示"
fi

echo "==> 0/6 迁移旧数据（只跑一次）"
if [ ! -d "$HOME/Library/Xpier" ] && [ -d "$HOME/Library/Rime" ]; then
  echo "    发现 ~/Library/Rime，全量搬到 ~/Library/Xpier（词库/设置/用户词都保留）"
  cp -R "$HOME/Library/Rime" "$HOME/Library/Xpier"
else
  echo "    无需迁移"
fi
# 以前有个同名测试包（名字还叫 Squirrel 的几个版本）：只杀路径对得上的，
# 不碰官方鼠须管。
for pid in $(pgrep -x Squirrel 2>/dev/null); do
  if pgrep -ax Squirrel 2>/dev/null | grep "^$pid " | grep -q "$HOME/Library/Input Methods/Squirrel.app"; then
    echo "    退出旧测试包进程 $pid"
    kill "$pid" 2>/dev/null || true
  fi
done

echo "==> 1/6 覆盖文件（输入法仍在运行，不影响）"
mkdir -p "$HOME/Library/Input Methods"
if [ -d "$DST" ]; then
  rsync -a --delete "$SRC/" "$DST/" 2>/dev/null || {
    echo "    rsync 不可用，改用备份式替换…"
    mv "$DST" "$DST.bak"
    cp -R "$SRC" "$DST"
    rm -rf "$DST.bak"
  }
else
  cp -R "$SRC" "$DST"
fi

echo "==> 2/6 退出旧进程（确保下次启动读到的是新文件）"
killall Xpier 2>/dev/null || true
sleep 1
killall -9 Xpier 2>/dev/null || true
sleep 1
if pgrep -x Xpier >/dev/null 2>&1; then
  echo "    !! 仍有 Xpier 进程存活，请手动执行：killall -9 Xpier"
else
  echo "    旧进程已退出"
fi

echo "==> 3/6 清掉五笔方案的派生产物，强制重新编译码表"
# 方案本身改过就得重编：z 万能键（speller/algebra）是编译期作用在编码索引上的，
# 不重编的话新规则等于没写。librime 按文件时间戳判断要不要重建，
# 直接删掉派生产物最可靠。代价是下次启动输入法会多花十几秒重建这一张表，仅此一次。
for f in wubi86_jidian.schema.yaml wubi86_jidian.prism.bin \
         wubi86_jidian.table.bin wubi86_jidian.reverse.bin; do
  rm -f "$HOME/Library/Xpier/build/$f"
done
echo "    已清理（下次启动输入法时自动重建）"

echo "==> 4/6 用正确路径重新注册输入源"
echo "    （bundle 名字就是在这时候被系统读走的，跳过这步菜单里会一直是旧名字）"
"$BIN" --register-input-source

echo "==> 5/6 刷新 LaunchServices 注册"
"$LSREG" -f "$DST" || true

echo "==> 6/6 自检"
echo -n "    已安装二进制的构建时间："
ls -l "$BIN" | awk '{print $6, $7, $8}'
echo -n "    源包（dist）构建时间："
ls -l "$SRC/Contents/MacOS/Xpier" | awk '{print $6, $7, $8}'
echo -n "    appDir 是否已摆脱硬编码："
if strings "$BIN" 2>/dev/null | grep -qx "/Library/Input Methods/Xpier.app"; then
  echo "否 —— 这个包是旧的！"
else
  echo "是（已用 Bundle.main.bundleURL）"
fi
echo "    系统现在认得的名字："
if [ -x "$TIS" ]; then
  "$TIS" 2>/dev/null | grep -E "显示名称|当前选中" || echo "      （探针没输出）"
else
  echo "      （探针还没编：跑 make tools 再装一次即可）"
fi

echo ""
echo "✔ 安装完成"
echo ""
echo "接下来："
echo "  1. 点菜单栏输入法图标 → 切到 ABC → 再切回 Xpier五笔"
echo "     （第一次切回来会重建码表，卡十几秒是正常的，只此一次）"
echo "  2. 输入法菜单里应该有：设置… / 输简出繁 / 全角形状 / 英文标点 / 引号配对"
echo "  3. 试一下万能键：输 tzfu，应该能出「等」「徒增」这些 t?fu 的字"
echo "  4. 打开设置窗口，左下角有「构建 MM-dd HH:mm」，和上面的时间对得上就对了"
echo ""
echo "若切回来等了 1 分钟还是打不出中文：重建很可能卡在了半截"
echo "（build 里只有 prism 没有 table 就是这个状态），删干净重建一次："
echo "  rm -f ~/Library/Xpier/build/wubi86_jidian.* && killall Xpier"
echo "  然后再切回本输入法等 30 秒。用 make check 确认 4 个产物都在。"
echo ""
echo "若菜单里名字不对：菜单由系统进程绘制，注销重登一次即可彻底刷新。"
echo "（只有「输入法列表里没有本输入法」这一种情况才需要进键盘设置手动添加）"
