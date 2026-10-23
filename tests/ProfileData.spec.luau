--!strict
local Data = require("../src/server/ProfileData")

-- Domain fixture deliberately has no Roblox Color3 values; the production logic
-- accepts a server catalog, never client prices. Studio checks the presentation catalog.
local config = {
	Trails = {
		{ Id = "None", Price = 0 },
		{ Id = "Cyan", Price = 60 },
		{ Id = "Pink", Price = 100 },
		{ Id = "Gold", Price = 180 },
		{ Id = "Emerald", Price = 260 },
	},
	Quests = {
		survive = { Target = 8, Reward = 50 },
		stars = { Target = 10, Reward = 50 },
		runs = { Target = 2, Reward = 60 },
	},
	Rewards = {
		SurvivalCoins = 12,
		SurvivalXP = 20,
		StarCoins = 2,
		StarXP = 3,
		RunCoins = 15,
		RunXP = 25,
		WinCoins = 20,
	},
}
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local today = 20_000
local timestamp = today * 86400 + 100
local fresh = Data.fresh(today)
expect(fresh.Coins == 0 and fresh.XP == 0 and fresh.Wins == 0, "New profiles start without earned progress")
expect(fresh.OwnedTrails.None and fresh.EquippedTrail == "None", "Default cosmetic is always available")
expect(Data.day(timestamp) == today and Data.day(timestamp + 86400) == today + 1, "Daily quests use UTC day")
expect(Data.level(0) == 1 and Data.level(99) == 1 and Data.level(100) == 2, "First level boundary")
expect(Data.level(399) == 2 and Data.level(400) == 3, "Increasing XP cost for later levels")

local corruptFields = {
	SchemaVersion = 0,
	Coins = 0 / 0,
	XP = math.huge,
	Wins = -3,
	OwnedTrails = { Cyan = true, Pink = "true", Unknown = true },
	EquippedTrail = "Unknown",
	QuestDay = today,
	Quests = { survive = 999, stars = -3, runs = 1.9 },
	ClaimedQuests = { survive = true, stars = "true" },
}
local normalized = assert(Data.normalize(corruptFields, today, config))
expect(normalized.SchemaVersion == 1, "Version zero migrates to current schema")
expect(
	normalized.Coins == 0 and normalized.XP == 0 and normalized.Wins == 0,
	"Non-finite and negative fields rejected"
)
expect(
	normalized.OwnedTrails.Cyan and not normalized.OwnedTrails.Unknown and not normalized.OwnedTrails.Pink,
	"Ownership allowlist"
)
expect(normalized.EquippedTrail == "None", "Unknown equipped cosmetic repaired")
expect(
	normalized.Quests.survive == 8 and normalized.Quests.stars == 0 and normalized.Quests.runs == 1,
	"Quest progress bounded"
)
expect(
	normalized.ClaimedQuests.survive and not normalized.ClaimedQuests.stars,
	"Claims require actual booleans"
)
local invalid, reason = Data.normalize("broken record", today, config)
expect(invalid == nil and reason == "InvalidRecord", "Invalid root never becomes an overwritable default")
invalid, reason = Data.normalize({ SchemaVersion = 2 }, today, config)
expect(invalid == nil and reason == "FutureSchema", "Newer saves are preserved for compatible builds")
invalid, reason = Data.normalize({ SchemaVersion = 0 / 0 }, today, config)
expect(invalid == nil and reason == "InvalidSchema", "NaN schema rejected")

local progress = Data.fresh(today)
for _ = 1, 8 do
	Data.reward(progress, "Survival", false, today, config)
