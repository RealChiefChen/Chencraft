class_name ChoppableTree
extends StaticBody3D

## A tree built from cylinders, each of which can be cut on its own.
##
## There is no single "tree health": the trunk and every branch is a limb with
## its own collider and its own accumulated axe work, and a cut goes through
## whichever limb the player is actually aiming at. Work needed scales with the
## area of the cut face, so a branch is a swing or two and a trunk is real
## labour, and a sharper axe removes more area per swing.
##
## Cutting the trunk severs it at the height of the cut. Everything above that
## line leaves as one falling piece with exactly the shape it grew to, the
## branches above it come away as their own pieces, and what is left standing
## is a shorter tree that can be cut again. Leaves are decoration: they carry no
## collider, and they are gone when the wood they hang on comes down.

signal felled(tree: ChoppableTree)
signal limb_cut(tree: ChoppableTree, wood_volume: float)

@export var wood_item: StringName = &"wood_pine"
@export var trunk_height: float = 6.5
@export var trunk_radius: float = 0.34
@export var trunk_taper: float = 0.62      ## top radius as a fraction of the base
@export var branch_count: int = 5
## Axe work per square metre of cut face. A fat trunk is many swings.
@export var work_per_m2: float = 900.0

## What kind of tree this is. Wood is a separate thing: a swamp willow and a
## woodland oak are different trees that both cut into oak.
@export var species: String = "Tree"
@export var leaf_color: Color = Color(0.16, 0.44, 0.20)
## Where up the trunk the lowest branch sits, as a fraction of its height. Low
## for a conifer, high for a broadleaf carrying its crown above open trunk.
@export var branch_start: float = 0.45
## How far branches are swept up or out, in radians from vertical. A small
## range is a spire; a wide one is a spreading canopy.
@export var branch_pitch: Vector2 = Vector2(0.5, 0.95)
## Branch length as a fraction of trunk height.
@export var branch_length: Vector2 = Vector2(0.18, 0.30)
## Foliage clump radius, as a multiple of the branch it hangs on.
@export var foliage_spread: float = 7.0
## The crown on top: radius as a multiple of trunk radius, and height as a
## fraction of trunk height. A zero radius leaves the tree bare-topped.
@export var crown_spread: float = 6.5
@export var crown_height: float = 0.45
## How the leaves are drawn: cone (a conifer's drooping tiers), ball (round
## lumpy clumps), canopy (broad, flatter clumps: oak and the like), puff (a
## cloud of blossom), palm (fronds from the top only), cap (a giant
## mushroom) or bare (a dead snag, or something stranger).
@export var foliage_style: StringName = &"cone"
## Bark colour when it is not the wood's own (a birch is white outside).
@export var bark_color: Color = Color(0, 0, 0, 0)
## Dark marks up the bark (a birch's).
@export var bark_marks: bool = false
## Leaves (or cracks) that give off light, for the stranger trees.
@export var leaf_glow: float = 0.0
## A second leaf colour mixed through the canopy (blossom, autumn).
@export var leaf_accent: Color = Color(0, 0, 0, 0)

## Past this a tree is not drawn at all; the fog has it by then.
const VIEW_RANGE := 300.0
## How fast a severed trunk swings over, in radians per second about the cut.
const FALL_RATE := 0.9
## A trunk shorter than this is a stump: nothing left worth cutting.
const MIN_TRUNK := 0.6

var plot_id: int = 0
var manager: LooseItemManager

## Every branch still attached: {height, dir, radius, length, cut, mesh, leaf, shape}
var branches: Array[Dictionary] = []
## Work done on the trunk so far, and the height the current cut is being made.
var trunk_cut: float = 0.0
var trunk_cut_height: float = 0.0

var _trunk_mesh: MeshInstance3D
var _flare_mesh: MeshInstance3D
var _crown: MeshInstance3D
var _marks: Array[MeshInstance3D] = []

## The leaf clumps, fronds and root flare, made in Blender
## (assets/models/source/trees.blend): low-poly pieces with the light and shade
## painted into their vertex colours, tinted per tree. Leaves carry no
## collider, so they are only ever the look; the wood is still cut as before.
const PIECES := "res://assets/models/trees.glb"
static var _piece_meshes: Dictionary = {}
static var _pieces_loaded: bool = false

static func piece(piece_name: String) -> Mesh:
	if not _pieces_loaded:
		_pieces_loaded = true
		var scene := load(PIECES) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			for n in root.find_children("*", "MeshInstance3D", true, false):
				var near := _brightened((n as MeshInstance3D).mesh)
				_piece_meshes[String(n.name)] = near
				var far := _far_piece(String(n.name))
				if far != null:
					_far_of[near] = far
			root.free()
	return _piece_meshes.get(piece_name, null)

## Past NEAR_RANGE a tree is drawn from these instead: the same shapes in a
## fraction of the triangles (a leaf clump is 20, not 400).
static var _far_of: Dictionary = {}
const NEAR_RANGE := 35.0

static func _far_piece(piece_name: String) -> Mesh:
	match piece_name:
		"LeafClump", "CanopyClump", "BlossomClump":
			return _far_lump()
		"ConiferTier":
			return _far_tiers([[1.0, 0.0, 1.0]])
		"ConiferStack":
			return _far_tiers([[1.0, 0.0, 0.5], [0.72, 0.3, 0.42], [0.45, 0.56, 0.34], [0.22, 0.78, 0.22]])
	return null

