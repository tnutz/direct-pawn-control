# MODLOG: DirectPawnControl

## Goal
Allow the player to take direct control of their Main Pawn or Hired Pawns in Dragon's Dogma 2 with full camera attachment, locomotion, combat attacks, and equipped vocation skills.

## Route
REFramework Lua script (`reframework/autorun/DirectPawnControl.lua`)

## Changelog & Engineering Post-Mortem

#### Vocation runs (2026-11-15, 0.9.28, `party-matrix-2` / `-3`, robot in co-op, same party both times: Fighter, Archer, Warrior)
- 0 script errors in both runs. Fighter: all checks. Warrior: move, attack, Tackle on L2, Crescent Slash on skill 1 (one run missed the "moves" check, the next passed it).
- Archer: move and skill 1 (Threefold Arrow, skill state 13) pass; the "attacks" check failed in both runs, with layer 0 staying in `Strafe`. Probably the test's blind spot (bow shots may run on the upper-body layer), not confirmed. `party-matrix-4` also watches layer 1.
- Sorcerer not covered yet.

### v0.9.167 (2026-11-19): Archer pawn skills used from the hip abort
- Report (second PC, Xbox controller, default controls): the played Archer's Spiral Arrow (Whirling Arrow) and Heavenly Shot (Full Blast) light up on the skill palette but abort; "it often seemed to work but not in all cases".
- `archer-chord-1` (TestGuide, 70 s of recorded actions): every attempt started while the aim button (R1) was held fired (Prepare -> Shoot). Every attempt from the hip started and was cancelled by the game: Whirling Arrow `Job02_AimCancel` after 1.2 s, Full Blast `Job02_CrouchShotCancel` after 0.4 s. Stamina was never short. The mod's aim camera was not the cause: it was on in the attempts that worked. (The test's "aim camera off" step did not take; the command did not reach the mod. Not needed after this result.)
- Fix: while the played Archer is in a skill's Prepare / Ready / charge stage, the mod holds AimHold + JobSpecialAction on his input until the skill leaves that stage, as the aim button would. Setting `pawn_hip_skill_aim` (on; Archer pawn group). Dev status `aim.hip_aims` counts them. Not in co-op yet.
- Confirmed (`archer-chord-2`, the tester: "that seems to have worked"): from the hip, Whirling Arrow fired twice and Full Blast once (Prepare -> Shoot, no cancels); with R1 held, Whirling Arrow and Full Blast also fired.

### v0.9.166 (2026-11-19): Archer pawn reticle off screen on some PCs
- Report on the second PC (5120x1440 screen, Xbox controller, default controls): the possessed Archer zooms but shows no reticle.
- Watch over 12 s of aiming (`apt1`, read-only): every reticle request came from the mod (492, none from the game), no errors, the widget switched on while aiming (FlowNow 1, UpdateSelf true), and it drew at **DrawPos 1440,810** on its 1920x1080 canvas. The mod had asked for 3840,1080, the centre of the 7680x2160 display REFramework reported. 3840 x 1920 / 1440 = 5120 and 1080 x 1080 / 810 = 1440: the game's own screen is 5120x1440, so the reported size includes the 150 % Windows display scaling. The reticle was three quarters of the way right and down.
- Fix: after each request the mod reads the widget's DrawPos and scales its point until DrawPos is 960,540, so the centre is found whatever size is reported. Dev status `aim` gains `dp_x`, `dp_y`, `fixes`.
- Confirmed on the 5120x1440 PC (the tester: "reticle shows perfectly").

### v0.9.165 (2026-11-18): developer only: robot "antics" for co-op shots (not tested in game yet)
- The tester: co-op is hard to show on video, a second player fighting is almost indistinguishable from a pawn playing by itself; something funny or erratic is needed.
- `{"cmd":"robot","who":"pad","secs":20,"antics":true}`: the robot runs rings round the Arisen at 3 m and jumps every 0.9 s. New shot `10b-coop-antics` in the showcase shot list.

### v0.9.164 (2026-11-18): developer only: the robot player can fight (not tested in game yet)
- First capture session with CaptureGuide 1.0: 18 takes, 10 of 12 shots kept. The tester: the robot as player 2 in co-op is useless, it just runs off. The shot list gave it fixed stick directions.
- `{"cmd":"robot","who":"pad","secs":25,"fight":true}`: the robot steers the played pawn at the nearest enemy (camera-relative stick from `brain_stick_for`), and within 3 m taps the light attack, with a heavy attack every sixth beat. Nothing changes for players; the robot only exists in developer mode.

