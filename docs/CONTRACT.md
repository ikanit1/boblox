# Rule Room prototype contract

Source of truth: Rojo files in this project. Generated place files and XML assets are built from these sources. No cloud publishing or paid products in this prototype.

## Ownership
- Server agent: `src/server/`, `src/shared/GameConfig.luau`, `tests/` only.
- Presentation agent: `src/client/`, `tools/build_assets.py`, generated `assets/Arena.rbxmx`, `assets/RuleRoomHUD.rbxmx` only.
- Root agent: project mapping, setup/build/run scripts, tools, documentation, integration.

## World
`Workspace.Arena` is a Model containing `Tiles` (Folder with 36 anchored 10x2x10 Parts, 6x6 grid, center at 0,0,0), `ArenaSpawn` (invisible anchored Part at 0,5,0), `LobbySpawn` (SpawnLocation at 0,3,52), walls and lobby platform. Tile positions are -25,-15,-5,5,15,25 on x/z. Each tile has a string `ColorName` attribute: Blue, Pink, Yellow, Green, cycling across the grid. World asset must be present in edit mode, including a non-collidable anchored `Laser` Part (60x1x1) initially invisible. Floor below -15 eliminates arena players via server boundary checks. World has no runtime asset dependency.

## Replicated state
Server creates/reuses Folder `ReplicatedStorage.RuleRoomState` with attributes:
- `Phase`: Waiting / Intermission / Rule / Results
- `RuleId`: SafeColor / LaserSweep / LowGravity (empty when none)
- `RuleName`, `Instruction`: Russian display strings
- `PhaseEndsAt`: Workspace:GetServerTimeNow() deadline, number
- `Round`: number; `RuleIndex`: number; `RuleCount`: 3
- `SafeColor`: Blue/Pink/Yellow/Green or empty
- `Accent`: Color3

No client-to-server gameplay remotes required. Server handles authoritative round state, hazard checks, health and points. State attributes are the only HUD protocol.

Player attributes: `InRound` boolean, `Eliminated` boolean. `leaderstats` IntValues: `Score`, `Best` (session only, no persistence). HUD must reflect late join/current attributes and survive respawn.

## Loop
Wait for >=1 player. Intermission 8s. Teleport current players to ArenaSpawn with distributed offsets, health reset, InRound=true. Run three distinct rules in sequence, roughly 20-25s each, including visible warning. One rule active at a time. SafeColor names AND symbols identify colors, with >=5s warning before unsafe tiles vanish. LaserSweep has a visible nonlethal warning then low sweeping beam(s), server geometric checks and damage cooldown; can jump. LowGravity lowers gravity temporarily, optionally collects server-checked floating pickups (keep scope small); restoration is unconditional. Award survivor points once per rule, end early if everyone eliminated. Results 5s, restore all tile collision/color, Laser visibility, gravity, teleport to lobby; repeat. Joining mid-round waits in lobby. Death/respawn cannot re-enter or double-award. No external art/audio, monetization, inventory or databases yet.

## HUD
`StarterGui.RuleRoomHUD` ScreenGui, ResetOnSpawn=false, named inspectable objects. Responsive Russian UI: game title, phase/rule, instruction, countdown, round/rule index, points, waiting/eliminated status and short controls tip. Client reads attrs and server clock; never awards points. Respect Roblox top bar and touch jump area. Color hints must include text/symbol, not color alone.

## Verification
Build with Rojo; format and lint Luau. Test actual Studio when accessible, inspect server/client errors, full loop and restoration, join/death/respawn, then 2-client mode. Static checks alone are not Studio acceptance. Report any login/MCP dependency honestly.
