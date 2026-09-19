# Xpier 五笔输入法（macOS）

自用的五笔 86 输入法。全本地、不开账号、不连云。
包名和官方鼠须管分家，两者可以一起装、互不干扰。

百度五笔是我用下来最舒服的五笔之一。输入法能看见你打的每一个字，
科技越发达，这件事越不该交给别人。所以有必要自己搞一个。

仓库：<https://github.com/ffqa/xpier-input-method>

> 没有 Apple Developer 证书，打出来的包是 **ad-hoc 签名**，系统会拦一次。
> 更稳的办法是自己编译、自己装。下面两条路都可以。

## 功能（相对上游多出来的）

- **输入法菜单四个开关**：输简出繁 / 全角形状 / 英文标点 / 引号配对。
  点一下就生效，换输入框、换 App 不丢（落盘 + 广播，见交接文档 6.6）。
  快捷键 `Ctrl+Shift+3`（全角）、`Ctrl+Shift+4`（简繁），和菜单同一条路。
- **z 万能键 + 拼音反查**：哪位编码记不清就拿 `z` 顶上（如 `tzfu`）；
  `z` 开头直接进拼音反查（如 `zni`），每个候选后面都带着五笔编码。
  平时打字不含 `z` 时界面干干净净，一个编码都不显示。
- **生僻字开箱可打**：字符集不过滤（五笔是精确码，不需要拼音那层过滤），
  扩展区字直接敲码上屏；主码表没有的𡋤（U+212E4）已补进个人码表（`fnyu`）。
- **引号配对开关**：开着半角引号也成对（写中文）；关掉空闲时直出单个
  （写代码、敲命令不断行）。中文全角里永远配对。
- **粉主题默认**：选中候选条是粉的（用户钦定），设置里可复制改色。
- **终端友好**：cmux / iTerm2 这类重度 `Ctrl+Shift` 用户，误触开全角的
  暗门已拔掉；常用 App 的中英文默认可在设置里逐个改。

## 安装

### 路 A：自己编译（推荐）

源码都在这个仓库里，编出来的包就是你这台机器打的，不用信网上的 zip。

