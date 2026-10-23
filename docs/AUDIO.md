# RuleRoom audio

The alpha uses short, local 2D feedback cues. Audio never determines damage, timing, rewards, or voting. Every meaningful event still has a visual/text cue. There is no background music, looping ambience, microphone capture, voice chat modification, or downloaded audio pack.

## Source provenance

These two files were verified in the signed, installed Roblox Studio 0.744 distribution on 2026-10-23. They are referenced through Roblox's bundled-content URI scheme. No audio binaries are copied into this repository, and no arbitrary Creator Store/private asset IDs are used.

| Engine URI | Installed content file | Bytes | File duration | SHA-256 |
|---|---|---:|---:|---|
| `rbxasset://sounds/volume_slider.ogg` | `content/sounds/volume_slider.ogg` | 12475 | 0.848083 s | `F2A84FFC3AFDAFF965186C3085ACAC4D50DC825743B3C0299554DE6E80FD23D3` |
| `rbxasset://sounds/action_jump_land.mp3` | `content/sounds/action_jump_land.mp3` | 5331 | 0.269188 s | `39FA42EEDF3E2E15FC009F98A0C6A7077327DC927B896913832FDDF640F81B5E` |

Verified installation: `C:/Program Files/Roblox/Versions/version-7aaa6838d36c4448`. These are Roblox-distributed engine content, not original RuleRoom recordings or CC0 media. Referencing them does not grant a separate redistribution license. Availability on the target Roblox client is checked at runtime through `Sound.IsLoaded`; a missing source drops optional cues without delaying gameplay. Studio clients loaded and played both sources in the 0.3 checks below; physical-device playback and listening remain separate acceptance steps.

## Implementation and mix

`src/shared/AudioConfig.luau` defines the two sources, gains in dB, pitch/speed, short playback windows, fade duration, per-cue cooldowns, and priority. `src/client/AudioController.luau` owns one local folder `SoundService.RuleRoomAudio`, one `SoundGroup`, three reusable tone voices, and one impact voice. It never creates a new sound per event. Short fades avoid a hard cut; four voices is the strict maximum.

The small `Sound`/`SoundGroup` route is intentional for a few non-spatial UI cues. The installed Roblox audio skill permits this simple 2D case. More complex spatial audio or a future music mix should use the current modular audio graph rather than expand this pool into a general music engine.

| Cue | Trigger | Gain before master | Limit |
|---|---|---:|---|
| Rule | New run/trial identity while phase is Rule | -18 dB | 0.8 s cooldown |
| Countdown | Last 3, 2, 1 seconds while the local player is active | -22 dB | 0.45 s cooldown; each timer value is intentionally limited to once per trial |
| Damage | Local character health decreases during an active trial | -18 dB | 0.4 s cooldown |
| Reward | Confirmed replicated coin balance increases | -23 dB | 0.55 s cooldown; no cue for spending |
| Finale | Successful shared finale reaches Results | -17 dB | Three rising notes, 0.18 s apart; once per Results transition |
| RunEnd | Other Results transition | -23 dB | One soft closing cue |
| UI | Authored and dynamically cloned `GuiButton.Activated` | -29 dB | 0.1 s cooldown |

The master gain is -2 dB. The damage cue has higher priority than optional UI/reward feedback. Full pools drop lower-priority cues. There are no reverb, pitch-shifter, or acoustic simulation effects.

The countdown's deduplication key is the run/trial identity and timer value, not each internal deadline. SafeColor and other staged rules therefore do not replay 3–2–1 for every substage. This is intentional noise reduction; the on-screen instruction and timer still update for every stage.

Audio initialization asynchronously preloads the four pool instances (two unique sources); the HUD does not wait. Source loading and playback are protected so an unavailable optional sound cannot stop gameplay. Character health listeners are replaced on respawn, dynamic button listeners are removed with their buttons, and destroy cancels pending notes/fades and removes the pool.

## Player control and integration

The authored `Root.Actions.Audio` button uses `Activated`, making it usable by touch, mouse, and controller. Its text is `ЗВУК: ВКЛ` / `ЗВУК: ВЫКЛ`. Muting immediately silences the mix, stops every voice, and invalidates delayed finale notes. Unmuting permits future cues without replaying old ones.

The local player attribute `RuleRoomAudioMuted` stores the preference across character respawns for the current server session. It is local presentation state, is not a gameplay remote or a cloud-saved preference, and does not change Roblox's global volume or other experiences' audio. Reduced motion and audio mute are separate controls.

HUD integration:

```luau
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local audio = AudioController.new(player, state, root, root.Actions.Audio)
-- During HUD cleanup:
audio.Destroy()
```

