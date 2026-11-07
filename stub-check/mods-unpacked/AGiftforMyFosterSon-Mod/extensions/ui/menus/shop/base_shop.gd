extends "res://ui/menus/shop/base_shop.gd"
const StbLog = preload("res://stubs/mod_loader_log.gd")
const StbMod = preload("res://stubs/mod_loader_mod.gd")
const StbRun = preload("res://stubs/run_data.gd")
const StbUtils = preload("res://stubs/utils.gd")
const StbItemData = preload("res://stubs/item_data.gd")
const StbCharacterData = preload("res://stubs/character_data.gd")
const StbConsumableData = preload("res://stubs/consumable_data.gd")
const StbUpgradeData = preload("res://stubs/upgrade_data.gd")
const StbProjectileEffect = preload("res://stubs/projectile_effect.gd")

# AGiftforMyFosterSon — base_shop 扩展(赠送执行逻辑)
# 所有游戏 API 调用前都有 has_method/get 探测:
#  - 关键路径缺失 → 明确写 error 日志并中止本次赠送(不崩溃)
#  - 焦点/音效等非关键路径缺失 → 静默降级
# 首次进商店输出一份 StbRun/base_shop/StbUtils 兼容性体检报告到 godot.log。

const LOG_NAME = "AGiftforMyFosterSon-Mod:Shop"

# 与 item_popup 扩展保持一致的黑名单(特殊挂载行为道具,参考 Coop Trading)
const AGIFT_BLOCKED_ITEM_IDS = ["item_celery_tea", "item_lure", "item_peacock"]

var _compat_logged := false


func _ready() -> void:
	call_deferred("_giftbro_shop_ready")


func _giftbro_shop_ready() -> void:
	_compat_check_once()
	_connect_gift_signals()


# ---------------------------------------------------------------- 兼容性体检

func _compat_check_once() -> void:
	if _compat_logged:
		return
	_compat_logged = true

	var rundata_checks := [
		"get_player_count", "is_coop_run", "get_remaining_max_nb_item",
		"get_player_items", "remove_item", "add_item",
		"get_player_effect", "add_item_displayed",
	]
	for method_name in rundata_checks:
		if not StbRun.stb_has(method_name):
			StbLog.error("compat: StbRun.%s MISSING — gifting will not work." % method_name, LOG_NAME)
	StbLog.info("compat: StbRun ok=%s players_data=%s" % [
		str(StbRun.stb_has("add_item")), str(StbRun.stb_get("players_data") != null)
	], LOG_NAME)

	var shop_checks := [
		"_update_stats", "_get_gear_container", "_get_shop_items_container",
		"_get_item_popup", "_get_default_focus_control",
	]
	for member in shop_checks:
		if has_method(member):
			StbLog.info("compat: base_shop.%s() ok" % member, LOG_NAME)
		else:
			StbLog.error("compat: base_shop.%s MISSING — related behavior degraded." % member, LOG_NAME)
	StbLog.info("compat: _popup_manager=%s recycle_sounds=%s" % [
		str(get("_popup_manager") != null), str(get("recycle_sounds") != null)
	], LOG_NAME)

	var base_script = get_script().get_base_script()
	if base_script != null and base_script.has_method("_ready"):
		StbLog.error("compat: base_shop parent defines _ready() which AGiftforMyFosterSon does NOT invoke. Report this log to the developer.", LOG_NAME)

	for util in ["get_focus_emulator", "focus_player_control"]:
		if not StbUtils.stb_has(util):
			StbLog.error("compat: StbUtils.%s MISSING — focus handling degraded." % util, LOG_NAME)

	StbLog.info("compat: check complete.", LOG_NAME)


# ---------------------------------------------------------------- 信号连接

func _connect_gift_signals() -> void:
	if not has_method("_get_item_popup"):
		return
	for player_index in StbRun.get_player_count():
		var item_popup = call("_get_item_popup", player_index)
		if item_popup == null:
			continue
		if not item_popup.has_signal("item_gift_button_pressed"):
			continue
		if item_popup.is_connected("item_gift_button_pressed", self, "_on_item_gift_button_pressed"):
			continue
		var _err = item_popup.connect(
			"item_gift_button_pressed",
			self,
			"_on_item_gift_button_pressed",
			[player_index]
		)


# ---------------------------------------------------------------- 赠送主流程

