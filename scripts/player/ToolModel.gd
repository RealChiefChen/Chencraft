class_name ToolModel
extends RefCounted

## A hand tool as a mesh, built from its row in tools.json: a handle and a
## head, an axe's blade (or two, on a twin-bit) or a hammer's block. Used for
## the one in your hand and on the store shelf.

static func mesh(def: Dictionary) -> ArrayMesh:
	var g := Greeble.new()
	var head := _color(def.get("head", [0.6, 0.6, 0.62]))
	var handle := _color(def.get("handle", [0.5, 0.35, 0.2]))
	var glow := bool(def.get("glow", false))
	var hammer := String(def.get("kind", "axe")) == "hammer"
	var length := 0.72 if hammer else 0.78
	# The handle runs up +Y from the grip.
	g.box(Vector3(0.045, length, 0.045), Transform3D(Basis(), Vector3(0, length * 0.5, 0)), handle)
	g.box(Vector3(0.055, 0.12, 0.055), Transform3D(Basis(), Vector3(0, 0.08, 0)), handle.darkened(0.3))
	var top := Vector3(0, length - 0.05, 0)
	if hammer:
		var kg := float(def.get("head_kg", 3.0))
		var s := clampf(0.1 + kg * 0.006, 0.1, 0.3)
		g.box(Vector3(s * 2.2, s, s), Transform3D(Basis(), top), head, glow)
		for side in [-1.0, 1.0]:
			g.box(Vector3(0.03, s * 1.1, s * 1.1), Transform3D(Basis(), top + Vector3(side * s * 1.1, 0, 0)), head.darkened(0.25))
	else:
		var sides := [1.0, -1.0] if bool(def.get("twin", false)) else [1.0]
		g.box(Vector3(0.08, 0.1, 0.06), Transform3D(Basis(), top), head.darkened(0.3))
		for side in sides:
			_blade(g, top, side, head, glow)
	return g.commit()

## One blade: from the eye out to the edge along +X (or -X), flaring from
## the eye's height to a longer edge and thinning evenly on both faces to a
## bright honed strip. Nothing reaches past the edge.
static func _blade(g: Greeble, top: Vector3, side: float, head: Color, glow: bool) -> void:
	var x0 := 0.04
	var x1 := 0.215
	var hone := 0.02
	var half_eye := 0.05
	var half_edge := 0.1
	var thick := 0.0175
	var thin := 0.004
	var p := func(x: float, y: float, z: float) -> Vector3: return top + Vector3(side * x, y, z)
	var hx := x1 - hone
	var hy := lerpf(half_eye, half_edge, (hx - x0) / (x1 - x0))
	var ht := lerpf(thick, thin, (hx - x0) / (x1 - x0))
	for zs in [-1.0, 1.0]:
		var out := Vector3(0, 0, zs)
		# The cheek, eye to the start of the hone.
		g.quad(p.call(x0, -half_eye, zs * thick), p.call(x0, half_eye, zs * thick),
			p.call(hx, hy, zs * ht), p.call(hx, -hy, zs * ht), out, head, glow)
		# The honed strip, out to the edge.
		g.quad(p.call(hx, -hy, zs * ht), p.call(hx, hy, zs * ht),
			p.call(x1, half_edge, zs * thin), p.call(x1, -half_edge, zs * thin), out, head.lightened(0.35), glow)
	for ys in [-1.0, 1.0]:
		var out := Vector3(0, ys, 0)
		g.quad(p.call(x0, ys * half_eye, -thick), p.call(x0, ys * half_eye, thick),
			p.call(hx, ys * hy, ht), p.call(hx, ys * hy, -ht), out, head.darkened(0.1), glow)
		g.quad(p.call(hx, ys * hy, -ht), p.call(hx, ys * hy, ht),
			p.call(x1, ys * half_edge, thin), p.call(x1, ys * half_edge, -thin), out, head.darkened(0.1), glow)
	g.quad(p.call(x1, -half_edge, -thin), p.call(x1, half_edge, -thin),
		p.call(x1, half_edge, thin), p.call(x1, -half_edge, thin), Vector3(side, 0, 0), head.lightened(0.45), glow)

static func _color(a: Variant) -> Color:
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))

static func color_of(def: Dictionary) -> Color:
	return _color(def.get("head", [0.6, 0.6, 0.62]))
