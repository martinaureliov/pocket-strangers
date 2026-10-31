# Agent skills

Claude Code loads skills from this folder. Each skill is a folder that contains a `SKILL.md`:

```
.claude/skills/<skill-name>/SKILL.md
```

## Source

[gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
(Apache-2.0). To add a skill, copy its folder from that repo's `skills/<category>/<name>/` into this
folder, including any `references/`, `scripts/` and `assets/` inside it. Also copy the repo's `router/`
folder in as `router/` so the agent can pick skills automatically. Keep the upstream `LICENSE`/`NOTICE`
next to the copied skills.

## Suggested skills for this project

| Skill | Category | Why |
|-------|----------|-----|
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
| `itch-publish` / `steam-publish` | workflows | Shipping, later on |
