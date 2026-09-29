# Pinecraft

**Fell it, haul it, mill it, sell it - then build the machines that do it for you.**

Pinecraft is a physics-first logging and mining sandbox. Every log is a real,
loose, rolling solid with its own weight; every rock is part-buried and has to be
heaved out or hammered apart. Cut trees limb by limb, strap the load down (or
don't) and drive it over the bridges between islands, feed it down conveyors
through tunnel machines that plank, sand, crush, smelt, refine and cut gems, and
sell it at the yard for whatever the market pays today.

- A big island world with other islands beyond it - snowfields, desert, mountains,
  wet woods and a crater where something fell from the sky - joined by winding
  roads, bridges and a causeway.
- Cave networks under it all, well below sea level: big chambers and tight
  tunnels running back and forth, ice caves, desert caves, river caves, crystal
  and fungal caves, each with its own resources - and one tunnel that goes
  under the sea to an island you cannot reach any other way.
- Seventeen kinds of tree, twenty-odd ores and gemstones, and materials that do
  not always behave: some are worth more raw, some only pay once they are
  fully refined.
- Seven vehicles, from a quad to a log truck and a crane truck; two stores; a
  build mode with handles for moving, scaling and rotating what you place.

No asset files: everything you see is built in code from primitives.

## Install and play

1. Install **Godot 4.4 or later** (standard build, not .NET).
   - Windows/macOS: download from <https://godotengine.org/download/>.
   - NixOS: `nix profile install nixpkgs#godot` (installs 4.6 or whatever is current).
2. Get the game:
   ```bash
   git clone https://github.com/dell1388/pinecraft.git
   ```
3. On first run, rebuild the class cache (required after a fresh clone or any
   pull that adds new scripts):
   ```bash
   godot --headless --editor --quit --path pinecraft
   ```
4. Run it:
   ```bash
   godot --path pinecraft
   ```
   Or use the included helper which pulls, rebuilds the cache when needed, and
   launches in one step:
   ```bash
   bash pinecraft/run.sh           # normal
   bash pinecraft/run.sh verbose   # verbose log to /tmp/pinecraft.log
   ```

**First launch** compiles shaders and builds the world — expect 1–3 minutes
before the title screen appears. Later launches are fast.

**Known issue — Godot 4.6 + AMD Zen 5 (Ryzen 9000 series):** the engine's
occlusion culling hits a crash in its bundled `libembree4` AVX-512 path.
Pinecraft disables occlusion culling to work around this (`project.godot` +
`_build_occluders` skipped in `Terrain.gd`). No action needed on your part.

Controls are on the title screen's Controls page and in the in-game journal
(**F1**). The essentials: **WASD** to move, **left mouse** on something with an
empty hand to drag it, **1-9** for your tools, **E** to use things, **F** to
get into vehicles, **B** for build mode (then **E** for the build menu),
**Tab** for the journal, **F2** for first or third person. Every key can be
rebound in Settings > Controls. If the game runs slowly, Settings > Video > Graphics
quality has Low, Medium and High presets.

Your settings and key bindings are kept in one commented, hand-editable
config file, `config.cfg` in the game's user folder (on Windows
`%APPDATA%\Godot\app_userdata\Pinecraft\`; Settings has a button that opens
it). Saves are in the `saves` folder next to it - six slots. The balance
constants (speeds, prices, strengths) are in `data/balance.json`.

## For developers

```bash
godot --headless --path . --fixed-fps 60 scenes/tests.tscn        # integration tests
godot --headless --path . --fixed-fps 60 scenes/smoke_world.tscn  # boot the whole world headless
```

After adding a script with a new `class_name`, run
`godot --headless --editor --quit --path .` once to refresh the class cache.

Design notes, systems and measurements live in [docs/GUIDE.md](docs/GUIDE.md)
for now.

## Version numbers

Every commit bumps the version shown on the title screen and pause menu (the
last number goes up by one, and the date is stamped): see
`tools/githooks/pre-commit`. Turn the hook on once after cloning:

```
git config core.hooksPath tools/githooks
```
