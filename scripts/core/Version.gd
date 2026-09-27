class_name Version
extends RefCounted

## Which build this is: the version number and when it was made. Both come
## from BuildInfo, which every commit bumps (see tools/githooks/pre-commit).
## Shown on the pause menu and the title screen.

static func number() -> String:
	return BuildInfo.NUMBER

static func released() -> String:
	return BuildInfo.RELEASED

## "Pinecraft v0.2.0  ·  released 2026-09-26 15:00 EDT"
static func line() -> String:
	var when := released()
	return "Pinecraft v%s%s" % [number(), ("  ·  released " + when) if when != "" else ""]
