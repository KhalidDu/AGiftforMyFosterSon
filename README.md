# 这是一份给我义子的礼物 (A Gift for My Foster Son)

Brotato（土豆兄弟）合作模式道具赠送 mod —— [ShareWithYourBro](https://steamcommunity.com/sharedfiles/filedetails/?id=3718814620) 的 1.2.0.1 / Primal Dread 复刻继任者。

> **状态**：v0.1.5，已完成离线编译验证（Godot 3.6 桩工程 3/3 通过），**待实机测试**。
> 下载测试包：见 [Releases](../../releases)，附件 `AGiftforMyFosterSon-Mod-v0.1.5.zip`。

## 功能

- 合作商店中，点击自己已拥有的道具 → 弹出赠送按钮（2 人局一个「送给队友」；3/4 人局每个队友一个，标签带角色名，如「送给 小土豆 (P3)」）
- 赠送后自己失去道具与效果、队友获得，双方面板即时刷新
- 每个目标独立检查道具上限，满员按钮灰显带提示
- 特殊道具黑名单（芹菜茶/诱饵/孔雀/沙漏/一次性下波效果），防平衡与逻辑事故
- **对原生 UI 零侵入**：不动游戏自带按钮的焦点链（含 1.2 新版机械化工坊），可随时启停
- 内置兼容自检 + 诊断日志（`compat:` / `diag:` 行写入 `%APPDATA%\Brotato\logs\godot.log`）

## 设计要点（为什么它能扛游戏更新）

1. **防御式探测**：所有游戏 API 调用前 `has_method`/`get()` 探测，缺失降级并写日志而非崩溃
2. **零侵入焦点管理**：只在自己注入的按钮间组焦点链，唯一临时改动（取消键上方向）保存原值可还原——前辈 mod 死于硬编码焦点链打断 1.2 新按钮
3. **双通道派发**：赠送按钮按下时，信号无人监听则向上直呼商店节点处理方法，任何 mod 断掉 `_ready` 继承链（如联机类 mod）都不影响功能
4. **离线编译验证**：见 `scripts/validate-offline.sh`——不装游戏，用自写 API 桩工程 + Godot 3.6 `--check-only` 校验全部脚本

## 仓库结构

```
mod-src/AGiftforMyFosterSon-Mod/   # mod 源码(manifest + mod_main + 2个脚本扩展)
stub-check/                        # 自写的 Brotato API 桩工程(离线编译验证用)
scripts/validate-offline.sh        # 一键:生成变换副本 → Godot 编译检查
docs/测试指南.md                    # 安装/测试/DLC测试/发布流程
docs/生态兼容性审计.md              # 工坊Top25热门mod全量兼容矩阵
```

## 本地测试

把 Release 里的 zip 原样放进 `<Steam>\steamapps\workshop\content\1942280\<自建文件夹>\`，开一局本地合作即可。详见 [docs/测试指南.md](docs/测试指南.md)。

## 合规声明

- 本仓库与发行包**不含任何 Brotato 游戏代码**（两个扩展脚本全部自研，防御式探测不复制原方法体）
- 不含任何第三方 mod 内容（参考用 mod 源码留在本地 `downloads/`，已 gitignore）
- 依据 Brotato 官方 modding 指南要求，本仓库保持**私有**；`stub-check/` 全部为自写桩，无版权顾虑

## 技术栈

GDScript (Godot 3.6) · Godot Mod Loader 6.3+ · 零依赖 · 纯脚本扩展
