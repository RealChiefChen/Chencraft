class_name Version
extends RefCounted

## Which build this is: the version number and when it was released, both set
## in project.godot (application/config/version and release_date) - bump them
## there when cutting a release. Shown on the pause menu and the title screen.

static func number() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))

static func released() -> String:
	return String(ProjectSettings.get_setting("application/config/release_date", ""))

## "Pinecraft v0.2.0  ·  released 2026-09-26 15:00 EDT"
static func line() -> String:
	var when := released()
	return "Pinecraft v%s%s" % [number(), ("  ·  released " + when) if when != "" else ""]
