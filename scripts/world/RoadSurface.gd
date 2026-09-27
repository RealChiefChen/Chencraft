class_name RoadSurface
extends Node3D

## The roads as something laid on the land rather than a grey stripe of it: a
## textured carriageway sitting a hand's width proud of the graded ground, with
## painted edge lines and a dashed centre line, a gravel verge down each side,
## and marker posts with red reflectors every forty metres. Dirt spurs get a
## rutted track instead, and no paint.
##
## Solid: the surface carries its own collision, so what you stand on is
## the road you see.

const HALF := 4.8                   ## half the carriageway
const VERGE := 1.5                  ## gravel each side of that
const LIFT := 0.14
const STEP := 3.0                   ## metres between cross-sections
const PIECE := 360.0                ## metres of road per mesh, for culling
const POST_EVERY := 40.0
## The plain road's shoulder each side, sloping from the carriageway down to
## the land.
const SHOULDER := 1.2
## How far either way the road's direction is judged over.
const TANGENT_REACH := 4.0

var terrain: Terrain
var _body: StaticBody3D
static var _materials: Dictionary = {}
## Plain roads: just a band of a different colour on the land, no paint, no
## verges, no posts - the look of a block-built world.
var plain: bool = true
const PLAIN_ROAD := Color(0.64, 0.66, 0.70)
const PLAIN_DIRT := Color(0.76, 0.62, 0.46)

func setup(p_terrain: Terrain) -> void:
	terrain = p_terrain

func _ready() -> void:
	if terrain == null:
		return
	for road in terrain.road_paths:
		_build_road(road.path, String(road.style), road.get("profile", PackedFloat32Array()),
			float(road.get("trim", 0.0)))

func _build_road(path: Array, style: String, profile: PackedFloat32Array = PackedFloat32Array(),
		trim: float = 0.0) -> void:
	if path.size() < 2:
		return
	var span := terrain._path_length(path)
	var dirt := style == "dirt"
	var half := HALF * (0.75 if dirt else 1.0)
	var verge := SHOULDER if plain else VERGE
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var posts := Greeble.new()
	var piece_start := 0.0
	var prev: Array = []
	# A road leaving another starts at that one's edge, not over its surface.
	var along := trim
	var next_post := POST_EVERY * 0.5
	while along <= span:
		var p := terrain._point_along(path, along)
		# The direction is taken over a few metres either way, so a tight bend
		# turns the cross-sections smoothly rather than a step at a time.
		var ahead := terrain._point_along(path, minf(span, along + TANGENT_REACH))
		var behind := terrain._point_along(path, maxf(0.0, along - TANGENT_REACH))
		var tangent := Vector3(ahead.x - behind.x, 0.0, ahead.z - behind.z).normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var ground := terrain.height_at(p.x, p.z)
		# Over water the bridge deck carries the road; the surface stops at
		# either end of it.
		var wet := ground < Terrain.WATER_LEVEL - 0.05 and not dirt
		# No road across the player's land: it stops at the edge of the plot.
		var kept_clear := terrain.in_clear_zone(p.x, p.z, half + verge + 0.5)
		var section: Array = []
		if not wet and not kept_clear:
			# The carriageway is level across at the road's own height, bends
			# and all - never tipped toward the hillside on a turn - and the
			# shoulders run from its edges down to the land (the land under a
			# road is cut down to it, so it never stands up through it).
			var level := (terrain._profile_height(profile, along, span) if not profile.is_empty() \
				else ground + Terrain.ROAD_SINK) + LIFT
			# Where the road stops at the plot it comes down to the ground over
			# its last few metres, rather than ending in a step.
			var before := terrain._point_along(path, maxf(0.0, along - STEP))
			var after := terrain._point_along(path, minf(span, along + STEP))
			if terrain.in_clear_zone(before.x, before.z, half + verge + 0.5) \
					or terrain.in_clear_zone(after.x, after.z, half + verge + 0.5):
				level = minf(level, ground + 0.03)
			for k in [-(half + verge + 0.01), -half, half, half + verge + 0.01]:
				var q: Vector3 = p + side * float(k)
				section.append(Vector3(q.x, level, q.z))
			for k in [0, 3]:
				var land := terrain.height_at(section[k].x, section[k].z) + LIFT * 0.5
				section[k].y = minf(land, level - 0.01)
			# On the inside of a tight bend the edge would come back past
			# where it was a step ago and fold the strip over itself: it is
			# held where it was instead.
			if not prev.is_empty():
				for k in 4:
					var was: Vector3 = prev[k]
					if (section[k] - was).dot(tangent) < 0.05:
						var y: float = section[k].y
						section[k] = was + tangent * 0.05
						section[k].y = y
		if not prev.is_empty() and not section.is_empty():
			_quad_strip(verts, uvs, colors, prev, section, along, dirt)
		prev = section
		if not wet and not kept_clear and along >= next_post and not dirt and not plain:
			next_post += POST_EVERY
			for s in [-1.0, 1.0]:
				var at: Vector3 = p + side * s * (half + VERGE + 0.4)
				at.y = terrain.height_at(at.x, at.z)
				posts.block(Vector3(0.14, 1.0, 0.14), at + Vector3(0, 0.5, 0), Color(0.94, 0.94, 0.9))
				posts.block(Vector3(0.16, 0.14, 0.16), at + Vector3(0, 0.86, 0), Color(0.9, 0.12, 0.1), true)
		if along - piece_start >= PIECE:
			_flush(verts, uvs, colors, dirt)
			verts = PackedVector3Array()
			uvs = PackedVector2Array()
			colors = PackedColorArray()
			piece_start = along
		along += STEP
	_flush(verts, uvs, colors, dirt)
	if not posts.is_empty():
		add_child(posts.instance("RoadPosts", false))

