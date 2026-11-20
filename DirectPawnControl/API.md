# Direct Pawn Control: mod API (`_G.DPC_API`, version 1.0)

Other REFramework Lua mods can ask Direct Pawn Control who is being played, react when control changes hands, and
take over a few things DPC would otherwise do itself. Available since DPC 0.9.170.

Everything is a plain Lua table on `_G.DPC_API`. Your callbacks run inside `pcall`: a callback that errors 5 times
in 10 seconds is switched off and shown as OFF under **Connected mods** in DPC's settings window, where players can
also switch any connected mod's hooks off by hand.

## Getting the API

DPC may load before or after your script. Either use it directly when it is there, or queue a function that DPC
calls once it has loaded:

```lua
local function setup(dpc)
    dpc.on("possess", function(e) log.info("now playing " .. tostring(e.name)) end, { mod = "My Mod" })
end

if _G.DPC_API then
    setup(_G.DPC_API)
else
    _G.DPC_API_QUEUE = _G.DPC_API_QUEUE or {}
    table.insert(_G.DPC_API_QUEUE, setup)
end
```

Always pass `{ mod = "Your mod's name" }` in `opts`: that is the name players see under Connected mods.

Check for a feature before you rely on it: `DPC_API.has("events")`, `"claims"`, `"overrides"`, `"players"`,
`"coop2pads"`. `DPC_API.version` is the API version ("1.0"), `DPC_API.dpc_version` the mod's version.

## Questions

| Call | Returns |
|---|---|
| `state()` | `{ active, played, arisen = { name, job, chara, ai_on }, coop = { active, two_pads, players = { [1], [2] } }, transition = { running, style } }`. `active`: a pawn is being played. `played`: info about that pawn (below). `ai_on`: DPC's AI is driving the Arisen |
| `played(p)` | The character (`app.Character`) player `p` (default 1) controls right now. In co-op player 1 is the Arisen and player 2 the pawn |
| `player_of(chara)` | 1 or 2 if a player controls that character, else nil |
| `is_played(chara)` | true if a player controls that character |
| `arisen_ai()` | `{ on, target, target_name, mode }`: whether DPC's AI drives the Arisen and what it is fighting |
| `party()` | A list of `{ slot, name, job, job_name, chara, controlled_by }`; `controlled_by` is `"player1"`, `"player2"` or `"ai"` |
| `option(key)` | The current value of one of DPC's settings (plain values only) |

Character info (in `state()`): `{ chara, name, job, job_name, slot, is_main_pawn, is_arisen }`.

Compare characters by address (`a:get_address() == b:get_address()`), never with `==`.

## Events

`local h = DPC_API.on(event, function(e) ... end, { mod = "My Mod" })`, and `DPC_API.off(h)` to stop.

| Event | Payload `e` |
|---|---|
| `ready` | `{ version }`: once, on DPC's first game frame |
| `possess` | `{ player, name, job, chara, from_name }`: a player took a pawn over |
| `switch` | `{ player, from_name, to_name }`: straight from one character to another |
| `release` | `{ player, name, reason }`: a player let go of a pawn |
| `coop_start` / `coop_stop` | `{ players = { [1], [2] } }` / `{}` |
| `transition_start` / `transition_end` | `{ style, chara }` / `{ to_name, interrupted }`: DPC's camera transition when control changes hands. An interrupted transition ends before the next one starts |
| `arisen_ai_target` | `{ target, target_name }`: DPC's Arisen AI picked a new enemy |
| `world_loading` / `world_back` | `{}`: a load screen started / the world is back |

## Claims: taking over something DPC does

`local c = DPC_API.claim(resource, { mod = "My Mod", priority = 0, on_lost = function() end })` returns a handle,
or `nil, "held by <mod>"`. A higher priority takes a claim over; the old owner's `on_lost` runs.
`DPC_API.release(c)` gives it back.

| Resource | While you hold it |
|---|---|
| `camera.transition` | DPC does not run its camera transition when control changes hands (a running one stops). Use the transition events to run your own |
| `camera.follow` | DPC does not move the main camera to follow the played pawn. For a split-screen or custom camera mod |

## Overrides: a setting for this session only

`local o = DPC_API.override(key, value, { mod = "My Mod" })` sets one of DPC's settings (`option(key)` names) until
the game closes, Reset Scripts, or `DPC_API.clear_override(o)`. It is never written to the player's saved settings.
Returns `nil, "no such setting"` for an unknown key.

## Example

`research/examples/DPC_API_Example.lua` in the source logs every event and has switches for a claim, an override
and a handler that always errors (to see the safety switch work).
