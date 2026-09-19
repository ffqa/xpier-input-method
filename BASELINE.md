# 基线说明（默认版本）

## 当前基线（默认版本）

**本仓库当前 HEAD 就是默认版本**，已实机可用；后续所有改动都以它为回归基准。
对应 git tag：`baseline-v1`。

| 项 | 值 |
| --- | --- |
| 引擎 | librime（自编，opencc 静态链接，无动态依赖） |
| 外壳 | rime/squirrel，分支 `wip-m2` |
| 方案 | 极点五笔 86（`wubi86_jidian`），随包分发且为默认首选 |
| Shift 行为 | `ascii_composer/switch_key` 的 `Shift_L` / `Shift_R` 均为 `commit_code`（未选字时原样输出编码）。由 `tools/patch_ascii_composer.py` 在**构建期强制**，`make debug` / `make release` 都必须先过这一关 |
| 设置入口 | 菜单栏输入法图标 → **Xpier 设置…**。**不占用任何键盘快捷键**（曾用 Cmd+, 会劫持所有 App 的偏好设置） |
| 全部配置 | 菜单栏输入法图标 → **Xpier 设置…**：371 项 / 6 个标签页（另有 2 项键名含「/」，无法用点路径寻址，见下），**均可编辑** |
| 主题 | `xpier_default`（浅）/ `xpier_dark`（深），全部配色键可在界面里用取色器改 |
| 安装 / 更新 | `bash scripts/update-xpier.sh`（原地覆盖，保留输入源注册） |

完整设置清单：`docs/全部设置清单.md`（由 `squirrel-fork/tools/gen_settings_doc.py` 自动生成，改配置后重跑即同步）。

### 不许回归的行为（改动后必须逐条复验）

1. 86 五笔直接可打，默认方案是 `wubi86_jidian`。
2. 未选字时按 Shift **原样输出编码**，不是首字。
3. 输入法菜单里**任何一项都不得带快捷键**。
4. 设置窗不空白；「全部配置项」每个分组都有内容。
5. `/` 与 `\` 直接输出 `/`、`、`。
6. 词库导入/导出可用。
7. 启动不崩（`otool -L` 不得出现 `libopencc`）。

> 本文件随 `squirrel-fork` 一起版本控制；根目录的 README.md 内容相同。

### 界面里改不到的 2 项（有意为之）

`punctuator/full_shape` 与 `punctuator/half_shape` 中**键名本身是 `/`** 的那两条。
Rime 的 patch 路径以 `/` 作分隔符且没有转义写法，写成 `"punctuator/full_shape//"`
会被解析成多一层空键，等于把配置写坏。需要改这两条时，请直接编辑方案文件或
`~/Library/Rime/wubi86_jidian.custom.yaml` 里的嵌套写法。

> 其余 371 项全部可在设置窗里直接编辑。
