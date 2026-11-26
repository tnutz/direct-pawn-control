# Direct Pawn Control - Play as Any Pawn. Includes Couch Co-op (Dragon's Dogma 2)

Take direct control of your pawns. Possess your main pawn or a hired pawn and play it with the game's own player controls, camera and HUD, while the Arisen fights on beside you. Or hand friends a controller and play couch co-op: up to four players (more with party mods), each on their own character, the Arisen included.

**Status: beta (0.9.x).** Playable from start to finish of a fight with every pawn vocation. See "Known limits".

## Requirements
- [REFramework](https://github.com/praydog/REFramework) for Dragon's Dogma 2 (nightly build recommended).
- Optional: **Camera Distance & Framing Studio** (included as a separate mod). It keeps both players in view in co-op and adds an off-screen marker. On its own it changes nothing until you pick a camera style.
- Recommended alongside: **Pawn Tactical Wheel**, a radial menu for ordering pawn skills with slow motion. The two mods work together.

## Install
- **Fluffy Mod Manager:** drop the zip into the DD2 mods folder and enable "Direct Pawn Control" (and, if you want it, "Camera Distance & Framing Studio").
- **Manual:** copy the `reframework` folder into the game folder. Since 0.9.178 DPC is `reframework/autorun/DirectPawnControl.lua` **plus** the `reframework/autorun/DirectPawnControl` folder next to it; copy both (an old single-file install is replaced by them).

## Controls
| Keyboard | Controller | What it does |
|---|---|---|
| **F7** | **Hold D-pad left / right** (half a second) | Select the previous / next character. An arrow shows over them and their name appears at the bottom of the screen. While you play a pawn the selection starts on the Arisen |
| **F6** | **L1 + left stick click** | Take control of the selection (a pawn, or back to the Arisen). On the controller, while you already play a pawn: go on to the next character in the party (each pawn in turn, then the Arisen), or to the one you just picked with the D-pad while its arrow is still showing |
| | **Hold D-pad down** while playing a pawn | Back to the Arisen |
| **F8** | | Warp the Arisen to the pawn you are playing |
| **Ctrl+F6** | | Start / stop couch co-op from the keyboard. Player 1 keeps what he was playing on: keyboard and mouse, or his controller if he was on one. The first other controller anyone touches afterwards is player 2's, and L3 + R3 on another controller adds players 3 and 4 |
| | **Hold L3 + R3** (both stick clicks) on another controller, half a second | Join couch co-op as the next player. Held 3 s: leave (player 1 holding it on their controller ends co-op) |
| **Numpad 1-6** | | The selected character uses skill slot 1-6 (the Arisen by default while you play a pawn; never the one you are playing) |
| **Numpad 7** | | Warp all pawns to you (and the Arisen, while you play a pawn) |
| **Numpad .** | | Heal / revive all pawns and the Arisen. A cheat, **off by default**: tick it under Cheats in the settings |

Every key can be changed or cleared (Clear button) in the settings under Controls. Untick **Keyboard shortcuts on** there to use DPC from the controller only; the controller combinations keep working.

- **Bow skills just work (on by default):** special arrows are not used up while you play a pawn, and a played Archer that has none of one kind is quietly given one. Given arrows weigh nothing for whoever carries them, so the weight class never changes; everyone else's arrows weigh what they always did. Switches under Cheats.

### Couch co-op
- **Joining:** whoever plays the Arisen keeps what they play on (keyboard and mouse, or their controller). A friend holds L3 + R3 on another controller for half a second and joins as player 2, then players 3 and 4 the same way. The friend takes the next character: a character player 1 just pointed at with the selection arrow, else the Arisen if player 1 is on a pawn, else the selected pawn. Holding L3 + R3 for 3 s leaves.
- **Who is who:** each player's character glows in their colour when they join (by default player 1 cyan, 2 white, 3 green, 4 magenta; each player can pick their colour under Couch co-op > Player colours, with a Preview button) and keeps glowing while they play it (a tick per player under Couch co-op). A player who leaves flashes red. Each player has a target circle and an off-screen marker in their colour, their own bars (over their character; the game's own bar under a played pawn's name is hidden so there aren't two) and skill list, with their own controller's button names.
- **Changing characters:** each player's take-control combination (L1 + left stick click; F6 for player 1) goes to their next free character, the Arisen included. Whoever plays the Arisen plays him with the game's own controls, player 2 too. When co-op ends, player 1 stays on whoever he was playing.
- **Menus:** whoever opens a menu drives it. Player 1's Options or touchpad (map) opens his; a menu player 2 opens, or gets by talking to someone or at a Rift while he plays the Arisen, stays his to the end. Pressing buttons in the other player's menu shows who controls it.
- **Player cards:** every player gets a small card in a row at the bottom middle of a shared screen (player 1's in place of the game's HUD; in split screen player 1 keeps the game's HUD): a title bar in their colour, health and stamina, their actions and skills on their own controller's buttons (like the game's own palette, the skills show while the skill button is held, and a held button lights up), and their D-pad items. In the co-op settings you can put the cards in a stack at the bottom middle or at the side, or in each player's own spot, give player 1 the game's HUD again, show health and stamina over or under each character, hide the item lines and change the card background, side and height.
- **Items, orders and looting for everyone:** with the skill button held, each player's D-pad uses their own healing (up) and stamina (down) item, from their character's bag first and then the Arisen's; right works the Arisen's lantern. A plain D-pad tap gives the game's pawn order (Go / Come / Wait / Help) to the AI pawns, who answer aloud; Come calls them to the Arisen. Every player's pawn can loot, open chests, gather and pick up with their own Interact button; the prompt shows in their colour.
- **Aiming (on by default):** tap R3 to keep a target, flick the right stick to move to the next enemy on that side, hold R3 to take player 1's target.
- **Split screen (early release, off by default):** every player gets their own view: two side by side or top and bottom, three across or in a grid, four in a grid or across. Turn it on with **Split screen (early)** in the co-op camera row at the top of the settings; its own options are under REFramework menu > Script Generated UI > DPC Split Screen. Each player's right stick turns their own camera, each can pick their own Camera Distance preset (Monster Hunter, Wide Combat and the rest), and the sound can come from between the players or from player 1. Player 1 keeps the game's own HUD, fitted to his view; the other players get their cards in their own view. Menus, talks and cutscenes go back to one view. See "Known limits" for what isn't finished.
- **Camera:** every player's right stick turns it (a slow push; a quick flick switches target), whoever plays whom. Ticks per player under Couch co-op. With Camera Distance installed the camera keeps everyone in view, climbs and cranes up against walls, and drops back to the normal camera in the Rift.
- Two PlayStation controllers, PlayStation and Xbox controllers mixed, all work. Turn **Steam Input off** for Dragon's Dogma 2, or Steam merges the controllers into one and players can't be told apart.
- Player 2's controller rumbles (on by default).
- **Co-op comes back by itself** after a Ferrystone, a cutscene or a loading screen, with everyone on the character and controller they had (players 3 and 4 may land on a different pawn). Ending co-op yourself ends it for good. Switch: "Resume co-op by itself".
- Pawn Tactical Wheel's controller button (L1 + R3) is kept shut while co-op runs, so it doesn't pop open for other players; its keyboard key still works.
- **The controller you pick up drives the Arisen.** The game listens to one "active" controller and does not switch by itself, so a controller that went off, or a second one left connected, could leave the Arisen ignoring the one in your hands while the keyboard still worked. The mod hands the Arisen to the controller you use (switch: "The controller you use drives the Arisen").
- Any key can be given Ctrl: hold Ctrl while you press the new key.
- These are the defaults. Every keyboard key above (co-op and the six skill orders included) and three controller combinations (take control / next character, back to the Arisen, couch co-op) can be changed under **Controls** in the settings window. There is also a switch there to keep the Arisen out of the take-control round.
- A line at the bottom of the screen says what the take-control button does right now and to whom ("L1+L3: Control <pawn>", "Hold D-pad down: Control Arisen"). It follows the keyboard or the controller, whichever you last used, and can be switched off under Controls.
- A **tap** on the D-pad is still the game's pawn order. A **hold** that selects or switches does not give the order. D-pad up is left entirely to the game (Go, and hold for Explore). As the Arisen, holding D-pad down is still the game's High Five.
- While you play a pawn it uses your normal controls (keyboard and mouse or controller): attacks, vocation action, all six skill slots, jump, sprint, grab, and the health and stamina item shortcuts. The lantern shortcut works the Arisen's lantern and your pawn's follows it.
- Your pawn reads its own attack and skill state the way the Arisen does, so the game's own cancels, combos and input windows work for every vocation, including vocations added by other mods. Its lock-on is measured from the pawn, not from the Arisen, so attacks and skills like Blink Strike go for the enemy in front of you.
- Controller rumble comes from the character you play (the game only rumbles for the Arisen).
- With player 1 on keyboard and mouse, the game's button prompts stay keyboard prompts when other players use controllers (they may flicker while a controller turns the camera).
- Remapped controls are fine. The mod reads the game's own controller and keyboard settings instead of assuming the defaults. If one of the mod's own keys (F6, F7, F8, the number pad) is also bound to something in the game, the settings window says so.
- In co-op, player 2's buttons follow the controller layout set in the game's options, remapped or not: every action sits where the game shows it.

When control changes hands, the camera pulls back so both characters are in view, the action slows for a moment, and the camera glides in behind the one you now play while they light up with one of the game's own glows. Full speed returns just before the camera lands. Under **Switching characters** you can pick another camera style (Instant, Establish, Bird's-eye or Custom), the slow-down, when full speed returns, and the glow (Pawn lift by default; Revival, Can interact, Riftstone, Summon, Healing, Astral or none).

Open the REFramework menu (Insert) and look for **Direct Pawn Control** to change options. The main choices are at the top as rows of buttons (the co-op camera, camera turning, two controllers, what the Arisen does while you play a pawn, how switching characters looks); everything else is in folders named for what they hold. The co-op folder is split into settings for both kinds of co-op camera, the shared screen only, and split screen only. Outside that menu the mod puts very little on screen: one line saying who you are playing or have selected, the Arisen's bars over his head, and in co-op player 2's bars and skill list.

## Playing a pawn feels like playing the Arisen
While one player plays a pawn, the game treats the pawn more like the player:
- A Mage you play puts her boons and other support spells (Holy Affinity, the healing spot, the party heal) on the ally you are looking at, players and AI pawns alike, as the Arisen does with his reticle.
- **Sound:** the pawn gets the player's sound settings, sounds get quieter by distance from the camera rather than from the Arisen, and echo / ambience follow the pawn.
- **Skill slow motion:** skills that slow the world for the Arisen (Riotous Fury, for example) do it for the pawn too.
- Hit-stop and perfect-block slow motion already worked for a pawn.
These are under "Playing as the player" in the settings, each with its own switch.

## What your pawn can do while you play it
- Loot corpses (monsters and enemies, bandits and other hostile people included), open chests, gather and pick things up: press interact when the mod's prompt shows over the object (in your player colour, with your button). Items go to the pawn's inventory, or to the Arisen's if you tick "what the pawn picks up goes into the Arisen's bag" under Features.
- Revive a dead person with a Wakestone: the prompt says "Revive ... (Wakestone, by the Arisen)". Press once, then again to confirm: the Arisen comes over and does the game's own revive. Only out of battle, only for player 1, and only with a Wakestone (or Forgery) in the bag.
- The Arisen's own loot / talk / examine prompts are hidden while you play a pawn, so his button can't do something behind your back.
- Wake a sleeping companion, and revive a downed pawn by holding interact (a ring fills, as for the Arisen).
- An Archer pawn gets the bow aim camera and reticle while you hold aim, turns with the camera and shoots at the reticle. On a controller, the aim button + a skill button fires the aimed form of that skill. Skills used from the hip fire as they do for the Arisen. Shots from the hip home in on what you look at, like the Arisen's; the Arisen keeps a lock-on of his own while he fights by himself.
- If the pawn was leading the way to a quest when you took it over, the guiding stops so it does not pull against you.

## What the Arisen does while you play a pawn
He fights on his own, follows you outside of battle, and cannot die while you are away from him (an option, on by default). His health and stamina show over his head.

| Arisen vocation | What he does |
|---|---|
| Archer | Keeps his distance, shoots, uses his skills, holds fire when a wall is in the way |
| Fighter, Warrior, Thief, Mystic Spearhand | Closes in, attacks in chains, uses his skills. No guarding or dodging yet |
| Mage | Buffs first, heals whoever is hurt (the pawn you play first), attack spells with magick bolts in between |
| Sorcerer | Attack spells in turn, Quickspell while incanting, magick bolts in between |
| Trickster | Keeps the simulacrum out, throws and swings the censer, uses his skills |
| Magick Archer | Shoots and uses his skills without aiming; switches Conversion mode by the number of enemies. Remedy Arrow: he fires it at a downed pawn and the mod completes the revive (an assisted option, on by default) |
| Warfarer | Fights by the rules of the weapon he is holding and swaps weapons with Rearmament every 20 seconds (option and slider in the menu; Rearmament must be in a skill slot) |

Wait and To Me orders tell him to stay or follow again. A caster Arisen answers Help by coming to heal you.

## Known limits
- Talking to people, vocation guilds and other menus belong to the Arisen; F8 brings him to your pawn, then switch back. A Wakestone revive from your pawn is done by the Arisen (he is brought over), without the game's "use a Wakestone?" menu: the second press is the confirmation.
- Looting, gathering, chests, waking and reviving by your pawn happen without the usual animation.
- The Arisen does not aim. A Magick Archer or Archer Arisen shoots at what he has locked on to. The Arisen's melee vocations do not guard or dodge.
- The bow aim camera and reticle are for Archer pawns in normal possession, not in co-op. Aimed skills for a bow pawn are on the controller only.
- Quick skills (Numpad 1-6) cover the six pawn vocations; attack skills need an enemy in view or near the pawn.
- Possessing a pawn far away from the Arisen for a long time is not recommended.
- A pawn that is leaning, sitting or bathing (the hot spring) stands up first when you take it over; in the hot spring the Arisen's own "Stand Up" prompt follows the game's controller.
- While you play a pawn, the button guide does not show "Dash" on its button. Dashing works as usual; only the label is missing.
- **Dullahan / Skill and Vocation Creator:** while you play a pawn, the mod pauses Dullahan's Rearmament option (it cancelled the pawn's skills) and turns it back on when you return to the Arisen. Brand-new skills added by Skill Creator mods only work on the Arisen, so a pawn can't use them, AI or played.
- **Split screen is an early release.** Enemy health bars show only in player 1's view and are not placed right there; players 3 and 4 can look brighter than players 1 and 2; shadows can pop in and out at the edge of a view; target markers are off in split screen by default; photo mode goes back to one view. If something looks wrong, switch the co-op camera row back to a shared view.
- **Thief** pawns had crashes in early versions; none since. If you do get crashes while playing a Thief pawn, the advanced options have a switch that puts Thief pawns on simpler fallback controls.

