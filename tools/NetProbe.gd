extends Node

## Co-op end to end, as two real games talking over localhost. Run the host,
## then the guest:
##   godot --headless --path . scenes/net_probe.tscn -- --host
##   godot --headless --path . scenes/net_probe.tscn -- --join
## Each checks its side and prints PASS or FAIL lines, then quits.

const PORT := 24599
var world: World
var failures: int = 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--host"):
		await _host()
	else:
		await _join()
	print("NETPROBE %s: %s" % ["HOST" if args.has("--host") else "GUEST", "PASS" if failures == 0 else "FAIL (%d)" % failures])
	Net.leave()
	get_tree().quit(1 if failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1

func _load_world() -> void:
	world = load("res://scenes/world.tscn").instantiate()
	world.autosave = false
	add_child(world)
	await get_tree().physics_frame

func _host() -> void:
	_check(Net.host(PORT) == "", "the host opened its port")
	await _load_world()
	var start_money := Economy.money
	# The whole base goes to the guest: more land than at the start, and a
	# bin with something in it.
	world.plot._apply_expansion(mini(2, GameData.max_expansion_tier()))
	var bin := world.plot.place(GameData.building(&"storage"), Vector2i(-40, -40), Vector3i.ZERO, false) as StorageBin
	_check(bin != null, "the host put up a storage bin")
	if bin != null:
		bin.contents.append({"id": &"wood_pine", "dims": Solid.cylinder(0.1, 0.1, 1.0), "owned": true})
	var built_before := world.plot.placed.size()
	# Wait for a guest to arrive and look round.
	var t := 0.0
	while world.guests.is_empty() and t < 90.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(world.guests.size() == 1, "a guest joined (%d)" % world.guests.size())
	if world.guests.is_empty():
		return
	var guest: Player = world.guests.values()[0]
	_check(guest.avatar != null and guest.avatar.ready_to_draw() and guest.avatar._label != null,
		"the guest is drawn here as the lumberjack, with their name over him")
	var placeholders := 0
	for c in guest.get_children():
		if c is Avatar:
			placeholders += 1
	_check(placeholders == 0, "no stand-in figure on the guest's player (%d)" % placeholders)
	var from := guest.global_position
	# The guest walks forward for a while (it presses W at its end).
	t = 0.0
	while guest.global_position.distance_to(from) < 2.0 and t < 30.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(guest.global_position.distance_to(from) > 2.0,
		"the guest's player walked on the host (%.1f m)" % guest.global_position.distance_to(from))
	# The purse is shared: money earned here is the guest's money too.
	await get_tree().create_timer(2.0).timeout
	Economy.add_money(12345)
	# Tools are not: this one is the guest's alone.
	guest.kit.give_tool(&"steel_axe")
	_check(not PlayerState.owns_tool(&"steel_axe"), "the guest's new axe is not the host's")
	t = 0.0
	while guest.selected_slot != 0 and t < 40.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(guest.selected_slot == 0, "the guest's key press picked a tool on the host (slot %d)" % guest.selected_slot)
	# The host's own number keys are the host's: the guest's hand stays put.
	var three := InputEventKey.new()
	three.keycode = KEY_3
	three.physical_keycode = KEY_3
	three.pressed = true
	Input.parse_input_event(three)
	await get_tree().create_timer(0.3).timeout
	_check(guest.selected_slot == 0, "the host's key 3 left the guest's hand alone (slot %d)" % guest.selected_slot)
	# The guest builds a bin on the host's land.
	t = 0.0
	while world.plot.placed.size() == built_before and t < 30.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(world.plot.placed.size() > built_before, "the guest's building went up on the host")
	# A log at the guest's feet: they pick it up (right mouse, at their end),
	# once they have seen the tool in hand and the hand is emptied again.
	await get_tree().create_timer(4.0).timeout
	guest.select_slot(0)
	var log_piece := world.manager.spawn(&"wood_pine", Transform3D(Basis(), guest.global_position + Vector3(0.8, 0.4, 0)),
		0, Vector3.ZERO, Solid.cylinder(0.1, 0.1, 1.0), true)
	t = 0.0
	while log_piece.state != LooseItem.State.HELD and t < 30.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(log_piece.state == LooseItem.State.HELD, "the guest picked up a log on the host")
	# A truck beside them: they get in, drive off, get out.
	var truck := Hauler.new()
	truck.setup(world.manager, 0, &"pickup")
	truck.terrain = world.terrain
	world.add_child(truck)
	var at := guest.global_position + Vector3(3.5, 0, 0)
	truck.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + truck.spawn_height(), at.z)
	world.hauler = truck
	t = 0.0
	while not guest.driving() and t < 40.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(guest.driving() and truck.driver == guest, "the guest got into the truck")
	var parked := truck.global_position
	t = 0.0
	while truck.global_position.distance_to(parked) < 4.0 and t < 30.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(truck.global_position.distance_to(parked) >= 4.0, "the guest drove the truck (%.1f m)" % truck.global_position.distance_to(parked))
	t = 0.0
	while guest.driving() and t < 30.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(not guest.driving() and truck.driver == null, "the guest got out")
	# Hold on until the guest has checked its side and gone.
	t = 0.0
	while not world.guests.is_empty() and t < 60.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(world.guests.is_empty(), "the guest's player went when the guest left")
	Economy.from_dict({"money": start_money})

