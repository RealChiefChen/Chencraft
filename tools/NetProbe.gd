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
	# Wait for a guest to arrive and look round.
	var t := 0.0
	while world.guests.is_empty() and t < 90.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(world.guests.size() == 1, "a guest joined (%d)" % world.guests.size())
	if world.guests.is_empty():
		return
	var guest: Player = world.guests.values()[0]
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
	t = 0.0
	while guest.selected_slot != 0 and t < 40.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(guest.selected_slot == 0, "the guest's key press picked a tool on the host (slot %d)" % guest.selected_slot)
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
	# A long, blocking build with the connection open: it must survive it.
	await _load_world()
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
	# Walk forward: the host moves this player, and this view follows.
	var money_before := Economy.money
	var from := world.player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.5).timeout
	_check(world.player.global_position.distance_to(from) > 2.0,
		"this player moved where the host walked it (%.1f m)" % world.player.global_position.distance_to(from))
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
