class_name FilterPanel
extends Control

## A filter belt's rules, opened with [R] at the belt. The list of rules, top
## one first, each with a delete button; a switch for what happens to a piece
## no rule covers; and a form for a new rule: type, then which one (or all),
## then how far worked (or any), then a size limit, then drop or keep. On a
## co-op guest the whole set is sent to the host's belt.

var player: Player
var filter: Filter
var _list: VBoxContainer
var _default: CheckButton
var _type: OptionButton
var _sub: OptionButton
var _stage: OptionButton
var _size: OptionButton
var _m3: SpinBox
var _let: OptionButton

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
	card.custom_minimum_size = Vector2(620, 0)
	center.add_child(card)
	var outer := UIKit.vbox(12)
	card.add_child(outer)
	var head := UIKit.hbox(8)
	head.add_child(UIKit.label("Filter belt", "Header"))
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Done", func(): visible = false)
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	outer.add_child(head)
	var note := UIKit.label("Rules are checked top to bottom; the first that fits a piece decides whether it drops through the grate.", "Muted", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 580
	outer.add_child(note)

	_default = CheckButton.new()
	_default.text = "With no rule for it, a piece drops through"
	_default.focus_mode = Control.FOCUS_NONE
	_default.toggled.connect(func(on: bool):
		if filter != null:
			filter.drop_by_default = on
			_changed())
	outer.add_child(_default)

	outer.add_child(UIKit.label("RULES", "Subheader"))
	_list = UIKit.vbox(6)
	outer.add_child(_list)

	outer.add_child(UIKit.label("NEW RULE", "Subheader"))
	var row1 := UIKit.hbox(8)
	_type = _options(row1, 150)
	_sub = _options(row1, 170)
	_stage = _options(row1, 170)
	outer.add_child(row1)
	var row2 := UIKit.hbox(8)
	_size = _options(row2, 150)
	for s in [["any", "Any size"], ["under", "Under"], ["over", "Over"]]:
		_size.add_item(s[1])
		_size.set_item_metadata(_size.item_count - 1, s[0])
	_m3 = SpinBox.new()
	_m3.min_value = 0.001
	_m3.max_value = 20.0
	_m3.step = 0.01
	_m3.value = 0.5
	_m3.suffix = "m3"
	_m3.custom_minimum_size.x = 130
	row2.add_child(_m3)
	_let = _options(row2, 170)
	_let.add_item("Drop through")
	_let.set_item_metadata(0, true)
	_let.add_item("Keep on the belt")
	_let.set_item_metadata(1, false)
	row2.add_child(UIKit.spacer())
	var add := UIKit.button("Add rule", _add_rule)
	add.focus_mode = Control.FOCUS_NONE
	row2.add_child(add)
	outer.add_child(row2)

	_type.item_selected.connect(func(_i: int): _fill_type())
	_size.item_selected.connect(func(_i: int): _m3.editable = _size.get_item_metadata(_size.selected) != "any")
	visibility_changed.connect(func():
		if player != null:
			player.set_ui_blocking(visible))

func _options(row: HBoxContainer, width: float) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.x = width
	o.focus_mode = Control.FOCUS_NONE
	row.add_child(o)
	return o

func open(f: Filter) -> void:
	filter = f
	_default.set_pressed_no_signal(f.drop_by_default)
	_type.clear()
	_type.add_item("Anything")
	_type.set_item_metadata(0, "")
	for t in Filter.TYPES:
		_type.add_item(String(Filter.TYPE_NAMES[t]))
		_type.set_item_metadata(_type.item_count - 1, t)
	_type.select(0)
	_fill_type()
	_m3.editable = false
	_refresh()
	visible = true

## The second and third lists follow the type picked.
func _fill_type() -> void:
	var t := String(_type.get_item_metadata(_type.selected))
	_sub.clear()
	_sub.add_item("All")
	_sub.set_item_metadata(0, "")
	_stage.clear()
	_stage.add_item("Any stage")
	_stage.set_item_metadata(0, "")
	if t != "":
		for s in Filter.subtypes(t):
			_sub.add_item(String(s[1]))
			_sub.set_item_metadata(_sub.item_count - 1, s[0])
		for s in Filter.STAGES.get(t, []):
			_stage.add_item(String(s[1]))
			_stage.set_item_metadata(_stage.item_count - 1, s[0])
	_sub.disabled = t == ""
	_stage.disabled = t == ""

func _add_rule() -> void:
	if filter == null or not is_instance_valid(filter):
		return
	var rule := Filter.new_rule()
	rule.type = _type.get_item_metadata(_type.selected)
	rule.sub = _sub.get_item_metadata(_sub.selected)
	rule.stage = _stage.get_item_metadata(_stage.selected)
	rule.size = _size.get_item_metadata(_size.selected)
	rule.m3 = _m3.value
	rule.let = bool(_let.get_item_metadata(_let.selected))
	filter.rules.append(rule)
	_changed()

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	if filter.rules.is_empty():
		_list.add_child(UIKit.label("No rules yet: every piece goes the default way.", "Muted", 14))
	for i in filter.rules.size():
		var row := UIKit.hbox(8)
		var text := UIKit.label("%d.  %s" % [i + 1, Filter.describe(filter.rules[i])])
		text.custom_minimum_size.x = 480
		row.add_child(text)
		row.add_child(UIKit.spacer())
		var index := i
		var del := UIKit.button("Delete", func():
			filter.rules.remove_at(index)
			_changed())
		del.focus_mode = Control.FOCUS_NONE
		row.add_child(del)
		_list.add_child(row)

func _changed() -> void:
	if filter == null or not is_instance_valid(filter):
		return
	_refresh()
	# A guest's belt is a picture of the host's: the host is told.
	if Net.is_client() and Net.client_side != null:
		var id := int(Net.client_side.call("id_of", filter))
		if id >= 0:
			Net.client_side.call("send_event", {"t": "fcfg", "id": id, "state": filter.to_dict()})

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (Controls.pressed(event, &"pause") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)):
		visible = false
		get_viewport().set_input_as_handled()
