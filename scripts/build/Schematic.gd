class_name Schematic
extends Node3D

## A shape you plan first and pay for in material.
##
## Placing one costs almost nothing: it is a drawing, a translucent block with
## no collision. Touching material to it fills it - the piece is consumed and
## the shape fills by exactly that much volume. The first thing fed to a shape
## decides what it is made of, and after that it will only take more of the
## same. Once it is full it turns solid, takes the colour of whatever filled it,
## and starts colliding like any other structure.
##
## Volume is conserved on the way in and on the way out: a piece too big for the
## room left is trimmed rather than swallowed, and pulling a finished shape down
## hands the material back.

signal filled_changed(schematic: Schematic)
signal completed(schematic: Schematic)

@export var building_id: StringName = &"schematic_block"

var def: BuildingDef
var manager: LooseItemManager
var plot_id: int = 0

## What has gone in so far, and what it was. `material` is empty until the
## first piece arrives and fixed from then on.
var filled_m3: float = 0.0
var material: StringName = &""
var solid: bool = false

var _size: Vector3 = Vector3.ONE
var _body: StaticBody3D
var _shape: CollisionShape3D
var _ghost: MeshInstance3D
var _fill: MeshInstance3D
var _area: Area3D
var _area_shape: CollisionShape3D
var _poll: float = 0.0

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	plot_id = p_plot_id

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	_size = def.footprint_world(Plot.CELL)
	_build()
	set_physics_process(true)

## How much material a shape takes, as a share of its own volume: a wall is
## framed and faced, not cast solid, so it takes a tenth of its bulk.
static var MATERIAL_SHARE: float = Balance.num("build.material_share", 0.1)

## How much material this shape takes to finish.
func capacity_m3() -> float:
	return _size.x * _size.y * _size.z * MATERIAL_SHARE * (0.5 if _wedge() else 1.0)

func _wedge() -> bool:
	return def != null and def.shape == &"wedge"

# --- Doors --------------------------------------------------------------------

## A door plan: filled, it becomes a frame with a door in it - a hinged door
## that swings, or a garage door that swings up overhead - which [E] opens
## and shuts.
func is_door() -> bool:
	return def != null and (def.shape == &"door" or def.shape == &"garage")

var open: bool = false
## How far open, 0 shut to 1 open; the door is posed from it about its hinge.
var swing: float = 0.0
var _hinge: Transform3D
var _panel_rest: Transform3D
var _panel: AnimatableBody3D
var _door_meshes: Array[MeshInstance3D] = []
var _tween: Tween
const PANEL := 0.12
const POST := 0.1

## Opens it if shut, shuts it if open. Returns what to say.
func toggle_door() -> String:
	if not is_door() or not solid:
		return ""
	set_open(not open)
	return "%s %s" % [def.display_name.replace("Plan: ", ""), "open" if open else "shut"]

func set_open(on: bool, snap: bool = false) -> void:
	open = on
	if _panel == null:
		return
	var target := 1.0 if on else 0.0
	if _tween != null:
		_tween.kill()
	# Switched off (a co-op guest's picture of the host's door), it cannot
	# animate: it is simply put where it is.
	if snap or not is_inside_tree() or not can_process():
		_pose_door(target)
		return
	_tween = create_tween()
	_tween.tween_method(_pose_door, swing, target, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## The door `t` of the way open. The body itself is moved (not a parent it
## hangs from), so its collision goes with it.
func _pose_door(t: float) -> void:
	swing = t
	var garage := def.shape == &"garage"
	var turn := Basis(Vector3.RIGHT, -PI * 0.5 * t) if garage else Basis(Vector3.UP, -PI * 0.5 * t)
	_panel.transform = Transform3D(turn, _hinge.origin) * _panel_rest

func _build_door() -> void:
	var garage := def.shape == &"garage"
	var w := _size.x - POST * 2.0
	var h := _size.y - POST
	# The frame: two posts and a head, solid.
	for side in [-1.0, 1.0]:
		_frame_part(Vector3(POST, _size.y, _size.z * 0.5), Vector3(side * (_size.x * 0.5 - POST * 0.5), _size.y * 0.5, 0))
	_frame_part(Vector3(_size.x, POST, _size.z * 0.5), Vector3(0, _size.y - POST * 0.5, 0))
	# The door, on its hinge: down the left post for a door, along the head
	# for a garage door, which swings up and in overhead.
	_hinge = Transform3D(Basis(), Vector3(0, h, 0) if garage else Vector3(-w * 0.5, 0, 0))
	_panel_rest = Transform3D(Basis(), Vector3(0, -h * 0.5, 0) if garage else Vector3(w * 0.5, h * 0.5, 0))
	_panel = AnimatableBody3D.new()
	_panel.collision_layer = Layers.MACHINE
	_panel.collision_mask = Layers.MASK_MACHINE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, PANEL)
	cs.shape = box
	_panel.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, PANEL)
	mi.mesh = bm
	_panel.add_child(mi)
	_door_meshes.append(mi)
	# A handle, or the garage door's ribs.
	var g := Greeble.new()
	if garage:
		for i in 4:
			g.box(Vector3(w * 0.98, 0.04, 0.03), Transform3D(Basis(), Vector3(0, -h * 0.5 + h * (float(i) + 0.5) / 4.0, PANEL * 0.5 + 0.015)), Color(0.2, 0.2, 0.22))
	else:
		for face in [-1.0, 1.0]:
			g.box(Vector3(0.12, 0.04, 0.05), Transform3D(Basis(), Vector3(w * 0.38, 0, face * (PANEL * 0.5 + 0.03))), Color(0.75, 0.7, 0.45))
	_panel.add_child(g.instance("Trim"))
	add_child(_panel)
	for m in _door_meshes:
		_apply_material(m, 1.0)
	set_open(open, true)

