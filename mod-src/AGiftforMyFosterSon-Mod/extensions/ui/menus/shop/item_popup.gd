extends "res://ui/menus/shop/item_popup.gd"

# AGiftforMyFosterSon — item_popup 扩展
# 设计原则(与 ShareWithYourBro 的关键差异):
#  1. 绝不硬编码原生按钮焦点链(1.2 的 Mechanize 等新按钮因此不受影响)
#  2. 所有原生成员通过 get()/has_method() 动态探测,缺失时安全降级并写日志
#  3. 唯一被临时修改的原生属性: _cancel_button.focus_neighbour_top,且保存原值、可完整还原
#  4. 内置一次性布局诊断,把 1.2 实际 UI 结构写进 godot.log,便于远程适配

signal item_gift_button_pressed(item_data, target_player_index)

const LOG_NAME = "AGiftforMyFosterSon-Mod:Popup"

# 参考同类 mod 的经验:这些道具有特殊挂载行为/平衡问题,Coop Trading 明确拉黑
const AGIFT_BLOCKED_ITEM_IDS = ["item_celery_tea", "item_lure", "item_peacock"]

var _gift_buttons_by_target := {}
var _vanilla_cancel_top := NodePath()
var _cancel_top_patched := false
var _layout_logged := false
var _sell_mod_logged := false
var _targets_logged := false


func _ready() -> void:
	call_deferred("_giftbro_ready")


func _giftbro_ready() -> void:
	_log_compat_once()
	_ensure_gift_buttons()


# ---------------------------------------------------------------- 冗余刷新挂载点
# 主挂载点是 _update_button_visibilities;focus/hide 两个父类方法作为备用触发,
# 即使主挂载点在某个版本改名,按钮可见性仍能跟随弹窗状态(参考 ZloiDed 的多挂载点模式)。

func focus() -> void:
	.focus()
	_giftbro_refresh_visibility()


func hide(_player_index = -1) -> void:
	.hide(_player_index)
	_giftbro_refresh_visibility()


func _giftbro_refresh_visibility() -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var item_data = get("_item_data")
	if _is_giftable_item(item_data) and RunData.is_coop_run and RunData.get_player_count() >= 2:
		call_deferred("_update_button_visibilities")


# ---------------------------------------------------------------- 兼容性诊断

func _log_compat_once() -> void:
	if _layout_logged:
		return
	_layout_logged = true

	var base = get_script().get_base_script()
	ModLoaderLog.info("diag: base_script=%s has_ready=%s" % [
		base.resource_path if base != null else "<null>",
		str(base.has_method("_ready")) if base != null else "?"
	], LOG_NAME)

	var anchor = _get_anchor_button()
	if anchor == null:
		ModLoaderLog.error("diag: no anchor button found (neither _discard_button nor _cancel_button). Gift UI disabled.", LOG_NAME)
		return

	var parent = anchor.get_parent()
	if parent == null:
		ModLoaderLog.error("diag: anchor button has no parent container. Gift UI disabled.", LOG_NAME)
		return

	var layout := []
	for child in parent.get_children():
		if child is Button:
			layout.append("%s(v=%s,focus_enabled=%s)" % [child.name, str(child.visible), str(child.focus_mode != Control.FOCUS_NONE)])
	ModLoaderLog.info("diag: popup button layout -> %s" % str(layout), LOG_NAME)

	for probe in ["_combine_button", "_discard_button", "_cancel_button", "_item_data", "player_index", "_focused", "buttons_enabled"]:
		ModLoaderLog.info("diag: member '%s' present=%s" % [probe, str(get(probe) != null)], LOG_NAME)


# ---------------------------------------------------------------- 按钮注入

func _get_anchor_button():
	# 动态选锚点:优先 _discard_button,退而求其次 _cancel_button,再退而求其次容器里最后一个按钮
	for member in ["_discard_button", "_cancel_button"]:
		var btn = get(member)
		if btn is Button and btn.get_parent() != null:
			return btn
	return null


func _get_button_parent():
	var anchor = _get_anchor_button()
	if anchor != null:
		return anchor.get_parent()
	return null


func _get_insert_index(parent) -> int:
	# 插到取消按钮之前(保持"赠送→取消"的顺序);没有取消按钮就排到末尾
	var cancel = get("_cancel_button")
	if cancel is Button and cancel.get_parent() == parent:
		return cancel.get_index()
	return parent.get_child_count()


