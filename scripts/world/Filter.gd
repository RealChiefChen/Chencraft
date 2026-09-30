class_name Filter
extends Conveyor

## A belt like any other, with a grate in the middle of it. What the filter's
## rules let through drops through the grate - onto a belt, into a bin or a
## truck underneath - and everything else rides on over it to the far end.
##
## The rules are read top to bottom and the first that matches a piece
## decides it; a piece no rule matches goes the default way, which is a
## switch: everything through, or nothing through. A rule picks pieces by
## type (stone, ore, gem, wood), then which one (mahogany, starmetal - or all
## of that type), then how far along it has been worked (sanded, refined...),
## and by size, over or under so many cubic metres. [R] at the belt opens
## them (FilterPanel).
##
## The grate is a body of its own in the deck. A piece that may go through is
## told not to collide with it, and falls; the rest roll across it as across
## the belt.

var def: BuildingDef
## [{type, sub, stage, size ("any"/"under"/"over"), m3, let}]
var rules: Array[Dictionary] = []
## With no rule for it, does a piece go through?
var drop_by_default: bool = false

## Rules are picked from these. `sub` lists come from the materials table.
const TYPES := ["stone", "ore", "gem", "wood"]
const TYPE_NAMES := {"stone": "Stone", "ore": "Ore and metal", "gem": "Gems", "wood": "Wood"}
## Each type's stages, as [key, name], in the order they are worked.
const STAGES := {
	"wood": [["log", "Log"], ["sanded", "Sanded log"], ["plank", "Plank"]],
	"ore": [["ore", "Ore"], ["crushed", "Crushed ore"], ["bar", "Bar"], ["refined", "Refined bar"]],
	"gem": [["rough", "Rough"], ["polished", "Polished"], ["cut", "Cut jewel"]],
	"stone": [["dug", "As dug"], ["crushed", "Crushed"], ["glass", "Glass"]],
}
const PATH_TYPE := {"wood": "wood", "metal": "ore", "gem": "gem", "stone": "stone"}

var _trap: StaticBody3D
var _hole: float = 1.0
## Pieces told to fall through the grate, until they are clear of it.
var _dropping: Dictionary = {}
var total_dropped: int = 0

func setup(p_def: BuildingDef) -> void:
	def = p_def

func _ready() -> void:
	if def == null:
		def = GameData.building(&"filter")
	super()

# --- The grate ---------------------------------------------------------------