func _frame_part(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	add_child(mi)
	_door_meshes.append(mi)

## The shape's outline mesh at `size`: a box, or a ramp high at its front.
func _mesh_for(size: Vector3) -> Mesh:
	if _wedge():
		var p := PrismMesh.new()
		# The triangle is drawn across X and pushed out along Z; turned a
		# quarter (see _mesh_basis) it runs along Z, high at -Z.
		p.size = Vector3(size.z, size.y, size.x)
		p.left_to_right = 1.0
		return p
	var b := BoxMesh.new()
	b.size = size
	return b

func _mesh_basis() -> Basis:
	return Basis(Vector3.UP, PI * 0.5) if _wedge() else Basis()

func _collision_shape(size: Vector3) -> Shape3D:
	if _wedge():
		var h := size * 0.5
		var c := ConvexPolygonShape3D.new()
		c.points = PackedVector3Array([
			Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)])
		return c
	var box := BoxShape3D.new()
	box.size = size
	return box

func remaining_m3() -> float:
	return maxf(0.0, capacity_m3() - filled_m3)

func fill_fraction() -> float:
	return clampf(filled_m3 / maxf(0.0001, capacity_m3()), 0.0, 1.0)

# --- Filling ---------------------------------------------------------------

## Spec: only the material that started the shape can finish it.
func can_accept(item_id: StringName) -> bool:
	if solid or remaining_m3() <= 0.0001:
		return false
	if material != &"" and item_id != material:
		return false
	return GameData.item(item_id) != null

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	if material == &"":
		material = item.item_id
	var room := remaining_m3()
	var supplied := item.volume()
	var taken: float = minf(room, supplied)
	# A piece bigger than the room left is trimmed, not swallowed whole: the
	# offcut comes back rather than disappearing into the wall.
	if supplied - taken > 0.0001:
		_return_offcut(item, supplied - taken)
	manager.despawn(item)
	filled_m3 += taken
	_refresh()
	filled_changed.emit(self)
	if remaining_m3() <= 0.0001:
		_solidify()
	return true

func _return_offcut(item: LooseItem, offcut: float) -> void:
	var dims := item.dims
	var scaled: Dictionary
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		# Keep the round stock round: shorten it to the offcut's volume.
		var ratio: float = offcut / maxf(0.0001, item.volume())
		scaled = Solid.cylinder(float(dims.r0), float(dims.r1), float(dims.length) * ratio)
	else:
		scaled = Solid.cube(offcut)
	var spot := global_position + Vector3(0, _size.y + 0.4, 0)
	var back := manager.spawn(item.item_id, Transform3D(Basis(), spot), plot_id,
		Vector3.UP * 0.4, scaled, item.owned)
	if back != null:
		back.owned = true

## Material dropped against the shape is taken, so a belt or an armful both work.
func _on_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not can_accept(item.item_id):
		return
	if not Trigger.contains_point(_area_shape, item.global_position, 0.3):
		return
	accept_item(item)

