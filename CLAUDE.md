# Pocket Strangers: agent guide

A story-driven **visual novel** with a couple of puzzles, split into **5 episodes**.
Engine: **Godot 4.7**, GDScript only, GL Compatibility renderer, 1920×1080 base resolution
(`canvas_items` stretch, `expand` aspect).

## Commands

- Import (needed on a fresh checkout, since `.godot/` isn't committed): `godot --headless --path . --import`
- Run tests: `godot --headless --path . --script res://tests/test_runner.gd` (exit code 0 = pass)
- Run game: `godot --path .`

## Structure and conventions

- `episodes/epXX/` holds everything that belongs to one episode: `episode.tres` (an `Episode` resource) plus
  that episode's scenes, scripts, and dialogue. Set `entry_scene` on the resource to make an episode playable.
  Assets used by only one episode can go in its folder. Shared assets go in `assets/`.
- `scripts/autoload/game_state.gd` (`GameState`) is the single source of story state: `current_episode`,
  `completed_episodes`, and `flags`. Story choices and puzzle results are written as flags
  (`GameState.set_flag(&"ep01_helped_stranger")`). Prefix flags with the episode id.
- Episode ids are `ep01`…`ep05` and are stored in save data, so don't rename them.
- Use data-driven `Resource` classes (`scripts/data/`) instead of hard-coded tables.
- GDScript style: static typing everywhere, tabs, `snake_case` files and functions, `PascalCase` classes and nodes.
  Use `%UniqueName` for node lookups inside a scene.
- File names: `snake_case`. Assets: `bg_<place>_<time>.png`, `chr_<name>_<pose>_<expression>.png`,
  `cg_epXX_<moment>.png`, `mus_<mood>.ogg`, `sfx_<thing>.ogg`.
- Add a test in `tests/test_runner.gd` (`test_*` method returning `true`) for any non-UI logic: state, saves,
  puzzle rules. Don't use bare `assert()` in tests because it hangs the headless run.

## Open decisions (ask before assuming)

- Dialogue/scripting: a custom system, or an addon (Dialogue Manager, Dialogic 2, …)?
- Target platforms: desktop, web, mobile?
- Art style and resolution of character sprites.
- Localization.

## Agent skills

Game design and development skills live in `.claude/skills/` (taken from
[awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)).
Before writing code or design, load the skills that match the task. See `.claude/skills/README.md`.
