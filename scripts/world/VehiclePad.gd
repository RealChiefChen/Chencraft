class_name VehiclePad
extends Node3D

## A marked slab on the property that a vehicle appears on.
##
## The pad is the vehicle: owning one is what lets you have a truck, and one pad
## is worth exactly one truck. Triggering it again does not give you a second -
## it takes the old one away first, wherever it happens to have been left, which
## is also how you get a truck back after driving it into a ravine.

signal vehicle_spawned(pad: VehiclePad, vehicle: Node3D)

@export var building_id: StringName = &"vehicle_pad"

var def: BuildingDef
var manager: LooseItemManager
var plot_id: int = 0
## Where a spawned vehicle is parented. Not the pad itself: a truck has to be
## able to drive off it.
var host: Node3D
var terrain: Terrain

var vehicle: Node3D = null
## On a loader's pad: what the loader comes out with, a bucket or a log
## grapple. Changing it means sending the loader back and spawning it again.
var attachment: StringName = &"bucket"
## The colour the next vehicle off this pad is painted (alpha 0: as it comes
## from the factory).
var paint: Color = Color(0, 0, 0, 0)
const PAINTS := [
	["Factory", Color(0, 0, 0, 0)], ["Fire red", Color(0.80, 0.14, 0.12)], ["Sunset orange", Color(0.95, 0.46, 0.10)],
	["Lemon", Color(0.96, 0.82, 0.16)], ["Lime", Color(0.45, 0.80, 0.20)], ["Forest", Color(0.12, 0.42, 0.20)],
	["Teal", Color(0.08, 0.58, 0.60)], ["Sky", Color(0.30, 0.62, 0.95)], ["Navy", Color(0.12, 0.20, 0.52)],
	["Grape", Color(0.46, 0.22, 0.66)], ["Pink", Color(0.96, 0.44, 0.66)], ["Snow", Color(0.93, 0.93, 0.95)],
	["Graphite", Color(0.20, 0.21, 0.23)], ["Sand", Color(0.82, 0.70, 0.50)],
]

## The parts fitted to this pad's vehicle: track -> level (1 is stock), and
## which of them are switched on. They go on whichever vehicle comes off the
## pad, and on the one out now as soon as they are fitted or switched.
var fitted: Dictionary = {}
var switched_off: Dictionary = {}

func fitted_level(track: StringName) -> int:
	return int(fitted.get(track, 1))

func part_on(track: StringName) -> bool:
	return not bool(switched_off.get(track, false))

## What the vehicle runs with: the fitted level of each track, or stock where
## a part is switched off.
func effective_parts() -> Dictionary:
	var out := {}
	for track in PlayerState.VEHICLE_TRACKS:
		out[track] = fitted_level(track) if part_on(track) else 1
	return out

## Fits a part from the inventory (level 1: back to stock); the part taken off
## goes back into the inventory. Returns "" or why not.
func fit(track: StringName, lvl: int) -> String:
	var now := fitted_level(track)
	if lvl == now:
		return ""
	if lvl > 1 and not PlayerState.take_part(track, lvl):
		return "no %s in your parts" % GameData.part_name(track, lvl)
	if now > 1:
		PlayerState.add_part(track, now)
	fitted[track] = lvl
	_apply_parts()
	return ""

func set_part_on(track: StringName, on: bool) -> void:
	switched_off[track] = not on
	_apply_parts()

func _apply_parts() -> void:
	if has_vehicle() and vehicle is Hauler:
		(vehicle as Hauler).set_parts(effective_parts())

var _size: Vector3 = Vector3(4, 0.2, 6)

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0,
		p_host: Node3D = null) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	plot_id = p_plot_id
	host = p_host

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	_size = def.footprint_world(Plot.CELL)
	_build()

func has_vehicle() -> bool:
	return vehicle != null and is_instance_valid(vehicle)

## Spec: one copy at a time. A second call clears the first.
func spawn() -> Node3D:
	recall()
	var truck := Hauler.new()
	truck.setup(manager, plot_id, def.vehicle if def != null else &"hauler")
	truck.paint_override = paint
	truck.part_levels = effective_parts()
	truck.terrain = terrain
	var target: Node3D = host if host != null else get_parent() as Node3D
	if target == null:
		return null
	target.add_child(truck)
	if truck.loader != null:
		truck.loader.set_attachment(attachment)
	truck.global_transform = Transform3D(
		Basis.from_euler(Vector3(0, global_rotation.y, 0)),
		global_position + Vector3(0, truck.spawn_height(), 0))
	vehicle = truck
	vehicle_spawned.emit(self, truck)
	return truck

## Takes the current vehicle away, wherever it is. Its load is real, so it
## stays where it was and drops to the ground.
func recall() -> bool:
	if not has_vehicle():
		vehicle = null
		return false
	# Whoever is at the wheel is put out by the door first.
	var driver: Variant = vehicle.get("driver")
	if driver is Player and is_instance_valid(driver):
		var p := driver as Player
		var size: Variant = vehicle.get("body_size")
		var out := (size as Vector3).x * 0.5 + 1.3 if size is Vector3 else 2.5
		p.exit_vehicle()
		vehicle.set("driver", null)
		p.global_position = vehicle.global_position + vehicle.global_transform.basis.x * out + Vector3(0, 1.0, 0)
		p.velocity = Vector3.ZERO
	vehicle.queue_free()
	vehicle = null
	return true

