class_name NetHost
extends Node

## The host's end of co-op. Each guest gets a real Player in this world,
## driven by the keys the guest presses; and everything in the world a guest
## has to see - loose pieces, trees, rocks, buildings, vehicles, players, the
## shared purse - is sent to them: what appears and goes and changes, reliably,
## and where the moving things are, many times a second.

const RATE := 20.0            ## motion updates a second
const STATE_EVERY := 4        ## state checks every this many motion updates
const ECON_EVERY := 20        ## money and unlocks, once a second
const VIEW_EVERY := 2         ## each guest's own prompt and hand
const WHEEL := 1 << 24        ## wheel poses ride on the vehicle's id plus this
const CHUNK := 32             ## poses per motion packet

var world: Node

var _ready_peers: Dictionary = {}     ## peer -> true, once its world is built
var _next_id: int = 1
var _ids: Dictionary = {}             ## key -> id
var _nodes: Dictionary = {}           ## id -> [node, kind, key]
var _state_hash: Dictionary = {}      ## id -> hash of the last state sent
var _poses: Dictionary = {}           ## id -> last pose sent
var _econ_hash: int = 0
var _tick: int = 0
var _acc: float = 0.0
var _outbox: Array = []               ## for every guest
var _mail: Dictionary = {}            ## peer -> [entries for them alone]

func _ready() -> void:
	Net.host_side = self
	# Guests keep being sent the world while the host sits in a menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100    # after the world has moved

func _exit_tree() -> void:
	if Net.host_side == self:
		Net.host_side = null

# --- Guests coming and going ---------------------------------------------------------

func on_guest_ready(peer: int, display: String) -> void:
	if OS.has_environment("NET_TRACE"):
		print("[host] guest ready ", peer, " ", display)
	var p: Player = world.call("add_guest", peer, display)
	_ready_peers[peer] = true
	# Everything there is, as it is, then who they are.
	var batch: Array = []
	for entry in _entities():
		var fresh := not _ids.has(entry[2])
		var id := _id_for(entry[0], entry[1], entry[2])
		_nodes[id] = entry
		var spawn := _spawn_entry(id, entry[0], entry[1])
		batch.append(spawn)
		if fresh:
			# New to everyone (this guest's own player, at least).
			_outbox.append(spawn)
		var st: Variant = _state_of(entry[0], entry[1])
		if st != null:
			batch.append({"t": "state", "id": id, "s": st})
	batch.append(_econ_entry())
	batch.append({"t": "you", "id": _ids.get(_key_of(p, "p"), -1)})
	if OS.has_environment("NET_TRACE"):
		print("[host] sending %d entries, %d bytes" % [batch.size(), var_to_bytes(batch).size()])
	Net.rpc_id(peer, "h_batch", batch)
	for q in _ready_peers:
		if q != peer:
			tell_peer(q, "%s joined" % display)
	world.call("_tell", world.get("player"), "%s joined" % display)

func on_guest_left(peer: int) -> void:
	_ready_peers.erase(peer)
	_mail.erase(peer)
	world.call("remove_guest", peer)

func on_guest_input(peer: int, state: Dictionary) -> void:
	var p := _guest(peer)
	if p == null:
		return
	p.input.apply(state)
	if state.has("yaw"):
		p.rotation.y = float(state.yaw)
	if state.has("pitch"):
		p.camera.rotation.x = clampf(float(state.pitch), -1.45, 1.45)

func on_guest_event(peer: int, ev: Dictionary) -> void:
	var p := _guest(peer)
	if p == null:
		return
	match String(ev.get("t", "")):
		"key":
			if int(ev.code) == KEY_B:
				tell_peer(peer, "building is done on the host's machine for now")
				return
			var k := InputEventKey.new()
			k.keycode = int(ev.code) as Key
			k.physical_keycode = int(ev.get("phys", ev.code)) as Key
			k.pressed = true
			p.remote_press(k)
			world.call("handle_key", p, k)
		"btn":
			var b := InputEventMouseButton.new()
			b.button_index = int(ev.b) as MouseButton
			b.pressed = true
			p.remote_press(b)
		"base":
			world.call("return_to_base", p)

func _guest(peer: int) -> Player:
	var guests: Dictionary = world.get("guests")
	var p: Variant = guests.get(peer, null)
	return p as Player if p != null and is_instance_valid(p) else null

## A message for one player: a guest's goes to their game.
func tell(p: Player, message: String) -> void:
	var guests: Dictionary = world.get("guests")
	for peer in guests:
		if guests[peer] == p:
			tell_peer(peer, message)
			return

