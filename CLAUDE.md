# Pinecraft - notes for whoever works on this repo

- Version: every commit bumps the version (scripts/core/BuildInfo.gd) through
  the hook in tools/githooks. Turn it on once in each clone:
  `git config core.hooksPath tools/githooks`
  If the hook is not on, bump the last number in BuildInfo.gd and stamp the
  date and time yourself before committing.
- Tests: `godot --headless --path . --fixed-fps 60 scenes/tests.tscn`
- Blender sources live in assets/models/source (Godot skips that folder).
- Task lists from the owner: before starting, add them to the "Done" tab of
  the Pinecraft sheet
  (https://docs.google.com/spreadsheets/d/1KP1TiR1jUg4sx_UkPvOKv9D3OYDOpfhRgl8T9DMLTxk),
  one task per row in column A, at the top of the list (just under the DONE
  header in row 1, above the earlier batches), with a thick bar under the new
  batch. As each task is done, fill its cell red (background, not text).
- Balance tab of that sheet: tools/PriceDump.gd dumps every price. In the
  "Every sellable item" table, rate/level/piece/swing cells are formulas that
  point at the materials table above it, not typed numbers.
