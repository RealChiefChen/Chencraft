class_name BuildSystem
extends Node3D

## Build mode: a grid-snapped ghost that follows the player's aim, with
## placement validity resolved by the plot itself.

signal mode_changed(active: bool)
signal selection_changed(def: BuildingDef)
## The build menu opened or closed.
signal menu_toggled(open: bool)

var plot: Plot
var camera: Camera3D
var player: Node3D

var active: bool = false
## Quarter turns about each axis. Spec binds Z, X and C to the three of them.
var rot: Vector3i = Vector3i.ZERO
var yaw: int = 0
## Which palette entry is in hand; -1 for nothing. Build mode opens with an
## empty hand: you choose from the menu (or copy a building you aim at).
var index: int = -1
var palette: Array[BuildingDef] = []
## A building copied off the plot with the pick key: its exact size and tier,
## which may not be a palette entry (a stretched belt, say).
var _picked: BuildingDef = null
## The build menu is open: the mouse is the menu's.
var menu_open: bool = false
var last_error: String = ""
var target_cell: Vector2i = Vector2i.ZERO
var has_target: bool = false

const REACH := 40.0
## Spec: build mode is a freecam. These are how fast it flies.
const FLY_SPEED := 14.0
const FLY_SPRINT := 32.0

var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
## Where the camera was before build mode took it, so leaving puts it back.
var _ghost_label: Label3D
## The building itself, see-through, where it would go and turned the way it
## would face; rebuilt when the choice (or its size or tier) changes.
var _preview: Node3D
var _preview_key: String = ""
var _preview_ok: StandardMaterial3D
var _preview_bad: StandardMaterial3D
var _preview_valid: bool = true
var _stowed: Transform3D
var _flying: bool = false

## Editing a placed building: which one (index into plot.placed, -1 for
## none), what the handles do, and the drag under way.
var selected: int = -1
var edit_mode: BuildGizmo.Mode = BuildGizmo.Mode.MOVE
var edit_error: String = ""
var _gizmo: BuildGizmo
var _drag: Dictionary = {}
## Where a handle drag has got to on screen: it starts at the crosshair and
## follows the mouse from there.
var _cursor: Vector2 = Vector2.ZERO

func setup(p_plot: Plot, p_camera: Camera3D, p_player: Node3D) -> void:
	plot = p_plot
	camera = p_camera
	player = p_player
	refresh_palette()
	# Building the last copy of something, or taking one down, changes what
	# there is to build.
	PlayerState.inventory_changed.connect(refresh_palette)

func _ready() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	_preview_ok = _preview_material(Color(0.85, 1.0, 0.85, 0.62))
	_preview_bad = _preview_material(Color(1.0, 0.45, 0.4, 0.62))
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	add_child(_ghost)
	_gizmo = BuildGizmo.new()
	_gizmo.top_level = true
	add_child(_gizmo)
	set_process(true)

func refresh_palette() -> void:
	var was := current() if _picked == null else null
	palette = PlayerState.available_buildings()
	if index >= palette.size():
		index = palette.size() - 1
	# Stay on the same thing if it is still there.
	if was != null:
		index = -1
		for i in palette.size():
			if palette[i].id == was.id and palette[i].tier == was.tier:
				index = i
				break
	selection_changed.emit(current())

static func _preview_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m

## Swaps the see-through model for `def`'s, if it is not already showing.
func _ensure_preview(def: BuildingDef) -> void:
	var key := "%s|%s|%d" % [def.id, def.size, def.tier]
	if key == _preview_key and _preview != null:
		return
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_preview_key = key
	_preview = plot.preview_model(def)
	if _preview == null:
		return
	_preview.top_level = true
	# Which way is its front: an arrow on the floor out of its -Z side, the
	# way belts run and machines take things in and put them out.
	var fp := Vector3(def.size) * Plot.CELL
	var arrow := MeshInstance3D.new()
	var g := Greeble.new()
	var ahead := -fp.z * 0.5 - 0.35
	g.box(Vector3(0.12, 0.03, 0.5), Transform3D(Basis(), Vector3(0, 0.03, ahead + 0.1)), Color(1.0, 0.85, 0.3))
	for side in [-1.0, 1.0]:
		g.box(Vector3(0.1, 0.03, 0.34), Transform3D(Basis(Vector3.UP, side * 0.6), Vector3(side * 0.09, 0.03, ahead - 0.12)), Color(1.0, 0.85, 0.3))
	arrow.mesh = g.commit()
	arrow.name = "FrontArrow"
	_preview.add_child(arrow)
	add_child(_preview)
	_preview_valid = not _preview_valid
	_tint_preview(not _preview_valid)

