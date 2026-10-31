# Pocket Strangers: game design document

> Working draft. Sections marked **TBD** are still open.

## Pitch

**TBD**: one or two sentences on what the player experiences and why it matters.

## Pillars

1. **Storytelling first.** Narrative, characters, and choices drive the experience.
2. **Puzzles serve the story.** A few puzzles, each tied to a story beat, never filler.
3. **Episodic.** Five self-contained episodes that together form one arc.

## Format

| | |
|---|---|
| Genre | Visual novel with light puzzles |
| Engine | Godot 4.7 |
| Structure | 5 episodes |
| Platforms | **TBD** |
| Target length | **TBD** per episode |

## Episodes

| # | Id | Title | Synopsis | Puzzle(s) |
|---|------|-------|----------|-----------|
| 1 | ep01 | TBD | TBD | TBD |
| 2 | ep02 | TBD | TBD | TBD |
| 3 | ep03 | TBD | TBD | TBD |
| 4 | ep04 | TBD | TBD | TBD |
| 5 | ep05 | TBD | TBD | TBD |

## Characters

**TBD**

## Choices and state

- Choices and puzzle outcomes are stored as story flags in `GameState` (see `CLAUDE.md`).
- **TBD**: Do choices carry across episodes? Are there multiple endings?

## Puzzles

**TBD**: puzzle types, difficulty, hints and skip option, failure handling.

## Visual and audio direction

### Visual

**TBD**: art style, palette.

### Audio

Three sounds blended, inspired by Yooka-Laylee, Fate/stay night and NieR: Automata. The music itself is original:
it is generated from style descriptions, never from those names.

- **Light and puzzle moments:** a playful, bouncy cartoon orchestra (marimba, pizzicato, tuba, whistling).
- **Tension and reveals:** dramatic visual-novel orchestra with choir.
- **Title and night scenes:** melancholic piano and strings with wordless vocals.

Tracks (`tools/audio/music_tracks.json`):

| Name | Use |
|---|---|
| `title` | Title theme. Piano, strings, distant wordless vocal |
| `bus_stop_night` | Quiet background for dialogue at night. Felt and electric piano, pads |
| `mystery` | Tense underscore for reveals. Staccato strings, brass, timpani, dark choir |
| `puzzle` | Light, curious puzzle music. Pizzicato, marimba, clarinet |
| `playful` | Bouncy, goofy adventure tune. Marimba, tuba, whistling |
| `quiet_memory` | Sad, intimate confession scenes. Piano, cello, soft humming |
| `sting_reveal` | Short orchestral hit for a shocking reveal |
| `sting_success` | Short bright flourish for solving a puzzle |

Ambience loops and sound effects (including UI sounds) are synthesized or taken from CC0 packs.

Voice acting: **TBD**.

## UI

Built: title with episode select, dialogue box, choice menu, backlog/history, save/load (Auto + 9 slots), settings
(text speed, auto-advance, volumes, fullscreen).

Planned: puzzle HUD.
