extends Node
## Screenshot harness (not part of the game): boots the world with no menu,
## runs a scenario named by --shot=<name>, saves PNGs to user://shots.

var world: World
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	world = load("res://scenes/world.tscn").instantiate()
	world.show_menu = false
	world.autosave = false
	add_child(world)
	for i in 30:
		await get_tree().process_frame
	var shot: String = args.get("shot", "home")
	await call("shot_" + shot)
	get_tree().quit()

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shots"))
	img.save_png("user://shots/%s.png" % name)
	print("saved ", name)

func look(from: Vector3, at: Vector3) -> void:
	var cam := world.player.camera
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(), from).looking_at(at, Vector3.UP)
	world.hud.visible = args.has("hud")
	for i in 20:
		await get_tree().process_frame

func shot_home() -> void:
	await look(Vector3(0, 60, 90), Vector3(0, 0, 0))
	await snap("home")

func _cam_state() -> String:
	var c := world.player.camera
	return "pos=%s rot=%s" % [c.global_position.snapped(Vector3.ONE * 0.01), c.global_rotation.snapped(Vector3.ONE * 0.001)]

func _mouse(button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(ev)

func _motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(ev)

func shot_dragcam() -> void:
	var p := world.player
	p.global_position = world.plot.global_position + Vector3(0, 1, 8)
	for i in 5:
		await get_tree().physics_frame
	Settings.set_value(&"unlimited_money", true, false)
	world.build_system.set_active(true)
	var node := world.plot.place(GameData.building(&"conveyor"), Vector2i(0, 0), 0, false)
	var idx := world.plot.placed.size() - 1
	world.build_system.select_building(idx)
	await get_tree().process_frame
	var bs := world.build_system
	var h: Dictionary = bs._gizmo.handles[0]
	var cam := p.camera
	cam.global_transform = Transform3D(Basis(), cam.global_position).looking_at(h.point, Vector3.UP)
	await get_tree().process_frame
	print("handle pick=", bs._gizmo.pick(cam, bs._centre()), " ", _cam_state())
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	print("dragging=", not bs._drag.is_empty(), " ", _cam_state())
	for i in 10:
		_motion(Vector2(12, 0))
		await get_tree().process_frame
		print("  drag ", i, " ", _cam_state(), " cell=", world.plot.placed[idx].cell)
	_mouse(MOUSE_BUTTON_LEFT, false)
	for i in 6:
		await get_tree().process_frame
		print("  after ", i, " ", _cam_state())
	_motion(Vector2(1, 0))
	await get_tree().process_frame
	print("  after small motion ", _cam_state())

func shot_roads() -> void:
	var t: Terrain = world.terrain
	var found: Array = []
	for road in t.road_paths:
		var path: Array = road.path
		if path.size() < 3:
			continue
		var span := t._path_length(path)
		var along := 10.0
		while along < span - 10.0:
			var a := t._point_along(path, along - 8.0)
			var p := t._point_along(path, along)
			var b := t._point_along(path, along + 8.0)
			var d1 := Vector2(p.x - a.x, p.z - a.z).normalized()
			var d2 := Vector2(b.x - p.x, b.z - p.z).normalized()
			var turn := absf(d1.angle_to(d2))
			var relief := 0.0
			for k in 8:
				var ang := TAU * k / 8.0
				relief = maxf(relief, absf(t.height_at(p.x + cos(ang) * 20.0, p.z + sin(ang) * 20.0) - t.height_at(p.x, p.z)))
			if turn > 0.6 and relief > 6.0:
				found.append({"p": p, "turn": turn, "relief": relief, "back": t._point_along(path, maxf(0.0, along - 22.0))})
				along += 60.0
			along += 3.0
	found.sort_custom(func(x, y): return x.turn * x.relief > y.turn * y.relief)
	print("sharp steep turns: ", found.size())
	for i in mini(4, found.size()):
		var f: Dictionary = found[i]
		var p: Vector3 = f.p
		p.y = t.height_at(p.x, p.z)
		print("turn %d at %s angle %.2f relief %.1f" % [i, p, f.turn, f.relief])
		await look(p + Vector3(18, 22, 18), p)
		await snap("road_%d" % i)
		var back: Vector3 = f.back
		back.y = t.height_at(back.x, back.z) + 2.5
		await look(back, p + Vector3(0, 1.0, 0))
		await snap("road_%d_low" % i)

func shot_plot() -> void:
	Settings.set_value(&"unlimited_money", true, false)
	while world.plot.try_expand():
		pass
	await look(Vector3(70, 45, 70), Vector3(0, 0, 0))
	await snap("plot_corner")
	await look(Vector3(0, 90, 1), Vector3(0, 0, 0))
	await snap("plot_top")

func shot_forest() -> void:
	var c: Vector3 = world.starter_forest
	print("starter forest at ", c)
	await look(c + Vector3(40, 35, 40), c)
	await snap("starter_forest")
	await look(Vector3(0, 380, 200), Vector3(0, 0, -150))
	await snap("groves")

func shot_store() -> void:
	var s: Store = world.store
	var door := s.global_transform * Vector3(0, 1.6, s.extents.z * 0.5 + 5.0)
	await look(door + Vector3(3, 0.5, 0), s.global_transform * Vector3(0, 0.2, s.extents.z * 0.5))
	await snap("store_door")
	# The gear bay.
	await look(s.global_transform * Vector3(0, 3.0, 2.0), s.global_transform * Vector3(0, 0.5, -s.extents.z * 0.5))
	await snap("store_inside")

func shot_build() -> void:
	var p := world.player
	p.global_position = world.plot.global_position + Vector3(0, 1, 6)
	Settings.set_value(&"unlimited_money", true, false)
	for i in 5:
		await get_tree().physics_frame
	for x in 3:
		world.plot.place(GameData.building(&"conveyor_open"), Vector2i(x * 4, -8), Vector3i.ZERO, false)
	world.plot.place(GameData.building(&"conveyor"), Vector2i(-12, -8), Vector3i.ZERO, false)
	world.build_system.set_active(true)
	world.hud.visible = true
	await get_tree().process_frame
	var cam := p.camera
	cam.global_transform = Transform3D(Basis(), world.plot.global_position + Vector3(1, 4.5, 4)).looking_at(world.plot.global_position + Vector3(0.5, 0, -1), Vector3.UP)
	for i in 10:
		await get_tree().process_frame
	await snap("build_empty")
	world.build_system.toggle_menu()
	for i in 10:
		await get_tree().process_frame
	await snap("build_menu")
	world.hud.close_build_menu()
	world.build_system.choose(GameData.building(&"sander"))
	for i in 10:
		await get_tree().process_frame
	await snap("build_ghost")

func shot_loader() -> void:
	var p := world.player
	var at := world.plot.global_position + Vector3(0, 0, 30)
	at.y = world.terrain.height_at(at.x, at.z)
	var v := Hauler.new()
	v.setup(world.manager, 0, &"loader")
	world.add_child(v)
	v.global_position = at + Vector3(0, v.spawn_height(), 0)
	for i in 30:
		await get_tree().physics_frame
	print(v.loader.swap_attachment())
	for i in 10:
		await get_tree().physics_frame
	await look(at + Vector3(-6, 3.5, -7), at + Vector3(0, 1, -1.5))
	await snap("loader_grapple")

func shot_fell() -> void:
	var trees: Array = world.trees()
	var best: ChoppableTree = null
	for t in trees:
		if t.foliage_style == &"ball" or t.foliage_style == &"cone":
			if best == null or t.global_position.distance_to(world.plot.global_position) < best.global_position.distance_to(world.plot.global_position):
				best = t
	var at := best.global_position
	best.fell(at + Vector3(0, 0, 3))
	for i in 180:
		await get_tree().physics_frame
	await look(at + Vector3(8, 5, 8), at + Vector3(0, 0.5, -3))
	await snap("felled")

func shot_pause() -> void:
	world.pause_game()
	for i in 10:
		await get_tree().process_frame
	await snap("pause")
	world.pause_menu._show_slots()
	for i in 10:
		await get_tree().process_frame
	await snap("pause_slots")
	world.pause_menu._show_page("Settings", SettingsPanel.new())
	for i in 10:
		await get_tree().process_frame
	await snap("settings_controls")

func shot_drive() -> void:
	var at := world.plot.global_position + Vector3(0, 0, 60)
	at.y = world.terrain.height_at(at.x, at.z)
	var v := Hauler.new()
	v.setup(world.manager, 0, &"crane_truck")
	world.add_child(v)
	v.global_position = at + Vector3(0, v.spawn_height(), 0)
	for i in 30:
		await get_tree().physics_frame
	world.drive(v)
	world.hud.visible = true
	Settings.set_value(&"manual_gearbox", true, false)
	for i in 30:
		await get_tree().process_frame
	await snap("drive_manual")
	v.rig.set_operating(true)
	for i in 60:
		await get_tree().physics_frame
	await snap("crane_banner")

func shot_menu() -> void:
	world.show_main_menu()
	for i in 20:
		await get_tree().process_frame
	await snap("main_menu")
	world.main_menu._open_page("Controls", KeyGuide.sheet())
	for i in 10:
		await get_tree().process_frame
	await snap("main_controls")

func shot_axe() -> void:
	var p := world.player
	PlayerState.give_tool(&"steel_axe", false)
	p.select_slot(PlayerState.hotbar.find(&"steel_axe"))
	world.hud.visible = false
	for i in 20:
		await get_tree().process_frame
	await snap("axe")

func shot_minimap() -> void:
	var p := world.player
	p.rotation.y = 0.8
	Settings.set_value(&"minimap_rotate", true, false)
	Settings.set_value(&"minimap_zoom", 2, false)
	world.hud.visible = true
	for i in 30:
		await get_tree().process_frame
	await snap("minimap")

## The lumberjack in third person, in one pose after another.
func _pose_cam(p: Player, side: float = 1.0, dist: float = 2.6) -> void:
	var at := p.global_position + Vector3(0, 0.95, 0)
	var f := -p.global_transform.basis.z
	var r := p.global_transform.basis.x
	var cam := p.camera
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(), at + f * dist + r * dist * 0.55 * side + Vector3(0, 0.35, 0)).looking_at(at, Vector3.UP)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Plays a gesture and waits until it is `share` of the way through.
func _gesture_at(p: Player, kind: StringName, share: float) -> void:
	# Slowed right down, so a slow frame here does not skip the moment.
	p.avatar.play(kind)
	Engine.time_scale = clampf(p.avatar._g_len * 0.4, 0.12, 1.0)
	while p.avatar._gesture == kind and p.avatar._g_t < p.avatar._g_len * share:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	Engine.time_scale = 1.0

