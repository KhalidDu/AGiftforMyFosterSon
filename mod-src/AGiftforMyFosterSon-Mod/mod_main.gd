extends Node

# AGiftforMyFosterSon — Brotato co-op item gifting (successor of ShareWithYourBro, rebuilt for 1.2.x)
# 零依赖、纯脚本扩展、对原生按钮零侵入。

const MOD_ID = "AGiftforMyFosterSon-Mod"
const EXT_DIR = "res://mods-unpacked/AGiftforMyFosterSon-Mod/extensions/"
const LOG_NAME = "AGiftforMyFosterSon-Mod:Main"


func _init():
	ModLoaderLog.info("loading: 这是一份给我义子的礼物 (A Gift for My Foster Son) — co-op item gifting for Brotato 1.2.x / Primal Dread.", LOG_NAME)

	_install_translations()

	ModLoaderMod.install_script_extension(EXT_DIR + "ui/menus/shop/item_popup.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "ui/menus/shop/base_shop.gd")

	ModLoaderLog.info("loaded.", LOG_NAME)


func _install_translations() -> void:
	_add_translation("en", {
		"AGIFT_GIFT": "Give to Teammate",
		"AGIFT_GIFT_TO_PLAYER": "Give to {player}",
		"AGIFT_TARGET_FULL": "This teammate already has the max amount of this item.",
	})
	_add_translation("zh", {
		"AGIFT_GIFT": "送给队友",
		"AGIFT_GIFT_TO_PLAYER": "送给{player}",
		"AGIFT_TARGET_FULL": "这位队友已达到该道具的持有上限。",
	})
	_add_translation("zh_TW", {
		"AGIFT_GIFT": "送給隊友",
		"AGIFT_GIFT_TO_PLAYER": "送給{player}",
		"AGIFT_TARGET_FULL": "這位隊友已達到該道具的持有上限。",
	})
	_add_translation("fr", {
		"AGIFT_GIFT": "Offrir à un coéquipier",
		"AGIFT_GIFT_TO_PLAYER": "Offrir à {player}",
		"AGIFT_TARGET_FULL": "Ce coéquipier possède déjà le maximum de cet objet.",
	})
	_add_translation("de", {
		"AGIFT_GIFT": "An Teammate verschenken",
		"AGIFT_GIFT_TO_PLAYER": "An {player} verschenken",
		"AGIFT_TARGET_FULL": "Dieser Mitspieler besitzt bereits die maximale Anzahl dieses Items.",
	})
	_add_translation("es", {
		"AGIFT_GIFT": "Regalar a un compañero",
		"AGIFT_GIFT_TO_PLAYER": "Regalar a {player}",
		"AGIFT_TARGET_FULL": "Este compañero ya tiene la cantidad máxima de este objeto.",
	})
	_add_translation("it", {
		"AGIFT_GIFT": "Regala a un compagno",
		"AGIFT_GIFT_TO_PLAYER": "Regala a {player}",
		"AGIFT_TARGET_FULL": "Questo compagno ha già la quantità massima di questo oggetto.",
	})
	_add_translation("ja", {
		"AGIFT_GIFT": "隊友に贈る",
		"AGIFT_GIFT_TO_PLAYER": "{player}に贈る",
		"AGIFT_TARGET_FULL": "この隊友はすでにこのアイテムの所持上限に達しています。",
	})
	_add_translation("ko", {
		"AGIFT_GIFT": "팀원에게 주기",
		"AGIFT_GIFT_TO_PLAYER": "{player}에게 주기",
		"AGIFT_TARGET_FULL": "이 팀원은 이미 이 아이템의 보유 한도에 도달했습니다.",
	})
	_add_translation("pl", {
		"AGIFT_GIFT": "Podaruj koledze",
		"AGIFT_GIFT_TO_PLAYER": "Podaruj: {player}",
		"AGIFT_TARGET_FULL": "Ten kolega ma już maksymalną liczbę tego przedmiotu.",
	})
	_add_translation("pt", {
		"AGIFT_GIFT": "Presentear um aliado",
		"AGIFT_GIFT_TO_PLAYER": "Presentear {player}",
		"AGIFT_TARGET_FULL": "Este aliado já tem a quantidade máxima deste item.",
	})


func _add_translation(locale: String, messages: Dictionary) -> void:
	var t = Translation.new()
	t.locale = locale
	for key in messages:
		t.add_message(key, messages[key])
	TranslationServer.add_translation(t)