#### Final for release: 0.9.163 (2026-11-18)
- **The tester:** the Arisen was landed on while a pawn was played and no flash showed (0.9.161's panel hide confirmed). "Let's call this final. We can always issue updates later."
- Not confirmed in play at this point: 0.9.162's take-over fix for a pawn set on climbing, and 0.9.163's arrows for pawns fighting on their own.

### v0.9.163 (2026-11-18): free arrows also while the pawns fight on their own (not tested in game yet)
- **The tester:** the flash he still sees is the normal one while playing the Arisen (wanted). Agreed to leave the no-bag half for a later look with the decompile. His reason for the cheat: if the pawns use up all their arrows on their own, there is nothing left to fire when one is taken over.
- That reason is not met by a cheat that only works while a pawn is played. The removal hooks now also skip a special arrow whenever its owner is not the Arisen (owner read from the `CharacterID` or `Character` argument, compared with the Arisen's, refreshed every 3 s), played or not. The Arisen's own arrows are spared only while a pawn is played, as before. `deletePartyItem` (no owner argument) is still skipped only during a possession.
- Side effect to know: moving special arrows out of a pawn's bag through the item menu may leave them in the bag as well, if the game removes them with the same call. A cheat either way; off by default.

### v0.9.162 (2026-11-18): every command of the pawn is ended at take-over; the no-bag arrow cheat is removed from the menu (not tested in game yet)
- **The tester on 0.9.161:** the stuck red is gone (no overall red). With the experimental no-bag arrow cheat ticked, the Incendiary skill worked once, then fired only plain arrows, Nocuous kept working, and after enough Incendiary shots the game crashed, the second crash with that option on. And: taking control of the Archer pawn while she was set on getting onto a Cyclops, she kept at it and it felt like having no control; regression, or not caught deep enough?
- **Not a regression; not caught deep enough.** 0.9.132 ends only commands from `app.actinter.cmd.move.*`. Jumping onto a monster is `app.actinter.cmd.JumpGrab` (type index), and the latest take-over recording (the second Archer pawn) shows a non-move command, `app.actinter.cmd.job02.TriadShot`, still executing 5.8 s after the take-over. Now any running command is ended during the first 1.5 s of a possession, and `JumpGrab` is ended for as long as the pawn is played, like the move group. The 8 s grace after a skill order to that pawn stays.
- **No-bag arrows:** `cheat_free_arrows_nobag` is forced off at load and its menu line is removed. Counters before the second crash: the oil action swapped 37 times, poison 6, water 6, `kept deleteItem` 5. "Never used up" (confirmed by the tester with real arrows) and the pawn's own counts in the skill list (confirmed) stay.
- Flash: `hides` 1, `unstuck` 1 in that session. The tester's "Arisen does still show red when hit hard" is not yet clear to me: the normal flash while playing the Arisen (wanted), or the flash while a pawn is played (the thing 0.9.161 should stop). Asked.

### v0.9.161 (2026-11-17): red screen after going back to the Arisen fixed (not tested in game yet)
- **The tester on 0.9.160:** the screen still turns red when he goes back to the Arisen after playing a pawn, also after returning to the title and reloading. Confirmed by him on the same build: the second Archer pawn's arrow counts are right, and the free-arrows cheat works with real arrows (0.9.154's "never used up").
- Read live while a pawn was played (`dev/bridge/flash2.lua`): `PnlCritical` `Visible=false`, `PlayState=DEFAULT`, `Play=true`, widget flow 0. So the panel rests in DEFAULT and is normally not visible; 0.9.158's "show it again on release" set it visible in that state, and DEFAULT while visible is solid red. It came back after a reload because the first hide of a new session was followed by the same forced show.
- Change: the script never shows the panel. During possession it hides the panel only when the game has shown it and the played pawn is not low; on release nothing is done. A once-a-second check (`R.danger_unstick`, whoever is played) hides a panel found visible in DEFAULT, which also clears the state left behind tonight.
- Still untested: whether hiding stops the flash on a heavy hit to the Arisen, and whether a later flash as the Arisen shows normally (it should, if the game sets the panel visible itself each time).

### v0.9.160 (2026-11-17): bright red screen from 0.9.158 fixed; the skill list shows the played pawn's arrow counts (not tested in game yet)
- **The tester on 0.9.159 (screenshots):** after switching to a pawn the whole screen is bright red; and the second Archer pawn, who now carries 5 / 5 / 5 / 7 special arrows, shows "00" in front of Incendiary, Nocuous and Deluging Shot in the skill list.
- **Red screen: caused by 0.9.158.** Setting the widget's kept `PlayerHpRate` to 0 before each update did not hide a drop, it made the widget see a player at zero health, and the screen stayed red. That measure is removed. Hiding `PnlCritical` unless the played pawn is low stays; whether it stops the flash is still untested.
- **Arrow counts:** the "00" is `ItemManager._...ArrowNum`, which counts the Arisen's arrows. While a pawn is played (not co-op) the four fields are now set to the played pawn's own counts twice a second (`getHaveNum(id, pawn)` for 166 / 167 / 168 / 169) and back to the Arisen's on release and on Reset Scripts. Switch: `pawn_arrow_counts` (on; menu: Features). Display only.
- 0.9.156's counter hold is replaced by this (with the experimental no-bag cheat a 0 shows as 1).
- Not reported yet: whether the second Archer pawn's special-arrow skills fire now that he carries the arrows, and whether the cheat keeps the counts from dropping.

### v0.9.159 (2026-11-17): free arrows: "not needed in the bag" is off by default after a crash (not tested in game yet)
- **The tester on 0.9.158 (playing the second Archer pawn, cheat on, no special arrows in any bag):** a Nocuous Shot (poison) could be loaded; he could then not change to the Incendiary one ("maybe noxious never left the bow"); then the game crashed.
- Counters before the crash: `swapped to Job02_PrepareSpecialArrowOil` 6, `...Poison` 3, `...Water` 2, so 0.9.157's replacement action is accepted and plays. `kept deleteItem` 2, log "a special arrow (item 166) was not used up": **the arrow is taken away through `ItemManager.deleteItem(Int32, Int32, CharacterID)`**, also when the bag holds none. `last_skill_action` was back at "skill 19 -> 'Job02_NoSpecialArrow'" (the oil skill), swapped six times while the bow kept the poison arrow.
- No exception in the REFramework log and no new `reframework_crash.dmp` (the one on disk is from 16 November), so there is no stack. The last log line is a camera change at [time]; the log ends there.
- Reading: forcing the with-arrow action when the bag is empty leaves the game's arrow state half done (the prop on the bow does not change back), and the crash followed attempts to load a second kind. Not proven; it is the only new thing in that session besides the hidden flash panel of 0.9.158.
- Change: the "not needed" half is now `cheat_free_arrows_nobag`, **off by default** and labelled experimental in the menu (new name, so the saved "on" from tonight does not carry over). With it off, neither the action swap nor the counter hold runs. "Never used up" stays: it only skips the `deleteItem` family for the four arrow ids.
- Still untested: "never used up" with real arrows in the pawn's bag.

### v0.9.158 (2026-11-17): red flash, second fix: the widget's own trigger (not tested in game yet)
- **The tester (0.9.156, playing the second Archer pawn):** the red flash showed again when a Cyclops slammed the Arisen. So "confirmed gone" for 0.9.141 was wrong: it had only not happened in the fights since.
- Counters at that moment: `skips` 0, `flag_clears` 0, `flow_resets` 0, with the hooks installed (`isDangerHp` swapped 13,909 times). Probe `flash1` a minute later: `FlowNow` 0, `IsReqCritical` false, `PlayerHpRate` 0.92, and **`PnlCritical` visible with play state "FADE_IN"**. The flash is the panel being played from inside `ui022401.update()`, without `reqCritical`, `GuiManager.requestCriticalEffect`, the flag or a flow change, so none of 0.9.75 / 0.9.91 / 0.9.141 could see it.
- Change, in the existing hooks on `update()`: before the call `PlayerHpRate` is set to 0 while a pawn is played, so the Arisen's health cannot read as a drop against the frame before; after the call `PnlCritical` is hidden unless the played pawn is itself below the danger share, and shown again when it is, on release, in co-op and on Reset Scripts. Counters `rate_zeroed`, `hides`, `hidden`.
- Not known: which of the two does the work (the hidden panel alone should be enough), and whether the low-health screen edge for a low pawn lives in the same panel (then it still shows, by the rule above).

### v0.9.157 (2026-11-17): free arrows, the no-arrow action is replaced where it is chosen (not tested in game yet)
- **The tester on 0.9.156 (screenshot of the second Archer pawn's skill list):** still the no-arrow animation. The list shows "01 Incendiary Shot", "01 Nocuous Shot", "01 Deluging Shot": the held counters are what the HUD prints, so the HUD believed it; the skill did not.
- Diagnostics from that try: `asked getCustomSkillAction` 24, `last_skill_action` "skill 19 -> 'Job02_NoSpecialArrow'" (19 = `Job02_SpecialAllowOil`), counters held twice each, `getHaveNum` raised 4 of 20. So `Job02ActionSelector.getCustomSkillAction` is called and returns the no-arrow action whatever the counters and `getHaveNum` say; its inner check is not reachable by any of them.
- Read live (`dev/bridge/arrow2.lua`): the played Archer's `Human.SpecialArrows` holds the props for kinds 3, 4, 5, 6 (Bomb, Water, Oil, Poison) with their weapon objects, although his bag holds no arrows. So the action has its arrow prop to draw.
- Change: the post-hook on `getCustomSkillAction` returns, for skills 17 to 20, the action of the same skill with an arrow instead of the three no-arrow actions: `Job02_PrepareSpecialArrow<Kind>` (aiming), `Job02_SpecialArrow<Kind>WithoutAim`, `Job02_ClimbingSpecialArrow<Kind>`. The names are from the game's action enums; that these are the ones the game returns when an arrow is there is an assumption.
- If the action plays but then stops or fires a plain arrow, the next check sits inside the action itself and needs the decompile.

### v0.9.156 (2026-11-17): free arrows, third try at "not needed": the player's arrow counters are held at 1 (not tested in game yet)
- **The tester on 0.9.155 (playing the second Archer pawn, a new Archer pawn with more skills):** he still acts as if he has no arrows.
- After a minute of his trying, every counter was empty: `getHaveNum` was not asked for an arrow id and `getSpecialArrowAction` was not called (its hook was installed, log [time]). 0.9.154's 40 `getHaveNum` calls must have come from the item menu. So the choice of the no-arrow action happens inside native code that calls none of the hooked methods.
- What that code can still read without a call: `ItemManager._PoisonArrowNum` / `_WaterArrowNum` / `_OilArrowNum` / `_ExplosiveArrowNum`. They count the player's arrows, and a played pawn is driven through the player's input. Guess: the game checks these for whoever the player drives.
- Change: `R.arrow_tick` holds each of the four fields at 1 while the cheat is on and a pawn is played, and puts a field it raised back to 0 on release, when the cheat goes off, or on Reset Scripts. Counted as `held <field>`.
- Diagnostics added: the action `Job02ActionSelector.getCustomSkillAction` returns for a skill (`last_skill_action`), if that method is called at all.
- A side effect to watch: with the Arisen as an Archer, his own arrow count on the HUD would read 1 for a kind he has none of while a pawn is played.

### v0.9.155 (2026-11-17): free arrows, second try at "not needed" (not tested in game yet)
- **The tester on 0.9.154:** with the cheat on and no arrows of the right kind in anyone's bag, the Archer pawn plays the missing-arrow animation. (No arrows to give her, so "not used up" could not be tried.)
- Counters at that moment: `asked getHaveNum` 40, `raised getHaveNum` 10, `addArrowNum minus` 1 (skipped); the four counter getters were never called. So the game does ask `getHaveNum` for the arrow ids, and raising it to 1 does not change which action is chosen.
- Change: a post-hook on `Job02ActionSelector.getSpecialArrowAction(Boolean, HumanCustomSkillID, String)`. When it answers `Job02_NoSpecialArrow` or `Job02_NoClimbingSpecialArrow`, the String argument is returned instead, on the assumption that it is the action for the case with an arrow. The flag, the argument and the answer are written to `arrows.last_action` in the developer status file, so the assumption can be checked from one press.
- Still open if the action then plays: whether the arrow effect itself (the explosion, the oil) needs the arrow object the game equips from the bag.

### v0.9.154 (2026-11-17): cheat, off by default: special arrows are free while a pawn is played (not tested in game yet)
- Requested: an Archer pawn that is played (possession or co-op) should neither use up nor need the special arrows; pawns need them in the bag for the matching skills and waste them.
- Read live (`dev/bridge/arrow1.lua`): the items are 166 Blighting, 167 Drenching, 168 Tarring, 169 Explosive Arrow (174 Unmaking and 455 Unmasking left alone). `ItemManager._ExplosiveArrowNum` was 11 while the Arisen held 11 and the pawns none, so the four `_...ArrowNum` counters count the player's arrows. From the type index: `addArrowNum(CharacterID, Int32, Int32)`, getters for the four counters, `Job02ActionSelector.getSpecialArrowAction(Boolean, HumanCustomSkillID, String)`, action ids `Job02_NoSpecialArrow` and so on.
- `cheat_free_arrows` (menu: Cheats): while a pawn is played, calls that remove items by id are skipped for those four ids (`deleteItem`, `deleteItemNoLock`, `deletePartyItem`, six overloads), and a negative `addArrowNum` is skipped.
- `cheat_free_arrows_none` (on once the cheat is on): the four counter getters and `getHaveNum` for those ids answer at least 1.
- **This is built from names, not from having watched the game do it.** Which call the game makes before a special-arrow skill and which one removes the arrow is unknown; every hook counts what it saw into `arrows` in the developer status file, and removals by stored-item record are only counted. The first test decides what stays.
- Hooks are installed only once the cheat is ticked (then they stay for the session and do nothing while it is off).

#### Release housekeeping (2026-11-17, still 0.9.153, script unchanged)
- The tester called 0.9.153 final for release. `modinfo.ini` of both mods: `author=TDizzle13` (it said the developer's first name, which would have shipped in the zips). README title is the release name, "Direct Pawn Control - Play as Any Pawn, with Couch Co-op". Zips rebuilt; public source rebuilt from this state.

### v0.9.153 (2026-11-17): in co-op player 2 changes pawn with the take-control combination (not tested in game yet)
- The tester asked whether the co-op player should get the same pawn selection controls, minus returning to the Arisen.
- Done for the one control that is free on player 2's controller: the take-control combination (L1 + left stick click, or whatever it is set to) switches player 2 to the next pawn in party order, pawns only, wrapping round. `coop.pawn_idx` and the status file follow (0.9.152), so Camera Distance frames the new pawn. Switch: `coop_p2_switch` (on; menu: Controls).
- Not given to player 2: the D-pad holds. In co-op the D-pad is player 2's quick items (up / down) and lantern (right), and a hold would give those first.
- The hint line shows in co-op too: "Player 2   L1+L3: Control <next pawn>".
- **Confirmed in play 2026-11-17 on 0.9.153:** the tester: looks great (co-op switching and the camera following; this also covers 0.9.152's index fix in developer mode). Still not tested: co-op framing with developer mode off.

### v0.9.152 (2026-11-17): co-op tells Camera Distance which pawn player 2 plays, also after a switch and also in a released copy (not tested in game yet)
- **The tester (0.9.151, co-op, player 2 on the Archer):** the Archer's auto-target works great (0.9.138 confirmed), but the camera does not keep the co-op Archer on screen.
- Read from the files at that moment: `DPC_coop.json` said `pawn_idx 0`, `pawn_name "the Archer pawn"`; the co-op event log said co-op had started on the main pawn. Camera Distance finds player 2's pawn by that index, so it was framing the main pawn while player 2 played the Archer pawn.
- Cause 1: `coop.pawn_idx` was set when co-op started and never again. Switching player 2 to another pawn with the select key calls `start_possession` directly; the name in the file followed (it is read from the possession state), the index did not. Now the file carries the index of the pawn being played and is rewritten on the switch.
- Cause 2, found while reading the same code, and worse: the file was written with `R.dump`, which writes only in developer mode. A copy installed from the release zip never wrote `DPC_coop.json`, so Camera Distance's co-op framing could never have switched on for anyone but the developer. The file is now always written; outside developer mode only when co-op starts, stops or changes pawn.
- **Tested with developer mode off, 2026-11-17 on 0.9.153** (`DPC_dev.json` set to `dev: false`, Reset Scripts): the tester: the camera works great. The file the mod wrote in that state was the short form, `active true, pawn_idx 1, pawn_name "the Archer pawn"`, so the released path writes it and carries the switched pawn. Developer mode switched back on afterwards.

### v0.9.151 (2026-11-17): any key can carry Ctrl; an ordered pawn skill is kept; orders work with no enemy about (not tested in game yet)
- **0.9.150 confirmed by the tester** ("everything worked"), with one fault: a skill order could not be set to Ctrl + F4, it was taken as F4. Only the co-op key recorded Ctrl.
- **Ctrl:** every key now has `cfg.keys.<id>_ctrl`, set from whether Ctrl was held when the key was chosen. A key without Ctrl does nothing while Ctrl is held and the other way round (before, only the take-control key minded Ctrl). The clash check with the game's bindings skips keys that carry Ctrl.
- **The tester's question:** with Pawn Tactical Wheel the Fighter pawn's Launchboard holds much longer; ordered with this mod's key it is dropped quickly; the wheel also lets pawns use other skills with no target, as this mod once did. Why?
- **Read in the wheel's script on the tester's PC** (`PawnTacticalWheel/ai_engine.lua`, `fire_order`): it gives the same order this mod gives (`AIBlackBoardExtensions.setBBValuesToExecuteActInter` + `set_ReqMainActInterPackData`) and then calls `set_Enabled(false)` on the pawn's `AIDecisionMaker`, switching it on again when the action is over. This mod left the decision maker on, so the pawn's next evaluation replaced the order. For the launch stances (skills 5 and 60) the wheel also treats a second order as "leave the stance". On targets: by its code the wheel also refuses an attack skill with no target, but it looks 60 m round the player; this mod looked 45 m in view of the camera or 25 m round the pawn and otherwise refused.
- **Change (`quick_skill_hold_ai`, on):** after the order the pawn's decision maker is switched off (`quick.hold_start`) and on again when the pawn's action nodes are back at plain locomotion, if the action never started within 2.5 s, at 8 s (20 s for the launch stances), when the pawn goes down, is taken over, co-op starts, or scripts are reset. Ordering a launch stance again while it is held ends it.
- **Change (`quick_skill_no_target`, on):** an attack skill ordered with no enemy found is performed on the spot (target = the pawn himself) instead of being refused.
- Both switches are in the menu under Controls, below the skill-order keys. The READMEs' credit to Pawn Tactical Wheel now says its hold technique is used.
- **Confirmed in play 2026-11-17 on 0.9.151:** the tester: everything works great. Decision: the hold technique stays, with the credit to Pawn Tactical Wheel.
- Not known: whether the action nodes are a good enough end signal for every skill (a channelled spell may read as over too early or run to the 8 s limit), and how every attack pack behaves when aimed at the pawn himself.

### v0.9.150 (2026-11-17): co-op and skill-order keys can be changed; the take-control combination follows a fresh pick and walks the whole party (not tested in game yet)
- Requested after 0.9.149: make the co-op key and the skill orders remappable; if a pawn is picked with the arrows while another is played, the take-control combination should go to that pick while its arrow is up, not to the next pawn; and a checkbox, off by default, that keeps the Arisen out of the round, so a new player can cycle through everyone with one button and a seasoned one can keep the Arisen on his own control.
- **Keys:** `cfg.keys.coop` with `coop_ctrl` (Ctrl + F6 by default; whether Ctrl is part of it is taken from whether Ctrl was held when the key was chosen) and `skill1`..`skill6` (Numpad 1-6). A controller combination for co-op, `cfg.pad.coop` (none by default). The take-control key still does nothing with Ctrl held.
- **A fresh pick comes first:** while the selection arrow is up (3 s after a D-pad hold or the select key), the combination goes to the picked character, pawn or Arisen.
- **The round:** otherwise the next pawn in party order, and after the last pawn the Arisen; on that step the stored pick is set back to the first pawn, so the next press as the Arisen starts the round again. `cycle_skip_arisen` (off; menu: Controls) makes it pawns only, as in 0.9.148.
- The hint names the same target the press will take (rebuilt five times a second so it follows the arrow), and drops "Hold D-pad down: Control Arisen" when the combination itself goes to the Arisen next.
- Unchanged: the keyboard take-control key while a pawn is played goes to the selection (the Arisen by default), not round the party. The number-row / numpad skill keys of the old puppeteer mode are not remapped.

### v0.9.149 (2026-11-17): controls hint on screen; keys and controller combinations can be changed (not tested in game yet)
- **0.9.148's L1 + left stick click: confirmed by the tester** ("works great"). Requested with it: an optional, context-aware help text for new players ("Control Arisen" / "Control <next pawn's name>") and controls the tester can remap.
- **Hint** (`hint_controls`, on; menu: Controls): one dim line over the selection label, built twice a second. As the Arisen: "<take>: Control <selected pawn>" and, with more than one pawn, how to select. Playing a pawn on the controller: "<take>: Control <next pawn>" and "Hold D-pad down: Control Arisen"; on the keyboard: "<key>: Control <selection, the Arisen by default>" and the select key. Controller or keyboard wording follows the device last used (any pad button or stick; W A S D or the mod's two keys). Not in co-op. Height on screen: `hint_y`.
- **Remapping** (menu: "Controls"): the five keyboard keys (take control, select, warp the Arisen, warp pawns, heal) and two controller combinations, `cfg.pad.take` (0 = L1 + left stick click) and `cfg.pad.back` (0 = none; hold D-pad down stays). "Change" waits for a key (first key down after all are up; Esc or 8 s cancels) or for two or more controller buttons held together for 0.8 s (one button alone would take a button from the game). The mod's own keys and combinations do nothing while one is being chosen. "Reset all controls to the defaults".
- The take-control combination now fires on the frame the last of its buttons goes down (before: L1 held and the stick click going down; the same for the default).
- The key-clash check with the game's own bindings runs again after a key is changed.
- Not done: the D-pad holds (left / right / down) keep their directions; they can only be switched off. Couch co-op stays Ctrl + the take-control key, skill orders stay Numpad 1-6.
- Not known: how the hint reads over the game's own HUD at different resolutions, and whether it should hide in menus and cutscenes (it does not).

### v0.9.148 (2026-11-17): the quick-item cross names the played pawn's items; L1 + left stick click goes to the next pawn (not tested in game yet)
- **Quick-item cross.** Read live with the tester opening the cross (probes `item2`-`item7`): while the widget updates, the count comes from `ItemManager.getHaveNum(Int32, CharacterID)` with the Arisen's CharacterID (2891076981), once per frame; the pickers return their `Nullable<ItemIDEnum>` through a caller's buffer (the hook sees a stack address), which a script cannot write. `KeyItem.setMessage(String, Boolean)` is called for all four keys every frame: with the cross open ("IsShift") the strings were `'Harspud Roborant x2'` on action 40, `''` on action 39 (empty health slot, `IsEnable` false), `'Go to Items Menu'`, `'Lantern On'`; closed, the four order words. The Boolean was 0 throughout.
- Change: twice a second the played pawn's bag is searched in the game's list order (the same search the press uses since 0.9.142). Where the pawn holds an item, a pre-hook on `setMessage` replaces the string for that slot with "<name> x<the pawn's count>" while the cross is open, and sets the key's `IsEnable` if the game had the slot disabled. A slot the pawn has nothing for keeps the game's label, which is the Arisen's item and is what the press falls back to. Not in co-op. Switch: `pawn_quick_item_labels` (menu: "the quick-item cross shows that pawn's own items").
- Not known: whether a slot the game had disabled shows the new text normally or greyed (the game may set `IsEnable` again after the hook).
- **Confirmed in play 2026-11-17 on 0.9.148:** the tester: the quick curatives menu looks great in his tests. (L1 + left stick click: no report yet.)
- **L1 + left stick click while a pawn is played** (requested: it should select the next one and take it, otherwise it only repeats holding D-pad down). It went back to the Arisen because the selection starts on him. It now switches straight to the next pawn in party order, wrapping round, without the Arisen in the round. From the Arisen it still takes the selection, as before. With no other pawn in the party it does nothing.

#### Play reports on 0.9.147 (2026-11-17)
- **Red flash (0.9.141): confirmed gone** in the tester's play ("seems to have been gone in my tests").
- **Quick curatives (0.9.142): the cross still shows the Arisen's items** whichever pawn is played. Two screenshots while playing the main pawn: up = Salubrious Draught x1, down = Harspud Roborant x2; after the Arisen gave the draught away the up slot was empty ("Lantern Off" on the right, Harspud Roborant x2 still below). 0.9.142 only changed what a press uses (the pawn's bag first); the labels on the cross are the game's and were never touched.
- Read live (probes `item2`-`item5`, hooks that only count): the cross widget is `app.ui020401`; its `PlChara` is already the played pawn; key 1 (action 40) held `DispItemId` 56 x2. In 50 s with nothing changing in the bags, none of `ItemManager.getHaveNum` / `getHaveNumNoLock` (both overloads), `ItemShortcutParameter.getRecoverHPItemID` / `getRecoverStaminaItemID` / `getItemID`, or `KeyItem.setMessage` / `updateMessage` ran, in the widget or anywhere. So the labels are refreshed on an event, not every frame. Next: the same hooks while the tester opens the cross and changes an item.

#### `walk-5d-warfarer-weapons` on 0.9.147 (2026-11-17): 25 of 25, Warfarer confirmed by the tester
- The tester: looked solid, he attacks with the skills that are available.
- All four weapons seen: job 4 (Thief), 7 (Mystic Spearhand), 8 (Magick Archer), 5 (Warrior), each with attacks and its own skill (41 / 39, 73, 80, 51). Five swaps went through, none failed: four on the first press in 0.3 s, one on the second press after 1.2 s (the retry of 0.9.146 at work). Two of the five were his own, on the 12 s timer. One more timer press was still open when the fight ended.
- 88 attack presses, 26 skill uses, 0 script errors, lock-on and possession held, nobody died. The "weapon of job N" line is logged once per swap now (the 2-second reset is gone).
- Reset Scripts before this run was the first use of 0.9.147's clean-up on reset; no test enemies were alive at that moment, so it is still not exercised.

### v0.9.147 (2026-11-17): test enemies are removed when scripts are reset (not tested in game yet)
- **The tester (0.9.146 just loaded):** the three goblins from the stopped Warfarer run were still there and could not die. The despawn command answered "ok" with 0 enemies: the list of spawned test enemies lives in the script and Reset Scripts had emptied it, so nothing could remove them or clear their `IsNoDie`.
- Removed by hand through the bridge (`dev/bridge/orphan1.lua`: every enemy in `EnemyManager.getAllEnemies` with `IsNoDie` set gets the flag cleared and its GameObject destroyed; 3 of 16 matched, all `ch220000_00`).
- Fix: `re.on_script_reset` now calls `despawn_tests()` before the script goes away. Developer feature only (spawning is not in the release build's menu for players).

### v0.9.146 (2026-11-17): Warfarer swap retries until the weapon has changed; menu option and slider (not tested in game yet)
- **The tester after `walk-5c-warfarer-weapons` (0.9.145):** the Arisen did not change weapons; asked for the swap time as a slider and an option.
- The run's record: skills read correctly for a Warfarer, six slots `73, 39, 41, 80, 100, 51` (Rearmament in slot 5). Weapon job 5 (Warrior) at the start. Swap commands 1 and 2 were pressed ("ordered skill 5") and nothing changed; command 3, pressed while he was in "approach", changed him to job 4 (Thief) within 0.3 s. The run ended in that step, before the part where he swaps on his own. So the press is right and it only takes when he is not in the middle of an attack. No script errors.
- Fix: a swap is now an attempt that stays open until `getWeaponJob()` reports another weapon: no attack input between presses, a new press every 1.2 s, the weapon checked four times a second, given up after 8 s. Status file: `rearm_ok`, `rearm_fail`.
- Second fault found in the same record: "Warfarer: weapon of job 5" was logged every 2 s. The 2-second skill refresh reset `fjob` to 10 and the style to "ranged" each time, so for up to a second in every two he ran the wrong rules and treated his skills as not his. A Warfarer now keeps his weapon job across the refresh.
- Menu ("How the Arisen fights on his own"): checkbox "Warfarer: swaps weapons during a fight" (`arisen_brain_rearm`, on) and a slider "seconds between weapon swaps" (`arisen_brain_rearm_every`, 5 to 120, default 20).
- Looked up in the type index and not used: `app.Human.get_Job10WeaponManager()` with `changeWeapon()` and `isPreparing()`. Calling the manager directly would skip the game's own checks; the button press is the path the game uses for a player.
- Test plan `walk-5d-warfarer-weapons` (the 5c plan with the checks on `rearm_ok`).

### v0.9.145 (2026-11-17): Warfarer Arisen swaps weapons (Rearmament) while he fights (not tested in game yet)
- The tester unlocked Warfarer and set four weapons. The Warfarer rules in the brain date from 0.9.65 and have never run in the game.
- Read from the script before the test: the brain follows the weapon in hand (`getWeaponJob()` once a second) and presses only the skills that belong to it, but Rearmament (skill 100) sits in `brain.NEVER`, so he stayed on one weapon for the whole fight. A Warfarer with skills spread over four weapons would then have most slots unusable.
- New: `brain.rearm()` presses the slot that holds Rearmament through the ordered-skill path (the one the numpad order uses). While he has a target he does it every `arisen_brain_rearm_every` seconds (default 20, 0 = never; config file only, no menu entry yet), not during a skill or while the skill watchdog is letting go. No slot with Rearmament: nothing happens.
- For tests: command `{"cmd":"rearm"}`; the brain status file now carries `fjob` (the vocation of the weapon in hand), `style` and `rearms`.
- Not known until it runs: whether `getSkillID(10, slot)` returns the Warfarer's slots, whether the swap goes through as a slot press, and how he does with a weapon that has no skill set (he should fall back to plain attacks or shots).
- Test plan `walk-5c-warfarer-weapons`: one 22 s fight per weapon against three goblins that cannot die, swap by command in between, then 45 s swapping on his own every 12 s.

### v0.9.144 (2026-11-17): comments only: the script no longer quotes the tester (no change in behaviour)
- For release. The script's comments quoted the tester verbatim in about 40 places and named hired pawns and clock times. They now paraphrase the reports ("reported:", "requested:", "confirmed in play"), with the technical content unchanged.
- Done by `tools/trim_text.py` (the same tool that produces the public change log from this one). Checked: the compiled listing of the script before and after is identical apart from line numbers (48,251 instructions and constants compared).
- Licence decided for the public source: PolyForm Noncommercial 1.0.0 (free to use and build on, not for money).

### v0.9.143 (2026-11-17): the Arisen's climbing camera is not switched to while a pawn is played (not tested in game yet)
- **Reported 2026-11-17 (0.9.141, playing the main pawn, game paused):** the camera was being pulled away at that moment..
- Camera watch: 5017.58 `Camera: Combat (2) -> Climbing (6), player camera false, 14.0 m from the main pawn, target ch100000_00`; still Climbing at 5023.86. Brain at the same time: the Arisen (Mystic Spearhand) targeting `ch253000_00` (Griffin), 0.7 m from it, and held in `Job07_Gungnir` for 42 s with the skill watchdog trying to let go 20 times. So this pull is a second camera, the **climbing camera**, which the game gives the player character when he clings to a monster.
- 0.9.139's block worked in the same session: `cine_blocked` 1, no CinematicAction in the watch. 0.9.138: `lock_guards` 3,746, no error, no crash.
- Change: in the existing pre-hook on `MainCameraController.switchCamera`, a switch to Climbing (6) is skipped while a pawn is played (not co-op), and so is CinematicAction (10) as a second barrier (`possess_no_climb_cam`, `possess_no_cinematic_cam`; counter `cam_refused` in the brain status). That hook was only installed when an Archer pawn aimed; it is now installed on every possession.
- **Confirmed in play 2026-11-17 on 0.9.143:** the camera stays with the played pawn.. Counters after that session: `cam_refused` 302 (so the game asks repeatedly while he clings, not once), `cine_blocked` 1, `lock_guards` 10,255, 0 errors, no crash. Red flash counters still 0 / 0 / 0. Also seen in the brain log: the Arisen "stuck while follow" for about 7 s, steering left and right on the spot (not looked into).
- **Not known:** whether the game asks once or every frame, and whether refusing leaves it in a state it later "returns" from oddly; whether other types pull the same way (Follow 9, Watch 11, Notice 5 have not been seen).
- **Separate, open:** the Arisen stayed in Gungnir on the Griffin for 42 s; the watchdog's presses (Jump, AttackS, JobSpecialAction, Sheathe) did not end it. A Mystic Spearhand Arisen can ride a Griffin for a long time.
- Red flash counters in the same session (0.9.141): skips 0, flag_clears 0, flow_resets 0. Either the Arisen was not hit hard, or the flash is not this widget.

### v0.9.142 (2026-11-17): the quick-use item looks in the played pawn's own bag first (not tested in game yet)
- **Reported 2026-11-17:** the game's quick-use item menu was not filling; question whether higher-tier items such as Panacea are ever offered.
- Probe `item1` (read-only, playing the main pawn): the game's shortcut offers only items from three fixed lists (`ItemShortcutParameter`): 45 health items (Salubrious Draught, dried and aged food, fruit, Greenwarish, roborants ...), 11 stamina items (Harspud family, roborants), 2 for maximum stamina (Vitalic Drench). **Panacea and the other cure-alls are in none of them**; that is the game's rule, with or without this mod.
- Holdings at that moment: the Arisen had one Beast-Steak and one Scrag of Beast and nothing for stamina; the main pawn had one Ripened Harspud and two Mighty Roborants. The game's picker answered Beast-Steak for health (nothing when its meat flag is set) and nothing for stamina. So the cross is close to empty because the Arisen carries almost nothing from those lists.
- The picker only looks in the Arisen's bag, so the played pawn's own stamina items were not offered. Change: on the health / stamina quick-use press while a pawn is played, the pawn's own bag is searched first in the order of the game's list; the picker's choice from the Arisen's bag is second. The log line names both when neither has anything.
- Not changed: what the game's own cross shows (it still shows the Arisen's bag). Not known: whether the game's list order is the order a player would want (it is not the "Ordered..." variant of the lists).

### v0.9.141 (2026-11-17): the Arisen's red hit flash while a pawn is played, two more places (not tested in game yet)
- **Reported 2026-11-17:** the hands-off run looked good; a large red flash still crosses the screen while a pawn is played whenever the Arisen takes damage, even far away..
- `release-check-5c` (0.9.140, three unkillable goblins at 9 m): **25 of 25**; the Arisen (Mystic Spearhand) attacked 89 times, brain in "engage" for 83 of 280 samples, lock-on with the pawn throughout, 0 errors. So the two failures of `release-check-5b` were the test's fight (no battle began with the killable goblins at 14 m), not 0.9.137 - 0.9.140.
- Flash, probe `flash1` (read-only, after that session): the hooks of 0.9.75 / 0.9.91 are installed, the low-health swap answered 15,371 times, but **`reqCritical` and `GuiManager.requestCriticalEffect` were skipped 0 times**. The flash the tester saw was not asked for through either. The widget (`app.ui022401`) has `PlayerHpRate`, `IsReqCritical` and a flow Wait / In / Disp / Out of its own. Reading, not shown: it notices the Arisen's health drop inside its own `update`.
- Change, while a pawn is played (not co-op): `IsReqCritical` is cleared right before `updateFlow` and again after `update`; after `update` the flow is set back to Wait when it is In or Disp and the played pawn is not low on health. Counters in the dev status: `aim.flash.skips / flag_clears / flow_resets`.
- **Not known:** whether the flash the tester sees is this widget at all (a camera or post-effect flash would not be touched); whether a reset after `update` still lets one frame through. The counters after the next hit on the Arisen will say which path fires, if any.

#### `release-check-5b` on 0.9.140 / CameraDistance 2.9.8 (2026-11-17, hands off, Mystic Spearhand Arisen): 23 of 25
- Passed: select, take control (the Thief pawn, Thief), stand still, lock-on with the pawn, return on D-pad down, co-op on the main pawn with stick / attack / skill, 0 errors in both mods, no crash. First run of 0.9.138 - 0.9.140 code.
- Co-op ranges read from the game for the first time: log "Lock-on ranges from the game for Fighter: 8.0 m (22 entries)".
- **Failed, both in the fight step:** "the Arisen attacks or uses a skill on his own" (0) and "the brain reaches engage" (0 of 284 samples). The brain read "idle" for the whole 30 s: its log has "ON (job 7)", "battle over -> stand down", then the spawn of three goblins at 14 m and nothing more. The three goblins still existed at clean-up. Two minutes later, by hand against a Cyclops, the same brain went "battle mode", picked the target and approached.
- **Not established** why no battle was registered with the goblins: killed by the two free pawns before one began, never noticed the party at 14 m, or something in 0.9.137 - 0.9.140. `walk-4` on 0.9.136 (three unkillable goblins at 9 m) had 35 attacks. `release-check-5c` repeats the run with unkillable goblins at 9 m to separate these.
- Note: a plan's result file name is its `record.out`, which the rerun copies had inherited (this run is in `result_release-check-4.json`, `walk-3b` in `result_walk-3-archer-arisen.json`). Set per plan from `release-check-5c` on.

### v0.9.140 (2026-11-17): co-op auto-target uses the game's own lock-on ranges, read once per vocation (not tested in game yet)
- **Requested 2026-11-17:** read the ranges for the played and the co-op vocation from the game once and keep them. (earlier request: auto-target anything within the skill's range, at the distance the Arisen gets).
- Normal possession: nothing to cache. The game's own target search runs for the played pawn with the game's table; the mod holds no range number and reads none while playing (0.9.138 only keeps the Arisen's step from wiping the result).
- Co-op: player 2's pawn has a lock-on controller that nothing searches for, so the mod picks the target itself, until now within a fixed 15 m (`coop_target_range`). Now the range comes from the game's table (`LockOnRangeParameterList` on the lock-on controller): per vocation the longest distance of its Default / NormalAttack / SubNormalAttack entries, or a longer one of an equipped skill's entry. Read the first time a vocation is played in co-op, kept as plain numbers for the session (one attempt per vocation); log line "Lock-on ranges from the game for X: n m". Falls back to 15 m if the table cannot be read. Switch `coop_target_game_ranges` (default on). The status line shows the range in use.
- **[time], follow-up:** skills with a long reach, such as Burst Strike, must still be able to target.. Probe `lock3` (read-only, whole table, kept as `dev/bridge/lock3_ranges_2026-11-17.txt`): Fighter base 8 m, **Burst Strike 20 m**, Shield Summons 20, Shield Counter / Divine Defense / Rush Attack 15; Thief base 9, Cutting Wind 20, Attract 15; Warrior base 65 (one attack entry); Mage / Sorcerer 30; Mystic Spearhand base 12.5, Dragon Stinger / Dance of Death 20; Magick Archer base 23, most skills 30 - 45, two at 75; Trickster 30 - 35. With the skill equipped the co-op range is the skill's, so a Fighter with Burst Strike targets to 20 m (15 m before), without any long skill to 8 m.
- Known from the live table: Archer 30 m (Meteor Shot 40 m), Mystic Spearhand 12.5 m. A melee pawn in co-op will most likely get less than the old 15 m, i.e. the game's own reach; whether that feels right is to be judged in play. The angle tiers of the table are not used: the mod's own "in front of the pawn" weighting stays.

### v0.9.139 (2026-11-17): the game's cinematic action camera is not started while a pawn is played (not tested in game yet)
- **Reported 2026-11-17 (0.9.137 loaded, playing an Archer pawn against a spawned Cyclops):** the camera was pulled away again, possibly when the main pawn drew attention (he called out an opening), so Launchboard or another condition may be involved.
- Camera watch (0.9.137), the last lines before that message: [time] `Camera: Combat (2) -> CinematicAction (10), player camera false, 9.2 m from the Archer pawn, target ch111011`; [time] still CinematicAction, distance reading 1688.9 m. One earlier in the same fight: [time] Combat -> CinematicAction for 2.1 s. The camera's target object was the Archer pawn's throughout. Every other change in that log is Usually / Combat / Aim, as expected for an Archer.
- So the pull is the game's own cinematic action camera (`app.CameraDefine.ControlType.CinematicAction`, `app.CinematicActionCameraController`). Type index: it is started through the static `requestPlay(UInt32, Nullable<UInt32>)` and computes its own base position (`getBasisPosition`), not from the camera's target object. **Which character's action asked for it (the Arisen's, the main pawn's Launchboard, the Cyclops going down) is not known.**
- Change: while a pawn is played (possession or co-op) `requestPlay` is skipped (`possess_no_cinematic_cam`, default on; counter `cine_blocked` in the brain status). Cost: no cinematic camera for the played pawn's own moments either; it would have been placed on the wrong character anyway.
- **Not known:** whether `requestPlay` is the only way in (`ReservedAction` / `playAction` exist too); the camera watch will show a type 10 if one still gets through. Skipping a static method that takes a `Nullable` argument has not been done in this mod before.
- **Unexplained:** the camera watch's distance read about 1,700 m three times, twice for 30 - 40 s in plain Combat mode ([time] and [time]) with no complaint from the player. That number is not a reliable sign of a pull; possibly the camera object's transform is in another coordinate frame at times.

### v0.9.138 (2026-11-17): the Arisen's input step no longer disturbs the played pawn's lock-on target (not tested in game yet)
- **Reported 2026-11-17 (playing an Archer pawn; Arisen is a Mystic Spearhand):** the Archer's skill, used without aiming, did not auto-target at range; it only worked very close to the enemy. Expected: the same range the Arisen gets..
- The game's own range table (probe `lock1`, `HumanParameter.LockOn`, per vocation and action): Archer default and her skill (id 13) reach **30 m** (narrow cone at distance), Meteor Shot 40 m. Mystic Spearhand: default 5 m, attacks 7 - 12.5 m. So the game already gives an Archer the long range; no number of ours is involved.
- Probe `lock2` (read-only, during the possession): **one lock-on controller, used by both input processors**: the Archer pawn's last request was Job 2, custom skill 13; the Arisen's was Job 7, sub attack; controller `Chara` = the Archer pawn, 0 targets at that moment.
- Reading (from those two facts and the code, **not observed frame by frame**): when the brain has a target, the existing swap hands the controller to the Arisen for his step and restores the pawn's target after. When it has none, or he is approaching / idle, there was no swap: his step ran on the pawn's controller with Spearhand ranges measured from the pawn, and dropped a target further away than that. Her un-aimed shot, fired about a second after the skill found its target, then had none. Near an enemy his ranges find the same one, hence the report that it works very close up. It would not have shown with an Archer Arisen.
- Change (`arisen_lock_guard`, default on): on those frames the controller is handed over the same way (Chara = Arisen, the pawn's target saved), and after his step whatever he locked is cleared and hers put back. Same crash guards as the existing swap: not while the pawn runs on the fallback controls, not for a Thief pawn. Counter `lock_guards` in the brain status.
- Not covered: the same step while the Arisen's fighting is switched off altogether. Co-op is not affected (player 2's pawn has a controller of its own, range 15 m from `coop_target_range`; whether that should follow the game's table is open).
- Risk to watch: this does the Chara swap on more frames than before; the swap is the operation suspected in the 2026-11-10 crashes (which is why Thief and fallback controls are excluded).

### v0.9.137 (2026-11-17): developer-mode camera watch for a played pawn (not tested in game yet)
- **Reported 2026-11-17 (playing an Archer pawn against a spawned Cyclops):** when the Cyclops was knocked down, the camera was pulled away from the played pawn..
- What the files show: possession of the Archer pawn from 2702.7, still possessed at 2806; two Arisen auto-warps early on (2706.7, 2716.6), none later; **no camera re-attach in the trace** after take-over, so the camera's target object stayed the Archer pawn; the recorder shows normal aiming and shooting up to 2761, then running and jumping. 0 script errors. Nothing recorded says what moved the camera.
- Candidates, none shown: a camera of the game's own for a large monster going down (it would be placed by the game, not by target object); the lock-on; CameraDistance.
- Added (developer mode only): while a pawn is played, the camera controller's control type, "is the player camera" and the camera's distance from the pawn are read 10 x a second; a log line "Camera: A -> B, player camera x, n m from X, target Y" on every change and when the distance passes 25 m.
- Test runs read at the same time: **`walk-4-spearhand-arisen` passed 6 of 6** on 0.9.136 / CameraDistance 2.9.8 (Mystic Spearhand Arisen: attack count 35, 7 skills, lock-on with the pawn throughout, 0 errors); the three unkillable goblins (0.9.136 `tough`) were all alive at the end of the 45 s fight. `release-check-5` and `walk-5-warfarer-arisen` are marked finished with no result file (dismissed, not run).

### v0.9.136 (2026-11-17): test enemies can be made unkillable from a test plan (developer tool; not tested in game yet)
- **Reported 2026-11-17, after walk-through 3:** looks good; the goblin fight is too short at this party's level. Request: unkillable but weak test enemies..
- `walk-3b-archer-arisen` result: 7 of 7 checks passed, 0 errors in both mods. The fight step has 335 samples and the Arisen's attack count reached 3.
- The spawner already had "tough" (the game's `HitController.IsNoDie` plus topping up when low), used for dummies that stand still. The `spawn` command now takes `"tough": true` for fighting enemies too; despawn clears it as before.
- `walk-4-spearhand-arisen` and `walk-5-warfarer-arisen` (in `TestGuide/examples/`, not queued) spawn their goblins with it.
- Not known: how fighting goblins behave when held at their last sliver of health (stagger loops, fleeing).

### v0.9.135 (2026-11-17): the 0.9.134 Dash-slot write is switched off (it did not work)
- **Reported 2026-11-17 on 0.9.134:** the Circle slot is blank and greyed for the played pawn..
- Probe `dash10` (read-only, playing the main pawn): `BtnDash` read 5 at that moment, `puts` 47, so the game sets it back to -1 again and again and the mod rewrote it 47 times; `IsBtnAssigned` still false; the Circle slot (5) has Key 1024 (the Skill4 action bit) with KeyInputType 0, empty text, panel visible. The other face slots carry plain actions (Triangle AttackL, Square AttackS, Cross Jump).
- So a slot number alone does not make the label draw, and the game's own assignment keeps undoing it. The switch is renamed `hud_dash_slot` and defaults to off (a new name, so a "true" saved under the old one cannot keep it on); the code stays for a later attempt.
- What a real fix needs: the condition inside `ui010201.updateButtonAssign` / `updateKeyGuide` that leaves `IsBtnAssigned` false for a pawn. That is logic, not names; the type index cannot show it. It needs the decompile (tooling plan item 5) or the method tracer (item 4).
- Dash itself works for a played pawn (Circle and L3, the tester 2026-11-17); only the label is missing. Listed as a known cosmetic issue until then.

### v0.9.134 (2026-11-17): the played pawn's guide gets the Arisen's Dash slot (tested: did not work, see 0.9.135)
- **Reported 2026-11-17, fresh session:** no Dash on Circle for the played pawn; the Arisen has his Dash label back.
- Probe `dash9`, read-only, same session, twice: guide on the main pawn: `BtnDash` -1, `BtnDash2` -1, `IsBtnAssigned` false. Guide on the Arisen ("go", standing still, Dash showing): **`BtnDash` 5** (Circle slot, same as `BtnInteract`), `BtnDash2` -1, **`IsBtnAssigned` true**. `convertBtn(Dash)` is -1 in both, `isDisableDash` / `isRestrictedDash` false in both; `setBtnDashText` arguments identical for both (recorder).
- Reading: the label is written to the slot `BtnDash` names; the game's button assignment does not complete while the guide is on a pawn, so there is no slot. Why it does not complete is not known (no decompile).
- Change: at take-over, while the guide is still on the Arisen, his `BtnDash` / `BtnDash2` are remembered; after the guide is pointed at the pawn, and every 0.5 s while it stays there, they are written back if they read -1 (`hud_dash_label`, default on; dev status `aim.dash_label.slots` / `puts`). Nothing is written when no Arisen value was seen (Reset Scripts during a possession).
- **Not known:** whether a slot number alone makes the label draw (`IsBtnAssigned` stays false and is not touched), and whether the game resets the slot each frame (then `puts` climbs by 2 a second and the label flickers).
- The 0.9.133 guard was not exercised in the [time] run (no Reset Scripts during a possession there).

### v0.9.133 (2026-11-17): the key guide is always handed back to the Arisen (not tested in game yet)
- **Reported 2026-11-17 (screenshot of the skill list while playing the main pawn):** the list shows a skill of the Arisen's (Gutting Skewer) where the pawn has Launchboard, and the button does Launchboard; then: the Arisen shows no skill list at all with L1 held.
- Bridge probe `hud4` during the possession: guide `PlChara` / `PlHuman` / `SkillContext` = the main pawn's, but its cached `CustomSkillId` = the **Arisen's** six skills (BlinkStrike, ShieldCounter, CymbalAttack, ViolentStab, BravesRaid, HindsightSlash); the main pawn's own are BlinkStrike, FullMoonGuard, CymbalAttack, Springboard, FullMoonSlash, BravesRaid. Both are Fighters.
- `hud4` again **after release, nobody possessed: guide `PlChara` and `PlHuman` still the main pawn**, `SkillContext` the Arisen's. So the Arisen was playing with a guide that watches the pawn's buttons: no skill list on L1.
- Cause of that part, from the code: `apply_native_hud_skills` saved the guide's fields "as found" at take-over and restored them on release. Scripts were reset while a pawn was possessed several times this morning (0.9.129 - 0.9.132); the reloaded script then found the guide already on the pawn and saved that as the original.
- Change: the saved original is taken from the guide only when the guide is on the Arisen; otherwise it is built from the Arisen (character, human, skill context, input, vocation). Log line when that happens.
- **Not established:** why the cached skill ids were the Arisen's during the possession. Re-running `setupCustomSkillMsgId` and `setupCustomSkillButton(true)` (probe `hud5`) did not change them, with the HUD redirect off (Arisen brain running) or forced on. Possibly the same crossed state; to be read again in a fresh game session.
- **Possibly the same cause, not shown:** the missing "Dash" on Circle for the Arisen since 0.9.129 ("now dash shows up for neither"): a guide pointed at a pawn shows no Dash, and from then on the Arisen's guide may have been pointed at a pawn.
- **Result 2026-11-17, fresh game start on 0.9.133 (three screenshots):** Arisen before take-over: Dash visible. Played pawn: no Dash on Circle, skill list correct. Back on the Arisen: Dash visible again.. Arisen before take-over: Circle = Dash. Playing the main pawn: Circle blank; L1 list = his own skills (Flawless Guard, Burst Strike, Launchboard, Shield Pummel, Full Moon Slash on 5, Riotous Fury on 6). After release: Arisen's Dash back. So the crossed guide explained the Arisen's missing Dash, his missing skill list and the wrong skills in the pawn's list; all three came from resetting scripts during a possession.
- Left open: no Dash on Circle for a played pawn. Probe `dash9` (read-only, playing the main pawn): `BtnDash` -1, `BtnDash2` -1, `convertBtn(Dash)` -1, not disabled, not restricted; recorder: `setBtnDashText` gets the same Guid and (false, false) for the Arisen (label shows) and for the pawn (label does not). The difference is therefore inside that method or in the guide's state; the same reading as the Arisen is still missing.

### v0.9.132 (2026-11-17): the played pawn's running move command is ended (not tested in game yet)
- **Reported 2026-11-17 on 0.9.131:** the pawn still ran on after take-over.
- `DPC_takeover.json` of that possession (0.9.131, 145 samples): "Stopped the main pawn's path-following (1 so far)" at take-over, `IsNaviNow` false from 0.64 s on and `navi_stops` stays 1; **he still covered 0.4 - 0.9 m per tenth of a second with the stick at 0 until about 6.3 s.** No decision, no requested pack, order 0, guide off. So 0.9.131's `setNavigationStop()` took effect and was not what moves him.
- The type index answered the "what else" question without a decompile (`dd2-modkit index`, built in the container from the packed dump `il2cpp_dump.json.gz`, 15 s): `index uses app.NavigationAI` lists who holds one: `app.CharacterNavigationController` (the pawn's is an `app.PawnNavigationController`, states None / NaviCheck / NaviCalculating / NaviUpdating / NaviStop) and `app.actinter.cmd.move.MoveBase`, a command of `app.actinter.Executor` (`forceEndAction()`, `_CommandExecutor._PrimaryCommand`), reached through `AIDecisionModule.get_ActionInterface()`.
- Bridge probe `nav2` (read-only, nobody possessed, party walking): all three pawns had executor state 1 (Execute), command executor executing, **primary command `app.actinter.cmd.move.Approach`**, navigation controller state 3 (NaviUpdating).
- Reading: the follow movement is a command of the action executor. `forceEndDecision` (0.9.72) ends the decision that issued it but not the command, which runs until he arrives. **Inferred from the two observations above, not yet seen during a possession.**
- Change: while a pawn is played, a running primary command whose type is in `app.actinter.cmd.move.*` is ended with `Executor.forceEndAction()`, checked 10 x a second (`possess_stop_move`, default on). Not done for 8 s after this mod gave the same pawn a skill pack. Log line "Ended X's move command Approach (N so far)", at most every 5 s.
- Take-over recording gains `cmd` (command type, executor state, command-executor state), `navctl` (navigation controller state, idle request) and `move_stops`, so the next recording shows whether a move command was running while he ran, and whether ending it stopped him.
- **Confirmed in play 2026-11-17:** the pawn stops and control is immediate. Recording of that take-over (0.9.132): first sample `cmd` = `app.actinter.cmd.move.Approach`, executor state 1; one tenth of a second later no command, executor state 2 (End), navigation controller state 0; he coasted 0.85 / 0.61 / 0.37 / 0.36 m over the next four tenths and then followed the stick. `move_stops` 2, did not climb. The reading above is confirmed for this case.
- Dash label, same message: "the dash on circle still is not visible on arisen nor the pawn." Probes `dash6` - `dash8` (read-only except one call of the guide's own `updateButtonAssign()`, during a possession): `ui010201.BtnDash` = -1 and `BtnDash2` = -1, `convertBtn(Dash)` = -1 while `convertBtn(Interact)` = 5; `IsBtnAssigned` false; `isDisableDash` / `isRestrictedDash` / `IsWeightOver` false; the pad list is the default one (Dash on Circle and on L3). `updateButtonAssign()` changed nothing. **Not known** whether -1 is the game's normal value there (no reading from a session where the label showed), so the cause is open; next is a comparison with the mod off.
- **Not known:** whether `forceEndAction()` halts him at once; whether the executor starts the next node of the same pack (then N climbs and the pack has to be dropped instead); whether anything else than a `move.*` command can carry him.

### v0.9.131 (2026-11-17): the played pawn's own path-following is stopped (not tested in game yet)
- **Reported 2026-11-17:** on take-over the pawn finished running to wherever it had been heading before it could be controlled; a jump did not break it out..
- `DPC_takeover.json` of that possession (0.9.130, 143 samples): no decision executing, guide "off", order 0, no requested action pack; **`NavigationAI.IsNaviNow` true from the first sample**; he covered 0.4 - 1.1 m per tenth of a second with the stick at 0 until 7.3 s, when `IsNaviNow` went false and he stood. The jump at 4.3 s did not end it. One decision end had been logged at take-over ("decision ended, idle requested").
- So a third thing can carry a pawn on after take-over, besides an AI decision (0.9.72) and the quest guide (0.9.93): its path-following towards the party.
- Bridge probe `nav1` (game paused): `app.NavigationAI` has `setNavigationStop()`, `get_IsNaviNow()`, `get_IsStopCalled()`.
- Change: while a pawn is played (possession or co-op) and `IsNaviNow` is true, `setNavigationStop()` is called, checked 10 x a second (`possess_stop_navi`, default on). Log line "Stopped X's path-following (N so far)", at most every 5 s; the take-over recording carries `navi_stops`.
- **Not known:** whether `setNavigationStop()` alone halts the movement at once, and whether the game simply requests the path again each time (then N climbs quickly and the source of the request has to be found).
- Dash label, from the 0.9.130 recorder in the same session: `setBtnDashText` got (false, false) with the same Guid for the Arisen (2416 calls) and for the pawn (1080 calls). No difference between the two in that minute; whether "Dash" was on screen for either is not yet reported.

### v0.9.130 (2026-11-17): 0.9.129's Dash-label change taken out again; a recorder for the label's arguments instead (not tested in game yet)
- **Reported 2026-11-17 on 0.9.129:** the Dash label now shows for neither the Arisen nor the pawn. (screenshot: Circle blank on the guide while playing the Arisen).
- Counters after about a minute: `setBtnDashText` 3120 calls, `setBtnDashTextEmpty` **0**, skipped 0, the one write "ok". So the assumption was wrong: the game calls `setBtnDashText(Guid, Boolean, Boolean)` every frame and the arguments decide what shows; nothing was ever skipped. **Whether 0.9.129 is what removed the Arisen's label is not established**: its only effects were one write with arguments taken from a single early frame, and the hook on that method being present at all.
- Removed: the `setBtnDashTextEmpty` hook, the write-once, `R.dash_ok`. `hud_dash_label` is left in the settings table unused.
- Developer mode only: the hook on `setBtnDashText` now only counts, per played character (arisen / pawn / coop), which (Boolean, Boolean) combinations arrive, with the first 32 bits of the Guid (`aim.dash_label.seen` in the dev status). A released copy has no hook on that method.
- Next: read `seen` after the Arisen has been walked, sprinted and stood still, and the same as a pawn; then decide whether to rewrite the two Booleans for a pawn.

### v0.9.129 (2026-11-17): the game's "Dash" label stays on the button guide while a pawn is played (not tested in game yet)
- **2026-11-17 / [time], reported with two screenshots:** the played pawn's guide lacks the second Dash label on Circle that the Arisen's has; dashing itself works on Circle and on left stick click, in possession and in co-op.. Also: "Co-op during the test didn't seem keep the main pawn in frame anymore but now it seems to" (in that test step player 2 played the Archer pawn, not the main pawn, so the camera framed the Archer pawn; not looked into further).
- Bridge probes in his running game (`dash1` .. `dash5`, `hud1` .. `hud3`; two of them changed the guide's `PlChara` by hand, which the mod puts right within half a second):
  - `app.ui010201` (the button guide) has `setBtnDashText(Guid, Boolean, Boolean)`, `setBtnDashTextEmpty()`, `isDisableDash()`, `isRestrictedDash()`. During a possession both "is…" answers were false, `Human.get_IsEnableDashAction` false for pawn and Arisen alike (standing).
  - The guide's `PlChara` / `PlInput` were the Arisen's in one reading and the pawn's later; the first was most likely taken during co-op, where the guide is left with player 1 on purpose. `maintain_native_hud` does run and does re-point (seen: back on the pawn 14 s after I set it to the Arisen; `orig_keyguide` can capture the pawn if the guide already points at him when a possession starts, not fixed here).
  - **Why the game blanks the label for a pawn is not known** (no decompile).
- Change (`hud_dash_label`, default on): pre-hook on `setBtnDashText` remembers the arguments while the Arisen is played; pre-hook on `setBtnDashTextEmpty` skips the blanking during a normal possession while `isDisableDash` and `isRestrictedDash` are false and the pawn is not on a monster (checked twice a second); the label is written once with the remembered arguments when that state begins. Not in co-op.
- Assumptions to check: that the blanking goes through `setBtnDashTextEmpty` (counters `aim.dash_label` in the dev status: text / empty / skipped), and that a `System.Guid` taken with `sdk.to_valuetype` can be handed back (`put_ok`).

### v0.9.128 (2026-11-17): pawn downer moved to Ctrl+F10; TestGuide 2.2 (not tested in game yet)
- **Reported 2026-11-17, in `walk-1-developer`:** the plan would not advance past the downed-pawn step on End; a Griffin then interrupted the run..
- Result file: steps 1 - 7 done; aimed skill on the aim button PASS (counter 2), back on the Arisen PASS, co-op started PASS; while the Archer pawn aimed, the camera mod reported "suspended: Non-Player Camera (Event/Talk…)" (information). Step 8: a pawn was down for 24 s of the 49 (Shift+F10 worked), then the plan ended as **"aborted"**, not advanced.
- Cause, as far as the data goes: Shift+F10 is Windows' context-menu shortcut. After it, `reframework:is_key_down(Shift)` kept answering true, so TestGuide read End as Shift+End, its abort key. Not reproduced in isolation.
- DPC: the downer hotkey is **Ctrl+F10** (button text too). TestGuide 2.2: Shift counts for Shift+End only when it went down in the last 5 s.
- New plan `walk-1b-developer` (queue `70b_…`) repeats the cut-off part: downer, heal, the Arisen's fight, and the switch to player mode for `walk-2-player`.
- From the three camera checks of that run: co-op bow zoom ran (co-op +0.0 m reported); the weapon-drawn and aim checks were by eye, no Home press was recorded.

### v0.9.127 (2026-11-17): the developer recorder follows the character being played (not tested in game yet)
- **2026-11-17:** Fighter Arisen and Fighter pawn available, ready to test the grab controls changing while climbing. (follow-up to an earlier note: the key prompts while climbing are similar to those on the ground; a Fighter Arisen is the comparison to make).
- The recorder (`DPC_demo.json`, developer mode) only ran while the Arisen was played by hand. Now, during a possession, it records the played pawn instead: its own input flags and action nodes, with a marker line when the recorded character changes and "(on monster)" on lines taken while `Character.IsClimbOnCharacter` is true. Not in co-op.
- Purpose: one climb as the Fighter Arisen and one as the Fighter pawn, same buttons, laid side by side, to see whether the pawn gets the same climbing actions as the game's own player.

### v0.9.126 (2026-11-17): dead calls found by the type index removed (no change in behaviour; not tested in game yet)
- New tool: `dd2-modkit index check <file.lua>` compares every game name a script uses with the full type database of dd2.exe 4.1.0.0 (202,055 types, from REFramework's SDK dump). Variable hints for it are in `ix_hints.txt` at the repo root.
- REFramework source confirms: `obj:call("name")` on a method that does not exist returns nil, with no error. It also does not remember the miss, so each such call walks every method of the type and its parents twice.
- Removed, all of which never ran:
  - `LockOnController.updateTargetWhenUnlock` and `updateSpellTarget` in `update_pawn_lockon_target` (no such methods on any type). Setting `Chara` to the pawn stays.
  - `HumanActionSelector.requestAimAction(app.LocomotionSpeedTypeEnum)` in the Archer / Magick Archer hold-to-aim branch. The real method is `requestAimAction()` with no arguments. It was not switched on: the pawn already enters `Job02_StartAim` (archer-aim-1), so the aim comes from the mirrored `AimHold` input, and a second request every frame is untested.
- Settled by the index, no code change: `app.Human.get_SkillContext()` is the real getter (no `get_HumanCustomSkillContext` exists); `requestCustomSkill(app.HumanCustomSkillID, app.LocomotionSpeedTypeEnum)` takes a speed type (Idle 0, Walk 1, Run 2, Dash 3), which is what the code passes.
- The [time] crash stack from v0.9.125 is unchanged by this; the Oct 31 crash address `DD2.exe+0x52345ae` is in unnamed native code and could not be resolved.

### v0.9.125 (2026-11-17): after a crash in co-op: the key table is read on demand; test commands; two test plans
- **2026-11-17: run finished.** (he ran both plans straight away, on 0.9.125).
  - `coop-soak-1`: **no crash.** About 3.5 minutes of co-op across all three party members (the main pawn, the Archer pawn, the Thief pawn), 14 actions each, map "game assignment (44 bindings)", 0 errors. 51 of 52 checks; the one miss is a faulty check of mine (a text value compared with `last`), not a finding. So the crash did not come back; its cause is still not established.
  - `morning-check-1`: 23 of 23. Quick skills: 9 orders accepted, 3 empty slots (the Archer pawn has one skill), 1 "no enemy" (Perfect Guard, when the target was gone). Sources: the pawn's live decisions for 7, **the game's table for Springboard and Attract** (`DPC_skill_table.json`: 682 action packs read, 82 skills, 82 resolved, same picks as the offline run). Aimed skill on the game's aim button fired on the Archer (counter 1). **Downer by command: the Thief pawn down; the Arisen: "Remedy Arrow for the Thief pawn (down)" -> "Remedy Arrow: the Thief pawn revived (assisted)" 5.1 s later.**
  - Also in that log: a Magick Archer skill press that "did not start" at 100 % stamina, so stamina is not the reason for those.
- **Reported 2026-11-17:** the game crashed. Testing stopped for the night; the remaining test plans were prepared for the morning.
- **The crash** (`re2_framework_log.txt`, `reframework_crash.dmp`), [time] by the PC's clock, DPC 0.9.124, remapped controller:
  - [time] co-op started by hand on the Archer pawn (Archer), map "game assignment (44 bindings)". 17 s later: `c0000005`, a read of address `0x100000050` (minidump: a non-pointer value, `RAX = 0x100000000`, used as an object).
  - Stack, all inside the game on a worker thread: `app.ui020901.update` -> `updateDisp` -> `setupStatusIcon` -> `ui020901.IconInfo.disp` -> `app.GUIBase.ConditionIconRef.setup`. `ui020901` is the game's health / stamina gauge, the one widget the mod re-points at the pawn in a normal possession (`HUD_GAUGES`); in co-op it is left with the Arisen (`COOP_OVERRIDES.native_hud_gauges = false`).
  - DPC's own state at the last write (about 1 s before): 0 errors, co-op active, no controller button held.
  - Three co-op runs of about 20 s each had passed in the half hour before (release-check-3, -3-remap, -4), all on the main pawn; this was the first co-op on the Archer and the first started by hand that night.
  - **Cause not established.** Candidates, none confirmed: (a) the game itself, after several controller remaps in a row; (b) 0.9.124's new timer that walked the game's key table every 6 s; (c) one of the action flags player 2's pawn now receives that it did not before 0.9.124 (`Draw`, `ShootRelease`, `ThrowRelease`, `Shift1OnlySpecificJob`, `Gimmick*`, `Glider*`, `SwitchSkill`, `Job08SwitchSkill`, `Job02MeteorShotSwitchAimType`, `Descent`); (d) something left over from the developer pawn-downer (the Archer pawn was its test subject at [time]).
- Changes:
  - Precaution for (b): the key table is read once after loading and again when a possession or co-op session starts, not on a timer.
  - Test commands in `DPC_cmd.json` (developer mode): `{"cmd":"quick","slot":N,"idx":P}` (the numpad skill order) and `{"cmd":"heal"}` (party heal / revive). Robot option `"noshift": true` presses an action's button without its shift.
  - Settings text "Skills while aiming on a controller (aim button + skill buttons)".
- Test plans queued for the morning (`TestGuide/examples`, game queue `65_…`, `66_…`):
  - **`coop-soak-1`** (about 4 min): co-op on each party member in turn; the robot walks and presses 14 actions by name. Tells whether the crash comes back, and with which pawn / action.
  - **`morning-check-1`** (about 3 min): 12 quick-skill orders (3 pawns x 4 slots) against a goblin that stands still, checking the game's table was read (0.9.115, never tested); aimed skill on the game's aim button for the Archer pawn; the pawn downer by command, with 25 s for the Arisen's Remedy Arrow or a pawn to bring her back; party heal at the end so nobody stays down.

### v0.9.124 (2026-11-17): any controller layout, any keyboard layout
- **Confirmed in play 2026-11-17:** both players moving at once in co-op works. (player 1 on the keyboard's direction keys while player 2 pushes the stick; the 0.9.124 key reading, default keys). His hand-started co-op on the Archer pawn ran [time] - [time] with no crash.
- **Reported 2026-11-17, after remapping several buttons** (the run looked good and the skills fired; the test's on-screen text named the wrong buttons): `result_release-check-3-remap.json` 24 of 25. Co-op map in use, from the game: light attack Circle [80], heavy Square [40], dash / interact Triangle [10], skills 1 - 4 on L1 + Triangle / Square / Cross / Circle; the co-op stick, light-attack and skill-1 checks passed on those buttons. **So a remapped layout works in co-op.** The one failed check, "the Arisen attacks on his own", counted only plain attack presses: the Magick Archer opened with a skill (0.9.116 cadence), the goblins were gone, and he was idle for 209 of 269 samples; presses 0, skill uses 1. A weakness of the check, not of the layout code. `release-check-4` counts skills too and no longer names buttons in its on-screen text.
- **Result 2026-11-17, on the game's default layout:** passed.. `result_release-check-3.json`: 25 of 25 checks; co-op map in use "game assignment (44 bindings)"; 0 errors. Verified by that run: the co-op map from the game's list (stick, light attack and skill 1 by action name), select and take control, the Arisen fighting. Not covered by it: a remapped layout, the keyboard readings (direction keys, skill modifier), aimed skills on the aim button, the key-clash notice.
- **Reported 2026-11-17:** the tester had been playing on a remapped controller layout all along; with aim on L2 the chorded skills glitched, which looks like a bug in the game. Requirement: the mod must work on the default layout and on any remapped one. His old layout is written down in `the tester's notes`. Direction: support whatever controller and keyboard bindings a player may have.
- **What was wrong (found by reading the code against the game's default list, `dev/bridge/kb1`):**
  - **Co-op: player 2's whole button table was the tester's remap** (measured on his controller on 2026-11-12 and taken for the game's layout): R1 / R2 attacks, L2 vocation action, Circle sheathe, Triangle dash, plus a rule "skills 3 / 4 move to L1 + R1 / R2 when a chord slot is in use". With the default layout player 2 would have got the wrong action on Square, Triangle, Circle, R1, R2 and L2. The shipped `DPC_coop_layout.json` (Grab on Square, Dash on Triangle) was his remap too.
  - Aimed skills for a possessed bow pawn waited for L2 (his aim button); the default aim button is R1.
  - Co-op moved player 1 with W / A / S / D whatever the game's keys were; the same in the pawn's own stick fallback.
  - Skill-modifier key fixed to Ctrl; the old puppeteer mode had Shift = dash and right mouse = vocation action fixed.
- **Now read from the game, every 2 s (pad) / 6 s (keys):**
  - Controller: all of `getCurrentCharacterPadAssign().AssignList` (`R.bind.list`, `R.bind.by[action]`), not only the six skills. Action index a = input flag `1 << a`; `PreInput` 14 / 15 = Shift1 / Shift2 must be held; `IsIgnorePreInput` respected.
  - Keyboard and mouse: `UserInputManager.KeyBindController.getCurrentKeyBindSettingTable()` (probes `kb2`, `kb3`): 101 `KeyBindSettingItem`, `_CharacterCommand` = the same action index, three keys each, `via.hid.KeyboardKey` = Windows key codes (default: W 87 / S 83 / A 65 / D 68, Space jump, left Shift dash, left Ctrl skill modifier, mouse 1 / 2).
- **Used for:**
  - Co-op button map = the game's list (`coop_map_assign`, default on), minus pawn orders and item shortcuts (the mod handles player 2's D-pad itself). Rebuilt when the layout changes in the options. Skill shift = the Shift1 button; the vocation-action button also counts as a skill shift for bow vocations only (as the game does: `Shift1OnlySpecificJob`). Fallback when the list cannot be read: the game's default layout (was: the tester's remap). The layout override file is ignored unless `coop_layout_file` is switched on, and is no longer in the zip.
  - Aimed skills: the button the game has `AimHold` on.
  - Player 1's direction keys in co-op, the stick fallback, the skill-modifier key, dash and vocation action in the old puppeteer mode.
  - Labels of the mod's own skill lists ("L1+…" prefix and the vocation action button).
  - Log lines at start: "Controller layout (from the game): light …, heavy …" and "Keyboard layout (from the game, key codes): …".
  - **Key clashes:** if one of the mod's keys (F6, F7, F8, Numpad 7, Numpad .) is also bound in the game, the log and the top of the settings window say which.
  - Test robot: `{"who":"pad","actions":["AttackS","Skill1"]}` presses whatever buttons the game has those on (with the shift a skill needs). New plan `release-check-3` uses that for the co-op steps, so it passes with any layout; `release-check-1 / 2` have R1 as "attack" baked in and only fit the old remap.
- **Not changed, on purpose:** the mod's own controller combos are physical buttons (hold D-pad left / right / down, L1 + left stick click). Normal possession needed nothing: the pawn is driven by the game's own input flags, which already follow any remap; the Arisen's brain presses flags, not buttons.
- **Still fixed keys:** a few raw-key fallbacks in the old puppeteer mode (Space jump, left mouse attack, number row).
- Why the tester's Remedy Arrow never charged (for the record): with his remap the Triangle+Circle chord while aiming went straight to `LifeReturnWithoutAim`; Hailstone Bolt on Triangle alone went `Prepare` -> `Ready` -> `Shoot`. And with Circle = sheathe, the chord's Circle kept its own action, hence the sheathing. Both are the game's handling of his remap, reproduced with all mods off.
- Not tested in game. To test: Reset Scripts, check the two "layout (from the game)" log lines against the options menu, then run `release-check-3` (End).

### v0.9.123 (2026-11-17): the developer recorder also logs the skill charge (not tested in game yet)
- **Reported 2026-11-17 (playing the Magick Archer by hand, on Remedy Arrow):** the arrow hit the downed pawn but did not revive her; the one input that loads the skill is holding L2 and then pressing the chord; the same happens with all mods off; holding the chord drops out of aim; with L1 or L2 held the shot fires at once, with both held nothing happens..
- **Not the mod:** it fails the same with all mods off (the tester's test). A pawn downed with the 0.9.122 tool was picked up by hand normally (`RescuePawn` in the recording).
- Recordings (`DPC_demo.json`): every Remedy Arrow was `Job08_CS08.Job08_LifeReturnWithoutAim`, about 3 s long whatever was held (chord tapped, chord held 3 s, L2 held). My three guesses of how to charge it (hold the chord; hold L2 after the press; ring first) were each wrong or unconfirmed.
- **Game data, read with the bridge (`j8`, `j9`, `j10`):** `Job08Parameter.LifeReturnParam.ChargeArrowParam`: `SecPrepare` 5.0 s (4.0 with "Focus", 3.5 at skill level 2, 2.8 with both); `ReviveNodamageFrame` 600; `MultiParam.MultiLockOnCount` 3. `Human` has `IsSkillPreparing`, `RatePrepareSkill`, `IsSkillPrepared`, `TimerPrepareSkill`; `Job08ActionController` has `MagicBowSkillPreparedEffect` and `ArrowStanceSoundSkill`. So a 5 s charge exists in the game's data; **what starts it is not known.** Fextralife: revives only fully charged; Rivet Shot mode "press the button, then press it again or release R1".
- Change: the recorder (developer mode, the Arisen played by hand) appends `{skill N charging 50% ready}` to a line whenever a skill state or a charge is active, so the next session shows when the charge runs and what the buttons were.

### v0.9.122 (2026-11-17): the pawn downer works through the damage path (bridge-tested once; the hotkey itself not tested yet)
- **Reported 2026-11-17:** the pawn-downer key did nothing.. Log: four runs on the Archer pawn, each "trying way 1 / 2 / 3" then "none of the three ways put the Archer pawn down; health restored". Setting the health number to zero does not make the game run a death.
- Probes `dn3`, `dn4` (read-only): `HitController` has `IsDie`, `IsStartDead`, a `DieHandler`, and death is decided in `updateDamageHp(HitController.DamageInfo, Single, Boolean)`; `IsNoDie` / `IsInvincible` were false on the pawn.
- **Bridge experiment `dn5` in the tester's live game (state-changing, done because he was pressing the same thing):** a new `HitController.DamageInfo` (Damage and FixedDamage 99999, IsDirectDamage, both damage hit controllers = the pawn's) passed to `updateDamageHp(info, 99999, false)` on pawn `ch111011`: hp 1517 -> 0, `IsDead` true, `IsDie` true, no error. **That pawn was left down by the test.**
- The tool now does exactly that, once, and logs "Down a pawn: X -> down / NOT down".

### v0.9.121 (2026-11-17): developer tool to put a pawn down (not tested in game yet)
- **Reported 2026-11-17:** unsure whether the ring has to be on the downed pawn before the chord; the pawn had to be rescued by hand before her timer ran out. Request: a debug key that downs a pawn.
- Developer mode only: **Shift+F10**, a button at the top of "Test bench", or `{"cmd":"down","idx":N}` in `DPC_cmd.json` puts the selected pawn (F7) down. Never the pawn being played.
- **How to down a pawn was not known.** Bridge probes `dn1`, `dn2` (read-only) list `HitController.setHpValue(Single, Boolean)`, `setHp(Single, Boolean, Int32)` and `Character.killAndSetDieLoop(option)` (not used: looks like scripted corpses). The tool tries setHpValue(0, false), setHpValue(0, true), setHp(0, false, 0) in turn, 1.2 s apart, until `Character.IsDead` is true, logs which way worked ("Down a pawn: X is down (way N)") and restores the health if none did. Once known, the ladder can be cut to the one that works.

### v0.9.120 (2026-11-17): the magick-bow ring is switched back on when the Arisen is played again (not tested in game yet)
- **2026-11-17 / [time], reported while playing the Arisen (Magick Archer) by hand:** pressing the Remedy Arrow chord lights all three button indicators in the game's skill display, but the skill does not start. Then, with a pawn down: repeated presses sometimes start it, but the arrow does not hit the pawn.
- Bridge (read-only, `ra1`, `ra2`): `HumanSkillAvailability.isCustomSkillAvailable` true for all six skills incl. 87; stamina and health full; mod idle, 0 errors.
- Recording of his presses (`DPC_demo.json`, 0.9.119, 143 lines): 40 Triangle+Circle presses. **10 carried skill flags (`Skill2+Skill5`) and each started `Job08_CS08.Job08_LifeReturnWithoutAim`; 30 carried none** (Triangle arrived as `Dash / Ascent / Interact`, Circle as `Draw / Sheathe / ActCancel`), all of those with the aim button held (`AimHold ...`) and no `Shift1+Shift2`. The two presses made without the aim button show `Shift1+Shift2` and worked. So in the failed presses the game saw no skill-shift (L1). Whether L1 was physically held is not in the data.
- Every press that worked held the skill buttons 0.2 - 0.4 s and got the unaimed version (`...WithoutAim`). The aimed, charged version (the one that revives, see 0.9.108) never started in the recording. From the 2026-11-16 demo, Magick Archer skills aim by holding the skill buttons themselves (`Prepare` -> `Ready` -> release), not with the aim button. **Suggested to the tester, unverified for this skill:** hold L1 + Triangle + Circle, sweep the ring over the downed pawn, release when charged.
- Found while looking: `R.ring_hook` switched the ring (`GuiManager.MagicBowReticle`) off during a possession and never on again. Now it is switched back on at the first ring update after the possession ends. Whether the ring had in fact stayed hidden for the Arisen is not known.

### v0.9.119 (2026-11-17): skill list while the played pawn climbs on a monster (verified 2026-11-17: it works)
- **Reported 2026-11-17, Fighter Arisen and Fighter pawn on the same monster (DPC 0.9.126), three screenshots:** while climbing, the Arisen has Gutting Skewer available and the pawn does not; otherwise they behave the same.
  - Arisen, L1 held on the monster: his six skills greyed except Gutting Skewer. The main pawn possessed, L1 held: all six greyed (Flawless Guard, Full Moon Slash, Burst Strike, Launchboard, Riotous Fury, Shield Pummel). **the main pawn has no Gutting Skewer equipped**; that is the whole difference. Without L1 both show Release / Empale / Onslaught / Jump.
  - Log: "Off the monster (the game greyed a skill 2670 / 2790 / 3960 / 2592 times while on it)". So the game does answer "disabled" while climbing, **when the skill list is showing (L1 held)**, and this version's pass-through is what greys the pawn's list. The 0 in the [time] run was a climb without L1; my note below that "the change does nothing" was wrong.
- **2026-11-17, climbing as the main pawn:** log "Climbing on a monster" for 32 s, then "Off the monster (the game greyed a skill 0 times while on it)". So the detection works and the game's `isDisableCustomSkill` never says "disabled" while climbing; the assumption below was wrong and this change has no effect. His screenshots: the game's button guide on the monster reads Release / Empale / Onslaught / Jump / Switch Weapon Skill, "similar to on ground" (the ground guide: Empale, Onslaught, Jump, Sheathe/Draw, Grab, Defend). To be compared with a Fighter Arisen () to see what the game itself shows when its own player climbs. Open until then.
- **Reported 2026-11-17** (Fighter main pawn on the Griffin): while climbing, the R1 / R2 buttons change for many vocations; the hints still showed Launchboard while the pawn was clearly stabbing..
- The recording of that possession (`DPC_takeover.json`) only covers its first 15 s and holds no climbing node, so the climb itself is not in the data.
- Found in the code: hook 2d on `app.ui010201.isDisableCustomSkill` returned "not disabled" for every skill during a possession ("never grayed out while possessing"), so the game's skill list could not grey out skills the climb replaces.
- Change: while the played pawn is on a monster (`Character.get_IsClimbOnCharacter`, found with bridge probe `cl1`, read 10 x a second) the hook lets the game's own answer through (`hud_cling_grey`, default on). Log lines "Climbing on a monster ..." / "Off the monster (the game greyed a skill N times ...)".
- **Assumption, not verified:** that the game's answer for the pawn is right while climbing (the list's `PlChara` is the pawn since `setupPlChara` is re-pointed). If N in the log stays 0 while skills visibly turn into stabs, the game decides this elsewhere and the list needs another way.
- Not changed: the co-op skill palette for player 2 and the optional old palette (both drawn by the mod) still list all skills while climbing.

### v0.9.118 (2026-11-17): Vimtaking Arrow rule counts the pawns' health too (not tested in game yet)
- **Reported 2026-11-17:** Vimtaking Arrow seems to heal the whole party.. Not checked against the game; taken as given. The rule from 0.9.117 now looks at the lowest health share among the Arisen and the living party pawns (read twice a second) instead of only his own.
- **Same message, noted for later, nothing changed:** while a pawn is possessed and the Arisen is low on stamina, his panting is still heard; most sound seems to come from the Arisen's position. Left for later.. Not investigated: where the game's audio listener sits while a pawn is played, and whether the out-of-breath sound is tied to the player character rather than a position. On the after-release list.

### v0.9.117 (2026-11-17): Magick Archer: Hailstone Bolt is held to charge, Vimtaking Arrow kept for when he is hurt (not tested in game yet)
- **Confirmed in play 2026-11-17 on 0.9.116:** the Magick Archer Arisen casts his skills.. Brain log of that fight: 29 skill presses in the last 100 s (before: one per 7 - 14 s), 0 errors. Stamina ran between 20 % and 55 %, twice under the 20 % line. Presses that started nothing: 12 in the fight, at 21 - 34 % stamina, while the same skill (id 80) also started at 27 %, so stamina alone does not explain them. Open.
- **Reported 2026-11-17:** Hailstone Bolt needs a hold to charge and then aims like the Irradiant Orb; un-aimed it fires a weak version. Vimtaking Arrow heals by the number of targets it hits..
- Hailstone Bolt (id 83, `Job08_FrostBlock`): the skill button is now held 2.0 s (`arisen_brain_ma_charge_s`) instead of 0.5 s so it can charge. He still does not aim (the aim is the player's camera), so by the tester's description it stays the weaker, unaimed version. **Unknown: whether the unaimed version charges at all while held, and how long a full charge takes.** The next brain log's node names will show it.
- Vimtaking Arrow (id 86, `Job08_AbsorbArrow`): pressed only when he is below 80 % health (`arisen_brain_ma_vim_hp`), or hurt at all (below 97 %) with three or more enemies within 25 m (`arisen_brain_ma_vim_group`; the count comes from the Conversion check and can be up to 8 s old). At full health the slot is skipped.
- Not tested in game.

### v0.9.116 (2026-11-17): Magick Archer Arisen uses his skills back to back (not tested in game yet)
- **Reported 2026-11-17** (Griffin from the test bench, playing the Thief pawn): the Magick Archer Arisen only fires quick shots, over and over..
- Evidence, `DPC_arisen_brain.json` of that fight (0.9.115, 163 s): 23 skill presses, exactly one every 7 s (`arisen_brain_skill_cd`). A skill lasts about 2.6 s (`Job08_…WithoutAim` nodes), the other 4.4 s are `Job08_NormalShootWithoutAim`. **From the second round on, the presses for slots 2 (id 83), 4 (id 80) and 6 (id 86) were followed by no skill node at all**, so only slots 1 and 3 fired: one skill per 14 s. Nothing to do with 0.9.115's quick-skill change (the brain presses buttons, it does not use action packs).
- Cause of the thin skill use: the flat 7 s rule, made for melee. Cause of the presses that start nothing: **not known** (stamina is the first suspect; it was not logged).
- Change, Magick Archer only: the wait before the next skill runs from the end of the skill itself (`arisen_brain_ma_skill_gap`, 1.2 s, about one plain shot; 0 = old rule). A press that starts no skill within 1.5 s is logged ("skill slot N did not start") and the next slot is tried at once. No skill below 20 % stamina (`arisen_brain_ma_stamina`), plain shots meanwhile. Skill events now carry his stamina.
- Not tested in game. To look for in the next fight's brain log: how often "did not start" appears and at what stamina.

### v0.9.115 (2026-11-17): quick skills read the game's own skill table; the borrowed table is gone (not tested in game yet)
- Decision (about a table of our own instead of Pawn Tactical Wheel's): build our own from the game's data and credit the idea. Decision: build the harvester, replace the table, and credit Pawn Tactical Wheel for getting it started.
- **Found instead of a harvester: the game's complete table, readable while playing.** Bridge probes of 2026-11-17 (`dev/bridge/skills/hv1`..`hv11`, read-only, game running, party Fighter / Archer / Thief):
  - A type search from the pawn's components for anything holding `app.DecisionPack` led to `app.goalplanning.AIGoalPlanning._AIGoalData` (`AppSystem/ch/ch100/UserData/PawnAIGoalData.user`) `._CSDecisions` = `app.goalplanning.CustomSkillDecisions`, asset `AppSystem/AI/GoalPlanning/CustomSkillDecisionRefData.user`.
  - `_CustomSkillDecisions`: **82 entries, one per weapon skill of the six pawn vocations** (`_SKillID`, `_DecisionPackList`). Each decision has `_HumanCustomSkillIDs`, `_ActInterPack` (`get_Path`) and `_Target` (`AITargetFlag`: My 1, Player 2, Enemy 4, Animal 8, Gimmick 16, Interact 32, Party 64, SpatialEvent 1024, Position 2048, WrestlePoint 4096). All three pawns point at the same asset.
  - (`CharacterManager.DecisionPackCatalog` again held only 26 packs, the party's equipped skills; `_NormalSkillDecisions` has 10 more entries, not used.)
- **The mod now builds the table from that asset the first time a quick skill is used** (`quick.game_rows`, `quick.table_def`), nothing ships. Rule for the plain pack of a skill: file name contains the skill's enum name (`Job01_BlinkStrike` ...), else the decisions naming the skill, else the same name in another entry (Spell Hold: `Job03_SpellStockRelease`); situational variants are skipped (`_Spot`, `Climb`, `_Charged`, `_Multiple`, `_NPC`, `_ch…`, `Quest`, `Common/` ...); shortest name wins. Target kind from the flags of that pack: Enemy if set (falling back to the pawn itself or the Arisen when no enemy is near and the game also lists My / Player / Party for it), else Player/Party = the Arisen, else the pawn.
- **Checked offline** (`dev/bridge/skills/t115.py`, results in `hv9.out` / `hv11.out`, the shipped Lua functions run on the probe dump): 82 of 82 skills resolve; for 71 the result is the same file and target as the old table, which was never consulted. The 11 that differ are the game's own flags: Shield Summons and War Cry now aim at an enemy (`…_EMTarget`, `…_TargetEM`), Perfect Guard and Divine Defense at an enemy, Palladium (`GuardBit_Lv1`) and Guts at the pawn itself, Celestial Paean (`DivineShot`) at the Arisen, Stealth / Scarlet Vow / Spell Hold at an enemy with the pawn as fallback, **Flame Blade only at an enemy** (flags Enemy + Gimmick; before: itself, so it can no longer be put on out of battle with a quick skill).
- Removed: `QUICK_PACKS` (82 lines from Pawn Tactical Wheel's `data.lua`), `QUICK_PACK_ROOT`, the learned file `DPC_skill_packs.json` (no longer read or written; an old copy in `reframework/data` can be deleted). Order now: the pawn's live decisions (as since 0.9.17), then the game table. The world guard drops the cached table on a load.
- Developer mode writes the resolved table to `data/DPC_skill_table.json` on first use.
- README credit reworded: Pawn Tactical Wheel for the idea and the bootstrap; no data from it in the release.
- Not tested in game: any quick skill on 0.9.115 (needs "Reset Scripts"). Worth one press each in a fight: a Fighter skill, a Mage heal, Flame Blade, Shield Summons.

### v0.9.114 (2026-11-16): first-run experience for a new player
- **Result 2026-11-16:** only the two current zips remain; all checks passed. (`release-check-2` on 0.9.114: 25 of 25, 0 errors; the release folder holds only the two 0.9.114 zips).
- Direction for the release: clear out old material; nothing should confuse a new user; the defaults should just work, as though the game had always been designed to be played this way.
- **Decision: the Pawn Tactical Wheel fallback table stays** (quick skills work from the first press; credit in the README). Its permission terms on Nexus are the tester's to check.
- Found in a pass over the defaults, each of which a new player would have met:
  - **F9 / F10 / F11 test hotkeys were live for everyone** (`test_hotkeys` default true, no developer check): F9 spawned test enemies, F11 switched the Arisen's brain off. Now developer mode only, and the "Test bench" section too.
  - **The top-left status panel was on by default**: "CONTROLLING PAWN", HP, speed in m/s, last action, key hints, the brain's mode and target id. Now off by default (`hud_overlay`; Screen: "Status panel ... for troubleshooting"). Settings files from before get it switched off once (`migrated_0114`), and "Show advanced ..." unticked.
  - **The settings window was drawn from `re.on_frame` whenever `window_open` was set**, with no check that the REFramework menu is open. It now returns unless `reframework:is_drawing_ui()`.
  - **The Numpad . heal cheat was on by default.** Now off (`party_heal_key`); an existing settings file keeps its own value.
- In place of the panel: one line, at the selection label's spot and size, for 3 s: "Playing as <name>", "Back to the Arisen", "Co-op: player 2 plays <name>" (`R.note`).

### 2026-11-16: release check passed; the save-load errors looked at again (no code change)
- **`release-check-1` on 0.9.113 / camera 2.9.6: 25 of 25 PASS** (result: all checks passed.). Among them: lock-on with the played pawn 100 % of the samples before and during the fight, safety net 0 firings, the magick-bow ring hidden 100 %, possession held through the fight, hold D-pad right / L1 + left stick click / hold D-pad down by the robot, co-op stick 6.07 m/s with the Arisen at 0, attack and skill 1, 0 errors in both mods.
- **Save load with the world guard** (note: a save had been loaded a few minutes earlier.): log [time] "World is loading: the mod pauses until it is back", three "Scene changed" lines, [time] "World is back: the mod resumes". **0 access violations** ([time], without the guard: 77). So `IsInGamePhase` / the player character do drop out during a load and the guard trips. One load is one data point; the [time] violations are still not attributed.
- **The steady `get_GameObject` exceptions are not from the mods.** After that load they ran at exactly one every 0.25 s for 8 minutes (1865 lines), starting while DirectPawnControl was still paused by its guard. Source: `reframework/autorun/_claude_stamina_recorder.lua`, a temporary test recorder from an earlier session ("Delete when done testing") that tests a cached HUD gauge with `gauge:call("get_GameObject")` four times a second and writes a JSON file each time. It and `_claude_dist_recorder.lua` (2 Hz, also writing a file) were replaced on the test PC by empty stubs; the originals are in `docs/retired-dev-helpers/`. Neither was ever part of a package.

### v0.9.113 (2026-11-16): release checks; world guard while the game loads (not tested in game yet)
- Direction: get it ready for release, with as much autonomous testing as possible..
- **Static checks (both mods):** compiles; the bytecode listing has **no** write to a global and no read of a global outside Lua's and REFramework's own names (so no misspelt variable anywhere in the 7,900 lines).
- **Log review** (`re2_framework_log.txt`, whole evening): dev status 0 errors on 0.9.112 / camera 2.9.5; no "ERROR in" line from this mod; "Lock-on had left the played pawn" **0 times** since 0.9.95 (the safety net never fired, so the two holes were the cause). Found: 221 `via.Component.get_GameObject` `InvalidOperationException` lines; 164 of them plus **77 caught access violations in one second at [time], during a save load** ("Scene changed", DPC 0.9.93, not possessing). The rest come in ones and threes right after test enemies are despawned or die (a destroyed object asked for its GameObject). The log does not name the script, and LootOverlay, CampfireWaypoints, the agent bridge and TestGuide were loaded too.
- **World guard** (`R.world_check`): both per-frame entry points return at once while `MainFlowManager.IsInGamePhase` is false or there is no player character, and for 1 s after. (The load icon and `SaveDataManager.IsBusy` were left out on purpose: they may also be up during an ordinary autosave, and dropping a possession on every autosave would be worse.) On the way in: a possession is released ("loading"), and cached objects are dropped (test units, HUD widgets, selection marker, brain and co-op targets). Logged as "World is loading ..." / "World is back ...". `IsInGamePhase` read true in game; its value during a save load is not yet seen, so the guard may simply never trip.

### v0.9.112 (2026-11-16): selection arrow without the name; gone at once on possession (not tested in game yet)
- Requested: no name over the selection arrow (the game's name plates are already there), and the arrow gone the moment the character is possessed.
- The marker is the yellow wedge only. `start_possession` clears it.

### v0.9.111 (2026-11-16): larger selection label (not tested in game yet)
- Reported (screenshot: the label shows, small, under "To me!" at the left of the bars): the font of the "Selected: <name>" label should be larger. So the label, its position and the name source from 0.9.110 work.
- The label is drawn with the default font loaded at `sel_label_size` x screen height (0.014 = 30 px at 2160; it was about 13 px) through `imgui.load_font(nil, px)` + `push_font` around `draw.text`. Falls back to the small text if the font cannot be loaded (`R.sel_font_ok`).
- Unverified: that `draw.text` follows the pushed font in this REFramework build.

### v0.9.110 (2026-11-16): selection name on the HUD; the Arisen's magick-bow ring hidden while a pawn is played (not tested in game yet)
- Reported (screenshot of the HUD): a selected pawn off screen has no visible indicator; request a name label left of the health and stamina bars. Also: the Magick Archer's ring popped up when the Arisen fired a skill.
- **Selection label:** "Selected:  <name>" at 21.5 % / 95.7 % of the HUD area (`sel_label_x`, `sel_label_y`; left of the game's health bar in the screenshot), bright for 4 s after a change, dim while a pawn other than the default is the pick. `sel_label = false` hides it.
- **English names:** read live: <non-Latin name> has `PawnDataContext.get_Nickname()` = "the Thief pawn" (the main pawn: "Tiger", the Archer pawn: "the Archer pawn"). `get_party` now uses the moniker when the name has non-Latin characters, which matches the game's own plate ("the Thief pawn"). That name is used everywhere the mod shows or logs a pawn.
- **Ring:** `GuiManager.MagicBowReticle` = `app.ui020804` (methods `setDraw`, `getLockonState`, `update`, ...). Post-hook on its `update`: while a pawn is played (not co-op) its GameObject's `DrawSelf` is switched off. `hide_arisen_ring = false` turns that off. Not hidden: `MagicTarget` (ui020802), `Aim` (ui020801).
- Unverified: both. The label position is estimated from one screenshot.

### v0.9.109 (2026-11-16): the played pawn leaves dead NPCs alone (not tested in game yet)
- Reported: a played pawn can walk up to a dead person and revive them with the Wakestone animation but without the game's Wakestone menu. Question: show the menu, or leave Wakestone revives to the Arisen?
- Cause: the pawn's interact treats every dead character as a corpse to loot and forces the object's interaction (`addActiveInteract` + `executeInteract`). On a dead NPC that interaction is the Wakestone revive, run without the confirmation the game shows the Arisen.
- Now off: a dead character with a `Human` whose id does not start with `ch2` (so not a monster or a human enemy) is skipped; the pawn shows no prompt for it. `pawn_interact_dead_people = true` in the settings file brings the old behaviour back. Not known: whether the forced revive used up a Wakestone.
- Showing the game's Wakestone menu for a pawn is not attempted before release: forcing a menu meant for the Arisen is what crashed at the vocation counter (0.9.58).
- Also from reported: the Magick Archer's ring popped up a few times while an Archer pawn was played. Not looked into yet (when it shows is the open question).

### v0.9.108 (2026-11-16): assisted Remedy Arrow
- **Verified by result:** good enough..
- Reported after 0.9.107: Remedy Arrows fired by hand did not aim at a downed pawn either; a green effect showed that had not been seen before.. His own recording (`DPC_demo.json`): L1 + Triangle+Circle -> `Job08_LifeReturnWithoutAim`, buttons held 1 - 1.5 s, the action 3.5 - 3.9 s long; the Archer pawn down 11.5 m away, not revived. The brain's three 0.9.107 tries did not revive her either.
- What the skill is (guides): revives a fallen pawn only when **fully charged**, heals the allies it strikes if loosed early; it must hit. Enums_Internal.hpp lists the shells `MALifeReturnHip`, `MALifeReturnAim`, `MALifeReturnAimFull`: no full-charge hip shell. Aiming is the on-screen camera's (0.9.104). So a real revive is out of the brain's reach while a pawn is played. The 0.9.105 - 0.9.107 lock-on work was aimed at the wrong problem and is removed (the pawn lock-on switch, the 5 s hand-over).
- Offered: (1) walk over and revive by hand, (2) assisted Remedy Arrow, (3) drop it. Decision: try option 2, and drop the feature if it fails; reviving by hand works anyway..
- **Assisted:** pawn down within 25 m and the skill equipped -> face him, draw, hold L1 + the skill 1.6 s (long enough for the charge effect the tester saw); once `LifeReturn` has played and ended, the mod calls the game's revive (`PawnManager.getPartyPawn` -> `Pawn.setPawnRevive(hp, false, false)`, `Hit.setHpValue`, health = `pawn_revive_health`), the same call as the hold-to-revive feature. Event "Remedy Arrow: <name> revived (assisted)". 10 s between tries. Switch: `arisen_brain_ma_remedy_assist` (default on; Features: "Magick Archer: his Remedy Arrow revives a downed pawn (assisted: the mod completes the revive)"). Off = he never uses the skill.

### v0.9.107 (2026-11-16): the downed pawn's lock-on point is switched on for the Remedy Arrow (not tested in game yet)
- Reported on 0.9.106: he still fires over her..
- Read live with the Archer pawn down 4.8 m from him (`dev/bridge/rem4.lua`): the lock-on work is found now, but it reads `IsLockOnEnable = false`, `LockOnController.isTargetEnableLockOn(work)` = **false**, and its `LockOnPos` is stale (236, 8, -1348 while she lies at 108, -120, 60: not updated while switched off). `isEnableFriendLockOn` = true. The controller had no target at all between tries. So the lock never held and the no-aim arrow flew level in the direction he faced, over a pawn lying on the ground.
- Now: at the start of a try `LockOnTarget.set_isLockOnEnable(true)` on the downed pawn (switched off again 6 s later if still down); the lock-on is kept on that work for 5 s (through the release, not only while the button is held); and after `setTarget` the controller's `setAimTargetInfoToCharacter()` is called.
- Unverified. If it still misses, the fallback is to revive through the game's own revive call when his Remedy Arrow action plays next to a downed pawn.

### v0.9.106 (2026-11-16): Remedy Arrow gets the pawn's real lock-on point (not tested in game yet)
- Reported on 0.9.105: he fired and missed; she was then picked up by hand..
- Telemetry: drawing the bow worked (`Locomotion.DrawWeapon` -> `Job08_LifeReturnWithoutAim`, out of a fight). But every try logged "no lock-on point on him", so nothing was locked. And the second arrow action sat in its node for 14 s while new tries and the skill watchdog's cancel taps piled onto it.
- Read live (`dev/bridge/rem2.lua`, `rem3.lua`): a pawn's `LockOnTarget.get_work()` is nil, but `getWorkCount()` is 1 and `getNearestWork(vec3)` / `get_Works()[0]` return its work. (`LockOnController.Option` has `CanLockOnDeadOnLockOnWithoutEnemy`: the game itself can lock a downed ally.)
- Now: the work comes from `get_work()`, else `getNearestWork`, else `Works[0]`; no new try while a `LifeReturn` node is playing; 10 s between tries.
- Unverified: that the arrow follows that lock.

### v0.9.105 (2026-11-16): Remedy Arrow locks on the downed pawn and draws the bow first (not tested in game yet)
- **Verified by confirmed in play (0.9.104):** he fired all the skills. (Magick Archer without aiming; node log: `Job08_NormalShootWithoutAim`, skills, 18 skill uses). Then: "there is a downed pawn right now and he hasn't tried to fire the revive arrow".
- Read live (`dev/bridge/rem1.lua` + telemetry): the Archer pawn (ch111011) `get_IsDead` true, 13 m away; the brain logged "Remedy Arrow for the Archer pawn (down)" every 7 s, so detection works. In the fight one try did run `Job08_CS08.Job08_LifeReturnWithoutAim` but did not revive her; after "battle over" the tries produced **no action node at all**.
- Two changes: (1) while the Remedy routine runs, the lock-on is handed to the downed pawn (`get_LockOnTarget():get_work()`, the same call used for enemies), in and out of a fight; the 0.9.102 version only faced her. (2) `HumanActionSelector.requestDrawWeapon()` at the start, 1.2 s before the press, and the press held 0.8 s.
- Unverified: that the no-aim Remedy Arrow follows the lock-on, and that a pawn has a lock-on point (the event text says so if not).

### v0.9.104 (2026-11-16): Magick Archer shoots without aiming (not tested in game yet)
- Reported on 0.9.103 (playing the main pawn, Magick Archer Arisen, 3 hobgoblins; screenshot with the magick-bow ring around the pawn): the ring overlay shows while possessing and should be hidden; the Arisen shoots many arrows into the ground from higher terrain..
- Telemetry of that fight: Conversion worked ("3 enemies -> multi-target mode", "1 enemies -> single-target mode", `Job08_ChangeArrow` in the node log). But the aimed shots did nothing: `StartAim` -> `ShootNormalArrow` after only ~0.45 s each time (other brain modes cut the hold), "no damage for 6s -> reposition" nine times, and both skills "did not start while aiming".
- Why: aiming is a camera thing. The aim reticle (the rune ring) is drawn for whoever is on screen and the shot goes where that camera looks. While a pawn is played the camera is the player's, so the Arisen's aimed shots went down the player's view and his reticle sat on the player's screen. **My 0.9.101 claim "there is no attack-button shot" was wrong**: it was only what the demo happened to show. The game has no-aim forms (`Job08_AimTurnWithoutAim`, `PrevTargetWithoutAim`, `PrevSkillIDWithoutAim`, `Job08_LifeReturnWithoutAim`).
- Now: his shots and skills use the generic ranged rules again (light-attack taps, shift + skill), which go to the lock-on target the brain sets, like the Archer's. `brain.ma_conv_tick` keeps Conversion. Remedy Arrow: face the downed pawn, then shift + the skill for 0.5 s. The aim-and-release routine stays behind `arisen_brain_ma_aim` (default off).
- Unverified: that the no-aim shots and skills fire and hit; that the no-aim Remedy Arrow picks the downed pawn. No aiming should also mean no reticle on the player's screen.

### v0.9.103 (2026-11-16): Magick Archer switches Conversion mode by the number of enemies (not tested in game yet)
- Decision on the proposed rule (single-target mode against one enemy or a large monster, wide mode against three or more): accepted..
- Found live (`dev/bridge/ma1.lua`): `Human.get_Job08ActionCtrl()` -> `app.Job08ActionController` with `get_ArrowType()` / `changeArrowType()`; `ChangeArrowTypeEnum` Multiple = 0, Multiplex = 1 (Enums_Internal.hpp); the Arisen read **1** at the time. (`Job08_WideLockOn` turned out to be a core-skill id, not the mode.)
- `brain.ma_conv`: between shots, at most every 8 s: count live enemies within 25 m; three or more and the target is not a large monster (id `ch25...`) -> multi-target, else single-target. If the mode differs he presses what the demo showed for Conversion (AttackL + SkillAdditional + GimmickSpecial1 + GliderAscent, 0.2 s, out of aim) and rests 1.8 s. Two presses that leave `ArrowType` unchanged stop it for 60 s. `arisen_brain_ma_convert = false` switches it off.
- **Confirmed 2026-11-16:** reported: the mode is now Rivet Shot (single target). while `ArrowType` read 1 (`dev/bridge/ma2.lua`). So Multiplex (1) = single-target (Rivet Shot), Multiple (0) = multi-target; the defaults are right.
- (Was an assumption:) Multiple (0) is the wide multi-target mode and Multiplex (1) the single-target one (`arisen_brain_ma_multi` / `arisen_brain_ma_single` swap them if it is the other way round).

### v0.9.102 (2026-11-16): Remedy Arrow only for a downed pawn (not tested in game yet)
- Game knowledge supplied by the tester: Remedy Arrow only revives pawns, so it should be used only when a pawn is down. The Magick Archer has two modes switched with Conversion: a small single-target area and a larger multi-target one; some skills use that area, others aim a projectile.
- Remedy Arrow is `Job08_LifeReturn` = 87 (Enums_Internal.hpp; action nodes `Job08_PrepareLifeReturn` / `ReadyLifeReturn` / `ShootLifeReturn`). It was already out of the rotation (`brain.NEVER`), so 0.9.101 never fired it; the two "started nothing" taps in the demo were the tester's.
- `brain.ma_remedy`: while a party pawn reads `get_IsDead` within 25 m and the skill is equipped: face him (`set_TargetFrontAngleDeg`), aim 0.6 s, tap the slot, hold until the node reads Ready + 1 s (4.5 s cap), release; 6 s before another try, 20 s if the skill did not start. Runs in a fight (ahead of the attack rotation; the lock-on is not handed to the enemy during it) and out of one.
- Conversion (the `Job08_ChangeArrow` action seen in the demo on AttackL + SkillAdditional): not used by the brain yet. He fights in whichever mode the player left him in. Enums has `Job08_WideLockOn = 30` among status values, a lead for reading the current mode.
- Unverified: that facing the pawn is enough for the arrow to reach him (no lock-on on an ally is set).

### v0.9.101 (2026-11-16): Magick Archer brain from the tester's demonstration; bigger test bench (not tested in game yet)
- Game knowledge supplied by the tester: each skill can be put in any of the fixed slots. (The mod works by slot; which skill sits in a slot is read from the character.) Also requested: more useful large-monster spawns in the test bench, with a hotkey..
- **Demo read** (`DPC_demo.json`, 0.9.99, job 8, 77 entries): basic attack = hold aim (flags AimHold + GimmickAction + JobSpecialAction + Shift1OnlySpecificJob + ShootRelease + ThrowRelease; `Job08_StartAim` on layer 1) and release (`Job08_ShootNormalArrow`), held 0.4 - 3 s. Skills while aiming: Skill1 -> `Job08_CS03.Job08_PrepareFrostTrace` (1.1 s) -> `ReadyFrostTrace` -> release -> `ShootFrostTrace`; Skill2 -> `Job08_CS02` `PrepareBurningLight` -> `ReadyBurningLight` -> `ShootBurningLight`. Skill flags came WITHOUT Shift1 / Shift2. Skill3 / Skill4 taps started nothing. AttackL + SkillAdditional out of aim = `Job08_ChangeArrow`.
- **`brain.ma_tick`** (Magick Archer only, in "engage"): rest -> aim 1.8 s (`arisen_brain_ma_lock`) -> release (shot) -> 0.9 s rest; with a skill due: aim 0.5 s -> SkillN (no shift) 0.15 s -> keep aiming until the layer-1 node reads Ready + 0.8 s (4 s cap) -> release -> 1.2 s rest. A skill that starts no `CustomSkill` node within 1 s is skipped for 120 s. The generic light-attack taps and shift + skill presses are off for him. `arisen_brain_ma = false` in the settings file restores the old rules.
- **Test bench:** enemy list + Griffin, Golem, Drake, Grim Ogre, Gore Chimera, Gore Minotaur, strong Goblin, Chopper, Asp, Rattler, Succubus (ids from EncounterDirector's charRef; appended, so saved selections keep their meaning). New presets: Cyclops, Cyclops dummy, Minotaur, Chimera, Griffin, Golem, Drake, Saurians x3, Asps x2, Ogre behind you. **Ctrl+F9** = the custom spawn (F9 = the selected preset, F10 = despawn as before).
- Unverified: all of it. Not known whether every new id has a prefab the spawner can load ("Test spawn: no prefab for ..." in the log if not).

### v0.9.100 (2026-11-16): skill buttons read from the game's own assignment (not tested in game yet)
- Reported: the screenshot shows the game's default layout. Requirement: read the game's bindings and follow them..
- Found (`dev/bridge/bind1.lua`, `bind2.lua`): `app.UserInputManager.getCurrentCharacterPadAssign()` -> `app.CharacterPadAssign`, `AssignList` of 62 `Info` (Action, Button mask, PreInput). Live values: Skill1 (7) = Square + L1, Skill2 (8) = Triangle + L1, Skill3 (9) = **R1** + L1, Skill4 (10) = **R2** + L1, Skill5 (27) = Triangle+Circle + L1, action 61 = Square+Cross + L1; orders Go / Come / Help / Wait = D-pad up / down / left / right; item shortcuts = L1 + D-pad; Dash = Triangle and L3; Grab = Square. (v0.9.0's `UserInput.getButton` was the wrong call.)
- `R.bind_read` (every 2 s) keeps slot -> button from that list. Used by: co-op (player 2's skill buttons and chord pairs), aimed skills on a possessed bow pawn (chord pairs; single slots only when the game has them on a face button, so R1 / R2 stay shots while aiming), and the skill list labels. The fixed tables remain as the fallback when the list cannot be read.
- Note: the list is the Arisen's. The game moves skills 3 / 4 from Circle / Cross to R1 / R2 when chord slots are in use, so the buttons can change with his skill loadout; the log line "Controller skill buttons changed" records it.
- Unverified in game: co-op slots 3 / 4 on R1 / R2 with a four-skill pawn; label text.

### v0.9.99 (2026-11-16): aimed-skill chords corrected to Square+Cross and Triangle+Circle (not tested in game yet)
- **Verified by result (0.9.98):** seemed to work. (hold D-pad left / right to select, L1 + left stick click to take control, hold down to return, orders eaten after a hold).
- The tester, with a screenshot of the Equipped Weapon Skills screen (Magick Archer: Square = Frostseeker Bolt, Triangle = Irradiant Orb, R2 = Remedy Arrow, R1 = none; Triangle+Circle = Remedy Arrow, Square+Cross = none): correction from the tester: for every vocation the two chorded slots (5 and 6) are Square+Cross and Triangle+Circle.
- Checked: co-op (`coop.pad_input`, 0.9.21) already uses Square+Cross = Skill6 and Triangle+Circle = Skill5, measured with TestGuide chord-flags-2. The aimed-skill path for possessed bow pawns (0.9.87) had Circle+Cross for Skill5. Now Triangle+Circle; Triangle also waits 0.09 s for its partner like the other three.
- Open: on the tester's layout the screenshot shows skills 3 and 4 on **R2 and R1**, not Circle and Cross. The aimed-skill path and co-op both put slots 3 / 4 on Circle / Cross.

### v0.9.98 (2026-11-16): controller select / switch reshaped around the game's own holds (not tested in game yet)
- Title Update 3.2 "expanded pawn commands": hold Go = Explore, hold To Me = High Five (each with an option). The 0.9.97 D-pad hold took both over.
- Reported on 0.9.97: after a hold on D-pad up took control, the pawn still got the Go order; the hold must swallow it. Wanted: hold left / right to change the selection, L1 + left stick click to take control, hold D-pad down to go back to the Arisen (still High Five when playing the Arisen).
- Now: hold left / right = select previous / next (always); hold down = back to the Arisen only while a pawn is played (as the Arisen it is left to the game); up is never the mod's. L1 + `LStickPush` = take control of the selection (`pad_l1_l3_possess`, default on). The L1 + right stick click from 0.9.97 is gone (Pawn Tactical Wheel keeps it).
- Order eaten after a hold: the game gives the order on release (its own hold timing), when the pad is no longer held, so the 0.9.97 check missed it. The hook now also skips while the hold has fired and for 0.4 s after the release.
- The mod's own reactions to orders while a pawn is played (Arisen Wait / Come, the caster's Help) follow the same rule: held back while an owned direction is held, applied on a tap's release, dropped after a hold.
- Unverified: all of it in game; whether L1 + left stick click also toggles the game's dash on the tester's layout (left stick click = Dash there).

### v0.9.97 (2026-11-16): a D-pad hold no longer gives the order; L1 + stick clicks as an option (not tested in game yet)
- Reported on 0.9.96: the orders must be swallowed: a tap gives the order, a hold does the mod's action. Also wanted: L1 + stick click as an option..
- Type read (`dev/bridge/ord1.lua`): `app.PawnOrderController` has `tryGetOrderInput()`, `tryGetOrderInputNew()`, `tryUpdatePawnOrder(PawnOrder) -> Boolean`, and its own `_InputOrderButtonTimer` / `_isButtonRelease` (the game's "expanded orders" option also times the button).
- `R.order_hook`: pre-hook on `tryUpdatePawnOrder`. While exactly one D-pad direction is held on the controller (read live from the merged pad, no shoulder button or trigger), a non-zero order is skipped (returns false) and kept. On release before `pad_hold_s` the tick calls `tryUpdatePawnOrder` with the kept order; if the hold fired the order is dropped. Keyboard orders and co-op are untouched. Counters `R.ord_skips`, `R.ord_replays`.
- `pad_l1_stick_select` (default **off**): L1 + `LStickPush` = select next, L1 + `RStickPush` = switch to the selection. Pawn Tactical Wheel uses L1 + R3 too.
- Unverified: that `tryUpdatePawnOrder` is the only path from the D-pad to an order; that calling it from the mod's tick on release works like the game's own call; how this interacts with the game's expanded-orders hold; the `RStickPush` name.

### v0.9.96 (2026-11-16): controller: hold the D-pad to select and switch (not tested in game yet)
- Question: is there a good controller combination for selecting a pawn and switching to it? L1+R1 is out (it is a skill chord). On the hold idea: try it, although it may set off the D-pad orders; L1+L3 and L1+R3 are other candidates (Pawn Tactical Wheel uses L1+R3).
- Hold one D-pad direction for `pad_hold_s` (0.5 s) with no shoulder button or trigger held: left / right = select previous / next (same list and marker as F7), up = switch to the selection (same as F6), down = back to the Arisen. `pad_hold_select`, default on; not in co-op. Switch in Features.
- The pawn order on that direction still goes out at the press: orders are not delayed or swallowed in this version. L1+L3 is the fallback combo if that is a nuisance.
- Unverified: the D-pad / shoulder bit names (`LUp`, `LDown`, `LLeft`, `LRight`, `LTrigTop`, `LTrigBottom`, `RTrigTop`, `RTrigBottom`) on the merged pad; while unpossessed, left / right changes the selected pawn and up possesses it.

### v0.9.95 (2026-11-16): the played pawn keeps the lock-on (not tested in game yet)
- Result on 0.9.94: seems fine now. (the guide; takeover recording of the main pawn: guide off, no decision, the pawn follows the stick from 0.5 s). Then reported: the possessed pawn may be targeting a friendly escort NPC; attacks do not go to the enemies near the pawn.
- Read live twice (`dev/bridge/tgt1.lua`, `tgt2.lua`, and the brain telemetry `pawn.lock_chara`): while possessing the main pawn, not co-op, brain in "approach" (no swap in that mode), the shared `LockOnController.Chara` was **ch100000_00, the Arisen**, with no target. It should be the pawn. So the pawn's attacks searched for targets around the Arisen (who was 20 m away, by the escort).
- Cause: the brain borrows the shared lock-on for the Arisen inside `app.Player.update` and gives it back after. Two holes: a second borrow before the give-back saved the Arisen as "the one to give back to"; and an error in `setTarget` after the swap left it un-restored. `lock_sets` was 696 in that session.
- Fixes: no save while a swap is open; the swap is marked before `setTarget`; the give-back goes to the played pawn whenever one is played (not co-op); and each frame outside the swap the mod checks the lock-on's character and gives it back to the pawn if it has left (`R.lock_fixes`, logged).
- Unverified: which of the two holes it was. If "Lock-on had left the played pawn" shows in the log, something else also moves it.

### v0.9.94 (2026-11-16): takeover recorder (dev only), no behaviour change
- Reported on 0.9.93: the pawn still guided. After a script reset, a Go order (which starts the guiding) and taking control of a hired pawn, the pawn kept walking while supposedly controlled.. Screenshot: the pawn's name plate reads "the Thief pawn" (the mod's English name for <non-Latin name>).
- Read live a few minutes later: the log shows "Guide: ... asked the game to end the guidance" at both possessions; `guide_stops` 2, `guide_forced` nil; the Concierge now `IsConcierge = false`, state `ConciergeStateSuspend`; no decision executing, no pack, order 0. So the request is accepted, but single reads cannot show how long the pawn keeps walking after it or what moves him. (`IsSkipThink` read false at bridge time and true right after setting it: it is a per-frame request the game consumes, not a latch.)
- `R.takeover_rec` (dev only): 15 s from each possession start, 10 Hz, to `data/DPC_takeover.json`: position and distance moved, the player's stick, action nodes, executing decision, guide on/off + whose + state, navigation state, order, requested pack, the interrupt counters.

### v0.9.93 (2026-11-16): a pawn that is guiding the party stops guiding when you take it over (not tested in game yet)
- Reported on 0.9.92: a freshly possessed pawn was stuck in some plan or animation, heading somewhere, and hard to break out of. Marked as the main thing to fix before release..
- Read live while it was happening (`dev/bridge/stuck1-4.lua`): the pawn (ch111017) was in `NormalLocomotion`, **no decision executing**, `IsSkipThink` and `IsRequestDisableNavi` both true, no ActInter pack requested. But `PawnManager.PawnConcierge` (`app.Concierge`) had `IsConcierge = true`, `_ConciergeCharacter` = **the possessed pawn**, quest 30170, 712 m to the destination, state `ConciergeStateContinue`, `_IsMovingInFrontOfPl = true`. He was the party's guide ("I know the way"). The log for that possession shows "decision ended" with no idle request. So the 0.9.38 / 0.9.88 decision interrupt cannot stop this: guiding is driven by the Concierge and `PawnNavigationController.updateConcierge`, not by a decision.
- `R.guide_stop`: at possession start and 4 times a second while a pawn is played, if the concierge is active and its character is the played pawn: `Concierge.requestEndGuidancePawn()`; if still guiding 1.5 s later, `Concierge.endNavigation()`. Counters `R.guide_stops`, `R.guide_forced`. Under `possess_interrupt_ai`.
- Unverified: that `requestEndGuidancePawn` ends it promptly and that the game does not restart the guidance at once (then the log line repeats every 1.5 s). Guiding by a pawn that is not being played is left alone.

### v0.9.92 (2026-11-16): the pawn being played follows the Arisen's lantern (not tested in game yet)
- Reported on 0.9.91: the lantern toggle during possession switches every lantern except the played pawn's..
- Read live (not possessing at the time): Arisen on, one pawn on, the pawn that had been played **off**. `HumanLanternController.isTurnOnCondition()` read **false on lit lanterns**, so it is the game's automatic darkness test, not "can light". That is why the 0.9.79 pawn toggle refused. The type also has `hasEnableLantern()` and `isEnableTurnOn()`; pawns follow through `PawnManager.useLantern(app.Character)` / `Pawn.usedLantern`, which is AI-side.
- `R.lantern_sync`, once a second while a pawn is played (`pawn_quick_lantern`): if the pawn's `IsLanternOn` differs from the Arisen's, `turnOn/OffByOwnerAction`, then `turn(Boolean)` if unchanged. Lighting needs `hasEnableLantern() and isEnableTurnOn()`. Also covers switching pawns and the Arisen lighting up on his own.
- The Arisen's toggle now lights on `isTurnOnCondition() or (hasEnableLantern() and isEnableTurnOn())`.
- Unverified: what `isEnableTurnOn` tests exactly; whether the game's update switches the pawn's lantern back (then it would blink once a second: `R.lantern_syncs` would climb).

### v0.9.91 (2026-11-16): the hard-hit red flash is stopped at its source (not tested in game yet)
- Reported on 0.9.90: a big red hurt flash crossed the screen while an Archer pawn was played, although it was most likely the Arisen who was hit..
- Read live: the 0.9.75 hooks are installed; `isDangerHp` was redirected 4365 times (the edge part works) but the `ui022401.reqCritical` pre-hook had **0** skips. `app.GuiManager` has `requestCriticalEffect()`, which is what asks for the flash. Now pre-hooked and skipped under the same condition (possessing, not co-op, `possess_danger_pawn`).
- Unverified. If the flash still shows, `R.danger_skips` tells whether the request came this way.

### v0.9.90 (2026-11-16): selection (F7), go to selection (F6), numpad orders the selection (not tested in game yet)
- Design note: while possessing, the number pad orders the Arisen by default. Wanted: one key to select a pawn or the Arisen, with an in-game highlight, and another to switch to the selection from wherever you are.
- **F7** while playing a pawn no longer switches at once: it walks a selection through the Arisen and the other pawns, with a yellow wedge and the name over the pick for 3 s and "Selection: <name>" in the status banner. The selection starts on the Arisen each time a pawn is taken. Not possessing, F7 selects among the pawns as before (now with the marker). In co-op F7 still switches player 2's pawn at once. `cycle_switches_now` (legacy bin) brings the old behaviour back.
- **F6** goes to the selection: another pawn -> switch to him; the Arisen (the default) -> release, as before.
- **Numpad 1 - 6** order the selection: not possessing -> the selected pawn (unchanged); possessing -> the Arisen by default (`brain.order_*`: the brain sends that slot's skill press for 0.5 s over whatever it was doing; needs his brain running), or the pawn picked with F7 (`quick_skill(slot, idx)`). They no longer fire the possessed pawn's own skills (the number row still does when it is set to skills).
- Unverified: all of it. Known gap: an Arisen order while his brain is off (unsupported vocation, brain disabled) does nothing but log.

### v0.9.89 (2026-11-16): numpad keys are not aimed-skill keys
- Clarified on 0.9.88: number-pad skills are orders for a character that is NOT being played, so they are never the aimed versions. The keyboard path of 0.9.88 (numpad / number keys while aiming) is removed; the controller part (L2 + face, chords) stays.
- Open, asked of the tester: which keys fire aimed skills on keyboard and mouse; and what the numpad should do while a pawn is possessed (today, since v0.7, numpad 1 - 6 drive the possessed pawn's own skills, and "quick skills" for the selected pawn only run while nobody is possessed).

### v0.9.88 (2026-11-16): aimed chords and keyboard aimed skills; a possessed pawn no longer runs off on an order (not tested in game yet)
- Reported on 0.9.87: slots 5 and 6 are chords (Square+Cross and Circle+Cross); the tester plays on mouse and keyboard; the possessed Archer pawn is still running around from an earlier order..
- **Aimed skills, controller:** with a skill in slot 5 or 6, L2 + Square + Cross fires the `Skill6` flag and L2 + Circle + Cross the `Skill5` flag (Square + Cross is `Skill6` in the L1 layout too; which of the two what was meant as "5" is an assumption). A lone chord button (Square, Circle, Cross) waits 0.09 s for its partner; a shorter tap fires its single skill on release (0.1 s pulse); Triangle never waits.
- **Aimed skills, keyboard:** while the aim button is held (`AimHold` in the player's flags) the number / numpad keys 1 - 6 send SkillN with the shift flags removed.
- **Pawn running off:** the AI interrupt (`forceEndDecision`) ran only when possession starts. Pawn orders given while possessing reach the possessed pawn too and start a new decision. `R.ai_watch` now checks four times a second and ends any decision found executing on the possessed pawn (logged at most every 5 s; dev counter `R.ai_ends`). The interrupt code moved into `R.interrupt_ai`.
- Unverified: all three.

### v0.9.87 (2026-11-16): aimed skills for bow pawns on a controller (not tested in game yet)
- Reported on 0.9.86: aiming works now. Skills must also fire with the left trigger held for the bow vocations (the aimed versions). Stamina regenerates with the Thief's cloak skill off.
  - **Aim fix confirmed** (the `evaluate` hook with the DrawBow setting) with a Thief Arisen.
  - **Stamina cause confirmed:** it was 48 `Job04_Stealth` (the reported "shadow cloak"); switching it off brought regeneration back.
- Aimed skills: the flags a possessed pawn receives are the ones the game builds for the Arisen's layout, and only a bow-vocation Arisen gets Skill flags from L2 + face. `pawn_aim_skills` (default on; normal possession, native controls, pawn job 2 or 8): while L2 is held on the pad, Square / Triangle / Circle / Cross add `Skill1` - `Skill4` (no shift flags, as the game does and as co-op already did) with trigger and release edges, and that button's own action flags (from the co-op pad map, incl. the measured Square / Triangle ones) are removed. Dev status: `aim.aim_skills`.
- Unverified: that the face-to-slot order while aiming is 1 - 4 as with L1; the six-skill layout while aiming; keyboard and mouse (number keys still send SkillN with the shift flags).

### v0.9.86 (2026-11-16): the right aim setting for the pawn; the brain stops switching on stamina-draining Thief toggles (not tested in game yet)
- Reported on 0.9.85: the Arisen, back under the player's control, is stuck not regaining stamina; the Archer aim zoom did not work at all..
- **Stamina.** Read live while it was happening: stamina 507 / 1429 and falling (`StaminaAddValue` -0.0635), `IsDash` false (so the 0.9.81 sprint theory was wrong), `HumanStaminaController.DisableRecoverStamina` = 32 = `Consume` (`DisableRecoverStaminaType`: Fsm 1, Sequence 2, RunOut 4, Damage 8, Down 16, Consume 32, SpellStock 64, AfterDash 128, External 256). Something was consuming stamina every frame. His skills are 38 / 40 / 39 / 101 / 44 `Job04_FlameBlade` / 48 `Job04_Stealth`: slots 5 and 6 are toggles that drain stamina while on, and the brain has pressed slots 5 / 6 since 0.9.55 without ever switching them off. `brain.NEVER` gains 42 (AbsoluteAvoidance), 44, 48. Which of the two was on was not identified. The 0.9.81 sprint clear stays (harmless).
- **Aim.** Dev status on 0.9.85: `setting` "fallback 6", `setups` 101 (the controller's `_AimSetting` was nil again every time, so something resets it), and the 22 settings read live: all conditions are `app.gc.pl.*` (player conditions, never true for a pawn); 0 / 1 carry-throw, 4 `Job02FullBend`, 5 `Job02BodyBinder`, 6 / 7 `Job02MeteorShot` (15 and 7 deg/s, FOV 15 and 5), 8 `Job02RandomShot`, 9 `Job02FullBlast`, 10 `Job02HeavyRain`, **11 `DrawBow`** (100 / 90 deg/s, gyro, asset FOV 60 with narrowing 0.8), 12 spell prep, 16 - 20 Magick Archer bows. 0.9.85's fallback had picked the sniper view.
- Now: the setting is chosen from the pawn's own action node (DrawBow by default, the skill ones by name), and a post-hook on `AimCameraSetting.evaluate` returns it while the pawn aims (the controller asks `evaluate(player)` and got nil). `setupAim` is still called when the choice changes. Dev status: `aim.setting` "index N", `aim.evals` = how often the hook answered.
- Unverified: that the controller calls `evaluate` while the camera is on type 7 for a pawn (if `evals` stays 0 the hook is not on the path).

### v0.9.85 (2026-11-16): Archer pawn aim works whatever the Arisen's vocation (not tested in game yet)
- Result on 0.9.84 (the judgments were accepted for the settings sort). Also reported: a regression in Archer possession aim: the reticle shows, but neither mouse, gyro nor right stick aims, and there is no zoom.
- Not a code regression. Dev status: aim requests and blocks as before (`reqs` 12, `blocked` 1410), 0 errors. The Arisen is now a Thief; on 2026-11-15, when the aim was verified, he was an Archer.
- Read live: `app.AimCameraController` has `_AimCameraSetting` (asset, 22 `AimSetting`s, each with `_Enabled`, `_Fov`, `_YawRotSpeed`, `_PitchRotSpeed`, mouse rates, `_GyroOperation`, a `_Condition`), `_AimSetting` / `_CurrentAimSetting`, and `setupAim(AimSetting)`; `AimCameraSetting.evaluate(via.GameObject)` picks the setting for a character. At rest `_AimSetting` was **nil** and `evaluate` returned nil for everyone. So the controller only has rotation, zoom and gyro once the player himself has aimed in the session; an Archer Arisen had, a Thief Arisen never does.
- `R.aim_setup` (10 Hz while the pawn aims): `evaluate(pawn GameObject)`; if that gives nothing and the controller has none, the first enabled, non-throwing setting with a FOV; then `setupAim`. Dev status gains `aim.setting` ("pawn" / "fallback N" / "already set" / "none found") and `aim.setups`.
- Unverified: that `evaluate` accepts a pawn mid-aim; that `setupAim` alone is enough (the controller may re-evaluate against the player each frame); that the fallback setting is a sensible bow one.

### v0.9.84 (2026-11-16): settings sorted by how likely a player is to change them (not looked at in game yet)
- Requested: sort the options so the things a player might actually change are clearly on top. Looting, waking and reviving are real features; a player may switch them off, but they are not common choices..
- Top of the window, unfolded, 13 choices under four coloured headings: the Arisen (fights on his own, follows, cannot die, his bars + overhead), couch co-op (player 2's bars, skill list, button names), screen (status banner, 16:9 overlays), cheats (heal key + Arisen).
- Folded: "Positions and sizes" (all the sliders and the reset button); "Features (all on by default; switch one off if it gets in your way)" with the pawn's interact / wake / revive / quick items / lantern / red edge / skill display, the brain's per-vocation and healer switches, the two co-op behaviours, the Archer aim trio.
- The "advanced, test and legacy" bin behind its checkbox is unchanged.

#### 2026-11-16, decision: co-op where each player picks any character waits until after release
- Question: in co-op, could the keyboard-and-mouse player also choose any pawn or the Arisen? Offered: a swap (player 1 on a pawn, the controller on the Arisen; one possession) or the full version (two possessions at once, the Arisen on his brain; a restructuring of the single-pawn core). Decision: the full version of that waits until after release.. Recorded in `claude/dpc-release-plan.md` under "After release".

#### 2026-11-16: the tester's saved settings brought back to defaults (to get close to a new player's experience)
- Backups first, in the game's `reframework/data`: `DirectPawnControl.backup-2026-11-16.json`, `camera_distance_config.backup-2026-11-16.json`.
- DirectPawnControl: of 156 defaults only three saved values differed: `arisen_brain_cast_gap` 2.5 -> 4.0 (a stale older default: `save_cfg` writes every key, so a changed default never reaches an existing config), `arisen_auto_follow` true -> false, `coop_map_source` "auto" -> "builtin". Set through `DPC_cmd.json` (`set` + save), so the running script and the file agree. `pawn_aim_point_dist` 25 is what a fresh install's migrations give; left.
- CameraDistance: `coop_aim_zoom_limit` true -> false, `coop_max_extra` 1.47 -> 10, `coop_max_shift` 0 -> 12, `joint_restore` false -> true, `rts_distance` 10 -> 8, `rts_extra_distance` 12 -> 8, `rts_forward_lead` 2.5 -> 1.5, `rts_height_y` 1.5 -> 0.5, `rts_pitch_deg` 38 -> 32, `custom_presets` -> empty. Written to the file; the running script picks it up at the next script reset.
- Still not a player's setup: `DPC_dev.json` is present (developer tools, telemetry, recorder on).

### v0.9.83 (2026-11-16): revive hold matches the game (3.8 s)
- Game knowledge supplied by the tester: the default pawn revive takes 3.8 s, about 4 s with animation delays. `pawn_revive_hold` default 2.0 -> 3.8; a saved 2.0 is migrated once; the slider goes to 6 s and names the game's value.

### v0.9.82 (2026-11-16): settings window regrouped; advanced / test / legacy options in a hidden bin (not looked at in game yet)
- Requested: a full pass over the settings to make the menus clean; debug and note items that are no longer real options go away; obsolete options are separated from the ones someone may care about and hidden by default.
- The flat list of about 45 switches became six groups, one plain line per option: **Playing a pawn**, **The Arisen while you play a pawn**, **Couch co-op**, **Archer pawn aiming**, **Display**, **Cheats**. The first two open by default. New in the window: wake, revive (+ hold seconds), lantern, the caster's heal / top-up / cure switches.
- One checkbox, "Show advanced, test and legacy options" (`show_legacy`, default off), reveals the other bin: "Advanced and legacy switches" (native controls, AI interrupt, line-of-sight rule, ray cast and aim distance, old skill palette, Interact-brings-Arisen, head-anchored stamina bar and its sliders), Test bench, Pawn action buttons, "Brain, co-op and control tuning" (was "Tuning & experimental"), Diagnostics & log. Nothing was deleted; no setting changed value.
- Removed from the window: the stale session note line; the duplicate vocation checkboxes in the tuning node; the Test bench no longer opens by itself.

### v0.9.81 (2026-11-16): release clears the Arisen's sprint state (not tested in game yet)
- Reported: the Arisen was drenched and his stamina would not regenerate after control went back to him, until it ran out completely and a pawn touched him; he stayed drenched but regained stamina..
- Not reproduced. Read live afterwards: `StaminaManager` has no "regeneration off" switch of its own (`IsEnableConsume` true, amounts normal); `app.Human` has `IsDash` / `IsPrevDash` and `requestDisableRecoverStaminaFromFsm/External`. Working theory: sprint is a toggle and the brain presses it when its target is far; released mid-sprint, the Arisen kept `IsDash`, which holds stamina recovery off until exhaustion ends the sprint. Drenched would then be a coincidence.
- `release_possession` now clears `IsDash` / `IsPrevDash` on the Arisen when set and logs "Release: cleared the Arisen's sprint state". If the bug returns without that log line the theory is wrong.

### v0.9.80 (2026-11-16): lantern back to the Arisen, Arisen death protection, heal key covers the Arisen, Xbox / PlayStation button names (not tested in game yet)
- Reported and requested: the lantern should stay the Arisen's, since all pawns follow his (the played pawn's own lantern did not light). Show the right button names for an Xbox or a PlayStation controller on the co-op skill list. Numpad . should heal the Arisen too, as an optional cheat. An option that protects the Arisen from death, or lets him be revived like a pawn, while a pawn is played. / then a settings pass.
- **Lantern:** the shortcut (co-op: player 2's D-pad right) now toggles the Arisen's `Human.LanternCtrl` (`turnOn/OffByOwnerAction`, then `turn(Boolean)` if the state did not change). The 0.9.79 pawn-lantern version did not light.
- **Death protection** (`arisen_no_death`, default on): while a pawn is possessed and not in co-op, `HitController.set_IsNoDie(true)` on the Arisen, re-applied every second, cleared on release / co-op / script reset. Chosen over "revive him like a pawn" because the Arisen's death runs the game's own game-over flow. Not known: how the game shows him at his last health, and whether brine / falls ignore the flag.
- **Heal key:** Numpad . also does `recoverAll` + stamina on the Arisen (`party_heal_arisen`); the whole key can be switched off (`party_heal_key`).
- **Button names:** `via.hid.GamePad.get_LastInputDevice().get_DeviceKindDetails()` (5 / 6 / 8 / 9 = DualShock 4 / DualSense -> PlayStation names; 11 - 23 = Xbox, XInput, Steam, Switch -> X / Y / B / A, LB / RB / LT / RT), checked once a second; `coop_pad_names` 1 auto, 2 PlayStation, 3 Xbox. Only the merged device was read while building this (kind 2), so what a real pad reports here is unverified; with Steam Input a DualSense may report as XInput.
- Next, asked for by the tester: a pass over the settings window (cleaner menus, debug and stale notes removed or hidden).

### v0.9.79 (2026-11-16): lantern shortcut for the pawn; quick items from the pawn's own bag first (not tested in game yet)
- Reported on 0.9.78: up used a health item and down a stamina item, and both applied, but the items seemed to come from the Arisen's pack.. So the health item works too (the 0.9.77 refusal was the pawn's state), and the co-op / normal layout is right. Also wanted: left and right work the possessed pawn's own lantern; the items shortcut already opens the items menu, which is enough.
- Item source order swapped: `useItem(id, pawn, pawn)` first, `useItem(id, arisen, pawn)` only if that is refused. The item is still the one the game's picker offers, which it chooses from the Arisen's stock, so a pawn who carries none of it still draws on the Arisen.
- Lantern: the `Lantern` action in the player's flags (co-op: player 2's D-pad right) toggles the possessed pawn's own lantern through `Human.get_LanternCtrl()`: `get_IsLanternOn` -> `turnOffByOwnerAction`, else `isTurnOnCondition` -> `turnOnByOwnerAction`. `pawn_quick_lantern`, default on. Left (items menu) is left to the game.
- Unverified: that `HumanLanternController` carries those `app.LanternController` methods, and that a pawn with no lantern equipped just reports "cannot light one now".

#### 2026-11-16, confirmed in play, quick items (0.9.77): the stamina item goes to the pawn.
- Quick-use stamina item on the possessed pawn: confirmed. Note from the tester: he runs another mod that makes some items not cost a use, so a count that does not drop on his PC is not a DPC fault.
- Still open: the health item was refused once (pawn's health at the time unknown); co-op D-pad up / down (0.9.78) not tried yet.

### v0.9.78 (2026-11-16): co-op quick items follow the game's layout (not tested in game yet)
- 0.9.77 in normal possession, from the log: "Quick item (stamina): item 52 on <non-Latin name> -> true (the Arisen's bag)", then item 502 -> true, then "Quick item (hp): item 500 on <non-Latin name> -> false (his own bag)". So the flags are raised in the player's input, the picker's Nullable is read correctly, and `useItem(id, arisen, pawn)` is accepted for stamina items. The health item was refused both ways (not known why; the pawn may have been at full health).
- The tester's screenshot of the game's shortcut cross: up = Salubrious Draught x4 (health), down = Mighty Roborant x3 (stamina), left = Go to Items Menu, right = Lantern On. 0.9.77 had co-op down = health, up = stamina: swapped to match.
- Not confirmed by eye: that the stamina items landed on the pawn and not the Arisen.

### v0.9.77 (2026-11-16): quick-use recovery items for the pawn being played (not tested in game yet)
- Reported (co-op, 0.9.75): the quick-use menu does not work for the played pawn; an item showed on the down arrow but did not fire for the pawn.
- Read live: `GuiManager.CrossGuide` (`app.ui020401`) has `OrderActs` = [18, 17, 19, 20] (Go, Come, Help, Wait) and `ShortcutActs` = [39, 40, 43, 38] (RecoverHpItem, RecoverStaminaItem, ItemMenu, Lantern), `PlChara` = the Arisen, `ShortcutParam` = `app.ItemShortcutParameter` with `getRecoverHPItemID(Boolean, ItemShortcutSettingType)` / `getRecoverStaminaItemID(...)` -> `Nullable<ItemIDEnum>`, `SecInterval` 0.5. So the shortcut is a CharacterInput action read from the Arisen and applied to the Arisen.
- `R.item_tick` (`pawn_quick_item`, default on): in normal possession the RecoverHpItem / RecoverStaminaItem trigger in the player's own flags; in co-op player 2's D-pad down (health) / up (stamina). It asks the game's picker for the item id and calls `ItemManager.useItem(id, arisen, pawn)`, and if that returns false `useItem(id, pawn, pawn)`. Logs "Quick item (...)".
- Unverified, any of which can make it do nothing: that those two flags exist in `ACTION_FLAGS` and are raised in the player's flags; the order / meaning of `useItem`'s two characters; reading the Nullable result; the Boolean of `getRecoverHPItemID` (false used); which D-pad direction the game uses for which item.

#### 2026-11-16, confirmed in play on 0.9.76: L1 skills work in co-op again.

### v0.9.76 (2026-11-16): co-op L1 skills no longer lost on a quick tap (not tested in game yet)
- Co-op soak on 0.9.75 with player 2 on the Thief pawn (skills 43 / 39 / 42 / 40), reported: L1 skills do not work for a Thief on the controller in co-op..
- 30 s read-only recording through the bridge (`dev/bridge/l1a.lua`, `l1b.lua`: DPC's flags for player 2, the pawn's input, his nodes). L1 alone = 0xC000 (Shift1 + Shift2) as expected, L1 + R1 = 0xC002. But no Skill flag ever appeared: L1 held then a Square tap went 0xC000 -> 0x801000020 (Grab + SkillAdditional + Present, Square's own flags) with no Shift, and the pawn did `Locomotion.TryCatch` / a pin-down instead of a skill.
- Cause: `coop_chord_window` (saved at 0.16 s) holds a face button back while it waits for a chord partner, on every vocation and layout. A tap shorter than that never reached the skill; if L1 came up a frame before the face button, the button then counted as its own action (grab). Slower presses worked, which is why this passed with the Fighter.
- Fix in `coop.pad_input`: the hold-back and the chords only run when a chord is possible (a skill in slot 5 or 6); a button released during the hold-back fires its skill as a 0.1 s pulse with the shift flags; a face button that went down under L1 is ignored (not grab / jump / sheathe) once L1 is released, until it comes up.
- Also learnt: slot 1 of this pawn is 43 (Draw and Quarter), which does nothing unless he is clinging or pinning, so L1 + Square looks dead on this pawn even when the input is right.
- Open (parked): the game's item shortcut on the D-pad does not work for the possessed pawn / player 2. Found so far: `GuiManager.CrossGuide` = `app.ui020401` with `ShortcutActs`, `ShortcutInputs`, `ShortcutParam` (`app.ItemShortcutParameter`), `PlChara` / `PlHuman`, `isItemDisable()`; `ItemManager.useItem(Int32, app.Character, app.Character)`.

#### Thief soak, normal possession: passed. 2026-11-16 on 0.9.73; confirmed in play: more fighting done, all good.
- About 13 minutes with the Thief pawn (<non-Latin name>) on native controls (`Job04InputProcessor`), Thief Arisen alongside: most attacks and movement skills, grab + climb + Draw and Quarter, pawn switches (Thief -> Fighter -> Archer -> Thief), fights incl. `ch251000_00`. Status file: 0 errors. No crash.
- [time] "Releasing possession (arisen died)", re-possessed 07:55:54: the Arisen dying mid-possession is handled (released cleanly, session carried on).
- Thief Arisen brain in the same session: 18 skill uses across all six slots, 47 attack presses, 0 errors; several short "stuck while approach" runs near the large enemy and one "blocked 2.4 m from ch251000_00 -> attacking from here" (the big-body contact rule firing for the first time).
- **Not covered:** co-op with the Thief (no co-op start in this session's log). 0.9.74 / 0.9.75 were deployed during the soak and are not loaded yet.

### v0.9.75 (2026-11-16): red low-health screen edge follows the possessed pawn (not tested in game yet)
- Thief soak, confirmed in play: climbing and Draw and Quarter done with a possessed Thief. (Grab, climb and Draw and Quarter work under possession.) Also reported: a red edge and a red flash on screen from the Arisen being hit hard while a pawn was possessed; suggestion: flash on the Arisen himself, or ignore it.
- Found live: `GuiManager.ScreenEffect` is `app.ui022401` with `isDangerHp()`, `reqCritical()`, `PlayerHpRate` (0.171 at that moment: the Arisen really was at 17 %), danger sound ids; `GuiManager.getDangerHpRate()` = 0.25.
- `possess_danger_pawn` (default on), normal possession only: post-hook on `isDangerHp` answers for the possessed pawn (below 25 % of his reduced max), pre-hook on `reqCritical` skips the hard-hit flash. Hooks are installed on first possession. The Arisen's overhead health bar turns red and pulses below 25 %.
- Not known: whether the edge effect is driven by `isDangerHp()` alone or also by `PlayerHpRate` directly (then the edge would stay); whether the heartbeat sound follows.

### v0.9.74 (2026-11-16): automatic Thief fallback removed (not tested in game yet)
- The tester asked how the fallback kicks in; reading the code showed it counted every session that ended mid-possession on a Thief (crash **or** an ordinary quit), never reset the count, and at two silently moved Thief pawns to the puppeteer. Decision: the fallback controls may never be needed; fix the crashes instead. None for a long time, apart from the one at the vocation counter that has since been fixed..
- The session sentinel now only logs "Last session ended while possessing ...". No counter, no automatic switch, no note in the window. A one-time migration sets `native_skip_thief` back to false and drops `thief_unclean`. The manual checkbox ("Thief pawns use the puppeteer instead of native controls") stays.
- Thief soak so far on 0.9.73 (native controls confirmed in `DPC_session.json`): one combat, "Got through most attacks and movement", 0 errors.

### v0.9.73 (2026-11-16): the brain skips Gut and Run / Draw and Quarter (not tested in game yet)
- Thief soak in progress (Thief Arisen + possessed Thief pawn, 0.9.72), confirmed in play: many Thief skills used under possession. Draw and Quarter did nothing for him: it needs the Thief to be clinging to a large enemy or pinning a downed small one. Not a mod fault.
- Decision: he skips it unless there is a simple way to make him climb large monsters.. There is no simple way (grab, climb to a weak spot, then the skill), so 43 `Job04_HollowOut` joins `brain.NEVER`.
- Seen by reported in the same session: the Thief Arisen was aggressive, chased saurians, fell off a bridge into the brine, was brought back, and possession held throughout.. Possession survives the Arisen being taken by the brine.

#### Trickster Arisen on 0.9.72, 2026-11-16 (user: "how did that go? He casted some stuff"), 3 x ch220001_10, 36 s
- **Fix holds:** one "summon the simulacrum" at 433.8, one "simulacrum out", no "taken back" for the rest of the fight.
- With the simulacrum known to be out the routine ran for the first time: 5 x `Job09_ShortSmokeAttack`, 2 x `Job09_PrepareThrowSmoke -> Job09_ThrowSmoke` (445.4 and 462.4), skills alternating `CastAttentionFregrance` / `CastSmokeWall` (5 uses). 0 errors.
- He was hit once right after summoning (`DmgShrinkM`); one "stuck while backoff", one "no damage for 6 s -> reposition" (expected: a Trickster deals no damage, so that rule fires for nothing; harmless).

### v0.9.72 (2026-11-16): Trickster no longer toggles his simulacrum away (not tested in game yet)
- 0.9.71, Trickster Arisen vs 3 x `ch220001_10`, confirmed in play: the Trickster Arisen's simulacrum comes out well.. Telemetry agrees it came out, and both skills cast (`Job09_CS04.Job09_CastAttentionFregrance`, `Job09_CS01.Job09_CastSmokeWall`), 0 errors. But in 22 s he summoned at 224.0, **took it back at 231.7**, summoned 235.0, took it back 239.5, summoned 242.0 and 246.1; and only one censer swing, no smoke throw.
- Cause: `brain.decoy = {}` sat in the block that re-reads his skills every 2 s (events at x.5 s cadence re-logging "simulacrum out"), so "out" was forgotten every 2 s and the toggle pressed again. The swings and throws only run while it is known to be out, hence almost none.
- Fix: the state is cleared only when his vocation changes. (A simulacrum the player summoned before possessing was already picked up correctly: "simulacrum out" at 161.7.)
- Also in this log: 10 s of "no line of sight -> flank" with slides, falls and a low-wall climb on rough ground; he recovered by himself.

#### 2026-11-15, result for the moved skill list (0.9.71): fine.

### v0.9.71 (2026-11-15): player 2's skill list moved beside their bars (not tested in game yet)
- 0.9.70 seen working in the tester's screenshots (Archer: one skill + L2; Fighter: six skills with the L1+R1 / L1+R2 / chord labels) but it sat on the game's own button hints at the lower right. Requested: move it left, into the empty space right of the co-op health bar..
- Now anchored by its bottom-left corner at 0.60 / 0.93 of the HUD area (`coop_palette_left`, `coop_palette_bottom`; the bars end at 0.58 and sit at 0.90), so a longer list grows upward. New key names so a saved 0.80 does not carry over.

### v0.9.70 (2026-11-15): skill list for player 2 in co-op (not tested in game yet)
- Requested: bring back the mod's own drawn skill list to show the co-op player their skills.. The palette was switched off by default in 0.9.27 because the native HUD shows the possessed pawn's skills; in co-op the native HUD is the Arisen's, so player 2 had nothing.
- `coop_skill_palette` (default on): in co-op the palette is drawn again, titled "Player 2: <name> (<vocation>)", equipped skills only, controller buttons only ("[L1+Square]", with the six-skill layout's L1+R1 / L1+R2 and chords when slot 5 or 6 is filled), the active skill highlighted, plus the L2 vocation action. Position `coop_palette_x / y` (0.80 / 0.80 of the HUD area) with sliders. Outside co-op nothing changes ("Skill palette (debug)" still off by default).

#### 2026-11-15, confirmed in play: the Arisen's overhead bars work well; the vocation counter no longer crashes.
- 0.9.57 Arisen health + stamina over his head: confirmed.
- 0.9.58 crash fix (possessed pawn at the vocation guild counter): confirmed, no crash.

#### 2026-11-15, confirmed in play, hold-to-revive (0.9.69): works well for now.

### v0.9.69 (2026-11-15): revive is a hold with a filling ring (not tested in game yet)
- Question: can reviving work the way it does for the Arisen, with a circle filling up?.
- Revive now needs Interact held for `pawn_revive_hold` (2 s; 0 = single press as in 0.9.68). Progress restarts when the button is released or the target changes. Prompt reads "[Interact] Hold: Revive <name>".
- Ring: 48 `draw.filled_quad` segments left of the prompt (radius 16 - 24 px at 2160p), dim when empty, filling white clockwise from the top. Drawn in the frame callback from `R.rev_prog`, which the game-thread tick sets.
- Not checked: that `draw.filled_quad` takes the eight coordinates in this order on this REFramework build (wrapped in pcall: if not, the ring is missing but the hold still works); the real revive's hold time (2 s is a guess).

### v0.9.68 (2026-11-15): possessed pawn revives a downed party pawn (not tested through the prompt yet)
- Reported: trying to revive a downed pawn with a possessed pawn.. The 0.9.58 interact whitelist skips party members, and the game's own revive interact (`app.Human.ReviveInteractCtrl`, `HumanReviveInteractController`, checks `IsPlayerInteractToPawnInValidDistance`) is for the player.
- Probed live on the downed pawn (`ch111011`, `get_IsDead` = true, hp 0, node `Damage.Damage_Root.DieCollapse`): `app.Pawn` is not a component; `PawnManager.getPartyPawn(app.Character, false)` returns it. `setPawnRevive(0.5, false, false)` -> `get_IsDead` false, hp **0.5** (the Single is health points, not a share). Then `Hit.setHpValue(max * 0.5, false)` -> hp 672.65 of 1345.3. Both calls ran without error; the game was unfocused, so whether he stands up with his normal animation was not seen.
- Prompt "[Interact] Revive <name>" next to a downed party pawn (same range and code path as Wake); the press asks for 50 % of his current maximum (`pawn_revive_health`), `pawn_revive` default on. The Arisen is excluded (his death is the game's own flow). The meaning of the two Booleans is unknown (false, false used).

### v0.9.67 (2026-11-15): Trickster brain built from the tester's demonstration (not tested in game yet)
- Demo recorder (0.9.66) worked first time: 162 lines of the tester playing the Trickster (went through every Trickster attack). Input -> action:
  - `AttackL` tap -> `Job09.Job09_Normal.Job09_SummonDecoy`; `AttackL` again -> `Job09.NormalAttack.Job09_UnsummonUpperBody` (layer 1). A toggle.
  - `AttackS` tap -> `Job09_ShortSmokeAttack` (standing) / `Job09_MoveSmokeAttack` (moving).
  - `AttackS` held about 1.1 s -> `Job09_PrepareMoveThrowSmoke`, on release -> `Job09_ThrowSmoke`.
  - `Skill4` + shift -> `Job09.Job09_Skill.Job09_CS01.Job09_CastSmokeWall` (instant).
- Brain: when no simulacrum is known to be out, tap `AttackL` (retry after 2.5 s); with it out, a smoke throw (hold 1.3 s) every 6 s and censer swings in between; skills in rotation; 3 - 9 m band. Simulacrum state is tracked from his own summon / unsummon actions; `app.DecoyHandler` (via `Job09ActionController.get_DecoyHandler`) has no obvious "exists" flag (`get_Hidden` was false with it out; not compared against "not summoned").
- Not known: what happens when the simulacrum is destroyed by enemies (he would not notice for up to 60 s, then tap once).

### v0.9.66 (2026-11-15): dev demonstration recorder (not tested in game yet)
- The tester's vocation list: Fighter, Archer, Mage, Thief, Warrior, Sorcerer, Mystic Spearhand, Trickster. Magick Archer and Warfarer are not unlocked, so those two brains cannot be tested yet. Trickster is Arisen-only (no pawn to copy); he fought one fight as the Trickster to demonstrate.
- That fight was not captured: telemetry says version 0.9.64 (scripts not reset after 0.9.65), brain "off" for job 9, node log empty. His Trickster has one weapon skill equipped: 95 `Job09_AttentionFregrance`.
- New, dev only: while nothing is possessed, `R.demo_tick` logs every change of the Arisen's action nodes (both layers) with the names of the buttons held, 20 Hz, last 400 lines, to `data/DPC_demo.json`. One minute of the player using a vocation gives the input -> action map.
- **Verified on 0.9.64 from the same telemetry (Mage Arisen, earlier fights):** heals in battle for the Sorcerer pawn at 24 %, the Archer pawn at 40 %, the main pawn at 60 %; **the Help order is recognised** ("Help order -> heal the possessed pawn", then "help for the main pawn at 60 % health (Anodyne)", twice, out of battle); buffs first (29 then 28), Firestorm between. Top-up and cure not seen yet.

### v0.9.65 (2026-11-15): brains for Magick Archer, Trickster and Warfarer (not tested in game yet)
- Result (good Mage behaviour for now). Requested: brains for the remaining Arisen vocations.
- `arisen_brain_hybrid` (default on):
  - **Magick Archer (8):** the Archer's ranged rules (keep 7 - 20 m, face, line of sight, `AttackS` shots, skills in rotation).
  - **Trickster (9):** ranged rules with a 3 - 9 m band, `AttackS` (censer) and his skills in rotation. He does no damage himself in the game; this only makes him use his kit near the enemy.
  - **Warfarer (10):** `app.Character.getWeaponJob()` read once a second gives the vocation of the weapon in his hands (`brain.fjob`); he runs that vocation's rules (melee / caster / ranged) and only presses equipped skills that belong to it (`brain.skill_job`, id ranges from `HumanCustomSkillID`). He never swaps weapons himself.
- `brain.NEVER`: 87 `Job08_LifeReturn` (needs a chosen ally), 91 `Job08_SpiritArrow` (spends his own health), 100 `Job10_00` (weapon swap) are never pressed, on any vocation.
- The node log (`watch`) now also runs for jobs 8, 9, 10, with same-vocation pawns alongside.
- Assumptions, all unverified: a tap of `AttackS` looses a Magick Archer shot at the lock-on target the way it does for the Archer; Magick Archer skills fire at the lock-on target without manual aiming; `getWeaponJob()` returns 1 - 9 for a Warfarer; the Trickster's simulacrum is not summoned (not known which input does it).

### v0.9.64 (2026-11-15): caster Arisen tops up after fights, answers Help, cures debilitations (not tested in game yet)
- Result (after seeing the Anodyne bubble and walking into it): topping up, helping and curing statuses is good..
- Healing moved into `brain.caster_heal`, used with and without an enemy:
  - **Top-up:** with no enemy, anyone (himself included) below 85 % (`arisen_brain_topup`) gets a heal; same walk-to-them, same 10 s spacing.
  - **Help:** the pawn-command "Help" input (action flag named `Help`, next to `Wait` / `Come`; the load line now logs `help=`) makes him come to the possessed pawn and heal whatever the pawn's health, for up to 20 s; ignores the heal spacing.
  - **Cure:** skill 35 (FullRecover) is class "cure": when someone has Poison / Sleep / VirulentPoison / Frostbite / Freeze / Oil / Silence / Stone / Blind (status flag = 1 << enum) and nobody needs a heal, he walks over and casts it, at most every 12 s. Only if that spell is equipped.
- Also: the 0.5 s press of a heal / cure spell is now held even when the back-off or approach rule would have taken the frame.
- Not known: that the `Help` flag name exists as assumed (else the order does nothing; the load line shows `help=nil`); whether 35 works around the caster like Anodyne; whether Wet / drenched should count.

#### Verified on 0.9.63, 2026-11-15 (result: that worked.; Mage Arisen, several fights incl. 4 x ch222000_00)
- **Wake:** [time] "the main pawn: woke the Arisen (enum)", one press. The enum overload `reqStatusConditionCure(Sleep, true)` is the one that works, and the sleeper plays his own wake-up (`Damage.StatusCondition_Root.DmgStatusSleepWakeUpStartRight -> DmgStatusSleepWakeUp`, about 2.5 s).
- **Heal:** `Job03.Job03_NormalAttack.Job03_CastAnodyne` for 5 s on the upper-body layer: the Mage's Anodyne is on the held heavy attack as assumed.
- **Buffs:** GuardBit (28) cast first in two fights (`Job03_PrepareGuardBit -> ReadyGuardBit -> CastGuardBit`), FireBoon (29) cast (`...CS02.Job03_PrepareFireBoon -> Ready -> Cast`); both are real cast sequences, so the "buff" class for 28 and 29 fits.
- **Bolts:** 24 presses, runs of `JobMagicUser_PrepareNormalShot / RapidShot` between spells and while backing off; Firestorm between them. 11 skill uses, 0 errors.
- Seen, not fixed: the brain keeps issuing turns / steps while the Arisen himself is asleep ("turn stuck at 154 deg off" during `DmgStatusSleepDown`); harmless, he cannot act. A Firestorm incantation was cut off by Sleep once.

### v0.9.63 (2026-11-15): possessed pawn wakes a sleeping companion or the Arisen (not tested in game yet)
- Requested: a possessed pawn should be able to wake a sleeping pawn or the Arisen..
- A party member or the Arisen with the Sleep status (`StatusConditionCtrl.get_ActiveStatusConditionFlagProp() & 4`) within interact range + 0.6 m gets the prompt "[Interact] Wake <name>" (before any object). The press calls `reqStatusConditionCure(StatusConditionEnum 2 = Sleep, true)`; if he is still asleep a second press uses the `StatusConditionFlag` overload (4). `pawn_wake`, default on.
- Deliberately not the game's own rescue interact (`app.Human.RescueSleepInteractCtrl`, `app.HumanRescueSleepInteractController` exists): forced interacts crashed once today. So no shake animation. Not known: what the Boolean of the cure call means, and whether the sleeper plays his wake-up action.

### v0.9.62 (2026-11-15): caster brain with roles: buffs early, heals the hurt, bolts between big spells (not tested in game yet)
- Requested: a simple brain that buffs early, heals when someone is reasonably hurt (the played pawn above all) and uses small attacks while waiting for the bigger spells..
- `brain.SPELL` classes the Mage / Sorcerer weapon skills by `app.HumanCustomSkillID` (from `Enums_Internal.hpp`): attack 24 25 26 32 106 62-69 112 113; buff 28 (GuardBit) 29 30 31 (boons) 34 (HasteSpot); heal 33 (CureSpot). Unlisted ones (27 SpellStock, 35 FullRecover, 36 SpellBreak, 37 HolyGlare, 107 Reraise) are never pressed. The classes of 28, 32, 33, 34 are read off the enum names, not confirmed in game.
- Buffs: a buff not cast in the last 75 s goes before the attack rotation, so all equipped buffs come first in a fight.
- Heal: possessed pawn under 65 % of his (reduced) max health, anyone else or himself under 50 %; the most-below-threshold one wins. He walks to within 2.5 m of them, then casts the equipped heal, or as a Mage without one holds the heavy attack 3.5 s for the core Anodyne (**assumption: Anodyne is on `AttackL` and wants a hold**; the node log will show). 10 s between heals.
- Attack: attack spells in rotation with 4 s of magick bolts between them (was 2.5); bolts also while backing off; casters back off inside 4 m instead of 7 (in three fights he had spent most of the time retreating: 1 bolt press in 30 s).

#### Mage Arisen on 0.9.61, 2026-11-15 (user: "a quick goblin fight with a bot controlled mage arisen")
- Job 3, skills 24 / 29 / - / - / 28 / -. 12 s fight: one spell, Firestorm, Prepare 2.5 s -> Ready -> Cast 4 s -> End, then straight back to locomotion: **no magick barrier after the spell** (0.9.61 fix holds). 0 errors, no stuck events.
- Too short to see slots 2 (id 29) and 5 (id 28) or any bolts; the heal / boon question is still open.

### v0.9.61 (2026-11-15): Quickspell only while incanting (not tested in game yet)
- **Caster brain works on 0.9.60.** Sorcerer Arisen vs 3 hobgoblins; confirmed in play: the spells landed; flames and lightning from the Arisen.. Both 0.9.59 guesses settled by the log:
  - spell nodes are on layer 1 and match the pattern: `JobMagicUser.JobMagic_CS01.JobMagicUser_PrepareFirestorm -> ReadyFirestorm -> CastFirestorm -> EndFirestorm` (2.5 s / 0.5 s / 4 s), same for `CS02 ...Levin`, and `Job06.Job06_Skill.Job06_CS03.Job06_PrepareMineVolt`; layer 0 goes `JobMagicUser_PrepareMagicTurn` then `Locomotion.Strafe`.
  - one tap is enough: Prepare -> Ready -> Cast -> End with no second press. The Sorcerer pawn runs the identical sequence (`Combat_Magic.JobMagic_CS01...`), with Prepare about 3 s against the Arisen's 2.5 s (Quickspell).
  - bolts in between: `Job06.Job06_Normal.Job06_PrepareBurstShot / CastRapidShot`.
- Seen in the node log: right after each spell he went into `JobMagicUser_MagicBarrier` for about 1 s, because Quickspell and the barrier share a button and it was still held as the spell ended. Now held only in a `Prepare` node.
- The remaining "stuck while backoff" events were real (`StopRunInFrontOfWall`).

### v0.9.60 (2026-11-15): caster brain sees upper-body spells; node log of Arisen + same-vocation pawns (not tested in game yet)
- 0.9.59 first Sorcerer fight (job 6, skills 24 / 25 / 64 / 62, two hobgoblins, 25 s): three skill presses, **no "casting:" event at all**, and two rounds of "stuck while backoff (moved 0.2 - 0.6 m)" then "cornered". Unstick only samples in a Locomotion node, so he was in Locomotion on layer 0 while crawling: an incantation that allows walking, most likely on the upper-body layer (layer 1), which 0.9.59 did not look at. So he backed off / stepped / repositioned through his own casts.
- Fix: cast detection also reads layer 1. Not yet known whether layer 1 names match the pattern either.
- To find out, and on a suggestion from the tester (a Sorcerer pawn was in the party to study): telemetry field `watch` logs every node change (both layers, 10 Hz, last 160) of the Arisen and of each party pawn with the same vocation while the caster brain runs.

### v0.9.59 (2026-11-15): caster brain for Mage and Sorcerer (not tested in game yet)
- Reported: a Sorcerer Arisen does nothing. Request: give him a brain. (So the no-brain behaviour is confirmed: follow only.)
- `brain.CASTER = {3, 6}`, style "caster" = the Archer's ranged rules (keep 7 - 20 m, face, line of sight, magick bolts on `AttackS`, weapon skills from all six slots) plus a "cast" mode: while his action is in a custom-skill node he stands still, sends no stick / attack / new skill, holds Quickspell (`JobSpecialAction`) between 45 % and 20 % stamina (`arisen_brain_quickspell`), and the next spell comes 2.5 s after the last one ended (`arisen_brain_cast_gap`). Skill watchdog for casters: 25 s (`arisen_brain_cast_max`) instead of 4.
- Assumptions to check in the first fight: (1) a tap of the skill starts the incantation and the spell goes off by itself when it completes (no second press); (2) spell nodes are named like the other jobs' (`_SkillAttack` / `_CS<n>`), else "cast" mode never engages and he walks or bolts out of his own spells. The log now has "casting: <node>" events to settle both. Known limits: fires support spells (heals, boons, Spellhold, Galvanize) on the same rotation with no judgement; no Levitate; does not flee melee beyond the 7 m back-off.

### v0.9.58 (2026-11-15): CRASH FIX, possessed-pawn interact limited to known object families (not tested in game yet)
- Reported: a crash after teleporting while possessing the main pawn, walking up to a vocation changer and holding interact, all while still possessing.
- `re2_framework_log.txt`: [time] and [time] "the main pawn: used gm52_029", then [time] `Exception occurred: c0000005` (RIP DD2.exe+0x524507e, RAX 0), 21 ms after the second forced interact. The 0.9.26 scan offered every interactive object except live characters, so the pawn's Interact press ran `addActiveInteract` + `executeInteract` on the guild counter, which is built to open a menu for the player.
- Fix: the scan only accepts dead characters, `gm80_*` and `gm82_*` (every object used without trouble so far: gm80_001 / 053 / 079 / 096 / 097, gm82_000 / 009 / 013 / 016 / 021 / 036 / 080). Everything else shows no prompt and is not touched. Talking to NPCs and counters stays the Arisen's (walk him over, or release).
- Not known: whether the teleport beforehand played any part (the log does not need it to explain the crash).

### v0.9.57 (2026-11-15): the Arisen's health and stamina while a pawn is possessed (not tested in game yet)
- 0.9.56 Fighter fight, result: that fight went better. Telemetry: rotation 1 -> 2 -> 3 -> 4 -> **5 (id 12) -> 6 (id 8)**, so the brain now presses all six weapon skill slots; no stuck stance, no "letting go" needed, 0 errors. (Pressed, per the log; whether slots 5 / 6 actually came out was not captured.)
- The tester: while possessing, the Arisen has no bar over his head and nothing shows his state; put his health and maybe stamina at the bottom like co-op, or over his head since no plate is there to conflict with.
- `arisen_bars` (default on, normal possession only): thin green / gold pair (same thickness and opacity settings as player 2's) drawn over his head, anchored on `Head_0` + 0.32 m, computed at LockScene. When he is off screen (or `arisen_bars_overhead` is off) the pair goes to the fixed bottom spot with an "Arisen" label. Health from `Hit.get_Hp / get_OriginalMaxHp` (+ `get_ReducedMaxHp` section), stamina from `StaminaManager`.

### v0.9.56 (2026-11-15): brain breaks out of wait-to-be-hit stances (not tested in game yet)
- 0.9.55, Fighter Arisen (skills now read as six: 1, 10, 3, 7, 12, 8); reported: he looks stuck in the waiting state of a parry skill that holds until someone hits him.. Telemetry: `Job01.Job01_SkillAttack.Job01_CS10.Job01_ShieldCounterStart` from 34654 to past 34791 (2 min 17 s), "letting go" every 4 s throughout, also after "battle over". So pausing the inputs does not end it. Bridge tries of `requestEndAction` / `requestResetAction` showed no change, but the game window may have been unfocused (frozen) then, so that is not conclusive.
- Watchdog now: each try taps one of Jump / AttackS / JobSpecialAction / Sheathe (in turn), from the third try also calls `HumanActionSelector.requestEndAction()`, retries every 2 s while the node lasts, and blocks that skill slot from the rotation for 120 s. Events name the try and the button, so the log will show which one breaks the stance.
- Slots 5 / 6 on the Arisen: still not seen firing (the 0.9.55 fight got stuck at slot 2).

#### Fighter fight at [time] was still on 0.9.54 (no script reset), so slots 5 / 6 are not tested yet
- Telemetry version 0.9.54, `skills` = [1, 10, 3, 7]. Rotation 4 -> 1 -> 2 -> 3 -> 4 -> 1, 0 errors.
- **Skill watchdog verified firing:** "in Job01.Job01_SkillAttack.Job01_CS10.Job01_ShieldCounterAttack for 4 s -> letting go" (skill id 10, a held counter stance). So the name pattern matches real skill nodes (`<Job>_SkillAttack.<Job>_CS<n>.<name>`), and the next skill followed 7 s later.
- Two "stuck while approach (moved 0.5 / 0.2 m)" steers in about 75 s, while in locomotion: plausibly real (four hobgoblins and pawns in the way).

### v0.9.55 (2026-11-15): the brain uses all six weapon skill slots (not tested in game yet)
- Game knowledge supplied by the tester: they have six skills, not four, and core skills are not the same as the button skills. Correct on both. The brain (Archer and melee) only read and rotated slots 1 - 4. Wording: these are **weapon skills** (the equipped, button-press ones); "core skills" are the vocation's built-in moves. Earlier entries that say "core skills" mean weapon skill slots.
- Now `brain.skills` holds slots 1 - 6 and the rotation runs over all six, pressing `Skill5` / `Skill6` with the shift flags for the last two (the flags the game itself raises for the chords, measured in `chord-flags-2`). Not verified: that those two flags alone fire slots 5 / 6 on the Arisen through the brain's injected input (they do for a possessed pawn in co-op).

#### Fighter Arisen on 0.9.54, 2026-11-15; result: the Fighter worked.
- Job 1, core skills 1 / 10 / 3 / 7. Three fights (one `ch222000_00` picked up from 29.3 m, then two spawns of 4 hobgoblins): skills fired in rotation, 11 skill uses and 27 attack presses, 0 errors, no "stuck" / "blocked" / "letting go" events, stood down after each.
- **All four melee vocations have now run in fights**: Mystic Spearhand (dummy), Warrior (goblins, hobgoblins, ogre), Thief (hobgoblins), Fighter (hobgoblins). Missing in all: guard, dodge.

#### Thief Arisen vs 4 hobgoblins on 0.9.54, 2026-11-15; result: the Thief Arisen worked against hobgoblins.
- About 55 s of fighting over two possessions: all four core skills used in rotation (38, 40, 39, 101, then 38, 40), 0 errors, no "stuck" or "blocked" events, stood down at the end. The event log survived the tester switching windows (frozen-time fix holds).
- The skill watchdog did not fire (no "letting go" event): no skill action lasted 4 s this time, so it is still unexercised, and whether its name pattern matches Ensnare is still unknown.

### v0.9.54 (2026-11-15): brain skill watchdog; unstick ignores frozen time (not tested in game yet)
- 0.9.53, Thief Arisen (job 4, core skills 38 / 40 / 39 / 101), a non-Thief pawn possessed; result: the Thief Arisen did well; he held Ensnare for a long time before letting go. Question: should there be a timer? 28 skill uses, 34 attack presses, 0 errors.
- Watchdog (`arisen_brain_skill_max`, 4 s): when his action stays in a custom-skill node (name with `SkillAttack` or `_CS<n>` on either layer) that long, the brain sends no attack or skill input for 1.5 s and pushes the next skill back 5 s. Event "in <node> for 4 s -> letting go". The node name of Ensnare was not captured (see next point), so the name match is by pattern.
- The fight's events were lost: with the game window unfocused the brain logged "stuck while follow (moved 0.0 m) -> steer" every 0.6 s (30 in a row). The simulation stands still when unfocused but the tick runs. Unstick now also skips ticks where his animation frame did not advance (`via.motion.Motion.getLayer(0).get_Frame()`).

#### Ogre fight on 0.9.53, Warrior Arisen (job 5), 2026-11-15; result: the Warrior Arisen looked good in the Ogre fight.
- Target `ch251000_00`, engaged from 6.8 m, fight about 106 s, 16 skill uses (one every ~6.5 s), 0 errors, stood down at the end.
- **No "stuck ... steer" and no "blocked ... attacking from here" events at all**: the 0.9.53 unstick gate holds, and the big-body contact rule was never needed (the ogre's centre was reachable; last distance 1.3 m).
- So that rule is still unexercised; it would take something wider (cyclops, drake, golem). No guard / dodge yet.

### v0.9.53 (2026-11-15): unstick only counts while he can move (not tested in game yet)
- 0.9.52, Warrior Arisen against 4 spawned hobgoblins; result: the Warrior Arisen looks very good in a real fight.. Telemetry: no "blocked ... attacking from here" events any more (the 0.9.52 fix holds), 4 skill uses in 30 s, 0 errors, stood down when the battle ended.
- Remaining noise: "stuck while approach (moved 0.1 - 0.4 m) -> steer 70 / 95 / 119 deg" five times in 30 s. Same cause as the contact rule: the no-progress window ran through attack recoveries. The unstick check (all brain styles) now only samples while his main FSM node is a Locomotion node.

### v0.9.52 (2026-11-15): melee brain: "blocked by its body" rule tightened (not tested in game yet)
- First real fight on 0.9.51, Warrior Arisen (job 5), the main pawn possessed; result: it worked well.. Telemetry: 88 attack presses, 17 skill uses (Warrior has one core skill, id 52), 0 errors, "battle over -> stand down" at the end.
- Flaw in the events a player would not have noticed: "blocked 7.5 / 4.7 / 3.7 / 3.9 / 3.3 / 3.8 m from <goblin> -> attacking from here", six times in 25 s, plus two unstick steers. Goblins are not big; he was not pressed against them. The no-progress check ran while he stood in an attack's recovery (mode already back to `approach`), so he then counted as in reach and swung from up to 7.5 m away.
- Now the check only samples while his main FSM node is a Locomotion node, and only applies within reach + 2.5 m (was 9 m).

#### `melee-brain-1` on 0.9.51, Mystic Spearhand Arisen (job 7): 6 of 6, result: he looked good and powerful.
- Brain on for the vocation; 60% of the 25 s in `engage` (approach 18%, turn 8%, skill 6%); dummy 1000 -> 1 HP; 4 skill uses; 0 script errors.
- Moves seen: `Job07_ShortRangeAttack`, `ShortRangeHeavyAttack`, `FinishingMoveBack / Down`, `LongRangeFinishingMoveBack`. Only skill slot 1 fired (id 73): the Spearhand has one core skill equipped, so the rotation is fine.
- Wait: 0% of the step approaching; he stayed in `wait (out of reach)` with the dummy 10 m away.
- Still untested: Fighter, Thief, Warrior; real enemies that move and hit back; big monsters (the "blocked by its body" rule).

### v0.9.51 (2026-11-15): melee brain for the Arisen, first version (not tested in game yet)
- Decision: build a melee brain; the DLC's vocation bots can be studied, and decompiling is acceptable where needed. (`claude/arisen-ai-plan.md`: Maister spirits, human-enemy AI, action interface.)
- What stands in the way of running the game's AI on him: the Arisen's GameObject has none of the parts pawns run on. Component comparison (`DPC_probe_interact_1.json`): only the pawn has `app.AIBlackBoardController`, `app.ActionInterface`, `app.AIDecisionMaker`, `app.goalplanning.AIGoalPlanning`, `app.PawnNavigationController`, `app.PawnAIBlackBoardController`, `app.DecisionEvaluationModuleLateUpdator` (and 19 more). So routes A / B / C of the plan all start with adding AI components to the player character at run time, which is an experiment, not a feature.
- Built now, on the machinery the Archer brain already uses (his own player controls and lock-on): `brain.style = "melee"` for jobs 1, 4, 5, 7.
  - Out of reach (2.3 m centre to centre, Warrior 2.7): run at the target, sprint beyond 7 m. No progress for 0.5 s within 9 m = his body is against a big target -> counts as in reach for 3 s.
  - In reach: turn if more than 25 deg off; otherwise attack every 0.42 s (Warrior 0.8 s) with every fifth press heavy, leaning the stick toward the target; core skills 1 - 4 in turn every 6 s.
  - Wait: he only fights what comes into reach. Battle-only gate, target choice, unstick and lock-on as for the Archer.
  - Not in this version: guard, dodge, backing off at low health, flying targets, line-of-sight flank.
- Checkbox "Melee brain" (on). README updated.
- Next for the DLC-bot route: read a human enemy's / Maister spirit's AI state with `dev/bridge/ai/ai_state.lua` when one is nearby, to copy its attack choices and timing, and try attaching an `ActionInterface` to the Arisen in a throwaway session.

#### Verified live by the tester, 2026-11-15 (0.9.50)
- Wait keeps the Arisen in place (0.9.28). Interact prompt over the object: "perfect" (0.9.37). AI action interrupted on taking control: "seems to be interrupted fine" (0.9.38). Co-op gyro block: "worked great" (0.9.39). Co-op warp incl. player 2's pawn: "great" (0.9.40 / 0.9.41). Player 2's left trigger no longer aims the Arisen's bow (0.9.46). Numpad . heal: "works perfectly". Thin muted bars: "looks good" (0.9.50).
- Next, per the tester: other Arisen vocations / brains.

### v0.9.50 (2026-11-15): player 2's bars thinner and muted (not tested in game yet)
- 0.9.49 seen working (screenshot: green health over yellow stamina, "P2 the main pawn"). Requested: vertically thinner and less bright, so they do not overpower the Arisen's own UI..
- Thickness 13 px -> 4 px at 2160 p (`coop_bars_thick`), colours muted (green 78A860, gold D2B450) at 65% opacity (`coop_bars_alpha`), lighter backing, dimmer label, smaller gap. Sliders for both.

### v0.9.49 (2026-11-15): player 2 gets a health bar with the stamina bar (not tested in game yet)
- 0.9.48 fixed bar seen working in the tester's screenshot (bottom centre, just above the Arisen's own gauges, "P2 <pawn name>"). Decision: a health and a stamina bar for the co-op player.
- Health bar (green) drawn above the stamina bar (yellow) in the fixed pair: `Character.get_Hit()` -> `get_Hp()` / `get_OriginalMaxHp()`, with a dim section up to `get_ReducedMaxHp()` when that reads. `coop_health_bar` (default on); the checkbox for the pair now reads "health and stamina bars for player 2".

### v0.9.48 (2026-11-15): player 2's stamina as a fixed HUD bar (not tested in game yet)
- 0.9.47 with the real head joint, reported (three screenshots): still all over the place.. Measured: the height now matches the health bar within 10 - 35 px in all three, but sideways the plate's bar is 260 px right, 100 px left and 130 px right of ours. So the plate takes its height from about the head and its horizontal position from something else (unknown), and its own position is not readable.
- As the tester proposed (it could even sit near the Arisen's UI): the default is now a fixed bar, bottom centre of the HUD area (`coop_stamina_hud_x` 0.5, `coop_stamina_hud_y` 0.9, width 16% of the HUD width), yellow on dark, labelled "P2 <pawn name>". Two sliders move it. The head-following bar stays as an option (`coop_stamina_attach`, off).

### v0.9.47 (2026-11-15): stamina bar: the head joint is `Head_0` (not tested in game yet)
- 0.9.45 / 0.9.46, reported (three screenshots): still bobbing around relative to the health bar.; crouched, the bar sat about 470 px above the plate.
- Cause: `getJointByName("Head")` returns nil. Joint list read live from the main pawn (`dev/bridge/joint1.lua`, 187 joints, heights above the root while standing): Hip 0.97, Spine_0 0.97, Spine_1 1.15, Spine_2 1.32, Neck_0 1.49, Neck_1 1.56, **Head_0 1.63**. So 0.9.45 fell back to feet + 1.62 + 0.44 m and behaved exactly like the feet anchor. Now tries `Head_0`, `Head`, `Neck_1`; the joint in use is in the dev status (`stam_joint`).
- If the plate turns out not to follow the head either, fallback agreed with the tester: a fixed stamina bar for player 2 near the Arisen's gauges.

### v0.9.46 (2026-11-15): co-op: controller reached the Arisen again (false self-check); fixed (not tested in game yet)
- Reported: a regression; the left trigger in co-op zooms the Arisen's bow as if the controller drove the Arisen.
- Cause, from the log and config: at [time] DPC logged "Co-op: processButton pad zeroing blocked keyboard/mouse too; switched off" and `coop_zero_pad_for_arisen` was saved as false. That self-check (player 1 holds a mouse button or Space while the Arisen's input shows no buttons for 45 frames) fired while the tester was dragging the stamina sliders in the REFramework window. With the zeroing off, player 2's L2 (AimHold) reached the Arisen. Not a code regression in the aim / gyro work.
- Fix: the check runs only in the first 20 s of a co-op session, never while the REFramework UI is drawn, and only disables the zeroing for that session (`coop.zero_off`); the saved setting is no longer changed. Existing configs get `coop_zero_pad_for_arisen` back to true once.

### v0.9.45 (2026-11-15): stamina bar anchored to the Head joint (not tested in game yet)
- 0.9.44, reported (two screenshots, idle vs Launchboard): the game must be basing it on some other position.. Measured from them: standing, the feet + 1.9 m anchor projects 31 px under the health bar; crouched in Launchboard it is 95 px above and 9 px right. So the plate follows the head, not the root; the "lag" was the body moving under a fixed-height anchor.
- Anchor is now the `Head` joint (`Transform.getJointByName`) + `coop_stamina_head_up` (0.44 m, estimated), feet + 1.62 m if the joint is missing. Offsets reset to dx -9, dy +10, frames 0; the height slider is replaced by "height above the head".

### v0.9.44 (2026-11-15): stamina bar: placement from the screenshot, frame offset slider (not tested in game yet)
- 0.9.43, reported (screenshot): at rest the bar sits just above the health bar (about 14 px up, 9 px right, same width); in motion it lags the movement and ends up anywhere near it, not attached. So the LockScene projection is still not the frame the game's plate uses.
- Defaults moved under the health bar (dx -9, dy +24 at 2160 p; applied to configs still at 0 / 0). New `coop_stamina_frames` slider (-3 .. 4): positive shows an older projection, negative extrapolates ahead by the last frame's motion.
- The plate itself is still not found: it is not a `GuiManager` field (all `app.ui*` fields scanned), and `Scene.findComponents(via.gui.GUI)` returns an empty array (`dev/bridge/plate1.lua`, `plate2.lua`).

### v0.9.43 (2026-11-15): stamina bar position computed at LockScene (not tested in game yet)
- 0.9.42, reported: the bar updates but wiggles on any movement. Guess at the cause: it was projected at draw time (`on_frame`), when the pawn's transform and the camera are not from the same moment. Now the screen position and ratio are computed in a `LockScene` pre-entry callback (scene final for rendering), rounded to whole pixels, and only drawn in `on_frame`. Falls back to draw-time if the callback can't be registered.
- The game's plate still isn't read: `GuiManager.PawnOverHead` was nil even with a plate on screen, and a scene search for `app.ui0225xx` components returned a collection the probe couldn't walk (`dev/bridge/stam3.lua`).

### v0.9.42 (2026-11-15): co-op stamina bar for player 2's pawn (not tested in game yet)
- The tester asked for a thin yellow stamina bar under the co-op pawn's health bar. Stamina is `Character.get_StaminaManager()` -> `get_RemainingAmount()` / `get_MaxValue()` (994 / 994 on the main pawn, read live). The plate is `GuiManager.PawnOverHead` (`app.ui022502`); it was nil when probed, so its position is not read.
- First version (`coop_stamina_bar`, default on): drawn with `draw.filled_rect` at the projection of feet + 1.9 m, centred, 252 px x 5 px at 2160 p (scaled by screen height), dark backing. Sliders: height, x / y offset, width. Placement estimated from screenshots; expect to tune it.

### v0.9.41 (2026-11-15): co-op warp brings everyone, with a toggle (not tested in game yet)
- Decision: teleport everyone, with a toggle. In co-op Numpad 7 now also warps player 2's pawn to the Arisen (`coop_warp_p2`, default on, checkbox). Checkbox added for `coop_no_gyro` too.
- Not checked: how the native controls and the co-op camera take a warp of the pawn player 2 is driving.

### v0.9.40 (2026-11-15): co-op: Numpad 7 warps pawns to the Arisen (not tested in game yet)
- Requested: in co-op the warp key should bring pawns to the Arisen, or to whoever the keyboard player controls, since it is a keyboard command. It used the possessed pawn, which in co-op is player 2's. Now: normal possession -> the possessed pawn; co-op or no possession -> the Arisen. Player 2's pawn is not moved.

### v0.9.39 (2026-11-15): co-op: controller gyro no longer aims the Arisen (not tested in game yet)
- Requested: PlayStation gyro aiming must be off for the Arisen while the controller is meant to drive the co-op pawn.
- Type probe (`dev/bridge/gyro1.lua`): `app.RotateCameraControllerBase` (parent of the aim camera) has `GyroEnable`, `GyroSensitivity`, `_GyroAngle`; `app.UserInput` / `CharacterInput` carry `GyroAngularVelocity`; `app.Player` has `GyroSensorTrack`, `GyroSensorDisableTimer`, `updateGyroSensorSequence`; `app.UserPadManager.isMotionSensorEnable()` is the option check; `AimCameraSetting.AimSetting` has `_GyroOperation`.
- While co-op is active (`coop_no_gyro`, default on): a post-hook makes `isMotionSensorEnable()` return false, and each frame the camera controller in use gets `set_GyroEnable(false)` if it was on. Counters in the dev status (`gyro.blocked`, `gyro.cleared`) show which of the two actually bites. No settings checkbox yet.

### v0.9.38 (2026-11-15): stop the pawn's running AI action when taking control (not tested in game yet)
- Reported: when co-op control starts, the pawn is sometimes already doing something, such as running somewhere, and is hard to break out of. DPC's suppression is soft flags only (`IsSkipThink`, `IsRequestDisableNavi`, `_NextOrder` = 0), which stop new decisions but not the one being executed.
- Type probe (`dev/bridge/act1.lua`): `app.DecisionExecutor` (from the pawn's `DecisionEvaluationModule.get_DecisionExecutor()`) has `get_ExecutingDecision()`, `forceEndDecision()`, `endDecision()`; `HumanActionSelector` has `isEnableRequestIdle()`, `requestIdleImpl(Boolean)`, `requestEndAction()`, `cancelUpperBodyAction()`.
- At possession start (normal and co-op), `possess_interrupt_ai` (default on): `forceEndDecision()` when a decision is executing, then `requestIdleImpl(false)` when `isEnableRequestIdle()` allows. Logged as "Interrupted <pawn>'s AI action: ...". Not known yet whether this covers every case the tester saw (e.g. navigation moves that are not a decision).

### v0.9.37 (2026-11-15): interact prompt drawn over the object (not tested in game yet)
- **Verified live (0.9.35 / 0.9.36):** result: arrows land well on all targets so far, and back-pedalling works. So the ray-cast aim point and the after-processor facing are confirmed for the possessed Archer.
- The tester (co-op screenshot): the Gather prompt sits mid-screen, not near the item, which is over by player 2's pawn. The prompt is now placed at the object's projected screen position (`draw.world_to_screen`, 0.35 m above it); the old fixed spot is the fallback when that is off screen. Applies to normal possession too.

### v0.9.36 (2026-11-15): Archer pawn keeps facing the target while moving in aim (not tested in game yet)
- 0.9.35, the tester (screenshot): moving backwards while aiming, the Arisen backpedals facing the target; the possessed pawn turns round (the reticle stays forward). Cause, by reading: DPC set the facing only before the pawn's input processor ran, and with a move input the processor overwrote it with the move direction. Now the camera yaw is also written right after the processor (same place as the aim point).
- No word yet on the 0.9.35 ray-cast aim (tree / rock / enemy).

### v0.9.35 (2026-11-15): Archer pawn aims at what the reticle is on (ray cast; not tested in game yet)
- 0.9.34, reported (screenshots, tree a few metres away): almost right, but still shooting left compared with the Arisen. Geometry: the pawn stands left of the camera's centre line; arrows converge on the aim point, so with the point at 25 m a target at 5 m is hit left of the reticle. Only the real distance fixes every range.
- Ray cast from Lua works (`dev/bridge/aim/ray1-5.lua`): `via.physics.System.castRay(Scene, CastRayQuery, CastRayResult)` (and `castRay(CastRayQuery)`), options all hits + near sort, filter layer 0, mask all. 42 - 61 hits per ray: sensors and markers (collidable layers 12, 15, 16, 17, 20, 34, 35), the party's own bodies (3, 4, 7, 26, 37, 38; folders Player / Pawn), world geometry (layer 1 `EnvRoot_*` folder Environment, layer 22 `EnvRoot_*` / `GroundCol` folder Terrain). Result pool counters unchanged after 10 casts.
- The mod's aim point now sits at the first hit that is world geometry (layer 1 or 22) or a character outside the Player / Pawn folders; fixed 30 m when nothing is hit. Checkbox `pawn_aim_ray`; five ray errors switch it off with one error report. Dev status shows `aim.dist`.
- Not verified: enemies and breakable objects as hits (no enemy was in view during the probes), and thin obstacles in front of the target.

### v0.9.34 (2026-11-15): Archer pawn arrow steering on by default
- `archer-aim-6` on 0.9.33 (result: arrows behaved well in the test, landing a little left of the reticle.; outside the test "arrows are still spraying" because steering was off by default):
  - **How the game aims the Arisen's bow:** while he aims, `Character.AimTargetPosition` has a value in 105 of 105 aiming samples, exactly on the camera's centre line (0.00 m off), 12.6 - 13.6 m along it while facing a wall, i.e. the point the centre line hits. Possessed pawn without steering: no value in 113 of 113 samples. With the corrected steering: value present, on the line, at the fixed 60 m; bow steady, 0 errors.
  - Up / down / up snapshots (562 numeric fields of Character, Human, input processor, camera controller): only the aim camera's own angle / position follow the pitch, the same for the Arisen and the pawn. Nothing else to copy; the aim target is the mechanism.
  - "A bit left": the bow is right of the camera, so a point 60 m out on the centre line pulls near shots left of a 13 m target.
- `pawn_aim_point` on by default again, distance 25 m (`pawn_aim_point_dist`, slider 5 - 100 in the DPC window, with the checkbox). A ray cast to the real hit point would remove the leftover offset; not done.

### v0.9.33 (2026-11-15): corrected aim-point write (still off by default); dev hook for tests
- 0.9.32, reported (screenshot): reticle in place; arrows are close to right side to side, but not vertically (one went into the ground at his feet, some fly at normal height).
- Bridge probes (`dev/bridge/aim/aim5_*`, `aim6_*`): camera forward is the transform's -Z (confirmed against the pawn's position). `Character.get/set_AimTargetPosition` use `System.Nullable<via.vec3>` (32 bytes, `_HasValue` at 0, `_Value` at 16), not a plain vector. **So the 0.9.30 steering passed the wrong kind of value; that, not the idea, made the bow circle**, and it is also why the test's aim-target probes failed. The pawn's value read `_HasValue` false when idle.
- `R.aim_point` now writes a proper Nullable. Still off by default until tested.
- With `DPC_dev.json`, DPC exposes `_G.DPC_dbg = { native, state, R }` so TestGuide plans can read the pawn's own input processor.
- `archer-aim-6`: snapshots every numeric field of Character / Human / input processor (+ Detail, Param) / camera controller while the Arisen looks up, down, up, keeps the values that follow the pitch, does the same for the possessed pawn, then tries the corrected steering.

### v0.9.32 (2026-11-15): Archer pawn reticle centred (not tested in game yet)
- `archer-aim-5` on 0.9.31 (reported: steering causes the circling; the reticle is off centre; compare with the Arisen., with screenshots):
  - **Aim point confirmed as the cause of the circling bow** (off: steady, on: circles). It stays off and loses its checkbox.
  - **Reticle point is in real screen pixels.** Arisen aiming: `ui020801.DrawPos` = 960,540 in every sample. Pawn with the mod's request at 1920,540 on the 7680x2160 screen: `DrawPos` = 480,270 (and the earlier 960,540 request sat further left). So DrawPos = point x (1920 / width, 1080 / height); the right point is the centre of the real screen (3840,1080 here). The mod now uses that; the "learn from the Arisen" hook never fired (0 calls seen) and is removed.
  - Camera hold fine again (aim camera in 79% of the step incl. releases, 1270 switch-backs skipped, 0 errors).
  - The test's aim-target probes failed (`get_AimTargetPosition` did not return a plain vector), so how the game steers the Arisen's arrow is still unmeasured.
- Open: where the possessed Archer's arrows go with steering off.

### v0.9.31 (2026-11-15): aim point off by default
- 0.9.30 in free play (screenshot from reported): the reticle shows for the possessed Archer (drawn at 1920,540, the computed centre; nothing learned from the Arisen yet), but the bow rotates in circles while aiming. Dev status: aim hold on, 856 switch-backs skipped, 0 errors. Suspect: the new `set_AimTargetPosition` write (the only new thing touching his pose; 0.9.29 had camera + body follow without this report). `pawn_aim_point` now defaults to false (existing configs are switched off once).
- The live switch-off did not take (the command file was overwritten by a TestGuide warm-up mark a moment later), so the fix arrives with 0.9.31 after a script reset. Not confirmed yet that the circling stops with it off. `archer-aim-4` has not been run; its part 1 (the Arisen's aim target against the camera line) is still what tells us how the game steers the arrow.

### v0.9.30 (2026-11-15): Archer pawn reticle and aim point (not tested in game yet)
- `archer-aim-3` on 0.9.29 (reported: the possessed Archer had a zoom reticle, but off to the side; the camera follows and seems to aim, but arrows go high or into the ground; dropped-item pickup worked for the main pawn):
  - The mod's camera hold works by itself: aim camera on while the pawn aimed, 594 switch-backs skipped, body within 4.6 deg of the camera on average, camera back to normal on release, 0 errors. The `Smooth` preset was used (nothing learned, the hook was only installed at the first pawn aim).
  - Reticle: the game drives it with `ui020801.requestDraw` every frame (259 calls in 6 s for the Arisen), scale 1.0, flag false. The point is passed **by pointer** (the test read the pointer, not the point). Replaying with 960,540 made the reticle appear for the pawn (`FlowNow` 1) but left of centre on the 7680x2160 screen, although the UI reports `ScreenSize` 1920x1080.
- Reticle in the mod (`pawn_aim_reticle`): each frame of the aim hold DPC calls `requestDraw(point, 1.0, false)`. Point = what the game passed for the Arisen this session (read through the pointer in a hook installed at load), else the centre of a 1080-high canvas as wide as the screen (1920,540 on 32:9; 960,540 on 16:9). Both are guesses until measured.
- Aim point (`pawn_aim_point`): right after the pawn's input processor runs, `set_AimTargetPosition` = camera position + 60 m along its view. Not known yet whether the bow reads this while aiming.
- `archer-aim-4` measures the Arisen's aim target against the camera's centre line, checks the reticle position, and compares arrows with the aim point on and off.

### v0.9.29 (2026-11-15): bow aim camera for the possessed Archer; dropped items; stuck-interact fix (not tested in game yet)
- `archer-aim-2` (TestGuide-side experiment, reported: closer, but no aim reticle; the camera did zoom and worked better.):
  - Holding works: with the game's switch back to type 0 skipped in a pre-hook, the aim camera stayed on in every sample of phases 2 and 3 (the game tries about 50 times a second; 674 skipped in 15 s). On release the camera returned to normal.
  - Body follows the camera with `set_TargetFrontAngleDeg(camera yaw)` each frame: body-to-camera angle 21.8 deg average (78 max) without it, 0.5 deg (1.7 max) with it.
  - Reticle: idle vs aiming diff on the Arisen: `GuiManager.Aim` (`app.ui020801`) `FlowNow` 0 -> 1 and its GameObject `UpdateSelf` false -> true; `Player.InputProcessor.IsAimHoldOn` false -> true; `Human._DrawBowRatio` 0 -> 1, `ActionType` 0 -> 13. `ui020801` has `requestDraw(via.Point, Single, Boolean)` and `setFlowId(FlowId, Boolean)`; `GuiManager.drawAim` is never called.
  - The game's transitions: enter `CameraSwitchInterpParam` frame 20 mode 1, exit frame 40 mode 1, no post effect, option 0. The type has static presets (`Smooth`, `EaseIn`, ...).
- **Aim camera in the mod** (`pawn_aim_camera`, default on; native controls, not co-op, Archer only): while the pawn's upper body is in `Job02_StartAim` (and following bow nodes) DPC requests camera type 7, skips the game's switch-back, turns the pawn to the camera yaw, and switches back to type 0 when he stops or possession ends. Transition objects are learned from the Arisen's own aim when seen, else the `Smooth` preset. The skip only applies while the aim tick is fresh (0.5 s), so it cannot outlive the feature.
- **Dropped items** (user: The main pawn can't pick up the miasmite next to him; prompt shows, Triangle / F do nothing). Object `gm82_000_01` (`app.Gm82_000_01`, item 236), 0.61 m away. `addActiveInteract` + `executeInteract` returned ok but the item stayed and the pawn was left `isInteracting` (which made DPC ignore every later press). Invoking the object's `StartInteractHandler(0, pawn)` afterwards: interact cleared at once and the item was gone at the next check (not yet confirmed by eye whose inventory). Now: for `gm82_000*` DPC also invokes the Start handler; the prompt says "Pick up"; and a pawn still "interacting" 3 s after the last press is ended with `endInteract` before the new one.
- Dev status file gains `aim = { hold, blocked, reqs, learned, off }`.
- Next: `archer-aim-3` checks the mod's camera hold and tries the reticle through `ui020801.requestDraw` with the Arisen's captured arguments, then an aim point at the screen centre.

#### Archer pawn: no aim zoom, no reticle, arrows follow the body not the camera (2026-11-15, 0.9.28, open)
- User report while possessing an Archer pawn. Probes (`dev/bridge/aim/`): the bow aim is camera control type 7 (`app.AimCameraController`) on `app.MainCameraController`; the camera's target is the pawn but the controller stays `UsuallyCameraController`. Reticle candidates: `app.Player.drawReticle / updateReticle`, `GuiManager.Aim` (`app.ui020801`), `GuiManager.drawAim(via.Point, Single, Boolean)`.
- `archer-aim-1`:
  - Arisen aiming: one `MainCameraController.switchCamera(7, interp, nil, 0)` on entering, `switchCamera(0, interp, nil, 0)` on leaving (upper body `Job02.Job02_StartAim` -> `Job02_AimCancel`). `GuiManager.drawAim` was never called (0 calls), so the bow reticle is not drawn through it; `Player.drawReticle` / `updateReticle` run every frame regardless; `ReticleRoutine` stayed 0.
  - Pawn aiming, unchanged: the pawn does enter `Combat.Job02_StartAim` (41 of 53 samples) but the game never requests the aim camera.
  - Replaying the Arisen's `switchCamera(7, ...)` for the pawn: accepted, and 20 ms later something called `switchCamera(0)` again (aim camera seen in 1 of 90 samples). The tester: no zoom, no reticle, arrows go where the pawn faces, the model does not follow the camera.
- `party-matrix-4` (Fighter, Archer, Sorcerer), 14 of 15, 0 errors: Archer's R1 attack shows on the upper-body layer (`Job02_NormalShootWithoutAim`), so the earlier "attack not detected" was the test's blind spot. Sorcerer: move, L2 and skill 1 pass; R1 attack not detected on either layer (weapon drawn, then idle). Not yet known whether that is the robot or the mod.
- Next: `archer-aim-2` holds the aim camera by blocking the switch back while the pawn aims, then adds body-follows-camera and an aim point at the screen centre, and diffs the reticle UI / Player state between idle and aiming.

#### "Skills did not work on the Warrior until the test ran" (2026-11-15, 0.9.28): it was co-op mode, not a reset problem
- User report: possessing the Warrior, the native skill display did not work and skills could not be triggered; after the tests it worked.
- `re2_framework_log.txt`: [time] co-op ON (the main pawn) with no command-file line, F7 x2 to Graal, [time] co-op off, [time] co-op ON (Graal) until `party-matrix-3` started at [time]. So every F6 press in that window was read as Ctrl+F6. In co-op the keyboard and the HUD stay with the Arisen, which is exactly the symptom. 09:07:23: plain possession of Graal, skills fine. No script errors, native controls built every time (`Job05InputProcessor`).
- Not known: whether Ctrl was really held or REFramework's key state was stuck down (`reframework:is_key_down(0x11)`). Possible hardening, not done: accept Ctrl for the chord only if its press was seen in the last few seconds; a larger on-screen co-op notice.
- Same log: Sorcerer (the Sorcerer pawn) possessed at [time] with native controls (`Job06InputProcessor`).

### v0.9.28 (2026-11-15): Wait keeps the Arisen where he is (not tested in game yet)
- `beta-check-1` (0.9.27), 13 of 14 checks, 0 script errors; result: everything looked good..
  - Quick skills: Blink Strike, Shield Pummel (Cymbal Attack) and Full Moon Slash came from the game's own data (`game (live)`); Launchboard (Springboard) from the fallback table, as expected (the game has no decision naming it).
  - Numpad 7 brought the main pawn to 0.9 m.
  - Co-op: HUD prompts stayed on keyboard/mouse in every sample; L1+R1 = slot 3, L1+R2 = slot 4, Triangle+Circle = slot 5, Square+Cross = slot 6.
  - Leash (auto-warp off, Arisen waiting): the pawn reached 59.8 m (the check wanted 80), was never teleported, no errors.
  - Wildlife: the tester: large bison were nearby and the Arisen did not shoot them (brain stayed idle / following for the 8 s step). The battle-only gate (0.9.18) holds for that case.
- While the Arisen waits, the auto-warp now only fires past `arisen_warp_dist_wait` (120 m) and ignores the height rule; while he follows it stays at 35 m.

### v0.9.27 (2026-11-15): skill palette off by default
- The tester: the drawn skill palette (bottom right) is no longer needed now that the native HUD shows the pawn's skills; default it off and keep it as a debugging option. `skill_hud_overlay` defaults to false (existing configs are switched off once); the checkbox reads "Skill palette (debug)".
- **Verified live (0.9.23+):** the tester: number row and D-pad Wait / Follow work relative to the possessed pawn.
- Question from the tester: does the Arisen need to warp over when he is too far (he popped over during Wait)? That is `arisen_warp_dist` (35 m): it was added to stop the game's party leash pulling the possessed pawn back to the Arisen, not as a crash fix (the crash suspect was the every-frame warp storm, fixed in 0.6.0). Whether the leash still pulls a possessed pawn has not been measured since; `beta-check-1` measures it with the warp off.

### v0.9.26 (2026-11-15): the possessed pawn gathers and loots himself (not tested in game yet)
- `pawn-interact-1`: `requestInteractFromAI(corpse, 0, pawn)` was accepted but nothing happened (no node change, never `isInteracting`): the pawn's AI is suspended while possessed. The gather step found no `gm*` object within 4 m.
- Bridge experiment `int4_direct.lua`: `addActiveInteract(pawn, InteractPoint{Object = corpse, PointNo = 0})` + `executeInteract(pawn)` -> `isInteracting` true, ended by itself. **Confirmed in play: that one looted, and the item went to the pawn's inventory..**
- Feature (`pawn_interact`, default on), normal possession and co-op:
  - 5x a second: nearest object in `InteractManager.InteractiveObjects` within `pawn_interact_range` (2.2 m) of the pawn. Party members and the Arisen are skipped; a character only counts when dead (a corpse).
  - DPC draws its own prompt (`[Interact] Loot` / `Gather / Use`) inside the 16:9 area.
  - While the prompt shows, the game's Interact press runs the two calls above; that press (which is also dash) is removed from the pawn's input until released. 1 s cooldown.
- **Verified live (0.9.26):** the tester: a herb worked; a chest worked and gave its item (a Wakestone Shard) but the opening animation did not play. Likely because the calls go straight to execute and skip the start phase (`StartInteractHandler`, the character's own interact action). Corpse loot verified earlier.
- Not verified: ore / doors / levers through this path (only a corpse was tried), and whether something that should not be usable shows the prompt.

### v0.9.25 (2026-11-15): interact helper off by default
- The tester tried 0.9.24: the warp and the pickup work, but it is unsuitable. Triangle is used constantly (it is also dash) and carries the Interact flag, so the Arisen warps on dashes; and the Gather prompt never shows for the possessed pawn, so there is nothing to tell the player an interaction is available.
- `interact_bring` now defaults to false (0.9.24 configs are switched off once) and is labelled experimental.
- Direction from the tester: if the Gather prompt showed for the possessed pawn as it does for the Arisen, capturing that press and having the Arisen walk over might be suitable. Next: find what drives the prompt (`dev/bridge/interact/`).

#### Interact research (2026-11-15, game running, probes `dev/bridge/interact/int1..3`)
- Only the Arisen's GameObject has `app.Player`, `app.SpecialPlayer`, `PL_SituationalReactionCircleController`, `OccupiedEventHolderPlayer`; nothing interact-specific sits on the character.
- `app.InteractManager` (singleton) owns it: `InteractiveObjects` (33 registered where the tester stood), `InteractivesForPlayer`, `HighestPriorityObjectForPlayer` (what the prompt shows), `updateHighestPriorityObjectForPlayer()`, `executeInteract(Character)`, and **`requestInteractFromAI(InteractiveObject, UInt32 pointNo, Character)`**, the route AI pawns use to gather.
- `app.InteractiveObject`: `Owner` (GameObject, for the position), `get_NumInteractPoints`, `HasEnabledWorkTargetPlayer`, per-character enable handlers.
- Idea to test: for the possessed pawn, find the nearest interactive object, draw our own prompt, and on a dedicated key call `requestInteractFromAI(object, 0, pawn)` so the pawn itself gathers. `int3_request.lua` is the first experiment (not run with a target nearby yet).

### v0.9.24 (2026-11-15): Interact brings the Arisen to the possessed pawn (not tested in game yet)
- The tester: while possessing, most things stay relative to the Arisen; the pawn can't pick up items, but the button works if the Arisen stands at the loot.
- Helper (`interact_bring`, default on): in normal possession and out of battle, an `Interact` press while the Arisen is more than `interact_bring_dist` (2 m) from the pawn warps him to the pawn (the F8 warp), at most once per 1.5 s. A second press then interacts; the loot goes to the Arisen.
- Unknown: whether the `Interact` flag shares its bit with another action (several names share bits), which would trigger the warp on that action too.

### v0.9.23 (2026-11-15): number row back to the game while possessing (not tested in game yet)
- The tester: while possessing, the number row fired the pawn's skills instead of the game's orders (Go, Wait, ...); not needed any more.
- Keys 1-6 on the number row are no longer read by DPC (native key injection and the puppeteer fallback). Numpad 1-6 still fire the possessed pawn's skills. `number_row_skills = true` restores the old behaviour.
- The palette labels say `Num1`..`Num6`.
- Not done: making the orders apply relative to the possessed pawn.

### v0.9.22 (2026-11-15): skill palette labels and co-op skills 3 / 4 follow the six-skill layout (not tested in game yet)
- The tester's screenshot (possessed Fighter with six skills, L1 held): Square = skill 1, Triangle = skill 2, **R1 = skill 3, R2 = skill 4**, Circle = Sheathe/Draw, Cross = Jump, Triangle+Circle = 5, Square+Cross = 6. DPC's palette said `L1+X / Y / B / A` and `Skill 5 / 6`.
- Palette: PlayStation names; when slot 5 or 6 holds a skill it shows the layout above, otherwise the four-skill layout (Square, Triangle, Circle, Cross; measured 2026-11-12). Vocation action shows `L2`.
- Co-op: with a skill in slot 5 or 6, player 2's skills 3 and 4 are L1 + R1 / R2. The rule "layout switches when slot 5 or 6 is filled" is inferred from the two observations, not read from the game.

### v0.9.21 (2026-11-15): chorded skills on the possessed pawn (not tested in game yet)
- `chord-flags-2` (60 Hz, controller), Arisen vs possessed Fighter:
  - L1 + Square+Cross raises `Skill1 + Jump + Descent + GimmickCancel + Job09AstralDown + Skill6` in the same frame; L1 + Triangle+Circle raises `Skill2 + ActCancel + Sheathe + Draw + Skill5`. So Square+Cross is the **Skill6** flag and Triangle+Circle the **Skill5** flag.
  - The game holds back the single skill flag while one button is down alone (Circle alone for 20 ms showed no `Skill3`), then raises single and chord flags together.
  - The Arisen did the chord skills (ids 19 and 17). The pawn's input carried the same flags one frame later, but he did the single skills: Blink Strike (slot 1) and Full Moon Guard (slot 2).
- Fix attempt: while `Skill5` / `Skill6` is on in the pawn's input, the single-button actions (Skill1-4, Jump, ActCancel, Sheathe, Draw, Descent, GimmickCancel, Grab, Interact, Dash) are removed from its On / Trigger / Release flags. Why the pawn's processor prefers the single skill is not known.
- Co-op chords now send the game's own flags: Square+Cross -> `Skill6`, Triangle+Circle -> `Skill5`.
- **Verified live** (`chord-flags-3`, 4 of 4): possessed Fighter, controller. Square+Cross -> Braves Raid (slot 6) in every press, never Blink Strike; Triangle+Circle -> Full Moon Slash (slot 5), never Full Moon Guard. Result: the chords worked perfectly..
- The `a_trg` / `p_trg` probes were empty because the field is `ButtonTriggerFlags`, not `ButtonTrgFlags`.

### v0.9.20 (2026-11-15): co-op chord for skill 6 is Triangle+Circle
- The tester: the game's chords are Square+Cross (skill 5) and **Triangle+Circle** (skill 6); they fire easily as the Arisen. 0.9.13 had guessed Cross+Circle for skill 6.
- Open (normal possession, native controls): the HUD lights the chord but the pawn does the single skill. TestGuide `chord-flags-1` records the input flags per frame for the Arisen and the possessed pawn.

### v0.9.19 (2026-11-15): co-op chord window 0.09 s -> 0.16 s
- The tester: the chorded skills (5 / 6) are possible but very hard to trigger. In co-op the chord timing is DPC's own, not the game's: the first face button waited only 90 ms for its partner, then fired as a single skill, after which the chord can no longer start. Now 160 ms (saved 0.09 values are migrated). Cost: L1 + Square / Cross / Circle alone start 0.16 s after the press.
- Normal possession uses the game's own input handling for chords; DPC does not touch it.
- Open: it was reported that the bottom-right skill palette is "wrong now" for the Fighter; details asked.

### v0.9.18 (2026-11-15): the Arisen brain only fights during a battle (not tested in game yet)
- The tester: while possessing, the Arisen fires arrows too eagerly, apparently at wildlife; he should only fight when in combat.
- Cause: the brain targeted any living entry in `EnemyManager.getAllEnemies()` within 30 m, with no combat check.
- New gate `arisen_brain_battle_only` (default on): a target is only picked while `BattleManager.get_IsBattleMode()` is true or a party pawn's `Pawn.isBattle()` is true (checked 4x a second, held 2 s after it ends). Brain events log `battle: ...` / `battle over`.
- Not verified: whether wildlife ever sets either flag, and whether the flags rise early enough at the start of a fight.

### v0.9.17 (2026-11-15): quick skills read the game's own pawn AI data (not tested in game yet)
- Goal: rebuild the skill -> action pack table independently of Pawn Tactical Wheel (the tester's reason: it also double-checks that we understand everything; PTW is still credited and recommended).
- Probes (`dev/bridge/skills/dec1..4`), game running, party Fighter / Thief / Mage:
  - `app.AIDecision` has `HumanCustomSkillIDs`, `ActionPack` (`app.ActInterPackData`, `get_Path`) and `Target` (`AITargetFlag`: My 1, Player 2, Enemy 4, Party 64).
  - A pawn's decisions live in `AIDecisionMaker.DecisionModule` (`app.DecisionEvaluationModule`): `MainDecisions` / `PreDecisions` / `PostDecisions`. Out of battle: 24 decisions, none naming a skill. **In battle: 57-63, with 5-7 naming the equipped skills.**
  - `CharacterManager.DecisionPackCatalog` holds only 26 packs (12 skills), so it is not the full source.
  - 17 skill decisions read; 13 give exactly PTW's file. The other 4 are variants the game also has: `Job01_BlinkStrike_Standard` (PTW: `job01_blinkstrike`), `Pawn_Job01_FullMoonSlashEx`, `Job04_HollowOut_02`, `Job03_ThunderRain_COMEPL`. Target kinds agree (ThunderBoon is Player|My|Party).
  - Fighter slot 2 (Springboard, id 5) has no decision naming it.
- Quick skills now look in the pawn's own decisions first (plainest file name among variants, target kind from the flag), using the game's pack object directly. Each find is saved to `data/DPC_skill_packs.json`, our own table learned from the game, and used out of battle. The PTW-derived table is only the fallback for skills not seen yet.
- Also seen on the pawn: `app.SafetyPositionFinder`, `app.CheckBattleTargetSafeLocation`, `app.PawnRayController`, `app.OcclusionChecker`, `app.TacticalArea`, `app.goalplanning.AIGoalPlanning`: candidates for the Arisen brain's "pick a clear spot".

### v0.9.16 (2026-11-15): release preparation (not tested in game yet)
- **Developer tooling is off unless `data/DPC_dev.json` has `{"dev": true}`:** the command file, robot, spawner commands and every telemetry file (`DPC_trace`, `DPC_arisen_brain`, `DPC_coop`, `DPC_quick`, `DPC_input_log`, `dev_status`). A released copy writes only its config and `DPC_session.json`.
- **Session sentinel:** `DPC_session.json` records whether a pawn is possessed. If the game starts and it still says so, the last session ended mid-possession; the DPC window says which pawn. Two such endings on a natively controlled Thief set `native_skip_thief` (fallback controls) automatically.
- **Overlays for 16:9 recording:** `hud_safe_169` ("auto" = screens wider than 16:9) places the status banner and skill palette inside the middle 16:9. Checkbox and "Reset overlay positions" in the window; the overlays can also be dragged while the REFramework menu is open.
- The main chunk hit Lua's 200-local limit; new release helpers live in one table `R`.
- Packaging: `README.md`, `modinfo.ini`, `tools/build_release.py` -> `dist/` (DPC zip, CameraDistance zip, and one archive with both as separate Fluffy mods).
- TestGuide `party-matrix-1`: the robot takes each party pawn through move / attack / vocation action / skill 1 and records its vocation.
- Open before a public upload: Pawn Tactical Wheel's permission/credit for the quick-skill table; a Thief soak; non-Archer Arisen behaviour while possessing.

### v0.9.15 (2026-11-14): heal / revive and warp-to-me from PawnCommander; despawn clears "can't die"
- The tester retired PawnCommander in favour of DPC + Pawn Tactical Wheel and asked for its heal / revive and warp to move into DPC.
  - **Numpad .** heals and revives every pawn: `recoverAll`, `IsStartRecoverHpAndMaxHpCompletely`, stamina `recoverAll`, `Pawn.setPawnRevive`, `cureAllScar`.
  - **Numpad 7** warps every pawn to you: `PawnManager.safeWarp(chara, UniversalPosition)`, falling back to `warp()` on a ring around you if a pawn ends up more than 60 m away after 0.3 s. While a pawn is possessed, "you" is that pawn.
  - Keys: `cfg.keys.party_heal` / `party_warp`. Numpad 7 and . were PawnCommander's Order 3 and Heal; Numpad + (its Warp) also belonged to CameraDistance's zoom.
- PawnCommander made inert in `pawn_commander_config.json` (hotkeys and wheels off, keys 0; backup taken first). The script itself stays in autorun until the tester moves it, since the bridge can't move files.
- Bug: the bridge-test goblin stayed alive at 0-1 HP after `despawn`, because its GameObject wasn't destroyed and it kept `IsNoDie`. Despawn now clears `IsNoDie` on tough dummies first. That goblin was fixed by hand over the bridge.

### v0.9.14 (2026-11-14): Numpad 1-6 quick skills for the selected pawn
- The tester: Numpad keys used to fire pawn skills while nobody was possessed (PawnCommander, Numpad 1-4), but they no longer do. He wants Numpad 1-6 = skills 1-6 on the pawn F6 would possess; the numpad doesn't need PawnCommander's orders (Numpad 5-8).
- Bridge tests on the main pawn (Fighter, skills 1, 9, 3, 5, 4, 12):
  - `HumanActionSelector.requestCustomSkill(id, 0)` every frame for 1.5 s (AI decisions off, weapon draw requested): nothing happened. This is PawnCommander's method, so its numpad skills are dead for that reason.
  - Pawn Tactical Wheel's method: `AIBlackBoardExtensions.setBBValuesToExecuteActInter(bb, ActInterPackData(job01_blinkstrike.user), AITarget(enemy))` + `set_ReqMainActInterPackData`. Blink Strike started 0.47 s later (`Job01_SkillAttack.Job01_CS01.Job01_BlinkStrike`).
- New `quick_skills` (default on): Numpad 1-6 while nobody is possessed and co-op is off -> the selected pawn (`selected_pawn_idx`, F7 cycles) uses skill slot 1-6 through its AI pack.
  - Pack table: 82 skills, jobs 1-6, from Pawn Tactical Wheel's `data.lua`.
  - Enemy skills target the Arisen's lock-on target, else the enemy nearest the middle of the screen (35 deg, 45 m), else the enemy nearest the pawn (25 m).
  - Support skills target the Arisen; self skills the pawn. The pawn's own blackboard target entry (weak points) is preferred.
  - Each order is written to `DPC_quick.json` and the DPC log.
- PawnCommander's numpad keys (`skill_1..4`, `order_1..4`) were set to 0 in `pawn_commander_config.json` so they don't fire alongside (they also lock the pawn's target list for up to 10 s).
- TestGuide `quick-skills-1`.
- **Verified live (0.9.15):** the tester: all six Numpad skill keys work in combat; Launchboard (a support skill) also works out of combat.

### v0.9.13 (2026-11-14): co-op HUD stays on keyboard prompts; chord skills 5/6 for player 2 (not tested in game yet)
- The tester: in co-op the HUD shows controller prompts as soon as player 2 uses the pad, but player 1 (keyboard/mouse) owns the HUD.
  - `app.UserInputManager.switchingGamePadKeyboardMouse` sets `HIDInputMode` (`app.UserInputManager.InputMode`: GamePad 0, KeyboardMouse 1; from `Enums_Internal.hpp`, game closed).
  - In co-op a pre-hook pins it to 1 and skips the switch (`coop_kbm_glyphs`, default on). Co-op start also sets it back to 1. Counter `glyph_skips` in `DPC_coop.json`.
- The tester: player 2's chorded skills (Square+Cross, Cross+Circle) did nothing. DPC's pad map had skills 1-4 only.
  - Now L1 (or L2) + Square+Cross = `Skill5`, + Cross+Circle = `Skill6`, sent with Shift1+Shift2 (`coop_chord_skills`).
  - A chord button held alone waits `coop_chord_window` (0.09 s) for its partner before it counts as a single skill.
  - The chord stays latched until both buttons are up, so letting go of one doesn't fire skill 1, 3 or 4.
  - Counter `chords` in `DPC_coop.json`. The chord-with-L1 reading is my reading of the tester's description; the game's own combination assignment (`UserInputManager.setSkillButtonFromCombination`) wasn't read.
- TestGuide `coop-hud-chord-1`.
- **Verified live:** the tester: L1 + Cross + Circle works.

### v0.9.12 (2026-11-14): co-op auto-target for player 2's pawn (not tested in game yet)
- The tester: possessed the main pawn's skills (Burst Strike) seem harder to aim than a Fighter Arisen's.
- Code reading (game closed):
  - Normal possession: the pawn's native processor uses the Arisen's own LockOnController, rebound to the pawn and updated by `app.Player`, so skills should home like the Arisen's. The finder is camera based, so a camera pointed away can pick the wrong enemy or none.
  - **Co-op: player 2's pawn gets its own LockOnController (`native_own_lockon`) that nothing ever updates, so it never had a target.** Skills went straight ahead with no homing.
  - Pawn Tactical Wheel aims by handing the pawn's AI an `ActInterPackData` with an `AITarget` (`setBBValuesToExecuteActInter`), so the AI plays the move. Not used here: player 2 would lose control during skills.
- New `coop_auto_target` (default on): every 0.1 s, pick the best enemy for player 2's pawn: within `coop_target_range` 15 m, inside `coop_target_cone` 75 deg of his facing (or within 5 m from any side), scored by distance x angle, sticky toward the current one. Every frame right before his processor runs: `setTarget(work, false, false)` + `setAimTargetInfoToCharacter()` on his own controller. Skipped for a Thief (`coop_target_thief`), never touches player 1's controller, off after 20 errors.
- `DPC_coop.json` gets `target`, `target_dist`, `target_sets`; the Dev HUD line shows `p2 target`.
- TestGuide `coop-target-1`: dummy off to the side, skill 1 without turning toward it, first in normal possession, then in co-op.
- **Verified live** (`coop-target-1`, 7 of 7 checks): normal possession had a lock-on target in 63 of 76 samples, turned to within 2 deg of the dummy and hit it (a different skill went off there). In co-op the pawn had a target in every sample (74 of 74) while player 1's lock-on stayed empty, his aim was set, Blink Strike turned him to within 0.1 deg and the dummy dropped to 327 HP. Result: that worked well.. 0 errors.

### v0.9.11 (2026-11-14): unstick check on every full-stick move
- `brain-los-1f` (0.9.10): no stuck turn this time (turns finished in under a second). He picked a real enemy (4200 HP) over the dummy, approached, shot, used skills.
- The tester: when the enemy got close he ran for distance, a wall blocked him, and he kept running at it. Recording: `backoff` for 12.7 s with the enemy at about 6 m.
- New progress check on any move at full stick (approach, backoff, reposition, flank, follow): less than 0.6 m in 0.6 s -> steer 70 deg to one side for 1.2 s; still stuck -> other side, 25 deg wider each time (max 150). Mode shows `(unstick)`; each trigger is a brain event.
- Three failures in a row while backing off -> `cornered`: no backoff for 4 s, so he stands and fights.
- Not done: choosing a clear spot ahead of time (needs a ray or navmesh query; candidates to find with the bridge). TestGuide `brain-corner-1` sets up the wall case.

### v0.9.10 (2026-11-14): turn watchdog
- `brain-los-2c` (0.9.9, possessing): the dummy was never hidden (clear line in all 144 samples), so the flank is still unexercised; he fought normally (27 shots, all four skills).
- `robot-smoke-2`: 9 of 10. L1 held before Square now fires skill 1. The robot's Arisen `AttackS` still does nothing (open).
- `brain-los-1e` (solo): flags pass; blocked for 0.4 s at 20 m, line cleared, then he stood in mode `turn` for 23 s at 19.6 m with a clear line and never fired (reported: he did not attack.). The angle wasn't recorded, so the cause is unknown; `set_TargetFrontAngleDeg` plus the 0.15 stick did not finish the turn.
- Watchdog: 1.5 s in `turn` -> 0.5 s at full stick toward the target (mode `turn (step)`), logged as a brain event with the angle. `brain-los-1f` records `off_deg` so the next stuck turn can be diagnosed.

### v0.9.9 (2026-11-13): line-of-sight rule on by default
- `brain-los-1c` / `-1d` (0.9.8): wall flags verified (visible: `isWallPL` false in every sample; hidden: true in every sample). Tough dummy verified (dropped to 1 HP, refilled).
- `-1c`: the Arisen stood idle 12 s because the dummy was 35 m away (engage radius 30 m), not because of the wall.
- `-1d`: blocked at 29 m -> held fire (0 presses) and approached; the line cleared after 2 s and he fought normally (13 shots, 3 skills). Result: he worked correctly.. Mode stays `approach` beyond keep_max even when blocked, so plans now check `blocked=true` instead of the `no line of sight` label.
- `arisen_brain_los` now defaults to **true**. Still unexercised: the sideways flank (blocked while inside 20 m); `brain-los-2c` sets that up.

### v0.9.8 (2026-11-13): line-of-sight flags read correctly; test dummies can't die
- First live run (`brain-los-1`, `-1b`): every wall flag read `nil`, so the 0.9.6 rule could never trigger. Bridge reflection of `app.LockOnTargetWork` shows `isWall`, `isWallPL`, `isWallCam`, `isValid` are auto-properties (fields named `<isWall>k__BackingField`); only `IsRayCasted` is a plain field. The brain now calls `get_isWall()` etc.
- `IsRayCasted` is true on only about 15% of samples (the rays are asynchronous), so the rule no longer waits for it; the flags are taken as the last ray result.
- Reported: pawns kill the test dummy. A `still` spawn is now `tough` by default (`"tough": false` to opt out): `HitController.set_IsNoDie(true)` and a full refill (`recoverHpAndMaxHpCompletely`) below 30% HP.
- `robot-smoke-1` (0.9.7) passed 8 of 10: robot stick and R1 / L2 work, co-op isolation holds. The two fails were the robot's presses (Arisen `AttackS` for 0.2 s only reached Strafe; L1 + Square pressed on the same frame). `robot-smoke-2` presses longer and puts L1 down first.

### v0.9.7 (2026-11-13): dev status and robot player (not tested in game yet)
- **Dev status:** writes `data/dev_status/DirectPawnControl.json` once a second (version, error count, last error, config save result, what it is doing). TestGuide 2.0 shows it on the Dev HUD and uses it for a plan's `requires`. Errors from the co-op filter, co-op drive, pad read and the brain are counted there.
- **Robot player** (`DPC_cmd.json`), so tests can press the buttons themselves:
  - `{"cmd":"robot","who":"pad","secs":2,"buttons":["RTrigTop"],"stick":[0,1],"rstick":[1,0]}` adds buttons / overrides sticks in DPC's own pad read (co-op and DPC combos see them; the game's own pad read does not).
  - `{"cmd":"robot","who":"arisen","secs":3,"actions":["AttackS"],"stick":[0,1]}` (or `"yaw_deg": 90`) drives the Arisen through the brain's input path, with no gates and no job check. Brain mode shows `robot`.
  - `{"cmd":"robot","who":"all","stop":true}` stops both. `secs` is capped at 30.
- TestGuide `robot-smoke-1` is the first no-hands test: Arisen run and attack, co-op on, player 2 stick / R1 / L2 / L1+Square, with pass/fail checks.

### v0.9.6 (2026-11-12): line of sight for the Arisen brain (not tested yet)
- The tester: the brain-driven Arisen shoots even with no direct line of sight.
- Source of truth found offline (dd2-modkit `dd2_sdk.lua`): the lock-on system ray-casts each candidate for walls. `app.LockOnTargetWork` has `isWall`, `isWallPL` ("from player"), `isWallCam` ("from camera"), `IsRayCasted`, `WallCheckRayFromPlayer/Camera`, `gatherWallCheckRayResult()`. The brain already holds its target's work (`target:get_LockOnTarget():get_work()`).
- The brain reads the flags every tick; they are always in the telemetry (`los`, `los_blocked`).
- New `arisen_brain_los` (default **off**; checkbox next to "uses skills"): blocked for `arisen_brain_los_delay` 0.4 s -> mode `no line of sight`: no shots, runs at `arisen_brain_los_angle` 50 deg off the direct line (steeper when close), swaps side every `arisen_brain_los_swap` 2.5 s while still blocked. `arisen_brain_los_field` picks the flag (default `isWallPL`).
- Unknown until tested: whether the flags update for a target the Arisen isn't locked on, and whether "PL" is the Arisen while a pawn is possessed. TestGuide `brain-los-1` checks the flags first, then the behaviour.

### v0.9.5 (2026-11-12): player 2's buttons no longer block the Arisen's own
- The tester: while player 2 holds L2 (guard), the Arisen can't aim with the right mouse button. Cause: the co-op filter's second layer cleared every action flag player 2 was pressing from the Arisen's `ButtonOnFlags`, including ones player 1 pressed himself (L2 guard and RMB aim share the AimHold bit).
- That mask is now off by default (`coop_mask_p2_flags`); the `processButton` pad zeroing stays. TestGuide `coop-aimzoom-2` checks that player 2's R1/R2/Cross still don't reach the Arisen.

### v0.9.4 (2026-11-12): co-op layout file; Triangle = sprint
TestGuide `coop-pad-1` (co-op on, controller only) checked v0.9.3:

| Input | the main pawn |
|---|---|
| L2 | `Job01_Guard` |
| R1 | `ShortRangeAttack` |
| R2 | `ShortRangeHeavyAttack` |
| L1 + Square | `BlinkStrike` |
| L1 + Triangle | `FullMoonGuard` |
| L1 + Circle | `CymbalAttackLv2` |
| L1 + Cross | `Springboard` |

The Arisen stayed in normal locomotion the whole time. Square/Triangle alone did nothing (unmapped). The tester says Square = grab and Triangle = sprint toggle (same as L3).

- Triangle now maps to Dash/Sprint.
- New optional `data/DPC_coop_layout.json`, read at every co-op start, so a corrected layout needs no script reset. Its entries replace the built-in non-skill entries for that button. Format is in the code comment above `coop_ensure_map`.
- `pad-flags-2` measured: Square = 0x801000020 (Grab+…), Triangle = 0x20201000050 (Dash+Interact+…), L3 = 0x10 (Dash). These are in `DirectPawnControl/data/DPC_coop_layout.json`, deployed to `reframework/data/`.
- `coop-pad-3` (co-op, controller only):
  - Square → the main pawn `Catch…HoldDown` (pinned the hired Thief pawn and the Arisen; the Arisen went to `Caught_HoldDownDefault`).
  - Triangle sends Dash+…; pawn top speed ~8 m/s.
  - L1+Square → `BlinkStrike`, no grab.
  - The Arisen stayed in locomotion except while pinned.
- Open: a pawn's grab on an ally pins them (HoldDown) instead of the player's lift/carry (`Carry_Root`, seen when the Arisen grabbed a pawn). The game probably picks the catch type by who is grabbing.


### v0.9.3 (2026-11-11): co-op controller layout from the real game
The tester reported that the main pawn couldn't block or use skills in co-op. TestGuide `pad-flags-1` recorded the Arisen's `ButtonOnFlags` while each controller button was held with co-op off:

| Button | Game action (flag) |
|---|---|
| R1 | AttackS 0x400 |
| R2 | AttackL 0x800 |
| L2 | AimHold / JobSpecialAction 0x200 (block for a Fighter) |
| L1 | Shift1+Shift2 0x100 |
| L1 + Square / Triangle | Skill1 0x40 / Skill2 0x10 |
| L2 + Square | Skill1 without the shift flags |
| Cross | Jump 0x20 |
| Circle | ActCancel / Sheathe 0x80 |
| R3 | SwitchLockOn 0x2000 |

Several action names share one bit.

- The built-in layout now follows that table. v0.9.0 had light/heavy on Square/Triangle, the skill shift on R1, dash on L1 and "Aim" on L2.
- L1 or L2 now count as the skill shift; a shifted face button sends only the skill.
- Still guesses: Square/Triangle alone (unmapped), L3 = Dash.
- The pad enum is cached (it was re-read every frame).

### v0.9.2 (2026-11-11): co-op stick and camera blocks rewritten
Measured with TestGuide (`coop-walk-2`). With the v0.9.0 "keyboard-only stick" on, the Arisen crawled at about 0.5 m/s while W was held; with it off he ran at 4–5.5 m/s, but player 2's left stick also walked him (Arisen and pawn moved at the same speed). `KeyboardMouseAxisL` is zero on most frames even while W is held, so copying it every frame zeroed his stick. `KeyboardMouseAxisR` behaves the same way, which is why the camera filter kept switching itself off.

- **Stick:** new `coop_block_p2_stick`. Only on frames where player 2's left stick is pushed, the Arisen's stick is rebuilt from WASD (no keys = stand still). On all other frames his input is not touched.
- **Camera:** new `coop_block_p2_camera`. Only on frames where player 2's right stick is pushed and the mouse did not move, `AxisR` is cleared.
- The old keys (`coop_arisen_kb_stick`, `coop_camera_mouse_only`) and their auto-off self-checks are gone, so a saved `false` from v0.9.x doesn't carry over.
- The right stick is now read too (`pad_stick_rx/ry`). Telemetry adds `stick_fixes` and `cam_fixes`.
- Known gap: when player 1 moves the mouse and player 2 pushes the right stick in the same frame, both still reach the camera.
- **Verified live** (TestGuide `coop-walk-4`, co-op started by the plan):

  | Input | Result |
  |---|---|
  | W only | Arisen runs at 5.5 m/s |
  | Controller left stick only | Arisen stays put; the main pawn runs at up to 7.8 m/s |
  | Both together | Both move |
  | Mouse | Camera turns |
  | Right stick only | Camera doesn't move (`cam_fixes` 158) |
  | Triangle | the main pawn's `ShortRangeHeavyAttack` |

  `stick_fixes` was 293.

### v0.9.1 (2026-11-11): the controller is read at all
First live test of v0.9.0: in normal possession the controller drove the pawn's actions but not his movement, and in co-op (`Ctrl+F6`) the controller did nothing. Three bugs, found with bridge probes and a scan for undefined globals:

- **No controller device.** `poll_pad` called `via.hid.GamePad.getMergedDevice(0)`, which returns nil, so DPC never read the pad. Buttons still worked in normal possession because they come through the game's own input; the stick did not when the Arisen brain was on (that path skips the `UserInput` fallback). Fixed: the property `get_MergedDevice()` returns a `via.hid.MergedGamePadDevice`; `get_Button` and `get_AxisL` read from it.
- **Co-op read undefined globals.** `pad_buttons` / `pad_stick_x` / `pad_stick_y` were declared after `coop.pad_input`, and `is_key_down_safe` after `coop.filter`. In Lua those references became globals (nil), so player 2 always sent 0 and the Arisen filter raised an error every frame (inside a pcall). Fixed with declarations near the top. A `texluac -l` scan now shows no undefined globals in DPC or CameraDistance.
- **The "game pad assignment" was bogus.** `UserInput.getButton(action)` gave AttackL and Jump the same button (0x10) and mapped Grab and Dash to R3. Co-op now uses the built-in DualSense layout by default; the game map is opt-in (`coop_map_source = "game"`).
- Mode 2's L2 check tested 0x80 (Circle); now 0x200 (LTrigBottom).
- Telemetry `coop` block adds `pad_device` and `pad_stick`.

`via.hid.GamePadButton` values (probed): LUp 1, LDown 2, LLeft 4, LRight 8, RUp 10, RDown 20, RLeft 40, RRight 80, LTrigTop 100, LTrigBottom 200, RTrigTop 400, RTrigBottom 800, LStickPush 1000, RStickPush 2000, CLeft 4000, CRight 8000.

### v0.9.0 (2026-11-11): couch co-op (player 2 on a controller plays a pawn)
Built overnight without a live test. Every guess checks itself and reports in the `coop` block of `data/DPC_arisen_brain.json` and in the log.

**Start/stop:** `Ctrl+F6`, the "Start couch co-op" button, or the command file (`{"cmd":"coop","idx":0}` / `"on":false`). It plays the selected pawn.

**Player 2 (pawn, controller)**
- Uses the native controls as usual, but its `CharacterInput` comes from the pad only (`via.hid.GamePad` merged device).
- **Stick:** with a dead zone. It is camera-relative to the shared camera.
- **Buttons:** translated through the game's own pad assignment: `UserInput.getButton(actionFlag)` on the Arisen's input, for every `CharacterInput.Action`. If fewer than 6 actions resolve, it falls back to a built-in DualSense layout:
  - Square = light, Triangle = heavy, Cross = jump
  - R1 = skill shift (Shift1 + Shift2); R1 + Square / Triangle / Circle / Cross = skills 1-4
  - L1 = dash, Circle = grab, L2 = guard/aim, R3 = lock-on
  - Only action names that exist are used.
- R1 + face button becomes a skill, not a skill plus attack. Skill bits are never sent without the skill button.
- Keyboard number-key skills are off, since the keyboard belongs to player 1.
- It gets its own `LockOnController` (`native_own_lockon`), so player 1 keeps his.

**Player 1 (Arisen, mouse + keyboard)**
- Plays normally: no brain, no blocked processor, no tether or Wait/Come, the camera stays on him, the HUD stays his.
- **Ignoring the pad:**
  - The pre-hook of `app.UserInput.processButton` (the game's pad path) passes an empty `GamePadButton` for his input.
  - Self-check: if he holds a mouse button or Space for 45 frames with no actions registering, that layer turns itself off.
  - Any pad-derived action left in his buttons is also masked out in his processor's pre-hook.
- **Move stick:** his stick becomes `UserInput.KeyboardMouseAxisL`. Self-check: if WASD is held while it reads zero for 30 frames, this override turns off.
- **Camera:** `AxisR` becomes `KeyboardMouseAxisR`, so player 2's right stick doesn't turn the camera. v0.8.2 showed the camera reads `AxisR` after that hook. Self-check: if the mouse moves while it reads zero, the camera filter turns off.
- **Fallback drive:** if `app.Player.update` stops running his processor during the possession, DPC runs it, as the brain does.

**Possession settings while co-op runs**
- Co-op temporarily changes `sub_camera_attach`, `exp_rebind_lockon`, `native_own_lockon`, `sub_disable_arisen_pip`, `native_hud_skill_hook`, `native_hud_gauges` and `arisen_auto_follow`.
- They are restored when co-op ends. `save_cfg` never writes the co-op values, and switching pawns (F7) keeps co-op on.

**Camera:** DPC writes `data/DPC_coop.json` at load and whenever co-op starts or stops. CameraDistance v2.2.0 reads it to pull back and centre between both players.

**Settings:** Tuning has checkboxes for the three player-1 filters and for forcing the built-in DualSense layout.

**Untested assumptions:**
- `getButton` returns the bound pad button.
- `processButton`'s second argument is the pad state.
- `KeyboardMouseAxisL` and `KeyboardMouseAxisR` hold the keyboard and mouse share.
- An orphan `LockOnController` is safe for the pawn. It was a suspect in the old Thief crashes; Thief now runs native too.

### v0.8.11 (2026-11-10): Thief back on native controls
- **Why now:** the 3 Thief native crashes (v0.7.0-0.7.4) all happened under the old pre-`UpdateBehavior` timing. Moving the processor into `app.Player.update` (v0.7.5) ended the same crashes for Fighter and Mage, but Thief was never retested.
- **What we know since then:**
  - All Thief crashes are worker-thread access violations in the 0x524xxxx family, with the same worker stack (+0x52bbe45 → +0xf59f67). The return-to-title crash and the hired Thief pawn + brain crashes share it.
  - The common thread is the Arisen's `LockOnController`, which is shared with the possessed pawn. A main-thread change to it (rebinding `Chara`, a target swap, or a destroyed character) while its target search is in flight fits all of them.
- **Changes:**
  - `native_skip_thief` now defaults to off, migrated once.
  - The brain never swaps the shared lock-on while a Thief is possessed (`arisen_brain_lock_thief` turns it back on). The Arisen still fights; his shots go where the camera's target finder points them.
  - **Black box:** `DPC_arisen_brain.json` is now written twice a second whenever you are possessing, even with the brain off. It records:
    - the pawn's name, job, control path, FSM nodes, HP and last action
    - which character the lock-on currently belongs to, and whether it has a target
  - After a crash, the last snapshot shows what the pawn was doing.
- **Test plan:** first the hired Thief pawn with the brain off, fighting with her skills; then with the brain on. Fall back with "Thief pawns use the puppeteer" (Tuning).


### v0.8.10 (2026-11-10): no brain frames at the start of a possession
- **Third the hired Thief pawn crash with the brain setting on (v0.8.9):** crashed at [time], 3.5 s after the second the hired Thief pawn possession in a row.
  - Worker thread `c0000005` at DD2.exe+0x5f45, with the same worker stack as before (+0x5d75 → +0x52bbe45 → +0xf59f67).
  - The tester reports the hired Thief pawn does not crash with the brain setting off.
- **Telemetry:**
  - The brain did run 25 frames, lock swaps included, right at the main pawn → the hired Thief pawn switch ([time]).
  - Cause: the "pawn uses native controls" flag was still the previous pawn's until the mirror refreshed it.
  - During the later the hired Thief pawn possession the brain stayed off.
- **Change:**
  - The flag resets on release.
  - The brain waits 60 frames after any possession starts, so it never runs while DPC is still setting up the pawn, or before the flag is fresh.
- **If the hired Thief pawn still crashes with the brain setting on:** the brain is not running then. Look at what the setting still changes while the brain is idle.


### v0.8.9 (2026-11-10): knockdowns no longer end possession
- **Play test (v0.8.8):** the main pawn and Yenn with the brain on were stable. the hired Thief pawn with the brain on (now auto-off) was stable too.
- **User report:** control snapped back to the Arisen when the pawn took damage. The log showed `Releasing possession (possessed pawn downed/dead)` mid-fight.
- **Cause:** the safety guard released on `Character.get_IsDown`, which is also true for an ordinary knockdown from a hit.
- **Fix:** release only on `get_IsDead`, or when `get_IsDown` is true with 0 HP (the revivable dying state).


### v0.8.8 (2026-11-10): brain stays off while a Thief (puppeteer) pawn is possessed
- **Second crash, on v0.8.7:** possessing the hired Thief pawn (Thief, Mode 2 puppeteer) with the brain on crashed again, about 7 s later.
  - Worker thread `c0000005` at DD2.exe+0x524aa9d, again in `via.vec3.op_Subtraction`.
  - The v0.8.7 lock-swap skip was active, so the swap alone is not the cause.
  - the main pawn (native controls) with the brain on has not crashed.
- **Change:** the brain does not run while the possessed pawn uses DPC's puppeteer (Thief, or failed native controls). The Arisen falls back to the classic follow and Wait/Come behaviour. `cfg.arisen_brain_puppeteer` turns it back on for testing.
- **Still open:**
  - Whether Thief puppeteer possession crashes with the brain off. Thief crashed before the brain existed.
  - The source of the caught `via.Component.get_GameObject` `InvalidOperationException`. It now also shows up with nothing possessed ([time]).


### v0.8.7 (2026-11-10): the hired Thief pawn crash with the brain on
- **Play test (v0.8.6):**
  - **the main pawn (native) possessed, brain on:** the Arisen moved and shot goblins with his bow, and your controls worked.
  - **Switching to the hired Thief pawn (Thief, Mode 2 puppeteer) mid-fight:** the game crashed 6 s later.
- **Crash:** `c0000005` on a worker thread in `via.vec3.op_Subtraction`, at DD2.exe+0x524aa97.
  - The stack runs through +0x52bbe45 and +0xf59f67, the same frames as the return-to-title crash (+0x5246c38).
  - It is the same 0x524xxxx family as the earlier Thief crashes.
- **Also in the log:** two caught `InvalidOperationException`s from `via.Component.get_GameObject`, 30 s earlier while possessing the main pawn. Source unknown.
- **Lead:** the brain swaps the shared `LockOnController.Chara` between the pawn and the Arisen every frame. A worker-thread target search that starts in one state and finishes in the other would subtract positions from the wrong or a stale character. Thief possession leans hardest on that controller.
- **Change:** no lock swap while the possessed pawn runs on DPC's puppeteer, i.e. Thief, or native controls failed. `cfg.arisen_brain_lock_puppeteer` turns it back on. In those possessions the Arisen still fights, but his shots only hit what the camera finds.
- **Next:** check whether Thief Mode 2 crashes with the brain off. If the swap is the cause, give the Arisen his own `LockOnController` instead of swapping `Chara` on the shared one.


### v0.8.6 (2026-11-10): clicks reach the pawn with the brain on
- **User report (v0.8.5):** clicks work with the brain off. As soon as the brain turns on, they stop reaching the pawn.
- **Cause:** with the brain on, the Arisen's `CharacterInput` holds the brain's buttons whenever the brain wrote last. Restoring your input at the end of `app.Player.update` (v0.8.4) depends on where the game calls his processor, and was not enough.
- **Fix:**
  - The brain snapshots your buttons right before it writes its own, on the first injection each frame.
  - While the brain is on, DPC's pawn mirror uses that snapshot instead of reading the Arisen's input, as long as the snapshot is less than 0.25 s old.
  - The snapshot reopens every frame at the mirror.
- **Telemetry:** adds `your_buttons` (the snapshot) and `pawn_mirror_on`, so you can see whether your presses reach the pawn while the brain runs.


### v0.8.5 (2026-11-10): your clicks reach the possessed pawn again
- **Symptom (v0.8.3-0.8.4):** while possessing, clicks did nothing and number keys behaved oddly. It happened with the Arisen brain off too.
- **Measured live:**
  - A frame-timeline probe sampled the Arisen's `CharacterInput` at 8 points per frame (pre/post UpdateBehavior, `app.Player.update` pre/post, LateUpdate, rendering). While possessed, 0 of 2,901 frames carried any button.
  - When playing the Arisen, buttons show up there normally.
  - Wide probe: the presses still reached `UserInputManager.SystemInput` and `InputForEventCamera`.
- **Cause:** the game only writes your buttons into the Arisen's `CharacterInput` while his `PlayerInputProcessor` is **enabled**. DPC mirrors that object onto the pawn. DPC disabled his processor at possession and every frame, so there was nothing to mirror.
- **Confirmed live:** a bridge script re-enabled it at pre-`UpdateBehavior` each frame, and the tester's pawn attacked again at once, without a restart.
- **Fix:** DPC keeps his processor enabled. Hooks 1a/1b still skip his processor update and sequence buffer, so he can't act on your input. When the brain is on, it drives him with its own input, then hands yours back (v0.8.4).
- **Open question:** how v0.7.x attacked with the processor disabled. The v0.8 test sessions may have changed something persistent, or the enable/disable timing shifted.


### v0.8.4 (2026-11-10): possessed pawn can attack again
- **User report (v0.8.3):** the camera works, but the possessed pawn cannot attack.
- **Cause:**
  - The brain writes its buttons into the Arisen's `CharacterInput`, and left them there for the rest of the frame.
  - At the start of the next frame, DPC mirrors that same object onto the pawn, so the pawn got the brain's buttons instead of yours.
  - Before v0.8.2 this never showed up: the brain could not run during possession, so nothing was injected.
  - Movement and the camera still worked, because DPC reads those from the pad and keyboard directly.
- **Fix:** the brain saves your real buttons and left stick before injecting, then puts them back at the end of the Arisen's `app.Player.update`, after his processor and sequence buffer. The pawn mirror then sees your input again.


### v0.8.3 (2026-11-10): camera fix while possessing
- User report: with v0.8.2 the camera could not be turned while possessing a pawn.
- Telemetry showed the game itself running the Arisen's processor: 837 injected frames, only 2 driven by the brain. That happens because the brain keeps `IsEnable` true.
- His processor runs after the pawn's and also feeds the camera. The brain was zeroing his right stick (`AxisR`), so the camera got zero input.
- The brain now leaves his right stick alone. `cfg.arisen_brain_clear_axis_r` (off) brings the old behaviour back.
- Still to check: whether the camera now turns at double speed, with both processors applying your input.


### v0.8.2 (2026-11-10): brain works while you possess a pawn (verified unattended through the command file)
**Test session:** the agent drove the game alone through `DPC_cmd.json` (possess / spawn / despawn / release) and bridge recorders. Before porting to DPC, each fix ran as a bridge stand-in on top of v0.8.1.
- **Brain while possessing, proven end to end** (the main pawn possessed, idle):
  - Dummy goblin 10-24 m away: he approached, drew, and shot it 1000 → 291 → dead in about 3 shots, then dashed back to the pawn and stopped.
  - Live goblin pack x3: one Threefold Arrow killed all three.
  - On release: camera back on the Arisen, `LockOnController.Chara` back on the Arisen, his processor enabled.
- **Three fixes found and ported:**
  1. **`app.Player.update` stops calling his `PlayerInputProcessor.update` while a pawn is possessed.** There were 0 calls in 584 frames, even with `IsEnable` true, and DPC also re-disabled it every frame. The brain now runs his processor itself from an `app.Player.update` pre-hook. That hook is registered after the native hook, so the pawn's processor has already run that frame. It is skipped if the game ran his processor in the last 0.25 s. DPC keeps `IsEnable` true while the brain is on.
  2. **Lock-on is required for hits and skills.**
     - Without-aim shots and archer skills take their target from `LockOnController` and the camera.
     - A/B on the same dummy: lock off gave 0 damage in 15 s; lock on killed it in 3 shots, and Whirling Arrow, Random Shot and Threefold Arrow all fired.
     - **Timing matters:** setting the lock inside his processor's update window was not enough; setting it around `app.Player.update` is.
     - **While possessing,** the controller is shared with the pawn. The brain swaps `Chara` to the Arisen and sets its target for the duration of `app.Player.update`. The post-hook removes it, restores your previous target, and points `Chara` back at the pawn. That was 12,148 restores with 0 errors.
  3. **Turning needs `set_TargetFrontAngleDeg`.** The 0.15 stick push sits inside the dead zone, so a target 98° off stayed 98° off for 12 s. With the angle set, he turns 180° in about 0.5 s.
- **New behaviour: sidestep when not hurting the target.**
  - Arrow tracking showed shots striking the terrain 3-4 m in front of him: a ledge lip, and a wall (the "goblin stuck in a wall").
  - If the target takes no damage for `arisen_brain_stuck_s` (6 s), he strafes 1.5 s at ±65° (alternating sides), then resumes.
  - There is a slider in Tuning.
- **Command file:** no longer floods the log when `DPC_cmd.json` is missing. `json.load_file` logged an error twice a second, 15k lines. DPC now creates an empty file once.
- **Telemetry** adds `lock_sets` and `driven_frames`.
- **Spawn note:** the area around the test save has walls and ledges, so dummies spawned behind cover can't be hit by anyone. Pick open ground, or watch for "reposition" events.


### v0.8.1 (2026-11-10): cleaner window and a test bench
- **The window is regrouped,** top to bottom:
  1. **Possession:** status, Release / Warp buttons, and one button per party pawn. Click a pawn to possess it.
  2. **Main settings:** native controls, Arisen brain (+ skills), "Arisen follows you", and the banner / skill palette / HUD switches.
  3. **Test bench,** open the first time.
  4. **Pawn action buttons.**
  5. **Tuning & experimental:** brain sliders, Thief fallback, control modes, subsystems, Mode 1/3 flags.
  6. **Diagnostics & log.**
- **"Arisen follows you"** now drives both the brain's follow and the classic tether (`arisen_auto_follow`). It is migrated once from `arisen_brain_follow`.
- **Test bench:**
  - Live readout: pawn control path (native frames and errors, or puppeteer), brain mode, target, target HP, distance, facing error, shots, skills, injected frames, errors, and test-enemy counts.
  - Spawn presets (one click), the standard battery:
    - Dummy ahead 14 m
    - Dummy beside 10 m (100°)
    - Dummy too close 4 m
    - Dummy far 28 m
    - Goblin pack x3, Wolves x3, Harpies x2, Ogre
  - **Dummies are `_IsThinkStop`.** They stand still and pawns mostly ignore them, so any damage is the Arisen's.
  - **Custom spawn:** enemy list (goblins, hobgoblin, wolf, harpy, saurian, skeleton, ogre, cyclops, minotaur, chimera; griffins left out on purpose), count, distance, angle, dummy, and around the Arisen or the possessed pawn.
  - **Despawn test enemies** (EncounterDirector's guarded `GameObject:destroy`).
  - **Mark this moment** puts a numbered marker in the log and in the brain telemetry events.
  - Solo brain, brain telemetry and input-log switches.
- **Test hotkeys** (`cfg.test_hotkeys`, on; keys in `cfg.test_keys`): F9 spawns the selected preset, Shift+F9 marks, F10 despawns, F11 turns the brain on/off.
- **Command file** gains `spawn` (`"preset":N`, or `cid` / `enemy` / `count` / `dist` / `angle` / `still` / `around`), `despawn` and `mark`. The ack now reports test-enemy counts.


### v0.8.0 (2026-11-10): the Arisen fights like a pawn while you possess one (Archer)
- **Goal:** while you possess a pawn, the Arisen behaves like an Archer pawn: stays at range, shoots your target or the nearest enemy, uses his equipped skills on a cooldown, follows you, and obeys Wait/Come.
- **Approach: the Arisen runs his own player controls on synthetic input.** DPC used to block his `app.PlayerInputProcessor` and `app.Player.updateSequenceBuffer` while possessing. When the brain is on, both run, and the pre-hook of his processor's `update` replaces his `CharacterInput` with the brain's input: `ButtonOnFlags` / `ButtonTriggerFlags` / `ButtonReleaseFlags` and the left stick (`setAxisL` + `set_AxisMagnitudeL`). The game then does everything a player would get: weapon draw, Job02 shots with real arrows, stamina and combos.
- **Verified live on an Archer Arisen, unpossessed, through the bridge prototype:**
  - Synthetic `AttackS` pulses → `Locomotion.DrawWeapon` → `Job02_NormalShootWithoutAim`, one `ShellManager` shell per press, and goblin HP 1000 → 536 → 72 → 0, each drop ~0.2 s after a shell.
  - With the pawns 17 m away, a goblin 100° to his side was turned to and killed with 3 arrows.
  - Back-off: a goblin spawned 4 m away. He retreated to 7 m, turned and killed it.
  - Stick movement: about 8.7 m in 2 s.
- **Gotchas found:**
  - **Floats only for `System.Single` args.** `set_AxisMagnitudeL(1)` with a Lua integer arrives as ~0 and nothing moves; `1.0` works.
  - **Writing input in pre-`UpdateBehavior` does nothing for the Arisen.** His processor runs later inside `app.Player.update`, so the write has to go in its pre-hook.
  - **`AimTargetPosition` is cleared by the processor every frame and does not steer without-aim shots.** The shot flies straight ahead of him, so the brain turns him with a light stick push until he is within 6° of the target before pressing attack.
  - **The without-aim target finder is camera based** (`LockOnController.findTargetBasedOnCamera`). A goblin standing 1.1 m above him, outside the camera's view, was missed repeatedly. While you possess a pawn, the camera is yours, so his arrows should home on what you look at.
  - **Do not hook `LockOnController` finders.** A probe that did hung the game (an `InvalidOperationException` inside a hook that runs under `FindTargetMutex`).
- **What changed in DPC:**
  - New brain module and `brain_tick` in the main tick (step 6), with the `brain_inject` call in the processor hook (1a).
  - 1b (sequence buffer) no longer blocks while the brain runs.
  - **HUD redirect hooks 2a/2b/2c** (`getSkillID` / `get_Job` / `getWeaponJob` returning the pawn's values for the Arisen) are skipped while the brain runs, so his processor picks the Archer detail and his real skills. `cfg.arisen_brain_keep_hud_redirect` puts them back.
  - **Edge detection for your keys:** `UserInput.update` copies `OldButtonOnFlags = ButtonOnFlags`. The brain overwrote those flags, so DPC now rebuilds trigger and release edges for the pawn from the hardware on-flags it saw last frame. Without this, held keys would re-trigger.
  - The mirror's stick fallback that reads the Arisen's `CharacterInput` axis is skipped while the brain runs, because that axis is the brain's.
  - The tether's selector-based follow is skipped while the brain runs; the brain follows with the stick and dashes past 14 m. Auto-warp and Wait/Come stay in the tether.
  - `release_possession` stops the brain immediately.
- **Config (all new keys get their defaults on load):**
  - Switches: `arisen_brain` (on), `arisen_brain_any_job` (off, which means Archer only), `arisen_brain_skills`, `arisen_brain_follow`, `arisen_brain_telemetry`.
  - Archer band: `arisen_brain_keep_min` / `keep_max` 7 / 20 m.
  - Timing: `shot_cd` 0.9 s, `skill_cd` 7 s, `skill_hold` 0.5 s.
  - Facing: `face_tol` 6°, `turn_mag` 0.15.
  - The DPC window has checkboxes and a status line, and the possession banner shows the brain's state.
- **Telemetry:** `reframework/data/DPC_arisen_brain.json`, twice a second. It holds the mode (approach / backoff / turn / engage / skill N / follow / wait / idle), target and HP, distance and facing error, the synthetic buttons and stick, shot and skill counts, the Arisen's FSM nodes (layers 0 and 1), errors, and the last 40 events.
- **Dev command file:** `reframework/data/DPC_cmd.json` with `{"id":"<new>","cmd":"possess","idx":0}`, `release`, `solo` (`"on":true` drives the Arisen with nothing possessed), or `set` (`"key","value","save"`). The result goes to `DPC_cmd_ack.json`. The first file seen after a script load is treated as stale and skipped.
- **Not verified yet (needs a possessed session):**
  - Skills: `SkillN + Shift1 + Shift2` held 0.5 s, which is what the game produced for skill presses on the pawn's processor. Archer aim skills may want a different hold.
  - Whether his processor and the pawn's processor sharing the rebound `LockOnController` changes your lock-on.
  - Whether the HUD keeps the pawn's skill labels with the redirects off.
  - Whether zeroing his right stick (`<AxisR>k__BackingField`) is needed. If that write fails, it switches itself off.

### v0.7.4-0.7.6 (2026-11-09)
- v0.7.4: migration re-ticks the Mode 2 puppeteer boxes (Thief fallback was uncontrollable with them off).
- v0.7.5: the pawn's processor updates inside the Arisen's `app.Player.update` pre-hook (the game's input slot); this ended the Fighter/Thief native crashes.
- v0.7.6: teardown hooks release possession before the scene unloads (return-to-title crash at DD2.exe+0x5246c38); untested.

### v0.7.2-0.7.3 (2026-11-09): Thief crashes under native controls; Thief falls back to Mode 2
- **Three crashes, all in Thief combat with native controls on**, 10-50 s into fights, each at a different site:
  1. An engine worker thread in `memmove` with a null source.
  2. A worker thread executing heap memory (DEP, call through a corrupt pointer; return address DD2.exe+0xfbb00).
  3. `via.effect.script.ObjectEffectManager2.start` → `createProviders` → `findChildrenRecursively` → `List<GameObject>.InsertRange`.

  Different sites each time points to memory corruption or a use-after-free, not one bad call. Fighter and Mage have had long native sessions with no crash.
- v0.7.2: the native processor now shares the Arisen's `LockOnController` (already rebound to the pawn, and kept updated by `app.Player`) instead of an orphan one. This didn't fix it (crash 3).
- PawnTacticalWheel marks nearly every Thief skill `target = "enemy"` and gives the pawn an `AITarget` before ordering it. Thief skills seek a target far more than Fighter or Mage moves, so a target path that works for `app.Player` but not for a pawn is the lead.
- v0.7.3: `cfg.native_skip_thief` (default on) makes Thief pawns use the Mode 2 puppeteer. The Thief Mode 2 baseline still has to be checked for stability.

### v0.7.1 (2026-11-08): native processor setup fixed
- `app.PlayerInputProcessor.setup` is `setup(app.Character, app.PlayerTrack)`. The bare `setup()` from v0.7.0 was rejected by REFramework ("Invalid number of arguments passed to REMethodDefinition::invoke") and skipped, so every pawn's processor ran half-initialized. Fighter and Mage worked because Param was filled by hand.
- Context: v0.7.0 crashed about 37 s into possessing a Thief, on an engine worker thread (`c0000005` in `vcruntime140!memmove`, nearest DD2.exe symbols near `+0x5244xxx`), not inside DPC or the processor. That is the same code region as the unattributed Oct 31 crash (`DD2.exe+0x52345ae`), so the link to the half setup is unproven.
- Native release just drops references (`:release()` logged "not managed by our Lua state").
- Verified: possessing Thief, Mage and Fighter logs no warnings. A longer Thief session is still pending.

### v0.7.0 (2026-11-08): native Arisen controls, play-tested on Fighter and Mage
- **The possessed pawn runs its own `app.PlayerInputProcessor`.** This is the Arisen's input-to-action layer, with every vocation's combo, cancel, skill and spell rules (`Job01..Job09InputProcessor`). DPC drives it each frame (`pcall(pip:update)`) right after mirroring the player's buttons and stick into the pawn's `CharacterInput`, and skips its hand-built Mode 2 movement and combat. Play-tested: Fighter walk, sprint, jump, combos, dash attack, guard, Burst Strike, Flawless Guard, Shield Pummel, Launchboard, Full Moon Slash, Riotous Fury; Mage spellcasting. Toggle: `cfg.native_controls`, a checkbox in the DPC window, default on.
- **Build:** `sdk.create_instance("app.PlayerInputProcessor")`, then `set_Chara/Human/PlayerTrack` (pawn `Human.Track`), copy `Camera` from the Arisen's processor, then `setup()` and `selectProcessor()` (it picks the job's Detail from the Human; DPC calls it again on vocation change). Then fill `Param` by hand: `Chara`, `Human`, `PlayerTrack`, and a new `app.LockOnController` (a plain object: `.ctor` + `setup(pawn, arisenLock.<ParamList>)`). Point every `DetailInstances[i].Param` at `pip.Param`; on the Arisen they all share it, while a fresh processor leaves them nil. `Param.Player` stays nil, and no crash has been seen without it so far.
- **Never attach it with `Character:setInputProcessor(pip)`.** The engine then calls `update()` itself and crashes that same frame in `app.LockOnController.clearLockOnIfNeeded` (this == null), before Param was filled. Driving it from Lua avoids that, and an exception falls back cleanly: after 5 errors DPC switches to the Mode 2 puppeteer for that possession.
- **Timing matters.** Run it in pre-`UpdateBehavior`, after the mirror. In post-`UpdateBehavior` the pawn's input has already been cleared, so nothing happens.
- **Pawn idle sit blocked.** Pawns get `HumanActionSelector.requestAction("LivSitOnTheGround")` about every 3 s while standing (no mod sends it). The Arisen never does. A pre-hook drops `LivSit*` requests for the possessed pawn's selector only.
- **Keys 1-6** are fed to the native processor as `SkillN + Shift1 + Shift2`, the input the game itself produces for a skill press.
- The Arisen `PlayerInputProcessor.update` block now only skips when the address matches a known Arisen processor, so it never blocks the pawn's own processor.

### v0.6.2 (2026-11-08): native HUD as the Arisen, 6 skill slots, Fighter combat feel (verified live)
- **Native HUD follows the pawn.** The HP/stamina gauge (`app.ui020901`), player gauge (`ui020401`) and minimap (`ui020301`) get `PlChara`/`PlHuman` set to the pawn plus their setup calls (`setupHpGauge`, `setupStGauge`, `setupStatusIcon`, `setupAction`, `NeedForceUpdate`) on possess or switch, and are restored to the Arisen on release. They are re-checked every 0.5 s. Verified: the stamina bar drains for the pawn on sprint and skills (Flawless Guard ~140, Burst Strike ~130 of 966).
- **Native button guide shows the pawn's skills.** `ui010201.isInputCustomSkillShift(bool)` is post-hooked to return true while the DPC skill-shift (Shift1 / Ctrl) is held. The guide was already bound to the pawn, but it reads shift from the pawn's AI-driven `PlInput`, so it never switched pages. "Defend / Onslaught / Impale..." was the correct Fighter base page.
- **setupPlChara hook fixed.** The post-hook used `args` (always nil in a post function), so it never ran. `this` now goes through `thread.get_hook_storage()`.
- **Localized, level-aware skill names.** `app.GUIBase.getCustomSkillName(JobEnum, HumanCustomSkillID, HumanCustomSkillLevelNo)` with the level from `HumanSkillContext:getCustomSkillLevel(id)`. The two-argument overload returns `<REF job03_skill_00_lv2>` for High Flagration, so the job overload comes first. Enum names were internal (BlinkStrike = Burst Strike, FullMoonGuard = Flawless Guard, CymbalAttack = Shield Pummel, Springboard = Launchboard, Firestorm = High Flagration).
- **Skill slots 5 and 6.** `getSkillID(job, 4/5)` and the `Skill5` (27) / `Skill6` (61) actions exist (e.g. Full Moon Slash, Riotous Fury). DPC read slots 1-4 only. It now reads 6, triggers on Skill5/Skill6 plus keys 5/6, and lists them when equipped.
- **Light-attack combo.** Each press called `requestNormalAttack`, which restarts at hit 1, so mashing reset the chain. A press during a swing is now held until `HumanActionSelector:get_NextComboAction()` is non-empty (the combo window, at most 0.45 s) and then sent. Play-tested: mashing and timed presses chain.
- **Movement no longer cancels attacks.** Locomotion/idle requests are skipped while the FSM layer-0 node is not `Locomotion.*`, and the stick only steers. `app.Character:isIdle()` is **false even while standing**, so it can't be used for this.
- Keyboard skill keys are no longer gated on `is_drawing_ui` (note: the REFramework menu takes the keyboard anyway, so play with it closed). Mouse buttons stay gated.
- `cfg.debug_input` (default off) logs input edges, attack decisions and per-frame attack FSM changes.
- **Stamina was never broken.** An earlier bridge test had left the gauge bound to Yenn, so the Arisen's bar looked frozen. In towns sprinting is free by design (`HumanStaminaController.isInfinityDashTownArea`).

### v0.6.1 (2026-11-08): ROOT CAUSE of the "far from Arisen" CTD found live
- **Repro (bridge distance recorder, 0.5 s samples):** the auto-warp fired once at 38.6 m, as v0.6.0 intended. The Arisen's position then read `x = 7,296,680,722,432, y = -1, z = 0` and it fell from there (y -1 → -17 over 1.5 s). DD2 crashed 2.2 s after the warp (`c0000005` in DD2.exe). The last DPC trace step was a camera re-register.
- **Cause:** `PawnManager:safeWarp(app.Character, via.Position)` was passed `transform:get_Position()`, which is a float `via.vec3`. `via.Position` is the double-precision **universal** position, so REFramework passed the bytes through unchecked and the engine read garbage. The call "succeeded", so the local-warp fallback never ran. The upstream Dimension Door field note already documents this: use `transform:get_UniversalPosition()`.
- **Fix:** pass `get_UniversalPosition()`. Every warp is now verified 0.3 s later; if the Arisen is more than 60 m from the target (or NaN), it gets a local `warp(via.vec3)` next to the pawn instead.
- **Wait / Come** pawn-command inputs now control the Arisen while possessing (Wait = stay, Come = follow; shown in the status banner). The auto-warp past 35 m still applies, because it is what stops the party leash.
- PawnCommander v2.4.1 had the same `safeWarp` bug in "Warp to me", and it's fixed there too.

### v0.6.0 (Stability pass, 2026-11-06, untested in-game)
- **Distance CTD suspect: auto-warp storm.** `update_arisen_tether` re-warped the Arisen every frame while `dist_xz > 35` or `|dy| > 25`, until the warp settled, and also during jumps, falls and monster climbs. Now the condition has to hold for `arisen_warp_delay` (1.0 s), with a cooldown of `arisen_warp_cooldown` (4 s) between warps. Set `arisen_warp_dist = 0` to disable it entirely when bisecting the crash.
- **Auto-follow strafed.** It passed `is_dash` as the `is_strafe` argument of `requestLocomotionImpl`. It now passes `false` and applies the Arisen dash flags (same root cause as the v0.5.1 sprint fix).
- **Release spam.** `requestRelease`/`requestShoot` fired every frame after 0.35 s, because `cast.released` was never checked. Release now fires once, with up to 3 retries spaced 0.4 s apart. Spells (Mage/Sorcerer) release when `isReadySpellAction` reports ready and the slot isn't held, with a `spell_release_fallback` (2.5 s) fallback. Other skills release when the slot button is let go.
- **Cast slot** is found from the pawn's equipped skills (it was reset to slot 1 whenever `CustomSkillState` differed from the requested id).
- **Fewer per-frame engine exceptions.** The `requestLocomotionImpl` signature is cached after the first success, and it backs off for 5 s if every form fails. The skill-context getter (`get_SkillContext` vs `get_HumanCustomSkillContext`) is probed once and logged. Job and skills refresh every 0.5 s.
- **Hot hooks** (`getSkillID`, `get_Job`, `getWeaponJob`, PIP `update`) compare `sdk.to_int64(args[2])` against cached addresses instead of calling `to_managed_object` + `pcall(get_address)` on every call.
- **Thread safety.** `re.on_frame`/ImGui now only read `ui_cache`, which is filled in `UpdateBehavior` (party list, HP, skill state, weapon drawn, camera target). This removes the render-thread toggling of `in_internal_query`.
- **Key edges** come from one snapshot per frame (`poll_keys`), so early returns no longer leave stale edges.
- **Tick errors** are logged (rate-limited) instead of silently swallowed by `pcall`.
- Evidence behind this pass: `re2_framework_log.txt` (Nov 1) has ~450 caught `via.Component.get_GameObject` `InvalidOperationException`s and ~300 `GetValue` `ArgumentOutOfRangeException`s. Upstream UniversalModder (Pactblade note) documents this class of error ending in a crash seconds later. `reframework_crash.dmp` (Oct 31, 4:55 PM) is an access violation reading `0xFFFFFFFFFFFFFFFF` at `DD2.exe+0x52345ae`, ~30 min after the v0.5.4 edit. It can't be attributed without symbols.

### v0.5.4 (Native HUD Skill Palette Redirection & Arisen Save Safety)
- **Root Cause (Skills staying on Arisen & campfire fix required):** `apply_native_hud_skills` was calling `HumanSkillContext:setSkill(job, skill_id, slot)` on the Arisen's persistent skill context. Calling `setSkill` writes directly to player save data in memory. On unpossessing, it only attempted to restore `orig.job` (Archer) and never restored `p_job` (Fighter), leaving Fighter skills permanently equipped on the Arisen. Furthermore, if skills were locked on the Arisen (Full Moon Guard & Springboard), `setSkill` rejected them, resulting in only unlocked skills (Burst Strike & Shield Pummel) being equipped.
- **Root Cause (Skills grayed out):** The native keyguide HUD (`app.ui010201:isDisableCustomSkill`) evaluates whether the character can use the custom skill with their currently equipped weapon. Because the Arisen held a bow, sword skills were flagged as disabled/grayed out.
- **Architectural Fix:**
  1. **Zero Save Data Mutation:** Completely removed all calls to `sc:setSkill()`. The Arisen's `HumanSkillContext` is never touched or mutated under any circumstances.
  2. **Native KeyGuide Widget Redirection:** While possessed, `app.ui010201` (`GuiManager.KeyGuide`) widget pointers (`PlChara`, `PlHuman`, `SkillContext`, `Job`, `WeaponJob`, `PlInput`) are redirected to point to the possessed pawn, followed by calling `setupCustomSkillMsgId()` and `setupCustomSkillButton(true)`.
  3. **No More Grayed-Out Skills:** Hooked `app.ui010201:isDisableCustomSkill` to return `false` while possessed, ensuring all 4 of the pawn's equipped skills display in full color with active icons.
  4. **Clean Instant Reversion:** On returning to the Arisen (or unpossessing), `ui010201`'s pointers are cleanly restored to the Arisen with zero lingering state or save corruption.


### v0.5.3 (Fighter "Defend" — Verified Native Action + Guard-Walk)
- **Root cause:** `pawn_set_fighter_guard` requested `"Guard01"` (+ `startAscertain`). That node does not exist in the Fighter pawn behavior tree, so all requests were silently ignored — the pawn only drew its weapon.
- **Discovery:** `PawnDefendProbe.lua` (now also `dd2-modkit/dd2_modkit/telemetry/lua/pawn_action_spy.lua`) hooked `app.ActionManager.requestActionCore` and caught the pawn AI defending naturally: `SEL.requestAction("Job01_Guard", 0xFFFFFFFF)` → layers 0+1, engine switches layer 0 to `Locomotion.Strafe`, layer 1 stays `Job01.Job01_Guard`, `IsGuard=true`; release `Job01_GuardEnd` on layer 1.
- **Fix:** RMB/LT hold → `requestAction("Job01_Guard", 0xFFFFFFFF)` (only re-requested when upper-body node isn't `Job01_Guard`); release / unpossess → `requestAction("Job01_GuardEnd", 1)`.
- **Guard-walk fix:** locomotion was fully suppressed while `is_guarding`, locking the pawn in place. Now keeps requesting `requestLocomotionImpl(SPEED_WALK, true)` (Strafe, layer 0) with shield facing camera-forward and stick steering; on stop requests Strafe at `SPEED_IDLE`.

### v0.5.2 (Fighter Shield Guard & Native Skill HUD Resolution)
- **Resolved Right Click / Left Trigger Hijacking Weapon Skill Mode:**
  - **Root Cause:** When the Arisen is an Archer (or other ranged vocation), DD2 maps Right Mouse Button / Left Trigger to `Shift1OnlySpecificJob` (`Action 30`) or `AimHold`. In `DirectPawnControl.lua`, line 1423 had `shift_skill_mod = is_on("Shift1") or is_on("Shift1OnlySpecificJob") or is_on("Shift2")`. Holding RMB/LT set `shift_skill_mod = true`, tricking the puppeteer into believing Right Shoulder / Left Ctrl was held. This intercepted all subsequent inputs as custom skill shortcuts and suppressed Fighter Shield Guard (`pawn_set_fighter_guard`).
  - **Fix:** Removed `Shift1OnlySpecificJob` and `Shift2` from `shift_skill_mod`. `shift_skill_mod` is now strictly `is_on("Shift1") or (not ui_open and is_key_down_safe(0x11))` (RB on controller or Left Ctrl on keyboard).
  - Routed `Shift1OnlySpecificJob`, `JobSpecialAction`, `AimHold`, `is_key_down_safe(0x02)` (RMB), and controller LT directly into Vocation Action handling.
  - For Fighter pawns (`Job 1`), holding RMB / LT now cleanly activates and maintains Shield Guard (`Guard01` / `Guard01End` + `startAscertain`), with guard-walk support and instant recovery after light attacks.
- **Resolved Native Skill HUD Palette Reflection:**
  - **Root Cause 1:** `apply_native_hud_skills` previously attempted to call non-existent method `sc:call("setSkillID", ...)`. The true RE Engine method is `app.HumanSkillContext:setSkill(JobEnum job, HumanCustomSkillID skill_id, SkillSlot slot)`.
  - **Root Cause 2:** The native HUD queries `app.JobContext:get_Job()` and `app.Character:getWeaponJob()` to determine which vocation palette to render. When the Arisen is an Archer, the HUD queried Archer skills.
  - **Fix:** Installed thread-safe hooks on `app.JobContext:get_Job()`, `app.Character:getWeaponJob()`, and `app.HumanSkillContext:getSkillID(job, slot)` so native HUD queries see the possessed pawn's vocation and equipped skills. Added `app.GuiManager:setupKeyGuideCustomSkill()` call to refresh native HUD keyguides immediately upon possession.

### v0.5.1 (The True Sprint Breakthrough: Decoupled is_strafe & Player-Accurate Dash Stack)
- **Breakthrough Finding — `requestLocomotionImpl(speed_type, is_strafe)` Second Parameter:**
  - Captured native telemetry during `PawnOrder.Come` (`sprint_ai_tap_log.json`): pawns hit **`10.42 m/s`** peak speed with animation clip `Bank#SPRINT`.
  - Evaluated `HumanActionSelector:getMoveAction`:
    - `getMoveAction(3, false)` returns **`"NormalLocomotion"`** (forward sprint at >7.0–10.4 m/s).
    - `getMoveAction(3, true)` returns **`"Strafe"`** (combat sidestep, which clamps speed to ~3.47 m/s).
  - Previously, `is_dash = true` was passed into `requestLocomotionImpl(3, true)`, commanding the pawn to **strafe** instead of sprinting forward!
- **Implemented Full Player Sprint Stack:**
  - In `DirectPawnControl.lua` and `PawnSprintDeepTest.lua`:
    - Fixed `safe_request_locomotion(sel, speed_type, is_strafe)` to pass `is_strafe = false` during all forward locomotion (walk, run, sprint).
    - Reserved `is_strafe = true` strictly for when aiming a bow (`is_aiming`) or holding shield guard (`is_guarding`).
    - Synchronized native character sprint state: `Human:set_IsDash(true)`, `Human:set_IsPrevDash(true)`, `Human:notifyKeepDash()`, `Character:setLocomotionSpeed(3)`, and `Character:set_DiscreteLocomotionSpeedType(3)`.
    - Corrected `HumanCommonActionController:requestMoveSpeedOfNormalLocomotion` from erroneous `2.0` clamp to normalized `1.0`.
- **Created Decisive 6-Recipe Sprint Benchmark Battery:**
  - Standardized `PawnSprintDeepTest.lua` (`v1.3.0`) with a clean automated 6-recipe battery directly comparing walk, run, flawed strafe dash, native sprint, and player-mirrored sprint in a single automated pass.

### v0.5.0 (Skill HUD Sync, Vocation-Accurate Fighter Defend, Spell Release Completion & Full Sprint)
- **Fixed Issue 1 — Dynamic Skill UI Labels (Native DD2 HUD Hook + Bottom-Right ImGui Skill Palette):**
  - Hooked `app.HumanSkillContext:getSkillID(job, slot)` on the Arisen (`state.arisen_skill_ctx`) while `state.active` is true, and mirrored the possessed pawn's equipped skill IDs onto the Arisen's active skill context slots during possession (restoring the Arisen's original skills upon release) so the native DD2 bottom-right skill HUD displays the possessed pawn's skills.
  - Added a toggleable bottom-right ImGui Skill Palette HUD (`cfg.skill_hud_overlay`) showing the possessed pawn's name, vocation, all 4 equipped skills (`[1 / L1+X]..[4 / L1+A]`) with live active/chanting highlight, and Vocation Action (`[LT / RMB] Defend (Shield Guard)` / `Quickspell` / `Swift Step` / `Steady Shot`).
- **Fixed Issue 2 — Fighter "Defend" (Shield Guard) & Vocation-Accurate Controls:**
  - Root cause in `v0.4.0-poc`: `is_trg("JobSpecialAction")` (`Action 29`, Left Trigger / Right Mouse / Vocation Action) and raw `key_pressed(0x02)` (`RMB`) were routed into `pawn_do_attack(true)` (`requestSubNormalAttack`), which is Fighter's Heavy Attack (`Empale`) instead of Shield Guard (`Guard01`).
  - Disabled raw `LMB`/`RMB` overrides by default (`cfg.raw_mouse_fallback = false`) so the player's actual DD2 bindings in `app.UserInput` are respected.
  - Routed `AttackS` (`Action 1`) -> Light Attack (`requestNormalAttack` + `requestComboAction`), `AttackL` (`Action 2`) -> Heavy Attack (`requestSubNormalAttack` + `requestComboAction`), and `JobSpecialAction` (`Action 29`) per vocation:
    - **Fighter (`Job 1`):** Hold-to-Defend (`requestAction("Guard01", 0)` / `setAction("Guard01", true, 0)` + `Job01ActionSelector:startAscertain()`; releases with `Guard01End` + `requestEndAction()`).
    - **Archer (`Job 2`) / Magick Archer (`Job 8`):** Hold-to-Aim (`requestAimAction`) and `AttackS` to loose arrows (`requestShoot()`).
    - **Mage (`Job 3`) / Sorcerer (`Job 6`):** Hold while chanting for Quickspell (`Concentrate`), or press while idle for `Anodyne` / `Galvanize`.
    - **Thief (`Job 4`):** Swift Step (`DodgeOfRing`).
- **Fixed Issue 3 — Mage & Sorcerer Spell Casting Completion (Two-Phase Chant -> Release):**
  - Root cause: `requestCustomSkill` initiates the spell chanting action (`Job03_Concentrate` / `CustomSkillState == skill_id`), which loops in the spell-ready state waiting for `sel:requestRelease()` / `sel:requestShoot()`.
  - In `DirectPawnControl.lua` (`v0.5.0`): Rebinds `LockOnController.Chara` to the possessed pawn and calls `updateTargetWhenUnlock()` / `updateSpellTarget()`, checks `CurrentSelector:isReadySpellAction()`, and calls `sel:requestRelease()` + `sel:requestShoot()` automatically once the chant is ready (unless the player holds the skill button to store the cast, or cancels with Jump/Sheathe).
  - Backported two-phase spell auto-release (`phase = "start"` -> `phase = "release"`) to `PawnCommander.lua` (`v2.2.0`) so single-button pawn skill commands automatically release spells as soon as chanting finishes.
- **Fixed Issue 4 — Full-Speed Pawn Sprinting (`Dash = 3`):**
  - Root cause in `v0.4.0-poc`: `app.LocomotionSpeedTypeEnum` defines `Idle = 0, Walk = 1, Run = 2, Dash = 3`, but `v0.4.0-poc` passed `2` (`Run`) when dashing and `1` (`Walk`) when running, never passing `3` (`Dash`).
  - Added latched sprint state (`state.is_sprinting`), enabled `HumanCommonActionCtrl:set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(true)`, passed `requestMoveSpeedOfNormalLocomotion(2.0, true)`, and called `sel:requestLocomotionImpl(3, true)` for full Arisen-speed sprinting.

### v0.4.0-poc (Working Pawn Possession + Combat & Skills)
- **Fixed `app.UserInput` Bitmask Reading (`1 << ActionID`):**
  - `app.UserInput` does not have an `isButtonTrigger(app.CharacterInput.Action)` overload—its signature is `isButtonTrigger(System.UInt64)`.
  - `ButtonTriggerFlags` and `ButtonOnFlags` store 64-bit bitmasks `(1 << ActionID)` (`AttackS=2, AttackL=4, Jump=8, Dash=32, Skill=64, Skill1=128, Skill2=256, Skill3=512, Skill4=1024, Hold=2048, Weapon=8192`).
  - Added direct keyboard/mouse triggers (`LMB`/`RMB`, `Space`, `1–4` / `Numpad 1–4`) when the REFramework UI is closed.
- **Fixed Arisen Intercepting Attacks (`sdk.hook` on `PlayerInputProcessor:update` & `Player:updateSequenceBuffer`):**
  - `app.Player:update()` calls `InputProcessor:update()` and `this:updateSequenceBuffer()` directly without checking `InputProcessor:get_IsEnable()`.
  - Installed `sdk.hook` pre-hooks returning `sdk.PreHookResult.SKIP_ORIGINAL` while possessing a pawn in Mode 2.
  - Preserved `ButtonOnFlags` on `state.arisen_input` at end-of-frame so `UserInput:update()` can copy `OldButtonOnFlags = ButtonOnFlags` on the next frame for accurate edge detection.
- **Integrated `PawnCommander` Skill/Attack Retry Window & Locomotion Suppression:**
  - Automatically calls `requestDrawWeapon()` before `requestCustomSkill` or attack requests if `not chara:get_IsDrawedWeapon()`.
  - Uses a `0.60s` per-frame retry window for `requestCustomSkill(id, 1065353216)` until `human:get_CustomSkillState() == id`, and a `0.30s` retry window for `requestMainNormalAttack()` / `requestSpecialAttack()`.
  - Suppresses `requestLocomotionImpl` for `0.35s–0.45s` after an attack/skill trigger (while still updating `TargetMoveAngleDeg`) so holding `WASD` / Left Stick on the next frame does not cancel weapon draw or attack startup.
- **Added In-UI Direct Action Test Buttons:**
  - Added clickable buttons in the `Direct Pawn Control` ImGui window for `Light Attack`, `Heavy Attack`, `Jump`, `Draw`, `Sheathe`, and equipped skills `[1]..[4]`.

### v0.3.0-poc (Working Camera Switch + Movement)
- **Fixed ValueType (`struct`) Return Marshaling Crash (`<userdata @ 0x0>`):**
  - Discovered via live `bridge eval` that calling `CharacterInput:get_AxisL()`, `get_MoveDir()`, or `CharacterManager:get_CameraFront()` as Lua methods returns `<userdata @ 0x0>`. Passing `0x0` into `pawn_input:set_AxisL(via.vec2)` caused an immediate null dereference CTD on the first tick after pressing `F6`.
  - Switched to reading `UserInput:get_field("<StickL>k__BackingField")` (with WASD fallback) and reading camera forward/right vectors from the active `via.Camera` GameObject's native `Transform:get_AxisZ()` (`-AxisZ` forward) and `Transform:get_AxisX()`.
- **Fixed Pawn AI Suppression Crash:**
  - Removed `via.Behavior:set_Enabled(false)` on `PawnAI` / `NpcController` (which caused null dereferences in `app.Human:update()`), keeping only `PawnActionDecision:set_IsCancel(true)`, `PawnOrderController:set_IsStopCommand(true)`, and `PawnLookAtController:set_LookAtStop(true)`.

### v0.2.0-poc
- **Fixed ImGui Error (`imgui.radio_button` nil):**
  - Replaced unsupported `imgui.radio_button` calls with `imgui.checkbox`.
- **Defaulted to Mode 2 (Safe ActionSelector Puppeteer):**
  - Confirmed that Mode 3 (`addPlayerSelectors()` / `selectProcessor("PlayerInputProcessor")`) crashes immediately on pawns because pawns are `app.Human` (`ch100000_00`), not `app.Player` (`ch000000_00`).

### v0.1.0-poc
- Initial multi-mode probe scaffold (`DirectPawnControl.lua`).
