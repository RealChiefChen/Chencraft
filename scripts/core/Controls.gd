class_name Controls
extends RefCounted

## Every key and mouse button the game answers to, by what it does rather than
## where it is. Each action has default bindings; the player can rebind any of
## them (Settings > Controls, or by editing the [controls] section of their
## config file), and everything that reads input asks for the action - so a
## rebound key works everywhere at once, and the prompts and the key guide show
## the new key.
##
## A binding is written the way it is shown: "W", "Shift", "Ctrl", "Space",
## "Tab", "Esc", "F5", "LMB", "RMB", "MMB", "WheelUp", "WheelDown", and a
## modifier combo as "Shift+E". An action can have several, comma separated.

## [id, label, group, default bindings]. Order matters twice: it is the order
## the settings page lists them in, and when a prompt says "[E]" the first
## action here bound to E by default is the one whose key is shown.
const ACTIONS := [
	# Moving
	[&"move_forward", "Forward", "Moving", ["W"]],
	[&"move_back", "Back", "Moving", ["S"]],
	[&"move_left", "Left", "Moving", ["A"]],
	[&"move_right", "Right", "Moving", ["D"]],
	[&"jump", "Jump / brake", "Moving", ["Space"]],
	[&"sprint", "Sprint / up", "Moving", ["Shift"]],
	[&"lower", "Down", "Moving", ["Ctrl"]],
	# Hands and tools
	[&"primary", "Use tool / drag / place", "Hands and tools", ["LMB"]],
	[&"secondary", "Pick up / throw / remove / fine crane", "Hands and tools", ["RMB"]],
	[&"use", "Use: deposit, sell, pay, open", "Hands and tools", ["E"]],
	[&"drop_one", "Drop one piece", "Hands and tools", ["Q"]],
	[&"drop_all", "Drop everything / reel in (seated)", "Hands and tools", ["G"]],
	[&"throw", "Throw: the piece in hand, or the top one off the rack", "Hands and tools", ["V"]],
	[&"turn_ccw", "Turn held piece / crane log / tip bucket", "Hands and tools", ["Q"]],
	[&"turn_cw", "Turn held piece / crane log / curl bucket", "Hands and tools", ["E"]],
	[&"wheel_up", "Closer / previous / zoom in", "Hands and tools", ["WheelUp"]],
	[&"wheel_down", "Further / next / zoom out", "Hands and tools", ["WheelDown"]],
	[&"machine_output", "Machine: change output size", "Hands and tools", ["R"]],
	[&"slot_1", "Hotbar 1", "Hands and tools", ["1"]],
	[&"slot_2", "Hotbar 2", "Hands and tools", ["2"]],
	[&"slot_3", "Hotbar 3", "Hands and tools", ["3"]],
	[&"slot_4", "Hotbar 4", "Hands and tools", ["4"]],
	[&"slot_5", "Hotbar 5", "Hands and tools", ["5"]],
	[&"slot_6", "Hotbar 6", "Hands and tools", ["6"]],
	[&"slot_7", "Hotbar 7", "Hands and tools", ["7"]],
	[&"slot_8", "Hotbar 8", "Hands and tools", ["8"]],
	[&"slot_9", "Hotbar 9", "Hands and tools", ["9"]],
	# Build mode
	[&"build_mode", "Build mode on / off", "Build mode", ["B"]],
	[&"build_menu", "Build menu", "Build mode", ["E"]],
	[&"pick_block", "Copy the building you aim at", "Build mode", ["MMB"]],
	[&"edit_select", "Select a building to edit", "Build mode", ["F"]],
	[&"rotate_x", "Rotate about X", "Build mode", ["Z"]],
	[&"rotate_y", "Rotate about Y", "Build mode", ["X"]],
	[&"rotate_z", "Rotate about Z", "Build mode", ["C"]],
	[&"remove_selected", "Remove the selected building", "Build mode", ["Delete", "Backspace"]],
	# Driving
	[&"enter_vehicle", "Get in / get out / crane claw", "Driving", ["F"]],
	[&"hitch", "Hitch / unhitch a trailer", "Driving", ["T"]],
	[&"unload", "Unload the bed", "Driving", ["X"]],
	[&"unload_one", "Drop one off the back", "Driving", ["Z"]],
	[&"recover", "Recover (set upright)", "Driving", ["C"]],
	[&"gear_up", "Gear up (manual gearbox)", "Driving", ["Shift"]],
	[&"gear_down", "Gear down (manual gearbox)", "Driving", ["Ctrl"]],
	# Crane, winch and loader
	[&"winch_hook", "Winch: hook on / unhook", "Crane, winch and loader", ["Y"]],
	[&"winch_in", "Winch: reel in", "Crane, winch and loader", ["K"]],
	[&"winch_out", "Winch: let out", "Crane, winch and loader", ["L"]],
	[&"outriggers", "Outriggers out / in", "Crane, winch and loader", ["O"]],
	[&"crane", "Crane: work it / stow it", "Crane, winch and loader", ["R"]],
	[&"rig_home", "Crane or loader: back to start", "Crane, winch and loader", ["N"]],
	[&"loader_lock", "Loader: lock / unlock the load", "Crane, winch and loader", ["Space"]],
	# Menus and game
	[&"journal", "Journal", "Menus and game", ["Tab", "J"]],
	[&"inventory", "Inventory", "Menus and game", ["I"]],
	[&"map", "Map", "Menus and game", ["M"]],
	[&"map_zoom_in", "Map and minimap: zoom in", "Menus and game", ["Equal"]],
	[&"map_zoom_out", "Map and minimap: zoom out", "Menus and game", ["Minus"]],
	[&"market", "Market", "Menus and game", ["P"]],
	[&"upgrades", "Upgrades", "Menus and game", ["U"]],
	[&"help", "Controls list", "Menus and game", ["F1"]],
	[&"toggle_hints", "Show / hide key hints and the crane banner", "Menus and game", ["H"]],
	[&"camera_view", "First / third person view", "Menus and game", ["V"]],
	[&"debug", "Debug readout", "Menus and game", ["F3"]],
	[&"quick_save", "Quick save", "Menus and game", ["F5"]],
	[&"quick_load", "Quick load", "Menus and game", ["F9"]],
	[&"new_game", "New game", "Menus and game", ["F8"]],
	[&"pause", "Pause / back", "Menus and game", ["Esc"]],
]