## For mod authors
Other REFramework mods can ask who is being played, react when control changes hands, switch who is played (`possess` / `release_pawn`, API 1.2), and take over DPC's camera transition or camera follow through `_G.DPC_API`. See `API.md` in the source.

## Uninstall
Remove the mod and delete `reframework/data/DirectPawnControl.json` and `DPC_*.json` if you want a clean slate.

## Upgrading
Coming from 0.9.170 or older, your settings start from the new defaults once; your key and controller bindings are kept, and the old file stays as `DirectPawnControl.before_0.9.172.json`.

## Credits
- **Pawn Tactical Wheel** showed that a pawn can be ordered to use a skill by handing its AI the skill's own action pack, and its table got this mod's quick skills started. Its way of keeping an ordered skill going (the pawn's decision maker is switched off until the action is over) is used for skill orders since 0.9.151. The released mod carries no data from it: which action pack belongs to which skill is read from the game's own skill table while you play.
- **joseau11** sent the code two-controller co-op is built on, plus co-op aiming, auto-resume and rumble, and Camera Distance's look-ahead pull-back.
- **guitarguy1104**'s DD2CouchCoop is where the split screen comes from: the second camera with its own part of the screen, the per-view picture settings, shadows, sound listener and culling, shared with the words "the logic for these mods is all yours to use as you see fit".
- **guitarguy1104**'s DD2PartySwitcher showed how to have the game treat the played pawn as the player for single game calls; the sound changes use that method.
- Built with REFramework by praydog.
