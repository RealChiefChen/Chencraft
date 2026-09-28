class_name SignPanel
extends Control

## Writing on a sign: a line of text, set as you type. Opens with [E] at a
## finished sign. On a co-op guest the words are sent to the host's sign.

var player: Player
var sign: Schematic
var _edit: LineEdit

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
	head.add_child(UIKit.label("Sign", "Header"))
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Done", func(): visible = false)
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	outer.add_child(head)
	_edit = LineEdit.new()
	_edit.max_length = Schematic.SIGN_MAX
	_edit.placeholder_text = "What it says"
	_edit.custom_minimum_size.x = 420
	_edit.text_changed.connect(_apply)
	_edit.text_submitted.connect(func(_t: String): visible = false)
	outer.add_child(_edit)
	visibility_changed.connect(func():
		if player != null:
			player.set_ui_blocking(visible))

func open(s: Schematic) -> void:
	sign = s
	_edit.text = s.text
	visible = true
	_edit.grab_focus()
	_edit.select_all()

func _apply(t: String) -> void:
	if sign == null or not is_instance_valid(sign):
		return
	sign.set_text(t)
	# A guest's sign is a picture of the host's: the host is told.
	if Net.is_client() and Net.client_side != null:
		var id := int(Net.client_side.call("id_of", sign))
		if id >= 0:
			Net.client_side.call("send_event", {"t": "sign", "id": id, "text": sign.text})

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (Controls.pressed(event, &"pause") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)):
		visible = false
		get_viewport().set_input_as_handled()
