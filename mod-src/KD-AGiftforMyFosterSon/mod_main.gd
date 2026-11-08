extends Node

# AGiftforMyFosterSon — Brotato co-op item gifting (successor of ShareWithYourBro, rebuilt for 1.2.x)
# 零依赖、纯脚本扩展、对原生按钮零侵入。

const MOD_ID = "KD-AGiftforMyFosterSon"
const EXT_DIR = "res://mods-unpacked/KD-AGiftforMyFosterSon/extensions/"
const LOG_NAME = "KD-AGiftforMyFosterSon:Main"


func _init():
	ModLoaderLog.info("loading: 这是一份给我义子的礼物 (A Gift for My Foster Son) — co-op item gifting for Brotato 1.2.x / Primal Dread.", LOG_NAME)

	_install_translations()

	ModLoaderMod.install_script_extension(EXT_DIR + "ui/menus/shop/item_popup.gd")
	# v0.1.7: 不再扩展任何商店脚本——1.2.0.1 的 base_shop.gdc 字节码损坏,
	# base_shop/coop_shop/shop 的继承链全部无法被 GML 按路径加载;
	# 赠送执行逻辑全部收敛到 item_popup 扩展(链路健康),商店服务向上探测获取。

	ModLoaderLog.info("loaded.", LOG_NAME)


func _install_translations() -> void:
	_add_translation("en", {
		"AGIFT_GIFT": "Give to Teammate",
		"AGIFT_GIFT_TO_PLAYER": "Give to {player}",
		"AGIFT_TARGET_FULL": "This teammate already has the max amount of this item.",
		"AGIFT_WEAPON_TARGET_FULL": "This teammate's weapon slots are full.",
})
	_add_translation("zh", {
		"AGIFT_GIFT": "送给队友",
		"AGIFT_GIFT_TO_PLAYER": "送给{player}",
		"AGIFT_TARGET_FULL": "这位队友已达到该道具的持有上限。",
		"AGIFT_WEAPON_TARGET_FULL": "这位队友的武器栏已满。",
})
	_add_translation("zh_TW", {
		"AGIFT_GIFT": "送給隊友",
		"AGIFT_GIFT_TO_PLAYER": "送給{player}",
		"AGIFT_TARGET_FULL": "這位隊友已達到該道具的持有上限。",
		"AGIFT_WEAPON_TARGET_FULL": "這位隊友的武器欄已滿。",
})
	_add_translation("fr", {
		"AGIFT_GIFT": "Offrir à un coéquipier",
		"AGIFT_GIFT_TO_PLAYER": "Offrir à {player}",
		"AGIFT_TARGET_FULL": "Ce coéquipier possède déjà le maximum de cet objet.",
		"AGIFT_WEAPON_TARGET_FULL": "Les emplacements d'armes de ce coéquipier sont tous occupés.",
})
	_add_translation("de", {
		"AGIFT_GIFT": "An Teammate verschenken",
		"AGIFT_GIFT_TO_PLAYER": "An {player} verschenken",
		"AGIFT_TARGET_FULL": "Dieser Mitspieler besitzt bereits die maximale Anzahl dieses Items.",
		"AGIFT_WEAPON_TARGET_FULL": "Die Waffenslots dieses Mitspielers sind voll.",
})
	_add_translation("es", {
		"AGIFT_GIFT": "Regalar a un compañero",
		"AGIFT_GIFT_TO_PLAYER": "Regalar a {player}",
		"AGIFT_TARGET_FULL": "Este compañero ya tiene la cantidad máxima de este objeto.",
		"AGIFT_WEAPON_TARGET_FULL": "Este compañero tiene las ranuras de armas llenas.",
})
	_add_translation("it", {
		"AGIFT_GIFT": "Regala a un compagno",
		"AGIFT_GIFT_TO_PLAYER": "Regala a {player}",
		"AGIFT_TARGET_FULL": "Questo compagno ha già la quantità massima di questo oggetto.",
		"AGIFT_WEAPON_TARGET_FULL": "Questo compagno ha tutti gli slot arma occupati.",
})
	_add_translation("ja", {
		"AGIFT_GIFT": "隊友に贈る",
		"AGIFT_GIFT_TO_PLAYER": "{player}に贈る",
		"AGIFT_TARGET_FULL": "この隊友はすでにこのアイテムの所持上限に達しています。",
		"AGIFT_WEAPON_TARGET_FULL": "この隊友の武器スロットがいっぱいです。",
})
	_add_translation("ko", {
		"AGIFT_GIFT": "팀원에게 주기",
		"AGIFT_GIFT_TO_PLAYER": "{player}에게 주기",
		"AGIFT_TARGET_FULL": "이 팀원은 이미 이 아이템의 보유 한도에 도달했습니다.",
		"AGIFT_WEAPON_TARGET_FULL": "이 팀원의 무기 슬롯이 가득 찼습니다.",
})
	_add_translation("pl", {
		"AGIFT_GIFT": "Podaruj koledze",
		"AGIFT_GIFT_TO_PLAYER": "Podaruj: {player}",
		"AGIFT_TARGET_FULL": "Ten kolega ma już maksymalną liczbę tego przedmiotu.",
		"AGIFT_WEAPON_TARGET_FULL": "Ten kolega ma pełne sloty na broń.",
})
	_add_translation("pt", {
		"AGIFT_GIFT": "Presentear um aliado",
		"AGIFT_GIFT_TO_PLAYER": "Presentear {player}",
		"AGIFT_TARGET_FULL": "Este aliado já tem a quantidade máxima deste item.",
		"AGIFT_WEAPON_TARGET_FULL": "Este aliado tem os espaços de armas cheios.",
})


func _add_translation(locale: String, messages: Dictionary) -> void:
	var t = Translation.new()
	t.locale = locale
	for key in messages:
		t.add_message(key, messages[key])
	TranslationServer.add_translation(t)