func _hide_ghost() -> void:
	_ghost.visible = false
	if _preview != null:
		_preview.visible = false

func _tint_preview(valid: bool) -> void:
	if _preview == null or valid == _preview_valid:
		return
	_preview_valid = valid
	for c in _preview.get_children():
		var mi := c as MeshInstance3D
		if mi != null:
			mi.material_override = _preview_ok if valid else _preview_bad

## What is in hand to build, or null for nothing.
func current() -> BuildingDef:
	if _picked != null:
		return _picked
	if palette.is_empty() or index < 0:
		return null
	return palette[clampi(index, 0, palette.size() - 1)]

## Empty-handed again.
func clear_choice() -> void:
	index = -1
	_picked = null
	selection_changed.emit(null)

## Takes `def` in hand - a palette entry, or a copy of something placed.
## It comes upright, facing the way the last one did: a tip onto its side is
## for the building it was given to, not everything after it.
func choose(def: BuildingDef) -> void:
	_picked = null
	index = -1
	rot = Vector3i(0, rot.y, 0)
	if def == null:
		selection_changed.emit(null)
		return
	for i in palette.size():
		if palette[i] == def or (palette[i].id == def.id and palette[i].tier == def.tier and palette[i].size == def.size):
			index = i
			break
	if index < 0:
		_picked = def
	selection_changed.emit(current())

## The build menu: open it, or close it again.
func toggle_menu() -> void:
	set_menu(not menu_open)

func set_menu(open: bool) -> void:
	if open == menu_open or (open and not active):
		return
	menu_open = open
	menu_toggled.emit(open)

## Copies the building under the crosshair into your hand: the same thing, at
## the same size and tier, turned the same way. Returns what happened.
func pick_block() -> String:
	if not active:
		return ""
	var hit := _aim_hit()
	var i := plot.index_at_hit(hit) if not hit.is_empty() else -1
	if i < 0:
		var point: Variant = _aim_point()
		if point != null:
			i = plot.index_at_world(point)
	if i < 0:
		return "aim at a building to copy it"
	var rec: Dictionary = plot.placed[i]
	choose(rec.def)
	rot = rec.rot
	yaw = rot.y
	var def: BuildingDef = rec.def
	return "copied: %s  (%s)" % [def.display_name, PlayerState.build_note(def)]

func set_active(value: bool) -> void:
	if active == value:
		return
	if value:
		last_error = can_start()
		if last_error != "":
			return
	active = value
	_ghost.visible = value
	if not value and _preview != null:
		_preview.visible = false
	if plot != null:
		plot.show_grid(value)
	if value:
		refresh_palette()
		clear_choice()
		_enter_freecam()
	else:
		set_menu(false)
		deselect()
		_leave_freecam()
	mode_changed.emit(active)

## Spec: build mode puts the player into a freecam - WASD and the mouse fly it,
## Shift and Control work elevation.
func _enter_freecam() -> void:
	if camera == null or _flying:
		return
	_stowed = camera.transform
	# Detached from the player, so flying the camera does not walk the body.
	var start := camera.global_transform
	camera.top_level = true
	# Up a few metres and tipped down at the ground, so the first thing you see
	# is where the building will go rather than the horizon.
	var e := start.basis.get_euler()
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(minf(e.x, deg_to_rad(-32.0)), e.y, 0.0)),
		start.origin + Vector3(0, 5.0, 0))
	_flying = true

func _leave_freecam() -> void:
	if camera == null or not _flying:
		return
	camera.top_level = false
	camera.transform = _stowed
	_flying = false