## Three icosahedron lumps filling the -1..1 box, lighter on top: the near
## clump's outline in 60 triangles.
static func _far_lump() -> Mesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var lobes := [[Vector3(0, 0.1, 0), 0.72], [Vector3(0.45, -0.2, 0.2), 0.52], [Vector3(-0.4, -0.15, -0.3), 0.52]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lobe in lobes:
		for f in faces:
			for k in [0, 2, 1]:
				var p: Vector3 = (v[f[k]] / Vector3(v[f[k]]).length()) * float(lobe[1]) + (lobe[0] as Vector3)
				var b := 0.62 + 0.38 * clampf(p.y * 0.5 + 0.5, 0.0, 1.0)
				st.set_color(Color(b, b, b))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

## A conifer's tiers as eight-sided skirts: [radius, bottom, height] each.
static func _far_tiers(tiers: Array) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tier in tiers:
		var r := float(tier[0])
		var y0 := float(tier[1])
		var h := float(tier[2])
		var apex := Vector3(0, y0 + h, 0)
		var under := Vector3(0, y0 + 0.22 * h, 0)
		for i in 8:
			var a0 := TAU * float(i) / 8.0
			var a1 := TAU * float(i + 1) / 8.0
			var p0 := Vector3(cos(a0) * r, y0 - 0.05 * h, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, y0 - 0.05 * h, sin(a1) * r)
			for q in [[p0, 0.8], [apex, 1.0], [p1, 0.8], [p1, 0.62], [under, 0.62], [p0, 0.62]]:
				st.set_color(Color(q[1], q[1], q[1]))
				st.add_vertex(q[0])
	st.generate_normals()
	return st.commit()

## The shade painted into a piece, as a gentle 0.62..1 multiplier on the tint
## (the file keeps it in linear light, which reads far too dark on its own).
static func _brightened(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	if c.is_empty():
		return mesh
	for i in c.size():
		var b := 0.62 + 0.38 * pow(clampf(c[i].r, 0.0, 1.0), 1.0 / 2.2)
		c[i] = Color(b, b, b, 1.0)
	arrays[Mesh.ARRAY_COLOR] = c
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
var _trunk_shape: CollisionShape3D
## While nobody has touched it, the whole tree is drawn as this one mesh -
## every part's shape and colour baked together - instead of a dozen and a
## half, one draw each. The parts stay built, hidden, and come back the moment
## the tree is cut.
var _merged: MeshInstance3D
var _hidden_parts: Array[MeshInstance3D] = []
## Set by a field that casts its trees' shadows itself, from a cheap stand-in
## batched with the rest of its tile: the merged tree then casts none of its own.
var field_shadows: bool = false
var _standing: bool = true
var _rng := RandomNumberGenerator.new()
## Set by the first blow. A field only ever retires trees nobody has started on.
var touched: bool = false

func _ready() -> void:
	collision_layer = Layers.TREE
	collision_mask = Layers.WORLD
	if _rng.seed == 0:
		_rng.seed = hash(name) + int(position.x * 31.0) + int(position.z * 17.0)
	_build()

## Lets the spawner decide the tree's form deterministically.
func seed_form(value: int) -> void:
	_rng.seed = value
	_form_seed = value

## Standing and never cut: safe for a field to take away and grow elsewhere.
func untouched() -> bool:
	return _standing and not touched

func standing() -> bool:
	return _standing

func trunk_dims() -> Dictionary:
	return Solid.cylinder(trunk_radius, trunk_radius * trunk_taper, trunk_height)

## Radius of the trunk at a given height above the ground.
func radius_at(height: float) -> float:
	var t := clampf(height / maxf(0.01, trunk_height), 0.0, 1.0)
	return lerpf(trunk_radius, trunk_radius * trunk_taper, t)

## Total wood still standing: what is left to be cut out of this tree.
func wood_volume() -> float:
	if not _standing:
		return 0.0
	var total := Solid.volume(trunk_dims())
	for b in branches:
		total += Solid.volume(_branch_dims(b))
	return total

func _branch_dims(b: Dictionary) -> Dictionary:
	return Solid.cylinder(float(b.radius), float(b.get("tip", float(b.radius) * 0.7)), float(b.length))

## How far out along branch `index` a world point is, from the trunk.
func _branch_along(index: int, world_point: Vector3) -> float:
	var b: Dictionary = branches[index]
	var local := to_local(world_point) - Vector3(0, float(b.height), 0)
	return clampf(local.dot(b.dir as Vector3), 0.0, float(b.length))

# --- Construction ----------------------------------------------------------

func _build() -> void:
	var wood_def := GameData.item(wood_item)
	var bark: Color = wood_def.color if wood_def != null else Color(0.42, 0.29, 0.17)
	if bark_color.a > 0.0:
		bark = bark_color
	# A little variation per tree, so a stand is not one colour repeated.
	var leaf := leaf_color.lightened(_rng.randf_range(0.0, 0.10)) \
		if _rng.randf() > 0.5 else leaf_color.darkened(_rng.randf_range(0.0, 0.10))

	_trunk_shape = CollisionShape3D.new()
	_trunk_shape.shape = CylinderShape3D.new()
	add_child(_trunk_shape)

	# The foot of the trunk, with buttress roots, turned a random way.
	_flare_mesh = _add_piece("RootFlare", Transform3D(
		Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(trunk_radius, maxf(0.45, trunk_radius * 1.3), trunk_radius)),
		Vector3.ZERO), bark.darkened(0.12))
	if _flare_mesh == null:
		_flare_mesh = _add_cylinder(trunk_radius * 1.45, trunk_radius * 1.02, 0.5,
			Transform3D(Basis(), Vector3(0, 0.25, 0)), bark.darkened(0.15))
	_trunk_mesh = _add_cylinder(trunk_radius, trunk_radius * trunk_taper, trunk_height,
		Transform3D(Basis(), Vector3(0, trunk_height * 0.5, 0)), bark)
	if bark_marks:
		_add_marks()
	if crown_spread > 0.01 and foliage_style != &"bare":
		_crown = _add_foliage(trunk_radius * crown_spread, trunk_height * crown_height,
			Transform3D(Basis(), Vector3(0, _crown_y(), 0)), leaf.darkened(0.05), true)

	for i in branch_count:
		var span: float = maxf(0.05, 0.98 - branch_start)
		var t: float = branch_start + span * float(i) / maxf(1.0, float(branch_count - 1))
		var height: float = trunk_height * t
		var yaw: float = _rng.randf_range(0.0, TAU)
		var pitch: float = _rng.randf_range(branch_pitch.x, branch_pitch.y)
		var length: float = trunk_height * _rng.randf_range(branch_length.x, branch_length.y)
		var radius: float = radius_at(height) * 0.42
		var dir := Vector3(cos(yaw) * sin(pitch), cos(pitch), sin(yaw) * sin(pitch)).normalized()
		var base := Vector3(0, height, 0)
		var basis := _basis_from_up(dir)
		var mesh := _add_cylinder(radius, radius * 0.7, length,
			Transform3D(basis, base + dir * length * 0.5), bark.lightened(0.05))
		var tint := leaf
		if leaf_accent.a > 0.0 and _rng.randf() < 0.45:
			tint = leaf_accent
		var foliage: MeshInstance3D = null
		if foliage_style == &"cone" and piece("ConiferTier") != null:
			# A conifer's bough: a drooping tier hung level off the branch,
			# close in to the trunk, so the tree reads as layers of needles.
			foliage = _add_foliage(radius * foliage_spread * 1.7, length * 1.1,
				Transform3D(Basis(), base + dir * length * 0.55 - Vector3(0, length * 0.3, 0)), tint, false)
		elif foliage_style != &"bare" and foliage_style != &"palm":
			foliage = _add_foliage(radius * foliage_spread, length * 1.25,
				Transform3D(Basis(), base + dir * (length + length * 0.35)), tint, false)
		# Each branch gets its own collider, so the aim ray can say which one
		# the player is standing under.
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = length
		shape.shape = cyl
		shape.transform = Transform3D(basis, base + dir * length * 0.5)
		add_child(shape)
		branches.append({"id": i, "height": height, "dir": dir, "radius": radius, "tip": radius * 0.7,
			"length": length, "cut": 0.0, "cut_at": -1.0, "mesh": mesh, "leaf": foliage, "shape": shape})

	_refresh_trunk()
	_merge()

## Rebuilds the trunk mesh and collider from the current height, after a cut has
## shortened the tree.
func _refresh_trunk() -> void:
	var cm := _trunk_mesh.mesh as CylinderMesh
	cm.bottom_radius = trunk_radius
	cm.top_radius = trunk_radius * trunk_taper
	cm.height = trunk_height
	_trunk_mesh.position = Vector3(0, trunk_height * 0.5, 0)
	var cyl := _trunk_shape.shape as CylinderShape3D
	cyl.radius = trunk_radius
	cyl.height = trunk_height
	_trunk_shape.position = Vector3(0, trunk_height * 0.5, 0)
	if _crown != null and is_instance_valid(_crown):
		_crown.visible = _standing and (not branches.is_empty() or foliage_style == &"palm" \
			or foliage_style == &"cap")
		_crown.position = Vector3(0, _crown_y(), 0)
	for m in _marks:
		m.visible = m.position.y < trunk_height - 0.1

## Where the crown sits: a conifer's stack of tiers comes down over the top of
## the trunk; anything else sits on top of it.
func _crown_y() -> float:
	if foliage_style == &"cone" and piece("ConiferStack") != null:
		return trunk_height * (1.04 - crown_height * 0.92)
	return trunk_height * 1.02

## A birch's dark marks: short black dashes round the white bark.
func _add_marks() -> void:
	var dash := BoxMesh.new()
	dash.size = Vector3.ONE
	for k in int(clampf(trunk_height * 1.6, 6.0, 18.0)):
		var y := _rng.randf_range(0.6, trunk_height * 0.92)
		var a := _rng.randf_range(0.0, TAU)
		var r := radius_at(y)
		var mi := MeshInstance3D.new()
		mi.mesh = dash
		mi.transform = Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.05, _rng.randf_range(0.05, 0.11), r * _rng.randf_range(0.9, 1.3))),
			Vector3(cos(a) * r, y, sin(a) * r))
		mi.material_override = _mat(Color(0.12, 0.11, 0.10))
		mi.visibility_range_end = VIEW_RANGE * 0.5
		add_child(mi)
		_marks.append(mi)

