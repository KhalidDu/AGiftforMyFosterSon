extends Node
const is_coop_run = true
const players_data = []
static func get_player_count():
    return 2
static func get_remaining_max_nb_item(item_data, player_index):
    return 1
static func get_player_items(player_index):
    return []
static func remove_item(item_data, player_index):
    pass
static func add_item(item_data, player_index):
    pass
static func get_player_effect(key_hash, player_index):
    return []
static func add_item_displayed(item_data, player_index):
    pass
static func can_combine(object_data, player_index):
    return false
static func stb_has(m):
    return true
static func stb_get(p):
    return null
