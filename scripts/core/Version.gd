class_name Version
extends RefCounted

## Which build this is: the version number and when it was made. Every commit
## bumps BuildInfo (see tools/githooks/pre-commit); a version set by hand in
## project.godot (application/config/version) counts too - whichever is
## higher is the one shown. On the pause menu and the title screen.

static func number() -> String:
	var by_hand := String(ProjectSettings.get_setting("application/config/version", ""))
	return by_hand if _newer(by_hand, BuildInfo.NUMBER) else BuildInfo.NUMBER

static func released() -> String:
	var by_hand := String(ProjectSettings.get_setting("application/config/version", ""))
	if _newer(by_hand, BuildInfo.NUMBER):
		return String(ProjectSettings.get_setting("application/config/release_date", ""))
	return BuildInfo.RELEASED

## True if version `a` is higher than `b` (numbers compared part by part).
static func _newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false

## "Pinecraft v0.2.0  ·  released 2026-09-26 15:00 EDT"
static func line() -> String:
	var when := released()
	return "Pinecraft v%s%s" % [number(), ("  ·  released " + when) if when != "" else ""]