## One step of road: the verge, the carriageway and the other verge.
func _quad_strip(verts: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray,
		a: Array, b: Array, along: float, dirt: bool) -> void:
	var v0 := (along - STEP) / 8.0
	var v1 := along / 8.0
	var gravel := Color(0.52, 0.47, 0.40) if not dirt else Color(0.46, 0.38, 0.28)
	if plain:
		# One band, one colour, and a darker shoulder down each side.
		var band := PLAIN_DIRT if dirt else PLAIN_ROAD
		_quad(verts, uvs, colors, a[1], a[2], b[2], b[1], Vector2(0, v0), Vector2(1, v0), Vector2(1, v1),
			Vector2(0, v1), band)
		for k in [0, 2]:
			_quad(verts, uvs, colors, a[k], a[k + 1], b[k + 1], b[k], Vector2(0, v0), Vector2(0.02, v0),
				Vector2(0.02, v1), Vector2(0, v1), band.darkened(0.18))
		return
	for k in 3:
		var u0 := 0.0
		var u1 := 1.0
		var tint := Color.WHITE
		if k != 1:
			# Verges use the plain corner of the texture, tinted gravel.
			u0 = 0.0
			u1 = 0.02
			tint = gravel
		_quad(verts, uvs, colors, a[k], a[k + 1], b[k + 1], b[k],
			Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), tint)

func _quad(verts: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t0: Vector2, t1: Vector2, t2: Vector2, t3: Vector2, tint: Color) -> void:
	# Wound so the face is up: clockwise seen from above.
	for tri in [[p0, p2, p1, t0, t2, t1], [p0, p3, p2, t0, t3, t2]]:
		var n: Vector3 = ((tri[2] as Vector3) - (tri[0] as Vector3)).cross((tri[1] as Vector3) - (tri[0] as Vector3))
		if n.y < 0.0:
			tri = [tri[0], tri[2], tri[1], tri[3], tri[5], tri[4]]
		for i in 3:
			verts.append(tri[i])
			uvs.append(tri[i + 3])
			colors.append(tint)

func _flush(verts: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, dirt: bool) -> void:
	if verts.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var n := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).normalized()
		normals[i] = n
		normals[i + 1] = n
		normals[i + 2] = n
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = mesh
	mi.material_override = Textures.material("road", 6.0) if plain else material(dirt)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Solid: what you drive and walk on is the road you see, not the ground a
	# hand's width under it.
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "RoadBody"
		_body.collision_layer = Layers.WORLD
		_body.collision_mask = 0
		var pm := PhysicsMaterial.new()
		pm.friction = 1.0
		_body.physics_material_override = pm
		add_child(_body)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	cs.shape = shape
	_body.add_child(cs)

## Asphalt with white edge lines and a dashed yellow centre, or a dirt track
## with two ruts; drawn once and shared.
static func material(dirt: bool) -> StandardMaterial3D:
	var key := "dirt" if dirt else "asphalt"
	if _materials.has(key):
		return _materials[key]
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 if dirt else 17
	for y in h:
		for x in w:
			var grain := rng.randf_range(-0.035, 0.035)
			var c: Color
			if dirt:
				c = Color(0.50, 0.40, 0.28).lightened(grain)
				var u := float(x) / float(w)
				if absf(u - 0.3) < 0.06 or absf(u - 0.7) < 0.06:
					c = c.darkened(0.16)
			else:
				c = Color(0.26, 0.26, 0.27).lightened(grain)
				var u2 := float(x) / float(w)
				if (u2 > 0.05 and u2 < 0.08) or (u2 > 0.92 and u2 < 0.95):
					c = Color(0.9, 0.9, 0.86)
				elif absf(u2 - 0.5) < 0.018 and (y % 128) < 72:
					c = Color(0.95, 0.76, 0.16)
			img.set_pixel(x, y, c)
	# The plain corner the verges sample.
	for y in h:
		for x in 2:
			img.set_pixel(x, y, Color(0.95, 0.95, 0.95).darkened(rng.randf_range(0.0, 0.1)))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = mat
	return mat