func _fly(delta: float) -> void:
	if not _flying:
		return
	var input := Vector3(
		Input.get_axis("move_left", "move_right"), 0.0,
		Input.get_axis("move_forward", "move_back"))
	var lift := 0.0
	if Input.is_action_pressed("sprint"):
		lift += 1.0
	if Input.is_action_pressed("lower"):
		lift -= 1.0
	var speed: float = FLY_SPRINT if Input.is_action_pressed("sprint") and lift <= 0.0 else FLY_SPEED
	var basis := camera.global_transform.basis
	var move := (basis * input) + Vector3.UP * lift
	if move.length_squared() > 0.0001:
		camera.global_position += move.normalized() * speed * delta

func toggle() -> void:
	set_active(not active)

## Build mode only opens on your own land. Returns why not, or "".
func can_start() -> String:
	if plot == null or player == null:
		return ""
	if not plot.contains_world(player.global_position, 1.0):
		return "you can only build on your own land - head back to your plot"
	return ""

func cycle(step: int) -> void:
	if palette.is_empty():
		return
	_picked = null
	if index < 0:
		index = 0 if step > 0 else palette.size() - 1
	else:
		index = wrapi(index + step, 0, palette.size())
	selection_changed.emit(current())

func select_index(i: int) -> void:
	if i < 0 or i >= palette.size():
		return
	_picked = null
	index = i
	selection_changed.emit(current())

## The build bar shows the palette a page at a time, so the number keys keep
## meaning the same slots while you scroll within a page.
const BAR_SLOTS := 7

func bar_first() -> int:
	return (maxi(0, index) / BAR_SLOTS) * BAR_SLOTS

## Number key 1-7: a slot on the page the selection is on.
func select_slot(slot: int) -> void:
	if slot >= 0 and slot < BAR_SLOTS:
		select_index(bar_first() + slot)

## Spec: Z, X and C each control an axis of rotation.
func rotate_axis(axis: int, step: int = 1) -> void:
	match axis:
		0: rot.x = wrapi(rot.x + step, 0, 4)
		1: rot.y = wrapi(rot.y + step, 0, 4)
		_: rot.z = wrapi(rot.z + step, 0, 4)
	yaw = rot.y

func rotate_ghost() -> void:
	rotate_axis(1)

func _process(delta: float) -> void:
	if not active or camera == null or plot == null:
		return
	_fly(delta)
	if editing():
		_hide_ghost()
		if selected >= plot.placed.size():
			deselect()
		elif _drag.is_empty():
			_gizmo.hover(_gizmo.pick(camera, _centre()))
		else:
			_drag_to(_centre())
		return
	_update_ghost()

# --- Editing placed buildings ----------------------------------------------

func editing() -> bool:
	return active and selected >= 0

## Spec: F picks the building under the crosshair for editing; F again lets
## it go. While editing, the crosshair picks a handle and the camera still
## flies and looks about as usual.
func toggle_select(add: bool = false) -> void:
	if add and editing():
		# [G]: the building under the crosshair joins the selection (or
		# leaves it), and moves and goes with it. With nothing selected it
		# starts the selection, as [F] does.
		var at := _aimed_index()
		if at >= 0 and at != selected:
			var node: Node3D = plot.placed[at].node
			if multi.has(node):
				multi.erase(node)
			else:
				multi.append(node)
			_refresh_multi()
		return
	if editing():
		deselect()
		return
	var hit := _aim_hit()
	if not hit.is_empty():
		select_building(plot.index_at_hit(hit))
		return
	var point: Variant = _aim_point()
	if point == null:
		return
	select_building(plot.index_at_world(point))

## The other buildings selected along with the one the handles are on.
var multi: Array[Node3D] = []
var _multi_boxes: Array[MeshInstance3D] = []

func _aimed_index() -> int:
	var hit := _aim_hit()
	if not hit.is_empty():
		return plot.index_at_hit(hit)
	var point: Variant = _aim_point()
	return plot.index_at_world(point) if point != null else -1

func selection_count() -> int:
	return (1 + multi.size()) if editing() else 0

func _index_of(node: Node) -> int:
	for i in plot.placed.size():
		if plot.placed[i].node == node:
			return i
	return -1