func status_line() -> String:
	var line := ""
	if has_vehicle():
		var distance := global_position.distance_to((vehicle as Node3D).global_position)
		line = "%s: [E] recall and respawn (it is %.0f m away)" % [def.display_name, distance]
	else:
		line = "%s: [E] spawn the %s" % [def.display_name, vehicle_name().to_lower()]
	line += "\n[R] paint, parts%s" % (" and bucket or grapple (now the %s)" % _attachment_name() if is_loader_pad() else "")
	return line

func vehicle_name() -> String:
	var spec := GameData.vehicle(def.vehicle if def != null else &"hauler")
	return String(spec.get("display_name", "vehicle"))

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, 0.2, _size.z)
	cs.shape = box
	cs.position = Vector3(0, 0.1, 0)
	body.add_child(cs)
	add_child(body)

	var g := Greeble.new()
	g.block(Vector3(_size.x, 0.2, _size.z), Vector3(0, 0.1, 0), Color(0.24, 0.25, 0.27))
	g.frame(Vector3(_size.x, 0.2, _size.z), Transform3D(Basis(), Vector3(0, 0.1, 0)), 0.1, Color(0.16, 0.16, 0.18))
	# Hazard stripes down the long edges, so the pad reads as somewhere a
	# vehicle lands rather than as a floor tile.
	for side in [-1.0, 1.0]:
		g.stripes(_size.z - 0.3, 0.32, Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5),
			Vector3(side * (_size.x * 0.5 - 0.24), 0.2, 0)))
	# A painted "H" and parking lines.
	var paint := Color(0.92, 0.92, 0.88)
	g.block(Vector3(0.2, 0.02, 1.6), Vector3(-0.55, 0.21, 0), paint)
	g.block(Vector3(0.2, 0.02, 1.6), Vector3(0.55, 0.21, 0), paint)
	g.block(Vector3(1.1, 0.02, 0.2), Vector3(0, 0.21, 0), paint)
	# A post at the head of the pad with a sign, and lamps on the corners.
	g.block(Vector3(0.16, 1.6, 0.16), Vector3(0, 0.8, -_size.z * 0.5 + 0.3), Color(0.35, 0.36, 0.38))
	g.plate(1.1, 0.5, Transform3D(Basis(), Vector3(0, 1.7, -_size.z * 0.5 + 0.38)), Color(0.86, 0.72, 0.16))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * (_size.x * 0.5 - 0.1), 0.2, sz * (_size.z * 0.5 - 0.1))
			g.block(Vector3(0.14, 0.5, 0.14), at + Vector3(0, 0.25, 0), Color(0.2, 0.2, 0.22))
			g.block(Vector3(0.18, 0.12, 0.18), at + Vector3(0, 0.56, 0), Color(1.0, 0.62, 0.2), true)
	add_child(g.instance("Pad"))

func _slab(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)

func is_loader_pad() -> bool:
	return def != null and GameData.vehicle(def.vehicle).get("loader", null) is Dictionary

## Which attachment the next loader off this pad gets. Returns what to say.
func cycle_attachment() -> String:
	if not is_loader_pad():
		return ""
	var kinds: Array = LoaderArm.ATTACHMENTS
	attachment = kinds[(kinds.find(attachment) + 1) % kinds.size()]
	return "the next loader from this pad comes with the %s - [E] to send the old one back and spawn it" % _attachment_name()

func _attachment_name() -> String:
	return "log grapple" if attachment == &"grapple" else "bucket"

func to_dict() -> Dictionary:
	var fit := {}
	for k in fitted:
		fit[String(k)] = int(fitted[k])
	var off := {}
	for k in switched_off:
		off[String(k)] = bool(switched_off[k])
	var d := {"has_vehicle": has_vehicle(), "attachment": String(attachment),
		"paint": [paint.r, paint.g, paint.b, paint.a], "fitted": fit, "off": off}
	if has_vehicle() and vehicle.has_method("to_dict"):
		d["vehicle"] = vehicle.call("to_dict")
	return d

func from_dict(d: Dictionary) -> void:
	attachment = StringName(String(d.get("attachment", "bucket")))
	var c: Array = d.get("paint", [0, 0, 0, 0])
	paint = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	fitted.clear()
	for k in d.get("fitted", {}):
		fitted[StringName(k)] = int(d["fitted"][k])
	switched_off.clear()
	for k in d.get("off", {}):
		switched_off[StringName(k)] = bool(d["off"][k])
	if not bool(d.get("has_vehicle", false)):
		return
	var truck := spawn()
	if truck != null and d.has("vehicle") and truck.has_method("from_dict"):
		truck.call("from_dict", d["vehicle"])
