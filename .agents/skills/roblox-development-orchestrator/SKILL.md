---
name: roblox-development-orchestrator
description: Coordinate work in an existing Roblox game repository using its skill catalog, source ownership, Studio MCP, QA and project Obsidian vault. Use for Roblox development or environment setup when the repository identifies this workflow.
---

# Roblox development orchestration

Start from the current repository, not a new project. Read `AGENTS.md`, identify the remote, branch and dirty files, then read `docs/obsidian-vault/00-Dashboard/Dashboard.md` and the relevant open task. Repository code and pinned tool versions are authoritative. The vault owns project knowledge; Git owns history.

Read the installed game-development `router` once at task start. Select only the skill bodies needed for the current concern from `docs/environment/skills-catalog.json`. Prefixes distinguish libraries: `el4-` for EL4CTEO, `brain-` for Roblox Brain, `ccb-` for Blender. Existing unprefixed engine skills remain independent. Use catalog paths; do not assume similarly named skills are interchangeable. Read references on demand. Announce selected skills and report those actually applied.

| Task | Focused combination to resolve from the catalog |
|---|---|
| Environment or Studio operation | roblox-studio-workflow + el4-roblox-tooling / el4-roblox-studio-mcp |
| Mechanic | brain-roblox-game-design + el4-roblox-game-systems + roblox-luau + el4-roblox-testing |
| Network | roblox-networking + el4-roblox-security + el4-roblox-architecture + testing |
| Data | roblox-datastores + el4-roblox-data-stores + security + testing |
| UI/input | roblox-ui + brain-roblox-gui + input + player psychology when usability is the question |
| Map/model | world-building/building + lighting/performance + the Blender modeling/export skills needed |
| Character/NPC | characters/animation or npc-ai + physics/performance as needed |
| Optimization | performance + code-review + tooling; measure before changing behavior |
| Release | publish checklist + testing + analytics/security within explicit release authorization |

This is routing, not a requirement to load every entry in a row. Resolve missing names through the catalog and state an actual gap. Conflicting advice is settled by project contracts, current official API documentation and observed tests. Record consequential decisions in `08-Decisions`.

For RuleRoom, Rojo `src/` and `default.project.json` own the DataModel. `tools/build_assets.py` owns generated arena/HUD XML. Change the generator or mapped source before syncing. Studio MCP may inspect and verify; exploratory edits must be ported back or cleaned. Only one agent owns a Studio instance and each edited file. Never synchronize into an unrelated user play session.

Prefer registered official tools. Enumerate Studio instances, identify the intended place, inspect its mode and perform a bounded non-destructive query before mutation. A registered server is not proof of a live connection. Do not require PlayerModule from an MCP diagnostic context: a separate module cache can create a second control binding; inspect control state inside the owning LocalScript instead.

Use Build.ps1 and checks matching the risk. Runtime changes need relevant Studio paths; network changes need native clients; device and human play acceptance stay distinct. Capture source/fixture identity, client count, expected and observed outcomes, logs and cleanup. Invalid instrumentation is retained and repeated, not counted as success. Mock pickup tests and Session profiles do not prove concurrent real-client awards or cloud persistence.

At completion update the affected vault page, task and Dashboard with evidence and the next unresolved gate. Keep failed/unrun cases visible. Follow the current user's publication/merge/spending authorization; setup and prior source pushes do not authorize a release.