func _on_item_gift_button_pressed(
	item_data, target_player_index: int, source_player_index: int
) -> void:
	if item_data == null or not (item_data is StbItemData):
		return
	if item_data is StbCharacterData or item_data is StbConsumableData or item_data is StbUpgradeData:
		return
	if item_data.my_id == "item_hourglass":
		return
	if item_data.my_id in AGIFT_BLOCKED_ITEM_IDS:
		StbLog.info("gift: blocked special item '%s'." % item_data.my_id, LOG_NAME)
		return
	if _has_deferred_next_wave_effect(item_data):
		return
	if not _is_valid_gift_target(source_player_index, target_player_index):
		return

	var remaining = StbRun.get_remaining_max_nb_item(item_data, target_player_index)
	if not (remaining > 0 or remaining == -1):
		return

	# 焦点与弹窗清理(非关键,缺失则降级)
	var popup_manager = get("_popup_manager")
	if popup_manager != null and popup_manager.has_method("reset_focus"):
		popup_manager.reset_focus(source_player_index)
	_hide_focused_inventory_popup(source_player_index)
	_clear_player_focus(source_player_index)

	# 记住双方焦点位置,赠送后还原
	var source_gear = _get_gear_container(source_player_index)
	if source_gear != null and not is_instance_valid(source_gear):
		source_gear = null
	var source_focus_index = 0
	if source_gear != null and source_gear.get("items_container") != null:
		source_focus_index = _get_inventory_element_index(source_gear.items_container.get("_elements"), item_data)

	if not _transfer_item(item_data, source_player_index, target_player_index):
		return

	# 目标玩家背包刷新 + 焦点还原
	var target_gear = _get_gear_container(target_player_index)
	if target_gear != null and not is_instance_valid(target_gear):
		target_gear = null
	if target_gear != null:
		var target_elements = null
		if target_gear.get("items_container") != null:
			target_elements = target_gear.items_container.get("_elements")
		var target_focus_index = _get_player_inventory_focus_index(target_player_index, target_elements)
		if target_focus_index != -1:
			_clear_player_focus(target_player_index)
		if target_gear.has_method("set_items_data"):
			target_gear.set_items_data(StbRun.get_player_items(target_player_index))
		if target_focus_index != -1:
			call_deferred("_restore_focus_after_gift", target_player_index, target_focus_index)

	# 源玩家背包刷新 + 焦点还原
	if source_gear != null:
		if source_gear.has_method("set_items_data"):
			source_gear.set_items_data(StbRun.get_player_items(source_player_index))
		call_deferred("_restore_focus_after_gift", source_player_index, source_focus_index)

	# 属性面板刷新
	if has_method("_update_stats"):
		call("_update_stats", source_player_index)
		call("_update_stats", target_player_index)

	# 商店重新加载(道具唯一性/重复购买状态依赖它)
	var source_shop_container = _get_shop_items_container(source_player_index)
	if source_shop_container != null and source_shop_container.has_method("reload_shop_items"):
		source_shop_container.reload_shop_items()
	var target_shop_container = _get_shop_items_container(target_player_index)
	if target_shop_container != null and target_shop_container.has_method("reload_shop_items"):
		target_shop_container.reload_shop_items()

	_play_gift_sound()


func _is_valid_gift_target(source_player_index: int, target_player_index: int) -> bool:
	var pcount = StbRun.get_player_count()
	if pcount < 2:
		return false
	if source_player_index < 0 or source_player_index >= pcount:
		return false
	if target_player_index < 0 or target_player_index >= pcount:
		return false
	return source_player_index != target_player_index


func _has_deferred_next_wave_effect(item_data) -> bool:
	for effect in item_data.effects:
		if effect.key in [
			"hp_start_next_wave",
			"extra_enemies_next_wave",
			"extra_loot_aliens_next_wave",
			"extra_elite_next_wave_chance",
			"gain_random_primary_stats_on_go_to_next_wave",
		]:
			return true
		if effect.custom_key == "stats_next_wave":
			return true
	return false


# ---------------------------------------------------------------- 安全转移

