class_name Avatar
extends Node3D

## How another player looks: a body, a head that looks where they look, and
## their name over it. Blocky, like everything else.

var head: Node3D
var label: Label3D

static func color_for(id: int) -> Color:
	var colors := [Color(0.85, 0.35, 0.25), Color(0.25, 0.55, 0.85), Color(0.95, 0.75, 0.2),
		Color(0.45, 0.75, 0.35), Color(0.7, 0.4, 0.8), Color(0.95, 0.55, 0.2), Color(0.3, 0.75, 0.75),
		Color(0.9, 0.9, 0.9)]
	return colors[absi(id) % colors.size()]

func setup(display: String, color: Color) -> void:
	var g := Greeble.new()
	var skin := Color(0.93, 0.78, 0.62)
	var dark := color.darkened(0.45)
	g.box(Vector3(0.5, 0.7, 0.3), Transform3D(Basis(), Vector3(0, 1.1, 0)), color)
	g.box(Vector3(0.2, 0.75, 0.24), Transform3D(Basis(), Vector3(-0.13, 0.38, 0)), dark)
	g.box(Vector3(0.2, 0.75, 0.24), Transform3D(Basis(), Vector3(0.13, 0.38, 0)), dark)
	for side in [-1.0, 1.0]:
		g.box(Vector3(0.14, 0.62, 0.16), Transform3D(Basis(), Vector3(side * 0.33, 1.12, 0)), color.darkened(0.15))
	add_child(g.instance("Body"))
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	var h := Greeble.new()
	h.box(Vector3(0.36, 0.36, 0.36), Transform3D(), skin)
	h.box(Vector3(0.38, 0.1, 0.38), Transform3D(Basis(), Vector3(0, 0.17, 0)), dark)
	h.box(Vector3(0.06, 0.06, 0.02), Transform3D(Basis(), Vector3(-0.08, 0.03, -0.18)), Color(0.1, 0.1, 0.1))
	h.box(Vector3(0.06, 0.06, 0.02), Transform3D(Basis(), Vector3(0.08, 0.03, -0.18)), Color(0.1, 0.1, 0.1))
	head.add_child(h.instance("Head"))
	add_child(head)
	label = Label3D.new()
	label.text = display
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 10
	label.modulate = color.lightened(0.3)
	add_child(label)

## Where they are looking up or down.
func set_pitch(pitch: float) -> void:
	if head != null:
		head.rotation.x = pitch
