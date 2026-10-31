# Pocket Strangers

A story-driven visual novel with a handful of puzzles, released in five episodes.
Built with **Godot 4.7** (GDScript, GL Compatibility renderer).

> Status: project setup. There's no story content yet.

## Getting started

1. Install [Godot 4.7.x](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** to run. The title screen lists Episodes 1–5. Each one is disabled until it has an entry scene.

## Project layout

```
assets/          art (backgrounds, characters, cgs, ui), audio (music, sfx, ambience, voice), fonts
episodes/epXX/   one folder per episode: episode.tres (metadata) + its scenes and scripts
scenes/main/     boot / title scene
scenes/ui/       shared UI: dialogue box, choice menu, save/load, settings
scenes/puzzles/  reusable puzzle scenes
scripts/autoload/ GameState: current episode, story flags, save/load
scripts/data/    Resource classes (Episode, …)
addons/          third-party Godot plugins
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
