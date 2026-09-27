extends Node

## Player preferences: kept apart from the save, because a new game should not
## throw away your mouse sensitivity. Autoloaded as `Settings`.
##
## They live in one personal config file, `user://config.cfg`, together with
## the key bindings: every primary setting and every control, each with a
## comment saying what it is, so it can be read and edited by hand as easily as
## from the Settings screen. (On Windows that is
## %APPDATA%/Godot/app_userdata/Pinecraft/config.cfg; Settings has a button that
## opens the folder.)
##
## Anything that reads a setting either asks for it when it needs it (mouse
## look) or listens to `changed` (the camera, the sun, the environment), so a
## slider moved in the pause menu shows its effect with the menu still open.

signal changed(key: StringName)
signal controls_changed

const PATH := "user://config.cfg"
## Where settings were kept before there was one config file; read once if the
## new file is not there yet.
const LEGACY_PATH := "user://settings.cfg"
const SECTION := "settings"
const CONTROLS := "controls"

## Every setting and its default. The type of the default is the type of the
## setting; `set_value` coerces to it.
const DEFAULTS := {
	# Controls
	&"mouse_sensitivity": 1.0,
	&"invert_y": false,
	&"fov": 75.0,
	&"manual_gearbox": false,
	&"toggle_sprint": false,
	# Video
	&"fullscreen": false,
	&"vsync": true,
	&"render_scale": 1.0,
	&"shadows": 2,            ## 0 off, 1 low, 2 high
	&"ambient_occlusion": true,
	&"bloom": true,
	&"view_distance": 600.0,
	&"moving_sun": true,
	# Interface
	&"ui_scale": 1.0,
	&"show_hints": true,
	&"show_rig_banner": true,
	&"minimap": true,
	&"minimap_zoom": 1,       ## 0 close .. 3 far
	&"minimap_rotate": false,
	&"show_compass": true,
	&"show_tutorial": true,
	&"show_fps": false,
	&"show_labels": false,
	# Game
	&"autosave": true,
	# Debug
	&"unlimited_money": false,
	&"demo_lines": false,
}

## What each setting is, for the comments in the config file.
const NOTES := {
	&"mouse_sensitivity": "Mouse look speed, 0.2 to 3.0",
	&"invert_y": "true to invert the mouse's up and down",
	&"fov": "Field of view in degrees, 60 to 100",
	&"toggle_sprint": "true: tap sprint to run until you tap it again or stop. false: hold it",
	&"manual_gearbox": "true: trucks change gear only when you do (gear up / gear down keys). false: automatic",
	&"fullscreen": "true for fullscreen",
	&"vsync": "true to sync to the monitor",
	&"render_scale": "3D resolution as a share of the window, 0.5 to 1.0",
	&"shadows": "0 off, 1 low, 2 high",
	&"ambient_occlusion": "Screen-space ambient occlusion",
	&"bloom": "Glow round bright things",
	&"view_distance": "How far you can see, in metres (150 to 1200)",
	&"moving_sun": "false keeps it mid-morning all day",
	&"ui_scale": "Interface size, 0.75 to 1.5",
	&"show_hints": "Key hints in the bottom-right corner",
	&"show_rig_banner": "The crane / winch / loader controls banner while driving",
	&"minimap": "The minimap under the money",
	&"minimap_zoom": "Minimap zoom, 0 (closest) to 3 (furthest)",
	&"minimap_rotate": "true: the minimap turns with you, what is ahead at the top. false: north up",
	&"show_compass": "The compass along the top",
	&"show_tutorial": "The getting-started checklist",
	&"show_fps": "Frame rate readout",
	&"show_labels": "Floating name labels over placed buildings",
	&"autosave": "Save every minute while playing",
	&"unlimited_money": "Debug: buying costs nothing",
	&"demo_lines": "Debug: automated demo lines south of home",
}

## Where the settings live. Tests point this somewhere disposable.
var path: String = PATH
var _values: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from(path)
	apply_display()

func value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))

