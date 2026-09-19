#!/bin/bash
# 装前自检：跑一遍就知道这台机器能不能编（缺什么当场问你要不要装）。
# 用法：
#   make requirements            交互式（缺啥问你，答 y 才装）
#   make bootstrap（make 的第一步）自动模式：缺 brew 包/子模块/码表就直接装，
#     不问（只跳过自己的 y/n，工具自带的密码/确认照常弹）。
#   make requirements-check / CI  只检查不装（stdin 关掉，非交互）。
# 退出码：0=全过，1=有失败项。
set -u
PASS=0
FAIL=0
TTY=0
[ -t 0 ] && TTY=1
AUTO=0
if [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then AUTO=1; fi

ok() { PASS=$((PASS + 1)); printf "    ✔ %s\n" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf "    ✘ %s\n" "$1"; }
info() { printf "    · %s\n" "$1"; }
ask() {  # ask <问题> <命令...>: --yes 直接跑；tty 才问，答 y 才跑
  if [ "$AUTO" -eq 1 ]; then
    shift
    printf "    …自动执行：%s\n" "$*"
    "$@"
    return $?
  fi
  if [ "$TTY" -eq 0 ]; then return 1; fi
  printf "    ？%s [y/N] " "$1"
  read -r ans </dev/tty
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    shift
    "$@"
  else
    return 1
  fi
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

echo "== 1/8 系统 =="
if sw_vers -productVersion 2>/dev/null | awk -F. '{exit ($1 < 13)}'; then
  ok "macOS $(sw_vers -productVersion)（要 13+）"
else
  bad "macOS 版本不够（要 13+，实际 $(sw_vers -productVersion 2>/dev/null))"
fi
if [ "$(uname -m)" = "arm64" ]; then info "Apple Silicon：编出来是 ARM 包"; else info "Intel：编出来是 Intel 包（CI 的 ARM 包用不了）"; fi

echo "== 2/8 Xcode =="
# 没有 pipefail 时 `xcodebuild | head` 在 xcodebuild 失败时仍成功（head 读空也 0），
# 空版本会被当成 MAJOR=0 报“太老”。xcode-select 指着命令行工具时就是这种：
# 本机明明有新 Xcode.app，xcodebuild 却跑不起来。
DEVDIR=$(xcode-select -p 2>/dev/null || true)
XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
if [ "$DEVDIR" = "/Library/Developer/CommandLineTools" ] && [ -d "$XCODE_DEV" ]; then
  ask "xcode-select 指着命令行工具，改指到 Xcode.app？（要管理员密码）" \
    sudo xcode-select -s "$XCODE_DEV"
  DEVDIR=$(xcode-select -p 2>/dev/null || true)
fi
XCODE_VER=""
if [ "$DEVDIR" != "/Library/Developer/CommandLineTools" ]; then
  XCODE_VER=$(xcodebuild -version 2>/dev/null | awk 'NR==1 && /Xcode / {print; exit}')
fi
if [ -n "$XCODE_VER" ]; then
  MAJOR=$(echo "$XCODE_VER" | grep -oE "[0-9]+" | head -n 1)
  if [ "${MAJOR:-0}" -ge 14 ]; then ok "${XCODE_VER}（要 14+，工程 objectVersion 54）"
  else bad "${XCODE_VER} 太老（要 14+）—— App Store 更新 Xcode"; fi
  xcrun --show-sdk-path >/dev/null 2>&1 && ok "SDK 就绪" || bad "xcrun 找不到 SDK：跑 sudo xcode-select -s /Applications/Xcode.app"
elif [ "$DEVDIR" = "/Library/Developer/CommandLineTools" ] && [ -d "$XCODE_DEV" ]; then
  bad "xcode-select 指着命令行工具，xcodebuild 用不了：跑 sudo xcode-select -s ${XCODE_DEV}"
elif [ -d "$XCODE_DEV" ]; then
  bad "有 Xcode.app 但 xcodebuild 读不到版本：打开一次 Xcode 接受协议，或 sudo xcodebuild -license accept"
else
  bad "没有 Xcode：App Store 装，装完打开一次接受协议"
  echo "    （命令行工具不够用，要 xcodebuild；抱怨 license 就跑 sudo xcodebuild -license accept）"
fi

echo "== 3/8 Homebrew / cmake / boost =="
# 修完复查：装完再查一遍，装上了就不算失败（bootstrap 全靠这个语义）。
have_boost() { [ -f /usr/local/include/boost/version.hpp ] || [ -f /opt/homebrew/include/boost/version.hpp ]; }
check_cmake_boost() {
  command -v cmake >/dev/null 2>&1 && ok "cmake 在" || {
    ask "brew 装 cmake？" brew install cmake
    command -v cmake >/dev/null 2>&1 && ok "cmake 在（刚装好）" || bad "缺 cmake（没装上，手动 brew install cmake）"
  }
  have_boost && ok "boost 头文件在" || {
    ask "brew 装 boost？" brew install boost
    have_boost && ok "boost 头文件在（刚装好）" || bad "缺 boost（没装上，手动 brew install boost）"
  }
}
if command -v brew >/dev/null 2>&1; then
  ok "brew 在"
  check_cmake_boost
else
  ask "现在装 brew（官方脚本，要输密码）？" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if command -v brew >/dev/null 2>&1; then
    ok "brew 在（刚装好）"
    check_cmake_boost
  else
    bad "没有 Homebrew（cmake/boost 都指着它，先把 brew 装上）"
  fi
fi

echo "== 4/8 git 与子模块 =="
command -v git >/dev/null 2>&1 && ok "git 在" || bad "没 git（装 Xcode 自带）"
check_sub() {
  NEED_SUB=0
  for d in librime/CMakeLists.txt plum/rime-install Sparkle/Sparkle.xcodeproj librime/deps/glog; do
    [ -e "$ROOT/$d" ] || { info "缺：$d"; NEED_SUB=1; }
  done
}
check_sub
# plum/output 是构建产物（make -C plum 时下载），不是源码：缺了只提示，不断言失败。
if [ -e "$ROOT/plum/output" ]; then info "plum 输出已在（构建时跳过下载）"
else info "plum 输出还没编（构建时下载，要联网一次）"; fi
if [ "$NEED_SUB" -eq 0 ]; then
  ok "引擎源码齐（librime/plum/Sparkle 已内嵌）"
else
  bad "源码缺文件（librime/plum/Sparkle）"
fi

echo "== 5/8 五笔码表 =="
# 码表放在仓库内 third_party/，不放到外面当兄弟目录（免得碰到别的 xpier）。
# 上游纯版：本地 schema 微调和加字由构建期补丁 + dict/ overlay 现打。
# 这个目录 gitignore，make / requirements --yes 会自己 clone。
WUBI_DIR="${WUBI86_DIR:-$ROOT/third_party/rime-wubi86-jidian}"
if [ -f "$WUBI_DIR/wubi86_jidian.schema.yaml" ]; then
  ok "$WUBI_DIR 在"
else
  if ask "现在 clone 上游码表到 third_party/？" true; then
    url=""
    if [ "$TTY" -eq 1 ] && [ "$AUTO" -eq 0 ]; then
      printf "    码表仓库地址（回车用 KyleBing 上游纯版）："
      read -r url </dev/tty || true
    fi
    [ -n "${url:-}" ] || url="https://github.com/KyleBing/rime-wubi86-jidian.git"
    mkdir -p "$(dirname "$WUBI_DIR")"
    git clone "$url" "$WUBI_DIR" || true
  fi
  if [ -f "$WUBI_DIR/wubi86_jidian.schema.yaml" ]; then
    ok "$WUBI_DIR 在（刚 clone 下来）"
  else
    bad "码表目录不在（${WUBI_DIR}；构建时拷码表用，WUBI86_DIR 可改）"
  fi
fi

echo "== 6/8 python3 =="
command -v python3 >/dev/null 2>&1 && ok "python3 在（构建期补丁用）" || bad "没 python3"

echo "== 7/8 磁盘 =="
FREE_GB=$(df -g / | tail -n 1 | awk '{print $4}')
if [ "${FREE_GB:-0}" -ge 3 ]; then ok "根卷可用 ${FREE_GB}GB（要 3GB+）"
else bad "根卷只剩 ${FREE_GB}GB（要 3GB+，构建中间产物约 1GB）"; fi

echo "== 8/8 小工具链 =="
command -v swiftc >/dev/null 2>&1 && ok "swiftc 在（编 tis-name 用，Xcode 自带）" || bad "没 swiftc"
command -v clang >/dev/null 2>&1 && ok "clang 在（编 rime_probe 用）" || bad "没 clang"

echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "✘ $FAIL 项没过，修完再跑（make requirements 重跑只查，不重装）。"
  exit 1
fi
echo "✔ 全过（$PASS 项）。下一步：make librime（约 30 分钟，一辈子一次）。"
