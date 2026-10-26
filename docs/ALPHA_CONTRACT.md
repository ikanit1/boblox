# RuleRoom alpha contract — 2026-10-23

Canonical repository: https://github.com/ikanit1/boblox, branch main. This supersedes CONTRACT.md (historical prototype). Rojo files are authoritative. User explicitly expanded the prototype into a full playable mode; GitHub pushes are authorized. Cloud game publication and paid products are separate.

## Gameplay
One laboratory complex, 1–12 intended players, six trials per run. First entry waits for an acknowledged Play/Explore choice. Voting 8s -> five distinct drawn trials -> ReactorRush cooperative finale -> Results 12s. Trials last roughly 12–27s including warnings; breaks 3s. Living survivors remain on the restored arena during breaks; results return the queue to the laboratory. Death eliminates for this trial only; next trial restores health and admits respawned players and late joins. Never spawn mid-hazard. No paid revival. Solo works; runs last about 2–4 minutes.

Rule catalog: SafeColor, LaserSweep, LowGravity (existing), RedLight (stop on red, grace before movement checks), LavaRise (safe platforms), MeteorRain (marked impacts), DisappearingTiles (warned waves), SafeZone (marked safe zone), Spinner (jump a rotating beam), ReactorRush (collect energy together while dodging a sweep). Every hazard warns, validates on server, and cleans up unconditionally.

Modes Balanced / Reflex / Cosmic alter deck weights, not movement stats or rewards. No repeats within a run; readable first trial, finale last. Pure seeded deck module. No rewards for lobby idling.

## Ownership
- Gameplay: Main.server.luau, PlayerRoster.luau, ArenaRules.luau, RuleMath.luau, StudioChecks.luau; shared/GameConfig.luau, shared/RuleDeck.luau; tests/RuleMath.spec.luau, RuleDeck.spec.luau.
- Presentation: src/client/*, tools/build_assets.py, assets/*.
- Progression: server/ProfileService.luau, server/ProfileData.luau; shared/EconomyConfig.luau; tests/ProfileData.spec.luau.
- Root: other tools, mapping, docs, integrations, live Studio.
Agents are not alone; don't revert others' edits. Only root controls Studio.

## World
Preserve Workspace.Arena, Tiles (36 anchored 14x2x14 Parts at x/z -35,-21,-7,7,21,35, y=0), ColorName Blue/Pink/Yellow/Green; ArenaSpawn (0,5,0), LobbySpawn (0,4,158), hidden noncollidable Laser. The arena spans 84x84. Lobby platform spans 180x144, X -90..90 / Z 48..192; a narrow viewing bridge stops at the arena boundary. Dynamic hazards under RuleEffects, destroyed on reset. No permanent collision inside the trial grid; no supporting slab or jump obstruction. World safety tests enforce this boundary. Native original scenery, no uploaded meshes or paid assets.

Optional station: seven ordered parkour checkpoints, ten rule-guide terminals, wardrobe terminal, viewing gallery and live server score board. Explore keeps the player out of admissions and voting until Join. New players start with LobbyOnly=true and EntryChoiceMade=false; accepted Join/Explore/Practice sets the choice flag. Main guards that flag even before Station has initialized. StartPractice is a proximity-only server action, permitted outside a trial; it switches to Explore. Falling restores the last checkpoint. A valid ordered finish records session-only PracticeBestSeconds, explicitly labeled as temporary. No currency, XP or run-win reward for practice/exploration. Join cancels practice and admits only at a normal trial boundary. Lunar gravity is applied only to admitted trial characters with temporary mass-scaled VectorForces; global scene gravity stays 196.2. A server-owned root TrialGravityScale selects the matching airborne envelope. Restore destroys every force/attachment and clears that attribute. Source: tools/build_station.py and Station.server/client scripts.

## Protocol
ReplicatedStorage.RuleRoomState attributes:
- Phase: Waiting / Voting / Rule / Break / Results.
- RuleId, RuleName, Instruction, PhaseEndsAt, Round, RuleIndex, RuleCount (6), SafeColor, Accent: existing meanings.
- ModeId: Balanced / Reflex / Cosmic; VotesBalanced, VotesReflex, VotesCosmic integers.
- TeamCharge, TeamGoal numbers; FinaleSuccess boolean; ResultsText string; AliveCount number.
- HazardStage: Warning / Active / Recovery; HazardCycle increments for each warning wave within a trial. These are presentation signals, not client permissions.

ReplicatedStorage.RuleRoomRemotes contains authored Vote, ProfileAction and StationAction RemoteEvents. Vote: FireServer(modeId), server allowlist, Voting phase only, replace previous vote, remove on leave/Explore, rate limit. ProfileAction: FireServer(action, id), action Purchase/Equip/ClaimQuest; server allowlisted id, price, ownership, eligibility and balance, rate limit. StationAction: FireServer("Explore" | "Join"), living character within the station, outside active participation, 0.4s server rate limit. StartPractice uses the authored ProximityPrompt only, checks exact ownership in the lobby, <=13 studs, living character, phase membership and rate. Guide/wardrobe prompts display local information; purchases still use ProfileAction. Never client-supplied money/scores/positions/prices/checkpoint/time.

Station player attributes: LobbyOnly and EntryChoiceMade booleans; PracticeState Idle/Running/Finished; PracticeCheckpoint 0..7; PracticeStartedAt server time or 0; PracticeLastSeconds and PracticeBestSeconds session-only positive times. Main ignores explorers and unconfirmed newcomers in queued counts, voting and trial admission. EndRound does not teleport an explorer. Session profile persistence schema is unchanged.

Player attributes: InRound, Eliminated, RunScore, RunSurvived, Coins, XP, Level, Wins, EquippedTrail, Owned_<id> booleans, DataStatus (Session/Loading/Saved/Unavailable/Busy), Quest_survive/stars/runs counts, Claimed_survive/stars/runs booleans, ActionMessage. leaderstats Score and Best remain session scores. RunScore and RunSurvived reset only at BeginRun, not per-trial StartRound.

Personal run display: TrialOutcome_1..6 (Pending/Playing/Survived/Eliminated/Skipped), TrialRule_1..6 rule IDs, LastTrialOutcome/LastTrialRule, RunStars, RunCoinsEarned/RunXPEarned. Reward totals capture synchronous attribute changes only around ProfileService's real grants; purchases and quest claims never enter these totals. RunResult is None/Won/FinaleFailed/FinaleMissed/NotEnoughTrials/NoSurvival/Aborted; ResultReady is published last. BeginRun resets the display, respawn does not. LastDamageRule/LastDamageAt are server-authored; EliminationReason distinguishes hazard, fall, boundary, movement and reset. These values do not change save schema or reward eligibility.

Roster APIs: BeginRun(deck?), StartRound(cframe,index?,ruleId?), EndRound(keepInArena?), CompleteRun(teamSuccess,aborted?). The optional legacy arguments support isolated fixtures; production Main supplies the deck and index. CompleteRun is guarded for all records, including zero-survival and aborted outcomes; aborted runs never receive a completion bonus.

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
