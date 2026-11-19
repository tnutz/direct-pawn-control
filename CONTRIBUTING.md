# Contributing

Bug reports, fixes and new features are all welcome. This page says how to send them so nothing gets lost on the way.

## Reporting a bug

Use the **Bugs** tab on the [Nexus page](https://www.nexusmods.com/dragonsdogma2/mods/2690) or open an
[issue here](https://github.com/tnutz/direct-pawn-control/issues/new/choose). Either is fine. Please include:

- the mod version (top of the Direct Pawn Control window in the REFramework menu) and your REFramework build;
- your other mods, especially ones that touch the camera, input, pawns or lock-on;
- the Arisen's vocation and the vocation of the pawn you were playing;
- controller or keyboard and mouse, and whether co-op was on;
- what you did, what happened, and what you expected;
- for crashes or errors, REFramework's log (`re2_framework_log.txt` in the game folder).

The known limits listed on the Nexus page are already known; no need to report those.

## Sending changes

Open a **pull request** against `main`. Please don't paste code into Nexus comments or messages: the site breaks the
formatting and the change can't be applied.

1. Fork this repository and make your changes on a branch.
2. Keep each pull request to one feature or fix. Changes to Direct Pawn Control and to Camera Distance are easier to
   review as separate pull requests.
3. Describe what it does, why, and how you tested it (vocations, controller type, co-op or not).
4. Mention it if you used AI tools to write the code. That's fine; this mod was written that way too.

No GitHub account? Put the changed files in a zip on any file-sharing link and send it through Nexus.

### What happens next

This repository is generated from the author's working copy, so pull requests are not merged with the button. Your
change is reviewed, tested in the game, and brought into a release; the repository is then updated, you are listed as
co-author of that commit and credited in the change log, and the pull request is closed with a note saying which
version includes it. Parts of a pull request may be taken and others left out, and the reason will be given.

### Guidelines for the code

- Keep the defaults. A new behaviour goes behind a setting, and it may start switched off until it has had play time.
- Don't rename existing settings; people's saved configurations would lose them.
- No new globals. Everything lives in the script's locals (the shared table `R` holds most of it). If another mod needs
  to read something, raise it in the pull request first.
- Wrap anything that calls into the game in `pcall`, check singletons and objects for `nil` before use, and compare
  game objects by `get_address()`, never with `==`.
- Don't edit the version number or the change log; they are updated when a release is made.
- Check that the script still compiles (`luac -p DirectPawnControl.lua`) and say in the pull request what you
  tested in the game.
- No game files, extracted assets or anything you don't have the right to share.

## Licence

Contributions are accepted under the same licence as the rest of the code,
[PolyForm Noncommercial 1.0.0](LICENSE.md). By opening a pull request you confirm the code is yours to give
under it.

You don't have to contribute here to build on the mod: the licence also lets you publish your own free add-on or
modified version, as long as you keep the required notice and link back. Asking first is appreciated.