func set_value(key: StringName, v: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key %s" % key)
		return
	var coerced: Variant = _coerce(DEFAULTS[key], v)
	if _values.get(key) == coerced:
		return
	_values[key] = coerced
	if key in [&"fullscreen", &"vsync", &"render_scale", &"ui_scale"]:
		apply_display()
	changed.emit(key)
	if persist:
		save_to(path)

func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate()
	apply_display()
	for key in DEFAULTS:
		changed.emit(key)
	save_to(path)

## Puts every key back where it started, and saves.
func reset_controls() -> void:
	Controls.reset()
	controls_changed.emit()
	save_to(path)

## Rebinds one action and saves.
func bind(action: StringName, labels: Array) -> void:
	Controls.set_binding(action, labels)
	controls_changed.emit()
	save_to(path)

func load_from(p: String) -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(p)
	if err != OK and p == PATH and FileAccess.file_exists(LEGACY_PATH):
		err = cfg.load(LEGACY_PATH)
	if err != OK:
		Controls.apply({})
		controls_changed.emit()
		return
	for key in DEFAULTS:
		if cfg.has_section_key(SECTION, String(key)):
			_values[key] = _coerce(DEFAULTS[key], cfg.get_value(SECTION, String(key)))
	var keys := {}
	if cfg.has_section(CONTROLS):
		for k in cfg.get_section_keys(CONTROLS):
			keys[k] = cfg.get_value(CONTROLS, k)
	Controls.apply(keys)
	controls_changed.emit()

## Reads the file again, for after it has been edited by hand.
func reload() -> void:
	load_from(path)
	apply_display()
	for key in DEFAULTS:
		changed.emit(key)

## Written as text rather than through ConfigFile, so it keeps a comment on
## every line saying what the value is. ConfigFile still reads it.
func save_to(p: String) -> bool:
	var lines: Array[String] = [
		"; Pinecraft - your personal config: settings and controls.",
		"; Edit a value and save; the game reads this file when it starts, and",
		"; Settings > Reload config file picks up changes without restarting.",
		"; Delete a line (or the whole file) to go back to the default.",
		"",
		"[%s]" % SECTION,
		""]
	for key in DEFAULTS:
		lines.append("; %s (default %s)" % [NOTES.get(key, String(key)), var_to_str(DEFAULTS[key])])
		lines.append("%s=%s" % [String(key), var_to_str(value(key))])
	lines.append("")
	lines.append("[%s]" % CONTROLS)
	lines.append("")
	lines.append("; action=\"Key, Other key\". Keys are written as shown on the Controls page:")
	lines.append("; letters and digits, Shift, Ctrl, Alt, Space, Tab, Esc, Enter, Del, Backspace,")
	lines.append("; F1-F12, Up, Down, Left, Right, Kp 1 (keypad), and the mouse: LMB, RMB, MMB,")
	lines.append("; WheelUp, WheelDown, Mouse4, Mouse5. A combination is Shift+E. Empty means unbound.")
	var group := ""
	var bound := Controls.to_dict()
	for a in Controls.ACTIONS:
		if String(a[2]) != group:
			group = String(a[2])
			lines.append("")
			lines.append("; --- %s" % group)
		lines.append("; %s (default %s)" % [a[1], ", ".join(PackedStringArray(a[3]))])
		lines.append("%s=%s" % [String(a[0]), var_to_str(String(bound.get(String(a[0]), "")))])
	var file := FileAccess.open(p, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return true

## The folder the config file is in, for the button that opens it.
func config_folder() -> String:
	return ProjectSettings.globalize_path(path.get_base_dir())

func open_config_folder() -> void:
	if not FileAccess.file_exists(path):
		save_to(path)
	OS.shell_open(config_folder())

static func _coerce(like: Variant, v: Variant) -> Variant:
	match typeof(like):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return float(v)
	return v

# --- Convenience -----------------------------------------------------------

func mouse_scale() -> float:
	return float(value(&"mouse_sensitivity"))

func invert_y() -> bool:
	return bool(value(&"invert_y"))

func flag(key: StringName) -> bool:
	return bool(value(key))

## Window-level settings. A headless run has no window to change.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var window := get_window()
	var fullscreen: bool = value(&"fullscreen")
	if (window.mode == Window.MODE_FULLSCREEN) != fullscreen:
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if value(&"vsync") else DisplayServer.VSYNC_DISABLED)
	window.scaling_3d_scale = clampf(float(value(&"render_scale")), 0.5, 1.0)
	window.content_scale_factor = clampf(float(value(&"ui_scale")), 0.75, 1.5)
