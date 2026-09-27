class_name Bridge
extends StaticBody3D

## A road bridge over open water: a plank deck on steel girders, a gentle arch
## so it clears the waves, rails down both sides and piers into the sea bed.
##
## The deck is drawn as a run of slabs along the arch; what you drive on is
## one smooth surface following it, carried on past each end and down into
## the road, so a truck at speed meets no joint and no lip.

const WIDTH := 10.0
const DECK := 0.6
const SLAB := 8.0
const RAIL := 1.1

var from_point: Vector3
var to_point: Vector3
var terrain: Terrain

func setup(a: Vector3, b: Vector3, p_terrain: Terrain) -> void:
	from_point = a
	to_point = b
	terrain = p_terrain

## Deck-top height at `t` (0..1) along the span.
func deck_height(t: float) -> float:
	var span := Vector2(to_point.x - from_point.x, to_point.z - from_point.z).length()
	var arch := minf(4.0, span * 0.025)
	return lerpf(from_point.y, to_point.y, t) + arch * sin(PI * t)

func _ready() -> void:
	add_to_group(&"bridges")
	collision_layer = Layers.WORLD
	collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	physics_material_override = pm
	var flat := Vector3(to_point.x - from_point.x, 0.0, to_point.z - from_point.z)
	var span := flat.length()
	if span < 1.0:
		return
	var dir := flat / span
	var side := Vector3.UP.cross(dir).normalized()
	var wood := Color(0.52, 0.38, 0.24)
	var steel := Color(0.34, 0.36, 0.40)
	var paint := Color(0.72, 0.22, 0.16)
	var g := Greeble.new()
	var slabs := maxi(2, int(ceil(span / SLAB)))
	for i in slabs:
		var t0 := float(i) / float(slabs)
		var t1 := float(i + 1) / float(slabs)
		var p0 := from_point + dir * span * t0
		var p1 := from_point + dir * span * t1
		p0.y = deck_height(t0)
		p1.y = deck_height(t1)
		var run := p1 - p0
		var along := run.normalized()
		var up := side.cross(along).normalized() * -1.0
		if up.y < 0.0:
			up = -up
		var basis := Basis(side, up, along)
		# A touch longer than its slice so neighbouring slabs overlap.
		var length := run.length() + 0.3
		var centre := (p0 + p1) * 0.5 - up * DECK * 0.5
		g.box(Vector3(WIDTH, DECK * 0.4, length), Transform3D(basis, centre + up * DECK * 0.3), wood)
		for k in 3:
			g.box(Vector3(0.4, DECK * 0.7, length), Transform3D(basis,
				centre + side * (float(k) - 1.0) * WIDTH * 0.4 - up * DECK * 0.3), steel)
		# Rails: posts and a top bar each side, solid so nothing rolls off.
		for s in [-1.0, 1.0]:
			var edge: Vector3 = centre + side * s * (WIDTH * 0.5 - 0.15) + up * (DECK * 0.5 + RAIL * 0.5)
			g.box(Vector3(0.14, 0.12, length), Transform3D(basis, edge + up * RAIL * 0.45), paint)
			g.box(Vector3(0.1, 0.08, length), Transform3D(basis, edge), paint.darkened(0.2))
			g.box(Vector3(0.14, RAIL, 0.14), Transform3D(basis, edge), paint)
			var rail := CollisionShape3D.new()
			var rail_box := BoxShape3D.new()
			rail_box.size = Vector3(0.25, RAIL, length)
			rail.shape = rail_box
			rail.transform = Transform3D(basis, edge)
			add_child(rail)
		# A pier every other slab, down to the sea bed.
		if i % 2 == 1 and i < slabs - 1:
			var foot := p0
			var bed := terrain.height_at(foot.x, foot.z) if terrain != null else foot.y - 8.0
			if bed < foot.y - 2.0:
				for s2 in [-1.0, 1.0]:
					var top: Vector3 = foot + side * s2 * WIDTH * 0.32 - Vector3(0, DECK, 0)
					g.pipe(Vector3(top.x, bed - 0.5, top.z), top, 0.45, Color(0.58, 0.56, 0.52), 8)
				g.box(Vector3(WIDTH * 0.8, 0.7, 1.0), Transform3D(Basis(side, Vector3.UP, dir),
					foot - Vector3(0, DECK + 0.35, 0)), Color(0.58, 0.56, 0.52))
	var mesh := g.instance("Deck")
	add_child(mesh)
	_build_deck_surface(dir, side, span)

## The deck you drive on is one smooth surface - short steps along the arch,
## all one shape, so there are no box edges at the joints for a wheel to
## catch at speed - carried a little way on past each end and down into the
## road, so there is no lip where the road meets it either.
const STEP := 1.0
const RUN_OFF := 3.0

func _build_deck_surface(dir: Vector3, side: Vector3, span: float) -> void:
	var faces := PackedVector3Array()
	var n := maxi(4, int(ceil(span / STEP)))
	var pts: Array[Vector3] = []
	# Run-off in front of the start, sinking into the road.
	pts.append(from_point - dir * RUN_OFF + Vector3(0, -0.25, 0))
	for i in n + 1:
		var t := float(i) / float(n)
		var p := from_point + dir * span * t
		p.y = deck_height(t)
		pts.append(p)
	pts.append(to_point + dir * RUN_OFF + Vector3(0, -0.25, 0))
	var half := side * WIDTH * 0.5
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		faces.append_array([a - half, a + half, b + half, a - half, b + half, b - half])
		# The underside, a deck's thickness down, so it is solid from below too.
		var d := Vector3(0, -DECK, 0)
		faces.append_array([a - half + d, b + half + d, a + half + d, a - half + d, b - half + d, b + half + d])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "DeckSurface"
	cs.shape = shape
	add_child(cs)

## Where the deck is under a point, if the point is over the deck.
func over_deck(point: Vector3) -> bool:
	var flat := Vector3(to_point.x - from_point.x, 0.0, to_point.z - from_point.z)
	var span := flat.length()
	var dir := flat / maxf(0.001, span)
	var rel := Vector3(point.x - from_point.x, 0.0, point.z - from_point.z)
	var along := rel.dot(dir)
	var across := absf(rel.dot(Vector3.UP.cross(dir).normalized()))
	return along >= 0.0 and along <= span and across <= WIDTH * 0.5

## On the deck: over it, and up at its level rather than down in the water
## under it.
func on_deck(point: Vector3) -> bool:
	if not over_deck(point):
		return false
	var flat := Vector3(to_point.x - from_point.x, 0.0, to_point.z - from_point.z)
	var span := flat.length()
	var t := Vector3(point.x - from_point.x, 0.0, point.z - from_point.z).dot(flat / maxf(0.001, span)) / maxf(0.001, span)
	var rise := point.y - deck_height(t)
	return rise > -1.0 and rise < 4.0
