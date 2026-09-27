class_name InputSetup
extends RefCounted

## Kept for the callers that set input up by this name: the actions and their
## keys now live in `Controls`, which the player can rebind.

static func ensure() -> void:
	Controls.ensure()
