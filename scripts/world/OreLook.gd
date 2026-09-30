class_name OreLook
extends RefCounted

## What each ore looks like: its whole chunk, made in Blender
## (assets/models/ores.glb, source in assets/models/source/ores.blend) - a
## perfect cube of the ore's own host rock, the ore sticking out of its faces
## as glowing cubes, Minecraft-style but with
## depth: rock cubes sit a little in or out, ore cubes stand proud and are split
## into smaller cubes of ore and rock, every ore its own pattern.
## The parts that glint are a second, glowing mesh.
##
## Used for the chunks in the ground (OreRock) and the pieces mined out of
## them (LooseItem); each is fitted to the box it occupies.

const PIECES := "res://assets/models/ores.glb"
static var _meshes: Dictionary = {}
static var _loaded: bool = false
static var _materials: Dictionary = {}

static func _piece(piece_name: String) -> Mesh:
	if not _loaded:
		_loaded = true
		var scene := load(PIECES) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			for n in root.find_children("*", "MeshInstance3D", true, false):
				_meshes[String(n.name)] = (n as MeshInstance3D).mesh
			root.free()
	return _meshes.get(piece_name, null)

static func _key(item_id: StringName) -> String:
	return "Ore_" + String(item_id).trim_prefix("ore_")

## Whether this ore has its own formation.
static func has_look(item_id: StringName) -> bool:
	return _piece(_key(item_id)) != null

## The ore's rock, fitted to a box of `size` whose centre is `centre`, turned
## `yaw` about the vertical: the body, and for the ores that glint the glowing
## parts. Empty if the ore has no look of its own.
static func rock(item_id: StringName, size: Vector3, centre: Vector3, yaw: float) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var key := _key(item_id)
	var body := _piece(key)
	if body == null:
		return out
	var box := body.get_aabb()
	# The rock is made of cubes, so it is only ever scaled evenly (a stretched
	# cube stops looking like one). It is turned so its longest side runs along
	# the longest side of `size` and its shortest along the shortest, then
	# scaled to the same volume.
	var from := _axes_by_length(box.size)
	var to := _axes_by_length(size)
	var turn := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for k in 3:
		var col := Vector3.ZERO
		col[to[k]] = 1.0
		turn[from[k]] = col
	if turn.determinant() < 0.0:
		turn[from[0]] = -turn[from[0]]
	var even := pow((size.x * size.y * size.z) / maxf(0.000001, box.size.x * box.size.y * box.size.z), 1.0 / 3.0)
	var fit := Basis(Vector3.UP, yaw) * turn * Basis.from_scale(Vector3.ONE * even)
	var xf := Transform3D(fit, centre - fit * box.get_center())
	for part in [key, key + "_Glow"]:
		var mesh := _piece(part)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "OreLook" if part == key else "OreGlint"
		mi.mesh = mesh
		mi.transform = xf
		mi.material_override = _material(item_id, part != key)
		out.append(mi)
	return out

static func _material(item_id: StringName, glow: bool) -> Material:
	var k := "%s|%d" % [item_id, int(glow)]
	if _materials.has(k):
		return _materials[k]
	var m: Material
	if glow:
		# The ore that sticks out of the rock glows, each cube in its own
		# colour (the colours are in the vertices, in linear light).
		var sm := ShaderMaterial.new()
		sm.shader = _glow_shader()
		m = sm
	else:
		var st := StandardMaterial3D.new()
		st.vertex_color_use_as_albedo = true
		st.roughness = 0.85
		m = st
	_materials[k] = m
	return m

static var _glow: Shader

static func _glow_shader() -> Shader:
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
	return _glow

## The three axes, longest first.
static func _axes_by_length(v: Vector3) -> Array[int]:
	var order: Array[int] = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return v[a] > v[b])
	return order