const MOUSE_NAMES := {"LMB": MOUSE_BUTTON_LEFT, "RMB": MOUSE_BUTTON_RIGHT, "MMB": MOUSE_BUTTON_MIDDLE,
	"WheelUp": MOUSE_BUTTON_WHEEL_UP, "WheelDown": MOUSE_BUTTON_WHEEL_DOWN,
	"Mouse4": MOUSE_BUTTON_XBUTTON1, "Mouse5": MOUSE_BUTTON_XBUTTON2}
## Friendlier names than the engine's for a few keys, both ways round.
const KEY_ALIASES := {"Esc": "Escape", "Del": "Delete", "Control": "Ctrl", "Return": "Enter"}
const DISPLAY := {"Escape": "Esc", "Delete": "Del"}

## action -> Array of binding labels.
static var bindings: Dictionary = {}
## Default label -> the action whose key a "[label]" in a prompt means.
static var _meaning: Dictionary = {}
static var _ready_once: bool = false

static func defaults() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		var labels: Array = []
		for label in a[3]:
			labels.append(normalise(String(label)))
		out[a[0]] = labels
	return out

static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in ACTIONS:
		out.append(a[0])
	return out

static func info(action: StringName) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			return a
	return []

## Registers every action with the engine at its current binding. Safe to call
## again: an action's events are replaced, not added to.
static func ensure() -> void:
	if not _ready_once:
		_ready_once = true
		if bindings.is_empty():
			bindings = defaults()
		_meaning.clear()
		for a in ACTIONS:
			for label in a[3]:
				var norm := normalise(String(label))
				if not _meaning.has(norm):
					_meaning[norm] = a[0]
	for a in ACTIONS:
		var id: StringName = a[0]
		if not InputMap.has_action(id):
			InputMap.add_action(id, 0.2)
		InputMap.action_erase_events(id)
		for label in bindings.get(id, a[3]):
			var ev := event_for(String(label))
			if ev != null:
				InputMap.action_add_event(id, ev)
	# The old names some code and tests still use.
	for pair in [[&"reel", &"drop_all"]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.2)
		InputMap.action_erase_events(pair[0])
		for ev in InputMap.action_get_events(pair[1]):
			InputMap.action_add_event(pair[0], ev)

## Sets the bindings (from the config file). Unknown actions are ignored and
## missing ones keep their defaults.
static func apply(from: Dictionary) -> void:
	bindings = defaults()
	for id in from:
		var key := StringName(id)
		if not bindings.has(key):
			continue
		var labels: Array = []
		var raw: Variant = from[id]
		var parts: Array = raw if raw is Array else String(raw).split(",", false)
		for p in parts:
			var label := normalise(String(p))
			if label != "" and event_for(label) != null:
				labels.append(label)
		bindings[key] = labels
	_ready_once = false
	ensure()

static func set_binding(action: StringName, labels: Array) -> void:
	if bindings.is_empty():
		bindings = defaults()
	bindings[action] = labels.duplicate()
	ensure()

static func reset() -> void:
	bindings = defaults()
	ensure()