end
expect(
	progress.Coins == 96 and progress.XP == 160 and progress.Quests.survive == 8,
	"Survival rewards accumulate"
)
expect(Data.claim(progress, "survive", today, config), "Completed quest can be claimed")
expect(progress.Coins == 146, "Quest reward granted")
expect(
	not Data.claim(progress, "survive", today, config) and progress.Coins == 146,
	"Repeated claim has no effect"
)
expect(not Data.claim(progress, "stars", today, config), "Incomplete quest cannot be claimed")
expect(not Data.claim(progress, "unknown", today, config), "Unknown quest cannot grant currency")
expect(
	not Data.reward(progress, "ClientMoney", true, today, config) and progress.Coins == 146,
	"Unknown reward rejected"
)
Data.reward(progress, "Survival", false, today, config)
expect(
	progress.Quests.survive == 8 and progress.Coins == 158,
	"Counters cap but legitimate gameplay still rewards"
)
expect(Data.purchase(progress, "Cyan", config), "Affordable cosmetic unlocks")
expect(
	progress.Coins == 98 and progress.OwnedTrails.Cyan and progress.EquippedTrail == "Cyan",
	"Purchase and equip atomic"
)
expect(
	not Data.purchase(progress, "Cyan", config) and progress.Coins == 98,
	"Duplicate purchase never charges twice"
)
expect(not Data.purchase(progress, "Pink", config) and progress.Coins == 98, "Insufficient balance unchanged")
expect(
	not Data.purchase(progress, "Unknown", config) and progress.Coins == 98,
	"Unlisted product cannot charge"
)
expect(not Data.equip(progress, "Gold") and progress.EquippedTrail == "Cyan", "Unowned cosmetic cannot equip")
expect(Data.equip(progress, "None") and progress.EquippedTrail == "None", "Free cosmetic can disable trail")
expect(
	not Data.rollDay(progress, today - 1) and progress.ClaimedQuests.survive,
	"Backward clock cannot duplicate claims"
)
expect(Data.rollDay(progress, today + 1) and not progress.ClaimedQuests.survive, "New UTC day resets claims")
expect(
	progress.Quests.survive == 0 and progress.Coins == 98 and progress.OwnedTrails.Cyan,
	"Daily reset preserves account progress"
)
expect(
	not Data.claim(progress, "survive", today + 1, config),
	"Yesterday completion cannot be claimed tomorrow"
)
for _ = 1, 10 do
	Data.reward(progress, "Star", false, today + 1, config)
end
expect(progress.Quests.stars == 10 and progress.Coins == 118, "Collectibles award and progress star quest")
Data.reward(progress, "Run", false, today + 1, config)
Data.reward(progress, "Run", true, today + 1, config)
expect(
	progress.Wins == 1 and progress.Quests.runs == 2 and progress.Coins == 168,
	"Completion and win bonus separate"
)
expect(
	Data.claim(progress, "runs", today + 1, config) and progress.Coins == 228,
	"Run quest can be earned naturally"
)
local snapshot = Data.clone(progress)
progress.OwnedTrails.Emerald = true
progress.Quests.runs = 0
expect(
	not snapshot.OwnedTrails.Emerald and snapshot.Quests.runs == 2,
	"Save snapshot cannot change during an async write"
)

