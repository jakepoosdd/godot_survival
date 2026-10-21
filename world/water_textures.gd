extends RefCounted
class_name WaterTextures

# =============================================================================
# 海面着色所需的 CPU 端贴图烘焙器。
# 两个 noise 直接照搬 Tidewater 的 CPU 生成算法：
#   · seaNoise  ← src/ocean/SeaDetail.js  makeNoiseTexture()（4 通道可平铺 fbm）
#   · lace      ← src/ocean/SurfFoam.js  makeLaceTexture()（可平铺 Worley 花边）
# 另外把 world.gd 的合成地形（高度图 + 细节噪声 + 营地压平）烘成单通道 float 贴图，
# 让着色器能在 GPU 上取到「与地形网格完全一致」的海床高度 —— 这是做
# 折射 ray-march / 水深 / 拍岸线的前提（Tidewater 里是 terrainHeightAt()）。
# =============================================================================

# ------------------------------------------------------------------ 可平铺 fbm
static func _grad_table(n: int, seed_val: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var g := PackedFloat32Array()
	g.resize(n * n * 2)
	var i: int = 0
	while i < n * n:
		var a: float = rng.randf() * TAU
		g[i * 2] = cos(a)
		g[i * 2 + 1] = sin(a)
		i += 1
	return g

# 周期性（可平铺）梯度噪声的 fbm，返回 [0,1] 归一化后的 size² 个值
static func perlin_tileable(size: int, freq: int, octaves: int, seed_val: int) -> PackedFloat32Array:
	var ns := PackedInt32Array()
	var gs: Array = []
	var o: int = 0
	while o < octaves:
		var n: int = freq << o
		ns.append(n)
		gs.append(_grad_table(n, seed_val + o * 101))
		o += 1

	var raw := PackedFloat32Array()
	raw.resize(size * size)
	var mn: float = 1e9
	var mx: float = -1e9
	var y: int = 0
	while y < size:
		var x: int = 0
		while x < size:
			var v: float = 0.0
			var amp: float = 1.0
			var norm: float = 0.0
			var oo: int = 0
			while oo < octaves:
				var n: int = ns[oo]
				var g: PackedFloat32Array = gs[oo]
				var fx: float = float(x) / float(size) * float(n)
				var fy: float = float(y) / float(size) * float(n)
				var xi: int = int(floor(fx))
				var yi: int = int(floor(fy))
				var xf: float = fx - float(xi)
				var yf: float = fy - float(yi)
				# 周期性格点查 Gradient
				var ix0: int = ((xi % n) + n) % n
				var iy0: int = ((yi % n) + n) % n
				var ix1: int = ((xi + 1) % n + n) % n
				var iy1: int = ((yi + 1) % n + n) % n
				var a0: float = g[(iy0 * n + ix0) * 2] * xf + g[(iy0 * n + ix0) * 2 + 1] * yf
				var a1: float = g[(iy0 * n + ix1) * 2] * (xf - 1.0) + g[(iy0 * n + ix1) * 2 + 1] * yf
				var b0: float = g[(iy1 * n + ix0) * 2] * xf + g[(iy1 * n + ix0) * 2 + 1] * (yf - 1.0)
				var b1: float = g[(iy1 * n + ix1) * 2] * (xf - 1.0) + g[(iy1 * n + ix1) * 2 + 1] * (yf - 1.0)
				var u: float = xf * xf * xf * (xf * (xf * 6.0 - 15.0) + 10.0)
				var w: float = yf * yf * yf * (yf * (yf * 6.0 - 15.0) + 10.0)
				var top: float = a0 + (a1 - a0) * u
				var bot: float = b0 + (b1 - b0) * u
				v += (top + (bot - top) * w) * amp
				norm += amp
				amp *= 0.5
				oo += 1
			v /= maxf(norm, 0.0001)
			raw[y * size + x] = v
			mn = minf(mn, v)
			mx = maxf(mx, v)
			x += 1
		y += 1

	var out := PackedFloat32Array()
	out.resize(size * size)
	var i2: int = 0
	while i2 < size * size:
		out[i2] = (raw[i2] - mn) / maxf(mx - mn, 0.0001)
		i2 += 1
	return out

# RGBA 四通道（每一通道独立的 seed / 频率），对应 SeaDetail 的 gust / gust2 / slick / streak
static func make_sea_noise_texture(size: int = 256) -> ImageTexture:
	var chans: Array = [
		{"seed": 11, "freq": 4, "oct": 4},
		{"seed": 23, "freq": 5, "oct": 4},
		{"seed": 37, "freq": 4, "oct": 3},
		{"seed": 53, "freq": 6, "oct": 3},
	]
	var planes: Array = []
	for c in chans:
		planes.append(perlin_tileable(size, c["freq"], c["oct"], c["seed"]))

	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var i: int = 0
	while i < size * size:
		bytes[i * 4 + 0] = int(clampf(planes[0][i], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 1] = int(clampf(planes[1][i], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 2] = int(clampf(planes[2][i], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 3] = int(clampf(planes[3][i], 0.0, 1.0) * 255.0)
		i += 1
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ 花边（Worley 条纹）
# R: 到最近「泡泡梗」的距离接口（0 在梗上，1 在孔洞中心）—— 按 coverage 阈值化后
#    依次呈现：致密泡沫垫 → 带孔的泡沫 → 蕾丝 → 细细的泡丝（对应 Tidewater 的 lace 语义）
# G: 沿梗聚集的小泡泡   B: 软斑驳（密度变化）   A: 每格随机值
static func make_lace_texture(size: int = 512, cells: int = 16) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9021
	var jitter := PackedFloat32Array()
	jitter.resize(cells * cells * 2)
	var cellrand := PackedFloat32Array()
	cellrand.resize(cells * cells)
	var ci: int = 0
	while ci < cells * cells:
		jitter[ci * 2] = rng.randf()
		jitter[ci * 2 + 1] = rng.randf()
		cellrand[ci] = rng.randf()
		ci += 1

	var warp := perlin_tileable(size, 4, 3, 77)
	var bub := perlin_tileable(size, 16, 2, 313)
	var mottle := perlin_tileable(size, 3, 3, 555)

	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var y: int = 0
	while y < size:
		var x: int = 0
		while x < size:
			var fx: float = float(x) / float(size) * float(cells)
			var fy: float = float(y) / float(size) * float(cells)
			var cx0: int = int(floor(fx))
			var cy0: int = int(floor(fy))
			var f1: float = 1e9
			var f2: float = 1e9
			var crand: float = 0.0
			var oy: int = -1
			while oy <= 1:
				var ox: int = -1
				while ox <= 1:
					var cx2: int = ((cx0 + ox) % cells + cells) % cells
					var cy2: int = ((cy0 + oy) % cells + cells) % cells
					var k: int = cy2 * cells + cx2
					var qx: float = float(cx0 + ox) + 0.5 + (jitter[k * 2] - 0.5) * 0.85
					var qy: float = float(cy0 + oy) + 0.5 + (jitter[k * 2 + 1] - 0.5) * 0.85
					# 环形（toroidal）距离：保证贴图可平铺
					var dx: float = fx - qx
					var dy: float = fy - qy
					if absf(dx) > float(cells) * 0.5:
						dx -= signf(dx) * float(cells)
					if absf(dy) > float(cells) * 0.5:
						dy -= signf(dy) * float(cells)
					var d: float = sqrt(dx * dx + dy * dy)
					if d < f1:
						f2 = f1
						f1 = d
						crand = cellrand[k]
					elif d < f2:
						f2 = d
					ox += 1
				oy += 1

			var idx: int = y * size + x
			# 梗：F2-F1 越小越接近 Cell 边界
			var e: float = (f2 - f1) / 0.55 + (warp[idx] - 0.5) * 0.34
			var edgev: float = clampf(e, 0.0, 1.0)
			var near_strand: float = 1.0 - clampf(edgev / 0.42, 0.0, 1.0)
			var gch: float = clampf(bub[idx] * 0.65 + near_strand * 0.45, 0.0, 1.0)
			bytes[idx * 4 + 0] = int(edgev * 255.0)
			bytes[idx * 4 + 1] = int(gch * 255.0)
			bytes[idx * 4 + 2] = int(clampf(mottle[idx] * 0.8 + 0.2, 0.0, 1.0) * 255.0)
			bytes[idx * 4 + 3] = int(crand * 255.0)
			x += 1
		y += 1
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ 合成高度图
# values: size² 个世界高度（米）。RF 单通道浮点，着色器直接读到米，无需 0..1 反解。
static func make_height_texture(values: PackedFloat32Array, size: int) -> ImageTexture:
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RF, values.to_byte_array())
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ 径向网格
# 近层 = 圆盘（中心密、边缘 3m 网格），远层 = 圆环（从盘边缘一直铺到地平线）。
# 两层在「波幅已被距离阻尼归零」的半径处拼合，两侧都是 y=0 纯平面，接缝不可见。
# 返回顶点位置(x,0,z)/法线朝上/索引的 ArrayMesh。
static func _build_radial_mesh(rings: PackedFloat32Array, segments: int, inner_ring: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n_rings: int = rings.size()
	if not inner_ring:
		# 圆盘：先放圆心
		verts.append(Vector3(0.0, 0.0, 0.0))
		norms.append(Vector3(0.0, 1.0, 0.0))
		uvs.append(Vector2(0.5, 0.5))
	for ri in range(n_rings):
		var r: float = rings[ri]
		for s in range(segments):
			var a: float = TAU * float(s) / float(segments)
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
			norms.append(Vector3(0.0, 1.0, 0.0))
			uvs.append(Vector2(float(s) / float(segments), float(ri) / float(maxf(n_rings - 1, 1.0))))
	var ring0: int = 0
	if not inner_ring:
		ring0 = 1   # 圆盘的第 0 个顶点是圆心，环从 1 开始
	for ri in range(n_rings - 1):
		var base_a: int = ring0 + ri * segments
		var base_b: int = base_a + segments
		for s in range(segments):
			var s2: int = (s + 1) % segments
			idx.append(base_a + s)
			idx.append(base_b + s)
			idx.append(base_a + s2)
			idx.append(base_a + s2)
			idx.append(base_b + s)
			idx.append(base_b + s2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# 圆盘（半径 radius，内部先均匀 3m，之后指数过渡到 radius）
static func make_disc_mesh(radius: float, segments: int = 720) -> ArrayMesh:
	var rings := PackedFloat32Array()
	var r: float = 0.0
	while r < radius and rings.size() < 200:
		rings.append(minf(r, radius))
		if r < 200.0:
			r += 3.1
		else:
			r *= 1.0302
	if rings[rings.size() - 1] < radius:
		rings.append(radius)
	return _build_radial_mesh(rings, segments, false)

# 圆环（r_in 有 1m 重叠进圆盘，r_out 到地平线）
static func make_ring_mesh(r_in: float, r_out: float, segments: int = 512) -> ArrayMesh:
	var rings := PackedFloat32Array()
	var r: float = r_in
	while r < r_out and rings.size() < 200:
		rings.append(r)
		r *= 1.0907
	if rings[rings.size() - 1] < r_out:
		rings.append(r_out)
	return _build_radial_mesh(rings, segments, true)
