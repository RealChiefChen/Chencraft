extends Node

## Every price in the game, as the game itself works them out, printed as one
## JSON line (PRICES {...}) for copying into the balance sheet:
##   godot --headless --path . res://tools/price_dump.tscn
## Shop boxes cost what Store.price_of charges; gear and machine tiers list
## every level of their track; materials give the per-m3 rate at a neutral
## market and the price of one piece of the usual size.

func _ready() -> void:
	var out := {"shop": [], "tracks": [], "buildings": [], "tools": [], "land": [], "items": [], "materials": []}
	var store := Store.new()
	for p in GameData.store_products():
		var price := -1
		if String(p.kind) == "upgrade":
			price = int(GameData.upgrade_level(StringName(p.target), 2).get("cost", -1))
		else:
			price = store.price_of({"target": StringName(p.target), "kind": StringName(p.kind),
				"tier": int(p.get("tier", 0)), "level": int(p.get("level", 0))})
		var st := GameData.store_def(StringName(p.store))
		out.shop.append({"store": String(st.get("name", p.store)), "section": String(p.section),
			"name": GameData.product_name(p), "kind": String(p.kind), "price": price})
	store.free()
	for track_id in GameData.upgrade_tracks:
		var track: Dictionary = GameData.upgrade_tracks[track_id]
		for lv in GameData.upgrade_levels(track_id):
			out.tracks.append({"track": String(track.get("display_name", track_id)),
				"level": int(lv.get("level", 0)), "label": String(lv.get("label", "")), "cost": int(lv.get("cost", 0))})
	for id in GameData.buildings:
		var b: BuildingDef = GameData.buildings[id]
		out.buildings.append({"id": String(id), "name": b.display_name, "kind": String(b.kind), "cost": b.cost})
	for id in GameData.tools:
		var t: Dictionary = GameData.tools[id]
		out.tools.append({"name": GameData.tool_name(id), "cost": int(t.get("cost", 0)), "level": int(t.get("level", 1)),
			"start": GameData.start_tools.has(id)})
	for i in GameData.plot_expansions.size():
		var e: Dictionary = GameData.plot_expansions[i]
		out.land.append({"tier": i, "cost": int(e.get("cost", 0)), "size": e.get("size", e.get("half_extent", 0))})
	for id in GameData.items:
		var def: ItemDef = GameData.items[id]
		var d := def.default_dims()
		var vol := Solid.volume(d)
		var piece := int(round(def.base_value_of(d) * Economy.size_bonus(def, d) * Economy.PRICE_SCALE))
		out.items.append({"name": def.display_name, "category": String(def.category),
			"per_m3": def.value_per_m3 * Economy.PRICE_SCALE, "fixed": def.fixed_value,
			"piece_m3": vol, "piece_price": piece, "swing": Economy.volatility(Economy.market_key(id))})
	for key in GameData.materials:
		var m: Dictionary = GameData.materials[key]
		out.materials.append({"name": GameData.item_name(StringName(m.get("raw_item", key))), "path": String(m.get("path", "")),
			"level": int(m.get("level", 1)), "raw": float(m.get("raw", 0)), "pre": float(m.get("pre", 0)), "final": float(m.get("final", 0)),
			"note": String(m.get("note", ""))})
	print("PRICES ", JSON.stringify(out))
	get_tree().quit()
