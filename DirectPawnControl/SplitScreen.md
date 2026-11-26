# DPC Split Screen (early release)

One view per player for Direct Pawn Control's couch co-op, two to four players. Ships with Direct Pawn Control
0.9.177 as `reframework/autorun/DPC_SplitScreen.lua` and is **off by default**: turn it on with "Split screen (early)"
in the co-op camera row at the top of DPC's settings. Its own settings: REFramework menu > Script Generated UI >
DPC Split Screen.

- Splits only while co-op runs; talks, cutscenes, special cameras and photo mode go back to one view. Menus keep the
  split (switchable).
- Layouts: two side by side (auto on wide screens) or top and bottom; three across or a 2 x 2 grid (the spare quarter
  blank or an overview from above); four in a grid or across.
- Every player's camera turns with their own right stick; each can use a Camera Distance preset of their own.
- Player 1 keeps the game's HUD, fitted to his view; DPC draws the other players' cards and bars in their own view.
- Picture settings, shadows and see-through per view; sound from the players' midpoint or from player 1.

Known limits: enemy health bars only in player 1's view and placed wrong there; views 3 and 4 can look brighter;
shadows can pop at view edges; target markers off by default in split screen.

Credits: the split-screen method (a second camera with its own RenderOutput region, the pose written at
BeginRendering, the stick turn, post-effect copying, per-view shadows, the second listener, culling) comes from
guitarguy1104's DD2CouchCoop, shared with "the logic for these mods is all yours to use as you see fit".
