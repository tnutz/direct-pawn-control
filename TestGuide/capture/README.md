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
