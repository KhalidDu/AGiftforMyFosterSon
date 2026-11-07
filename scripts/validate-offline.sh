#!/usr/bin/env bash
# 离线编译验证流水线:不安装游戏,用自写 API 桩工程 + Godot 3.6 --check-only 校验 mod 脚本
#
# 原理:Godot 3.6 的 --check-only 模式不注入 autoload 单例、不解析 class_name,
# 因此对"桩副本"做符号替换(ModLoaderLog→StbLog 等 const preload 替身)后即可完整编译校验。
# 发行源码(mod-src)保持原样,变换只发生在 stub-check/mods-unpacked 的副本上。
#
# 用法: scripts/validate-offline.sh <godot_exe路径>   (例: /c/work/godot36/Godot_v3.6-stable_win64.exe)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${1:-/c/work/godot36/Godot_v3.6-stable_win64.exe}"
SRC="$ROOT/mod-src/AGiftforMyFosterSon-Mod"
S="$ROOT/stub-check"
D="$S/mods-unpacked/AGiftforMyFosterSon-Mod"

[ -x "$GODOT" ] || { echo "找不到 Godot: $GODOT (用法: $0 <godot_exe>)"; exit 1; }

mkdir -p "$D/extensions/ui/menus/shop"

for f in mod_main.gd extensions/ui/menus/shop/item_popup.gd extensions/ui/menus/shop/base_shop.gd; do
	cp "$SRC/$f" "$D/$f"
	# autoload 全局名 → const preload 替身;数据类 → 桩类;Object 实例方法 → 静态桩方法
	sed -i 's/\bModLoaderLog\b/StbLog/g; s/\bModLoaderMod\b/StbMod/g; s/\bRunData\b/StbRun/g; s/\bUtils\b/StbUtils/g' "$D/$f"
	sed -i 's/\bItemData\b/StbItemData/g; s/\bCharacterData\b/StbCharacterData/g; s/\bConsumableData\b/StbConsumableData/g; s/\bUpgradeData\b/StbUpgradeData/g; s/\bProjectileEffect\b/StbProjectileEffect/g' "$D/$f"
	sed -i 's/StbRun\.has_method(/StbRun.stb_has(/g; s/StbRun\.get(/StbRun.stb_get(/g; s/StbUtils\.has_method(/StbUtils.stb_has(/g' "$D/$f"
	# 在 extends 行后插入替身 const 声明
	sed -i '1r '"$S"'/_autoconsts.txt' "$D/$f"
	sed -i '5r '"$S"'/_dataconsts.txt' "$D/$f"
done

OK=0
for f in mod_main.gd extensions/ui/menus/shop/item_popup.gd extensions/ui/menus/shop/base_shop.gd; do
	if "$GODOT" --path "$S" --no-window --check-only -s "res://mods-unpacked/AGiftforMyFosterSon-Mod/$f" > "$ROOT/out.txt" 2>&1; then
		echo "PASS  $f"
		OK=$((OK+1))
	else
		echo "FAIL  $f"
		grep -A2 "Parse Error" "$ROOT/out.txt" || cat "$ROOT/out.txt"
	fi
done

rm -f "$ROOT/out.txt"
echo "RESULT: $OK/3"
[ "$OK" -eq 3 ]
