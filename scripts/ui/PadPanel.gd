class_name PadPanel
extends Control

## A vehicle pad's paint and fittings: the colour the next vehicle off it is
## painted, and for a loader's pad, bucket or log grapple. Opens with [R] at
## a pad; the vehicle out now keeps what it has until it is sent back and
## spawned again [E]. On a co-op guest the choice is sent to the host's pad.

var player: Player
var pad: VehiclePad
var _title: Label
var _swatches: GridContainer
var _fit_row: HBoxContainer
var _fit: OptionButton
var _now: Label
var _parts: VBoxContainer

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
	card.custom_minimum_size = Vector2(520, 0)
	center.add_child(card)
	var col := UIKit.vbox(12)
	card.add_child(col)
	var head := UIKit.hbox(8)
	_title = UIKit.label("", "Header")
	head.add_child(_title)
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Done", func(): visible = false)
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	col.add_child(head)
	col.add_child(UIKit.label("PAINT", "Subheader", 13))
	_swatches = GridContainer.new()
	_swatches.columns = 7
	_swatches.add_theme_constant_override("h_separation", 8)
	_swatches.add_theme_constant_override("v_separation", 8)
	col.add_child(_swatches)
	_fit_row = UIKit.hbox(10)
	_fit_row.add_child(UIKit.label("Fitted with"))
	_fit = OptionButton.new()
	_fit.add_item("Bucket")
	_fit.add_item("Log grapple")
	_fit.item_selected.connect(func(i: int): _choose_fitting(LoaderArm.ATTACHMENTS[i]))
	_fit_row.add_child(_fit)
	col.add_child(_fit_row)
	col.add_child(UIKit.label("PARTS", "Subheader", 13))
	_parts = UIKit.vbox(8)
	col.add_child(_parts)
	_now = UIKit.label("", "Small")
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.custom_minimum_size.x = 480
	col.add_child(_now)
	visibility_changed.connect(func():
		if player != null:
			player.set_ui_blocking(visible))

func open(p: VehiclePad) -> void:
	pad = p
	_title.text = "%s pad" % p.vehicle_name()
	for c in _swatches.get_children():
		c.queue_free()
	for entry in VehiclePad.PAINTS:
		var colour: Color = entry[1]
		var b := Button.new()
		b.custom_minimum_size = Vector2(60, 44)
		b.tooltip_text = String(entry[0])
		b.focus_mode = Control.FOCUS_NONE
		var shown := colour if colour.a > 0.0 else Color(0.35, 0.35, 0.38)
		var chosen := p.paint.is_equal_approx(colour)
		for state in ["normal", "hover", "pressed"]:
			var box := UITheme.box(shown.lightened(0.1) if state == "hover" else shown, 8, Vector4.ZERO,
				UITheme.ACCENT if chosen else Color(0, 0, 0, 0.5), 3 if chosen else 1)
			b.add_theme_stylebox_override(state, box)
		if colour.a <= 0.0:
			b.text = "F"
		b.pressed.connect(func(): _choose_paint(colour))
		_swatches.add_child(b)
	_fit_row.visible = p.is_loader_pad()
	_build_parts()
	_fit.selected = maxi(0, LoaderArm.ATTACHMENTS.find(p.attachment))
	_refresh_note()
	visible = true

## One row per kind of part: which is fitted (stock, or any you have in your
## parts), and a switch to run without it.
func _build_parts() -> void:
	for c in _parts.get_children():
		c.queue_free()
	for track in PlayerState.VEHICLE_TRACKS:
		var row := UIKit.hbox(10)
		var t: Dictionary = GameData.upgrade_tracks.get(track, {})
		var name_label := UIKit.label(String(t.get("display_name", track)))
		name_label.custom_minimum_size.x = 140
		row.add_child(name_label)
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		var levels: Array[int] = []
		var now := pad.fitted_level(track)
		var count := (t.get("levels", []) as Array).size()
		for lvl in range(1, count + 1):
			var have := PlayerState.part_count(track, lvl)
			if lvl != 1 and lvl != now and have <= 0:
				continue
			var label := GameData.part_name(track, lvl)
			if lvl == now:
				label += "  (fitted)"
			elif lvl > 1:
				label += "  (%d in parts)" % have
			pick.add_item(label)
			levels.append(lvl)
		pick.selected = maxi(0, levels.find(now))
		pick.item_selected.connect(func(i: int): _fit_part(track, levels[i]))
		row.add_child(pick)
		var on := CheckBox.new()
		on.text = "On"
		on.focus_mode = Control.FOCUS_NONE
		on.button_pressed = pad.part_on(track)
		on.toggled.connect(func(v: bool): _switch_part(track, v))
		row.add_child(on)
		_parts.add_child(row)

func _fit_part(track: StringName, lvl: int) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	if Net.is_client():
		_send({"fit": [String(track), lvl]})
	else:
		var err := pad.fit(track, lvl)
		if err != "" and player != null:
			player.interacted.emit(err)
	open(pad)

func _switch_part(track: StringName, on: bool) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	if Net.is_client():
		_send({"on": [String(track), on]})
	pad.set_part_on(track, on)
	_refresh_note()

func _choose_paint(colour: Color) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	pad.paint = colour
	_send({"paint": [colour.r, colour.g, colour.b, colour.a]})
	open(pad)

func _choose_fitting(kind: StringName) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	pad.attachment = kind
	_send({"attachment": String(kind)})
	_refresh_note()

func _refresh_note() -> void:
	var paint_name := "factory paint"
	for entry in VehiclePad.PAINTS:
		if pad.paint.is_equal_approx(entry[1]):
			paint_name = String(entry[0]).to_lower()
	_now.text = "The next %s off this pad comes in %s%s. The one out now keeps what it has: send it back and spawn it again with [E] at the pad." % [
		pad.vehicle_name().to_lower(), paint_name,
		(" with the " + ("log grapple" if pad.attachment == &"grapple" else "bucket")) if pad.is_loader_pad() else ""]

## A guest's pad is a picture of the host's: the host is told.
func _send(ev: Dictionary) -> void:
	if Net.is_client() and Net.client_side != null:
		var id := int(Net.client_side.call("id_of", pad))
		if id >= 0:
			ev.t = "pad"
			ev.id = id
			Net.client_side.call("send_event", ev)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (Controls.pressed(event, &"pause") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)):
		visible = false
		get_viewport().set_input_as_handled()
