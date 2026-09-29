class_name OreLook
extends RefCounted

## What each ore looks like: a block of the ore's own host rock built out of
## cubes, Minecraft-style, with the ore sticking out of its faces as cubes that
## glow, each in its own colour. Every ore has its own pattern: banded iron,
## copper in green patina, a gold-in-quartz vein, silver, cobalt spikes in pink
## bloom, sunstone, tin, zinc, magnetite, nickel, rainbow bismuth, tungsten
## blades, platinum in olivine, and a starmetal meteorite with glowing cracks.
##
## Built here, in the game, for the exact box it has to fill: any size and any
## aspect ratio, with the cubes staying (nearly) cubes - a long flat slab just
## has more cubes along its length. The design was worked out in Blender
## (assets/models/source/ores.blend, texts ore_voxlib / ore_voxbuild).
##
## Used for the chunks in the ground (OreRock) and the pieces mined out of
## them (LooseItem). Meshes are cached by ore, size and seed.

## Fewest and most cubes along a side.
const MIN_CELLS := 4
const MAX_CELLS := 12

const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## The rock each ore sits in (sRGB).
const HOST := {
	&"ore_iron": Color(0.44, 0.45, 0.5), &"ore_copper": Color(0.5, 0.4, 0.32),
	&"ore_gold": Color(0.47, 0.45, 0.42), &"ore_silver": Color(0.6, 0.62, 0.68),
	&"ore_cobalt": Color(0.27, 0.29, 0.34), &"ore_sunstone": Color(0.78, 0.66, 0.46),
	&"ore_tin": Color(0.57, 0.53, 0.48), &"ore_zinc": Color(0.46, 0.49, 0.45),
	&"ore_magnetite": Color(0.15, 0.15, 0.17), &"ore_nickel": Color(0.42, 0.44, 0.36),
	&"ore_bismuth": Color(0.62, 0.6, 0.6), &"ore_tungsten": Color(0.54, 0.47, 0.4),
	&"ore_platinum": Color(0.34, 0.36, 0.34), &"ore_starmetal": Color(0.08, 0.08, 0.1),
}
const RAINBOW := [Color(0.95, 0.4, 0.78), Color(0.98, 0.78, 0.3), Color(0.38, 0.76, 0.96),
	Color(0.5, 0.9, 0.58), Color(0.76, 0.5, 0.98)]

static var _cache: Dictionary = {}
static var _materials: Dictionary = {}
static var _glow: Shader

## Whether this ore has a look of its own.
static func has_look(item_id: StringName) -> bool:
	return HOST.has(item_id)

## The ore's rock filling a box of `size` whose centre is `centre`, turned
## `yaw` about the vertical: the body, and the glowing ore. `form` picks which
## rock (the same number gives the same rock). Empty if the ore has no look.
static func rock(item_id: StringName, size: Vector3, centre: Vector3, yaw: float, form: int = 0) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if not has_look(item_id):
		return out
	var meshes := _meshes(item_id, size, form)
	var xf := Transform3D(Basis(Vector3.UP, yaw), centre)
	for k in 2:
		var mesh: ArrayMesh = meshes[k]
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "OreLook" if k == 0 else "OreGlint"
		mi.mesh = mesh
		mi.transform = xf
		mi.material_override = _material(k == 1)
		out.append(mi)
	return out

## How many cubes along each side of a box of `size`.
static func cells_for(size: Vector3) -> Vector3i:
	var small := minf(size.x, minf(size.y, size.z))
	var big := maxf(size.x, maxf(size.y, size.z))
	var v := maxf(small / float(MIN_CELLS), big / float(MAX_CELLS))
	return Vector3i(maxi(2, roundi(size.x / v)), maxi(2, roundi(size.y / v)), maxi(2, roundi(size.z / v)))

static func _meshes(item_id: StringName, size: Vector3, form: int) -> Array:
	var key := "%s|%s|%d" % [item_id, size.snapped(Vector3.ONE * 0.005), form]
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > 400:
		_cache.clear()
	var b := _Builder.new(item_id, size, form)
	b.pattern()
	var made := b.build()
	_cache[key] = made
	return made

static func _material(glow: bool) -> Material:
	if _materials.has(glow):
		return _materials[glow]
	var m: Material
	if glow:
		# The ore that sticks out of the rock glows, each cube in its own
		# colour (the colours are in the vertices, in linear light).
		var sm := ShaderMaterial.new()
		if _glow == null:
			_glow = Shader.new()
			_glow.code = """shader_type spatial;
uniform float glow = 0.9;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.35;
	METALLIC = 0.2;
	EMISSION = COLOR.rgb * glow;
}
"""
		sm.shader = _glow
		m = sm
	else:
		var st := StandardMaterial3D.new()
		st.vertex_color_use_as_albedo = true
		st.roughness = 0.85
		m = st
	_materials[glow] = m
	return m