static var _merged_material: StandardMaterial3D
## Merged meshes by species and seed: the same seed grows the same tree, so a
## tree that goes back to being a note and is built again reuses its mesh.
static var _merged_cache: Dictionary = {}
const MERGED_CACHE_MAX := 4000
var _form_seed: int = 0

## Bakes every visible part into one mesh with its colour in the vertices, and
## hides the parts. Glowing trees keep their own materials and are left be.
func _merge() -> void:
	if leaf_glow > 0.0 or _merged != null:
		return
	var key := "%s|%d|%.3f" % [species, _form_seed, trunk_height]
	var pair: Array = _merged_cache.get(key, []) if _form_seed != 0 else []
	var parts: Array[MeshInstance3D] = []
	var mesh: ArrayMesh
	var far_mesh: ArrayMesh
	if not pair.is_empty():
		mesh = pair[0]
		far_mesh = pair[1]
		for child in get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).visible:
				parts.append(child)
	else:
		mesh = _bake(parts)
		if mesh == null:
			return
		var ignore: Array[MeshInstance3D] = []
		far_mesh = _bake(ignore, true)
		if _form_seed != 0:
			if _merged_cache.size() >= MERGED_CACHE_MAX:
				_merged_cache.clear()
			_merged_cache[key] = [mesh, far_mesh]
	if _merged_material == null:
		_merged_material = StandardMaterial3D.new()
		_merged_material.vertex_color_use_as_albedo = true
		_merged_material.vertex_color_is_srgb = true
		_merged_material.roughness = 0.95
	_merged = MeshInstance3D.new()
	_merged.name = "Merged"
	_merged.mesh = mesh
	_merged.material_override = _merged_material
	_merged.visibility_range_end = VIEW_RANGE
	if field_shadows:
		_merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_merged)
	# Near, every clump in full; further out, the light version.
	if far_mesh != null:
		_merged.visibility_range_end = NEAR_RANGE
		_merged.visibility_range_end_margin = 4.0
		var far := MeshInstance3D.new()
		far.name = "MergedFar"
		far.mesh = far_mesh
		far.material_override = _merged_material
		far.visibility_range_begin = NEAR_RANGE
		far.visibility_range_begin_margin = 4.0
		far.visibility_range_end = VIEW_RANGE
		far.cast_shadow = _merged.cast_shadow
		_merged.add_child(far)
	for part in parts:
		part.visible = false
	_hidden_parts = parts