func _ensure_gift_buttons() -> void:
	if not (RunData.is_coop_run and RunData.get_player_count() >= 2):
		return

	var parent = _get_button_parent()
	if parent == null:
		return

	for target_index in RunData.get_player_count():
		var own_index = get("player_index")
		if target_index == own_index:
			continue
		if _gift_buttons_by_target.has(target_index):
			continue
		var gift_button = _create_gift_button(target_index)
		if gift_button == null:
			return
		_gift_buttons_by_target[target_index] = gift_button
		parent.add_child(gift_button)
		parent.move_child(gift_button, _get_insert_index(parent))


func _create_gift_button(target_player_index: int):
	var cancel = get("_cancel_button")
	var anchor = _get_anchor_button()
	if not (cancel is Button) and anchor == null:
		return null
	if cancel is Button and not is_instance_valid(cancel):
		return null
	var template: Button = cancel if cancel is Button else anchor

	var gift_button: Button

	# 三级回退构建,样式尽量跟随当前版本 UI 主题(参考 ZloiDed 的 _build_trade_button):
	# 1) 游戏自带菜单按钮脚本(存在则用,样式最标准)
	# 2) duplicate 取消按钮(主题全套继承,需清子节点+断连)
	# 3) 裸 Button + 手动拷主题
	if ResourceLoader.exists("res://ui/menus/global/my_menu_button.gd"):
		gift_button = load("res://ui/menus/global/my_menu_button.gd").new()
		gift_button.theme = template.theme
		var dfont = template.get_font("font")
		if dfont != null:
			gift_button.add_font_override("font", dfont)
		var normal_style = template.get_stylebox("normal")
		if normal_style != null:
			gift_button.add_stylebox_override("normal", normal_style.duplicate())
		gift_button.rect_min_size = template.rect_min_size
		gift_button.size_flags_horizontal = template.size_flags_horizontal
		gift_button.size_flags_vertical = template.size_flags_vertical
	elif cancel is Button:
		gift_button = cancel.duplicate()
		for child in gift_button.get_children():
			child.free()
	else:
		gift_button = Button.new()
		var dtheme = anchor.theme
		if dtheme != null:
			gift_button.theme = dtheme
		var dfont2 = anchor.get_font("font")
		if dfont2 != null:
			gift_button.add_font_override("font", dfont2)

	gift_button.name = "AGiftP" + str(target_player_index + 1)
	gift_button.text = _get_gift_button_text(target_player_index)
	gift_button.focus_mode = Control.FOCUS_NONE
	gift_button.hint_tooltip = ""

	# duplicate() 会复制场景里编辑器连接的信号;全部断开,避免按下赠送误触发取消等原生逻辑
	for conn in gift_button.get_signal_connection_list("pressed"):
		if conn.target != self:
			gift_button.disconnect("pressed", conn.target, conn.method)

	if gift_button.is_connected("pressed", self, "_on_GiftButton_pressed"):
		gift_button.disconnect("pressed", self, "_on_GiftButton_pressed")
	gift_button.connect("pressed", self, "_on_GiftButton_pressed", [target_player_index])
	gift_button.hide()
	return gift_button


func _get_gift_button_text(target_player_index: int) -> String:
	if RunData.get_player_count() <= 2:
		return tr("AGIFT_GIFT")
	return tr("AGIFT_GIFT_TO_PLAYER").replace("{player}", _get_target_display_name(target_player_index))


# 目标显示名:优先带角色名(多人局里能一眼看出按钮指向谁),取不到时回退 P2/P3/P4
func _get_target_display_name(target_player_index: int) -> String:
	var character_name = _get_player_character_name(target_player_index)
	if character_name != "":
		return "%s (P%d)" % [character_name, target_player_index + 1]
	return "P%d" % (target_player_index + 1)


func _get_player_character_name(target_player_index: int) -> String:
	# 参考 ZloiDed 的取名实现(经 1.1.x 实测),全部动态探测
	if RunData.get("players_data") == null:
		return ""
	var players = RunData.players_data
	if target_index_out_of_range(target_player_index, players.size()):
		return ""
	var player_data = players[target_player_index]
	if player_data == null:
		return ""
	var character = player_data.get("current_character")
	if character == null:
		return ""
	var name_key = character.get("name_key")
	if name_key is String and name_key != "":
		var translated = TranslationServer.translate(name_key)
		if translated != name_key:
			return translated
	var raw_name = character.get("name")
	if raw_name is String and raw_name != "":
		var translated_name = TranslationServer.translate(raw_name)
		return translated_name if translated_name != raw_name else raw_name
	return ""


func target_index_out_of_range(index: int, count: int) -> bool:
	return index < 0 or index >= count


# ---------------------------------------------------------------- 可见性接管

func should_show_buttons(item_data, focused: bool) -> bool:
	if _is_giftable_item(item_data) \
		and RunData.is_coop_run \
		and RunData.get_player_count() >= 2:
		var enabled = get("buttons_enabled")
		return (enabled == null or bool(enabled)) and focused
	return .should_show_buttons(item_data, focused)


