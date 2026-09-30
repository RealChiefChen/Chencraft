class_name OreRock
extends StaticBody3D

## A chunk of ore sitting part-buried in the ground.
##
## There are two ways to get it out, and they cost different things. Pulling
## takes it whole, but the pull needed is its own weight plus the share of it
## that is still buried - so a big chunk simply will not come, however long you
## heave. Hammering takes time instead of strength: every blow opens a crack
## somewhere random or drives an existing one deeper, and when a crack goes all
## the way through, the piece on the near side of it breaks away and can be
## carried off while the rest stays in the ground.
##
## Either way the ore is conserved: what comes out of the hole adds up to what
## was in it.

signal broken(rock: OreRock)
signal yielded(rock: OreRock, ore_volume: float)

@export var ore_item: StringName = &"ore_iron"
## The most of a chunk that is ever buried.
const MAX_EMBED := 0.95
## How much of the chunk is buried, as a fraction. The pull needed to free it
## is its mass plus this much of its mass again.
@export var embed: float = 0.45

## A chunk of radius r holds about this much ore: it is a lumpy thing, not a
## box, so it does not fill its own bounds.
const SHAPE_FILL := 2.36
## Below this there is no chunk left to work; the remainder comes free whole.
const MIN_CHUNK := 0.06
## Crack depth opened per kilogram of hammer head, before the chunk's size is
## taken into account. A heavier head cracks deeper, a bigger chunk cracks slower.
static var CRACK_GAIN: float = Balance.num("cutting.crack_gain", 0.05)
## Two blows closer together than this along the chunk work the same crack.
const CRACK_SPREAD := 0.18
## The least of the chunk a single fracture can take off.
const MIN_SPLIT := 0.12

var volume: float = 1.0
## Open cracks: {t: where along the chunk, 0..1; depth: how far through, 0..1}.
var cracks: Array[Dictionary] = []
var plot_id: int = 0
var manager: LooseItemManager

var _parts: Array[MeshInstance3D] = []
var _crack_meshes: Array[MeshInstance3D] = []
var _shape: CollisionShape3D
var _consumed: bool = false
## Set by the first blow or heave. A field only retires chunks nobody has worked.
var touched: bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	collision_layer = Layers.TREE      # shares the "resource node" layer
	collision_mask = Layers.WORLD
	if _rng.seed == 0:
		_rng.seed = hash(name) + int(position.x * 13.0) + int(position.z * 29.0)
	_rebuild()

func seed_form(value: int) -> void:
	_rng.seed = value

## Sets the chunk's size by the ore in it. The visible rock follows from this,
## never the other way round.
func set_volume(value: float) -> void:
	volume = maxf(MIN_CHUNK, value)
	if is_inside_tree():
		_rebuild()

## Half-width of the chunk, derived from how much ore is left in it.
func radius() -> float:
	return pow(maxf(0.0001, volume / SHAPE_FILL), 1.0 / 3.0)

func density() -> float:
	var def := GameData.item(ore_item)
	return def.density if def != null else 900.0

func mass() -> float:
	return density() * volume

## Spec: the pull to disgorge a chunk is its mass plus the buried fraction of
## its mass again.
func pull_required() -> float:
	return mass() * (1.0 + embed)

func untouched() -> bool:
	return not _consumed and not touched

func consumed() -> bool:
	return _consumed

## How close the worst crack is to going through, 0..1. Drives the aim prompt.
func worst_crack() -> float:
	var worst := 0.0
	for c in cracks:
		worst = maxf(worst, float(c.depth))
	return worst

# --- Working the chunk -----------------------------------------------------

## One blow of a hammer. Opens a crack at a random spot, or drives a nearby one
## deeper, and fractures the chunk when a crack goes all the way through.
func strike(head_kg: float) -> String:
	if _consumed:
		return ""
	touched = true
	var t := _rng.randf()
	var index := _crack_near(t)
	if index < 0:
		cracks.append({"t": t, "depth": 0.0})
		index = cracks.size() - 1
	# Depth won per blow falls off with the chunk's cross-section, so the same
	# hammer that shatters a boulder-chip barely marks a boulder.
	var gain: float = head_kg * CRACK_GAIN / pow(maxf(0.05, volume), 2.0 / 3.0)
	cracks[index]["depth"] = float(cracks[index].depth) + gain
	_nudge()
	if float(cracks[index].depth) < 1.0:
		_refresh_cracks()
		return "crack deepens (%d%%)" % int(float(cracks[index].depth) * 100.0)
	return _fracture(index)

func _crack_near(t: float) -> int:
	for i in cracks.size():
		if absf(float(cracks[i].t) - t) <= CRACK_SPREAD:
			return i
	return -1