## The visible parts baked into one mesh; `parts` gets the top-level ones.
func _bake(parts: Array[MeshInstance3D], far: bool = false) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	if not _gather(self, Transform3D(), verts, normals, colors, indices, parts, far):
		return null
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Adds the meshes under `node` (drawn through `xform`) to the arrays. Returns
## false if some part cannot be baked, in which case nothing is merged.
func _gather(node: Node, xform: Transform3D, verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array, top: Array[MeshInstance3D], far: bool = false) -> bool:
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		# Far off, the birch's dashes are too small to see.
		if far and mi in _marks:
			continue
		var source: Mesh = _far_of.get(mi.mesh, mi.mesh) if far else mi.mesh
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			return false
		var at := xform * mi.transform
		var arrays := source.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var base := verts.size()
		verts.append_array(at * v)
		normals.append_array(Transform3D(at.basis, Vector3.ZERO) * n)
		var c := PackedColorArray()
		c.resize(v.size())
		c.fill(mat.albedo_color)
		# A Blender piece's shading is in its own vertex colours: keep it.
		var own = arrays[Mesh.ARRAY_COLOR]
		if mat.vertex_color_use_as_albedo and own != null and (own as PackedColorArray).size() == v.size():
			for k in v.size():
				c[k] = mat.albedo_color * (own as PackedColorArray)[k]
		colors.append_array(c)
		var idx = arrays[Mesh.ARRAY_INDEX]
		var own_idx := PackedInt32Array()
		if idx == null or (idx as PackedInt32Array).is_empty():
			for k in v.size():
				own_idx.append(k)
		else:
			own_idx = idx
		for k in own_idx:
			indices.append(base + k)
		# Drawn from both sides (palm fronds): the merged material is not, so
		# the back is added as its own faces, turned the other way.
		if mat.cull_mode == BaseMaterial3D.CULL_DISABLED:
			var back := verts.size()
			verts.append_array(at * v)
			var flipped := Transform3D(at.basis, Vector3.ZERO) * n
			for k in flipped.size():
				flipped[k] = -flipped[k]
			normals.append_array(flipped)
			colors.append_array(c)
			for k in range(0, own_idx.size() - 2, 3):
				indices.append(back + own_idx[k])
				indices.append(back + own_idx[k + 2])
				indices.append(back + own_idx[k + 1])
		if node == self:
			top.append(mi)
		if not _gather(mi, at, verts, normals, colors, indices, top, far):
			return false
	return true

## Drawn as the one merged mesh (untouched, and not a glowing kind)?
func is_merged() -> bool:
	return _merged != null

## Back to separate parts, which cutting works on one at a time.
func _unmerge() -> void:
	if _merged == null:
		return
	_merged.queue_free()
	_merged = null
	for part in _hidden_parts:
		if is_instance_valid(part):
			part.visible = true
	_hidden_parts.clear()

