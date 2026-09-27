class_name KeyGuide
extends RefCounted

## Every binding in the game, grouped the way the player meets them. The
## controls screen, the journal and the context hints all read from here, so a
## key only has to be described once. Rows name actions, not keys: what is
## drawn on the keycap is whatever the action is bound to now (see Controls).

const GROUPS := [
	{"title": "On foot", "rows": [
		[[&"move_forward", &"move_left", &"move_back", &"move_right"], "Move"],
		[[&"sprint"], "Sprint"],
		[[&"jump"], "Jump"],
		[[&"slot_1", "/", &"slot_9"], "Take a tool from the hotbar (again to put it away)"],
		[[&"wheel_up"], "Step through the hotbar"],
		[[&"primary"], "Empty hand: hold to drag by the point you grab"],
		[[&"primary"], "Axe: chop and buck. Hammer: crack rock"],
		[[&"wheel_up", "/", &"wheel_down"], "While dragging: pull it closer or push it away"],
		[[&"sprint"], "While dragging: hold and use the move keys and the two turn keys to turn it"],
		[[&"secondary"], "Pick up onto your carry rack (while dragging: throw)"],
		[[&"inventory"], "Inventory: put tools on the hotbar"],
		[[&"drop_one"], "Drop one piece from the rack"],
		[[&"drop_all"], "Drop everything on the rack"],
		[[&"use"], "Use: deposit, sell, pay, load, talk"],
		[[&"sprint", &"use"], "Empty a storage bin onto the ground"],
		[[&"machine_output"], "At a machine: change the size of what it makes"],
	]},
	{"title": "Build mode", "rows": [
		[[&"build_mode"], "Enter or leave build mode"],
		[[&"build_menu"], "Open the build menu to choose what to build"],
		[[&"move_forward", &"move_left", &"move_back", &"move_right"], "Fly the camera"],
		[[&"sprint"], "Up / faster"],
		[[&"lower"], "Down"],
		[[&"primary"], "Place the chosen building"],
		[[&"secondary"], "Remove the building you aim at (empty-handed: put down what you hold)"],
		[[&"pick_block"], "Copy the building you aim at: same thing, size and turn"],
		[[&"wheel_up"], "Next / previous building"],
		[[&"rotate_x", &"rotate_y", &"rotate_z"], "Rotate around each axis"],
		[[&"edit_select"], "Select the building you aim at to edit it (again: done)"],
		[[&"slot_1", "/", &"slot_3"], "While editing: move, scale or rotate handles"],
		[[&"primary"], "While editing: aim at a handle, hold and move the mouse to drag it"],
		[[&"remove_selected"], "While editing: remove it"],
		[[&"pause"], "Leave build mode"],
	]},
	{"title": "Vehicles", "rows": [
		[[&"enter_vehicle"], "Get in (look at it or stand by it) / get out"],
		[[&"hitch"], "Hitch the trailer behind you, or let it go (seated or standing by it)"],
		[[&"move_forward", &"move_back"], "Throttle and reverse"],
		[[&"move_left", &"move_right"], "Steer"],
		[[&"jump"], "Brake"],
		[[&"gear_up", "/", &"gear_down"], "Manual gearbox: change gear (Settings > Controls)"],
		[[&"unload"], "Drop the tailgate and tip the load out"],
		[[&"unload_one"], "Drop one piece off the back"],
		[[&"recover"], "Recover (set it back on its wheels) - once a second, not on outriggers"],
		[[&"winch_hook"], "Winch: hook on what you aim at, or unhook (from the seat)"],
		[[&"winch_in", "/", &"winch_out"], "Winch: reel in / let out"],
		[[&"outriggers"], "Outriggers out or in (crane trucks): locks the truck where it stands (seated or standing by it)"],
		[[&"crane"], "Crane: operator mode (outriggers down) or fold it away"],
		[[&"move_forward", &"move_back"], "Crane: log away from / toward the camera"],
		[[&"move_left", &"move_right"], "Crane: log left / right of the camera"],
		[[&"sprint", "/", &"lower"], "Crane: log up / down"],
		[[&"turn_ccw", "/", &"turn_cw"], "Crane: turn the log"],
		[[&"enter_vehicle"], "Crane: drop the claw - it goes down until it meets something, grabs it and comes back up (again: let go)"],
		[[&"secondary"], "Crane: hold for fine, slow control"],
		[[&"wheel_up"], "Crane: zoom the camera (the mouse orbits the log)"],
		[[&"sprint", "/", &"lower"], "Loader: raise / lower the arms"],
		[[&"turn_ccw", "/", &"turn_cw"], "Loader: tip the bucket forward / curl it back"],
		[[&"loader_lock"], "Loader: lock what is in the bucket in place, or let it go"],
		[[&"loader_attachment"], "Loader: swap the bucket for the log grapple (empty)"],
		[[&"rig_home"], "Crane or loader: back to the default position"],
	]},
	{"title": "Game", "rows": [
		[[&"pause"], "Pause menu"],
		[[&"journal"], "Journal: orders, map, market, upgrades"],
		[[&"inventory"], "Inventory and hotbar"],
		[[&"map"], "Map"],
		[[&"market"], "Market prices"],
		[[&"upgrades"], "Upgrades and land"],
		[[&"help"], "This list"],
		[[&"toggle_hints"], "Show or hide key hints and the crane / winch banner"],
		[[&"quick_save"], "Quick save"],
		[[&"quick_load"], "Quick load"],
		[[&"debug"], "Debug readout"],
	]},
]