## A crack has gone through: the piece on its near side breaks away.
func _fracture(index: int) -> String:
	var t: float = cracks[index].t
	# The crack splits the chunk where it fell; the smaller side is what comes
	# off, so hammering peels a chunk down rather than halving it forever.
	var share: float = clampf(minf(t, 1.0 - t), MIN_SPLIT, 0.5)
	var piece: float = volume * share
	cracks.remove_at(index)
	_drop_ore(piece, Vector3.UP * 1.2)
	volume -= piece
	# What is left sits deeper in its hole than what came off it.
	embed = clampf(embed + 0.06, 0.0, MAX_EMBED)
	if volume <= MIN_CHUNK:
		var last := volume
		_drop_ore(last, Vector3.UP * 1.0)
		_consume()
		return "chunk broken up"
	_rebuild()
	yielded.emit(self, piece)
	return "%.2f m3 breaks off" % piece

## Tries to haul the whole chunk out of the ground. Returns the freed ore, or
## null when the pull is not enough.
func try_free(pull_kg: float) -> LooseItem:
	if _consumed:
		return null
	touched = true
	if pull_kg < pull_required():
		return null
	var freed := _drop_ore(volume, Vector3.UP * 0.6)
	_consume()
	return freed

## Breaks the whole chunk up at once. Not a player action: this is how tests and
## the smoke run empty a chunk without simulating a hundred hammer blows.
func shatter() -> int:
	var pieces := 0
	var guard := 0
	while not _consumed and guard < 200:
		guard += 1
		if strike(10000.0) != "":
			pieces += 1
	return pieces

func _drop_ore(piece_volume: float, impulse: Vector3) -> LooseItem:
	if manager == null or piece_volume <= 0.0:
		return null
	var top := global_position + Vector3(0, showing() + 0.35, 0)
	var spot := top + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
	var item := manager.spawn(ore_item, Transform3D(Basis(), spot), plot_id, impulse,
		Solid.chunk(piece_volume))
	yielded.emit(self, piece_volume)
	return item

func _consume() -> void:
	_consumed = true
	_shape.disabled = true
	for p in _parts:
		p.visible = false
	for c in _crack_meshes:
		c.visible = false
	collision_layer = 0
	Sfx.play(&"crack", global_position)
	broken.emit(self)

# --- Geometry --------------------------------------------------------------

## The chunk is drawn from the ore left in it, so hammering a piece off visibly
## shrinks the rock in the ground.
## Ores that catch the light, and the rock each tends to sit in, so a sunstone
## in sandstone and cobalt in dark slate read differently from across a valley.
const GLOWING_ORES := [&"ore_gold", &"ore_cobalt", &"ore_sunstone", &"ore_bismuth",
	&"ore_platinum", &"ore_starmetal"]
## Stones whose crystals flash many colours rather than one.
const PLAY_OF_COLOUR := {
	&"gem_black_opal": [Color(0.15, 0.95, 0.45), Color(0.2, 0.55, 1.0), Color(1.0, 0.5, 0.1),
		Color(1.0, 0.3, 0.7), Color(0.2, 0.95, 0.95), Color(0.75, 0.3, 1.0)],
}
## How each ore shows in its rock: 0 bands wrapped round it, 1 nuggets
## clustered on it, 2 spikes of crystal - spread so neighbours differ.
const VEIN_STYLE := {
	&"ore_iron": 0, &"ore_tin": 0, &"ore_silver": 0, &"ore_magnetite": 0, &"ore_tungsten": 0,
	&"ore_copper": 1, &"ore_gold": 1, &"ore_nickel": 1, &"ore_platinum": 1, &"ore_zinc": 1,
	&"ore_cobalt": 2, &"ore_bismuth": 2, &"ore_sunstone": 2, &"ore_starmetal": 2,
}
const HOST_STONE := {
	&"ore_copper": Color(0.55, 0.46, 0.38), &"ore_silver": Color(0.56, 0.58, 0.62),
	&"ore_cobalt": Color(0.28, 0.30, 0.34), &"ore_sunstone": Color(0.78, 0.64, 0.44),
	&"ore_gold": Color(0.50, 0.47, 0.43), &"ore_tin": Color(0.55, 0.52, 0.47),
	&"ore_zinc": Color(0.45, 0.47, 0.44), &"ore_magnetite": Color(0.36, 0.34, 0.33),
	&"ore_nickel": Color(0.42, 0.44, 0.38), &"ore_bismuth": Color(0.60, 0.58, 0.56),
	&"ore_tungsten": Color(0.50, 0.44, 0.38), &"ore_platinum": Color(0.40, 0.40, 0.44),
	&"ore_starmetal": Color(0.12, 0.11, 0.14),
	&"gem_quartz": Color(0.62, 0.60, 0.56), &"gem_jade": Color(0.46, 0.50, 0.44),
	&"gem_amethyst": Color(0.44, 0.40, 0.42), &"gem_obsidian": Color(0.30, 0.22, 0.20),
	&"gem_emerald": Color(0.40, 0.42, 0.40), &"gem_ruby": Color(0.52, 0.46, 0.44),
	&"gem_diamond": Color(0.20, 0.20, 0.24), &"gem_sapphire": Color(0.62, 0.70, 0.78),
	&"gem_turquoise": Color(0.56, 0.44, 0.34), &"gem_black_opal": Color(0.14, 0.13, 0.15),
	&"gem_lapis": Color(0.70, 0.68, 0.64),
}

