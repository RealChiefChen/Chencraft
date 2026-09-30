extends Node

## Autoload. Money, the day clock and the weekly price table.
##
## A day is a full turn of the sun, dawn to dawn. The market moves once a
## week, so there is time to go out, gather and come back to the same prices.
## Prices are deterministic: the multiplier for (week, item) is derived from a
## hash, so a save reloaded on day 12 sees exactly the prices it saw before, and
## no price history needs to be stored.

signal money_changed(amount: int, delta: int)
signal day_changed(day: int)
signal week_changed(week: int)
signal item_sold(item_id: StringName, amount: int)

var money: int = 0
var day: int = 1
var day_time: float = 0.0
var total_earned: int = 0
var items_sold: int = 0

var _day_length: float = 900.0
## Days between price changes.
static var WEEK: int = int(Balance.num("economy.week_days", 7))
var _seed: int = 20260921
var _trend_strength: float = 0.35
var _price_cache: Dictionary = {}
var _cached_day: int = -1

func _ready() -> void:
	_day_length = float(GameData.price_config.get("day_length_seconds", 900.0))
	_seed = int(GameData.price_config.get("seed", 20260921))
	_trend_strength = float(GameData.price_config.get("trend_strength", 0.35))

func _process(delta: float) -> void:
	day_time += delta
	if day_time >= _day_length:
		day_time -= _day_length
		advance_day()

func advance_day() -> void:
	var was := week()
	day += 1
	_price_cache.clear()
	_cached_day = -1
	day_changed.emit(day)
	if week() != was:
		week_changed.emit(week())

## Which market week it is, from 0; day 1 to 7 is the first.
func week() -> int:
	return (day - 1) / WEEK

## Day of the market week, 1 to 7.
func day_of_week() -> int:
	return (day - 1) % WEEK + 1

## Until the market next moves: what is left of today and the rest of the week.
func seconds_left_this_week() -> float:
	return seconds_left_today() + float(WEEK - day_of_week()) * _day_length

## The hour of the day, 0 to 24. A day begins at six in the morning.
func hour() -> float:
	return fposmod(6.0 + day_progress() * 24.0, 24.0)

func day_length() -> float:
	return _day_length

func day_progress() -> float:
	return clampf(day_time / maxf(0.001, _day_length), 0.0, 1.0)

func seconds_left_today() -> float:
	return maxf(0.0, _day_length - day_time)

# --- Money -----------------------------------------------------------------

func add_money(amount: int) -> void:
	if amount == 0:
		return
	money += amount
	if amount > 0:
		total_earned += amount
	money_changed.emit(money, amount)

## Debug setting: everything is affordable and nothing is ever taken off
## you. Earnings still count, so the rest of the game behaves as normal.
func unlimited() -> bool:
	return Settings.flag(&"unlimited_money")

func can_afford(amount: int) -> bool:
	return unlimited() or money >= amount

## Spends `amount` if affordable; returns whether the purchase went through.
func try_spend(amount: int) -> bool:
	if unlimited():
		money_changed.emit(money, 0)
		return true
	if amount > money:
		return false
	money -= amount
	money_changed.emit(money, -amount)
	return true

# --- Prices ----------------------------------------------------------------

## Deterministic pseudo-random value in [-1, 1] for a (day, key) pair.
func _noise(day_index: int, key: String) -> float:
	var h: int = hash("%d:%d:%s" % [_seed, day_index, key])
	# Two mixes so neighbouring keys do not produce visibly similar values.
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h % 20001 - 10000) / 10000.0

## The market moves by material, not by item: mahogany logs, sanded mahogany
## and mahogany lumber all rise and fall together, so a good week for
## mahogany is a good week whatever state you sell it in. Anything that is not
## a material (crates, toolkits) moves on its own.
func market_key(item_id: StringName) -> StringName:
	var mat: Variant = GameData.material_of.get(item_id, null)
	return StringName(mat) if mat != null else item_id

## What a market key is worth per cubic metre as found - the yardstick for how
## much its price swings.
func base_value(key: StringName) -> float:
	var m: Dictionary = GameData.materials.get(key, {})
	if not m.is_empty():
		return float(m.get("raw", 0.0))
	var def: ItemDef = GameData.item(key)
	if def == null:
		return 100.0
	return float(def.fixed_value) if def.fixed_value > 0 else def.value_per_m3

## How far a market key's price swings week to week: cheap stuff is all over
## the place, the dear materials hardly move. Log-scaled between the two ends
## set in balance.json.
static var VOL_CHEAP: float = Balance.num("economy.volatility_cheap", 0.6)
static var VOL_DEAR: float = Balance.num("economy.volatility_dear", 0.06)
static var CHEAP_VALUE: float = Balance.num("economy.cheap_value", 25.0)
static var DEAR_VALUE: float = Balance.num("economy.dear_value", 8000.0)
## Every sale price times this.
static var PRICE_SCALE: float = Balance.num("economy.price_multiplier", 1.0)

func volatility(key: StringName) -> float:
	var v := maxf(1.0, base_value(key))
	var t := clampf(log(v / CHEAP_VALUE) / log(DEAR_VALUE / CHEAP_VALUE), 0.0, 1.0)
	return lerpf(VOL_CHEAP, VOL_DEAR, t)

