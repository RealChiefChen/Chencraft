class_name Avatar
extends Node3D

## How another player looks in co-op: the same lumberjack you play as, in a
## shirt of their colour with their name over him, posed by PlayerAvatar from
## how he moves here and what the host says he is doing (carrying, dragging,
## building, the tool in hand, each chop and throw).
##
## PlayerAvatar asks a player a handful of questions; this answers them for
## someone whose game is on another machine.

static func color_for(id: int) -> Color:
	var colors := [Color(0.85, 0.35, 0.25), Color(0.25, 0.55, 0.85), Color(0.95, 0.75, 0.2),
		Color(0.45, 0.75, 0.35), Color(0.7, 0.4, 0.8), Color(0.95, 0.55, 0.2), Color(0.3, 0.75, 0.75),
		Color(0.9, 0.9, 0.9)]
	return colors[absi(id) % colors.size()]

var body: PlayerAvatar
## Stands in for the player's camera: its pitch is where they look.
var camera: Node3D
var head: Node3D:
	get:
		return camera
## Worked out from how far he moved since the last frame.
var velocity: Vector3 = Vector3.ZERO
## The truck he is in, as the host last said (null on foot).
var vehicle: Node3D = null
var held: Array = []
var dragged: Variant = null
var build_system: Variant = null
var third_person: bool = true
var input := PlayerInput.new()
var _tool: StringName = &""
var _last: Variant = null
var _floor_t: float = 0.0

func setup(display: String, color: Color) -> void:
	input.remote = true
	camera = Node3D.new()
	camera.name = "Look"
	camera.position = Vector3(0, 1.65, 0)
	add_child(camera)
	body = PlayerAvatar.new(self)
	body.fidgets = false
	body.set_look(display, color)
	add_child(body)

## Where they are looking up or down.
func set_pitch(pitch: float) -> void:
	if camera != null:
		camera.rotation.x = pitch

## The host's snapshot of this player: pitch, the truck they are in, the tool
## in hand, and what they are carrying, dragging and doing.
func apply_state(s: Dictionary, vehicle_node: Node3D) -> void:
	set_pitch(float(s.get("pitch", 0.0)))
	vehicle = vehicle_node
	_tool = StringName(s.get("tool", ""))
	if body != null:
		body.apply_net_state(s)

func _physics_process(delta: float) -> void:
	var here := global_position
	if _last is Vector3 and delta > 0.0:
		var moved: Vector3 = (here - (_last as Vector3)) / delta
		# Snapshots come in steps; smooth them into a steady pace.
		velocity = velocity.lerp(moved, clampf(delta * 10.0, 0.0, 1.0))
	_last = here
	_floor_t = 0.0 if absf(velocity.y) > 1.5 else _floor_t + delta

# --- What PlayerAvatar asks ------------------------------------------------

func driving() -> bool:
	return vehicle != null and is_instance_valid(vehicle)

func rig() -> VehicleRig:
	return vehicle.get("rig") as VehicleRig if driving() else null

func loader() -> LoaderArm:
	return vehicle.get("loader") as LoaderArm if driving() else null

func is_on_floor() -> bool:
	return _floor_t > 0.1

func water_depth() -> float:
	return maxf(0.0, Terrain.WATER_LEVEL - global_position.y)

func swimming() -> bool:
	return water_depth() > Player.WADE_DEPTH

func selected_tool() -> StringName:
	return _tool

func selected_tool_def() -> Dictionary:
	return GameData.tool(_tool) if _tool != &"" else {}

func drag_point() -> Vector3:
	return global_position