func _build() -> void:
	super()
	var run := sqrt(length * length + rise * rise)
	# Half the belt, so a longer one sorts more at a time; a solid strip at
	# each end to load on and run off.
	_hole = clampf(run * 0.5, 0.6, run - 1.0)
	var deck_shape: CollisionShape3D = null
	for c in _deck.get_children():
		if c is CollisionShape3D:
			deck_shape = c
			break
	# The deck in two, before and after the grate.
	var pose := deck_shape.transform
	var part := (run - _hole) * 0.5
	for end in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, DECK_THICKNESS, part)
		cs.shape = box
		cs.transform = pose.translated_local(Vector3(0, 0, end * (_hole + part) * 0.5))
		_deck.add_child(cs)
	deck_shape.queue_free()
	_trap = StaticBody3D.new()
	_trap.name = "Grate"
	_trap.collision_layer = _deck.collision_layer
	_trap.collision_mask = _deck.collision_mask
	_trap.physics_material_override = _deck.physics_material_override
	var ts := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(width, DECK_THICKNESS, _hole)
	ts.shape = tb
	ts.transform = pose
	_trap.add_child(ts)
	# Drawn as a steel grate in a hazard-striped frame over the rubber.
	var g := Greeble.new()
	var steel := Color(0.55, 0.58, 0.62)
	var top := pose.translated_local(Vector3(0, DECK_THICKNESS * 0.5 + 0.01, 0))
	g.box(Vector3(width - 0.2, 0.02, _hole), top, Color(0.08, 0.08, 0.09))
	var bars := maxi(3, int(_hole / 0.14))
	for i in bars:
		var z := -_hole * 0.5 + _hole * (float(i) + 0.5) / float(bars)
		g.box(Vector3(width - 0.24, 0.03, 0.04), top.translated_local(Vector3(0, 0.015, z)), steel)
	for end in [-1.0, 1.0]:
		g.stripes(width - 0.2, 0.08, top.translated_local(Vector3(0, 0.02, end * (_hole * 0.5 + 0.04)))
			* Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	_trap.add_child(g.instance("Grate", false))
	add_child(_trap)

func _drive() -> void:
	super()
	if _trap != null:
		_trap.constant_linear_velocity = belt_velocity()

func _aboard(inside: Dictionary) -> void:
	for item: LooseItem in inside:
		var through := lets_through(item)
		if through and not _dropping.has(item):
			item.add_collision_exception_with(_trap)
			_dropping[item] = true
		elif not through and _dropping.has(item) and _local(item).y > DECK_THICKNESS:
			item.remove_collision_exception_with(_trap)
			_dropping.erase(item)
	# Clear of the grate - fallen through, or gone off an end - it is a
	# solid thing again.
	for item in _dropping.keys():
		if not is_instance_valid(item) or item.state != LooseItem.State.FREE:
			_dropping.erase(item)
			continue
		if inside.has(item):
			continue
		var at := _local(item)
		if at.y < -0.8 or absf(at.z) > length * 0.5 + 1.0 or absf(at.x) > width:
			if at.y < -0.8:
				total_dropped += 1
			item.remove_collision_exception_with(_trap)
			_dropping.erase(item)

# --- Rules -------------------------------------------------------------------

## Which rule type a piece is: stone, ore, gem or wood ("" for anything else).
static func type_of(item_id: StringName) -> String:
	var path := String(GameData.material_for(item_id).get("path", ""))
	return String(PATH_TYPE.get(path, ""))

## How far along a piece has been worked, as a key from STAGES.
static func stage_of(item_id: StringName, dims: Dictionary) -> String:
	var def_ := GameData.item(item_id)
	if def_ == null:
		return ""
	match String(def_.category):
		"wood":
			return "sanded" if Solid.has_finish(dims, &"sanded") else "log"
		"lumber":
			return "plank"
		"ore":
			return "crushed" if bool(dims.get("crushed", false)) else "ore"
		"metal":
			return "refined" if Solid.has_finish(dims, &"refined") else "bar"
		"gem":
			return "polished" if Solid.has_finish(dims, &"polished") else "rough"
		"jewel":
			return "cut"
		"stone":
			return "crushed" if bool(dims.get("crushed", false)) else "dug"
		"glass":
			return "glass"
	return ""

static func rule_matches(rule: Dictionary, item_id: StringName, dims: Dictionary) -> bool:
	var t := String(rule.get("type", ""))
	if t != "" and t != type_of(item_id):
		return false
	var sub := String(rule.get("sub", ""))
	if sub != "" and String(GameData.material_of.get(item_id, "")) != sub:
		return false
	var stage := String(rule.get("stage", ""))
	if stage != "" and stage != stage_of(item_id, dims):
		return false
	var v := Solid.volume(dims)
	match String(rule.get("size", "any")):
		"under":
			return v < float(rule.get("m3", 0.0))
		"over":
			return v > float(rule.get("m3", 0.0))
	return true

## Whether a piece goes through the grate.
func lets_through(item: LooseItem) -> bool:
	return decide(item.item_id, item.dims)

func decide(item_id: StringName, dims: Dictionary) -> bool:
	for rule in rules:
		if rule_matches(rule, item_id, dims):
			return bool(rule.get("let", true))
	return drop_by_default

static func new_rule() -> Dictionary:
	return {"type": "", "sub": "", "stage": "", "size": "any", "m3": 0.5, "let": true}

## A rule in words, for the panel and the prompt.
static func describe(rule: Dictionary) -> String:
	var t := String(rule.get("type", ""))
	var what := "Anything"
	if t != "":
		what = String(TYPE_NAMES.get(t, t))
		var sub := String(rule.get("sub", ""))
		if sub != "":
			what = sub.capitalize()
		var stage := String(rule.get("stage", ""))
		for s in STAGES.get(t, []):
			if s[0] == stage:
				what += ", " + String(s[1]).to_lower()
	match String(rule.get("size", "any")):
		"under":
			what += ", under %.2f m3" % float(rule.get("m3", 0.0))
		"over":
			what += ", over %.2f m3" % float(rule.get("m3", 0.0))
	return ("Drop: " if bool(rule.get("let", true)) else "Keep on: ") + what

## The materials of a type, as [id, name], for the panel's second list.
static func subtypes(t: String) -> Array:
	var out: Array = []
	for id in GameData.materials:
		var m: Dictionary = GameData.materials[id]
		if String(PATH_TYPE.get(String(m.get("path", "")), "")) == t:
			out.append([String(id), GameData.item_name(StringName(m.raw_item)).replace(" Wood", "").replace(" Ore", "").replace("Rough ", "")])
	out.sort_custom(func(a, b): return String(a[1]) < String(b[1]))
	return out

func status_line() -> String:
	return "Filter belt: %s, %d rule(s), otherwise %s  [E] %s  [R] rules" % [
		"running" if running else "stopped", rules.size(),
		"everything drops" if drop_by_default else "nothing drops", "stop" if running else "start"]

func set_rules(p_rules: Array, p_default: bool) -> void:
	rules.clear()
	for r in p_rules:
		var rule := new_rule()
		rule.merge(r as Dictionary, true)
		rules.append(rule)
	drop_by_default = p_default

func to_dict() -> Dictionary:
	return {"rules": rules.duplicate(true), "drop": drop_by_default}

func from_dict(d: Dictionary) -> void:
	set_rules(d.get("rules", []), bool(d.get("drop", false)))