func _rebuild_prices() -> void:
	_price_cache.clear()
	var category_trend: Dictionary = {}
	for def: ItemDef in GameData.items.values():
		var key := market_key(def.id)
		if _price_cache.has(key):
			continue
		var cat := def.category
		if not category_trend.has(cat):
			category_trend[cat] = _noise(week(), "cat:" + String(cat))
		var swing := volatility(key)
		var mult: float = 1.0 + swing * (0.8 * _noise(week(), String(key)) + _trend_strength * float(category_trend[cat]))
		_price_cache[key] = clampf(mult, 0.35, 2.4)
	_cached_day = day

func price_multiplier(item_id: StringName) -> float:
	if _cached_day != day:
		_rebuild_prices()
	return float(_price_cache.get(market_key(item_id), 1.0))

## Price of one piece at today's rate. Variable items (wood, lumber, billets)
## are priced by volume, so milling a trunk into boards is worth exactly what
## the boards are worth - never more or less because of how it was cut.
func price_of(item_id: StringName, dims: Dictionary = {}) -> int:
	var def: ItemDef = GameData.item(item_id)
	if def == null:
		return 0
	var d := dims if not dims.is_empty() else def.default_dims()
	return maxi(1, int(round(def.base_value_of(d) * size_bonus(def, d) * price_multiplier(item_id) * PRICE_SCALE)))

## Big pieces sell for more per cubic metre: +25% for each doubling past the
## item's usual size, up to +75%. Smaller pieces pay the plain rate.
## Gemstones go further: their price runs with the square of their volume at
## every size - twice the stone, four times the price - so one big stone is
## worth far more than the same stone in pieces.
static func size_bonus(def: ItemDef, dims: Dictionary) -> float:
	if def.fixed_value > 0:
		return 1.0
	var usual := Solid.volume(def.default_dims())
	if usual <= 0.0:
		return 1.0
	var ratio := Solid.volume(dims) / usual
	if def.category == &"gem" or def.category == &"jewel":
		return ratio
	if ratio <= 1.0:
		return 1.0
	return 1.0 + 0.25 * minf(log(ratio) / log(2.0), 3.0)

## Rate per cubic metre, for the market board.
func rate_of(item_id: StringName) -> float:
	var def: ItemDef = GameData.item(item_id)
	if def == null:
		return 0.0
	if def.fixed_value > 0:
		return float(def.fixed_value) * price_multiplier(item_id) * PRICE_SCALE
	return def.value_per_m3 * price_multiplier(item_id) * PRICE_SCALE

func sell(item_id: StringName, dims: Dictionary = {}) -> int:
	var value := price_of(item_id, dims)
	add_money(value)
	items_sold += 1
	item_sold.emit(item_id, value)
	return value

## Sorted market board rows, one per material (every form of it moves
## together) and one per thing that is not a material:
## [{id, name, rate, unit, typical, multiplier, swing}]. `rate` is the raw
## form's price today.
func market_rows() -> Array:
	var rows: Array = []
	var seen: Dictionary = {}
	for def: ItemDef in GameData.items.values():
		if not def.sellable:
			continue            # store boxes: nobody buys those back
		var key := market_key(def.id)
		if seen.has(key):
			continue
		seen[key] = true
		var m: Dictionary = GameData.materials.get(key, {})
		var raw_id: StringName = StringName(m.raw_item) if not m.is_empty() else def.id
		var raw_def := GameData.item(raw_id)
		rows.append({
			"id": key,
			"name": String(key).capitalize() if not m.is_empty() else def.display_name,
			"rate": rate_of(raw_id),
			"unit": "each" if raw_def != null and raw_def.fixed_value > 0 else "m3",
			"typical": price_of(raw_id),
			"multiplier": price_multiplier(raw_id),
			"swing": volatility(key),
		})
	rows.sort_custom(func(a, b): return a.rate < b.rate)
	return rows

func to_dict() -> Dictionary:
	return {"money": money, "day": day, "day_time": day_time,
		"total_earned": total_earned, "items_sold": items_sold}

## A co-op guest told the shared purse and clock by the host: only what
## has actually changed is announced, so the new-day banner shows once a day.
func apply_remote(d: Dictionary) -> void:
	var old_money := money
	var old_day := day
	money = int(d.get("money", money))
	day = int(d.get("day", day))
	day_time = float(d.get("day_time", day_time))
	total_earned = int(d.get("total_earned", total_earned))
	items_sold = int(d.get("items_sold", items_sold))
	if money != old_money:
		money_changed.emit(money, money - old_money)
	if day != old_day:
		var was_week := (old_day - 1) / WEEK
		_price_cache.clear()
		_cached_day = -1
		day_changed.emit(day)
		if week() != was_week:
			week_changed.emit(week())

func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	day_time = float(d.get("day_time", 0.0))
	total_earned = int(d.get("total_earned", 0))
	items_sold = int(d.get("items_sold", 0))
	_cached_day = -1
	money_changed.emit(money, 0)
	day_changed.emit(day)
