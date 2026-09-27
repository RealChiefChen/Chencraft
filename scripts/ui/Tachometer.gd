class_name Tachometer
extends Control

## A rev counter for a manual gearbox: a dial from idle to past the red line,
## a needle, and the gear in the middle. Set `rpm`, `redline` and `gear`.

var rpm: float = 0.0
var redline: float = 6000.0
var top: float = 7000.0
var gear: String = "1"

func _init() -> void:
	custom_minimum_size = Vector2(96, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_reading(p_rpm: float, p_redline: float, p_gear: String) -> void:
	rpm = p_rpm
	redline = p_redline
	top = p_redline * 1.15
	gear = p_gear
	queue_redraw()

func _angle(v: float) -> float:
	# 225 degrees of sweep, from lower left round to lower right.
	return deg_to_rad(135.0) + deg_to_rad(270.0) * clampf(v / top, 0.0, 1.0)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.45))
	draw_arc(c, r, _angle(0.0), _angle(redline), 48, Color(1, 1, 1, 0.55), 3.0, true)
	draw_arc(c, r, _angle(redline), _angle(top), 16, Color(1.0, 0.25, 0.2), 5.0, true)
	var step := 1000.0
	var v := 0.0
	while v <= top + 1.0:
		var a := _angle(v)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 8.0), c + dir * r, Color(1, 1, 1, 0.8), 2.0, true)
		v += step
	var na := _angle(rpm)
	var over := rpm >= redline
	draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 4.0), Color(1.0, 0.3, 0.2) if over else Color(1.0, 0.8, 0.3), 3.0, true)
	draw_circle(c, 5.0, Color(0.9, 0.9, 0.9))
	var font := get_theme_default_font()
	var fs := 22
	var w := font.get_string_size(gear, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, r * 0.62), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var label := "x1000 rpm"
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 9).x
	draw_string(font, c + Vector2(-lw * 0.5, -r * 0.42), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.6))