func _basis_from_up(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	if axis.length_squared() < 0.0001:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))

func _add_cylinder(r_bottom: float, r_top: float, height: float, xform: Transform3D,
		color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = height
	cm.radial_segments = Tuning.ROUND_SIDES
	cm.rings = 1
	mi.mesh = cm
	mi.transform = xform
	mi.material_override = _mat(color)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

func _add_cone(radius: float, height: float, xform: Transform3D, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = 0.0
	cm.height = height
	cm.radial_segments = Tuning.ROUND_SIDES
	cm.rings = 1
	mi.mesh = cm
	mi.transform = xform
	mi.material_override = _mat(color)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

## Trees share materials by colour, so a forest of a few species is a few
## materials rather than one per branch.
static var _materials: Dictionary = {}

func _mat(color: Color, glow: float = 0.0, shaded: bool = false, two_sided: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%d%d" % [color.to_html(), glow, int(shaded), int(two_sided)]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	# A Blender piece's light and shade is in its vertex colours: the tint
	# multiplies it.
	m.vertex_color_use_as_albedo = shaded
	m.vertex_color_is_srgb = shaded
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_materials[key] = m
	return m

## One clump of leaves in the tree's style. `crown` is the top of the tree.
func _add_foliage(radius: float, height: float, xform: Transform3D, color: Color,
		crown: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = _add_clump(radius, height, xform, color, crown)
	if mi != null:
		if leaf_glow > 0.0:
			_glow_all(mi, color)
		return mi
	match foliage_style:
		&"ball", &"canopy":
			mi = _add_ball(radius * 0.85, height * 0.85, xform.translated(Vector3(0, height * 0.2, 0)), color)
		&"puff":
			# A few overlapping balls: blossom or a cloud of small leaves.
			mi = _add_ball(radius * 0.7, height * 0.7, xform.translated(Vector3(0, height * 0.2, 0)), color)
			for k in 3:
				var a := TAU * float(k) / 3.0 + _rng.randf()
				var puff := _add_ball(radius * 0.5, height * 0.5,
					Transform3D(Basis(), Vector3(cos(a) * radius * 0.55, height * 0.1, sin(a) * radius * 0.55)),
					color.lightened(_rng.randf_range(0.0, 0.12)))
				remove_child(puff)
				mi.add_child(puff)
		&"palm":
			mi = _add_fronds(radius, xform, color)
		&"cap":
			# A giant mushroom's cap: a broad, flattened dome with a pale
			# rim of gills under it.
			mi = _add_ball(radius, height * 0.5, xform.translated(Vector3(0, height * 0.05, 0)), color)
			var gills := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius * 0.92
			cyl.bottom_radius = trunk_radius * 1.3
			cyl.height = height * 0.14
			cyl.radial_segments = 10
			gills.mesh = cyl
			gills.position = Vector3(0, -height * 0.02, 0)
			gills.material_override = _mat(leaf_accent if leaf_accent.a > 0.0 else color.lightened(0.4), leaf_glow * 0.6)
			mi.add_child(gills)
		_:
			mi = _add_cone(radius, height, xform, color)
	if leaf_glow > 0.0:
		mi.material_override = _mat(color, leaf_glow)
	return mi

## A clump made from a Blender piece, or null to fall back on primitives.
func _add_clump(radius: float, height: float, xform: Transform3D, color: Color, crown: bool) -> MeshInstance3D:
	var turn := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	match foliage_style:
		&"ball", &"canopy", &"puff":
			var piece_name: String = {&"ball": "LeafClump", &"canopy": "CanopyClump", &"puff": "BlossomClump"}[foliage_style]
			var r := radius * 0.85
			var tall := minf(maxf(height * 0.85, r * (0.95 if foliage_style == &"canopy" else 1.2)), r * 1.35) * 0.5
			return _add_piece(piece_name, Transform3D(turn * Basis.from_scale(Vector3(r, tall, r)),
				xform.origin + Vector3(0, height * 0.2, 0)), color)
		&"palm":
			if piece("PalmFrond") == null:
				return null
			# A knob at the top of the trunk, and fronds arching out of it.
			var hub := _add_piece("LeafClump", Transform3D(Basis.from_scale(Vector3(trunk_radius * 1.5, trunk_radius * 1.2, trunk_radius * 1.5)),
				xform.origin), color.darkened(0.25))
			var reach := maxf(radius, 2.2)
			var count := 9
			for k in count:
				var a := TAU * float(k) / float(count) + _rng.randf_range(-0.2, 0.2)
				var tilt := _rng.randf_range(-0.15, 0.25)
				var frond := _add_piece("PalmFrond", Transform3D(
					Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(Vector3(reach * 0.9, reach, reach)),
					Vector3.ZERO), color if k % 2 == 0 else color.lightened(0.08), true)
				# Inverse of the hub's scale, so the fronds hang off it at full size.
				remove_child(frond)
				hub.add_child(frond)
				frond.transform = Transform3D(hub.transform.basis.inverse(), Vector3.ZERO) * frond.transform
			return hub
		&"cap", &"bare":
			return null
		_:
			var piece_name := "ConiferStack" if crown else "ConiferTier"
			return _add_piece(piece_name, Transform3D(turn * Basis.from_scale(Vector3(radius, height, radius)), xform.origin), color)

func _add_piece(piece_name: String, xform: Transform3D, color: Color, two_sided: bool = false) -> MeshInstance3D:
	var mesh := piece(piece_name)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	mi.material_override = _mat(color, 0.0, true, two_sided)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

## Glowing leaves (the stranger trees): every part of a clump.
func _glow_all(mi: MeshInstance3D, color: Color) -> void:
	var two_sided := mi.material_override != null and (mi.material_override as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED
	mi.material_override = _mat(color, leaf_glow, true, two_sided)
	for c in mi.get_children():
		if c is MeshInstance3D:
			_glow_all(c as MeshInstance3D, color)

func _add_ball(radius: float, height: float, xform: Transform3D, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = maxf(height, radius * 1.2)
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.transform = xform
	mi.material_override = _mat(color)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

## Palm fronds: long flat blades drooping out from the top of the trunk.
func _add_fronds(radius: float, xform: Transform3D, color: Color) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var hub := SphereMesh.new()
	hub.radius = trunk_radius * 1.4
	hub.height = trunk_radius * 2.0
	hub.radial_segments = 6
	hub.rings = 3
	root.mesh = hub
	root.transform = xform
	root.material_override = _mat(color.darkened(0.2))
	add_child(root)
	var count := 8
	var reach := maxf(radius, 2.2)
	for k in count:
		var a := TAU * float(k) / float(count) + _rng.randf_range(-0.2, 0.2)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.1, 0.06, reach)
		blade.mesh = bm
		var dir := Vector3(cos(a), 0, sin(a))
		var droop := _rng.randf_range(0.25, 0.55)
		blade.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, droop),
			dir * reach * 0.45 + Vector3(0, -reach * 0.18, 0))
		blade.material_override = _mat(color if k % 2 == 0 else color.lightened(0.08))
		root.add_child(blade)
	return root

# --- Cutting ---------------------------------------------------------------

## Which limb a world point belongs to: -1 for the trunk, otherwise an index
## into `branches`. Points are matched to the nearest branch axis, so aiming at
## a branch cuts that branch and aiming past it cuts the trunk.
func limb_at(world_point: Vector3) -> int:
	var local := to_local(world_point)
	var best := -1
	var best_d := INF
	for i in branches.size():
		var b: Dictionary = branches[i]
		var base := Vector3(0, float(b.height), 0)
		var dir: Vector3 = b.dir
		var along: float = clampf((local - base).dot(dir), 0.0, float(b.length))
		var d: float = local.distance_to(base + dir * along)
		if d < best_d and d < float(b.radius) * 2.2:
			best_d = d
			best = i
	# The trunk wins when the point is inside it, whatever branch is nearby.
	var height := clampf(local.y, 0.0, trunk_height)
	var trunk_d := Vector2(local.x, local.z).length()
	if trunk_d <= radius_at(height) * 1.25:
		return -1
	return best

## Work one swing of the axe into the limb under `world_point`. Returns a short
## line describing what happened.
func cut(damage: float, world_point: Vector3, from: Vector3) -> String:
	if not _standing:
		return ""
	touched = true
	_unmerge()
	var index := limb_at(world_point)
	if index >= 0:
		return _cut_branch(index, damage, _branch_along(index, world_point))
	return _cut_trunk(damage, to_local(world_point).y, from)

## How far out from the trunk's centre a cut still takes a branch off whole.
func _joint_reach(b: Dictionary) -> float:
	var dir: Vector3 = b.dir
	var out := maxf(0.3, Vector2(dir.x, dir.z).length())
	return radius_at(float(b.height)) * 1.25 / out + LooseItem.MIN_STUB

## The radius of a branch `along` metres out from the trunk (at the joint, its
## full base).
func _branch_radius_at(b: Dictionary, along: float) -> float:
	if along < _joint_reach(b):
		return float(b.radius)
	return lerpf(float(b.radius), float(b.get("tip", float(b.radius) * 0.7)), along / maxf(0.01, float(b.length)))

## A cut anywhere along a branch: right at the trunk it takes the whole branch;
## further out the end drops and a stub stays on the tree.
func _cut_branch(index: int, damage: float, along: float) -> String:
	var b: Dictionary = branches[index]
	if float(b.cut_at) < 0.0 or absf(along - float(b.cut_at)) > 0.3:
		b.cut_at = along
		b.cut = 0.0
	var r := _branch_radius_at(b, float(b.cut_at))
	var needed: float = PI * r * r * work_per_m2
	b.cut = float(b.cut) + damage
	if float(b.cut) < needed:
		_nudge(b.mesh)
		return "cutting branch: %d%%" % int(float(b.cut) / needed * 100.0)
	var at := float(b.cut_at)
	# Cut close in to the trunk, the whole branch comes away.
	if at < _joint_reach(b):
		_drop_branch(index, Vector3.ZERO)
		return "branch off"
	var fell_off := float(b.length) - minf(at, float(b.length) - LooseItem.MIN_STUB)
	_cut_branch_back(index, at)
	return "branch cut back: %.2f m off" % fell_off

## Drops the end of a branch past `at` metres and leaves the stub. Returns the
## volume that fell.
func _cut_branch_back(index: int, at: float) -> float:
	var b: Dictionary = branches[index]
	var length := float(b.length)
	at = minf(at, length - LooseItem.MIN_STUB)
	var r_cut := _branch_radius_at(b, at)
	var outer := Solid.cylinder(r_cut, float(b.get("tip", float(b.radius) * 0.7)), length - at)
	var dir: Vector3 = b.dir
	var base := Vector3(0, float(b.height), 0)
	var basis := _basis_from_up(dir)
	if manager != null:
		manager.spawn(wood_item, Transform3D(global_transform.basis * basis,
			global_transform * (base + dir * (at + (length - at) * 0.5))), plot_id, dir * 0.4, outer)
	_shorten_branch(b, at, r_cut)
	return Solid.volume(outer)

## Redraws a branch cut back to `at` metres, its end radius now `r_cut`.
func _shorten_branch(b: Dictionary, at: float, r_cut: float) -> void:
	var dir: Vector3 = b.dir
	var base := Vector3(0, float(b.height), 0)
	var basis := _basis_from_up(dir)
	b.length = at
	b.tip = r_cut
	b.cut = 0.0
	b.cut_at = -1.0
	var mesh := b.mesh as MeshInstance3D
	if is_instance_valid(mesh):
		var cm := mesh.mesh as CylinderMesh
		cm.top_radius = r_cut
		cm.height = at
		mesh.transform = Transform3D(basis, base + dir * at * 0.5)
	# The leaves hung at the end that came off.
	if b.leaf != null and is_instance_valid(b.leaf):
		(b.leaf as Node).queue_free()
	b.leaf = null
	var shape := b.shape as CollisionShape3D
	var cyl := (shape.shape as CylinderShape3D).duplicate() as CylinderShape3D
	cyl.height = at
	shape.shape = cyl
	shape.transform = Transform3D(basis, base + dir * at * 0.5)

# --- Co-op ---------------------------------------------------------------------------

## What a guest needs to draw this tree as it now stands: the trunk and each
## branch still on it.
func net_state() -> Dictionary:
	var bs: Array = []
	for b in branches:
		bs.append([int(b.get("id", -1)), float(b.length), float(b.get("tip", float(b.radius) * 0.7))])
	return {"h": trunk_height, "tp": trunk_taper, "b": bs}

## A guest's copy takes the host's state: a shorter trunk, branches gone or
## cut back. It never grows anything back.
func net_apply(state: Dictionary) -> void:
	_unmerge()
	var h := float(state.get("h", trunk_height))
	if not is_equal_approx(h, trunk_height) or not is_equal_approx(float(state.get("tp", trunk_taper)), trunk_taper):
		trunk_height = h
		trunk_taper = float(state.get("tp", trunk_taper))
		_refresh_trunk()
	var keep: Dictionary = {}
	for e in state.get("b", []):
		keep[int(e[0])] = e
	for i in range(branches.size() - 1, -1, -1):
		var b: Dictionary = branches[i]
		var id := int(b.get("id", -1))
		if not keep.has(id):
			for part in [b.mesh, b.leaf, b.shape]:
				if part != null and is_instance_valid(part):
					(part as Node).queue_free()
			branches.remove_at(i)
			continue
		var e: Array = keep[id]
		if float(e[1]) < float(b.length) - 0.001:
			_shorten_branch(b, float(e[1]), float(e[2]))
	if branches.is_empty() and _crown != null and foliage_style != &"palm" and foliage_style != &"cap":
		_crown.visible = false

## Severs the trunk at `height`. Everything above leaves; what is below stays
## standing and can be cut again.
func _cut_trunk(damage: float, height: float, from: Vector3) -> String:
	height = clampf(height, 0.0, trunk_height)
	# Moving the cut to a different height starts a new cut.
	if absf(height - trunk_cut_height) > 0.45:
		trunk_cut_height = height
		trunk_cut = 0.0
	var radius := radius_at(trunk_cut_height)
	var needed: float = PI * radius * radius * work_per_m2
	trunk_cut += damage
	if trunk_cut < needed:
		_nudge(_trunk_mesh)
		return "cutting trunk: %d%%" % int(trunk_cut / needed * 100.0)
	return _sever(trunk_cut_height, from)

## Drops everything above `height` as loose wood and leaves the rest standing.
func _sever(height: float, from: Vector3) -> String:
	var dir := global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD

	var cut_radius := radius_at(height)
	var top_radius := trunk_radius * trunk_taper
	var upper := Solid.cylinder(cut_radius, top_radius, maxf(0.05, trunk_height - height))
	var dropped := Solid.volume(upper)

	if manager != null and trunk_height - height > 0.05:
		# The severed length has to pivot about the cut, not spin about its own
		# middle: a cylinder given angular velocity about its centre drives one
		# edge of its base into whatever it is standing on and the contact
		# cancels it, which is what a standing quarter-tonne pole does - nothing.
		# So it gets a rotation about the cut plus the matching centre-of-mass
		# velocity, and a couple of degrees of lean to break the symmetry.
		var axis := Vector3.UP.cross(dir).normalized()
		var lean := Basis(axis, 0.06)
		var centre := global_position + Vector3(0, height + (trunk_height - height) * 0.5, 0)
		var piece := manager.spawn(wood_item, Transform3D(lean, centre), plot_id,
			Vector3.ZERO, upper)
		if piece != null:
			# The branches above the cut come down on it, still attached:
			# limbing them off is the next job.
			for i in range(branches.size() - 1, -1, -1):
				if float(branches[i].height) >= height:
					dropped += _attach_branch(i, piece)
			var spin := axis * FALL_RATE
			piece.angular_velocity = spin
			piece.linear_velocity = spin.cross(Vector3(0, (trunk_height - height) * 0.5, 0))

	# Any branches above the cut not taken with it (no trunk piece) drop loose.
	for i in range(branches.size() - 1, -1, -1):
		if float(branches[i].height) >= height:
			dropped += _drop_branch(i, dir * 1.5)

	# The stump keeps the taper it actually grew: it runs from its base radius
	# to the radius at the cut, not to the radius the whole tree ended at. Get
	# this wrong and the two halves of a cut no longer add up to the tree.
	trunk_taper = cut_radius / maxf(0.001, trunk_radius)
	trunk_height = height
	trunk_cut = 0.0
	trunk_cut_height = 0.0
	_refresh_trunk()
	limb_cut.emit(self, dropped)
	if trunk_height <= MIN_TRUNK:
		_standing = false
		_trunk_shape.disabled = true
		_trunk_mesh.visible = false
		_flare_mesh.visible = false
		if _crown != null:
			_crown.visible = false
		collision_layer = 0
		Sfx.play(&"fall", global_position + Vector3.UP * 2.0)
		felled.emit(self)
		return "tree down"
	return "trunk severed at %.1f m" % height

## Takes one branch off the tree and turns it into loose wood. Returns its volume.
## Cuts the tree right through at the base, dropping the whole thing. What a
## perfect swing with an oversized axe would do, and how tests and the smoke
## run take a tree down in one call.
func fell(from: Vector3 = Vector3.ZERO) -> String:
	if not _standing:
		return ""
	_unmerge()
	var origin := from if from != Vector3.ZERO else global_position + Vector3(0, 0, 3)
	return _sever(0.0, origin)

## Moves a branch - its model, its foliage, its collider and its weight - on
## to the felled trunk piece. Returns its volume.
func _attach_branch(index: int, piece: LooseItem) -> float:
	var b: Dictionary = branches[index]
	var dims := _branch_dims(b)
	var inv := piece.global_transform.affine_inverse()
	var origin: Vector3 = inv * (global_position + Vector3(0, float(b.height), 0))
	var dir: Vector3 = inv.basis * (b.dir as Vector3)
	var visuals: Array = [b.mesh]
	# The leaves do not come down with it: a felled trunk is bare wood,
	# branches and all, and the leaves are not worth anything.
	if b.leaf != null and is_instance_valid(b.leaf):
		(b.leaf as Node).queue_free()
	b.leaf = null
	piece.add_limb(origin, dir, float(b.radius), float(b.length), visuals, Color(0.42, 0.3, 0.2),
		float(b.get("tip", float(b.radius) * 0.7)))
	(b.shape as CollisionShape3D).queue_free()
	branches.remove_at(index)
	if branches.is_empty() and _crown != null and foliage_style != &"palm" and foliage_style != &"cap":
		_crown.visible = false
	return Solid.volume(dims)

func _drop_branch(index: int, impulse: Vector3) -> float:
	var b: Dictionary = branches[index]
	var dims := _branch_dims(b)
	if manager != null:
		var basis := _basis_from_up(b.dir)
		var pos: Vector3 = global_position + Vector3(0, float(b.height), 0) \
			+ (b.dir as Vector3) * float(b.length) * 0.5
		manager.spawn(wood_item, Transform3D(basis, pos), plot_id,
			impulse + (b.dir as Vector3) * 0.8, dims)
	(b.mesh as MeshInstance3D).queue_free()
	if b.leaf != null and is_instance_valid(b.leaf):
		(b.leaf as MeshInstance3D).queue_free()
	(b.shape as CollisionShape3D).queue_free()
	branches.remove_at(index)
	if branches.is_empty() and _crown != null and foliage_style != &"palm" and foliage_style != &"cap":
		_crown.visible = false
	return Solid.volume(dims)

func _nudge(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh):
		return
	mesh.scale = Vector3(1.05, 0.99, 1.05)
	create_tween().tween_property(mesh, "scale", Vector3.ONE, 0.12)

## How far through the limb under this point the current cut is, 0..1. Drives
## the aim prompt.
func cut_progress_at(world_point: Vector3) -> float:
	var index := limb_at(world_point)
	if index >= 0:
		var b: Dictionary = branches[index]
		if float(b.cut_at) < 0.0 or absf(_branch_along(index, world_point) - float(b.cut_at)) > 0.3:
			return 0.0
		var r := _branch_radius_at(b, float(b.cut_at))
		var needed: float = PI * r * r * work_per_m2
		return clampf(float(b.cut) / maxf(0.001, needed), 0.0, 1.0)
	var height := clampf(to_local(world_point).y, 0.0, trunk_height)
	if absf(height - trunk_cut_height) > 0.45:
		return 0.0
	var radius := radius_at(trunk_cut_height)
	return clampf(trunk_cut / maxf(0.001, PI * radius * radius * work_per_m2), 0.0, 1.0)
