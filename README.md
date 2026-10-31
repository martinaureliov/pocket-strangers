# Pocket Strangers

A story-driven visual novel with a handful of puzzles, released in five episodes.
Built with **Godot 4.7** (GDScript, GL Compatibility renderer) and
[Dialogue Manager 4](https://github.com/nathanhoad/godot_dialogue_manager) for story scripts.

> Status: vertical slice. Episode 1 is a short placeholder scene that exercises every system
> (dialogue, choices, flags, a puzzle, save/load); there's no real story content yet.

## Getting started

1. Install [Godot 4.7.x](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** to run. The title screen lists Episodes 1–5. Each one is disabled until it has an entry scene.

**Controls:** click or Space/Enter to advance; click again while text is typing to show it all. Mouse wheel up
opens the log. The top-right buttons are Save, Load, Log, Auto, Skip (only lines you've read) and Title.
Save and Load open a slot screen (Auto plus 9 slots); Esc or Back closes it, and saving over a used slot asks first.
The Auto slot is written at the end of each episode. When a save exists, the title screen has Continue (latest
save) and Load.

## Project layout

```
assets/          art (backgrounds, characters, cgs, ui), audio (music, sfx, ambience, voice), fonts
episodes/epXX/   one folder per episode: episode.tres (metadata), dialogue/*.dialogue, scenes, scripts
scenes/main/     boot / title scene
scenes/vn/       VN player: background, characters, text box, choices, backlog, auto/skip, save/load
scenes/ui/       other shared UI: save_load_screen/ (slot list), later settings and menus
scenes/puzzles/  puzzle scenes (extend Puzzle)
scripts/autoload/ GameState: current episode, story flags, save/load
scripts/data/    Resource classes (Episode, …)
scripts/vn/      StoryRunner: steps through dialogue without UI
scripts/puzzles/ puzzle rules (testable, no UI)
addons/          third-party Godot plugins (Dialogue Manager 4)
tests/           headless GDScript tests
docs/            game design docs
.claude/skills/  agent skills for game design and development
```

## Tests

```bash
godot --headless --path . --import
```

```bash
godot --headless --path . --script res://tests/test_runner.gd
```

CI (`.github/workflows/ci.yml`) runs both on every push and pull request.

## Docs

- [Game design document](docs/GAME_DESIGN.md)
- [Agent / contributor guide](CLAUDE.md)
- [Prompt for continuing in a local Claude Code session (Windows)](docs/LOCAL_SESSION_PROMPT.md)