func tell_peer(peer: int, message: String) -> void:
	if message == "":
		return
	if not _mail.has(peer):
		_mail[peer] = []
	(_mail[peer] as Array).append({"t": "msg", "m": message})

# --- What there is ---------------------------------------------------------------------

## Every replicated thing: [node, kind, key].
func _entities() -> Array:
	var out: Array = []
	var manager: LooseItemManager = world.get("manager")
	for item: LooseItem in manager._active:
		if is_instance_valid(item) and item.state != LooseItem.State.POOLED:
			out.append([item, "i", _key_of(item, "i")])
	for tree: ChoppableTree in world.call("trees"):
		if tree.has_meta("entry"):
			out.append([tree, "t", _key_of(tree, "t")])
	for rock: OreRock in world.call("rocks"):
		if rock.has_meta("entry") and not rock.consumed():
			out.append([rock, "r", _key_of(rock, "r")])
	var plot: Plot = world.get("plot")
	for rec in plot.placed:
		var node: Node3D = rec.node
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			out.append([rec, "b", _key_of(node, "b")])
	for v: Hauler in world.call("vehicles"):
		if not v.is_queued_for_deletion():
			out.append([v, "v", _key_of(v, "v")])
	for p: Player in world.call("players"):
		out.append([p, "p", _key_of(p, "p")])
	return out

## An identity that changes when a pooled piece is reused for a new one.
func _key_of(node: Object, kind: String) -> String:
	var n: Object = node
	var k := "%s%d" % [kind, n.get_instance_id()]
	if n is LooseItem:
		k += ":%d" % (n as LooseItem).spawn_index
	return k

func _id_for(_node: Variant, _kind: String, key: String) -> int:
	if _ids.has(key):
		return int(_ids[key])
	var id := _next_id
	_next_id += 1
	_ids[key] = id
	return id

func _spawn_entry(id: int, thing: Variant, kind: String) -> Dictionary:
	var e := {"t": "spawn", "id": id, "k": kind}
	match kind:
		"i":
			var item := thing as LooseItem
			e.item = String(item.item_id)
			e.dims = Solid.to_dict(item.dims)
			e.limbs = item.limbs_to_array()
			e.x = _pose(item.global_transform)
		"t", "r":
			var node := thing as Node3D
			e.entry = node.get_meta("entry")
			e.seed = int(node.get_meta("form_seed"))
			e.x = _pose(node.global_transform)
		"b":
			var rec: Dictionary = thing
			var def: BuildingDef = rec.def
			e.def = String(def.id)
			e.tier = def.tier
			e.size = [def.size.x, def.size.y, def.size.z]
			e.cell = [rec.cell.x, rec.cell.y]
			var r: Vector3i = rec.rot
			e.rot = [r.x, r.y, r.z]
			e.lift = float(rec.get("lift", 0.0))
		"v":
			var v := thing as Hauler
			e.veh = String(v.vehicle_id)
			e.x = _pose(v.global_transform)
		"p":
			var p := thing as Player
			var peer := _peer_of(p)
			e.peer = peer
			e.name = String(world.call("guest_name", peer)) if peer != 1 else Net.player_name
			e.x = _pose(p.global_transform)
	return e

func _peer_of(p: Player) -> int:
	var guests: Dictionary = world.get("guests")
	for peer in guests:
		if guests[peer] == p:
			return peer
	return 1

## What changes on a thing without it moving. Null for things with none.
func _state_of(thing: Variant, kind: String) -> Variant:
	match kind:
		"i":
			var item := thing as LooseItem
			return {"l": item.limbs_to_array()} if not item.limbs.is_empty() else {"l": []}
		"t":
			return (thing as ChoppableTree).net_state()
		"r":
			return (thing as OreRock).net_state()
		"b":
			var node: Node = (thing as Dictionary).node
			var run: Variant = node.get("running")
			return {"run": bool(run)} if run != null else null
		"v":
			var v := thing as Hauler
			var s := {"tub": v._tub_angle, "held": v.held}
			if v.rig != null:
				var r := v.rig
				s.rig = {"j": r.joints.duplicate(), "op": r.operating, "out": r.outriggers_down,
					"fold": r.folding, "anch": r.anchored, "ty": r.target_yaw, "tg": r.target}
			if v.loader != null:
				var l := v.loader
				s.ld = [l.lift, l.tilt, l.locked, l.thumb_angle]
			return s
		"p":
			var p := thing as Player
			var veh := -1
			if p.driving() and is_instance_valid(p.vehicle):
				veh = int(_ids.get(_key_of(p.vehicle, "v"), -1))
			return {"pitch": snappedf(p.camera.rotation.x, 0.05), "veh": veh, "tool": String(p.selected_tool())}
	return null

