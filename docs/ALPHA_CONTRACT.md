# RuleRoom alpha contract — 2026-10-23

Canonical repository: https://github.com/ikanit1/boblox, branch main. This supersedes CONTRACT.md (historical prototype). Rojo files are authoritative. User explicitly expanded the prototype into a full playable mode; GitHub pushes are authorized. Cloud game publication and paid products are separate.

## Gameplay
One room, 1–12 intended players, six trials per run. Voting 8s -> five distinct drawn trials -> ReactorRush cooperative finale -> Results 7s. Trials target 14–22s including warnings; breaks 3s. Death eliminates for this trial only; next trial restores health and admits respawned players and late joins. Never spawn mid-hazard. No paid revival. Solo works; runs last about 2–3 minutes.

Rule catalog: SafeColor, LaserSweep, LowGravity (existing), RedLight (stop on red, grace before movement checks), LavaRise (safe platforms), MeteorRain (marked impacts), DisappearingTiles (warned waves), SafeZone (marked safe zone), Spinner (jump a rotating beam), ReactorRush (collect energy together while dodging a sweep). Every hazard warns, validates on server, and cleans up unconditionally.

Modes Balanced / Reflex / Cosmic alter deck weights, not movement stats or rewards. No repeats within a run; readable first trial, finale last. Pure seeded deck module. No rewards for lobby idling.

## Ownership
- Gameplay: Main.server.luau, PlayerRoster.luau, ArenaRules.luau, RuleMath.luau, StudioChecks.luau; shared/GameConfig.luau, shared/RuleDeck.luau; tests/RuleMath.spec.luau, RuleDeck.spec.luau.
- Presentation: src/client/*, tools/build_assets.py, assets/*.
- Progression: server/ProfileService.luau, server/ProfileData.luau; shared/EconomyConfig.luau; tests/ProfileData.spec.luau.
- Root: other tools, mapping, docs, integrations, live Studio.
Agents are not alone; don't revert others' edits. Only root controls Studio.

## World
Preserve Workspace.Arena, Tiles (36 anchored 10x2x10 Parts at x/z -25,-15,-5,5,15,25, y=0), ColorName Blue/Pink/Yellow/Green; ArenaSpawn, LobbySpawn, hidden noncollidable Laser. Dynamic hazards under RuleEffects, destroyed on reset. Decor must not create safety floors or obstruct jump arcs. Cosmetic trails have no collision. Lobby outside arena. Bounded effects.

## Protocol
ReplicatedStorage.RuleRoomState attributes:
- Phase: Waiting / Voting / Rule / Break / Results.
- RuleId, RuleName, Instruction, PhaseEndsAt, Round, RuleIndex, RuleCount (6), SafeColor, Accent: existing meanings.
- ModeId: Balanced / Reflex / Cosmic; VotesBalanced, VotesReflex, VotesCosmic integers.
- TeamCharge, TeamGoal numbers; FinaleSuccess boolean; ResultsText string; AliveCount number.

ReplicatedStorage.RuleRoomRemotes contains authored Vote and ProfileAction RemoteEvents. Vote: FireServer(modeId), server allowlist, Voting phase only, replace previous vote, remove on leave, rate limit. ProfileAction: FireServer(action, id), action Purchase/Equip/ClaimQuest; server allowlisted id, price, ownership, eligibility and balance, rate limit. Never client-supplied money/scores/positions/prices.

Player attributes: InRound, Eliminated, RunScore, RunSurvived, Coins, XP, Level, Wins, EquippedTrail, Owned_<id> booleans, DataStatus (Session/Loading/Saved/Unavailable/Busy), Quest_survive/stars/runs counts, Claimed_survive/stars/runs booleans, ActionMessage. leaderstats Score and Best remain session scores. RunScore and RunSurvived reset only at BeginRun, not per-trial StartRound.

Roster.AwardSurvivors(ruleId) -> number returns the number of newly awarded eligible survivors. Main calls it once after a completed trial and requires a positive count before confirming FinaleSuccess; repeat calls return zero without duplicate rewards.

## Progression API
Main creates ProfileService.new() once, then PlayerRoster.new(lobbyCFrame, profiles). Dot-methods:
- IsReady(player) -> boolean. Failed loading may play explicitly session-only, but never save fallback over a failed record.
- AwardSurvival(player): +12 coins/+20 XP, daily survive count; once per completed trial/eligible player.
- AwardStar(player): +2 coins/+3 XP, daily stars count.
- CompleteRun(player, won): +15 coins/+25 XP, daily runs; +1 Wins/+20 coins if won. Main calls exactly once per run for participants who survived at least one trial. won = survived >=4 trials AND survived finale AND team goal completed.
- Destroy(): bounded flush/release, no overlapping saves.

EconomyConfig.Trails array {Id, Name, Price, Color}, default None free and four earnable trails, first ~60 coins. EconomyConfig.Quests keyed survive/stars/runs with Name, Target 8/10/2, Reward 50/50/60. Start Coins=0, XP=0. Level from XP, cosmetic only. Define exact catalog IDs before presentation uses them.

ProfileService owns Player events and ProfileAction. Persistence: server only, schema validation/migration, UpdateAsync, session lease, budget/backoff, autosave, PlayerRemoving/BindToClose. Studio in-memory by default; explicit development config and published sandbox needed for real persistence. Never overwrite after load failure/lock conflict. Separate production/test store names. No Robux products in this alpha.

## Presentation
Russian HUD: one current instruction/timer, six-trial progress, score, health feedback, team charge only in finale. Compact vote cards, results, optional cosmetics/quests panel closes for active trial; don't cover movement/jump controls. Activated buttons, gamepad selection, symbols+text+color, minimal motion option. Spectate living player while eliminated; restore CameraSubject on respawn/new trial. Trails client-rendered on all characters from EquippedTrail. Inspectable authored GUI; dynamic repeated catalog rows permitted.

## Verification
Rojo, format/lint/compile, meaningful pure deck/reward/schema/geometry tests. Live Studio full cycle, cleanup, death/reentry, late join, invalid/spammed remotes, reward boundaries, cosmetics, phone landscape, two clients. Record actual evidence level. Prototype tests do not certify alpha. Production persistence, Robux receipts, public play and retention require separate real validation.
