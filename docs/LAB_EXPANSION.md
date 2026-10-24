# Laboratory expansion — 2026-10-24

The small waiting platform is replaced by a navigable laboratory complex. This is a feature candidate for review, not a declaration of Roblox 1.0 release acceptance. No Roblox publication, asset upload or cloud persistence was performed.

## Playable changes

- Trial floor: 60×60 → 84×84 studs (1.96× area), same 36 color/symbol tiles. Laser width/travel, lava/platform positions, safe zones, star positions and disappearance indexing derive from the new dimensions. Safe-zone warning is 5.5s; finale collection window 24s to suit travel distances. Laser traversal is 7s with three sweeps over 21s; finale traversal 9s. This preserves approximately the original linear beam speed instead of silently increasing difficulty by 40%.
- Hub: 52×30 → 180×144 studs (~16.6× floor area), three wings, raised viewing gallery, arrival route, queue arch, reactor exhibit, original research equipment, plants, background towers, signage and modeled rule dioramas.
- Optional seven-checkpoint parkour with server timing, fall recovery, replay and a session best. No idle economy rewards. UI explicitly says the record lasts until leaving this server.
- Ten readable guides explain existing trials; wardrobe terminal opens the existing earnable cosmetic/quest catalog. Server score board reflects actual players and scores.
- Explore/Join buttons and world terminals. Exploring/training players remain in the hub across other players' rounds. Join waits for the normal admission boundary. Exploring cannot cancel an active trial or manufacture survival rewards.
- Motion-sensitive presentation: bounded local reactor/beam animation follows the existing reduced-motion switch. Native editable parts and SurfaceGuis; no third-party models, hidden scripts or new game framework.

## Verification and exact limits

`Build.ps1` runs generator + world-safety gates + StyLua/Selene/compiler + pure Luau suites + ProfileService integration + deserialized-place checks. The expanded place contains 973 authored instances before runtime characters/effects. World gates reject any permanent collision intruding into the trial grid, and verify all seven jump budgets and fourteen terminals.

Initial native solo station test on 8×8 platforms: actual proximity input started practice; ordinary MoveTo/Jump completed all seven checkpoints in **52.71s / 35 jump attempts**. The first mixed-role attempt confirmed lunar isolation but timed out in the narrow course; landing platforms were widened to 12×12 for a more forgiving training path. Server best and client finish UI agreed. Coins stayed at 0 after completion and malformed station intents. Native Join canceled practice and admitted the player through Main on the next trial boundary. The final participant-scoped lunar implementation passed the mixed-role test: all seven practice points in **9.61s**, 280 lunar-active observations with unchanged scene gravity, no explorer force/award, no EndRound teleport, and successful next-boundary rejoin. Earlier attempts and their failures are retained in the raw evidence. These are functional tests, not a novice or physical-device acceptance test.

Expanded-arena regression and mixed-role multiplayer results are recorded in `docs/qa/laboratory-expansion.json`. Curated raw runtime exports are versioned under `docs/qa/laboratory/`, with local originals under `evidence/laboratory/`; they use real Players and production ArenaRules/PlayerRoster with clearly labeled mock reward adapters where applicable. Complete/fixture-ok alone does not mean a no-damage solve.

Outstanding: cloud data (user requested local-only), physical phone/gamepad, external human playtest, 4/8/12-client acceptance and long performance profiling. Known platform asset-type warning 203785492 is preserved; no matching project Sound instance was found. No claim that this feature closes these release gates.

## Reproduce

Build with `Build.ps1`, open `build/RuleRoom.rbxlx` through `Open-Studio.ps1`, Play. During a lobby boundary choose «ЛАБОРАТОРИЯ», walk left to the parkour terminal and interact. Use «В ИСПЫТАНИЯ» to return. Right wing terminals explain all ten rules. Tests under `tools/studio/` are isolated fixtures and are not mapped into the shipped place. Remove fixtures and restore Main before any final smoke test.

Official API references: [ProximityPrompt](https://create.roblox.com/docs/reference/engine/classes/ProximityPrompt), [server validation](https://create.roblox.com/docs/scripting/security/client-server-boundary), [Studio test sessions](https://create.roblox.com/docs/reference/engine/classes/StudioTestService), [device simulator](https://create.roblox.com/docs/reference/engine/classes/StudioDeviceSimulatorService).

The gravity investigation found that compensating a globally reduced gravity still changed Humanoid jump behavior (controlled flat-floor apex 9.51 vs 7.27 studs). The final implementation leaves scene gravity at 196.2 and applies lunar VectorForce only to admitted trial characters; every force and attachment is destroyed during restoration.

Final clean production Play (Main enabled, no authored QA fixtures): native UI activation counters confirm Explore, Join and Explore during phone voting. iPhone 14 landscape viewport 749×389: guide prompt/open/footer-close, menu isolation, wardrobe/open/close; VirtualInput exercised the experience UI. This is emulator interaction, not physical touch/gamepad acceptance. The final source includes a compact footer exploration button that vacates the motion-settings slot while queued.

Fall recovery was additionally checked by an explicitly injected fall after native movement to checkpoint 2: checkpoint stayed 2, character returned to the pad and the timer continued. Original Studio network simulation was found at 500/500 ms and 0.5% loss; the developer preview is left on ordinary zero-delay/zero-loss local simulation.
