class_name FishMeshGen
extends RefCounted
const _Data = preload("res://fishing/tidewater_fish_data.gd")
## 程序化鱼网格生成器（对标 Tidewater FishGeometry.js）。
## 输入 TidewaterFishData 的解剖表 + 贴色表，输出带顶点色（背/腹/鳍渐变 + 眼）的 ArrayMesh。
## 坐标约定：snout z=+0.5，尾鳍尖 z=-0.5，背 +y，体轴 y=0，总长归一化 1。
## 实现：超椭圆截面鱼身（头尾扇形封口）+ 背/臀/尾/胸/腹鳍膜 + 眼睛穹顶。
## 不用任何模型文件——纯几何生成，忠实还原各鱼种外形轮廓。

# ---- 数学辅助 ----
static func _prof(pts: Array, u: float) -> float:
	if u <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if u <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			var t := (u - float(a[0])) / (float(b[0]) - float(a[0]))
			var s := t * t * (3.0 - 2.0 * t)
			return float(a[1]) + (float(b[1]) - float(a[1])) * (0.5 * t + 0.5 * s)
	return float(pts[pts.size() - 1][1])

static func _section(S: Dictionary, u: float) -> Dictionary:
	return {"T": _prof(S["top"], u), "B": _prof(S["bot"], u),
			"W": _prof(S["wid"], u), "e": 2.0 / float(S["sec"])}

static func _outline(c: Dictionary, phi: float) -> Vector2:
	var s := sin(phi)
	var k := cos(phi)
	var W: float = c["W"]; var e: float = c["e"]; var T: float = c["T"]; var B: float = c["B"]
	var sx: float = 1.0 if s >= 0.0 else -1.0
	var x: float = W * sx * pow(abs(s), e)
	var kk: float = T if k >= 0.0 else B
	var ky: float = 1.0 if k >= 0.0 else -1.0
	var y: float = kk * ky * pow(abs(k), e)
	return Vector2(x, y)

static func _surface_x(c: Dictionary, y: float) -> float:
	var T: float = c["T"]; var B: float = c["B"]; var W: float = c["W"]; var e: float = c["e"]
	var H := T if y >= 0.0 else B
	var r: float = min(1.0, abs(y) / max(H, 1e-4))
	var n: float = 2.0 / e
	return W * pow(max(0.0, 1.0 - pow(r, n)), 1.0 / n)

static func _hex(h) -> Color:
	var hh: int = int(h)
	return Color(float((hh >> 16) & 255) / 255.0, float((hh >> 8) & 255) / 255.0, float(hh & 255) / 255.0)

# ---- 累积缓冲 ----
var _verts: Array = []
var _cols: Array = []
var _idx: Array = []

func _push(p: Vector3, c: Color) -> int:
	_verts.append(p)
	_cols.append(c)
	return _verts.size() - 1

func _tri(i: int, j: int, k: int) -> void:
	_idx.append(i); _idx.append(j); _idx.append(k)

# ---- 顶点色 ----
func _body_color(p: Vector3, cTop: Color, cFlank: Color, cBel: Color, maxT: float) -> Color:
	var tt: float = clamp(p.y / maxT, -1.0, 1.0)
	if tt >= 0.0:
		return cTop.lerp(cFlank, 1.0 - tt)
	return cFlank.lerp(cBel, -tt)

# =========================================================
# 公开入口
# =========================================================
func build_by_id(anatomy_id: String) -> ArrayMesh:
	var S: Dictionary = _Data.get_species(anatomy_id)
	var skin: Dictionary = _Data.get_skin(anatomy_id)
	return _build(S, skin)

func _build(S: Dictionary, skin: Dictionary) -> ArrayMesh:
	_verts = []; _cols = []; _idx = []
	var cTop := _hex(skin["back"]); var cFlank := _hex(skin["flank"]); var cBel := _hex(skin["belly"])
	_build_body(S, cTop, cFlank, cBel)
	_build_midline_fins(S, 1, skin)
	_build_midline_fins(S, -1, skin)
	if S.has("caudal"):
		_build_caudal(S, skin)
	if S.has("pectoral"):
		_build_paired(S, S["pectoral"], "pectoral", skin)
	if S.has("pelvic"):
		_build_paired(S, S["pelvic"], "pelvic", skin)
	if S.has("eye"):
		_build_eyes(S, skin)
	return _finalize(skin)

