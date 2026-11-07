extends Control
var player_index = 0
var buttons_enabled = true
var _item_data = null
var _focused = false
var _combine_button: Button = null
var _discard_button: Button = null
var _cancel_button: Button = null
func should_show_buttons(item_data, focused):
    return focused
func _update_button_visibilities():
    pass
func focus():
    pass
func hide(_player_index = -1):
    pass
