class_name Ladder
extends Node3D

## A ladder up the side of a vehicle to its cab roof. It is not a thing you
## stand on: a player inside its box climbs (forward or jump goes up, down
## goes down) and hangs rather than falling. `size` is the box, in its own
## frame, centred on it.

var size: Vector3 = Vector3(0.9, 2.0, 0.6)

func _ready() -> void:
	add_to_group(&"ladders")
	var g := Greeble.new()
	var steel := Color(0.62, 0.63, 0.66)
	var h := size.y - 0.3
	for side in [-1.0, 1.0]:
		g.box(Vector3(0.05, h, 0.05), Transform3D(Basis(), Vector3(0, 0, side * 0.2)), steel)
	var rungs := int(h / 0.3)
	for i in rungs:
		var y := -h * 0.5 + 0.15 + float(i) * 0.3
		g.box(Vector3(0.04, 0.04, 0.4), Transform3D(Basis(), Vector3(0, y, 0)), steel.darkened(0.15))
	var mi := g.instance("Rungs")
	mi.position = Vector3(size.x * 0.5 - 0.05, -0.15, 0)
	add_child(mi)

## Whether a point (a player's feet) is on this ladder.
func holds(point: Vector3) -> bool:
	var p := global_transform.affine_inverse() * point
	return absf(p.x) <= size.x * 0.5 and absf(p.z) <= size.z * 0.5 and p.y >= -size.y * 0.5 - 0.2 and p.y <= size.y * 0.5
