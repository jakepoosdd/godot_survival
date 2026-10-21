extends Node
## 鱼种数据库（Autoload: FishDatabase）。持有全部鱼种，按栖息地/水深/时段筛选可咬钩鱼种，
## 并注册 fish_<id> 为可食用物品（接 Economy）。鱼不卖——用来给营地女主提升好感或直接食用。
## 机制对标 Tidewater 的 FishSpecies/FishTable。
## 要加鱼：往 _build_species() 里再 append 一条 FishSpecies 即可，其余自动接好。

var _species: Array[FishSpecies] = []

func _ready() -> void:
	_build_species()
	_register_items()

func _build_species() -> void:
	# 栖息地缩写
	var SH := FishSpecies.H_SHALLOWS
	var BA := FishSpecies.H_BAY
	var RE := FishSpecies.H_REEF
	var PI := FishSpecies.H_PIER
	var DE := FishSpecies.H_DEEP

	# 体长-体重统一用 W(kg) = a * L(cm)^3，a 按体型量级取。
	var sp: FishSpecies

	sp = FishSpecies.new(); sp.id="sardine"; sp.display_name="沙丁鱼"
	sp.habitats=[SH, BA]; sp.min_depth=0.0; sp.max_depth=3.0
	sp.min_len=12.0; sp.max_len=26.0; sp.weight_a=1.0e-5; sp.weight_b=3.0
	sp.active_from=0.2; sp.active_to=0.85; sp.rarity=0.05; sp.fight_pull=0.12; sp.fight_stamina=2.0
	sp.value=6; sp.food=5.0; sp.tint=Color(0.75,0.8,0.7); _species.append(sp)

	sp = FishSpecies.new(); sp.id="bass"; sp.display_name="鲈鱼"
	sp.habitats=[BA, SH, PI]; sp.min_depth=0.3; sp.max_depth=6.0
	sp.min_len=25.0; sp.max_len=55.0; sp.weight_a=1.2e-5; sp.weight_b=3.0
	sp.active_from=0.15; sp.active_to=0.95; sp.rarity=0.15; sp.fight_pull=0.2; sp.fight_stamina=3.0
	sp.value=14; sp.food=10.0; sp.tint=Color(0.55,0.65,0.5); _species.append(sp)

	sp = FishSpecies.new(); sp.id="snapper"; sp.display_name="红鲷"
	sp.habitats=[RE, BA]; sp.min_depth=1.0; sp.max_depth=12.0
	sp.min_len=28.0; sp.max_len=60.0; sp.weight_a=1.3e-5; sp.weight_b=3.0
	sp.active_from=0.1; sp.active_to=0.9; sp.rarity=0.2; sp.fight_pull=0.24; sp.fight_stamina=3.5
	sp.value=22; sp.food=14.0; sp.tint=Color(0.8,0.45,0.4); _species.append(sp)

	sp = FishSpecies.new(); sp.id="grouper"; sp.display_name="石斑鱼"
	sp.habitats=[RE]; sp.min_depth=2.0; sp.max_depth=20.0
	sp.min_len=35.0; sp.max_len=85.0; sp.weight_a=1.6e-5; sp.weight_b=3.0
	sp.active_from=0.0; sp.active_to=1.0; sp.rarity=0.25; sp.fight_pull=0.3; sp.fight_stamina=4.5
	sp.value=30; sp.food=20.0; sp.tint=Color(0.5,0.4,0.3); _species.append(sp)

	sp = FishSpecies.new(); sp.id="eel"; sp.display_name="海鳗"
	sp.habitats=[RE, SH]; sp.min_depth=0.5; sp.max_depth=10.0
	sp.min_len=40.0; sp.max_len=110.0; sp.weight_a=1.1e-5; sp.weight_b=3.0
	sp.active_from=0.55; sp.active_to=0.05; sp.rarity=0.35; sp.fight_pull=0.22; sp.fight_stamina=5.0
	sp.value=26; sp.food=16.0; sp.tint=Color(0.3,0.35,0.3); _species.append(sp)  # 黄昏-夜间活跃(跨午夜)

	sp = FishSpecies.new(); sp.id="mackerel"; sp.display_name="鲐鱼"
	sp.habitats=[DE, BA]; sp.min_depth=4.0; sp.max_depth=40.0
	sp.min_len=30.0; sp.max_len=65.0; sp.weight_a=1.0e-5; sp.weight_b=3.0
	sp.active_from=0.2; sp.active_to=0.8; sp.rarity=0.1; sp.fight_pull=0.26; sp.fight_stamina=3.0
	sp.value=18; sp.food=11.0; sp.tint=Color(0.4,0.5,0.6); _species.append(sp)

	sp = FishSpecies.new(); sp.id="trevally"; sp.display_name="鲹鱼"
	sp.habitats=[PI, RE, DE]; sp.min_depth=2.0; sp.max_depth=35.0
	sp.min_len=40.0; sp.max_len=95.0; sp.weight_a=1.5e-5; sp.weight_b=3.0
	sp.active_from=0.1; sp.active_to=0.95; sp.rarity=0.3; sp.fight_pull=0.38; sp.fight_stamina=5.5
	sp.value=38; sp.food=22.0; sp.tint=Color(0.45,0.5,0.45); _species.append(sp)

	sp = FishSpecies.new(); sp.id="tuna"; sp.display_name="金枪鱼"
	sp.habitats=[DE]; sp.min_depth=10.0; sp.max_depth=99.0
	sp.min_len=70.0; sp.max_len=160.0; sp.weight_a=1.8e-5; sp.weight_b=3.0
	sp.active_from=0.15; sp.active_to=0.85; sp.rarity=0.45; sp.fight_pull=0.5; sp.fight_stamina=8.0
	sp.value=80; sp.food=45.0; sp.tint=Color(0.3,0.4,0.55); _species.append(sp)

	sp = FishSpecies.new(); sp.id="marlin"; sp.display_name="旗鱼"
	sp.habitats=[DE]; sp.min_depth=15.0; sp.max_depth=99.0
	sp.min_len=120.0; sp.max_len=280.0; sp.weight_a=2.0e-5; sp.weight_b=3.0
	sp.active_from=0.2; sp.active_to=0.75; sp.rarity=0.85; sp.fight_pull=0.7; sp.fight_stamina=12.0
	sp.value=220; sp.food=80.0; sp.tint=Color(0.2,0.3,0.5); _species.append(sp)  # 传说级

	# ---- 追加 9 种加勒比海常见鱼（使总数达到 18，覆盖各水域/水深/时段） ----
	sp = FishSpecies.new(); sp.id="snook"; sp.display_name="大眼梭鲈"
	sp.habitats=[BA, SH, PI]; sp.min_depth=0.3; sp.max_depth=8.0
	sp.min_len=30.0; sp.max_len=100.0; sp.weight_a=1.3e-5; sp.weight_b=3.0
	sp.active_from=0.0; sp.active_to=1.0; sp.rarity=0.25; sp.fight_pull=0.32; sp.fight_stamina=4.0
	sp.value=26; sp.food=16.0; sp.tint=Color(0.5,0.55,0.4); _species.append(sp)

	sp = FishSpecies.new(); sp.id="tarpon"; sp.display_name="大海鲢"
	sp.habitats=[BA, DE]; sp.min_depth=1.0; sp.max_depth=30.0
	sp.min_len=80.0; sp.max_len=200.0; sp.weight_a=1.4e-5; sp.weight_b=3.0
	sp.active_from=0.2; sp.active_to=0.9; sp.rarity=0.6; sp.fight_pull=0.45; sp.fight_stamina=9.0
	sp.value=120; sp.food=40.0; sp.tint=Color(0.6,0.6,0.5); _species.append(sp)  # 标志性跳鱼

	sp = FishSpecies.new(); sp.id="bonefish"; sp.display_name="北梭鱼"
	sp.habitats=[SH, BA]; sp.min_depth=0.2; sp.max_depth=4.0
	sp.min_len=30.0; sp.max_len=90.0; sp.weight_a=1.1e-5; sp.weight_b=3.0
	sp.active_from=0.3; sp.active_to=0.9; sp.rarity=0.3; sp.fight_pull=0.28; sp.fight_stamina=3.5
	sp.value=20; sp.food=12.0; sp.tint=Color(0.7,0.7,0.6); _species.append(sp)

	sp = FishSpecies.new(); sp.id="permit"; sp.display_name="许可鱼"
	sp.habitats=[SH, BA, RE]; sp.min_depth=0.5; sp.max_depth=12.0
	sp.min_len=30.0; sp.max_len=100.0; sp.weight_a=1.3e-5; sp.weight_b=3.0
	sp.active_from=0.2; sp.active_to=0.85; sp.rarity=0.5; sp.fight_pull=0.4; sp.fight_stamina=6.0
	sp.value=50; sp.food=22.0; sp.tint=Color(0.55,0.6,0.5); _species.append(sp)

	sp = FishSpecies.new(); sp.id="barracuda"; sp.display_name="梭鱼"
	sp.habitats=[RE, DE, BA]; sp.min_depth=1.0; sp.max_depth=30.0
	sp.min_len=50.0; sp.max_len=160.0; sp.weight_a=1.5e-5; sp.weight_b=3.0
	sp.active_from=0.1; sp.active_to=0.95; sp.rarity=0.35; sp.fight_pull=0.5; sp.fight_stamina=6.0
	sp.value=44; sp.food=24.0; sp.tint=Color(0.4,0.45,0.5); _species.append(sp)

	sp = FishSpecies.new(); sp.id="yellowtail"; sp.display_name="黄尾鰤"
	sp.habitats=[RE, DE]; sp.min_depth=5.0; sp.max_depth=40.0
	sp.min_len=40.0; sp.max_len=120.0; sp.weight_a=1.6e-5; sp.weight_b=3.0
	sp.active_from=0.15; sp.active_to=0.85; sp.rarity=0.4; sp.fight_pull=0.42; sp.fight_stamina=6.5
	sp.value=60; sp.food=28.0; sp.tint=Color(0.6,0.6,0.3); _species.append(sp)

	sp = FishSpecies.new(); sp.id="hogfish"; sp.display_name="猪鱼"
	sp.habitats=[RE]; sp.min_depth=2.0; sp.max_depth=25.0
	sp.min_len=30.0; sp.max_len=90.0; sp.weight_a=1.2e-5; sp.weight_b=3.0
	sp.active_from=0.2; sp.active_to=0.9; sp.rarity=0.3; sp.fight_pull=0.26; sp.fight_stamina=3.5
	sp.value=34; sp.food=18.0; sp.tint=Color(0.8,0.6,0.5); _species.append(sp)

	sp = FishSpecies.new(); sp.id="parrotfish"; sp.display_name="鹦鹉鱼"
	sp.habitats=[RE]; sp.min_depth=1.0; sp.max_depth=20.0
	sp.min_len=25.0; sp.max_len=80.0; sp.weight_a=1.1e-5; sp.weight_b=3.0
	sp.active_from=0.1; sp.active_to=0.95; sp.rarity=0.28; sp.fight_pull=0.22; sp.fight_stamina=3.0
	sp.value=28; sp.food=16.0; sp.tint=Color(0.3,0.8,0.7); _species.append(sp)

	sp = FishSpecies.new(); sp.id="kingfish"; sp.display_name="鲭王"
	sp.habitats=[DE, BA]; sp.min_depth=6.0; sp.max_depth=50.0
	sp.min_len=60.0; sp.max_len=170.0; sp.weight_a=1.7e-5; sp.weight_b=3.0
	sp.active_from=0.15; sp.active_to=0.8; sp.rarity=0.45; sp.fight_pull=0.48; sp.fight_stamina=7.0
	sp.value=70; sp.food=34.0; sp.tint=Color(0.3,0.35,0.4); _species.append(sp)

	# 映射外形原型：本作 18 鱼种 → Tidewater 解剖表（见 tidewater_fish_data.gd）。
	# 让程序化鱼模型按原型生成真实轮廓（沙丁鱼=细长银带、金枪鱼=鱼雷月尾、梭鱼=尖长等地道外形）。
	var anatomy_map := {
		"sardine": "silverside", "bass": "grunt", "snapper": "redSnapper", "grouper": "grouper",
		"eel": "needlefish", "mackerel": "jack", "trevally": "jack", "tuna": "tuna", "marlin": "tuna",
		"snook": "redSnapper", "tarpon": "tarpon", "bonefish": "silverside", "permit": "jack",
		"barracuda": "barracuda", "yellowtail": "yellowtail", "hogfish": "wrasse",
		"parrotfish": "parrot", "kingfish": "tuna",
	}
	for s: FishSpecies in _species:
		if anatomy_map.has(s.id):
			s.anatomy_id = anatomy_map[s.id]

