extends Node3D
## Probe (not part of the game): how steep a slope each vehicle can drive up.
##   godot --headless --path . --fixed-fps 60 scenes/climb.tscn -- [--manual] [--flat]

func _ready() -> void:
	InputSetup.ensure()
	var args := OS.get_cmdline_user_args()
	var ids := ["pickup", "hauler", "log_truck", "dump_truck", "crane_truck", "quad", "buggy", "loader"]
	for deg in [20.0, 28.0, 34.0, 40.0]:
		var line := "%4.0f deg:" % deg
		for id in ids:
			var h := await _climb(id, deg, args.has("--manual"), args.has("--flat"))
			line += "  %s %.1f" % [id, h]
		print(line)
	get_tree().quit()

func _climb(id: String, deg: float, manual: bool, no_boost: bool) -> float:
	var world := Node3D.new()
	add_child(world)
	StressWorld.build_ground(world, 400.0)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = Layers.WORLD
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	ramp.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var length := 120.0
	box.size = Vector3(20, 1, length)
	cs.shape = box
	var a := deg_to_rad(deg)
	# Ramp rising toward -Z from z = -10.
	cs.transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, sin(a) * length * 0.5 - 0.5 * cos(a), -10.0 - cos(a) * length * 0.5))
	ramp.add_child(cs)
	world.add_child(ramp)
	var manager := LooseItemManager.new()
	world.add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))
	var v := Hauler.new()
	v.setup(manager, 0, StringName(id))
	world.add_child(v)
	v.global_position = Vector3(0, v.spawn_height(), 6)
	if no_boost:
		Hauler.GEAR_TORQUE_EXP = 0.0
	Settings.set_value(&"manual_gearbox", manual, false)
	for i in 60:
		await get_tree().physics_frame
	v.autopilot = true
	v.input_throttle = 1.0
	var best := 0.0
	for i in 600:
		await get_tree().physics_frame
		best = maxf(best, v.global_position.y)
	world.queue_free()
	await get_tree().process_frame
	Hauler.GEAR_TORQUE_EXP = 0.85
	return best
