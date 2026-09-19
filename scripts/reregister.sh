#!/bin/bash
# 强制 macOS 重新读取输入法的注册信息（只做这一件没有副作用的事）。
#
# 什么时候需要跑：改过 app bundle 的名称/路径之后。
# 平时不用单独跑 —— scripts/install.sh 的第 4 步已经包含这一步。
#
# 背景：输入法菜单里显示的名字来自系统的 TIS 注册，而注册是在
# TISRegisterInputSource() 时建立的 —— bundle 的名字就是在那时候被系统读走的。
# 本机菜单长期显示 "Squirrel - Simplified"，根因是两条凑一起：
#   1) appDir 被硬编码成 /Library/Input Methods/Squirrel.app —— 那个路径不存在，
#      macOS 读不到 bundle 里的本地化名字，只好拿路径末段当名字；
#   2) register() 在「已有模式启用」时直接 return，于是这个错误名字再没被刷新过。
# 两条都已修（Main.swift 的 appDir / InputSource.swift 的 register）。
#
# 本脚本不动启用/选中状态，只重新注册。
set -e

APP="$HOME/Library/Input Methods/Xpier.app"
BIN="$APP/Contents/MacOS/Xpier"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIS="$HERE/../tools/tis-name"

if [ ! -x "$BIN" ]; then
  echo "找不到输入法可执行文件：$BIN"
  exit 1
fi

show() {
  if [ -x "$TIS" ]; then
    "$TIS" 2>/dev/null | grep -E "显示名称|当前选中" || echo "  （探针没输出）"
  else
    echo "  （找不到探针 ${TIS}）"
  fi
}

echo "==> 重新注册之前的系统记录"
show
echo
echo "==> 用正确路径重新注册"
"$BIN" --register-input-source
echo
echo "==> 重新注册之后"
show
echo
echo "✔ 完成"
echo ""
echo "如果菜单栏里显示的名字还没变，说明是系统 UI 进程缓存了菜单："
echo "  · 先点菜单栏输入法图标 → 切到 ABC → 再切回本输入法"
echo "  · 仍不变则注销重登一次（菜单由系统进程绘制，只有重登才彻底刷新）"
echo ""
echo "注意：菜单里那条要显示成「设置…」（不带 Xpier 前缀），需要这次装的是新版本。"