local first = assert(Data.acquire(nil, "server-A", timestamp, 180, config))
expect(first.Session.Owner == "server-A" and first.Session.ExpiresAt == timestamp + 180, "Atomic new lease")
local blocked, blockedReason = Data.acquire(first, "server-B", timestamp + 10, 180, config)
expect(blocked == nil and blockedReason == "Busy", "Concurrent server cannot acquire a live lease")
expect(first.Session.Owner == "server-A", "Failed acquire does not mutate source record")
local refreshed = assert(Data.acquire(first, "server-A", timestamp + 10, 180, config))
expect(refreshed.Session.ExpiresAt == timestamp + 190, "Retrying own uncertain acquire is safe")
local stale = assert(Data.acquire(first, "server-B", timestamp + 181, 180, config))
expect(stale.Session.Owner == "server-B", "Expired lease can recover after a crashed server")
blocked, blockedReason = Data.prepareSave(stale, snapshot, "server-A", timestamp + 182, 180, false, "write-A")
expect(blocked == nil and blockedReason == "LeaseLost", "Old owner cannot overwrite a newly acquired profile")
blocked, blockedReason = Data.prepareSave(first, snapshot, "server-A", timestamp + 181, 180, false, "expired")
expect(blocked == nil and blockedReason == "LeaseExpired", "Expired owner cannot keep writing")
blocked, blockedReason = Data.prepareSave(nil, snapshot, "server-A", timestamp + 1, 180, false, "missing")
expect(
	blocked == nil and blockedReason == "MissingRecord",
	"Failed load cannot overwrite missing or deleted data"
)
local committed = assert(Data.prepareSave(first, snapshot, "server-A", timestamp + 1, 180, false, "write-1"))
expect(
	committed.Coins == snapshot.Coins and committed.Session.ExpiresAt == timestamp + 181,
	"Save includes snapshot and renewed lease"
)
expect(first.Coins == 0, "Prepare callback is pure and can rerun")
local conflictingSnapshot = Data.clone(snapshot)
conflictingSnapshot.Coins = 10
blocked, blockedReason =
	Data.prepareSave(committed, conflictingSnapshot, "server-A", timestamp + 2, 180, false, "write-1")
expect(
	blocked == nil and blockedReason == "AlreadyWritten" and committed.Coins == snapshot.Coins,
	"Uncertain save retry cannot replay or change an acknowledged snapshot"
)
local released =
	assert(Data.prepareSave(committed, snapshot, "server-A", timestamp + 2, 180, true, "release-1"))
expect(released.Session == nil, "Final save releases lease with data")
blocked, blockedReason =
	Data.prepareSave(released, snapshot, "server-A", timestamp + 3, 180, true, "release-1")
expect(blocked == nil and blockedReason == "AlreadyWritten", "Lost release response retry is idempotent")
local nextSession = assert(Data.acquire(released, "server-B", timestamp + 4, 180, config))
nextSession.Coins = 999
blocked, blockedReason =
	Data.prepareSave(nextSession, snapshot, "server-A", timestamp + 5, 180, true, "release-1")
expect(
	blocked == nil and blockedReason == "AlreadyWritten" and nextSession.Coins == 999,
	"Release retry cannot overwrite new session"
)
local newSchema = table.clone(first)
newSchema.SchemaVersion = 2
blocked, blockedReason =
	Data.prepareSave(newSchema, snapshot, "server-A", timestamp + 1, 180, false, "write-new-schema")
expect(blocked == nil and blockedReason == "SchemaChanged", "External schema migration blocks outdated saves")
blocked, blockedReason =
	Data.acquire({ Session = { Owner = "other", ExpiresAt = 0 / 0 } }, "server-A", timestamp, 180, config)
expect(blocked == nil and blockedReason == "InvalidLease", "Corrupt lease is never silently stolen")

local uncertain = assert(Data.releaseUncertainAcquire(first, "server-A"))
expect(uncertain.Session == nil and first.Session ~= nil, "Uncertain acquire release is pure")
expect(uncertain.Coins == first.Coins, "Uncertain acquire cleanup never writes fallback data")
expect(Data.releaseUncertainAcquire(first, "server-B") == nil, "Cleanup cannot release another session")
expect(Data.releaseUncertainAcquire(nil, "server-A") == nil, "Cleanup cannot create a default profile")
expect(Data.releaseUncertainAcquire(released, "server-A") == nil, "Cleanup safely repeats after release")
local infiniteLease = table.clone(first)
infiniteLease.Session = { Owner = "server-A", ExpiresAt = math.huge }
blocked, blockedReason =
	Data.prepareSave(infiniteLease, snapshot, "server-A", timestamp, 180, false, "infinite")
expect(blocked == nil and blockedReason == "LeaseExpired", "Non-finite lease cannot authorize a save")
print("ProfileData: " .. checks .. " checks passed")