## A faint box round each of the extra buildings in the selection.
func _refresh_multi() -> void:
	for i in range(multi.size() - 1, -1, -1):
		if not is_instance_valid(multi[i]) or _index_of(multi[i]) < 0:
			multi.remove_at(i)
	while _multi_boxes.size() < multi.size():
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.3, 0.8, 1.0, 0.18)
		m.no_depth_test = true
		mi.material_override = m
		mi.top_level = true
		add_child(mi)
		_multi_boxes.append(mi)
	for i in _multi_boxes.size():
		var box := _multi_boxes[i]
		box.visible = i < multi.size()
		if box.visible:
			var b := _record_box(plot.placed[_index_of(multi[i])])
			(box.mesh as BoxMesh).size = (b[1] as Vector3) * 2.0 + Vector3(0.1, 0.1, 0.1)
			box.global_position = b[0]

func select_building(index: int) -> void:
	if index < 0 or index >= plot.placed.size():
		deselect()
		return
	selected = index
	edit_error = ""
	_refresh_gizmo()

func deselect() -> void:
	selected = -1
	multi.clear()
	_refresh_multi()
	_drag = {}
	_gizmo.hide_all()
	if active and player != null and player.has_method("capture_mouse"):
		player.call("capture_mouse", true)

func set_edit_mode(mode: int) -> void:
	edit_mode = mode as BuildGizmo.Mode
	_refresh_gizmo()

func selected_record() -> Dictionary:
	return plot.placed[selected] if editing() else {}

## The world box a record occupies.
func _record_box(rec: Dictionary) -> Array:
	var def: BuildingDef = rec.def
	var size := Plot.oriented_extent(def.extent(), rec.rot)
	var base := plot.cell_to_world(rec.cell, def.size, rec.rot, def.trim)
	return [base + Vector3(0, size.y * 0.5 + float(rec.get("lift", 0.0)), 0), size * 0.5]

func _refresh_gizmo() -> void:
	if not editing():
		_gizmo.hide_all()
		return
	var box := _record_box(selected_record())
	var mode := edit_mode
	if mode == BuildGizmo.Mode.SCALE and Plot.size_limits(selected_record().def).is_empty():
		edit_error = "%s has a fixed size" % (selected_record().def as BuildingDef).display_name
	_gizmo.show_on(box[0], box[1], mode)

## Mouse input while editing. Returns true when it was used. The mouse stays
## captured and always looks about: the crosshair picks a handle, and while
## one is held it follows the crosshair, the camera turning with it.
func edit_input(event: InputEvent) -> bool:
	if not editing():
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.is_action(&"secondary"):
			return true
		if mb.is_action(&"primary"):
			if mb.pressed:
				_cursor = _centre()
				_press(_cursor)
			else:
				_drag = {}
				_refresh_gizmo()
			return true
		return false
	# The mouse keeps looking about through a drag: the crosshair is the hand,
	# and the handle follows it (see _process).
	return false

## The crosshair, in screen space.
func _centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5

func _ray(mouse: Vector2) -> Array:
	return [camera.project_ray_origin(mouse), camera.project_ray_normal(mouse)]

func _press(mouse: Vector2) -> void:
	var handle := _gizmo.pick(camera, mouse)
	if handle >= 0:
		var rec := selected_record()
		var ray := _ray(mouse)
		var h: Dictionary = _gizmo.handles[handle]
		var axis: Vector3 = BuildGizmo.AXES[h.axis]
		_drag = {"handle": h, "cell": rec.cell, "rot": rec.rot, "size": (rec.def as BuildingDef).size,
			"trim": (rec.def as BuildingDef).trim,
			"lift": float(rec.get("lift", 0.0)), "centre": _gizmo.centre,
			"t0": BuildGizmo.along_axis(h.point, axis, ray[0], ray[1]), "steps": 0,
			"others": _others_start()}
		return
	# Clicked off the handles: pick another building, or let go.
	var ray2 := _ray(mouse)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ray2[0], ray2[0] + ray2[1] * REACH, Layers.WORLD | Layers.MACHINE)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		deselect()
		return
	var index := plot.index_at_hit(hit)
	if index < 0:
		deselect()
	else:
		select_building(index)

## Where each of the other selected buildings started, for a group move.
func _others_start() -> Array:
	var out: Array = []
	for node in multi:
		var i := _index_of(node)
		if i >= 0:
			var rec: Dictionary = plot.placed[i]
			out.append({"node": node, "cell": rec.cell, "lift": float(rec.get("lift", 0.0))})
	return out

