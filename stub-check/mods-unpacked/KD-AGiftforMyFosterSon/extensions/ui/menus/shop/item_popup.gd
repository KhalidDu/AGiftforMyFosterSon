extends "res://ui/menus/shop/item_popup.gd"
const StbLog = preload("res://stubs/mod_loader_log.gd")
const StbMod = preload("res://stubs/mod_loader_mod.gd")
const StbRun = preload("res://stubs/run_data.gd")
const StbUtils = preload("res://stubs/utils.gd")
const StbItemData = preload("res://stubs/item_data.gd")
const StbCharacterData = preload("res://stubs/character_data.gd")
const StbConsumableData = preload("res://stubs/consumable_data.gd")
const StbUpgradeData = preload("res://stubs/upgrade_data.gd")
const StbProjectileEffect = preload("res://stubs/projectile_effect.gd")
const StbWeaponData = preload("res://stubs/weapon_data.gd")

# AGiftforMyFosterSon — item_popup 扩展
# 设计原则(与 ShareWithYourBro 的关键差异):
#  1. 绝不硬编码原生按钮焦点链(1.2 的 Mechanize 等新按钮因此不受影响)
#  2. 所有原生成员通过 get()/has_method() 动态探测,缺失时安全降级并写日志
#  3. 唯一被临时修改的原生属性: _cancel_button.focus_neighbour_top,且保存原值、可完整还原
#  4. 内置一次性布局诊断,把 1.2 实际 UI 结构写进 godot.log,便于远程适配
#  5. v0.1.7: 赠送执行逻辑收敛到本扩展。1.2.0.1 的 base_shop.gdc 字节码损坏,
#     凡继承链经过 BaseShop 的脚本(base_shop/coop_shop/shop)都无法被 GML 扩展
#     按路径加载;item_popup→BasePopup 链路健康,商店/容器服务改为向上探测获取。
#  6. v0.1.8: 武器可赠送。原版动作按钮(合成/机械化/回收)照常工作,赠送按钮
#     叠加显示;转移用 StbRun.remove_weapon/add_weapon,add_weapon 内部
#     duplicate() 会带上 meca_power/meca_rank(机械化状态),栏位满时按钮灰显。

signal item_gift_button_pressed(item_data, target_player_index)

const LOG_NAME = "KD-AGiftforMyFosterSon:Popup"

# 参考同类 mod 的经验:这些道具有特殊挂载行为/平衡问题,Coop Trading 明确拉黑
const AGIFT_BLOCKED_ITEM_IDS = ["item_celery_tea", "item_lure", "item_peacock"]

var _gift_buttons_by_target := {}
var _vanilla_cancel_top := NodePath()
var _cancel_top_patched := false
var _vanilla_above_bottom := NodePath()
var _above_button_path := NodePath()
var _above_bottom_patched := false
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
	if _is_giftable_item(item_data) and StbRun.is_coop_run and StbRun.get_player_count() >= 2:
		call_deferred("_update_button_visibilities")


# ---------------------------------------------------------------- 兼容性诊断

