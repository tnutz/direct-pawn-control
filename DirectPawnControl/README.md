# Direct Pawn Control - Play as Any Pawn. Includes Couch Co-op (Dragon's Dogma 2)

Take direct control of your pawns. Possess your main pawn or a hired pawn and play it with the game's own player controls, camera and HUD, while the Arisen fights on beside you. Or hand a second player a controller and play couch co-op: player 1 on the Arisen, player 2 on a pawn.

**Status: beta (0.9.x).** Playable from start to finish of a fight with every pawn vocation. See "Known limits".

## Requirements
- [REFramework](https://github.com/praydog/REFramework) for Dragon's Dogma 2 (nightly build recommended).
- Optional: **Camera Distance & Framing Studio** (included as a separate mod). It keeps both players in view in co-op and adds an off-screen marker. On its own it changes nothing until you pick a camera style.
- Recommended alongside: **Pawn Tactical Wheel**, a radial menu for ordering pawn skills with slow motion. The two mods work together.

## Install
- **Fluffy Mod Manager:** drop the zip into the DD2 mods folder and enable "Direct Pawn Control" (and, if you want it, "Camera Distance & Framing Studio").
- **Manual:** copy the `reframework` folder into the game folder.

## Controls
| Keyboard | Controller | What it does |
|---|---|---|
| **F7** | **Hold D-pad left / right** (half a second) | Select the previous / next character. An arrow shows over them and their name appears at the bottom of the screen. While you play a pawn the selection starts on the Arisen |
| **F6** | **L1 + left stick click** | Take control of the selection (a pawn, or back to the Arisen). On the controller, while you already play a pawn: go on to the next character in the party (each pawn in turn, then the Arisen), or to the one you just picked with the D-pad while its arrow is still showing |
| | **Hold D-pad down** while playing a pawn | Back to the Arisen |
| **F8** | | Warp the Arisen to the pawn you are playing |
| **Ctrl+F6** | | Start / stop couch co-op (player 2's controller drives the selected pawn) |
| **Numpad 1-6** | | The selected character uses skill slot 1-6 (the Arisen by default while you play a pawn; never the one you are playing) |
| **Numpad 7** | | Warp all pawns to you |
| **Numpad .** | | Heal / revive all pawns and the Arisen. A cheat, **off by default**: tick it under Cheats in the settings |

- Another cheat, **off by default** (Cheats in the settings): special arrows (Explosive, Blighting, Tarring, Drenching) are never used up by your pawns, whether you play them or they fight on their own, so there is always something to fire when you take one over. A pawn still needs at least one of the arrow in the bag.
- In couch co-op, player 2 changes to the next pawn with the same take-control combination (L1 + left stick click). It goes round the pawns only; the Arisen stays player 1's.
- Any key can be given Ctrl: hold Ctrl while you press the new key.
- These are the defaults. Every keyboard key above (co-op and the six skill orders included) and three controller combinations (take control / next character, back to the Arisen, couch co-op) can be changed under **Controls** in the settings window. There is also a switch there to keep the Arisen out of the take-control round.
- A line at the bottom of the screen says what the take-control button does right now and to whom ("L1+L3: Control <pawn>", "Hold D-pad down: Control Arisen"). It follows the keyboard or the controller, whichever you last used, and can be switched off under Controls.
- A **tap** on the D-pad is still the game's pawn order. A **hold** that selects or switches does not give the order. D-pad up is left entirely to the game (Go, and hold for Explore). As the Arisen, holding D-pad down is still the game's High Five.
- While you play a pawn it uses your normal controls (keyboard and mouse or controller): attacks, vocation action, all six skill slots, jump, sprint, grab, and the health and stamina item shortcuts. The lantern shortcut works the Arisen's lantern and your pawn's follows it.
- Remapped controls are fine. The mod reads the game's own controller and keyboard settings instead of assuming the defaults. If one of the mod's own keys (F6, F7, F8, the number pad) is also bound to something in the game, the settings window says so.
- In co-op, player 2's buttons follow the controller layout set in the game's options, remapped or not: every action sits where the game shows it.

Open the REFramework menu (Insert) and look for **Direct Pawn Control** to change options. The things most players change are at the top; everything else is folded away. Outside that menu the mod puts very little on screen: one line saying who you are playing or have selected, the Arisen's bars over his head, and in co-op player 2's bars and skill list.

## What your pawn can do while you play it
- Loot corpses, open chests, gather and pick things up: press interact when the mod's `[Interact]` prompt shows over the object. Items go to the pawn's inventory.
- Wake a sleeping companion, and revive a downed pawn by holding interact (a ring fills, as for the Arisen).
- An Archer pawn gets the bow aim camera and reticle while you hold aim, turns with the camera and shoots at the reticle. On a controller, the aim button + a skill button fires the aimed form of that skill.
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
- Talking to people, vocation guilds and other menus belong to the Arisen; F8 brings him to your pawn, then switch back. For the same reason your pawn does not use a Wakestone on a dead person: that choice stays with the Arisen.
- Looting, gathering, chests, waking and reviving by your pawn happen without the usual animation.
- The Arisen does not aim. A Magick Archer or Archer Arisen shoots at what he has locked on to. The Arisen's melee vocations do not guard or dodge.
- The bow aim camera and reticle are for Archer pawns in normal possession, not in co-op. Aimed skills for a bow pawn are on the controller only.
- Co-op needs player 1 on keyboard and mouse and player 2 on a controller, and player 1 always plays the Arisen. Choosing any character per player is planned.
- Quick skills (Numpad 1-6) cover the six pawn vocations; attack skills need an enemy in view or near the pawn.
- Possessing a pawn far away from the Arisen for a long time is not recommended.
- While you play a pawn, the button guide does not show "Dash" on its button. Dashing works as usual; only the label is missing.
- **Thief** pawns had crashes in early versions; none since. If you do get crashes while playing a Thief pawn, the advanced options have a switch that puts Thief pawns on simpler fallback controls.

## Uninstall
Remove the mod and delete `reframework/data/DirectPawnControl.json` and `DPC_*.json` if you want a clean slate.

## Credits
- **Pawn Tactical Wheel** showed that a pawn can be ordered to use a skill by handing its AI the skill's own action pack, and its table got this mod's quick skills started. Its way of keeping an ordered skill going (the pawn's decision maker is switched off until the action is over) is used for skill orders since 0.9.151. The released mod carries no data from it: which action pack belongs to which skill is read from the game's own skill table while you play.
- Built with REFramework by praydog.