## Verification and evidence limits

Static checks cover formatting, lint, compilation and the configuration. They do not establish audibility, subjective loudness or sound quality.

### Observed in Studio 0.744 on 2026-10-23

The user explicitly authorized continuation through Studio MCP. The following checks ran in real Play; phone UI input used `VirtualInput` with touch enabled in the iPhone 17 Pro landscape simulator (750×381 viewport, 750×323 GUI safe area).

| Check | Observed result | Local evidence |
|---|---|---|
| Source loading and cues | Both `Loaded_Tone` and `Loaded_Impact` true; Rule, Countdown, Damage, Reward, UI and RunEnd calls observed | `v03-controls-confirmed.json` |
| Engine audio signal | Tone peak `PlaybackLoudness` 185.5001, Impact 52.6337 | `v03-close-respawn.json` |
| Two respawns | Maximum one pool, minimum/maximum four sound instances | `v03-close-respawn.json` |
| Actual mute button | Playback count 105→105, playing sounds 0, mix volume 0 | `v03-mute-confirmed.json` |
| Actual unmute/UI input | Muted false and new UI cues; playback count reached 107 | `v03-controls-confirmed.json` |
| Delayed finale notes | First note played, then mute stopped the two scheduled notes; 178→178 | `v03-finale-mute-fixture.json` |
| Two-client mute isolation | Player1 stayed muted for the 8-second observation, 44→44 and no playing voice; Player2 stayed unmuted and progressed 15→39 | `v03-private-mute-fixedwindow.json`, `v03-private-mute-other.json` |
| Muted multiplayer respawn | Player1 health 100, mute retained, playback count 44 and four voices | `v03-muted-respawn-multiplayer.json` |
| Final-source HUD rebuild | One pool and four voices after replacing the HUD/script in a controlled client lifecycle fixture | `v03-final-hud-rebuild.json` |

The finale cancellation check changed **client presentation attributes only**. It verifies sound cancellation, not a naturally won reactor or gameplay reward. The earlier ambiguous multiplayer mute snapshot is not counted; the fixed 8-second observation is the evidence used. Player2's continued unmuted playback is established by separate snapshots. The latest compact-layout change was made after launching that multiplayer test and passed a separate solo UI check: iPhone 17 Pro, Samsung and a 443×241 GUI stress size, with 44 px action buttons and an 8 px gap below the voting/results/reactor panels. Those panel checks used presentation fixtures; see [QA_REPORT.md](QA_REPORT.md).

Nonzero `PlaybackLoudness` demonstrates an engine audio signal, not actual listening through speakers or headphones. No physical phone, output-device recording or subjective mix evaluation was performed. The recorded console includes an unresolved `rbxassetid://203785492` asset-type warning and, in one unpublished two-client test instance, Roblox CoreGui CreatorType/TopBar/PlayerList errors. The project does not reference that asset ID; an in-Play search returned no matching instance. Its origin remains unknown and it is not reported as fixed.

Remaining acceptance checklist:

1. Listen to rule change, countdown, damage, earned coins, menu clicks and a naturally successful finale. Match cues to visual events. Verify spending and healing do not play reward/damage cues.
2. Repeat on an actual phone; the final mobile layout passed in the emulator, whose audio is still desktop audio.
3. With two clients, trigger controlled damage and earnings on exactly one client to verify each private cue's audience. Independent mute already passed; it does not by itself prove every event's audience.
4. Listen on physical headphones and speakers before release and tune shared gains if needed. Roblox global mute/output-device settings remain outside this controller.

Local diagnostic attributes on the audio folder: `PlaybackCount` (actual `Sound:Play()` calls, not proof of audible output), `LastCue`, `LastPlaybackAt`, `Played_<cue>` (counts notes, so one successful finale is three), `Muted`, `Loaded_Tone`, `Loaded_Impact`, `PreloadCompleted`, and `PlaybackError` if a protected play call failed. Diagnostics are not sent to a server or analytics service.

## Current primary API references

- [Sound](https://create.roblox.com/docs/reference/engine/classes/Sound) — `SoundId`, `IsLoaded`, `PlaybackSpeed`, `TimePosition`, `Play`, `Stop` and local sound state.
- [SoundService](https://create.roblox.com/docs/reference/engine/classes/SoundService) — sound service scope and local playback facilities.
- [ContentProvider](https://create.roblox.com/docs/reference/engine/classes/ContentProvider) — asynchronous preloading.

Reference pages were consulted on 2026-10-23. A source file existing locally establishes provenance and installation availability; successful live loading/playback and listening are separate validation steps.
