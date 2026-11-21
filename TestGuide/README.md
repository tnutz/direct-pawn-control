# TestGuide

On-screen test runner for live tests of the DD2 mods. A plan file describes the steps; TestGuide shows them in an overlay, waits for the player to say they're ready, counts each step down, sends DirectPawnControl commands at step boundaries, and records probe values into a result file.

- Install: `reframework/autorun/TestGuide.lua`.
- Plan: `reframework/data/test_guide/plan.json` (format in the script header; example in `examples/`).
- **End** = ready (2.7.2: not L3+R3, which is co-op join) (3 s countdown, then step 1). **Shift+End** = dismiss or abort.
- Status: `data/test_guide/status.json` (`waiting` / `countdown` / `running` / `done` / `aborted`, current step, finished ids).
- Live values: `record.show` lists probe names to print on the overlay while a step runs (v1.1).
- `record.at = "frame"` samples in `re.on_frame`, after the camera update, which is needed for `draw.world_to_screen` and the final camera pose (v1.2).
- Queue (v1.5): plans in `data/test_guide/queue/*.json` run in file-name order after `plan.json`, each once by id; Shift+End skips the one waiting.
- A step with `"wait": true` has no timer: it stays up until the player presses End (v1.3). Use it for anything the player has to do in a menu or judge by eye.
- `"each_frame": "<lua>"` on a step runs that chunk every frame of the step, before the game's LateUpdate, in the probe environment (v1.4). Use it for live experiments such as overriding a camera field.
- Results: the plan's `record.out`, e.g. `data/test_guide/result_<id>.json` with one row per sample (`t`, `step`, each probe).
- A plan id runs once; finished ids survive script resets. Step commands are queued 0.6 s apart because DPC reads `DPC_cmd.json` every 0.5 s.

## 2.0: checks, Dev HUD, flight recorder

- **`requires`** (plan): `{"DirectPawnControl": "0.9.7", "TestGuide": "2.0"}`. The plan will not start until each mod reports at least that version in `data/dev_status/<Mod>.json`. The overlay says which one is missing, which means "Reset Scripts was not pressed".
- **`expect`** (step): a list of checks on the probes sampled during that step. Each is `{probe, agg, op, value, label, min_frac}`.
  - `agg`: `avg`, `min`, `max`, `last`, `any`, `all`, `frac` (share of samples that match; pass when it reaches `min_frac`).
  - `op`: `>`, `>=`, `<`, `<=`, `==`, `~=`, `contains`. With `any` / `all` and no `op`, the probe value itself is the test.
  - PASS / FAIL shows on the overlay and goes into `status.json` and the result file (`verdicts`, `versions`). The result screen stays 30 s or until End.
- **Dev HUD**: one line per mod that writes `data/dev_status/<Mod>.json` (`mod`, `version`, `t`, `errors`, `last_error`, `save_ok`, `info`). Red for a recent error or a failed config save, grey "not reporting" after 5 s of silence. **Shift+Home** hides or shows it.
- **Flight recorder**: keeps the last 30 s at 10 Hz (Arisen and pawns: position, node, hp; pad; camera; keys; DPC state). **Home**, or **Touchpad-left + L3**, saves it to `data/test_guide/flight_<time>_<n>.json` and `flight_latest.json`. Press it when something odd happens outside a test.
- **Robot steps**: a step's `cmds` can send DPC `robot` commands, so a plan can press the buttons itself (`examples/robot-smoke-1.json`).
- **Offline harness**: `python tests/harness.py` runs the real `TestGuide.lua` against a fake REFramework (needs `lupa`). Run it before deploying a change to TestGuide.

## 2.1
- The list of finished plan ids kept only the last 20, so older files left in `queue/` started again. It now keeps 300. Clear a queue file by overwriting it with `{}` (files without an id are ignored).

## 2.6: steps that last until done, manual step end
- An `expect` item with `"must": true` keeps its step running until every must-have passes (checked live four times a second over the step's samples so far); the step then moves on 1.5 s later. The overlay shows the checklist (`[ ]` / `[x]`). `secs` is only a hint for such steps. `min_secs` (default 2) and `max_secs` (default 180; the must then fails) bound it.
- End (keyboard only; L3+R3 is co-op join / leave) ends any running step at once. Its checks are still made.

## 2.7: the test's own settings, in one place
- A plan's `"settings"` list (`{"mod": "cd" | "dpc", "key": ..., "label": ..., "min": ..., "max": ..., "fmt": ...}`, or `"values"` / `"labels"` for a choice) is shown in a "Test settings" window while the REFramework menu is open, and first in TestGuide's own entry. `cd` goes through `CameraDistance_API`, `dpc` through `DPC_dbg` (dev builds). Changes save in the mod as usual; the values at the end go into the result file under `"settings"`.