static func to_dict() -> Dictionary:
	if bindings.is_empty():
		bindings = defaults()
	var out := {}
	for a in ACTIONS:
		out[String(a[0])] = ", ".join(PackedStringArray(bindings.get(a[0], [])))
	return out

# --- Events ---------------------------------------------------------------------

## The engine event for a binding label, or null if it does not name one.
static func event_for(label: String) -> InputEvent:
	label = normalise(label)
	if label == "":
		return null
	if MOUSE_NAMES.has(label):
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_NAMES[label]
		mb.pressed = true
		return mb
	var parts := label.split("+")
	var key_name := parts[parts.size() - 1]
	var code := _keycode(key_name)
	if code == KEY_NONE:
		return null
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	for i in parts.size() - 1:
		match parts[i]:
			"Shift": ev.shift_pressed = true
			"Ctrl": ev.ctrl_pressed = true
			"Alt": ev.alt_pressed = true
	return ev

static func _keycode(name: String) -> Key:
	var engine_name := name
	for alias in KEY_ALIASES:
		if String(alias).to_lower() == name.to_lower():
			engine_name = KEY_ALIASES[alias]
	return OS.find_keycode_from_string(engine_name)

## A label in the house style: "shift" -> "Shift", "esc" -> "Esc".
static func normalise(label: String) -> String:
	label = label.strip_edges()
	if label == "":
		return ""
	for m in MOUSE_NAMES:
		if String(m).to_lower() == label.to_lower():
			return m
	var parts := label.split("+")
	var out: Array[String] = []
	for p in parts:
		var code := _keycode(String(p).strip_edges())
		if code == KEY_NONE:
			return ""
		out.append(label_for_key(code))
	return "+".join(out)

## How a key is written on a keycap.
static func label_for_key(code: Key) -> String:
	var s := OS.get_keycode_string(code)
	return String(DISPLAY.get(s, s))

## The label for an event the player just pressed, to bind it; "" for events
## that cannot be bound (mouse motion, a modifier on its own is fine).
static func label_for_event(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		for m in MOUSE_NAMES:
			if MOUSE_NAMES[m] == (event as InputEventMouseButton).button_index:
				return m
		return ""
	var key := event as InputEventKey
	if key == null:
		return ""
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_NONE:
		return ""
	var base := label_for_key(code)
	var mods: Array[String] = []
	if code != KEY_SHIFT and key.shift_pressed:
		mods.append("Shift")
	if code != KEY_CTRL and key.ctrl_pressed:
		mods.append("Ctrl")
	if code != KEY_ALT and key.alt_pressed:
		mods.append("Alt")
	mods.append(base)
	return "+".join(mods)

# --- Asking -----------------------------------------------------------------------

## Was this event a fresh press of `action`? Echoes (a key held down) do not count.
static func pressed(event: InputEvent, action: StringName) -> bool:
	if event == null or not InputMap.has_action(action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return false
	return event.is_action_pressed(action, false, false)

static func released(event: InputEvent, action: StringName) -> bool:
	if event == null or not InputMap.has_action(action):
		return false
	return event.is_action_released(action, false)

## Is `action` held down right now?
static func held(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)

## -1..1 from a pair of actions.
static func axis(negative: StringName, positive: StringName) -> float:
	return (1.0 if held(positive) else 0.0) - (1.0 if held(negative) else 0.0)

## Which hotbar slot (0-8) this event picks, or -1.
static func slot_pressed(event: InputEvent) -> int:
	for i in 9:
		if pressed(event, StringName("slot_%d" % (i + 1))):
			return i
	return -1

# --- Showing ----------------------------------------------------------------------

## The key an action is on, for a keycap: its first binding, or "-" unbound.
static func key(action: StringName) -> String:
	if bindings.is_empty():
		bindings = defaults()
	var labels: Array = bindings.get(action, [])
	return String(labels[0]) if not labels.is_empty() else "-"

## Every key an action is on, joined for a label.
static func keys_text(action: StringName) -> String:
	var labels: Array = bindings.get(action, [])
	return " / ".join(PackedStringArray(labels)) if not labels.is_empty() else "unbound"

## A keycap label from a prompt, "[E]", shown as whatever key now does that
## job. Anything that is not a default binding is shown as written.
static func remap_label(label: String) -> String:
	if bindings.is_empty() or _meaning.is_empty():
		ensure()
	var parts := label.split("/")
	var out: Array[String] = []
	for p in parts:
		var combo := String(p).split("+")
		var shown: Array[String] = []
		for c in combo:
			var s := String(c).strip_edges()
			var norm := normalise(s)
			var action: Variant = _meaning.get(norm, null)
			if norm != "" and action != null:
				shown.append(key(action))
			else:
				shown.append(s)
		out.append("+".join(shown))
	return "/".join(out)
