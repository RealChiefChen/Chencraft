class_name MachineConfigPanel
extends Control

## A machine's output sizes, in centimetres, set with number boxes: the
## planker's board width and thickness, the crusher's biggest lump and so on
## (InlineMachine.config_fields). Opens with [R] at a machine. 0 means as it
## comes. On a co-op guest the change is sent to the host's machine.

var player: Player
var machine: InlineMachine
var _col: VBoxContainer
var _title: Label
var _summary: Label

func _ready() -> void:
	UIKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	UIKit.fill(shade)
	add_child(shade)
	var center := CenterContainer.new()
	UIKit.fill(center)
	add_child(center)
	var card := UIKit.panel("WindowPanel")
	card.custom_minimum_size = Vector2(460, 0)
	center.add_child(card)
	var outer := UIKit.vbox(12)
	card.add_child(outer)
	var head := UIKit.hbox(8)
	_title = UIKit.label("", "Header")
	head.add_child(_title)
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Done", func(): visible = false)
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	outer.add_child(head)
	var note := UIKit.label("Sizes in centimetres. 0 is as it comes: one piece, its natural size.", "Muted", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	outer.add_child(note)
	_col = UIKit.vbox(8)
	outer.add_child(_col)
	_summary = UIKit.label("", "Small")
	outer.add_child(_summary)
	visibility_changed.connect(func():
		if player != null:
			player.set_ui_blocking(visible))

func open(m: InlineMachine) -> void:
	machine = m
	_title.text = m.def.display_name
	for c in _col.get_children():
		c.queue_free()
	for f in m.config_fields():
		var row := UIKit.hbox(10)
		var name_label := UIKit.label(String(f[1]))
		name_label.custom_minimum_size.x = 200
		row.add_child(name_label)
		var box := SpinBox.new()
		box.min_value = float(f[2])
		box.max_value = float(f[3])
		box.step = float(f[4])
		box.suffix = "cm"
		box.value = m.setting(f[0])
		box.custom_minimum_size.x = 140
		var key: StringName = f[0]
		box.value_changed.connect(func(v: float): _apply_setting(key, v))
		row.add_child(box)
		_col.add_child(row)
	_summary.text = "Making: " + m.output_label()
	visible = true

func _apply_setting(key: StringName, cm: float) -> void:
	if machine == null or not is_instance_valid(machine):
		return
	machine.set_setting(key, cm)
	_summary.text = "Making: " + machine.output_label()
	# A guest's machine is a picture of the host's: the host is told.
	if Net.is_client() and Net.client_side != null:
		var id := int(Net.client_side.call("id_of", machine))
		if id >= 0:
			Net.client_side.call("send_event", {"t": "mcfg", "id": id, "k": String(key), "v": cm})

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (Controls.pressed(event, &"pause") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)):
		visible = false
		get_viewport().set_input_as_handled()