static func _pose(t: Transform3D) -> PackedFloat32Array:
	var q := t.basis.orthonormalized().get_rotation_quaternion()
	return PackedFloat32Array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])

func _econ_entry() -> Dictionary:
	var quests: Variant = world.get("quests")
	return {"t": "econ", "e": Economy.to_dict(), "p": PlayerState.to_dict(),
		"q": quests.call("to_dict") if quests != null else {}}

# --- Sending -------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _ready_peers.is_empty():
		return
	_acc += delta
	if _acc < 1.0 / RATE:
		return
	_acc = 0.0
	_tick += 1
	var ents := _entities()
	var seen: Dictionary = {}
	var ids := PackedInt32Array()
	var poses := PackedFloat32Array()
	var check_state := _tick % STATE_EVERY == 0
	for entry in ents:
		var key: String = entry[2]
		var fresh := not _ids.has(key)
		var id := _id_for(entry[0], entry[1], key)
		seen[id] = true
		if fresh:
			_nodes[id] = entry
			_outbox.append(_spawn_entry(id, entry[0], entry[1]))
		else:
			_nodes[id] = entry
		if fresh or check_state:
			var st: Variant = _state_of(entry[0], entry[1])
			if st != null:
				var h := hash(st)
				if fresh or int(_state_hash.get(id, 0)) != h:
					_state_hash[id] = h
					_outbox.append({"t": "state", "id": id, "s": st})
		_collect_motion(id, entry[0], entry[1], ids, poses)
	# Gone since last time.
	for id in _nodes.keys():
		if not seen.has(id):
			var key: String = _nodes[id][2]
			_nodes.erase(id)
			_ids.erase(key)
			_state_hash.erase(id)
			_poses.erase(id)
			_outbox.append({"t": "gone", "id": id})
	if _tick % ECON_EVERY == 0:
		var econ := _econ_entry()
		var h := hash([econ.e, econ.p, econ.q])
		if h != _econ_hash:
			_econ_hash = h
			_outbox.append(econ)
	if _tick % VIEW_EVERY == 0:
		for peer in _ready_peers:
			var p := _guest(peer)
			if p != null:
				if not _mail.has(peer):
					_mail[peer] = []
				(_mail[peer] as Array).append(_view_of(p))
	for peer in _ready_peers:
		var batch: Array = _outbox.duplicate()
		if _mail.has(peer):
			batch.append_array(_mail[peer])
		if not batch.is_empty():
			Net.rpc_id(peer, "h_batch", batch)
		# Motion in packets small enough never to be split.
		if OS.has_environment("NET_TRACE") and _tick % 200 == 0:
			print("[host] tick %d motion %d outbox %d guest at %s" % [_tick, ids.size(), batch.size(), _guest(peer).global_position if _guest(peer) != null else Vector3.ZERO])
		var i := 0
		while i < ids.size():
			var n := mini(CHUNK, ids.size() - i)
			Net.rpc_id(peer, "h_motion", ids.slice(i, i + n), poses.slice(i * 7, (i + n) * 7), _tick)
			i += n
	_outbox.clear()
	_mail.clear()

func _collect_motion(id: int, thing: Variant, kind: String, ids: PackedInt32Array, poses: PackedFloat32Array) -> void:
	match kind:
		"i", "p":
			_moved(id, (thing as Node3D).global_transform, ids, poses)
		"v":
			var v := thing as Hauler
			_moved(id, v.global_transform, ids, poses)
			for w in v.wheel_bodies.size():
				_moved(id + WHEEL * (w + 1), v.wheel_bodies[w].global_transform, ids, poses)

## Adds a pose if it has changed since it was last sent.
func _moved(id: int, t: Transform3D, ids: PackedInt32Array, poses: PackedFloat32Array) -> void:
	var p := _pose(t)
	var last: Variant = _poses.get(id, null)
	if last != null:
		var l: PackedFloat32Array = last
		var dp := Vector3(p[0] - l[0], p[1] - l[1], p[2] - l[2]).length()
		var dq := absf(p[3] * l[3] + p[4] * l[4] + p[5] * l[5] + p[6] * l[6])
		if dp < 0.004 and dq > 0.99995:
			return
	_poses[id] = p
	ids.append(id)
	poses.append_array(p)

## A guest's own player: what their HUD shows.
func _view_of(p: Player) -> Dictionary:
	var veh := -1
	if p.driving() and is_instance_valid(p.vehicle):
		veh = int(_ids.get(_key_of(p.vehicle, "v"), -1))
	return {"t": "view", "prompt": p.last_prompt, "slot": p.selected_slot, "veh": veh,
		"carry": [p.carried_count(), p.carried_volume()], "drag": p.dragged != null}