func _log_compat_once() -> void:
	if _layout_logged:
		return
	_layout_logged = true

	var base = get_script().get_base_script()
	StbLog.info("diag: base_script=%s has_ready=%s" % [
		base.resource_path if base != null else "<null>",
		str(base.has_method("_ready")) if base != null else "?"
	], LOG_NAME)

	var anchor = _get_anchor_button()
	if anchor == null:
		StbLog.error("diag: no anchor button found (neither _discard_button nor _cancel_button). Gift UI disabled.", LOG_NAME)
		return

	var parent = anchor.get_parent()
	if parent == null:
		StbLog.error("diag: anchor button has no parent container. Gift UI disabled.", LOG_NAME)
		return

	var layout := []
	for child in parent.get_children():
		if child is Button:
			layout.append("%s(v=%s,focus_enabled=%s)" % [child.name, str(child.visible), str(child.focus_mode != Control.FOCUS_NONE)])
	StbLog.info("diag: popup button layout -> %s" % str(layout), LOG_NAME)

	for probe in ["_combine_button", "_discard_button", "_cancel_button", "_item_data", "player_index", "_focused", "buttons_enabled"]:
		StbLog.info("diag: member '%s' present=%s" % [probe, str(get(probe) != null)], LOG_NAME)


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
	if not (StbRun.is_coop_run and StbRun.get_player_count() >= 2):
		return

	var parent = _get_button_parent()
	if parent == null:
		return

	for target_index in StbRun.get_player_count():
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
	if StbRun.get_player_count() <= 2:
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
	if StbRun.stb_get("players_data") == null:
		return ""
	var players = StbRun.players_data
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
		and StbRun.is_coop_run \
		and StbRun.get_player_count() >= 2:
		var enabled = get("buttons_enabled")
		return (enabled == null or bool(enabled)) and focused
	return .should_show_buttons(item_data, focused)


func _update_button_visibilities() -> void:
	var item_data = get("_item_data")
	if _is_giftable_item(item_data) and StbRun.is_coop_run and StbRun.get_player_count() >= 2:
		if item_data is StbWeaponData:
			# v0.1.8 武器:原版动作按钮(合成/机械化/回收)照常工作,赠送按钮叠加显示
			._update_button_visibilities()
			_update_weapon_gift_overlay()
			return
		# 可赠送道具:完全自行管理(原版路径里有按 StbWeaponData 断言的逻辑,如 can_combine)
		_update_button_visibilities_for_gift()
		return

	# 其余一切(不可赠送物):完整走原版逻辑,Mechanize 等新按钮不受任何影响
	._update_button_visibilities()
	_hide_all_gift_buttons()
	_restore_cancel_focus_top()


func _update_weapon_gift_overlay() -> void:
	# 武器弹窗不接管原版按钮,只负责赠送按钮自身的显示/灰显与焦点接入
	_ensure_gift_buttons()
	var enabled = get("buttons_enabled")
	var focused = get("_focused")
	if enabled == null or not bool(enabled) or focused == null or not bool(focused):
		_hide_all_gift_buttons()
		_restore_cancel_focus_top()
		return
	# v0.1.12: 机械化效果选择子界面打开期间不显示赠送按钮(避免赠送与效果选择
	# 两套流程同时在弹窗里生效,该状态下 EffectButton 也接管了取消键的导航)
	var effect_choice = get("_effect_choice_container")
	if effect_choice is Control and is_instance_valid(effect_choice) and effect_choice.visible:
		_hide_all_gift_buttons()
		_restore_cancel_focus_top()
		return
	_update_gift_button_visibilities()
	_wire_weapon_gift_focus()


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
	# v0.1.12: _upgrade_button(1.2 的机械化/升级按钮)必须一并隐藏——
	# 道具模式不走原版可见性逻辑,武器弹窗切到道具弹窗时它会残留显示且仍可点击
	for member in ["_combine_button", "_discard_button", "_upgrade_button"]:
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
			StbLog.info("compat: RobocrafterLP-ItemSelling detected — keep discard button visible.", LOG_NAME)
		return true
	return false


