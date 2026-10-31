# Agent skills

Claude Code loads skills from this folder. Each skill is a folder that contains a `SKILL.md`:

```
.claude/skills/<skill-name>/SKILL.md
```

## Source

Copied from [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
at commit `19d93f9` (2026-10-28). Licensed under Apache-2.0, see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

These are a subset of the upstream 77 skills, chosen for a Godot visual novel with puzzles. The `router` skill
knows about the whole catalog, so it may name a skill that isn't installed here (e.g. `godot-2d-movement`).
If that happens and the skill would help, copy it in from upstream.

**To add or update a skill:** copy its folder from upstream `skills/<category>/<name>/` into this folder, with
any `references/`, `scripts/` and `assets/` inside it. Then update the commit and the table below.

## Installed

| Skill | Upstream category | Why |
|-------|-------------------|-----|
| `router` | (root) | Picks the right skills for each request |
| `visual-novel` | genres | The core genre |
| `puzzle` | genres | The puzzle segments |
| `dialogue-systems` | disciplines | Branching dialogue and choices |
| `save-systems` | disciplines | Save slots, story-flag persistence |
| `game-ui-ux` | disciplines | Dialogue box, menus, readability |
| `audio-design` | disciplines | Music and ambience for mood |
| `create-game-assets` | disciplines | Consistent character/background art |
| `godot-gdscript` | godot | Language idioms |
| `godot-nodes-scenes` | godot | Scene structure, autoloads |
| `godot-signals-groups` | godot | Event-driven flow |
| `godot-ui-control` | godot | Control nodes, themes, focus |
| `godot-animation` | godot | Tweens, character transitions |
| `godot-resources` | godot | Data-driven episodes/dialogue |
| `godot-audio` | godot | Audio buses and players |
| `godot-export` | godot | Builds |
| `godot-gdscript-headless-testing` | godot | Tests and CI |
| `itch-publish` | workflows | Shipping on itch.io |
| `steam-publish` | workflows | Shipping on Steam |

## Helper scripts

A few skills include Python helpers. They only read local files, except `build_preview_sheet.py`, which writes the
preview image to the path you give it. None of them make network calls.

- `godot-nodes-scenes/scripts/check_godot_project.py`: checks `.tscn`/`.tres`/`project.godot` for broken references.
- `create-game-assets/scripts/asset_report.py`, `build_preview_sheet.py`: art consistency reports (need Pillow).
- `steam-publish/scripts/check_steam_build.py`: checks SteamPipe build scripts.