## The keycaps for a row: each action shown as its current key; a "/"
## between two stays a slash.
static func caps(row_keys: Array) -> Array:
	var out: Array = []
	for k in row_keys:
		if k is StringName:
			out.append(Controls.key(k))
		else:
			out.append(String(k))
	return out

## The whole reference as a two-column sheet.
static func sheet() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 18)
	for group in GROUPS:
		var col := UIKit.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		col.add_child(UIKit.label(String(group.title).to_upper(), "Subheader"))
		for row in group.rows:
			col.add_child(UIKit.binding_row(caps(row[0]), row[1]))
		grid.add_child(col)
	var outer := UIKit.vbox(10)
	var note := UIKit.label("Every key can be changed in Settings > Controls, or in your config file.", "Small")
	outer.add_child(note)
	outer.add_child(grid)
	return outer

## The handful of keys that matter right now, for the corner of the screen.
## `state` is "foot", "carrying", "dragging", "build", "drive" or "crane".
static func hints_for(state: String) -> Array:
	var rows: Array
	match state:
		"build":
			rows = [[[&"build_menu"], "Build menu"], [[&"primary"], "Place"], [[&"secondary"], "Remove"],
				[[&"pick_block"], "Copy"], [[&"edit_select"], "Edit what you aim at"],
				[[&"rotate_x", &"rotate_y", &"rotate_z"], "Rotate"], [[&"sprint", "/", &"lower"], "Up / down"], [[&"build_mode"], "Done"]]
		"drive":
			rows = [[[&"move_forward", &"move_back"], "Drive"], [[&"jump"], "Brake"], [[&"unload"], "Unload"],
				[[&"winch_hook"], "Winch"], [[&"winch_in", "/", &"winch_out"], "Reel"], [[&"crane"], "Crane"],
				[[&"hitch"], "Hitch"], [[&"enter_vehicle"], "Get out"]]
		"drive_manual":
			rows = [[[&"move_forward", &"move_back"], "Drive"], [[&"gear_up", "/", &"gear_down"], "Gears"],
				[[&"jump"], "Brake"], [[&"unload"], "Unload"], [[&"winch_hook"], "Winch"], [[&"crane"], "Crane"],
				[[&"hitch"], "Hitch"], [[&"enter_vehicle"], "Get out"]]
		"loader":
			rows = [[[&"move_forward", &"move_back"], "Drive"], [[&"sprint", "/", &"lower"], "Arms up / down"],
				[[&"turn_ccw", "/", &"turn_cw"], "Tip / curl"], [[&"loader_lock"], "Lock"],
				[[&"loader_attachment"], "Bucket / grapple"], [[&"rig_home"], "Reset"], [[&"enter_vehicle"], "Get out"]]
		"crane":
			rows = [[[&"move_forward", &"move_back"], "Along"], [[&"move_left", &"move_right"], "Across"],
				[[&"sprint", "/", &"lower"], "Up / down"], [[&"turn_ccw", "/", &"turn_cw"], "Turn"],
				[[&"enter_vehicle"], "Claw / let go"], [[&"secondary"], "Fine"], [[&"rig_home"], "Reset"], [[&"crane"], "Done"]]
		"dragging":
			rows = [[[&"primary"], "Hold to keep hold"], [[&"wheel_up"], "Closer / further"],
				[[&"sprint"], "+ move/turn keys: turn it"], [[&"secondary"], "Throw"]]
		"carrying":
			rows = [[[&"use"], "Deposit / sell"], [[&"drop_one"], "Drop one"], [[&"drop_all"], "Drop all"],
				[[&"secondary"], "Pick up more"], [[&"build_mode"], "Build"]]
		_:
			rows = [[[&"slot_1", "/", &"slot_9"], "Tools"], [[&"primary"], "Drag / use tool"], [[&"secondary"], "Pick up"],
				[[&"use"], "Use"], [[&"inventory"], "Inventory"], [[&"build_mode"], "Build"], [[&"journal"], "Journal"]]
	var out: Array = []
	for r in rows:
		out.append([caps(r[0]), r[1]])
	return out
