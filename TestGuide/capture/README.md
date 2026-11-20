# CaptureGuide: shoot a mod video from a shot list

One file, the shot list, drives the shoot, the log and the edit. Nothing is cut by hand, a bad take costs one
key press, and a second video is a second shot list.

## What you need
- `CaptureGuide.lua` and `TestGuide.lua` (2.3 or later) in `reframework/autorun`.
- A shot list at `reframework/data/capture/shots.json` (example: `shots_dpc-showcase-1.json` in this folder).
- For shots that set the scene or use the robot player: DirectPawnControl in developer mode
  (`reframework/data/DPC_dev.json` with `{"dev": true}`). The commands are DirectPawnControl's command file.
- OBS (or any recorder) and, for the edit, Python 3 with `ffmpeg` and `ffprobe` on the PATH.

## Recording settings
- Record the **game picture edge to edge**: OBS "Game Capture", or "Window Capture" of the client area. No
  borders, no webcam or overlay in the top-left corner (the sync marks sit there).
- 1920x1080 or 2560x1440 at 60 fps is plenty. If the files must be moved in pieces, switch on OBS's automatic
  file splitting (Settings > Output > Recording); the marks carry the take's number, and a take that
  starts in one file and ends in the next is joined by the cutter (give `find_marks.py` the files in order).
- Start the recording once, then leave it running through the whole session. Bad takes stay in the file and
  are simply not used.
- **Set OBS's recording path to this folder** (Settings > Output > Recording Path). With the capture desk open,
  the desk sees the recording file grow and tells the game. While nothing records, CaptureGuide 1.4 is in
  **practice mode**: the card and the corner of the screen say "PRACTICE: OBS IS NOT RECORDING", and takes are
  logged as practice, never kept, so the shot stays open. With the desk closed the guide says it can't tell and
  takes work as before.
- **Takes with no video** (for example shot before 1.4 with OBS off): the shot's panel in the desk has "Drop N
  takes with no video". They become practice takes (listed in the game's `capture/drops.json`; they stay in
  the log), and the guide offers the shot again.

## Shooting
1. Start recording. Press **Ctrl+End**: the first shot's card appears (title, what the viewer should see,
   what you do, how long).
2. **End** shoots it: the scene is set (enemies, party, who is played), a 3-2-1 runs, the screen clears, and the
   take runs. A take with no fixed length ends when you press End.
3. After the take: **End** keeps it, **Home** shoots it again. Home during a take gives it up.
4. PageDown / PageUp move between shots while a card is showing. Shots with a kept take are skipped
   automatically; the guide says when every shot has one.
5. **Ctrl+End** leaves capture mode. Come back any time: the log remembers what is kept.

While capture mode is on, TestGuide's overlay and keys are off.

## The capture desk (review, reshoot, render)
`capture_desk.bat` in the folder with the recordings starts a small local page (http://127.0.0.1:8777, this PC
only). Leave its window open while you use the page. Everything below is one loop you can go round as often as
you like; nothing in it deletes or rewrites a recording.

1. **Shoot** in the game with the guide (above). OBS can be stopped and started as you like; every recording
   stays in the folder.
2. **Get new footage** on the desk: copies the take log and shot list from the game, finds the take marks in
   recordings it has not seen yet (each file is scanned once), and makes the browser copies.
3. **Look**: pick a shot, step through its take frame by frame (buttons, or Left / Right, Shift for 10 frames,
   Space to play), press **Start here** / **End here** (I / O) to trim, choose another take, change the caption,
   leave a shot out, move it. "Play the cut" plays the whole edit with captions. Every change is saved at once
   (`edit_choices.json`).
4. **Rethink**: add a shot, duplicate one, or change what a shot does. The steps of a shot (spawn enemies, take
   over a pawn, start co-op, robot player, and so on) are forms, no JSON needed. "Describe a shot and have Claude
   draft it" writes the steps from a sentence, using the Claude Code program on this PC if it is installed; check
   the draft before shooting. "Stage the setup in the game now" runs a shot's setup in the running game so you
   can look at the scene first. The shot list is saved straight into the game's folder.
5. **Shoot again** marks a shot for a new take: the guide offers it again, and the take you have stays in the cut
   until a newer one is kept. "Shoot this next" makes the guide open on that shot. In the game press Ctrl+End
   (twice if the guide is already armed): it reads the shot list again every time it is armed.
6. **Render video** writes `out\final.mp4` and a small `out\proxy.mp4` from the current edit. `make_video.bat`
   does steps 2 and 6 without the page.