func _update_button_visibilities() -> void:
	var item_data = get("_item_data")
	if _is_giftable_item(item_data) and RunData.is_coop_run and RunData.get_player_count() >= 2:
		# 可赠送道具:完全自行管理(原版路径里有按 WeaponData 断言的逻辑,如 can_combine)
		_update_button_visibilities_for_gift()
		return

	# 其余一切(武器/不可赠送物):完整走原版逻辑,Mechanize 等新按钮不受任何影响
	._update_button_visibilities()
	_hide_all_gift_buttons()
	_restore_cancel_focus_top()


func _update_button_visibilities_for_gift() -> void:
	_ensure_gift_buttons()
	_hide_vanilla_action_buttons()

	var enabled = get("buttons_enabled")
	var focused = get("_focused")
	if enabled == null or not bool(enabled) or focused == null or not bool(focused):
		var cancel = get("_cancel_button")
		if cancel is Button:
			cancel.hide()
			cancel.focus_mode = Control.FOCUS_NONE
		_hide_all_gift_buttons()
		_restore_cancel_focus_top()
		return

	var cancel = get("_cancel_button")
	if cancel is Button:
		cancel.show()
		cancel.focus_mode = Control.FOCUS_ALL
	_update_gift_button_visibilities()
	_wire_gift_focus_chain()


func _hide_vanilla_action_buttons() -> void:
	# 只隐藏"动作"按钮,取消按钮保留(由赠送流程接管焦点)
	for member in ["_combine_button", "_discard_button"]:
		# 与 ItemSelling 类 mod 和平共处:检测到时不动回收按钮(它的出售按钮挂在回收位)
		if member == "_discard_button" and _is_other_sell_mod_present():
			continue
		var btn = get(member)
		if btn is Button and is_instance_valid(btn):
			btn.hide()
			btn.focus_mode = Control.FOCUS_NONE
	# 1.2 可能新增的其他原生按钮(如 Mechanize):一并按名字探测隐藏,避免与赠送流程打架
	for extra_name in ["_mechanize_button", "_mechanize_button_container"]:
		var extra = get(extra_name)
		if extra is Control and is_instance_valid(extra):
			extra.hide()


func _is_other_sell_mod_present() -> bool:
	# 参考 ZloiDed 对 RobocrafterLP-ItemSelling 的显式适配
	var store = get_node_or_null("/root/ModLoaderStore")
	if store == null or not ("mod_data" in store):
		return false
	var mod_data = store.get("mod_data")
	if mod_data is Dictionary and mod_data.has("RobocrafterLP-ItemSelling"):
		if not _sell_mod_logged:
			_sell_mod_logged = true
			ModLoaderLog.info("compat: RobocrafterLP-ItemSelling detected — keep discard button visible.", LOG_NAME)
		return true
	return false


func _update_gift_button_visibilities() -> void:
	var item_data = get("_item_data")
	if not _is_giftable_item(item_data) \
		or not RunData.is_coop_run \
		or RunData.get_player_count() < 2:
		_hide_all_gift_buttons()
		return

	var own_index = get("player_index")
	var valid_targets := []
	for target_index in RunData.get_player_count():
		if target_index != own_index:
			valid_targets.push_back(target_index)

	# 清理:已释放的悬空引用(弹窗整树重建) + 误建的"送给自己"按钮(player_index 晚设置时的残留)
	for target_index in _gift_buttons_by_target.keys():
		if not is_instance_valid(_gift_buttons_by_target[target_index]) or target_index == own_index:
			_gift_buttons_by_target.erase(target_index)

	# 多人诊断:每个弹窗记录一次"自己是谁/给谁建了按钮",3/4人实测核对一目了然
	if not _targets_logged and valid_targets.size() > 0:
		_targets_logged = true
		ModLoaderLog.info("diag: popup of P%s -> gift buttons for %s" % [
			str(int(own_index) + 1 if own_index != null else -1),
			str(valid_targets)
		], LOG_NAME)

	for target_index in _gift_buttons_by_target.keys():
		var gift_button: Button = _gift_buttons_by_target[target_index]
		if not valid_targets.has(target_index):
			gift_button.hide()
			gift_button.focus_mode = Control.FOCUS_NONE
			continue

		gift_button.text = _get_gift_button_text(target_index)
		gift_button.show()

		# 每个目标独立检查持有上限;注意 1.1.x 起 -1 表示无上限
		var remaining = RunData.get_remaining_max_nb_item(item_data, target_index)
		var can_gift = remaining > 0 or remaining == -1
		gift_button.disabled = not can_gift
		gift_button.focus_mode = Control.FOCUS_ALL if can_gift else Control.FOCUS_NONE
		gift_button.modulate = Color(1, 1, 1, 1) if can_gift else Color(0.5, 0.5, 0.5, 1)
		gift_button.hint_tooltip = "" if can_gift else tr("AGIFT_TARGET_FULL")


