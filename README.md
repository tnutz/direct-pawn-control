# Direct Pawn Control, Camera Distance and TestGuide (Dragon's Dogma 2)

Source for three REFramework mods for Dragon's Dogma 2, with the research notes behind them.

| Folder | What it is |
|---|---|
| `DirectPawnControl/` | Play as any pawn in your party with the game's own controls, camera and HUD while the Arisen fights on by himself; couch co-op on one PC with player 2 on a controller. |
| `CameraDistance/` | Camera Distance & Framing Studio: camera distance, over-the-shoulder framing, a tactical view, field of view, and co-op framing for Direct Pawn Control. |
| `TestGuide/` | An on-screen test runner used to develop the other two: it shows a plan step by step, presses buttons through a virtual controller, records values and checks them. |

Each mod's `reframework` folder is what goes into the game folder. All three need [REFramework](https://github.com/praydog/REFramework).

## If you are here to learn how it works

- `DirectPawnControl/CHANGELOG.md` is the full development log: every change with the evidence that led to it, what was tried and did not work, and what is still not known. It is long, and it is the most useful file here.
- `DirectPawnControl/research/` holds the probe scripts that were run against the live game, and some of their output: action names, key tables, lock-on ranges, the game's skill-decision table.
- The script itself is commented with the reason for each mechanism and the version it arrived in.

Things in there that other modders have asked about: how the Arisen is made to fight on his own in each vocation, how a pawn is driven with the game's own input processor, how the game's HUD and lock-on are pointed at another character, and which of the game's cameras pull away from a played pawn.

The log and comments have been edited for privacy (reports are paraphrased, clock times and names removed). Nothing technical was taken out.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE.md). In short: use it, change it, share it and build on it, for any purpose that is not commercial. It may not be sold, put behind a paywall or bundled into anything that is.

Required Notice: Copyright 2026 TDizzle13 (Nexus Mods)

## How it was made

By TDizzle13, who designed and play-tested every change, with AI-assisted coding (Anthropic's Claude wrote and revised code and ran the probes under his direction). No AI-generated art, audio or other assets are in these mods; they contain script files only.

Several notes and scripts mention `dd2-modkit`. That is a work-in-progress modding toolkit by the same author (a type index of the game, a linter for REFramework Lua, and the bridge the probe scripts in `research/` were sent through). It is not in this repository yet and is being prepared for a separate release; none of the three mods needs it to run.

## Credits

- [REFramework](https://github.com/praydog/REFramework) by praydog.
- Pawn Tactical Wheel showed that a pawn can be ordered to use a skill through its own AI, which got the quick-skill feature started, and its way of keeping an ordered skill going (switching the pawn's decision maker off until the action is over) is what the skill orders here use since 0.9.151. These mods carry no code or data from it.

Dragon's Dogma 2 is a trademark of Capcom. This is an unofficial fan project and contains no game files.
