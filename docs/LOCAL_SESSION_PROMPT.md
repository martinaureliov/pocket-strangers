# Prompt: continue in a local Claude Code session (Windows)

Use this to carry the work on in a Claude Code session running on your own Windows machine, so it can use your
installed Godot and open the game window.

## Before you paste

1. Get the latest project. If you already have a copy, run `git pull` in it. Otherwise:
   `git clone https://github.com/martinaureliov/pocket-strangers`
2. Start Claude Code in that folder: Claude Code in the desktop app, or run `claude` in a terminal inside `pocket-strangers`.
3. Find where your Godot 4.7.2 `.exe` is. The session will ask for it.

## Prompt

```text
We're continuing work on Pocket Strangers, a Godot 4.7 visual novel (5 episodes, story-first, a few puzzles).
This repo is github.com/martinaureliov/pocket-strangers and I'm on Windows. Read CLAUDE.md first and follow it:
it has the conventions, the dialogue rules, the Stage commands and the test rules. Project skills are in .claude/skills/.

Where things stand (done in a cloud session, all pushed to main):
- Project setup, the gamedev skills, and Dialogue Manager 4.2.0 in addons/.
- A vertical slice: StoryRunner (scripts/vn/, steps through dialogue without UI), the VNPlayer scene (scenes/vn/:
  background, characters, typewriter text box, choices, log, auto, skip-read, save/load at any line), a Puzzle
  base class plus a combination lock (code 3-1-4), GameState v2 with crash-safe saves, and a PLACEHOLDER Episode 1
  (episodes/ep01/) that uses every system. All art is placeholder boxes.
- 88 headless tests pass locally and in CI. CI shows Godot error lines as a GitHub annotation.

First, set up local verification:
1. Run `git pull` and confirm we're on main at the latest commit.
2. Ask me where my Godot 4.7.2 is installed. For terminal and headless runs, use the *_console.exe build
   (e.g. Godot_v4.7.2-stable_win64_console.exe); the plain .exe doesn't print to the terminal.
3. Run the import, then the tests (commands are in CLAUDE.md), and send output to log files before reading it,
   because Windows shells can drop or reorder Godot's output. Report the results.
4. Run tools/check_versions.sh (it's a bash script, so use Git Bash) and tell me about new Godot or Dialogue Manager versions.
5. Launch the game (godot --path .) so I can playtest Episode 1, then ask me for feedback on how it feels:
   text speed, fades, click response, the layout.

Then fix whatever the playtest shows. After that the open options are: a settings screen (text speed, auto speed,
volume), music and sound support, multiple save slots, or starting the real Episode 1 story.
Ask me which one before starting.

Keep in mind:
- Saves record dialogue line numbers, so editing a .dialogue file can move saved positions. This is fine for now;
  switch to fixed line IDs before release (see CLAUDE.md).
- When adding a Stage command, also add it to FakeStage in tests/test_runner.gd, or the headless tests hang.
- .gitattributes forces LF line endings. Don't commit CRLF changes.
- Commit and push to main when a piece of work is tested, and check that CI passes.
```

## Notes

- The official Windows download includes two files: `Godot_v4.7.2-stable_win64.exe` for the editor, and
  `Godot_v4.7.2-stable_win64_console.exe` for terminal use. The console one is what lets the session read test results.
- Update the "Where things stand" part of the prompt when the project moves on, or it will describe an old state.
