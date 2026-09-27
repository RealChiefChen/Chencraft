# Pinecraft - notes for whoever works on this repo

- Version: every commit bumps the version (scripts/core/BuildInfo.gd) through
  the hook in tools/githooks. Turn it on once in each clone:
  `git config core.hooksPath tools/githooks`
  If the hook is not on, bump the last number in BuildInfo.gd and stamp the
  date and time yourself before committing.
- Tests: `godot --headless --path . --fixed-fps 60 scenes/tests.tscn`
- Blender sources live in assets/models/source (Godot skips that folder).