func _update_gift_button_visibilities() -> void:
	var item_data = get("_item_data")
	if not _is_giftable_item(item_data) \
		or not StbRun.is_coop_run \
		or StbRun.get_player_count() < 2:
		_hide_all_gift_buttons()
		return

	var own_index = get("player_index")
	var valid_targets := []
	for target_index in StbRun.get_player_count():
		if target_index != own_index:
			valid_targets.push_back(target_index)

	# 清理:已释放的悬空引用(弹窗整树重建) + 误建的"送给自己"按钮(player_index 晚设置时的残留)
	for target_index in _gift_buttons_by_target.keys():
		if not is_instance_valid(_gift_buttons_by_target[target_index]) or target_index == own_index:
			_gift_buttons_by_target.erase(target_index)

	# 多人诊断:每个弹窗记录一次"自己是谁/给谁建了按钮",3/4人实测核对一目了然
	if not _targets_logged and valid_targets.size() > 0:
		_targets_logged = true
		StbLog.info("diag: popup of P%s -> gift buttons for %s" % [
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

		# 每个目标独立检查上限:道具为持有上限(1.1.x 起 -1 表示无上限),武器为武器栏空位
		var can_gift: bool
		if item_data is StbWeaponData:
			can_gift = StbRun.stb_has("player_has_weapon_slots") and StbRun.player_has_weapon_slots(target_index)
		else:
			var remaining = StbRun.get_remaining_max_nb_item(item_data, target_index)
			can_gift = remaining > 0 or remaining == -1
		gift_button.disabled = not can_gift
		gift_button.focus_mode = Control.FOCUS_ALL if can_gift else Control.FOCUS_NONE
		gift_button.modulate = Color(1, 1, 1, 1) if can_gift else Color(0.5, 0.5, 0.5, 1)
		if can_gift:
			gift_button.hint_tooltip = ""
		elif item_data is StbWeaponData:
			gift_button.hint_tooltip = tr("AGIFT_WEAPON_TARGET_FULL")
		else:
			gift_button.hint_tooltip = tr("AGIFT_TARGET_FULL")


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


func _wire_weapon_gift_focus() -> void:
	# v0.1.9 武器叠加模式专用:线性开链,不组闭环。
	# 道具模式的闭环会把"赠送↔取消"锁死,导致上方原版按钮(合成/机械化/回收)
	# 无法通过方向键到达——它们只是被隐藏,焦点邻居却还指着取消。
	# 武器模式下赠送按钮只在彼此之间线性相连(多人局),首尾交给 Godot 自动导航:
	# 首个按钮"上"→上方最近的原版按钮,最后一个"下"→取消;
	# 取消键"上"仍指向最后一个赠送键(经 _patch_cancel_focus_top,可还原)。
	var focus_buttons = _get_focusable_gift_buttons()
	if focus_buttons.empty():
		_restore_cancel_focus_top()
		return

	for i in focus_buttons.size():
		var button: Button = focus_buttons[i]
		button.focus_neighbour_top = NodePath()
		button.focus_neighbour_bottom = NodePath()
		button.focus_previous = NodePath()
		button.focus_next = NodePath()
		if i > 0:
			button.focus_neighbour_top = button.get_path_to(focus_buttons[i - 1])
			button.focus_previous = button.get_path_to(focus_buttons[i - 1])
		if i < focus_buttons.size() - 1:
			button.focus_neighbour_bottom = button.get_path_to(focus_buttons[i + 1])
			button.focus_next = button.get_path_to(focus_buttons[i + 1])
		button.focus_neighbour_left = NodePath(".")
		button.focus_neighbour_right = NodePath(".")

	var cancel = get("_cancel_button")
	if cancel is Button and cancel.visible:
		_patch_cancel_focus_top(focus_buttons[focus_buttons.size() - 1])
	_patch_above_button_bottom(focus_buttons[0])


func _patch_above_button_bottom(first_gift_button: Button) -> void:
	# v0.1.10 场景把原版动作按钮的"下"烘焙成死三连(合成→机械化→回收→取消),
	# 赠送键插在回收与取消之间后,向下导航会跳过赠送键;
	# 把赠送键上方最近的可见可聚焦控件的"下"临时改指赠送键(原值保存可还原)。
	if first_gift_button == null or not is_instance_valid(first_gift_button):
		return
	var parent = first_gift_button.get_parent()
	if parent == null:
		return
	var above: Control = null
	for i in range(first_gift_button.get_index() - 1, -1, -1):
		var child = parent.get_child(i)
		if child is Control and is_instance_valid(child) and child.visible and child.focus_mode != Control.FOCUS_NONE:
			above = child
			break
	if above == null:
		return
	# 上方按钮可能随合成/机械化可见性变化而切换:先还原旧的,再保存并补丁新的
	if _above_bottom_patched:
		var prev = get_node_or_null(_above_button_path)
		if prev is Control:
			prev.focus_neighbour_bottom = _vanilla_above_bottom
	_vanilla_above_bottom = above.focus_neighbour_bottom
	_above_button_path = get_path_to(above)
	_above_bottom_patched = true
	above.focus_neighbour_bottom = above.get_path_to(first_gift_button)


func _patch_cancel_focus_top(last_gift_button: Button) -> void:
	var cancel = get("_cancel_button")
	if not (cancel is Button):
		return
	if not _cancel_top_patched:
		_vanilla_cancel_top = cancel.focus_neighbour_top
		_cancel_top_patched = true
	cancel.focus_neighbour_top = cancel.get_path_to(last_gift_button)


func _restore_cancel_focus_top() -> void:
	# 同时还原取消键"上"与上方原版按钮"下"两处临时焦点补丁
	if _cancel_top_patched:
		var cancel = get("_cancel_button")
		if cancel is Button:
			cancel.focus_neighbour_top = _vanilla_cancel_top
		_cancel_top_patched = false
	if _above_bottom_patched:
		var prev = get_node_or_null(_above_button_path)
		if prev is Control:
			prev.focus_neighbour_bottom = _vanilla_above_bottom
		_above_bottom_patched = false


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
	if item_data is StbWeaponData:
		# v0.1.8: 武器可赠送;栏位检查在按钮灰显与转移守卫两处独立进行
		return not _has_deferred_next_wave_effect(item_data)
	if not (item_data is StbItemData):
		return false
	if item_data is StbCharacterData:
		return false
	if item_data is StbConsumableData:
		return false
	if item_data is StbUpgradeData:
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
	# 双通道派发:正常走信号(供其他 mod 集成);无人监听则由本扩展直接执行。
	# v0.1.7: 1.2.0.1 的 base_shop.gdc 字节码损坏,base_shop/coop_shop/shop
	# 继承链均无法被 GML 扩展加载,赠送执行逻辑全部收敛到本扩展
	# (item_popup→BasePopup 链路健康),商店服务通过向上探测动态获取。
	if get_signal_connection_list("item_gift_button_pressed").empty():
		_giftbro_transfer_to(item_data, target_player_index)
	else:
		emit_signal("item_gift_button_pressed", item_data, target_player_index)


# ---------------------------------------------------------------- 赠送执行(v0.1.7 自带,不再依赖商店侧扩展)

func _giftbro_transfer_to(item_data, target_player_index: int) -> void:
	var own_index = get("player_index")
	if not _is_giftable_item(item_data):
		return
	if not _is_valid_gift_target(own_index, target_player_index):
		return

	# 上限守卫:道具为持有上限,武器为武器栏空位(与按钮灰显逻辑双保险)
	var is_weapon = item_data is StbWeaponData
	if is_weapon:
		if StbRun.stb_has("player_has_weapon_slots") and not StbRun.player_has_weapon_slots(target_player_index):
			return
	else:
		var remaining = StbRun.get_remaining_max_nb_item(item_data, target_player_index)
		if not (remaining > 0 or remaining == -1):
			return

	# 弹窗与焦点清理:reset_focus 是原版取消/合成/回收后的正规收尾(隐藏弹窗面板本体),
	# 仅隐藏 dim 遮罩层并不关弹窗——v0.1.7 重构遗漏此调用,导致赠送武器后弹窗残留、
	# 半模态状态下按 ESC 焦点死锁(道具路径靠重建背包元素侥幸关闭,武器路径暴露)
	var shop = _giftbro_find_ancestor("_giftbro_is_shop")
	var popup_manager = shop.get("_popup_manager") if shop != null else null
	if popup_manager != null and popup_manager.has_method("reset_focus"):
		popup_manager.reset_focus(own_index)
	var own_container = _giftbro_get_player_container(own_index)
	if own_container != null and own_container.has_method("on_hide_focused_inventory_popup"):
		own_container.on_hide_focused_inventory_popup()
	_clear_player_focus(own_index)

	# 记住双方焦点位置,赠送后还原
	var source_gear = own_container.get("player_gear_container") if own_container != null else null
	if source_gear != null and not is_instance_valid(source_gear):
		source_gear = null
	var source_focus_index = _get_inventory_element_index(
		_giftbro_elements_of(source_gear, is_weapon),
		item_data
	)

	var transfer_ok = false
	if is_weapon:
		transfer_ok = _giftbro_transfer_weapon(item_data, own_index, target_player_index)
	else:
		transfer_ok = _giftbro_transfer_item(item_data, own_index, target_player_index)
	if not transfer_ok:
		return

	# 目标玩家背包/属性刷新 + 焦点还原
	var target_container = _giftbro_get_player_container(target_player_index)
	var target_gear = target_container.get("player_gear_container") if target_container != null else null
	if target_gear != null and not is_instance_valid(target_gear):
		target_gear = null
	if target_gear != null:
		var target_focus_index = _get_player_inventory_focus_index(target_player_index, _giftbro_elements_of(target_gear, is_weapon))
		if target_focus_index != -1:
			_clear_player_focus(target_player_index)
		if is_weapon and target_gear.has_method("set_weapons_data"):
			target_gear.set_weapons_data(StbRun.get_player_weapons(target_player_index))
		elif not is_weapon and target_gear.has_method("set_items_data"):
			target_gear.set_items_data(StbRun.get_player_items(target_player_index))
		if target_focus_index != -1:
			call_deferred("_restore_focus_after_gift", target_player_index, target_focus_index, is_weapon)
	if target_container != null and target_container.has_method("update_stats"):
		target_container.update_stats()

	# 源玩家背包/属性刷新 + 焦点还原
	if source_gear != null:
		if is_weapon and source_gear.has_method("set_weapons_data"):
			source_gear.set_weapons_data(StbRun.get_player_weapons(own_index))
		elif not is_weapon and source_gear.has_method("set_items_data"):
			source_gear.set_items_data(StbRun.get_player_items(own_index))
	call_deferred("_restore_focus_after_gift", own_index, source_focus_index, is_weapon)
	if own_container != null and own_container.has_method("update_stats"):
		own_container.update_stats()

	# 商店货架重新加载(道具唯一性/重复购买状态依赖它)
	if own_container != null:
		var own_shop_items = own_container.get("shop_items_container")
		if own_shop_items != null and own_shop_items.has_method("reload_shop_items"):
			own_shop_items.reload_shop_items()
	if target_container != null:
		var target_shop_items = target_container.get("shop_items_container")
		if target_shop_items != null and target_shop_items.has_method("reload_shop_items"):
			target_shop_items.reload_shop_items()

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


# ---------------------------------------------------------------- 祖先服务探测
# CoopShopPlayerContainer(自带 player_gear_container/shop_items_container/
# update_stats/on_hide_focused_inventory_popup)与 CoopShop(_get_coop_
# player_container/_popup_manager/recycle_sounds)都不扩展,按成员/方法探测。

func _giftbro_find_ancestor(checker) -> Node:
	var node = get_parent()
	while node != null:
		if node != self and call(checker, node):
			return node
		node = node.get_parent()
	return null


func _giftbro_is_player_container(node) -> bool:
	return node.get("player_gear_container") != null and node.get("item_popup") != null


func _giftbro_is_shop(node) -> bool:
	return node.has_method("_get_coop_player_container")


func _giftbro_get_player_container(player_index: int):
	if player_index == get("player_index"):
		return _giftbro_find_ancestor("_giftbro_is_player_container")
	var shop = _giftbro_find_ancestor("_giftbro_is_shop")
	if shop != null:
		var container = shop.call("_get_coop_player_container", player_index)
		if container != null and is_instance_valid(container):
			return container
	return null


# ---------------------------------------------------------------- 安全转移

func _giftbro_elements_of(gear, is_weapon: bool):
	# 取背包容器里的元素节点(武器/道具分列),供焦点记录与还原使用
	if gear == null or not is_instance_valid(gear):
		return null
	var inventory_container = gear.get("weapons_container") if is_weapon else gear.get("items_container")
	if inventory_container == null:
		return null
	return inventory_container.get("_elements")


func _giftbro_transfer_weapon(weapon: StbWeaponData, source: int, target: int) -> bool:
	if not (StbRun.stb_has("remove_weapon") and StbRun.stb_has("add_weapon")):
		StbLog.error("transfer: StbRun.remove_weapon/add_weapon unavailable. Aborted.", LOG_NAME)
		return false
	if StbRun.stb_has("player_has_weapon_slots") and not StbRun.player_has_weapon_slots(target):
		StbLog.info("gift: target P%d weapon slots full, aborted." % (target + 1), LOG_NAME)
		return false

	# StbProjectileEffect 防护与道具路径一致:临时摘除避免 unapply 除零
	var dangerous := []
	var safe_effects := []
	for effect in weapon.effects:
		if effect is StbProjectileEffect:
			var p = StbRun.get_player_effect(effect.key_hash, source)
			if not p.empty() and p[0] <= effect.value:
				dangerous.append(effect)
				continue
		safe_effects.append(effect)

	var original_effects = weapon.effects
	weapon.effects = safe_effects
	StbRun.remove_weapon(weapon, source)
	weapon.effects = original_effects
	for effect in dangerous:
		var p = StbRun.get_player_effect(effect.key_hash, source)
		if not p.empty():
			p.resize(0)

	# add_weapon 内部 duplicate(),meca_power/meca_rank(机械化状态)随副本转移到目标
	StbRun.add_weapon(weapon, target)

	StbLog.info("gift: weapon '%s' P%d -> P%d ok" % [weapon.my_id, source + 1, target + 1], LOG_NAME)
	return true


func _giftbro_transfer_item(item_data: StbItemData, source: int, target: int) -> bool:
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


# ---------------------------------------------------------------- 焦点/音效辅助(全部可降级)

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


func _restore_focus_after_gift(player_index: int, preferred_index: int, is_weapon: bool = false) -> void:
	var container = _giftbro_get_player_container(player_index)
	var gear = container.get("player_gear_container") if container != null else null
	if gear != null:
		var inventory_container = gear.get("weapons_container") if is_weapon else gear.get("items_container")
		if inventory_container != null and inventory_container.has_method("get_element_count"):
			var element_count = inventory_container.get_element_count()
			if element_count > 0:
				var index = int(clamp(preferred_index, 0, element_count - 1))
				var element = inventory_container.get_element(index)
				if element != null and StbUtils.stb_has("focus_player_control"):
					StbUtils.focus_player_control(element, player_index)
					return

	# 回退:聚焦该玩家的 Go 按钮(容器自带),保证焦点不悬空
	if container != null and container.get("go_button") != null and StbUtils.stb_has("focus_player_control"):
		StbUtils.focus_player_control(container.go_button, player_index)


func _play_gift_sound() -> void:
	var shop = _giftbro_find_ancestor("_giftbro_is_shop")
	var sounds = shop.get("recycle_sounds") if shop != null else null
	if sounds == null or not (sounds is Array) or sounds.empty():
		return
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager == null or not StbUtils.stb_has("get_rand_element"):
		return
	if sound_manager.has_method("play"):
		sound_manager.play(StbUtils.get_rand_element(sounds), 0, 0.1, true)