7. **Another video** is another shot list: the menu at the top of the desk starts a new one and opens the others.
   The list you leave is kept in `lists\` with its edit. The recordings and the take log are shared by all lists.

## Events: what happened in each take (CaptureGuide 1.2)
While a take runs, the guide notes what happens and when: kills, big hits on enemies, party members hit hard, someone
going down or getting back up, climbing a monster, every skill used (by whom, with the game's own skill name), who you
are playing, co-op starting and stopping, the shot's timed actions ("cues"), and **Delete** pressed to mark a moment by
hand. They go into the take in `log.json` and reach the desk with "Get new footage".

- **Timeline:** coloured ticks under the take's scrub bar; hover for what it was, click to jump just before it. The
  chips below switch each kind on and off (remembered by the browser) and count them for the take on screen.
- **Search:** the box at the top searches every take, kept or not ("launchboard", "kill ogre", "player 2"). Click a
  result to look at that take at that moment; "Use this take for the shot" puts it in the cut, "Back" returns to the
  chosen take.
- **Must show:** under a shot's details, list what the shot needs (a kind, plus optional who / what and a count). The
  guide's card lists them before you shoot and ticks them off on the keep / retake screen after the take; the desk
  shows the same checklist, "has 2 of 3" next to each take, and "missing" on a shot whose take in the cut lacks one.
- Big hit = an enemy losing 6 % of its health at once, hit hard = a party member losing 25 %; a shot list can set
  `"events": {"big_hit_pct": 4, "hurt_pct": 20}`. Enemies spawned to "not die" never give a kill.
- Nothing is shown on screen during a take (it would be in the recording); the checklist appears after it.

Good to know:
- One take log serves every shot list. Changing the list, or replacing it with a new one, never starts the log
  over; takes of shots that are no longer on the list stay in the log and the recordings.
- Before `shots.json`, `log.json` or `edit_choices.json` is replaced, the old one is copied to `history\`.
- A take can run over two recording files (OBS splitting a long recording, or the recording stopped and started).
  The desk and the cutter join the two; if the recording really was stopped there is a jump at the join.
- The commands need DirectPawnControl in developer mode. The folder of the game is taken from `--game`, or the
  `DD2_GAME_DIR` environment variable, or the default install path in `desk.py`.

## By hand
```
python tools/find_marks.py recording.mkv -o marks.json
python tools/cut.py --shots shots.json --log log.json --marks marks.json --out out --final
```
`out/clips/` holds one clip per chosen take, `out/final.mp4` the clips in order with each shot's caption in the
lower third, and `out/edit.json` says which shot used which take and which are still missing.

## How the marks work
For 8 frames at the start of a take, and 8 frames after its end, a strip of ten squares is drawn in the top-left
corner, each 1/45 of the picture height: white, then magenta (start) or cyan (end), then the take's serial
number in binary (white = 1, black = 0). The clips are cut between the two marks, so no mark is ever in a clip.

## Shot list format
The desk edits it; by hand, see the header of `CaptureGuide.lua`. In short: every shot has an `id`, a `title`, a `caption`, a `brief`, an
optional `you` (omit it when the robot does everything), `setup` and `cleanup` commands, either `secs` or
nothing (until End), and `actions`: commands at a time into the take, which is how the robot player is driven.

## The test bench (tests with nobody at the PC)
`bench.bat` (or the "Test bench" panel on the capture desk) watches the game's `reframework\data\bench\jobs\`
folder. A job is a list of TestGuide plans plus a few settings (see the top of `tools\bench.py`). For each plan the
bench makes sure the game is running and the Arisen is in the world, hands the plan to TestGuide (2.4 starts it by
itself while the bench runs), waits for it to finish, and copies the results, the REFramework log tail and DPC's
own files into `bench\runs\<run>\`. If the game crashes or hangs (no heartbeat for 90 s), it reads the crash dump
Windows wrote (fault address and the game code on the stack), restarts the game and tries the plan once more.

- Needs `DevBench.lua` and `TestGuide.lua` 2.4 in `reframework\autorun`, and DirectPawnControl in developer mode.
- **Never closes a game it did not start.** A job with `"use_running_game": true` uses the game you have open.
- Backs up the saves folder before each job (`bench\save_backups\`, the last 10 zips).
- **The save:** tests run on whichever save is loaded (for now the main save; the backups above are the safety net). A separate test slot works too. Loading it from the title menu, three ways:
  `observe` (someone loads it; meanwhile `DevBench.lua` writes the game's own calls to `bench\flow_log.json`),
  `call` (DevBench asks the game for the slot: a guess until the flow log confirms it), `keys` (the bench presses
  the keys listed in the job, as real key presses, after bringing the game to the front).
- **Known start and no saving:** each plan starts with DPC's `scene` command (pawn released, co-op off, test enemies
  gone, party healed, experimental switches off, the party back where the job started). While a job runs the game
  does not save (`"save_block": "flag"`: the game's own save switch; `"skip"`: save requests dropped), and the bench
  compares the save files before and after each plan, so a run says whether it changed the save. With the block
  holding, `"revert": "job_end"` (or `"each_plan"`) just restarts the game to be back at the save; Steam Cloud
  stays untouched. Revert only ever restarts a game the bench started.
- **Quit to title between plans** (`"title_between": true`): for crashes that happen when the world unloads. DevBench
  1.2 asks the game's own menu screen to return to the title (untested), then `"title_keys"` as key presses; the game
  then loads the save again (`"autoload": "call"`). A crash on the way to the title is reported like any other.
- `bench\stop.json` with `{"stop": true}` stops it after the current plan.
- `python tools\bench.py --dump <file.dmp>` reads any crash dump.
