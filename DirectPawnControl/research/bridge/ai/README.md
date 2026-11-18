# AI research probes (2026-11-12)

Goal: let the brain-driven Arisen fight with any vocation by reusing the game's own AI. The full plan is the project doc "Arisen AI plan" (claude.ai project "Dragon's Dogma Mods", `claude/arisen-ai-plan.md`).

Found offline (dd2-modkit `dd2_sdk.lua`, game `Enums_Internal.hpp`):

- **Human enemy AI** (bandits, named human bosses, very likely the Dark Arisen Maister spirits): `app.HumanEnemyController` on `app.Human`; `app.HumanEnemyManager`; `CharacterManager.HumanEnemyThinkTableDataList`, `HumanEnemySkillSetData` (Lv1 / Lv2 / LvEx), `HumanEnemyCombatParameterData`.
- **Decision layer on every `app.Character`:** `AIDecisionMaker` (modules include `ThinkTable`), `AIBlackBoardController.ReqMainActInterPackData` / `ReqSubActInterPackData`, `AIDecisionModule.ActionInterface`, `BattleStateController.CharaControllerTypeEnum { Player, AI }`.
- **Action interface commands** (`app.actinter.cmd.*`): `job` (NormalAttack, HeavyAttack, ComboAttack, DashAttack, JumpAttack, CustomSkillStandardBase), `job01` (Guard, TuskToss, SpringboardBase), `job02` (Aim, AimedShot, ContinuousAimedShot, MeleeAttack), `job03` (Levitate, SpellStockRelease), `job04`, `job06`, `job07`, `job08`, `job09`, `jobmagicuser`, `move` (ApproachTargetAroundPoint, MoveBase, SearchEscapePoint), `humanenemyjob` (FullMoonSlashComboEx, LocomotiveChargeAttack, HumanEnemyCarpetBombing, EnemyCloseNormalAttack).
- **Line of sight:** `app.LockOnTargetWork.isWall / isWallPL / isWallCam / IsRayCasted` (used by DPC 0.9.6); `app.CollisionSystem.AsyncCastRay` for our own rays; decision pack `Catalog_MoveToCanSeePlayer`.

Probes (send with `../send.py`, results land in `reframework/data/agent_bridge/`):

| Script | Needs | Output |
|---|---|---|
| `ai_types.lua` | game running (paused is fine) | `ai_types.json`: `app.*` type names by keyword |
| `ai_reflect.lua` | game running | `ai_reflect.json`: fields and methods of the AI types |
| `ai_state.lua` | a loaded save | `ai_state.json`: AI parts of the Arisen, each pawn and a nearby human enemy |

`ai_types.lua` assumes `sdk.get_tdb():get_num_types()` / `get_type(i)` exist in this REFramework build; if the bridge reports an error there, drop it and rely on `ai_reflect.lua`.
