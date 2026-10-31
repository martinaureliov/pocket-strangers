# Sound effects credits

All sound effects below were synthesized from scratch (filtered noise, envelopes,
additive/sweep tones, hand-written biquad filters) by `tools/audio/synth_sfx.py`.
The script is deterministic (fixed RNG seeds); re-run it from the project root with
`python tools/audio/synth_sfx.py` to regenerate the files. No third-party recordings
are used, so there is nothing to attribute. The generated files are the author's own
work, released with the rest of the game's original assets.

All files: OGG Vorbis, 44.1 kHz, mono, peak around -6 dBFS (toggle quieter), 5 ms fades.

| File | Source | Notes |
|------|--------|-------|
| `sfx_ui_click.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Soft button press: short falling sine "pop" plus a muffled tick, ~60 ms. |
| `sfx_ui_back.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Softer and lower sibling of the click, ~90 ms. |
| `sfx_ui_toggle.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Tiny quiet tick for sliders/toggles, ~30 ms, peak about -13 dBFS. |
| `sfx_save_done.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Two soft bell notes (E5 then A5), ~420 ms. |
| `sfx_dial_tick.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Two-stage mechanical notch click (dial drops in, pawl settles), ~50 ms. |
| `sfx_lock_fail.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Dull low thunk plus loose metal chatter, ~300 ms. |
| `sfx_lock_open.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Latch click, shackle clunk, small wobbling spring, ~500 ms. |
| `sfx_phone_buzz.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Two vibration-motor buzzes through wood-bench resonances plus case rattle, ~1 s. |
| `sfx_bus_arrive.ogg` | Synthesized by `tools/audio/synth_sfx.py` | Diesel rumble rising, air-brake hiss, door fold and clack, ~5 s. |
| `sfx_sting_reveal.ogg`, `sfx_sting_success.ogg` | Generated music stings | Not made by `synth_sfx.py`; credited in `assets/audio/music/CREDITS.md`. |
