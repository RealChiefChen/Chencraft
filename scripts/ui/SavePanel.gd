class_name SavePanel
extends VBoxContainer

## The save slots, for the title screen and the pause menu: what is in each
## (the day, the money, when it was saved) and what can be done with it.
##
##   LOAD   load a saved game, or clear a slot
##   NEW    pick the slot a new game goes in (a used one asks first)
##   PAUSE  load another slot, save the game into any slot, or clear one

signal load_requested(slot: int)
signal save_requested(slot: int)
signal new_requested(slot: int)

enum Mode { LOAD, NEW, PAUSE }

var mode: Mode = Mode.LOAD
## Where yes/no questions are put up.
var dialog_host: Control
var _rows: VBoxContainer

func _init(p_mode: Mode = Mode.LOAD, host: Control = null) -> void:
	mode = p_mode
	dialog_host = host

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var note := UIKit.label({
		Mode.LOAD: "Pick a game to carry on with.",
		Mode.NEW: "Pick a slot for the new game. A slot with a game in it is replaced (it asks first).",
		Mode.PAUSE: "Your game saves to the slot it is playing in. Save it into another slot to keep a copy, or load another game (this one is saved first).",
	}[mode], "Small")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	_rows = UIKit.vbox(8)
	add_child(_rows)
	refresh()

func refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for entry in SaveSystem.slots():
		_rows.add_child(_row(int(entry.slot), entry.info))

func _row(n: int, info: Dictionary) -> Control:
	var shell := UIKit.panel("Row")
	var row := UIKit.hbox(10)
	shell.add_child(row)
	var playing := mode == Mode.PAUSE and n == SaveSystem.slot
	var col := UIKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label("Slot %d%s" % [n, "  -  playing now" if playing else ""], "Subheader", 14,
		UITheme.ACCENT if playing else null))
	if info.is_empty():
		col.add_child(UIKit.label("Empty", "Muted"))
	else:
		var when := UIKit.ago(String(info.saved_at))
		col.add_child(UIKit.label("Day %d   ·   %s   ·   %d building%s%s" % [
			int(info.day), UIKit.money(int(info.money)), int(info.buildings),
			"" if int(info.buildings) == 1 else "s", ("   ·   saved " + when) if when != "" else ""]))
	row.add_child(col)
	var used := not info.is_empty()
	match mode:
		Mode.LOAD:
			if used:
				row.add_child(UIKit.button("Load", func(): load_requested.emit(n)))
				row.add_child(_delete_button(n))
		Mode.NEW:
			row.add_child(UIKit.button("Start here", func():
				if used:
					_ask("Replace slot %d?" % n, "The game saved there will be lost. Settings are kept.",
						"Start over", func(): new_requested.emit(n))
				else:
					new_requested.emit(n)))
		Mode.PAUSE:
			if used and not playing:
				row.add_child(UIKit.button("Load", func():
					_ask("Load slot %d?" % n, "Your game is saved to slot %d first." % SaveSystem.slot, "Load",
						func(): load_requested.emit(n), false)))
			row.add_child(UIKit.button("Save here", func():
				if used and not playing:
					_ask("Save over slot %d?" % n, "The game saved there will be replaced by this one.",
						"Save", func(): save_requested.emit(n))
				else:
					save_requested.emit(n)))
			if used and not playing:
				row.add_child(_delete_button(n))
	return shell

func _delete_button(n: int) -> Button:
	return UIKit.button("Delete", func():
		_ask("Delete slot %d?" % n, "The game saved there is gone for good.", "Delete", func():
			SaveSystem.delete_save(SaveSystem.slot_path(n))
			refresh()), "Ghost")

func _ask(title: String, body: String, yes: String, on_yes: Callable, danger: bool = true) -> void:
	var host: Node = dialog_host if dialog_host != null else self
	UIKit.confirm(host, title, body, yes, on_yes, danger)
