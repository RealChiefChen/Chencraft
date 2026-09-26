class_name BuildMenu
extends PanelContainer

## Build mode's menu: everything you can put up, in sections, with what each
## costs or how many copies are left. Click one to take it in hand; the menu
## closes and the ghost follows your aim. Opened and closed with the build-menu
## key (E by default); Esc closes it too.

signal chosen(def: BuildingDef)
signal closed

const SECTIONS := [
	["Belts and sorting", [&"conveyor", &"splitter", &"filter"]],
	["Machines", [&"inline", &"machine"]],
	["Storage", [&"storage"]],
	["Vehicle pads", [&"pad"]],
	["Plans (filled with material)", [&"schematic"]],
	["Doodads", [&"doodad"]],
]

var build_system: BuildSystem
var _body: VBoxContainer

func _init() -> void:
	theme_type_variation = "WindowPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _ready() -> void:
	var col := UIKit.vbox(10)
	add_child(col)
	var head := UIKit.hbox(10)
	var title := UIKit.label("Build", "Header")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.label("click one to take it in hand", "Muted"))
	head.add_child(UIKit.button("Empty hand", func():
		if build_system != null:
			build_system.clear_choice()
		closed.emit(), "Ghost"))
	head.add_child(UIKit.button("Close", func(): closed.emit(), "Ghost"))
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(900, 520)
	_body = UIKit.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	col.add_child(scroll)

func open() -> void:
	refresh()
	visible = true

func refresh() -> void:
	if _body == null or build_system == null:
		return
	for c in _body.get_children():
		c.queue_free()
	var current := build_system.current()
	for section in SECTIONS:
		var defs: Array[BuildingDef] = []
		for def in build_system.palette:
			if (section[1] as Array).has(def.kind):
				defs.append(def)
		if defs.is_empty():
			continue
		_body.add_child(UIKit.label(String(section[0]).to_upper(), "Subheader"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for def in defs:
			flow.add_child(_card(def, current != null and current.id == def.id and current.tier == def.tier))
		_body.add_child(flow)
	if build_system.palette.is_empty():
		_body.add_child(UIKit.label("Nothing to build yet - machines and pads are sold at the Store.", "Muted"))

func _card(def: BuildingDef, selected: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 74)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0.10, 0.13, 0.11, 0.92) if selected else UITheme.PANEL, 10,
		Vector4(10, 8, 10, 8), UITheme.ACCENT if selected else UITheme.EDGE, 2 if selected else 1))
	b.tooltip_text = def.blurb
	var col := UIKit.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_top = 6
	col.offset_right = -10
	col.offset_bottom = -6
	var name_label := UIKit.label(def.display_name, "", 15, UITheme.ACCENT if selected else UITheme.INK)
	name_label.add_theme_font_override("font", UITheme.font(600))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	col.add_child(UIKit.label("%d x %d x %d m" % [def.size.x, def.size.y, def.size.z], "Small", 12))
	var note := PlayerState.build_note(def)
	col.add_child(UIKit.label(UIKit.money(def.cost) if note.begins_with("$") else note, "", 13,
		UITheme.GOOD if PlayerState.can_build(def) else UITheme.BAD))
	for c in col.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	b.pressed.connect(func(): chosen.emit(def))
	return b
