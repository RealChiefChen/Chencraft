class_name PlayerKit
extends RefCounted

## One co-op guest's own things: their tools, their hotbar and their personal
## gear (carry rack, boots). The host's own kit is PlayerState itself; money,
## unlocks and machine and vehicle upgrades are shared and stay there too.
## Speaks the same tool and track calls as PlayerState, so a Player can use
## either.

signal changed()

const PERSONAL: Array[StringName] = [&"carry", &"boots"]
const HOTBAR_SLOTS := 9

var tools: Array[StringName] = []
var hotbar: Array[StringName] = []
var levels: Dictionary = {}              ## personal track -> int

func _init() -> void:
	reset()

func reset() -> void:
	tools.clear()
	hotbar.clear()
	hotbar.resize(HOTBAR_SLOTS)
	hotbar.fill(&"")
	levels.clear()
	for track in PERSONAL:
		levels[track] = 1
	for id in GameData.start_tools:
		give_tool(id, false)

static func personal(track: StringName) -> bool:
	return PERSONAL.has(track)

# --- Tracks: personal ones here, the rest shared ------------------------------

func level(track: StringName) -> int:
	if not personal(track):
		return PlayerState.level(track)
	return int(levels.get(track, 1))

func stats(track: StringName) -> Dictionary:
	return GameData.upgrade_level(track, level(track))

func stat(track: StringName, key: String, fallback: float = 0.0) -> float:
	return float(stats(track).get(key, fallback))

func track_value(track: StringName, key: String, fallback: float = 0.0) -> float:
	return PlayerState.track_value(track, key, fallback)

func label(track: StringName) -> String:
	return String(stats(track).get("label", String(track)))

func at_max(track: StringName) -> bool:
	return level(track) >= GameData.max_upgrade_level(track)

func next_cost(track: StringName) -> int:
	if at_max(track):
		return -1
	return int(GameData.upgrade_level(track, level(track) + 1).get("cost", 0))

## Up one level. Only personal tracks are this kit's to raise.
func level_up(track: StringName) -> bool:
	if not personal(track) or at_max(track):
		return false
	levels[track] = level(track) + 1
	changed.emit()
	return true

# --- Tools and the hotbar ------------------------------------------------------------

func owns_tool(id: StringName) -> bool:
	return tools.has(id)

func give_tool(id: StringName, announce: bool = true) -> bool:
	if GameData.tool(id).is_empty() or tools.has(id):
		return false
	tools.append(id)
	var free := hotbar.find(&"")
	if free >= 0:
		hotbar[free] = id
	if announce:
		changed.emit()
	return true

func set_hotbar(slot: int, id: StringName) -> void:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return
	if id != &"" and not tools.has(id):
		return
	var was := hotbar.find(id) if id != &"" else -1
	if was >= 0:
		hotbar[was] = hotbar[slot]
	hotbar[slot] = id
	changed.emit()

func hotbar_tool(slot: int) -> StringName:
	if slot < 0 or slot >= hotbar.size():
		return &""
	return hotbar[slot]

func best_tool(kind: String) -> StringName:
	var best := &""
	var best_cost := -1
	for id in tools:
		var t := GameData.tool(id)
		if String(t.get("kind", "")) == kind and int(t.get("cost", 0)) > best_cost:
			best = id
			best_cost = int(t.get("cost", 0))
	return best

# --- Saving, and what the guest's own game is told ------------------------------

func to_dict() -> Dictionary:
	var lv := {}
	for k in levels:
		lv[String(k)] = int(levels[k])
	return {"tools": tools.map(func(t): return String(t)),
		"hotbar": hotbar.map(func(t): return String(t)), "levels": lv}

func from_dict(d: Dictionary) -> void:
	reset()
	if d.has("tools"):
		tools.clear()
		for id in d["tools"]:
			if not GameData.tool(StringName(id)).is_empty() and not tools.has(StringName(id)):
				tools.append(StringName(id))
		var bar: Array = d.get("hotbar", [])
		for i in HOTBAR_SLOTS:
			var id := StringName(bar[i]) if i < bar.size() else &""
			hotbar[i] = id if tools.has(id) else &""
	var lv: Dictionary = d.get("levels", {})
	for track in PERSONAL:
		if lv.has(String(track)):
			levels[track] = clampi(int(lv[String(track)]), 1, GameData.max_upgrade_level(track))

## A PlayerState dictionary as this kit's owner sees it: shared things as
## they are, personal ones from the kit.
func over(state: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	out.erase("guests")
	var mine := to_dict()
	out["tools"] = mine.tools
	out["hotbar"] = mine.hotbar
	var lv: Dictionary = out.get("levels", {})
	for k in mine.levels:
		lv[k] = mine.levels[k]
	out["levels"] = lv
	return out