func _transfer_item(item_data: StbItemData, source: int, target: int) -> bool:
	if not (StbRun.stb_has("remove_item") and StbRun.stb_has("add_item")):
		StbLog.error("transfer: StbRun.remove_item/add_item unavailable. Aborted.", LOG_NAME)
		return false

	# 1. 临时摘除会导致 unapply 除零的 StbProjectileEffect(如 长胡子的婴儿/异形眼球)
	var dangerous := []
	var safe_effects := []
	for effect in item_data.effects:
		if effect is StbProjectileEffect:
			var p = StbRun.get_player_effect(effect.key_hash, source)
			if not p.empty() and p[0] <= effect.value:
				dangerous.append(effect)
				continue
		safe_effects.append(effect)

	var original_effects = item_data.effects
	item_data.effects = safe_effects

	# 2. 正常移除(危险 effect 已摘除,不会除零)
	StbRun.remove_item(item_data, source)

	# 3. 还原 effects 并清理源玩家残留数据
	item_data.effects = original_effects
	for effect in dangerous:
		var p = StbRun.get_player_effect(effect.key_hash, source)
		if not p.empty():
			p.resize(0)

	# 4. 添加给目标玩家(不 duplicate: apply 内部会创建独立运行时数据)
	StbRun.add_item(item_data, target)

	# 5. 重建源玩家外观(remove_item_displayed 不恢复被高优先级道具挤掉的旧外观)
	_rebuild_appearances(source)

	StbLog.info("gift: item '%s' P%d -> P%d ok" % [item_data.my_id, source + 1, target + 1], LOG_NAME)
	return true


func _rebuild_appearances(player_index: int) -> void:
	if not (StbRun.stb_has("add_item_displayed") and StbRun.stb_get("players_data") != null):
		return
	var player_data = StbRun.players_data[player_index]
	if player_data == null:
		return
	player_data.appearances.clear()
	for item in player_data.items:
		StbRun.add_item_displayed(item, player_index)


# ---------------------------------------------------------------- 焦点辅助(全部可降级)

func _hide_focused_inventory_popup(player_index: int) -> void:
	if not StbRun.is_coop_run or not has_method("_get_coop_player_container"):
		return
	var player_container = call("_get_coop_player_container", player_index)
	if player_container != null and player_container.has_method("on_hide_focused_inventory_popup"):
		player_container.on_hide_focused_inventory_popup()


func _clear_player_focus(player_index: int) -> void:
	if not StbUtils.stb_has("get_focus_emulator"):
		return
	var focus_emulator = StbUtils.get_focus_emulator(player_index)
	if focus_emulator != null:
		focus_emulator.focused_control = null


func _get_inventory_element_index(inventory, item_data) -> int:
	if inventory == null:
		return 0
	for index in inventory.get_child_count():
		var element = inventory.get_child(index)
		if element != null and element.item == item_data:
			return index
	return 0


func _get_player_inventory_focus_index(player_index: int, inventory) -> int:
	if inventory == null:
		return -1
	if not StbUtils.stb_has("get_focus_emulator"):
		return -1
	var focus_emulator = StbUtils.get_focus_emulator(player_index)
	if focus_emulator == null or focus_emulator.focused_control == null:
		return -1
	var focused_control = focus_emulator.focused_control
	if not inventory.is_a_parent_of(focused_control):
		return -1
	return focused_control.get_index()


func _restore_focus_after_gift(player_index: int, preferred_index: int) -> void:
	# _get_gear_container / _get_shop_items_container / _update_stats / _get_default_focus_control
	# 均为父类(base_shop)继承方法,直接调用;若 1.2 改名会在加载期报 parse error,
	# 由诊断日志暴露后跟进适配。
	var gear = _get_gear_container(player_index)
	if gear != null and gear.get("items_container") != null:
		var items_container = gear.items_container
		if items_container.has_method("get_element_count"):
			var item_count = items_container.get_element_count()
			if item_count > 0:
				var index = int(clamp(preferred_index, 0, item_count - 1))
				var element = items_container.get_element(index)
				if element != null and StbUtils.stb_has("focus_player_control"):
					StbUtils.focus_player_control(element, player_index)
					return

	if has_method("_get_default_focus_control") and StbUtils.stb_has("focus_player_control"):
		StbUtils.focus_player_control(call("_get_default_focus_control", player_index), player_index)


# ---------------------------------------------------------------- 音效

func _play_gift_sound() -> void:
	var sounds = get("recycle_sounds")
	if sounds == null or not (sounds is Array) or sounds.empty():
		return
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager == null or not StbUtils.stb_has("get_rand_element"):
		return
	if sound_manager.has_method("play"):
		sound_manager.play(StbUtils.get_rand_element(sounds), 0, 0.1, true)