## Lays out one rock: which cells are ore, then the cubes.
class _Builder:
	var id: StringName
	var size: Vector3
	var n: Vector3i
	var v: Vector3              # one cube's size
	var rng := RandomNumberGenerator.new()
	var noise := FastNoiseLite.new()
	var host: Color
	## cell -> [colour, glow, push, split]
	var ore: Dictionary = {}
	var _surface: Array[Vector3i] = []

	func _init(item_id: StringName, box: Vector3, form: int) -> void:
		id = item_id
		size = box
		n = OreLook.cells_for(box)
		v = Vector3(box.x / n.x, box.y / n.y, box.z / n.z)
		rng.seed = hash([item_id, n, form])
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
		noise.frequency = 1.0
		noise.seed = rng.randi()
		host = OreLook.HOST[item_id]
		for i in n.x:
			for j in n.y:
				for k in n.z:
					if i == 0 or j == 0 or k == 0 or i == n.x - 1 or j == n.y - 1 or k == n.z - 1:
						_surface.append(Vector3i(i, j, k))

	## Where a cell is, in "a 6-cube rock" units, so patterns keep their
	## scale however many cubes the block has.
	func at(c: Vector3i) -> Vector3:
		return (Vector3(c) + Vector3(0.5, 0.5, 0.5) - Vector3(n) * 0.5) / 6.0

	func nz(p: Vector3, f: float, o: Vector3) -> float:
		# Doubled to match the spread of Blender's noise the patterns were
		# tuned with.
		return noise.get_noise_3dv(p * f + o) * 2.0

	## Makes the surface cells `pick` chooses into ore. A `push` over 0.06
	## stands out of the rock and glows; less is a flat patch in the rock.
	func mark(pick: Callable, rgb: Color, glow: bool = false, push: float = 0.18, split: bool = true, chance: float = 1.0) -> void:
		for c in _surface:
			if ore.has(c):
				continue
			if pick.call(c, at(c)) and rng.randf() < chance:
				if push > 0.06:
					ore[c] = [rgb, true, rng.randf_range(0.18, 0.3), split]
				else:
					ore[c] = [rgb, glow, 0.0, split]

	func pattern() -> void:
		match id:
			&"ore_iron":
				mark(func(c, p): return c.y == 1 or (c.y == 2 and (c.x + c.z) % 3 == 0), Color(0.66, 0.22, 0.13), false, 0.12, false)
				mark(func(c, p): return true, Color(0.62, 0.2, 0.12), false, 0.25, true, 0.14)
			&"ore_copper":
				mark(func(c, p): return nz(p, 3, Vector3(1, 3, 2)) > 0.2, Color(0.2, 0.62, 0.36), false, 0.05, false)
				mark(func(c, p): return nz(p, 4, Vector3(5, 2, 1)) > 0.35, Color(0.28, 0.72, 0.68), false, 0.05, false)
				mark(func(c, p): return true, Color(0.9, 0.48, 0.22), false, 0.22, true, 0.16)
			&"ore_gold":
				var vd := Vector3(0.8, 0.5, 0.3).normalized()
				mark(func(c, p): return absf(p.dot(vd)) < 0.06 and rng.randf() < 0.55, Color(1.0, 0.8, 0.22), true, 0.25)
				mark(func(c, p): return absf(p.dot(vd)) < 0.1, Color(0.94, 0.93, 0.88), false, 0.1, false)
			&"ore_silver":
				mark(func(c, p): return nz(p, 3, Vector3(2, 1, 7)) > 0.3, Color(0.32, 0.33, 0.37), false, 0.0, false)
				mark(func(c, p): return true, Color(0.93, 0.94, 0.98), false, 0.2, true, 0.18)
			&"ore_cobalt":
				mark(func(c, p): return p.y > 0.1 and rng.randf() < 0.3, Color(0.22, 0.38, 0.96), true, 0.5, false)
				mark(func(c, p): return nz(p, 3.5, Vector3(3, 3, 3)) > 0.15, Color(0.85, 0.38, 0.6), false, 0.06, false)
			&"ore_sunstone":
				mark(func(c, p): return nz(p, 4, Vector3(1, 2, 8)) > 0.3, Color(1.0, 0.56, 0.14), true, 0.22)
			&"ore_tin":
				mark(func(c, p): return true, Color(0.22, 0.16, 0.12), false, 0.2, true, 0.2)
			&"ore_zinc":
				mark(func(c, p): return nz(p, 3.5, Vector3(6, 4, 1)) > 0.25, Color(0.76, 0.47, 0.15), false, 0.2)
			&"ore_magnetite":
				mark(func(c, p): return true, Color(0.32, 0.36, 0.46), false, 0.2, true, 0.22)
			&"ore_nickel":
				mark(func(c, p): return true, Color(0.82, 0.68, 0.34), false, 0.2, true, 0.12)
				mark(func(c, p): return nz(p, 3, Vector3(2, 5, 9)) > 0.15, Color(0.46, 0.76, 0.36), false, 0.05, false)
			&"ore_bismuth":
				for i in RAINBOW.size():
					mark(func(c, p): return nz(p, 3, Vector3(7, 2, 7)) > 0.2 and (c.x + c.y + c.z) % 5 == i, RAINBOW[i], true, 0.1 + 0.08 * i, false)
			&"ore_tungsten":
				mark(func(c, p): return (c.x + c.y) % 3 == 0 and rng.randf() < 0.5, Color(0.2, 0.19, 0.18), false, 0.3, false)
				mark(func(c, p): return nz(p, 3, Vector3(3, 8, 1)) > 0.3, Color(0.9, 0.9, 0.86), false, 0.05, false)
			&"ore_platinum":
				mark(func(c, p): return true, Color(0.92, 0.94, 0.98), true, 0.2, true, 0.12)
				mark(func(c, p): return nz(p, 4, Vector3(8, 6, 2)) > 0.15, Color(0.3, 0.46, 0.24), false, 0.05, false)
			&"ore_starmetal":
				# Glowing cracks, flush with the black rock.
				mark(func(c, p): return absf(nz(p, 2.5, Vector3(1, 9, 5))) < 0.08, Color(0.4, 0.66, 1.0), true, 0.0, false)
				mark(func(c, p): return true, Color(0.16, 0.15, 0.2), false, 0.2, true, 0.15)

	func _filled(c: Vector3i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < n.x and c.y < n.y and c.z < n.z

	func _shade(rgb: Color, k: float) -> Color:
		var j := 1.0 + rng.randf_range(-k, k)
		return Color(clampf(rgb.r * j, 0, 1), clampf(rgb.g * j, 0, 1), clampf(rgb.b * j, 0, 1)).srgb_to_linear()

	## [body, glow] meshes, centred on the box.
	func build() -> Array:
		var body := _Mesh.new()
		var glow := _Mesh.new()
		var half := v * 0.5
		var origin := -size * 0.5
		for c in _surface:
			var open: Array[Vector3i] = []
			for d in OreLook.DIRS:
				if not _filled(c + d):
					open.append(d)
			var p := origin + Vector3(c) * v + half
			var cell_ore: Variant = ore.get(c)
			if cell_ore == null:
				body.cube(p - half, p + half, _shade(host, 0.05), open)
				continue
			# Ore stands straight out of one face, the top by choice.
			var side := Vector3i.ZERO
			if open.has(Vector3i.UP):
				side = Vector3i.UP
			else:
				for d in open:
					if d != Vector3i.DOWN:
						side = d
						break
				if side == Vector3i.ZERO:
					side = open[0]
			var out := Vector3(side) * v
			var rgb: Color = cell_ore[0]
			var target: _Mesh = glow if cell_ore[1] else body
			var push: float = cell_ore[2]
			if not cell_ore[3]:
				var q := p + out * push
				target.cube(q - half, q + half, _shade(rgb, 0.08), OreLook.DIRS if push > 0.0 else open)
				continue
			# 2x2x2 smaller cubes: rock ones flush, ore ones standing out.
			var h4 := half * 0.5
			for a in [-1, 1]:
				for b in [-1, 1]:
					for e in [-1, 1]:
						var sc := p + Vector3(a, b, e) * h4
						if rng.randf() < 0.7:
							sc += out * (push + rng.randf_range(0.0, 0.12))
							target.cube(sc - h4, sc + h4, _shade(rgb, 0.1), OreLook.DIRS)
						else:
							body.cube(sc - h4, sc + h4, _shade(host, 0.05), OreLook.DIRS)
		return [body.commit(), glow.commit()]


## Cubes gathered into one mesh, flat-shaded, colour per cube.
class _Mesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## A box from `lo` to `hi`, only the faces facing `faces`.
	func cube(lo: Vector3, hi: Vector3, col: Color, faces: Array[Vector3i]) -> void:
		for d in faces:
			var nrm := Vector3(d)
			var q: Array[Vector3]
			match d:
				Vector3i(1, 0, 0): q = [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]
				Vector3i(-1, 0, 0): q = [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]
				Vector3i(0, 1, 0): q = [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]
				Vector3i(0, -1, 0): q = [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]
				Vector3i(0, 0, 1): q = [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
				_: q = [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]
			# Godot's front faces wind clockwise.
			for idx in [0, 2, 1, 0, 3, 2]:
				verts.append(q[idx])
				normals.append(nrm)
				colors.append(col)

	func commit() -> ArrayMesh:
		if verts.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