func _finalize(skin: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(_verts)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(_cols)
	# 法线：按面法线累加到共享顶点，得到平滑法线（鳍为独立顶点 -> 平面着色，正好适合薄片）
	var normals := PackedVector3Array()
	normals.resize(_verts.size())
	for i in range(0, _idx.size(), 3):
		var ia: int = _idx[i]; var ib: int = _idx[i + 1]; var ic: int = _idx[i + 2]
		var a3: Vector3 = _verts[ib]; var b3: Vector3 = _verts[ia]; var c3: Vector3 = _verts[ic]
		var n: Vector3 = (a3 - b3).cross(c3 - b3)
		normals[ia] += n; normals[ib] += n; normals[ic] += n
	for k in range(normals.size()):
		if normals[k].length_squared() > 0.0:
			normals[k] = normals[k].normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(_idx)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_colors_enabled = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = float(skin.get("rough", 0.4))
	mat.metallic = 0.05
	mesh.surface_set_material(0, mat)
	return mesh

# =========================================================
# 鱼身：超椭圆截面环 + 头尾封口
# =========================================================
func _build_body(S: Dictionary, cTop: Color, cFlank: Color, cBel: Color) -> void:
	var L := float(S["body"])
	var zOf := func(u: float) -> float: return 0.5 - u * L
	var n_rings := 18
	var n_phi := 20
	var us: PackedFloat32Array = []
	for i in range(n_rings + 1):
		var t := float(i) / float(n_rings)
		us.append(0.6 * pow(t, 1.55) + 0.4 * t)
	us[0] = 0.006
	# 先扫描一遍截面，取鱼身最大半高（背高/腹深的最大值）作为顶点色归一化基准，
	# 否则背色只覆盖极小部分、flank 占主体，色带整体偏移。
	var maxT := 0.001
	for u in us:
		var c: Dictionary = _section(S, u)
		maxT = max(maxT, float(c["T"]))
		maxT = max(maxT, float(c["B"]))
	var grid: Array = []   # grid[i][j] = vertex index
	for u in us:
		var c: Dictionary = _section(S, u)
		var z: float = zOf.call(u)
		var row: Array = []
		for j in range(n_phi):
			var phi := TAU * float(j) / float(n_phi)
			var p := _outline(c, phi)
			var v := Vector3(p.x, p.y, z)
			row.append(_push(v, _body_color(v, cTop, cFlank, cBel, maxT)))
		grid.append(row)
	# 环间四边形
	for i in range(n_rings):
		for j in range(n_phi):
			var jn := (j + 1) % n_phi
			var a: int = grid[i][j]; var b: int = grid[i][jn]
			var cc: int = grid[i + 1][jn]; var d: int = grid[i + 1][j]
			_tri(a, b, cc); _tri(a, cc, d)
	# 头/尾扇形封口
	var front: Array = grid[0]; var back: Array = grid[n_rings]
	var fc := _push(Vector3(0.0, 0.0, zOf.call(us[0]) + 0.02), cFlank)
	for j in range(n_phi):
		var jn := (j + 1) % n_phi
		_tri(fc, front[j], front[jn])
	var bc := _push(Vector3(0.0, 0.0, zOf.call(us[n_rings]) - 0.02), cFlank)
	for j in range(n_phi):
		var jn := (j + 1) % n_phi
		_tri(bc, back[jn], back[j])

# =========================================================
# 背鳍(sign>0) / 臀鳍(sign<0)
# =========================================================
func _build_midline_fins(S: Dictionary, sign: int, skin: Dictionary) -> void:
	var key := "dorsal" if sign > 0 else "anal"
	if not S.has(key):
		return
	var segs: Array = S[key]
	var L := float(S["body"])
	var zOf := func(u: float) -> float: return 0.5 - u * L
	var fin_col := _hex(skin["fin"])
	for seg in segs:
		var rays_n: int = seg["rays"]
		var rays: Array = []
		for k in range(rays_n):
			var t := 0.0 if rays_n <= 1 else float(k) / float(rays_n - 1)
			var u: float = lerp(float(seg["from"]), float(seg["to"]), t)
			var c: Dictionary = _section(S, u)
			var y0 := (float(c["T"]) * 0.9) if sign > 0 else (-float(c["B"]) * 0.9)
			var h := _prof(seg["h"], t) + ((float(c["T"]) if sign > 0 else float(c["B"])) * 0.1)
			var rake: float = lerp(float(seg["rake"][0]), float(seg["rake"][1]), t)
			var z: float = zOf.call(u)
			var tip := Vector3(0.0, y0 + sign * h * cos(rake), z - h * sin(rake))
			var base := Vector3(0.0, y0, z)
			rays.append({"b": [base.x, base.y, base.z], "t": [tip.x, tip.y, tip.z]})
		_membrane_push(rays, fin_col)

# 尾鳍
func _build_caudal(S: Dictionary, skin: Dictionary) -> void:
	var L := float(S["body"])
	var C: Dictionary = S["caudal"]
	var zb := 0.5 - L + 0.014
	var cEnd: Dictionary = _section(S, 1.0)
	var hp: float = min(float(cEnd["T"]), float(cEnd["B"])) * 0.9
	var R: int = C["rays"]
	var span: float = C["span"]
	var fin_col := _hex(skin["fin"])
	var rays: Array = []
	for k in range(R):
		var s := -1.0 + 2.0 * float(k) / float(R - 1)
		var a: float = abs(s)
		var y := 0.0; var len := 0.0
		var shape: String = C["shape"]
		if shape == "rounded":
			y = span * s * 0.95; len = float(C["len"]) * (1.0 - 0.3 * s * s)
		elif shape == "truncate":
			y = span * s; len = float(C["len"]) * (1.0 - 0.05 * s * s) * lerp(float(C["fork"]), 1.0, a)
		elif shape == "lunate":
			y = span * s * (0.75 + 0.25 * a); len = float(C["len"]) * (float(C["fork"]) + (1.0 - float(C["fork"])) * pow(a, 1.8))
		else: # forked
			y = span * s; len = float(C["len"]) * (float(C["fork"]) + (1.0 - float(C["fork"])) * pow(a, 1.3))
		rays.append({"b": [0.0, hp * s, zb], "t": [0.0, y, zb - 0.014 - len]})
	_membrane_push(rays, fin_col)

# 胸鳍 / 腹鳍
func _build_paired(S: Dictionary, F: Dictionary, part_name: String, skin: Dictionary) -> void:
	var L := float(S["body"])
	var zOf := func(u: float) -> float: return 0.5 - u * L
	var c: Dictionary = _section(S, float(F["u"]))
	var R: int = F["rays"]
	var fin_col := _hex(skin["fin"])
	var pelvic := (part_name == "pelvic")
	for side in [1, -1]:
		var rays: Array = []
		for k in range(R):
			var t := 0.0 if R <= 1 else float(k) / float(R - 1)
			var yb: float; var xb: float; var alpha: float; var len: float; var spread: float
			if pelvic:
				yb = -float(c["B"]) * 0.88
				xb = side * (float(c["W"]) * 0.22 + t * float(c["W"]) * 0.12)
				alpha = lerp(-0.35, -0.75, t)
				len = float(F["len"]) * (1.0 - 0.45 * t)
				spread = 0.35
			else:
				yb = float(F["y"]) + float(F["base"]) * (0.5 - t)
				xb = side * _surface_x(c, yb) * 0.94
				var shape: String = F["shape"]
				if shape == "falcate":
					alpha = lerp(0.05, -0.55, t); len = float(F["len"]) * (1.0 - 0.85 * pow(t, 0.55))
				elif shape == "pointed":
					alpha = lerp(0.1, -0.85, t); len = float(F["len"]) * (1.0 - 0.62 * pow(t, 0.9))
				else:
					alpha = lerp(0.25, -1.1, t); len = float(F["len"]) * (0.62 + 0.38 * sin(PI * (0.15 + 0.85 * t)))
				spread = float(F["spread"])
			var dir_x: float = side * sin(spread) * cos(alpha)
			var dir_y: float = sin(alpha)
			var dir_z: float = -cos(spread) * cos(alpha)
			var zb: float = zOf.call(float(F["u"]))
			rays.append({"b": [xb, yb, zb], "t": [xb + dir_x * len, yb + dir_y * len, zb + dir_z * len]})
		_membrane_push(rays, fin_col)

# 眼睛穹顶
func _build_eyes(S: Dictionary, skin: Dictionary) -> void:
	var L := float(S["body"])
	var E: Dictionary = S["eye"]
	var u: float = E["u"]; var z0 := 0.5 - u * L
	var c: Dictionary = _section(S, u)
	var r: float = E["r"]
	var xs := _surface_x(c, float(E["y"]))
	var segs := 10; var rings := 2
	var bulge := 0.34 * r
	var eye_col := Color(0.04, 0.04, 0.05)
	for side in [1, -1]:
		var ax := Vector3(side, 0.06, 0.22).normalized()
		var t1 := Vector3(0, 1, 0).lerp(ax, -ax.y).normalized()
		var t2 := ax.cross(t1)
		var base := Vector3(side * (xs - r * 0.12), float(E["y"]), z0)
		var idx: Array = []
		for i in range(rings + 1):
			var rho := float(i) / float(rings)
			var row: Array = []
			var n := 1 if i == 0 else segs
			for j in range(n):
				var a := (float(j) / float(segs)) * TAU
				var ca := cos(a) * rho; var sa := sin(a) * rho
				var h := bulge * (1.0 - rho * rho) + r * 0.12
				row.append(_push(Vector3(
					base.x + t1.x * sa * r + t2.x * ca * r + ax.x * h,
					base.y + t1.y * sa * r + t2.y * ca * r + ax.y * h,
					base.z + t1.z * sa * r + t2.z * ca * r + ax.z * h), eye_col))
			idx.append(row)
		for i in range(rings):
			for j in range(segs):
				var j1 := (j + 1) % segs
				if i == 0:
					var a0: int = idx[0][0]; var b0: int = idx[1][j]; var c0: int = idx[1][j1]
					if side > 0: _tri(a0, b0, c0)
					else: _tri(a0, c0, b0)
				else:
					var a2: int = idx[i][j]; var b2: int = idx[i][j1]
					var cc2: int = idx[i + 1][j1]; var d2: int = idx[i + 1][j]
					if side > 0: _tri(a2, d2, cc2); _tri(a2, cc2, b2)
					else: _tri(a2, b2, cc2); _tri(a2, cc2, d2)

# membrane 的薄封装：把 ray 转成顶点压入（鳍为独立顶点，平面着色）
func _membrane_push(rays: Array, col: Color) -> void:
	var cols: Array = []
	for k in range(rays.size()):
		cols.append({"b": rays[k]["b"], "t": rays[k]["t"], "dip": 0.0})
		if k < rays.size() - 1:
			var a: Dictionary = rays[k]; var b: Dictionary = rays[k + 1]
			var mb := [(a["b"][0] + b["b"][0]) * 0.5, (a["b"][1] + b["b"][1]) * 0.5, (a["b"][2] + b["b"][2]) * 0.5]
			var mt := [(a["t"][0] + b["t"][0]) * 0.5, (a["t"][1] + b["t"][1]) * 0.5, (a["t"][2] + b["t"][2]) * 0.5]
			cols.append({"b": mb, "t": mt, "dip": 0.05})
	var rows := 3
	for back in [false, true]:
		var grid: Array = []
		for c in cols:
			var col_arr: Array = []
			var top := 1.0 - float(c["dip"])
			for r in range(rows + 1):
				var t := (float(r) / float(rows)) * top
				col_arr.append(_push(Vector3(
					lerp(float(c["b"][0]), float(c["t"][0]), t),
					lerp(float(c["b"][1]), float(c["t"][1]), t),
					lerp(float(c["b"][2]), float(c["t"][2]), t)), col))
			grid.append(col_arr)
		for k in range(grid.size() - 1):
			for r in range(rows):
				var a: int = grid[k][r]; var b: int = grid[k + 1][r]
				var c2: int = grid[k + 1][r + 1]; var d: int = grid[k][r + 1]
				if back:
					_tri(a, b, c2); _tri(a, c2, d)
				else:
					_tri(a, c2, b); _tri(a, d, c2)