## Moves the rest of the selection by the same amount as the one dragged,
## those furthest along the move first, so none is blocked by another still
## to go.
func _move_others(dcell: Vector2i, dlift: float) -> void:
	var others: Array = _drag.get("others", [])
	var dir := Vector2(dcell)
	others.sort_custom(func(a, b): return Vector2(a.cell).dot(dir) > Vector2(b.cell).dot(dir))
	for o in others:
		var i := _index_of(o.node)
		if i < 0:
			continue
		var rec: Dictionary = plot.placed[i]
		var to_cell: Vector2i = (o.cell as Vector2i) + dcell
		var to_lift: float = maxf(0.0, float(o.lift) + dlift)
		if rec.cell == to_cell and is_equal_approx(float(rec.get("lift", 0.0)), to_lift):
			continue
		var def: BuildingDef = rec.def
		if _guest():
			_ask_host({"op": "edit", "id": _net_id(rec.node), "cell": [to_cell.x, to_cell.y],
				"rot": [rec.rot.x, rec.rot.y, rec.rot.z], "size": [def.size.x, def.size.y, def.size.z],
				"lift": to_lift, "trim": [def.trim.x, def.trim.y, def.trim.z]})
			continue
		var was: Node3D = o.node
		var err := plot.edit(i, to_cell, rec.rot, def.size, to_lift, def.trim)
		if err != "":
			edit_error = err
		# An edit can rebuild the building: follow it to its new node.
		var now: Node3D = plot.placed[i].node
		if now != was:
			o.node = now
			var at := multi.find(was)
			if at >= 0:
				multi[at] = now
	_refresh_multi()

## Turns a drag into whole steps and applies each new step as it is reached.
func _drag_to(mouse: Vector2) -> void:
	var d := _drag
	var h: Dictionary = d.handle
	var axis_i: int = h.axis
	var axis: Vector3 = BuildGizmo.AXES[axis_i]
	var ray := _ray(mouse)
	var steps := 0
	var cell: Vector2i = d.cell
	var rot: Vector3i = d.rot
	var size: Vector3i = d.size
	var trim: Vector3i = d.trim
	var lift: float = d.lift
	match edit_mode:
		BuildGizmo.Mode.MOVE:
			var moved: float = BuildGizmo.along_axis(h.point, axis, ray[0], ray[1]) - float(d.t0)
			if axis_i == 1:
				lift = maxf(0.0, snappedf(lift + moved, Plot.SNAP))
				steps = int(round(lift / Plot.SNAP))
			else:
				steps = int(round(moved / Plot.SNAP))
				cell += Vector2i(steps, 0) if axis_i == 0 else Vector2i(0, steps)
		BuildGizmo.Mode.SCALE:
			var limits := Plot.size_limits(selected_record().def)
			if limits.is_empty():
				return
			var grow: float = (BuildGizmo.along_axis(h.point, axis, ray[0], ray[1]) - float(d.t0)) * float(h.sign)
			# Plans and belts size to the fine grid; the rest in whole metres.
			var fine := Plot.fine_scalable(selected_record().def)
			var unit := Plot.SNAP if fine else Plot.CELL
			var pull := int(round(grow / unit)) * (1 if fine else Plot.SUB)
			# Which of the building's own axes lies along this world axis.
			var perm := Plot.oriented_size(Vector3i(0, 1, 2) + Vector3i.ONE, rot) - Vector3i.ONE
			var own: int = perm[axis_i]
			var was_steps := size[own] * Plot.SUB - trim[own]
			# Fine pieces go down to a single fine step: a wall a hand thick.
			var least := 1 if fine else (limits[0] as Vector3i)[own] * Plot.SUB
			var now_steps := clampi(was_steps + pull, least, (limits[1] as Vector3i)[own] * Plot.SUB)
			steps = now_steps - was_steps
			var new_size := size
			var new_trim := trim
			new_size[own] = ceili(float(now_steps) / float(Plot.SUB))
			new_trim[own] = new_size[own] * Plot.SUB - now_steps
			size = new_size
			trim = new_trim
			# Grown from the minus side, the building's corner moves too.
			if h.sign < 0.0 and axis_i != 1:
				cell += Vector2i(-steps, 0) if axis_i == 0 else Vector2i(0, -steps)
		BuildGizmo.Mode.ROTATE:
			var start: Vector3 = h.point
			var angle := BuildGizmo.angle_about(d.centre, axis, start, ray[0], ray[1])
			steps = int(round(angle / (PI * 0.5)))
			var turn := Vector3i.ZERO
			turn[axis_i] = steps
			rot = Vector3i(posmod(rot.x + turn.x, 4), posmod(rot.y + turn.y, 4), posmod(rot.z + turn.z, 4))
			# Keep it turning about its middle rather than its corner.
			var def: BuildingDef = selected_record().def
			var old_fp := Plot.oriented_size(def.size, d.rot)
			var new_fp := Plot.oriented_size(def.size, rot)
			cell += Vector2i((old_fp.x - new_fp.x) * Plot.SUB / 2, (old_fp.z - new_fp.z) * Plot.SUB / 2)
	if steps == int(d.steps):
		return
	d.steps = steps
	var rec := selected_record()
	if rec.cell == cell and rec.rot == rot and (rec.def as BuildingDef).size == size \
			and (rec.def as BuildingDef).trim == trim and is_equal_approx(float(rec.get("lift", 0.0)), lift):
		return
	if _guest():
		var same: bool = size == (rec.def as BuildingDef).size and trim == (rec.def as BuildingDef).trim
		var new_def: BuildingDef = rec.def if same else Plot.resized(rec.def, size, trim)
		edit_error = plot.placement_error(new_def, cell, rot, false, selected)
		if edit_error == "":
			_ask_host({"op": "edit", "id": _net_id(rec.node), "cell": [cell.x, cell.y],
				"rot": [rot.x, rot.y, rot.z], "size": [size.x, size.y, size.z], "lift": lift,
				"trim": [trim.x, trim.y, trim.z]})
		return
	edit_error = plot.edit(selected, cell, rot, size, lift, trim)
	_refresh_gizmo_box()
	if edit_mode == BuildGizmo.Mode.MOVE and edit_error == "" and not multi.is_empty():
		_move_others(cell - (d.cell as Vector2i), lift - float(d.lift))