# ---------------------------------------------------------------- 焦点管理
# 只在自己注入的按钮之间组链,并临时把取消键的"上"指向链尾;
# 不触碰任何其他原生按钮的焦点属性。

func _wire_gift_focus_chain() -> void:
	var focus_buttons = _get_focusable_gift_buttons()
	if focus_buttons.empty():
		_restore_cancel_focus_top()
		return

	var buttons = focus_buttons.duplicate()
	var cancel = get("_cancel_button")
	if cancel is Button:
		buttons.push_back(cancel)

	for i in buttons.size():
		var button: Button = buttons[i]
		var previous_button: Button = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next_button: Button = buttons[(i + 1) % buttons.size()]

		if _gift_buttons_by_target.values().has(button):
			button.focus_neighbour_top = button.get_path_to(previous_button)
			button.focus_neighbour_bottom = button.get_path_to(next_button)
			button.focus_neighbour_left = NodePath(".")
			button.focus_neighbour_right = NodePath(".")
			button.focus_next = button.get_path_to(next_button)
			button.focus_previous = button.get_path_to(previous_button)

	# 唯一的原生属性补丁:取消键向上 → 我的链尾(仅当按钮可见时)
	if cancel is Button:
		_patch_cancel_focus_top(buttons[buttons.size() - 2])


func _patch_cancel_focus_top(last_gift_button: Button) -> void:
	var cancel = get("_cancel_button")
	if not (cancel is Button):
		return
	if not _cancel_top_patched:
		_vanilla_cancel_top = cancel.focus_neighbour_top
		_cancel_top_patched = true
	cancel.focus_neighbour_top = cancel.get_path_to(last_gift_button)


func _restore_cancel_focus_top() -> void:
	if not _cancel_top_patched:
		return
	var cancel = get("_cancel_button")
	if cancel is Button:
		cancel.focus_neighbour_top = _vanilla_cancel_top
	_cancel_top_patched = false


func _get_focusable_gift_buttons() -> Array:
	var buttons := []
	for gift_button in _gift_buttons_by_target.values():
		if is_instance_valid(gift_button) and gift_button.visible and not gift_button.disabled:
			buttons.push_back(gift_button)
	return buttons


func _hide_all_gift_buttons() -> void:
	for gift_button in _gift_buttons_by_target.values():
		if is_instance_valid(gift_button):
			gift_button.hide()
			gift_button.focus_mode = Control.FOCUS_NONE


# ---------------------------------------------------------------- 赠送判定

static func _is_giftable_item(item_data) -> bool:
	if item_data == null:
		return false
	if not (item_data is ItemData):
		return false
	if item_data is CharacterData:
		return false
	if item_data is ConsumableData:
		return false
	if item_data is UpgradeData:
		return false
	if item_data.my_id == "item_hourglass":
		return false
	if item_data.my_id in AGIFT_BLOCKED_ITEM_IDS:
		return false
	if _has_deferred_next_wave_effect(item_data):
		return false
	return true


static func _has_deferred_next_wave_effect(item_data) -> bool:
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


# ---------------------------------------------------------------- 事件

func _on_GiftButton_pressed(target_player_index: int) -> void:
	var gift_button = _gift_buttons_by_target.get(target_player_index)
	if gift_button != null and gift_button.disabled:
		return
	var item_data = get("_item_data")
	var focused = get("_focused")
	if focused != null:
		set("_focused", false)
	# 双通道派发:正常走信号;若信号无人监听(其他 mod 的 _ready 链断掉了我方接线,
	# 如联机类 mod 不调用父类 _ready),直接向上找到商店节点调用处理方法
	if get_signal_connection_list("item_gift_button_pressed").empty():
		_giftbro_direct_transfer(item_data, target_player_index)
	else:
		emit_signal("item_gift_button_pressed", item_data, target_player_index)


func _giftbro_direct_transfer(item_data, target_player_index: int) -> void:
	var own_index = get("player_index")
	var node = get_parent()
	while node != null:
		if node != self and node.has_method("_on_item_gift_button_pressed"):
			node.call("_on_item_gift_button_pressed", item_data, target_player_index, own_index)
			return
		node = node.get_parent()
	ModLoaderLog.error("gift: signal not connected and no shop handler found in ancestors.", LOG_NAME)