func _stand(p: Player) -> Vector3:
	world.hud.visible = false
	var at := world.plot.global_position + Vector3(4, 0, 10)
	at.y = world.terrain.height_at(at.x, at.z) + 0.2
	p.global_position = at
	p.third_person = true
	for i in 30:
		await get_tree().physics_frame
	return at

func shot_avatar() -> void:
	var p := world.player
	await _stand(p)
	_pose_cam(p)
	await _frames(10)
	await snap("av_idle")
	await _gesture_at(p, &"stroke", 0.5)
	await snap("av_stroke")
	await _gesture_at(p, &"stretch", 0.5)
	await snap("av_stretch")
	await _gesture_at(p, &"scratch", 0.5)
	await snap("av_scratch")
	PlayerState.give_tool(&"steel_axe", false)
	p.select_slot(PlayerState.hotbar.find(&"steel_axe"))
	await _frames(20)
	await snap("av_tool")
	await _gesture_at(p, &"swing", 0.36)
	await snap("av_swing_up")
	await _gesture_at(p, &"swing", 0.6)
	await snap("av_swing_down")
	p.select_slot(p.selected_slot)
	await _frames(20)
	await _gesture_at(p, &"pick_up", 0.5)
	await snap("av_pick_up")
	await _gesture_at(p, &"throw", 0.34)
	await snap("av_throw")
	await _gesture_at(p, &"use", 0.5)
	await snap("av_use")
	await _gesture_at(p, &"drop", 0.5)
	await snap("av_drop")
	Input.action_press("move_forward")
	for i in 40:
		await get_tree().physics_frame
		_pose_cam(p)
	await snap("av_walk")
	Input.action_release("move_forward")
	p.velocity.y = p.jump_velocity
	for i in 16:
		await get_tree().physics_frame
		_pose_cam(p)
	await snap("av_jump")