func _join() -> void:
	# As the menu does it: connect, and only then build the world as a guest's.
	var joined := false
	for attempt in 20:
		Net.join("127.0.0.1", PORT)
		var result := [0]
		var ok_cb := func(): result[0] = 1
		var fail_cb := func(_r: String): result[0] = -1
		Net.joined.connect(ok_cb, CONNECT_ONE_SHOT)
		Net.join_failed.connect(fail_cb, CONNECT_ONE_SHOT)
		var t := 0.0
		while result[0] == 0 and t < 8.0:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
		for pair in [[Net.joined, ok_cb], [Net.join_failed, fail_cb]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
		if result[0] == 1:
			joined = true
			break
		Net.leave()
		await get_tree().create_timer(1.0).timeout
	_check(joined, "the guest connected to the host")
	if not joined:
		return
	# Nothing of this player's own game comes along.
	PlayerState.give_tool(&"goldleaf_axe", false)
	Economy.from_dict({"money": 987654})
	# A long, blocking build with the connection open: it must survive it.
	await _load_world()
	_check(not PlayerState.owns_tool(&"goldleaf_axe") and Economy.money != 987654,
		"this player's own tools and money stayed at home")
	_check(Net.is_client() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		"still connected after building the world")
	var client: NetClient = world.net_client
	_check(client != null, "the guest's world is in guest mode")
	# The world arrives.
	var t := 0.0
	while client._me < 0 and t < 30.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(client._me >= 0, "the host said which player is this one")
	await get_tree().create_timer(2.0).timeout
	var kinds := {}
	for id in client._kinds:
		kinds[client._kinds[id]] = int(kinds.get(client._kinds[id], 0)) + 1
	print("    guest sees: ", kinds)
	_check(int(kinds.get("t", 0)) >= 20, "the guest sees the host's trees (%d)" % int(kinds.get("t", 0)))
	_check(int(kinds.get("r", 0)) >= 10, "the guest sees the host's rocks (%d)" % int(kinds.get("r", 0)))
	_check(int(kinds.get("p", 0)) >= 2, "the guest sees both players (%d)" % int(kinds.get("p", 0)))
	var avatars := 0
	for id in client._nodes:
		if client._nodes[id] is Avatar:
			avatars += 1
	_check(avatars == 1, "the host's player is drawn as a person here (%d)" % avatars)
	var lumberjacks := 0
	for id in client._nodes:
		var av := client._nodes[id] as Avatar
		if av != null and av.body != null and av.body.ready_to_draw():
			lumberjacks += 1
	_check(lumberjacks == 1, "the host's player is the lumberjack here (%d)" % lumberjacks)
	var want_tier := mini(2, GameData.max_expansion_tier())
	_check(world.plot.tier == want_tier, "the host's land size came across (tier %d, want %d)" % [world.plot.tier, want_tier])
	var bins := 0
	for rec in world.plot.placed:
		if rec.node is StorageBin and not (rec.node as StorageBin).contents.is_empty():
			bins += 1
	_check(bins >= 1, "what is in the host's bin came across (%d)" % bins)
	# Walk forward: the host moves this player, and this view follows.
	var money_before := Economy.money
	var from := world.player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.5).timeout
	_check(world.player.global_position.distance_to(from) > 2.0,
		"this player walked here (%.1f m)" % world.player.global_position.distance_to(from))
	# The shared purse: the host adds money once it has seen the walk.
	var saw := false
	t = 0.0
	while t < 15.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		if Economy.money >= money_before + 12345 - 1:
			saw = true
			break
	_check(saw, "money the host earned shows here (%d -> %d)" % [money_before, Economy.money])
	t = 0.0
	while not PlayerState.owns_tool(&"steel_axe") and t < 5.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(PlayerState.owns_tool(&"steel_axe"), "the axe the host gave this player is in its own inventory")
	# Build a bin: the host puts it up, and here it is solid.
	var def := GameData.building(&"storage")
	client.send_build({"op": "place", "def": "storage", "tier": 1, "size": [def.size.x, def.size.y, def.size.z],
		"cell": [-20, -40], "rot": [0, 0, 0]})
	var bin_node: Node3D = null
	t = 0.0
	while bin_node == null and t < 15.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		for id in client._kinds:
			if client._kinds[id] == "b" and client._nodes[id] is StorageBin \
					and (client._nodes[id] as StorageBin).contents.is_empty():
				bin_node = client._nodes[id]
	_check(bin_node != null, "the bin this player built showed up here")
	if bin_node != null:
		await get_tree().physics_frame
		var top := bin_node.global_position + Vector3(0.3, 8.0, 0.3)
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 12.0, Layers.MACHINE)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
		var solid := false
		var n: Node = hit.get("collider") as Node
		while n != null:
			if n == bin_node:
				solid = true
				break
			n = n.get_parent()
		_check(solid, "the bin is solid here")
	# A key press, acted on by the host: 1 picks the first tool.
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.physical_keycode = KEY_1
	key.pressed = true
	client.send_press(key)
	t = 0.0
	while world.player.selected_slot != 0 and t < 5.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(world.player.selected_slot == 0, "the host's answer to pressing 1 came back (slot %d)" % world.player.selected_slot)
	# The host puts a log at our feet: pick it up.
	t = 0.0
	while world.player.carried_count() == 0 and t < 20.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		rmb.pressed = true
		client.send_press(rmb)
	_check(world.player.carried_count() == 1, "the log is on this player's rack (%d)" % world.player.carried_count())
	# The host parks a truck by us: F to get in.
	var truck: Hauler = null
	t = 0.0
	while truck == null and t < 30.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		for id in client._kinds:
			if client._kinds[id] == "v":
				truck = client._nodes[id]
	_check(truck != null, "the host's truck showed up here")
	if truck == null:
		return
	await get_tree().create_timer(1.5).timeout
	t = 0.0
	while not world.player.driving() and t < 20.0:
		client.send_press(_key(KEY_F))
		await get_tree().create_timer(1.0).timeout
		t += 1.0
	_check(world.player.driving() and world.player.vehicle == truck, "this player is in the truck here too")
	var from_truck := truck.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(4.0).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(1.0).timeout
	_check(truck.global_position.distance_to(from_truck) > 4.0,
		"the truck drove off here too (%.1f m)" % truck.global_position.distance_to(from_truck))
	var sits := world.player.global_position.distance_to(truck.global_position) < 4.0
	_check(sits, "this player rode along in the truck")
	_check(truck.net_mirror, "the truck was driven here, not on the host")
	# Recovering it, from the seat: done on the host, and here too.
	var low := truck.global_position.y
	var rec_key := InputEventKey.new()
	for e in InputMap.action_get_events(&"recover"):
		if e is InputEventKey:
			rec_key.keycode = (e as InputEventKey).keycode
			rec_key.physical_keycode = (e as InputEventKey).physical_keycode
			if rec_key.keycode == KEY_NONE:
				rec_key.keycode = rec_key.physical_keycode
			break
	rec_key.pressed = true
	client.send_press(rec_key)
	var rose := 0.0
	t = 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		rose = maxf(rose, truck.global_position.y - low)
	_check(rose > 0.8, "recovering the truck lifted it here too (%.2f m)" % rose)
	client.send_press(_key(KEY_F))
	t = 0.0
	while world.player.driving() and t < 10.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(not world.player.driving(), "out of the truck again")
	await get_tree().create_timer(1.0).timeout

static func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	return key