## An ore chunk is a rectangular block of its host rock, longer one way than
## the others; a gem is a dodecahedron. Both sit `embed` of their height in
## the ground.
const BLOCK := Vector3(2.0, 1.3, 1.5)

func _is_gem() -> bool:
	var def := GameData.item(ore_item)
	return def != null and def.category == &"gem"

## How tall the chunk stands, bottom to top, before any of it is buried.
func _height() -> float:
	return radius() * (1.9 if _is_gem() else BLOCK.y)

## The chunk's middle, relative to the ground it is bedded in.
func _centre() -> Vector3:
	return Vector3(0, _height() * (0.5 - embed), 0)

## How far the chunk stands out of the ground.
func showing() -> float:
	return _height() * (1.0 - embed)

## Bright, clean ore colours, so a seam reads from across a valley.
func _vivid(c: Color) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * 1.35 + 0.1, 0.0, 1.0), clampf(c.v * 1.15 + 0.12, 0.0, 1.0))

func _rebuild() -> void:
	for p in _parts:
		p.queue_free()
	_parts.clear()
	var r := radius()
	var ore_def := GameData.item(ore_item)
	var plain := ore_def != null and ore_def.category == &"stone"
	var stone: Color = HOST_STONE.get(ore_item, ore_def.color if plain else Color(0.47, 0.45, 0.42))
	# Each ore and stone has its own deep colour (items.json), used as it is.
	var seam: Color = ore_def.color if ore_def != null else Color(0.5, 0.5, 0.5)
	# The rock takes a stain of what is in it.
	# Ore rock is stained deep with what is in it, and the seams through it
	# are the colour at full strength: each ore reads from across a valley.
	stone = stone if plain else stone.darkened(0.2).lerp(seam.darkened(0.45), 0.65)
	var gem := _is_gem()
	var glint := GLOWING_ORES.has(ore_item) or gem
	var centre := _centre()
	var form := RandomNumberGenerator.new()
	form.seed = _rng.seed                 # same rock, same lumps, as it shrinks
	var yaw := Basis(Vector3.UP, form.randf() * PI)

	if _shape == null:
		_shape = CollisionShape3D.new()
		add_child(_shape)
	var g := Greeble.new()
	if gem:
		# A gem: a big dodecahedron of the stone itself, cloudy in its matrix,
		# with smaller bright ones breaking out of it.
		var R := r * 0.95
		var hull := ConvexPolygonShape3D.new()
		var pts := Greeble.dodecahedron_points()
		for i in pts.size():
			pts[i] = yaw * pts[i] * R
		hull.points = pts
		_shape.shape = hull
		_shape.transform = Transform3D(Basis(), centre)
		var play: Array = PLAY_OF_COLOUR.get(ore_item, [])
		# Black opal is black, with the play of colour breaking out of it.
		g.dodecahedron(R, Transform3D(yaw, centre), ore_def.color if not play.is_empty() else seam.darkened(0.4))
		for i in 6:
			var dir := Vector3(form.randf_range(-1, 1), form.randf_range(0.1, 1.0), form.randf_range(-1, 1)).normalized()
			var size := R * form.randf_range(0.28, 0.45)
			g.dodecahedron(size, Transform3D(Basis(dir, form.randf() * TAU), centre + dir * R * 0.85),
				(play[i % play.size()] as Color) if not play.is_empty() else seam.lightened(form.randf_range(0.0, 0.15)), true)
	else:
		var size := BLOCK * r
		size.x *= form.randf_range(0.9, 1.1)
		size.z *= form.randf_range(0.9, 1.1)
		var box := BoxShape3D.new()
		box.size = size
		_shape.shape = box
		_shape.transform = Transform3D(yaw, centre)
		var body := Transform3D(yaw, centre)
		# An ore with a look of its own (OreLook) is that rock, built to fill
		# the block exactly: cubes of stone with the ore standing out of them.
		if OreLook.has_look(ore_item):
			for part in OreLook.rock(ore_item, size, centre, yaw.get_euler().y, _rng.seed):
				part.visibility_range_end = 260.0
				add_child(part)
				_parts.append(part)
			_refresh_cracks()
			return
		g.box(size, body, stone)
		# Building stone is all one rock: laid down in beds, lighter and
		# darker, and nothing else in it.
		var style := 3 if plain else int(VEIN_STYLE.get(ore_item, absi(hash(String(ore_item))) % 3))
		# Each ore has its own look: bands of metal wrapped round the block,
		# nuggets clustered on it, or spikes of crystal - picked by the ore.
		match style:
			3:
				for k in 3:
					var y := (float(k) - 1.0) * size.y * 0.3
					g.box(Vector3(size.x * 1.02, size.y * 0.1, size.z * 1.02),
						body * Transform3D(Basis(), Vector3(0, y, 0)),
						stone.lightened(0.15) if k % 2 == 0 else stone.darkened(0.15))
			0:
				for k in 3:
					var at := (float(k) - 1.0) * size.x * 0.3 + form.randf_range(-0.05, 0.05) * size.x
					g.box(Vector3(size.x * 0.16, size.y * 1.04, size.z * 1.04),
						body * Transform3D(Basis(Vector3.FORWARD, form.randf_range(-0.25, 0.25)), Vector3(at, 0, 0)), seam, glint)
			1:
				for k in 9:
					var face := Vector3(form.randf_range(-0.5, 0.5) * size.x, size.y * 0.5, form.randf_range(-0.5, 0.5) * size.z)
					if k % 3 == 1:
						face = Vector3(size.x * 0.5 * (1.0 if form.randf() < 0.5 else -1.0), form.randf_range(-0.3, 0.45) * size.y, form.randf_range(-0.4, 0.4) * size.z)
					var nug := r * form.randf_range(0.26, 0.42)
					g.box(Vector3(nug, nug * 0.8, nug), body * Transform3D(Basis(Vector3.UP, form.randf() * PI), face), seam, glint)
			_:
				for k in 9:
					var out := Vector3(form.randf_range(-0.45, 0.45) * size.x, size.y * 0.5, form.randf_range(-0.45, 0.45) * size.z)
					var tilt := Basis(Vector3(form.randf_range(-1, 1), 0, form.randf_range(-1, 1)).normalized(), form.randf_range(0.0, 0.5))
					g.prism(4, r * form.randf_range(0.13, 0.2), 0.0, r * form.randf_range(0.55, 0.9),
						body * Transform3D(tilt, out - Vector3(0, r * 0.05, 0)), seam, glint)
		# A lighter cap of weathered rock where it stands out of the ground.
		g.box(Vector3(size.x * 0.7, size.y * 0.06, size.z * 0.7),
			body * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), stone.lightened(0.1))
	var mi := g.instance("Rock")
	add_child(mi)
	_parts.append(mi)
	_refresh_cracks()