func shot_avatar_drive() -> void:
	var p := world.player
	var at := await _stand(p)
	world.build_system.set_active(true)
	await _frames(10)
	_pose_cam(p, -1.0, 3.0)
	await _frames(2)
	await snap("av_build")
	await _gesture_at(p, &"place", 0.3)
	await snap("av_place")
	world.build_system.set_active(false)
	await _frames(5)
	var v := Hauler.new()
	v.setup(world.manager, 0, StringName(args.get("vehicle", "quad")))
	world.add_child(v)
	v.global_position = at + Vector3(6, v.spawn_height(), 0)
	for i in 40:
		await get_tree().physics_frame
	world.drive(v)
	for i in 20:
		await get_tree().physics_frame
	var vb := v.global_transform.basis
	var cam := p.camera
	cam.top_level = true
	Input.action_press("move_right")
	await _frames(30)
	vb = v.global_transform.basis
	p.rotation.y += PI * 0.5
	p.camera.rotation.x = -0.15
	await _frames(10)
	cam.global_transform = Transform3D(Basis(), v.global_position - vb.x * 3.2 + Vector3(0, 0.9, 0) + vb.z * 0.3).looking_at(v.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	await _frames(3)
	await snap("av_drive")
	Input.action_release("move_right")
	vb = v.global_transform.basis
	cam.global_transform = Transform3D(Basis(), v.global_position - vb.z * 3.5 + Vector3(0, 1.5, 0)).looking_at(v.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	await _frames(3)
	await snap("av_drive_front")

func shot_views() -> void:
	var p := world.player
	await _stand(p)
	world.hud.visible = true
	p.camera.top_level = false
	p.camera.rotation.x = -0.15
	p.set_third_person(true)
	PlayerState.give_tool(&"steel_axe", false)
	p.select_slot(PlayerState.hotbar.find(&"steel_axe"))
	await _frames(30)
	await snap("view_third")
	p.set_third_person(false)
	p.camera.rotation.x = -0.9
	await _frames(30)
	await snap("view_first_down")
	Settings.set_value(&"third_person", false)

## How other co-op players look: the lumberjack in their colour, named.
func shot_coop() -> void:
	var p := world.player
	var at := await _stand(p)
	var names := ["Dell", "Sam"]
	for i in 2:
		var a := Avatar.new()
		a.setup(names[i], Avatar.color_for(i + 2))
		world.add_child(a)
		a.global_position = at + Vector3(-1.2 + 2.4 * i, 0, -4.0)
		a.rotation.y = PI
		a.apply_state({"pitch": 0.0, "veh": -1, "tool": "steel_axe" if i == 0 else "", "held": 0, "build": false}, null)
	for i in 30:
		await get_tree().physics_frame
	var cam := p.camera
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(), at + Vector3(0, 1.8, 0.5)).looking_at(at + Vector3(0, 1.1, -4.0), Vector3.UP)
	await _frames(5)
	await snap("coop")

func shot_aerial() -> void:
	Settings.set_value(&"moving_sun", false, false)
	await look(Vector3(40, 170, 220), Vector3(-30, 0, -40))
	await snap("aerial")

func shot_ground() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var c: Vector3 = world.starter_forest
	await look(c + Vector3(50, 8, 55), c)
	await snap("ground")

func shot_machinecfg() -> void:
	var m := world.plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0, false) as InlineMachine
	await get_tree().process_frame
	m.set_setting(&"width_cm", 15)
	world.hud.visible = true
	world.hud.machine_config.open(m)
	for i in 10:
		await get_tree().process_frame
	await snap("machinecfg")