前置：macOS 13+，[Xcode](https://apps.apple.com/app/xcode/id497799835)（装完打开一次接受协议），[Homebrew](https://brew.sh)。
Intel / Apple Silicon 都能编，**编出来的包只能在同架构上用**。
`make librime` 大约 30 分钟，一辈子一次；以后改 App 代码再打包大约 2 分钟。

如果 `xcodebuild` 报它指着命令行工具，跑：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

```bash
git clone https://github.com/ffqa/xpier-input-method.git
cd xpier-input-method
brew install cmake boost
make            # 自动备依赖 + clone 码表到 third_party/ + 编引擎 + 打包
make test       # 不装机：探针断言 tffu/tzfu/zni
make install    # 拷到 ~/Library/Input Methods/Xpier.app（必须本人执行）
```

码表在仓库内 `third_party/rime-wubi86-jidian/`（gitignore，不进 git），
不会写到外面当兄弟目录。

成了的标志：末尾 `✔ 打包完成：…/dist/Xpier.app`。

### 路 B：下载已经打好的包

GitHub Actions 可以在线打包（Apple Silicon / arm64）。

1. 打开 [Releases](https://github.com/ffqa/xpier-input-method/releases) 下载 `Xpier-macOS-arm64.zip`。
   还没有 Release 时，到 [Actions](https://github.com/ffqa/xpier-input-method/actions/workflows/build.yml) 里
   点 **Run workflow**，跑完下载 artifact（要登录 GitHub）。
2. 解压得到 `Xpier.app`。
3. 拷到 `~/Library/Input Methods/`（访达：前往 → 按住 Option 点资源库 → Input Methods）。

自己再打一遍包：仓库 → Actions → build → Run workflow。

### 两条路装完都要做（只此一次）

没有标准的 Developer ID 签名，**Gatekeeper 会拦**。不点这一下，输入法加了也起不来。

1. **过 Gatekeeper**：访达打开 `~/Library/Input Methods/`，**右键** `Xpier.app` → 打开 → 确认。
   以后不再问。双击打开没用，必须右键。
2. **添加输入源**：系统设置 → 键盘 → 输入源 → 添加 → 找到 **Xpier五笔（简体）**。
   脚本只负责登记，不加这一步菜单里永远没有它。
3. **等码表**：切到 Xpier五笔，等半分钟（第一次编译）。打 `tffu` 出“等”，
   打 `fnyu` 第二个是𡋤。还不放心跑 `make doctor`。

Intel Mac 请走路 A 自己编，CI 打出来的 arm64 包在 Intel 上不能用。

## 自己改（手把手）

改完一律：`make dist && make install`。
先看效果不用装：`make probe KEYS="tffu fnyu"` 不碰系统，直接看引擎输出。

### 改名（换成你的名字）

上次完整改名（含踩坑）留下的清单，按顺序走一遍，漏一个就出一类怪病：

1. `Squirrel.xcodeproj/project.pbxproj`：`PRODUCT_BUNDLE_IDENTIFIER`、
   `PRODUCT_NAME`（模块名跟着变，类名前缀不用手动改 —— 是同一处）。
2. `resources/Info.plist`：`TISInputSourceID`（3 个）、`CFBundleExecutable`、
   `CFBundleName/DisplayName`、`InputMethodServerControllerClass/DelegateClass`
   （**必须是 `<模块名>.<类名>`**，写错类名按键全直通英文，血泪史；
   `scripts/package.sh` 里有自检锁死这一项）。
3. `resources/InfoPlist.xcstrings`：新 id 的本地化名（菜单里显示的字），
   旧 id 的条目一并改或删，否则系统显示 raw id。
4. `sources/Main.swift`：用户目录（`Library/Xpier` 这种，决定和谁分家）、
   通知名、注释里的旧路径。
5. 源码里的类名前缀（`Xpier…`）：纯机械替换，注意 `xpierAppDelegate`
   这个小写属性也要一起走。
6. `scripts/package.sh` 的自检字符串（包名、类名、菜单文案）跟着改，
   否则打包自检不过。

### 改图标

两处，两个槽位，规矩不一样：

- **App 图标**（访达里，全彩）：`Rime.icon/Assets/logo.svg`，
  改完正常构建就行，系统按规范切圆角。底色必须铺满整幅。
  **别手画字形** —— 上次手画的几何五被认成 E（事后看确实就是 E）。
  要换字就跑 `tools/mkappicon.swift`（跟菜单图标同款丸ゴ真字形取描边，
  产物零字体依赖）：
  `swiftc -o /tmp/mkappicon tools/mkappicon.swift -framework AppKit && /tmp/mkappicon`。
- **菜单图标**（菜单栏/设置列表，**系统强制单色蒙版**，只取形状不取颜色；
  22×16pt 横版，方图会撑坏菜单布局）：
  改 `tools/mkicon.swift` 里的字体/字，跑一遍
  `swiftc -o /tmp/mkicon tools/mkicon.swift -framework AppKit && /tmp/mkicon`
  （产物 `resources/rime.pdf` 进仓库，CI 不跑它，所以字体只要求本机有）。
  现在用的是系统自带的 Hiragino Maru Gothic ProN（圆体，俏皮就靠字形）。

### 改配色

`data/squirrel.yaml` 顶部的 `xpier_default`（浅色）/`xpier_dark`（深色）。
**Rime 配色是 `0xAABBGGRR`（ABGR），不是 ARGB** —— 标尺：谷歌主题的高亮
`0xCE7539` 就是 Google 蓝。按 ARGB 写，淡紫会变粉（我们花了一天才找到）。
只改饱和色的一定肉眼对一遍：近白近黑是对称色，字节序写反了也看不出来。
改完 `make dist` 装机，如果颜色没变，进设置点一次「保存并部署」强制刷全量。

### 加字加词（以𡋤为例，手把手）

场景：𡋤（U+212E4），在线词典有、现实生活有，主码表没有，打不出来。
下面是把它变成“敲 `fnyu` 就有”的全过程，新字都照此办。

**第 1 步：定编码。** 先拆字：𡋤 = ⿰土尽（左土右尽）。
结构拿不准去 [cjkvi-ids](https://github.com/cjkvi/cjkvi-ids) 查一行：
`U+212E4  𡋤  ⿰土尽` —— 实测过，就是这么拆。
然后定 86 编码：土取 `f`，尽是 `nyu`（一n二y末u），合起来全码 `fnyu`。
没把握就找同偏旁的字对照：赆=`mnyu`、烬=`onyu`，都是“一二末 + u”收尾，
`fnyu` 对得上。

**第 2 步：写进自有词表。** 注意文件在**本仓库**里，不在码表仓库：

```bash
# squirrel-fork/dict/wubi86_xpier.dict.yaml，末尾加一行
# （字和码之间是 Tab，不是空格；# 开头的是注释，只能另起一行）：
𡋤	fnyu
```

为什么不加主码表：主码表是上游的，更新会被覆盖；
这个 overlay 文件构建时拷进 `data/plum` 并挂进主词库的 `import_tables`，
升级也在。权重不写（默认按码长排，四码单字直接见面）。

**第 3 步：重编 + 装机。** 注意第一行 `wubi86-data` 不能省 ——
`make debug` 不管码表拷贝，只编 App；码表是这一步拷进 `data/plum` 的：

```bash
make wubi86-data && make debug && make dist && make install-user
```

**第 4 步：等重建。** 切回输入法等半分钟（码表编译中），敲 `fnyu`，
第二个就是𡋤（第一个是“真心诚意”）。`make check` 四个产物全绿即成。

排错：如果敲码没候选，先 `make probe KEYS="fnyu"` ——
探针有字而输入法没有，是部署/会话问题；探针也没有，是码没加对，
回去查 Tab 分隔和编码（新词条放分组末尾最稳）。

### 自定义短语（地址/邮箱/日期这种，以𡋤同一条路）

英文码配中文/英文长串（如 `addr`→地址、`mail`→邮箱）不用另起机制，
就是再挂一张用户词表：`~/Library/Xpier/wubi_custom_phrase.dict.yaml`
（一行一条，字⇥码⇥权重，Tab 分隔；权重 `10000` 可盖过主码表同码词）。
全库唯一码直接上屏，同码时靠权重排。原理、spike 实测表、随包桩、
gist 拉取计划见 `docs/自定义短语.md`（本机层已验证，还没进包；
gist 只读拉取是下一步）。

### 加减菜单开关

以引号配对（`quote_pair`）为模板，三件套：

1. `sources/XpierInputController.swift`：菜单加一项（一开关一无参方法 ——
   带参 action 会被跨进程菜单派发静默吞掉，点了没反应的元凶），`switchLogicalDefault`
   里登记默认值（Rime 的 option 默认全关，默认开的语义只能应用侧补），
   `createSession` 里种默认值。
2. `tools/patch_save_options.py` 的调用处（`Makefile` 的 `xpier-patches` 里）
   把开关名加进去，否则换个输入框就忘。
3. `scripts/package.sh` 的自检里加一行，防以后掉。

开关名千万别和 Rime 内置重名（查一下 `switches:`），`reset: 0` 别乱加 ——
引擎启动时先读存档再强制复位，写了等于每次进新输入框都掰回默认。

## 字体来源

- 菜单图标「五」：字形取自 macOS 自带字体 **Hiragino Maru Gothic ProN W4**
  （ヒラギノ丸ゴ，圆体），打包进 `resources/rime.pdf`（只用字形，不分发字体文件）。
- App 图标：纯几何图形（`Rime.icon/Assets/logo.svg`），无字体依赖，CI 也能编。
- 打字候选窗的字体：跟随系统 + 设置里的字体选择，与本仓库无关。

## 生僻字

默认可打两层意思：

1. **字符集不过滤**：`translator/enable_charset_filter: false`。
   五笔是精确码，敲对码才出字，不存在拼音那种生僻字刷屏问题，
   过滤除了拦字没用。想滤回去去设置开「只出常用字」。
2. **字必须在码表里**：主码表（极点 86）没有的字，进
   `wubi86_jidian_user.dict.yaml` 就是正式词条。本仓库加的：
   - **𡋤**（U+212E4，土+尽，`fnyu`）：在线词典有、现实生活有，主码表没有。
     在 `fnyu` 第二候选（第一是“真心诚意”）。

主码表自带 22 个扩展区旧词条（CJK 兼容字如 﨟 等），开箱都在。

## 和其他输入法对比

|              | 平台        | 花钱/开源 | 五笔 86       | 反查/万能键 | 隐私       | 一句话                                           |
| ------------ | ----------- | --------- | ------------- | ----------- | ---------- | ------------------------------------------------ |
| **本项目**   | macOS       | 免费开源  | ✅（极点 86） | ✅          | 全本地     | 给自己改着玩的，改完自己编                       |
| 官方鼠须管   | macOS       | 免费开源  | 需自配        | 看方案      | 全本地     | Rime 官方前端，本项目 fork 自它                  |
| 苹果自带五笔 | macOS       | 自带      | ✅            | ❌          | 全本地     | 零配置，但不可定制                               |
| 微软五笔     | Windows     | 自带      | ✅            | ❌          | 全本地     | Win 中文版自带，够用党终点                       |
| 百度五笔     | macOS / Win | 免费闭源  | ✅            | 部分        | 云端未知   | 手感很好；输入法能看见每一个字，这是自己做的原因 |
| 搜狗五笔     | Win         | 免费闭源  | ✅            | 部分        | 云词库上传 | 词库大，广告和弹窗自己掂量                       |
| 极点五笔     | Windows     | 免费闭源  | ✅（代表）    | ✅          | 全本地     | 老牌，五笔用户的基本盘                           |
| 清歌输入法   | macOS / iOS | 免费闭源  | ？            | ？          | ？         | 仓颉/注音见长，图标可爱（本项目图标灵感来源）    |
| Hamster      | iOS/Android | 免费开源  | 需自配        | 看方案      | 全本地     | 移动端 Rime 前端，五笔方案自己挂                 |
| fcitx5-rime  | Linux       | 免费开源  | 需自配        | 看方案      | 全本地     | Linux 端 Rime 前端                               |

“需自配”的意思是：前端只管显示，码表方案要自己找（如本仓库用的极点 86）。
“？”是没亲自验证的，欢迎指正。对比只聊五笔相关的维度。

## 致谢与来源

- [rime/squirrel](https://github.com/rime/squirrel) —— 鼠须管本体，外壳 fork 自它
  （`xpier` 分支，bundle id 等已改，和官方版共存）。
- [rime/librime](https://github.com/rime/librime) —— Rime 引擎，源码内嵌在本仓库，
  带几个本地补丁（编码门控、Ctrl+= 置顶，见交接文档）。
- [KyleBing/rime-wubi86-jidian](https://github.com/KyleBing/rime-wubi86-jidian) ——
  极点五笔 86 码表（Apache-2.0），构建时拷入，无修改随包（个人加字在
  `wubi86_jidian_user.dict.yaml`）。
- [rime/plum](https://github.com/rime/plum)、[opencc](https://github.com/BYVoid/OpenCC) ——
  默认配置与简繁转换。
- [cjkvi-ids](https://github.com/cjkvi/cjkvi-ids) —— 汉字拆分（给生僻字定编码）。
- [Sparkle](https://github.com/sparkle-project/Sparkle) —— 上游自带（本分支自动更新已关）。

## 常见问题

- **系统说已损坏 / 打不开**：不是包坏了，是 ad-hoc 签名过不了 Gatekeeper。
  访达里**右键**打开一次，不要双击。自己 `make install` 的也一样。
- **打不出中文**：跑 `make check`，四个码表产物缺了就是没编好 ——
  切回本输入法等 30 秒（重建），再查。还不行：`rm -f ~/Library/Xpier/build/wubi86_jidian.* && killall Xpier`，切回等 30 秒。
- **改了代码装了没变化**：装的是旧包（踩过不止一次）。`make dist` 看自检过没过，
  对设置窗口左下角「构建时间」和包的时间。
- **菜单开关点了没用**：先看勾在不在 —— 带参 action 发不过去，必须一开关一无参方法
  （修过一次）；终端里 `Ctrl+Shift` 快捷键到不了输入法（cmux/tmux 吃掉），用菜单点。
- **卡在全角退不出**：旧包的 `Ctrl+Shift+3` 暗门（已拔）。新包菜单关了即关，
  当前框还宽就切个输入框（新会话读存盘）。
- **终端默认英文**：Terminal / iTerm2 出厂配了进门英文，设置→常用 APP 关联里关掉那两项。