## Cracks are drawn as dark seams that lengthen as they deepen, so a chunk that
## is nearly through looks it.
func _refresh_cracks() -> void:
	for c in _crack_meshes:
		c.queue_free()
	_crack_meshes.clear()
	var r := radius()
	var centre := _centre()
	for crack in cracks:
		var depth: float = clampf(float(crack.depth), 0.0, 1.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 0.06, r * 1.45 * depth, r * 2.0 * depth)
		mi.mesh = bm
		mi.position = centre + Vector3((float(crack.t) - 0.5) * r * 1.6, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.06, 0.06, 0.07)
		mat.roughness = 1.0
		mi.material_override = mat
		add_child(mi)
		_crack_meshes.append(mi)

func _nudge() -> void:
	if _parts.is_empty() or not is_instance_valid(_parts[0]):
		return
	_parts[0].scale = Vector3(1.04, 0.97, 1.04)
	create_tween().tween_property(_parts[0], "scale", Vector3.ONE, 0.1)

func status_line() -> String:
	return "%s chunk  %.2f m3  %.0f kg  needs %.0f kg of pull" % [
		GameData.item_name(ore_item), volume, mass(), pull_required()]

# --- Co-op ---------------------------------------------------------------------------

## What a guest needs to draw this chunk as it is now.
func net_state() -> Dictionary:
	var cs: Array = []
	for c in cracks:
		cs.append([float(c.t), float(c.depth)])
	return {"v": volume, "e": embed, "c": cs}

func net_apply(state: Dictionary) -> void:
	embed = float(state.get("e", embed))
	cracks.clear()
	for c in state.get("c", []):
		cracks.append({"t": float(c[0]), "depth": float(c[1])})
	var v := float(state.get("v", volume))
	if not is_equal_approx(v, volume):
		set_volume(v)
	elif is_inside_tree():
		_refresh_cracks()
