--!strict
local Data = require("../src/server/ProfileData")
local Preferences = require("../src/shared/PlayerPreferences")

-- Domain fixture deliberately has no Roblox Color3 values; the production logic
-- accepts a server catalog, never client prices. Studio checks the presentation catalog.
local config = {
	PlayerPreferences = Preferences,
	RuleCount = 6,
	RuleOrder = {
		"SafeColor",
		"LaserSweep",
		"LowGravity",
		"RedLight",
		"ReactorRush",
		"PressureWave",
		"ChangingWalls",
	},
	MasteryMilestones = {
		{ Id = "FirstRun", Target = 1 },
		{ Id = "PerfectRun", Target = 1 },
		{ Id = "Collector", Target = 3 },
		{ Id = "Practice", Target = 1 },
		{ Id = "TeamVeteran", Target = 5 },
	},
	Trails = {
		{ Id = "None", Price = 0 },
		{ Id = "Cyan", Price = 60 },
		{ Id = "Pink", Price = 100 },
		{ Id = "Gold", Price = 180 },
		{ Id = "Emerald", Price = 260 },
		{ Id = "Aurora", Price = 0, UnlockTitle = "Practice" },
		{ Id = "Prism", Price = 0, UnlockTitle = "Collector" },
		{ Id = "Solar", Price = 0, UnlockTitle = "PerfectRun" },
		{ Id = "Nova", Price = 0, UnlockTitle = "TeamVeteran" },
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
expect(
	fresh.SchemaVersion == 5
		and fresh.BestRunScore == 0
		and fresh.BestRunSurvived == 0
		and fresh.BestPracticeSeconds == nil
		and next(fresh.Flawless) == nil,
	"New v5 profiles have empty records and no invented practice time"
)
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
expect(normalized.SchemaVersion == 5, "Version zero migrates to current schema")
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
invalid, reason = Data.normalize({ SchemaVersion = 6 }, today, config)
expect(invalid == nil and reason == "FutureSchema", "Newer saves are preserved for compatible builds")
invalid, reason = Data.normalize({ SchemaVersion = 0 / 0 }, today, config)
expect(invalid == nil and reason == "InvalidSchema", "NaN schema rejected")

for _, version in { 0, 1, 2 } do
	local legacy = {
		SchemaVersion = version,
		Coins = 321,
		XP = 456,
		Wins = 7,
		OwnedTrails = { None = true, Gold = true },
		EquippedTrail = "Gold",
		QuestDay = today,
		Quests = { survive = 8, stars = 3, runs = 1 },
		ClaimedQuests = { survive = true },
	}
	local migrated = assert(Data.normalize(legacy, today, config))
	expect(
		migrated.SchemaVersion == 5
			and migrated.Coins == 321
			and migrated.XP == 456
			and migrated.Wins == 7
			and migrated.OwnedTrails.Gold
			and migrated.EquippedTrail == "Gold"
			and migrated.Quests.survive == 8
			and migrated.Quests.stars == 3
			and migrated.Quests.runs == 1
			and migrated.ClaimedQuests.survive,
		"Migration preserves legacy currency, ownership and daily claims"
	)
	expect(
		migrated.BestRunScore == 0
			and migrated.BestRunSurvived == 0
			and migrated.BestPracticeSeconds == nil
			and next(migrated.Flawless) == nil,
		"Migration introduces empty record fields without inventing past achievements"
	)
	expect(legacy.SchemaVersion == version and legacy.Coins == 321, "Migration never mutates its input")
end
local unversioned = assert(Data.normalize({ Coins = 11, Wins = 2 }, today, config))
expect(
	unversioned.SchemaVersion == 5 and unversioned.Coins == 11 and unversioned.Wins == 2,
	"Missing version migrates"
)

local bounded = assert(Data.normalize({
	SchemaVersion = 2,
	BestRunScore = 1e12,
	BestRunSurvived = 1234.9,
	BestPracticeSeconds = 12.345,
	Flawless = {
		SafeColor = 1e12,
		LaserSweep = 3.9,
		LowGravity = -1,
		RedLight = math.huge,
		ReactorRush = "8",
		UnknownRule = 100,
		[1] = 3,
	},
}, today, config))
expect(
	bounded.BestRunScore == 1e9 and bounded.BestRunSurvived == 6,
	"Run records are bounded by scalar and trial limits"
)
expect(bounded.BestPracticeSeconds == 12.345, "Fractional practice times retain their precision")
expect(
	bounded.Flawless.SafeColor == 1e9
		and bounded.Flawless.LaserSweep == 3
		and bounded.Flawless.LowGravity == nil
		and bounded.Flawless.RedLight == nil
		and bounded.Flawless.ReactorRush == nil
		and bounded.Flawless.UnknownRule == nil
		and (bounded.Flawless :: any)[1] == nil,
	"Flawless counts use the rule allowlist and bounded nonnegative integers"
)
local invalidValues = { false, true, "5", {}, 0 / 0, math.huge, -math.huge, -1 }
for _, value in invalidValues do
	local repaired = assert(Data.normalize({
		BestRunScore = value,
		BestRunSurvived = value,
		BestPracticeSeconds = value,
		Flawless = { SafeColor = value },
	}, today, config))
	expect(
		repaired.BestRunScore == 0
			and repaired.BestRunSurvived == 0
			and repaired.BestPracticeSeconds == nil
			and repaired.Flawless.SafeColor == nil,
		"Invalid numeric record fields cannot create earned records"
	)
end
for _, value in { 0, 1e9 + 1 } do
	local repaired = assert(Data.normalize({ BestPracticeSeconds = value }, today, config))
	expect(
		repaired.BestPracticeSeconds == nil,
		"Invalid practice bounds remain absent rather than becoming a fake best"
	)
end
local malformedMastery = assert(Data.normalize({ Flawless = "not a table" }, today, config))
expect(next(malformedMastery.Flawless) == nil, "Malformed mastery becomes an empty bounded catalog")

local records = Data.fresh(today)
expect(Data.recordRun(records, 50, 2, config.RuleCount) == "Score,Survived", "Both run records improve")
expect(Data.recordRun(records, 50, 2, config.RuleCount) == "", "Equal records do not celebrate again")
expect(Data.recordRun(records, 49, 1, config.RuleCount) == "", "Worse records do not replace personal bests")
expect(Data.recordRun(records, 51, 2, config.RuleCount) == "Score", "Only score improved")
expect(Data.recordRun(records, 40, 3, config.RuleCount) == "Survived", "Only survived count improved")
for _, value in invalidValues do
	expect(
		Data.recordRun(records, value, value, config.RuleCount) == "",
		"Malformed run results cannot improve records"
	)
	expect(not Data.recordPractice(records, value), "Malformed practice results are rejected")
	expect(not Data.recordFlawless(records, value, config.RuleOrder), "Malformed rule IDs are rejected")
end
expect(
	Data.recordRun(records, 1e12, 10, config.RuleCount) == "Score,Survived",
	"Run helpers cap oversized valid numbers"
)
expect(records.BestRunScore == 1e9 and records.BestRunSurvived == 6, "Helper limits match normalization")
expect(
	not Data.recordPractice(records, 0) and not Data.recordPractice(records, 1e9 + 1),
	"Practice rejects out-of-range times"
)
expect(
	Data.recordPractice(records, 15.87) and records.BestPracticeSeconds == 15.87,
	"First practice result records exact positive time"
)
expect(
	not Data.recordPractice(records, 15.87) and not Data.recordPractice(records, 16),
	"Equal and slower practice results do not replace best"
)
expect(
	Data.recordPractice(records, 13.25) and records.BestPracticeSeconds == 13.25,
	"A faster result replaces practice best"
)
expect(
	not Data.recordFlawless(records, "UnknownRule", config.RuleOrder),
	"Unknown rule cannot create mastery"
)
expect(
	Data.recordFlawless(records, "SafeColor", config.RuleOrder) and records.Flawless.SafeColor == 1,
	"Valid flawless result increments mastery"
)
records.Flawless.SafeColor = 1e9 - 1
expect(
	Data.recordFlawless(records, "SafeColor", config.RuleOrder) and records.Flawless.SafeColor == 1e9,
	"Mastery reaches its upper bound"
)
expect(
	not Data.recordFlawless(records, "SafeColor", config.RuleOrder) and records.Flawless.SafeColor == 1e9,
	"Mastery saturates without overflow"
)
local recordsClone = Data.clone(records)
records.Flawless.SafeColor = 4
records.BestPracticeSeconds = 1
expect(
	recordsClone.Flawless.SafeColor == 1e9 and recordsClone.BestPracticeSeconds == 13.25,
	"Async snapshot owns its mastery table and records"
)
Data.rollDay(recordsClone, today + 1)
expect(
	recordsClone.BestRunScore == 1e9
		and recordsClone.BestRunSurvived == 6
		and recordsClone.BestPracticeSeconds == 13.25
		and recordsClone.Flawless.SafeColor == 1e9,
	"Daily quest rollover preserves lifetime records and mastery"
)

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
newSchema.SchemaVersion = 6
blocked, blockedReason =
	Data.prepareSave(newSchema, snapshot, "server-A", timestamp + 1, 180, false, "write-new-schema")
expect(blocked == nil and blockedReason == "SchemaChanged", "External schema migration blocks outdated saves")
local staleSnapshot = Data.clone(snapshot)
staleSnapshot.SchemaVersion = 1
blocked, blockedReason =
	Data.prepareSave(first, staleSnapshot, "server-A", timestamp + 1, 180, false, "stale-v1-snapshot")
expect(
	blocked == nil and blockedReason == "SchemaChanged" and first.SchemaVersion == 5,
	"A v1 snapshot can never replace an acquired v5 record"
)
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
local legacyRecords: any = Data.clone(bounded)
legacyRecords.SchemaVersion = 2
legacyRecords.Coins = 345
legacyRecords.Mastery = { FirstRun = 1, TeamVeteran = 5 }
legacyRecords.UnlockedTitles = { TeamVeteran = true }
legacyRecords.EquippedTitle = "TeamVeteran"
local migratedRecords = assert(Data.normalize(legacyRecords, today, config))
expect(
	migratedRecords.SchemaVersion == 5
		and migratedRecords.Coins == 345
		and migratedRecords.BestRunScore == 1e9
		and migratedRecords.BestRunSurvived == 6
		and migratedRecords.BestPracticeSeconds == 12.345
		and migratedRecords.Flawless.SafeColor == 1e9,
	"v2 migration preserves every record and the capped Flawless counter"
)
expect(
	next(migratedRecords.Mastery) == nil
		and next(migratedRecords.UnlockedTitles) == nil
		and migratedRecords.EquippedTitle == "None",
	"Legacy wins and stray future fields cannot invent action-qualified titles"
)
for _, bad in { false, "5", {}, math.huge, -math.huge, 0 / 0, -1 } do
	local repaired = assert(Data.normalize({
		SchemaVersion = 3,
		Mastery = { FirstRun = bad, PerfectRun = bad, Practice = bad, TeamVeteran = bad, Collector = 3 },
		CleanCollectors = { LowGravity = "true", RedLight = 1, Unknown = true },
		UnlockedTitles = { FirstRun = true, Collector = true, Unknown = true },
		EquippedTitle = "FirstRun",
	}, today, config))
	expect(
		repaired.Mastery.FirstRun == 0
			and repaired.Mastery.PerfectRun == 0
			and repaired.Mastery.Practice == 0
			and repaired.Mastery.TeamVeteran == 0
			and repaired.Mastery.Collector == 0
			and next(repaired.CleanCollectors) == nil
			and next(repaired.UnlockedTitles) == nil
			and repaired.EquippedTitle == "None",
		"Malformed progress and fabricated unlock flags cannot award or equip titles"
	)
end
local permanent = assert(Data.normalize({
	SchemaVersion = 3,
	Mastery = { FirstRun = 100, PerfectRun = 1.9, Practice = 1, TeamVeteran = 99, Unknown = 5 },
	CleanCollectors = { LowGravity = true, RedLight = true, ReactorRush = true, SafeColor = true },
	UnlockedTitles = "invalid",
	EquippedTitle = "Collector",
}, today, config))
for _, milestone in config.MasteryMilestones do
	expect(
		permanent.Mastery[milestone.Id] == milestone.Target and permanent.UnlockedTitles[milestone.Id] == true,
		"Completed bounded progress repairs exactly one permanent unlock flag"
	)
end
expect(
	permanent.Mastery.Unknown == nil and permanent.CleanCollectors.SafeColor == nil,
	"Mastery keys are allowlisted"
)
expect(permanent.EquippedTitle == "Collector", "Only an unlocked known title remains equipped")
local isolated = Data.clone(permanent)
isolated.Mastery.FirstRun = 0
isolated.CleanCollectors.LowGravity = nil
isolated.UnlockedTitles.Collector = nil
expect(
	permanent.Mastery.FirstRun == 1
		and permanent.CleanCollectors.LowGravity
		and permanent.UnlockedTitles.Collector,
	"Snapshot clone owns independent mastery, qualifying-rule and unlock tables"
)
Data.rollDay(permanent, today + 1)
expect(
	permanent.Mastery.TeamVeteran == 5 and permanent.UnlockedTitles.Collector,
	"Daily reset never erases permanent goals"
)

local goals = Data.fresh(today)
expect(not Data.recordRunMastery(goals, false, 0, 1, 0, 6, config), "Uncompleted runs cannot qualify")
expect(
	not Data.recordRunMastery(goals, true, 6, 0, 0, 6, config),
	"Passive perfect survival does not qualify without action"
)
expect(
	Data.recordRunMastery(goals, false, 1, 1, 0, 6, config),
	"An eligible collected run earns the first title"
)
expect(
	goals.UnlockedTitles.FirstRun and not goals.UnlockedTitles.PerfectRun,
	"First run and perfect run have separate conditions"
)
expect(
	not Data.recordRunMastery(goals, false, 6, 1, 1, 6, config),
	"A failed reactor cannot progress victory goals"
)
expect(
	Data.recordRunMastery(goals, true, 5, 1, 1, 6, config),
	"A personal reactor win with contribution counts toward veteran"
)
expect(
	goals.Mastery.TeamVeteran == 1 and not goals.UnlockedTitles.PerfectRun,
	"Five survived trials are not a perfect six"
)
expect(
	Data.recordRunMastery(goals, true, 6, 1, 1, 6, config),
	"Six-trial action-qualified victory unlocks perfect run"
)
expect(goals.UnlockedTitles.PerfectRun, "Perfect title is unlocked at its condition crossing")
for _ = 1, 8 do
	Data.recordRunMastery(goals, true, 6, 1, 1, 6, config)
end
expect(
	goals.Mastery.TeamVeteran == 5 and goals.UnlockedTitles.TeamVeteran,
	"Veteran progress saturates at five wins"
)
expect(not Data.recordRunMastery(goals, true, 6, 1, 1, 6, config), "Completed run goals never award again")
expect(not Data.recordPracticeMastery(goals, 0, config), "A zero-second finish is invalid")
expect(Data.recordPracticeMastery(goals, 30, config), "A validated practice finish unlocks its title")
expect(not Data.recordPracticeMastery(goals, 15, config), "A faster practice time cannot duplicate the title")
expect(
	not Data.recordCleanCollector(goals, "LowGravity", nil, config),
	"Flawless without a pickup does not count"
)
expect(
	not Data.recordCleanCollector(goals, "SafeColor", "Collected", config),
	"Noncollector rules cannot count"
)
expect(
	not Data.recordCleanCollector(goals, "LowGravity", true, config),
	"Only the server action literal qualifies"
)
for index, ruleId in { "LowGravity", "RedLight", "ReactorRush" } do
	expect(
		Data.recordCleanCollector(goals, ruleId, "Collected", config),
		"A distinct clean collector trial counts"
	)
	expect(
		not Data.recordCleanCollector(goals, ruleId, "Collected", config),
		"Repeating one rule is not a new distinct rule"
	)
	expect(goals.Mastery.Collector == index, "Collector progress tracks distinct clean rules")
end
expect(
	goals.UnlockedTitles.Collector and next(goals.Flawless) == nil,
	"Collector mastery does not rewrite historical Flawless statistics"
)
expect(goals.Coins == 0 and goals.XP == 0 and goals.Wins == 0, "All mastery awards are cosmetic only")
expect(Data.equipTitle(goals, "Collector", config), "Earned title can be equipped")
expect(goals.EquippedTitle == "Collector", "Equipped title uses the stable milestone ID")
expect(not Data.equipTitle(goals, "Unknown", config), "Unknown title cannot be equipped")
expect(not Data.equipTitle(Data.fresh(today), "FirstRun", config), "Locked title cannot be equipped")
expect(Data.equipTitle(goals, "None", config) and goals.EquippedTitle == "None", "Title can be disabled")

-- Exercise the production compatibility guards with the previous schema ceiling.
-- This is a guard-level rollback adapter, not execution of a historical server binary.
local v3Record = assert(Data.acquire(nil, "rollback-owner", timestamp, 180, config))
v3Record.SchemaVersion = 3
v3Record.Mastery.FirstRun = 1
v3Record.UnlockedTitles.FirstRun = true
v3Record.FutureMarker = "preserve"
local v2Snapshot = Data.clone(v3Record)
v2Snapshot.SchemaVersion = 2
Data.SchemaVersion = 2
local refused, refusal = Data.normalize(v3Record, today, config)
expect(
	refused == nil and refusal == "FutureSchema",
	"v2 schema ceiling rejects loading v3 instead of downgrading it"
)
refused, refusal =
	Data.prepareSave(v3Record, v2Snapshot, "rollback-owner", timestamp + 1, 180, false, "rollback-write")
expect(
	refused == nil and refusal == "SchemaChanged",
	"An in-flight v2 snapshot cannot overwrite a migrated v3 record"
)
local preservedV3 = assert(Data.releaseUncertainAcquire(v3Record, "rollback-owner"))
expect(
	preservedV3.SchemaVersion == 3
		and preservedV3.Mastery.FirstRun == 1
		and preservedV3.UnlockedTitles.FirstRun
		and preservedV3.FutureMarker == "preserve"
		and preservedV3.Session == nil,
	"Rollback lease release preserves all v3 fields verbatim"
)
Data.SchemaVersion = 5

expect(
	next(fresh.Preferences) == nil,
	"New profiles distinguish absent preferences from explicit false or zero"
)
expect(
	Preferences.Defaults.EffectsVolume == 1
		and Preferences.Defaults.MusicVolume == 0.5
		and Preferences.Defaults.AudioMuted == false
		and Preferences.Defaults.ReducedMotion == false,
	"Shared defaults are presentation defaults, not invented player choices"
)
local v3Mastery: any = Data.clone(permanent)
v3Mastery.SchemaVersion = 3
v3Mastery.Coins, v3Mastery.XP, v3Mastery.Wins = 333, 900, 14
v3Mastery.BestRunScore, v3Mastery.BestRunSurvived, v3Mastery.BestPracticeSeconds = 444, 6, 12.25
v3Mastery.Flawless.LowGravity = 9
v3Mastery.OwnedTrails.Gold, v3Mastery.EquippedTrail = true, "Gold"
v3Mastery.Quests.stars, v3Mastery.ClaimedQuests.stars = 10, true
v3Mastery.Preferences = { MusicVolume = 1, ReducedMotion = false }
local migratedV3 = assert(Data.normalize(v3Mastery, today + 1, config))
expect(
	migratedV3.SchemaVersion == 5
		and migratedV3.Mastery.TeamVeteran == 5
		and migratedV3.Mastery.Collector == 3
		and migratedV3.CleanCollectors.RedLight
		and migratedV3.UnlockedTitles.Collector
		and migratedV3.EquippedTitle == "Collector",
	"v3-to-v5 migration preserves completed permanent goals, distinct clean rules and equipped title"
)
expect(
	migratedV3.Coins == 333
		and migratedV3.XP == 900
		and migratedV3.Wins == 14
		and migratedV3.BestRunScore == 444
		and migratedV3.BestRunSurvived == 6
		and migratedV3.BestPracticeSeconds == 12.25
		and migratedV3.Flawless.LowGravity == 9
		and migratedV3.OwnedTrails.Gold
		and migratedV3.EquippedTrail == "Gold"
		and migratedV3.Quests.stars == 10
		and migratedV3.ClaimedQuests.stars,
	"v4 migration does not erase existing balances, records, cosmetics or current-day quests"
)
expect(
	next(migratedV3.Preferences) == nil and v3Mastery.SchemaVersion == 3,
	"Legacy profiles acquire no invented preferences and normalization remains pure"
)
local prefProfile = assert(Data.normalize({
	SchemaVersion = 4,
	Preferences = {
		EffectsVolume = -3,
		MusicVolume = 8,
		AudioMuted = false,
		ReducedMotion = true,
		Coins = 999,
	},
}, today, config))
expect(
	prefProfile.Preferences.EffectsVolume == 0
		and prefProfile.Preferences.MusicVolume == 1
		and prefProfile.Preferences.AudioMuted == false
		and prefProfile.Preferences.ReducedMotion == true
		and prefProfile.Preferences.Coins == nil,
	"Stored finite volumes clamp and explicit booleans survive the preference allowlist"
)
for _, malformed in { false, "settings", 7 } do
	local repaired = assert(Data.normalize({ SchemaVersion = 4, Preferences = malformed }, today, config))
	expect(next(repaired.Preferences) == nil, "Malformed settings maps normalize to absent choices")
end
for _, bad in { false, true, {}, "0.5", 0 / 0, math.huge, -math.huge } do
	local repaired = assert(
		Data.normalize(
			{ SchemaVersion = 4, Preferences = { EffectsVolume = bad, MusicVolume = bad } },
			today,
			config
		)
	)
	expect(
		repaired.Preferences.EffectsVolume == nil and repaired.Preferences.MusicVolume == nil,
		"Non-numeric and non-finite stored volumes stay absent"
	)
end
for _, bad in { 0, 1, {}, "true", 0 / 0 } do
	local repaired = assert(
		Data.normalize(
			{ SchemaVersion = 4, Preferences = { AudioMuted = bad, ReducedMotion = bad } },
			today,
			config
		)
	)
	expect(
		repaired.Preferences.AudioMuted == nil and repaired.Preferences.ReducedMotion == nil,
		"Boolean preferences require actual booleans"
	)
end
for _, key in { "EffectsVolume", "MusicVolume" } do
	for _, value in { 0, 0.25, 0.5, 0.75, 1, 0.123 } do
		expect(Preferences.isValid(key, value), "Volume request accepts finite values in the unit interval")
	end
	for _, invalidValue in { -0.001, 1.001, false, {}, "1", 0 / 0, math.huge, -math.huge } do
		expect(
			not Data.setPreference(prefProfile, key, invalidValue, Preferences),
			"Invalid volume requests are rejected instead of clamped"
		)
	end
end
expect(
	not Data.setPreference(prefProfile, "Unknown", true, Preferences),
	"Unknown preference cannot become stored data"
)
expect(not Data.setPreference(prefProfile, {}, 1, Preferences), "Malformed preference key is rejected")
expect(
	not Data.setPreference(prefProfile, "AudioMuted", nil, Preferences),
	"Missing choice cannot silently reset an explicit preference"
)
local explicit = Data.fresh(today)
expect(
	Data.setPreference(explicit, "AudioMuted", false, Preferences),
	"First explicit false differs from default absence"
)
expect(
	not Data.setPreference(explicit, "AudioMuted", false, Preferences),
	"Repeated identical preference is idempotent data mutation"
)
expect(Data.setPreference(explicit, "MusicVolume", 0, Preferences), "Explicit zero volume is preserved")
local prefSnapshot = Data.clone(explicit)
prefSnapshot.Preferences.AudioMuted = true
expect(explicit.Preferences.AudioMuted == false, "Preference snapshots deep-copy the choice map")
expect(
	explicit.Coins == 0 and explicit.XP == 0 and explicit.Wins == 0 and explicit.Quests.stars == 0,
	"Preference changes never award economy or quest progress"
)
expect(
	Preferences.effectiveReducedMotion(false, true),
	"Saved false cannot override a device request to reduce motion"
)
expect(
	Preferences.effectiveReducedMotion(nil, true),
	"Absent player choice still respects device accessibility"
)
expect(
	Preferences.effectiveReducedMotion(true, false),
	"Explicit player preference may further reduce motion"
)
expect(
	not Preferences.effectiveReducedMotion(false, false),
	"Motion stays enabled only when neither source requests reduction"
)

local v4Record = assert(Data.acquire(nil, "v3-owner", timestamp, 180, config))
v4Record.SchemaVersion = 4
v4Record.Mastery.FirstRun, v4Record.UnlockedTitles.FirstRun = 1, true
v4Record.Preferences = { MusicVolume = 0.25, AudioMuted = false, ReducedMotion = true }
local v3Snapshot = Data.clone(v4Record)
v3Snapshot.SchemaVersion = 3
Data.SchemaVersion = 3
refused, refusal = Data.normalize(v4Record, today, config)
expect(refused == nil and refusal == "FutureSchema", "Previous v3 ceiling refuses loading v4 preference data")
refused, refusal = Data.prepareSave(v4Record, v3Snapshot, "v3-owner", timestamp + 1, 180, false, "v3-write")
expect(
	refused == nil and refusal == "SchemaChanged",
	"An already-loaded v3 writer cannot erase a migrated v4 preference map"
)
local retainedV4 = assert(Data.releaseUncertainAcquire(v4Record, "v3-owner"))
expect(
	retainedV4.SchemaVersion == 4
		and retainedV4.Preferences.MusicVolume == 0.25
		and retainedV4.Preferences.AudioMuted == false
		and retainedV4.Preferences.ReducedMotion == true
		and retainedV4.UnlockedTitles.FirstRun
		and retainedV4.Session == nil,
	"Previous ceiling lease cleanup preserves all preference and mastery fields"
)
Data.SchemaVersion = 5

for _, item in config.Trails do
	if item.UnlockTitle then
		local rewardData = Data.fresh(today)
		rewardData.Coins = 1_000
		expect(not Data.purchase(rewardData, item.Id, config), "Coins cannot bypass a mastery unlock")
		expect(
			rewardData.Coins == 1_000 and not rewardData.OwnedTrails[item.Id],
			"Rejected claim changes nothing"
		)
		rewardData.Mastery[item.UnlockTitle] = 99
		expect(
			not Data.purchase(rewardData, item.Id, config),
			"A progress counter alone does not unlock a reward"
		)
		rewardData.UnlockedTitles[item.UnlockTitle] = true
		expect(Data.purchase(rewardData, item.Id, config), "A qualified mastery reward is claimable")
		expect(
			rewardData.Coins == 1_000
				and rewardData.OwnedTrails[item.Id]
				and rewardData.EquippedTrail == item.Id,
			"Claim atomically owns and equips the reward without a currency mutation"
		)
		expect(not Data.purchase(rewardData, item.Id, config), "Repeated claims are idempotent")
		local reloaded = assert(Data.normalize(Data.clone(rewardData), today, config))
		expect(
			reloaded.SchemaVersion == 5
				and reloaded.OwnedTrails[item.Id]
				and reloaded.EquippedTrail == item.Id,
			"The v5 ownership map persists the new style"
		)
	end
end
do
	local legacy = Data.fresh(today)
	legacy.SchemaVersion = 4
	legacy.Coins, legacy.XP, legacy.Wins = 91, 900, 7
	legacy.OwnedTrails.Cyan, legacy.EquippedTrail = true, "Cyan"
	legacy.Mastery.Practice, legacy.UnlockedTitles.Practice = 1, true
	legacy.Preferences = { AudioMuted = false, MusicVolume = 0.25 }
	local migrated = assert(Data.normalize(legacy, today, config))
	expect(
		migrated.SchemaVersion == 5 and migrated.Coins == 91 and migrated.XP == 900 and migrated.Wins == 7,
		"v4-to-v5 migration retains the existing progression"
	)
	expect(
		migrated.Preferences.AudioMuted == false
			and migrated.Preferences.MusicVolume == 0.25
			and migrated.UnlockedTitles.Practice
			and migrated.OwnedTrails.Cyan
			and migrated.EquippedTrail == "Cyan",
		"v5 preserves explicit preferences, mastery and previous cosmetics"
	)
	expect(
		not migrated.OwnedTrails.Aurora and migrated.Flawless.PressureWave == nil,
		"Migration does not fabricate new claims or challenge completions"
	)
	expect(
		Data.purchase(migrated, "Aurora", config),
		"Previously earned mastery qualifies for its new reward"
	)
	Data.recordFlawless(migrated, "PressureWave", config.RuleOrder)
	Data.recordFlawless(migrated, "ChangingWalls", config.RuleOrder)
	local record: any = Data.clone(migrated)
	record.Session = { Owner = "old-v4-owner", ExpiresAt = timestamp + 180 }
	local oldSnapshot = Data.clone(legacy)
	Data.SchemaVersion = 4
	local loaded, loadReason = Data.normalize(record, today, config)
	expect(
		loaded == nil and loadReason == "FutureSchema",
		"A v4 ceiling refuses v5 before applying its obsolete allowlists"
	)
	local saved, saveReason =
		Data.prepareSave(record, oldSnapshot, "old-v4-owner", timestamp + 1, 180, false, "old-write")
	expect(
		saved == nil and saveReason == "SchemaChanged",
		"An in-flight v4 snapshot cannot erase new v5 catalog entries"
	)
	local releasedV5 = assert(Data.releaseUncertainAcquire(record, "old-v4-owner"))
	expect(
		releasedV5.OwnedTrails.Aurora
			and releasedV5.Flawless.PressureWave == 1
			and releasedV5.Flawless.ChangingWalls == 1
			and releasedV5.Preferences.AudioMuted == false
			and releasedV5.Session == nil,
		"Old lease cleanup preserves new cosmetic and challenge ids verbatim"
	)
	Data.SchemaVersion = 5
end
print("ProfileData: " .. checks .. " checks passed")