func _register_items() -> void:
	for s: FishSpecies in _species:
		var it := ItemResource.new()
		it.id = "fish_" + s.id
		it.display_name = s.display_name
		it.category = ItemResource.Category.CONSUMABLE
		it.item_weight = 0.6
		it.sellable = false        # 鱼不卖（给营地女主提升好感 / 直接食用）
		it.hunger_change = s.food
		it.description = "%s：体长 %d-%dcm，偏好 %s。" % [
			s.display_name, int(s.min_len), int(s.max_len), ", ".join(s.habitats)]
		# 鱼图标：用鱼种 tint 上色（每个 fish_<id> 一张专属鱼图标，而非通用占位框）
		it.icon = ItemIcons.icon_for_fish(it.id, s.tint, s.max_len)
		ItemDatabase.register_item(it)

## 候选鱼种（栖息地/水深/时段都匹配）。gear 传入 FishingGear 以应用咬钩率加成。
## time01 < 0 时跳过时段判断（用于「当前时段无鱼则放宽」的兜底，保证一定有鱼可钓）。
func candidates(habitat: String, depth: float, time01: float, gear = null) -> Array[FishSpecies]:
	var out: Array[FishSpecies] = []
	for s: FishSpecies in _species:
		if not s.likes(habitat):
			continue
		if depth < s.min_depth or depth > s.max_depth:
			continue
		if time01 >= 0.0 and not s.is_active(time01):
			continue
		out.append(s)
	return out

## 按权重随机选一种（稀有度越低越常见），并掷出体长。返回 {species, length_cm} 或 null。
func roll_bite(habitat: String, depth: float, time01: float, gear = null) -> Dictionary:
	var cands := candidates(habitat, depth, time01, gear)
	if cands.is_empty():
		return {}
	var total := 0.0
	var weights: Array[float] = []
	for s: FishSpecies in cands:
		var w := 1.0 - 0.7 * s.rarity
		if gear != null and gear.has_method("bite_rate"):
			w *= gear.bite_rate()
		weights.append(w)
		total += w
	var r := randf() * total
	for i: int in cands.size():
		r -= weights[i]
		if r <= 0.0:
			var sp: FishSpecies = cands[i]
			var L := randf_range(sp.min_len, sp.max_len)
			if gear != null and gear.has_method("size_bonus"):
				L *= gear.size_bonus()
			L = clamp(L, sp.min_len, sp.max_len)
			return {"species": sp, "length_cm": L}
	return {}

func all_species() -> Array[FishSpecies]:
	return _species

func species_by_id(id: String) -> FishSpecies:
	for s: FishSpecies in _species:
		if s.id == id:
			return s
	return null
