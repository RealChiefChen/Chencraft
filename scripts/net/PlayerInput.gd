class_name PlayerInput
extends RefCounted

## What one player is pressing. Locally it reads the keyboard and mouse; for a
## co-op guest on the host it holds whatever that guest's game last sent, so
## the same Player code drives either.

## True for a guest's player on the host: the state below is theirs.
var remote: bool = false

## Held input-map actions, physical keys and mouse buttons (remote only).
var actions: Dictionary = {}
var keys: Dictionary = {}
var buttons: Dictionary = {}
## Actions that went down since the last physics frame (remote only).
var _just: Dictionary = {}

func pressed(action: StringName) -> bool:
	if remote:
		return actions.has(action)
	return Input.is_action_pressed(action)

func just_pressed(action: StringName) -> bool:
	if remote:
		return _just.has(action)
	return Input.is_action_just_pressed(action)

func axis(negative: StringName, positive: StringName) -> float:
	if remote:
		return (1.0 if actions.has(positive) else 0.0) - (1.0 if actions.has(negative) else 0.0)
	return Input.get_axis(negative, positive)

func key(code: Key) -> bool:
	if remote:
		return keys.has(int(code))
	return Input.is_physical_key_pressed(code)

func mouse(button: MouseButton) -> bool:
	if remote:
		return buttons.has(int(button))
	return Input.is_mouse_button_pressed(button)

## The held state, as a guest sends it: what the host needs every frame.
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint",
	&"lower", &"winch_in", &"winch_out", &"reel"]
const KEYS := [KEY_Q, KEY_E]

static func capture() -> Dictionary:
	var a: Array = []
	for action in ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			a.append(String(action))
	var k: Array = []
	for code in KEYS:
		if Input.is_physical_key_pressed(code):
			k.append(int(code))
	var b: Array = []
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if Input.is_mouse_button_pressed(button):
			b.append(int(button))
	return {"a": a, "k": k, "b": b}

## Takes a guest's latest held state.
func apply(state: Dictionary) -> void:
	var now: Dictionary = {}
	for a in state.get("a", []):
		now[StringName(a)] = true
	for a in now:
		if not actions.has(a):
			_just[a] = true
	actions = now
	keys.clear()
	for k in state.get("k", []):
		keys[int(k)] = true
	buttons.clear()
	for b in state.get("b", []):
		buttons[int(b)] = true

## Called after each physics frame: "just pressed" lasts one frame.
func end_frame() -> void:
	_just.clear()