func shot_padpanel() -> void:
	var pad := world.plot.place(GameData.building(&"pad_loader"), Vector2i(0, 0), 0, false) as VehiclePad
	await get_tree().process_frame
	pad.paint = VehiclePad.PAINTS[6][1]
	world.hud.visible = true
	world.hud.pad_panel.open(pad)
	for i in 10:
		await get_tree().process_frame
	await snap("padpanel")

func shot_ladder() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var truck := Hauler.new()
	truck.setup(world.manager, 0, &"hauler")
	truck.terrain = world.terrain
	world.add_child(truck)
	var at := Vector3(20, 0, 30)
	truck.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + truck.spawn_height(), at.z)
	for i in 90:
		await get_tree().physics_frame
	await look(truck.global_position + Vector3(-7, 3, 4), truck.global_position + Vector3(0, 1, -1))
	await snap("ladder")

func shot_bike() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var bike := Hauler.new()
	bike.setup(world.manager, 0, &"dirtbike")
	bike.terrain = world.terrain
	world.add_child(bike)
	var at := Vector3(20, 0, 30)
	bike.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + bike.spawn_height(), at.z)
	for i in 90:
		await get_tree().physics_frame
	await look(bike.global_position + Vector3(-3, 1.5, 1.5), bike.global_position)
	await snap("bike")