func _physics_process(delta: float) -> void:
	if solid:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	for body in Trigger.bodies_inside(_area, _area_shape):
		_on_body(body)

## Full: the drawing becomes a thing.
func _solidify() -> void:
	if solid:
		return
	solid = true
	_ghost.visible = false
	if is_door():
		_fill.visible = false
		_build_door()
	else:
		_shape.disabled = false
		_fill.visible = true
		_apply_material(_fill, 1.0)
	if _area != null:
		_area.queue_free()
		_area = null
	completed.emit(self)

## Taking a shape down gives the material back rather than refunding cash, since
## cash never went into it.
func reclaim() -> float:
	var given := filled_m3
	if manager != null and material != &"" and given > 0.0001:
		var def_out := GameData.item(material)
		# Handed back in pieces small enough to pick up again.
		var piece: float = 0.35 if def_out == null else maxf(0.08, minf(0.35, given))
		var left := given
		var i := 0
		while left > 0.0001 and i < 64:
			var take: float = minf(piece, left)
			var spot := global_position + Vector3(
				randf_range(-0.4, 0.4), _size.y + 0.5 + float(i) * 0.12, randf_range(-0.4, 0.4))
			var back := manager.spawn(material, Transform3D(Basis(), spot), plot_id,
				Vector3.ZERO, Solid.cube(take), true)
			if back == null:
				break
			left -= take
			i += 1
	filled_m3 = 0.0
	material = &""
	return given

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.MACHINE
	_body.collision_mask = Layers.MASK_MACHINE
	_shape = CollisionShape3D.new()
	_shape.shape = _collision_shape(_size)
	_shape.position = Vector3(0, _size.y * 0.5, 0)
	_shape.disabled = true        # a plan does not collide
	_body.add_child(_shape)
	add_child(_body)

	# The outline of what is planned.
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _mesh_for(_size)
	_ghost.transform = Transform3D(_mesh_basis(), Vector3(0, _size.y * 0.5, 0))
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.55, 0.75, 1.0, 0.22)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = gmat
	add_child(_ghost)

	# How full it is, drawn as the material rising inside the outline.
	_fill = MeshInstance3D.new()
	_fill.mesh = _mesh_for(_size)
	_fill.visible = false
	add_child(_fill)

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	_area_shape = CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = _size + Vector3(0.7, 0.7, 0.7)
	_area_shape.shape = ab
	_area_shape.position = Vector3(0, _size.y * 0.5, 0)
	_area.add_child(_area_shape)
	_area.body_entered.connect(_on_body)
	add_child(_area)

func _refresh() -> void:
	var fraction := fill_fraction()
	if fraction <= 0.0001:
		_fill.visible = false
		return
	_fill.visible = true
	var height: float = _size.y * fraction
	_fill.mesh = _mesh_for(Vector3(_size.x, height, _size.z))
	_fill.transform = Transform3D(_mesh_basis(), Vector3(0, height * 0.5, 0))
	_apply_material(_fill, fraction)

func _apply_material(mesh: MeshInstance3D, fraction: float) -> void:
	var def_mat := GameData.item(material)
	var color: Color = def_mat.color if def_mat != null else Color(0.6, 0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if fraction < 1.0:
		# Still a plan being filled, so it reads as loose material inside an
		# outline rather than as a finished wall.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
	mesh.material_override = mat

func status_line() -> String:
	if solid:
		var what := "%s of %s" % [def.display_name.replace("Plan: ", ""), GameData.item_name(material)]
		if is_door():
			return "%s  [E] %s" % [what, "shut" if open else "open"]
		return what
	if material == &"":
		return "%s: empty plan, needs %.2f m3 of anything" % [def.display_name, capacity_m3()]
	return "%s: %.2f / %.2f m3 of %s" % [
		def.display_name, filled_m3, capacity_m3(), GameData.item_name(material)]

func to_dict() -> Dictionary:
	return {"filled_m3": filled_m3, "material": String(material), "open": open}

func from_dict(d: Dictionary) -> void:
	filled_m3 = float(d.get("filled_m3", 0.0))
	material = StringName(d.get("material", ""))
	_refresh()
	if remaining_m3() <= 0.0001 and filled_m3 > 0.0:
		_solidify()
	if is_door() and bool(d.get("open", false)) != open:
		set_open(bool(d.get("open", false)), not solid)
