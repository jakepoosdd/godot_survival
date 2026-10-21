extends Node
## 程序化物品图标：用 Image 像素绘制，不依赖任何外部图片资源。
## 注册为 Autoload: ItemIcons，供 ItemDatabase 加载物品时填充 ItemResource.icon，
## HUD 背包/装备栏直接读取 it.icon 显示。

const S := 64

static var _cache: Dictionary = {}

static func icon_for(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw(id, img)
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex

# ===== 基础像素绘制基元 =====
static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < S and y >= 0 and y < S:
		img.set_pixel(x, y, col)

static func _rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, col)

static func _circle(img: Image, cx: int, cy: int, r: float, col: Color) -> void:
	var r2 := r * r
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			var dx := float(x - cx); var dy := float(y - cy)
			if dx * dx + dy * dy <= r2:
				_px(img, x, y, col)

static func _ellipse(img: Image, cx: int, cy: int, rx: float, ry: float, col: Color) -> void:
	for y in range(int(cy - ry), int(cy + ry) + 1):
		for x in range(int(cx - rx), int(cx + rx) + 1):
			var dx := float(x - cx) / rx; var dy := float(y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, col)

static func _edge(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	return (px - ax) * (by - ay) - (bx - ax) * (py - ay)

static func _tri(img: Image, ax: float, ay: float, bx: float, by: float, cx: float, cy: float, col: Color) -> void:
	var minx := int(floor(min(ax, bx, cx))); var maxx := int(ceil(max(ax, bx, cx)))
	var miny := int(floor(min(ay, by, cy))); var maxy := int(ceil(max(ay, by, cy)))
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var w0 := _edge(x, y, ax, ay, bx, by)
			var w1 := _edge(x, y, bx, by, cx, cy)
			var w2 := _edge(x, y, cx, cy, ax, ay)
			if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
				_px(img, x, y, col)

static func _line(img: Image, ax: float, ay: float, bx: float, by: float, col: Color, w: int = 2) -> void:
	var steps := int(max(abs(bx - ax), abs(by - ay))) * 2 + 1
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := ax + (bx - ax) * t
		var y := ay + (by - ay) * t
		_circle(img, int(x), int(y), float(w) / 2.0, col)

# ===== 各类物品 =====
static func _draw(id: String, img: Image) -> void:
	# 鱼物品（fish_<品种>）默认画一条鱼（兜底；具体鱼种用 icon_for_fish 按 tint 上色）
	if id.begins_with("fish_") and id != "cooked_fish" and id != "fish_small" \
			and id != "fish_big" and id != "fish_rare":
		_fish(img, Color(0.40, 0.58, 0.72))
		return
	match id:
		"rawmeat", "cookedmeat":
			_meat(img, id == "cookedmeat")
		"log":
			_log(img)
		"stick":
			_stick(img)
		"stone":
			_stone(img)
		"flintstone":
			_flint(img)
		"fish_small":
			_fish(img, Color(0.30, 0.55, 0.75))
		"fish_big":
			_fish(img, Color(0.30, 0.65, 0.45))
		"fish_rare":
			_fish(img, Color(0.85, 0.70, 0.20))
		"cooked_fish":
			_fish(img, Color(0.80, 0.55, 0.25))
		"berry":
			_berry(img)
		"root":
			_root(img)
		"cloth":
			_cloth(img)
		"rope":
			_rope(img)
		"coal":
			_coal(img)
		"axe":
			_tool(img, "axe")
		"pickaxe":
			_tool(img, "pick")
		"shovel":
			_tool(img, "shovel")
		"sickle":
			_tool(img, "sickle")
		"spear":
			_tool(img, "spear")
		"fishing_rod":
			_rod(img)
		"bait":
			_bait(img)
		"campfire":
			_campfire(img)
		"tent":
			_tent(img)
		"house":
			_house(img)
		"backpack_upgrade":
			_backpack(img)
		"camp_storage":
			_chest(img)
		_:
			_generic(img)

static func _meat(img: Image, cooked: bool) -> void:
	var base := Color(0.72, 0.22, 0.22) if not cooked else Color(0.55, 0.33, 0.18)
	var dark := Color(0.50, 0.12, 0.12) if not cooked else Color(0.38, 0.22, 0.12)
	_ellipse(img, 30, 34, 18, 12, base)
	_ellipse(img, 26, 30, 9, 6, dark)
	_ellipse(img, 36, 38, 7, 4, dark)
	# 骨头
	_rect(img, 44, 30, 12, 8, Color(0.95, 0.92, 0.85))
	_circle(img, 44, 31, 4, Color(0.95, 0.92, 0.85))
	_circle(img, 44, 37, 4, Color(0.95, 0.92, 0.85))
	_circle(img, 56, 31, 4, Color(0.95, 0.92, 0.85))
	_circle(img, 56, 37, 4, Color(0.95, 0.92, 0.85))

static func _log(img: Image) -> void:
	var wood := Color(0.45, 0.30, 0.16)
	_rect(img, 12, 26, 40, 14, wood)
	_circle(img, 12, 33, 7, wood)
	_circle(img, 52, 33, 7, wood)
	# 端面年轮
	_ellipse(img, 52, 33, 6, 7, Color(0.62, 0.45, 0.26))
	_ellipse(img, 52, 33, 3, 4, Color(0.50, 0.34, 0.18))
	_line(img, 22, 28, 22, 38, Color(0.35, 0.22, 0.12), 1)

static func _stick(img: Image) -> void:
	_rect(img, 30, 12, 5, 42, Color(0.50, 0.36, 0.20))
	_circle(img, 32, 22, 3, Color(0.38, 0.26, 0.14))

static func _stone(img: Image) -> void:
	var g := Color(0.55, 0.57, 0.60)
	_ellipse(img, 32, 36, 16, 13, g)
	_ellipse(img, 26, 30, 6, 5, Color(0.70, 0.72, 0.75))
	_ellipse(img, 40, 42, 5, 4, Color(0.42, 0.44, 0.47))

static func _flint(img: Image) -> void:
	_stone(img)
	_tri(img, 46, 24, 58, 20, 52, 32, Color(0.90, 0.90, 0.84))
	_tri(img, 48, 26, 56, 23, 52, 31, Color(1.0, 1.0, 0.95))

# 鱼物品专用：按鱼种 tint 上色的图标（每个 fish_<id> 一张，缓存复用）
static func icon_for_fish(id: String, tint: Color, max_len: float = 60.0) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := tint if tint.a > 0.001 else Color(0.40, 0.58, 0.72)
	_fish(img, col)
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex

static func _fish(img: Image, col: Color) -> void:
	_ellipse(img, 28, 32, 16, 10, col)
	_tri(img, 42, 32, 56, 22, 56, 42, col)
	_tri(img, 28, 22, 36, 14, 40, 22, col)          # 背鳍
	_px(img, 18, 28, Color(0.05, 0.05, 0.05))       # 眼睛
	_circle(img, 18, 28, 2, Color(1, 1, 1))
	_px(img, 18, 28, Color(0, 0, 0))

static func _berry(img: Image) -> void:
	_circle(img, 26, 38, 7, Color(0.70, 0.15, 0.30))
	_circle(img, 38, 40, 6, Color(0.78, 0.20, 0.34))
	_circle(img, 32, 30, 6, Color(0.62, 0.12, 0.26))
	_tri(img, 30, 20, 38, 18, 34, 12, Color(0.30, 0.55, 0.25))

static func _root(img: Image) -> void:
	var c := Color(0.55, 0.40, 0.22)
	_rect(img, 30, 18, 5, 36, c)
	_line(img, 32, 30, 18, 44, c, 5)
	_line(img, 33, 34, 48, 50, c, 5)
	_line(img, 32, 24, 20, 18, c, 4)

static func _cloth(img: Image) -> void:
	_rect(img, 14, 16, 36, 34, Color(0.85, 0.82, 0.72))
	_line(img, 14, 33, 50, 33, Color(0.70, 0.67, 0.58), 2)
	_line(img, 32, 16, 32, 50, Color(0.70, 0.67, 0.58), 1)

static func _rope(img: Image) -> void:
	var c := Color(0.60, 0.45, 0.25)
	_circle(img, 32, 32, 18, c)
	_circle(img, 32, 32, 12, Color(0.0, 0.0, 0.0, 0.0))
	_circle(img, 32, 32, 11, c)
	_circle(img, 32, 32, 6, Color(0.0, 0.0, 0.0, 0.0))
	_circle(img, 32, 32, 5, c)

static func _coal(img: Image) -> void:
	_ellipse(img, 30, 34, 15, 12, Color(0.12, 0.12, 0.14))
	_ellipse(img, 40, 36, 8, 7, Color(0.10, 0.10, 0.12))
	_ellipse(img, 26, 30, 5, 4, Color(0.22, 0.22, 0.26))

static func _tool(img: Image, kind: String) -> void:
	var handle := Color(0.45, 0.30, 0.16)
	_line(img, 20, 54, 44, 14, handle, 6)
	match kind:
		"axe":
			_tri(img, 42, 8, 56, 14, 44, 22, Color(0.65, 0.68, 0.72))
		"pick":
			_line(img, 36, 8, 56, 20, Color(0.65, 0.68, 0.72), 5)
		"shovel":
			_tri(img, 40, 10, 50, 10, 45, 22, Color(0.65, 0.68, 0.72))
		"sickle":
			_circle(img, 46, 12, 7, Color(0.65, 0.68, 0.72))
			_circle(img, 52, 18, 5, Color(0.65, 0.68, 0.72))
		"spear":
			_tri(img, 44, 6, 50, 14, 42, 14, Color(0.65, 0.68, 0.72))

static func _rod(img: Image) -> void:
	var wood := Color(0.55, 0.38, 0.18)
	_line(img, 12, 54, 52, 14, wood, 3)
	_line(img, 52, 14, 52, 40, Color(0.85, 0.85, 0.85), 1)   # 鱼线
	_circle(img, 52, 42, 2, Color(0.30, 0.55, 0.75))          # 浮标

static func _bait(img: Image) -> void:
	var c := Color(0.85, 0.55, 0.65)
	for i in range(40):
		var t := float(i) / 39.0
		var x := 12 + t * 40
		var y := 32 + sin(t * 9.0) * 10
		_circle(img, int(x), int(y), 3.0, c)

static func _campfire(img: Image) -> void:
	_line(img, 18, 46, 46, 34, Color(0.45, 0.30, 0.16), 4)
	_line(img, 18, 34, 46, 46, Color(0.45, 0.30, 0.16), 4)
	_tri(img, 32, 10, 44, 36, 20, 36, Color(0.95, 0.55, 0.15))
	_tri(img, 32, 20, 38, 36, 26, 36, Color(0.98, 0.85, 0.35))

static func _tent(img: Image) -> void:
	_tri(img, 32, 12, 54, 50, 10, 50, Color(0.80, 0.70, 0.45))
	_tri(img, 32, 26, 40, 50, 24, 50, Color(0.45, 0.38, 0.25))

static func _house(img: Image) -> void:
	var wall := Color(0.82, 0.72, 0.48)
	var roof := Color(0.50, 0.34, 0.18)
	_rect(img, 12, 28, 40, 22, wall)
	_tri(img, 32, 10, 56, 28, 8, 28, roof)
	_rect(img, 27, 40, 10, 10, Color(0.35, 0.22, 0.12))

static func _backpack(img: Image) -> void:
	_rect(img, 16, 18, 32, 34, Color(0.55, 0.40, 0.22))
	_tri(img, 16, 18, 48, 18, 32, 8, Color(0.45, 0.32, 0.18))
	_rect(img, 28, 34, 8, 10, Color(0.35, 0.24, 0.12))

static func _chest(img: Image) -> void:
	var wood := Color(0.52, 0.34, 0.17)
	var wood_dark := Color(0.38, 0.24, 0.12)
	var metal := Color(0.72, 0.68, 0.52)
	# 箱身
	_rect(img, 12, 28, 40, 24, wood)
	# 箱盖（拱形）
	_rect(img, 12, 16, 40, 12, wood)
	_circle(img, 32, 16, 20, wood)
	_rect(img, 12, 26, 40, 3, wood_dark)
	# 金属带 + 锁扣
	_rect(img, 28, 14, 8, 38, metal)
	_rect(img, 30, 32, 4, 6, Color(0.85, 0.80, 0.30))
	# 木纹
	_line(img, 12, 40, 52, 40, wood_dark, 1)

static func _generic(img: Image) -> void:
	_rect(img, 16, 16, 32, 32, Color(0.55, 0.40, 0.22))
	_line(img, 16, 16, 48, 48, Color(0.35, 0.24, 0.12), 2)
	_line(img, 48, 16, 16, 48, Color(0.35, 0.24, 0.12), 2)