## Moves the selection box and the knobs with the building without rebuilding
## the handles being dragged.
func _refresh_gizmo_box() -> void:
	var box := _record_box(selected_record())
	_gizmo.follow(box[0], box[1])

func remove_selected() -> void:
	if not editing():
		return
	var nodes: Array[Node3D] = [selected_record().node]
	nodes.append_array(multi)
	deselect()
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if _guest():
			_ask_host({"op": "remove", "id": _net_id(node)})
		else:
			plot.remove(node)

func edit_hint() -> String:
	var names := ["(1) Move", "(2) Scale", "(3) Rotate"]
	var parts: Array[String] = []
	for i in 3:
		parts.append(("[%s]" % names[i]) if i == int(edit_mode) else names[i])
	var many := ("   ·   %d selected" % selection_count()) if not multi.is_empty() else ""
	return "   ".join(parts) + "      aim at a handle, hold LMB and move the mouse   ·   [%s] add/remove more   ·   [Del] remove   ·   [F] done" % Controls.key(&"add_select") + many

## What the crosshair is on: the ray hit against the ground and buildings -
## and plans not yet filled, which have nothing solid to hit, by the box
## round them, so they are as easy to pick as anything built.
func _aim_hit() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.MACHINE)
	var hit := space.intersect_ray(q)
	var plan := _aim_plan(from, to)
	if not plan.is_empty() and (hit.is_empty() or from.distance_to(plan.position) < from.distance_to(hit.position) + 0.3):
		return plan
	return hit

