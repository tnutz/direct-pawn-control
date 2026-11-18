# Bridge prototypes for the v0.8 Arisen brain

These are eval snippets for the dd2-modkit agent bridge (`reframework/data/agent_bridge/request.json`). They run in the
bridge's Lua state, which is separate from DPC's. They were used on 2026-11-10 to prove the v0.8 approach.

| File | What it does |
| --- | --- |
| `s1.lua` | Spawns a goblin (`ch220000_00`) through `GenerateManager.requestCreateInstance`. Set `_G.SPAWN_CID/COUNT/DIST/ANGLE` first. `_G.SPAWN_THINKSTOP=false` lets it fight back. |
| `b1.lua` | Brain v1 (selector requests). Targeting works, but `requestNormalAttack` plays the shot without creating arrows. Kept for its `pick` and `set_aim`. Load before b4. |
| `b4.lua` | Brain v4: synthetic stick and buttons written in the `PlayerInputProcessor.update` pre-hook. This is what DPC v0.8 ports. |
| `rec4.lua` | 8-10 s recorder writing `agent_bridge/rec.json`: target HP, FSM nodes, shells, stick, distance and facing error. |
| `m1.lua` | Movement-injection experiment (which stick write moves him). |
| `d1.lua` | Logs `app.Character.onDamageHit` (`DamageInfo` has no attacker field). |
| `mk_multi.py` / `send.py` / `read.py` | Bundle several files into one eval, write the request, and check the response id. |

Never hook `app.LockOnController` finders from the bridge: an exception inside one hung the game.
