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
opens the log. The top-right buttons are Save, Load, Log, Auto, Skip (only lines you've read), Settings and Title.
Save and Load open a slot screen (Auto plus 9 slots); Esc or Back closes it, and saving over a used slot asks first.
The Auto slot is written at the end of each episode. When a save exists, the title screen has Continue (latest
save) and Load. Settings (text speed, auto speed, volumes, fullscreen) is at the bottom of the title screen's list
and in the quick menu; Esc or Back closes it and saves.

## Project layout

```
assets/          art (backgrounds, characters, cgs, ui), audio (music, sfx, ambience, voice), fonts
episodes/epXX/   one folder per episode: episode.tres (metadata), dialogue/*.dialogue, scenes, scripts
scenes/main/     boot / title scene
scenes/vn/       VN player: background, characters, text box, choices, backlog, auto/skip, save/load
scenes/ui/       other shared UI: save_load_screen/ (slot list), settings_screen/
scenes/puzzles/  puzzle scenes (extend Puzzle)
scripts/autoload/ GameState (current episode, story flags, save/load), Settings (player preferences), Audio (music, ambience, sfx)
scripts/data/    Resource classes (Episode, …)
scripts/vn/      StoryRunner: steps through dialogue without UI
scripts/puzzles/ puzzle rules (testable, no UI)
addons/          third-party Godot plugins (Dialogue Manager 4)
tests/           headless GDScript tests
tools/audio/     music and sound effect generators (music_tracks.json is the track list)
docs/            game design docs
.claude/skills/  agent skills for game design and development
```

## Regenerating audio

Music comes from Google's Lyria models through the Gemini API; sound effects are synthesized locally or taken from
Kenney's CC0 packs. Install the requirements and set `GEMINI_API_KEY` (paid tier; a full track costs about $0.08):

```bash
pip install -r tools/audio/requirements.txt
python tools/audio/generate_music.py [--dry-run] [names] [--force]
python tools/audio/synth_sfx.py
```

`--dry-run` shows what would be generated and what it would cost. Names limit the run to some tracks; `--force`
regenerates tracks that already exist; `--reprocess` redoes the looping and loudness on the saved raw downloads in
`build/audio_raw/` without calling the API. The tool keeps a cost ledger in `tools/audio/generation_log.json` and
stops at its budget cap. Output goes to `assets/audio/`, credits are in each folder's `CREDITS.md`.

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