## The nearest unfinished plan along the aim, as a hit on the plan itself.
func _aim_plan(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.TRIGGER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var skip: Array[RID] = []
	for attempt in 6:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var area := hit.collider as Area3D
		if area != null and area.get_parent() is Schematic and not (area.get_parent() as Schematic).solid:
			return {"collider": area.get_parent(), "position": hit.position, "normal": hit.normal}
		skip.append(hit.rid)
	return {}

## What a plan under the crosshair is made of (or wants), for the HUD.
func plan_hover_text() -> String:
	if not active:
		return ""
	var hit := _aim_hit()
	var i := plot.index_at_hit(hit) if not hit.is_empty() else -1
	if i < 0:
		return ""
	var node: Node = plot.placed[i].node
	if node is Schematic:
		return (node as Schematic).status_line()
	return ""

## Aim ray against the world layer, then snap the footprint so it is centred on
## the cell under the crosshair.
func _aim_point() -> Variant:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.MACHINE)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# Fall back to the ground plane so the ghost still tracks over open space.
		var dir := -camera.global_transform.basis.z
		if dir.y >= -0.05:
			return null
		var t: float = (plot.global_position.y - from.y) / dir.y
		if t < 0.0 or t > REACH:
			return null
		return from + dir * t
	return hit.position

func _update_ghost() -> void:
	var def := current()
	var point: Variant = _aim_point()
	if def == null or point == null:
		has_target = false
		_hide_ghost()
		last_error = "" if def == null else "no target"
		return
	var world_point: Vector3 = point
	var fp := Plot.oriented_size(def.size, rot)
	var cursor := plot.world_to_cell(world_point)
	target_cell = Vector2i(cursor.x - fp.x * Plot.SUB / 2, cursor.y - fp.z * Plot.SUB / 2)
	has_target = true

	var size := Plot.oriented_extent(def.extent(), rot)
	var base := plot.cell_to_world(target_cell, def.size, rot, def.trim)
	(_ghost.mesh as BoxMesh).size = size
	_ghost.global_position = base + Vector3(0, size.y * 0.5, 0)
	_ghost.rotation = Vector3.ZERO
	_ghost.visible = true

	last_error = plot.placement_error(def, target_cell, rot)
	# The box is only the footprint now, faint; the model shows the building.
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.10) if last_error == "" \
		else Color(1.0, 0.3, 0.25, 0.16)
	_ensure_preview(def)
	if _preview != null:
		_preview.visible = true
		_preview.global_transform = Transform3D(plot.global_transform.basis * Plot.orientation_basis(rot),
			base + plot.global_transform.basis * Plot.tilt_offset(def.extent(), rot))
		_tint_preview(last_error == "")

func try_place() -> bool:
	if not active or not has_target or editing():
		return false
	var def := current()
	if def == null:
		return false
	if _guest():
		if plot.placement_error(def, target_cell, rot) != "":
			return false
		_ask_host({"op": "place", "def": String(def.id), "tier": def.tier,
			"size": [def.size.x, def.size.y, def.size.z], "trim": [def.trim.x, def.trim.y, def.trim.z],
			"cell": [target_cell.x, target_cell.y],
			"rot": [rot.x, rot.y, rot.z]})
		return true
	var node := plot.place(def, target_cell, rot)
	if node != null:
		Sfx.play(&"place", node.global_position)
	return node != null

# --- Co-op ---------------------------------------------------------------------------

## A co-op guest builds on the host's land: what they do here is asked of the
## host, which puts it up (and charges for it), and the result comes back.
func _guest() -> bool:
	return Net.is_client() and Net.client_side != null

func _ask_host(ev: Dictionary) -> void:
	Net.client_side.call("send_build", ev)

func _net_id(node: Node) -> int:
	return int(Net.client_side.call("id_of", node))

func try_remove() -> bool:
	if not active:
		return false
	if _guest():
		var at := plot.index_at_hit(_aim_hit())
		if at < 0:
			var p: Variant = _aim_point()
			at = plot.index_at_world(p) if p != null else -1
		if at < 0 or at >= plot.placed.size():
			return false
		_ask_host({"op": "remove", "id": _net_id(plot.placed[at].node)})
		return true
	var hit := _aim_hit()
	if not hit.is_empty():
		var gone := plot.remove_at_hit(hit)
		if gone:
			Sfx.play(&"remove", hit.position)
		return gone
	var point: Variant = _aim_point()
	if point == null:
		return false
	return plot.remove_at_world(point)

func status_line() -> String:
	var def := current()
	if def == null:
		return "nothing in hand - [E] opens the build menu"
	var base := "%s  %s" % [def.display_name, PlayerState.build_note(def)]
	if last_error != "":
		return base + "  -- " + last_error
	return base
