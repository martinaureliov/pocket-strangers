# Pocket Strangers: agent guide

A story-driven **visual novel** with a couple of puzzles, split into **5 episodes**.
Engine: **Godot 4.7**, GDScript only, GL Compatibility renderer, 1920×1080 base resolution
(`canvas_items` stretch, `expand` aspect).

## Commands

- Import (needed on a fresh checkout, since `.godot/` isn't committed): `godot --headless --path . --import`
- Run tests: `godot --headless --path . --script res://tests/test_runner.gd` (exit code 0 = pass)
- Run game: `godot --path .`
- Check for new Godot releases: `tools/check_versions.sh`

## Keep the user informed about new versions

At the start of each session, run `tools/check_versions.sh`. Tell the user if a new **stable** Godot release is
out, so they can download it. Mention a new beta or RC only briefly, as information, and don't recommend
switching to it. The pinned version is `GODOT_VERSION` in `.github/workflows/ci.yml`. When upgrading, change it
there and in `config/features` in `project.godot`, and update the version notes in `README.md` and here.
The same applies to any addon added to `addons/` (e.g. Dialogue Manager): mention new releases when you notice them.

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
  `cg_epXX_<moment>.png`, `mus_<mood>.ogg`, `sfx_<thing>.ogg`. The VN player finds art by these names
  (`Stage.background("bus_stop_night")` → `assets/art/backgrounds/bg_bus_stop_night.png`; pose defaults to `default`)
  and draws a labeled placeholder when a file is missing.
- Add a test in `tests/test_runner.gd` (`test_*` method returning `true`) for any non-UI logic: state, saves,
  puzzle rules. Don't use bare `assert()` in tests because it hangs the headless run.

## Dialogue (Dialogue Manager 4)

Story scripts use [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) **v4.2.0**, vendored in
`addons/dialogue_manager/` (registered as the `DialogueManager` autoload, plugin enabled in `project.godot`).
Docs (match the installed version): https://github.com/nathanhoad/godot_dialogue_manager/tree/v4.2.0/docs

- Dialogue files live in `episodes/epXX/dialogue/*.dialogue`. Cue names are `snake_case`; each file starts at `~ start`.
- Dialogue reads and writes story state only through `GameState`: conditions like
  `[if GameState.has_flag("ep01_helped_stranger") /]` and mutations like `$> GameState.set_flag("ep01_helped_stranger")`.
  Don't keep story state in other autoloads or in dialogue-local variables.
- Keep presentation (backgrounds, sprites, transitions, music) out of dialogue text. Trigger it with mutations that call
  a stage/presentation node, so the same script works in tests.
- Mutations use `$>` (`do`/`set` are deprecated in v4).
- Don't edit files inside `addons/dialogue_manager/`, so updates stay a clean replace. Update with the plugin's
  built-in updater (Dialogue tab in the editor) or by copying a new release, then commit the whole folder.
- The addon ships C# versions of some files (`*.cs` and the PascalCase `.tscn` files, e.g. `ExampleBalloon.tscn`). This project is GDScript-only;
  use the lower-case GDScript versions (`example_balloon.tscn`, `dialogue_label.tscn`).

## VN player, stage commands, puzzles

- An episode's entry scene inherits `scenes/vn/vn_player.tscn` and sets `dialogue` and `episode_id`
  (see `episodes/ep01/ep01.tscn`). `VNPlayer` shows lines, choices, backlog, auto, skip (read lines only),
  quick save/load; `StoryRunner` (`scripts/vn/`) does the stepping and has no UI, so tests can drive it.
- Dialogue controls the screen through the `Stage` alias (methods on `VNPlayer`):
  - `$> Stage.background("bus_stop_night")`
  - `$> Stage.show_character("stranger", "smile", "right")` (expression, slot `left|center|right`, pose). Calling it
    again for a shown character swaps the expression/slot.
  - `$> Stage.hide_character("stranger")`, `$> Stage.clear_characters()`
  - `$> Stage.puzzle("res://scenes/puzzles/<name>/<name>.tscn", "ep01_<result_flag>")` waits for the puzzle and stores
    `true`/`false` in that flag. Branch on it with `if GameState.get_flag("ep01_<result_flag>") == true`.
- **When adding a Stage command, also add it to `FakeStage` in `tests/test_runner.gd`**: Dialogue Manager asserts
  (and the headless run hangs) when a script calls a method the stage doesn't have.
- Narration lines must not contain `: ` (Dialogue Manager reads text before it as a speaker name).
- Puzzles: scene root extends `Puzzle` (`scenes/puzzles/puzzle.gd`) and calls `finish(solved)` once. Put the rules in a
  UI-free `RefCounted` class in `scripts/puzzles/` with tests (see `CombinationLock`).
- Saves: one slot at `user://save.json` (crash-safe, with `.bak`). A save stores the dialogue line id, which is the
  line number, so editing a dialogue file can move or invalidate saved positions (an unknown id restarts the file).
  Before release, switch to static line IDs or save only at cue boundaries. Bump `SAVE_VERSION` and extend
  `GameState.migrate()` whenever the save format changes.

## Open decisions (ask before assuming)

- Target platforms: desktop, web, mobile?
- Art style and resolution of character sprites.
- Localization.

## Agent skills

Game design and development skills live in `.claude/skills/` (taken from
[awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)).
Before writing code or design, load the skills that match the task. See `.claude/skills/README.md`.
