---
name: obsidian-gamedev-workflow
description: Maintain an existing game project's Obsidian knowledge vault, decisions, asset provenance, QA and roadmap from verified code and test evidence. Use when the game repository identifies an Obsidian vault; do not inspect unrelated personal notes.
---

# Project knowledge in Obsidian

Locate the vault from project AGENTS.md. For RuleRoom it is `docs/obsidian-vault`. Read `00-Dashboard/Dashboard.md`, the current task and only the relevant system/decision pages. Confirm code and branch before changing a status; distinguish the main branch, unmerged PRs and combined local test candidates.

Use native Obsidian CLI when it is enabled and explicitly targets this project vault. Otherwise ordinary UTF-8 Markdown file editing is a supported, fully testable method. File editing does not prove that Obsidian GUI has opened the vault. If UI activation/CLI registration is required, report the observed state and exact action. Do not read personal vault contents or install community plugins as a prerequisite.

Keep one canonical page per maintained subject. Roadmap lives in `07-Tasks/Roadmap.md`, release gates in `10-Releases/Release Checklist.md`; legacy docs may point there. Link to code, manifests and evidence instead of copying facts into competing checklists. Preserve historical reports as dated evidence, not current status.

For a meaningful change, update its system/design page, related open task and Dashboard; add an ADR only for a consequential decision. Record what changed, why, validation level, source identity, limits and next action. For assets record source/license, generator or editable source, export settings, dimensions/collisions, import and visual/performance evidence. A file on disk is not an imported Roblox asset.

Use explicit statuses: planned, implemented, statically checked, executed in Studio, limited, failed, or not run. Record actual clients/devices and whether data is mock, Session-only or cloud. Do not infer retention, audio quality or human comprehension from automated checks.

Use Obsidian wikilinks for related notes, properties for stable metadata, and Mermaid when it clarifies relationships. Run `python tools/obsidian/verify_vault.py` after structural edits. Use the project's file smoke test for method validation; remove only the temporary note it created. Keep `.obsidian/workspace*`, caches and personal UI layout out of Git. Avoid logging every code-line change.
