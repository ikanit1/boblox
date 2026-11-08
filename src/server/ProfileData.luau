--!strict
-- Pure data operations. No Instances, yields, DataStore calls, or client values.
local ProfileData = {}

-- Version 5 also protects the expanded cosmetic/rule allowlists from older v4 writers.
ProfileData.SchemaVersion = 5
local MAX_VALUE = 1_000_000_000
local QUEST_IDS = { "survive", "stars", "runs" }
local COLLECTOR_RULES = { "LowGravity", "RedLight", "ReactorRush" }

export type Profile = {
	SchemaVersion: number,
	Coins: number,
	XP: number,
	Wins: number,
	BestRunScore: number,
	BestRunSurvived: number,
	BestPracticeSeconds: number?,
	Flawless: { [string]: number },
	Mastery: { [string]: number },
	CleanCollectors: { [string]: boolean },
	UnlockedTitles: { [string]: boolean },
	EquippedTitle: string,
	Preferences: { [string]: number | boolean },
	OwnedTrails: { [string]: boolean },
	EquippedTrail: string,
	QuestDay: number,
	Quests: { [string]: number },
	ClaimedQuests: { [string]: boolean },
}

local function integer(value: any, default: number, maximum: number?): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return default
	end
	return math.clamp(math.floor(value), 0, maximum or MAX_VALUE)
end

local function finiteNonnegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function practiceSeconds(value: any): number?
	if not finiteNonnegative(value) or value <= 0 or value > MAX_VALUE then
		return nil
	end
	return value
end

function ProfileData.day(timestamp: number): number
	return math.floor(timestamp / 86400)
end

function ProfileData.level(xp: number): number
	return 1 + math.floor(math.sqrt(integer(xp, 0) / 100))
end

function ProfileData.fresh(day: number): Profile
	return {
		SchemaVersion = ProfileData.SchemaVersion,
		Coins = 0,
		XP = 0,
		Wins = 0,
		BestRunScore = 0,
		BestRunSurvived = 0,
		BestPracticeSeconds = nil,
		Flawless = {},
		Mastery = {},
		CleanCollectors = {},
		UnlockedTitles = {},
		EquippedTitle = "None",
		Preferences = {},
		OwnedTrails = { None = true },
		EquippedTrail = "None",
		QuestDay = day,
		Quests = { survive = 0, stars = 0, runs = 0 },
		ClaimedQuests = { survive = false, stars = false, runs = false },
	}
end

function ProfileData.clone(data: Profile): Profile
	return {
		SchemaVersion = data.SchemaVersion,
		Coins = data.Coins,
		XP = data.XP,
		Wins = data.Wins,
		BestRunScore = data.BestRunScore,
		BestRunSurvived = data.BestRunSurvived,
		BestPracticeSeconds = data.BestPracticeSeconds,
		Flawless = table.clone(data.Flawless),
		Mastery = table.clone(data.Mastery),
		CleanCollectors = table.clone(data.CleanCollectors),
		UnlockedTitles = table.clone(data.UnlockedTitles),
		EquippedTitle = data.EquippedTitle,
		Preferences = table.clone(data.Preferences),
		OwnedTrails = table.clone(data.OwnedTrails),
		EquippedTrail = data.EquippedTrail,
		QuestDay = data.QuestDay,
		Quests = table.clone(data.Quests),
		ClaimedQuests = table.clone(data.ClaimedQuests),
	}
end

function ProfileData.rollDay(data: Profile, day: number): boolean
	-- A backwards wall-clock change cannot reset claims and grant a second reward.
	if day <= data.QuestDay then
		return false
	end
	data.QuestDay = day
	for _, id in QUEST_IDS do
		data.Quests[id] = 0
		data.ClaimedQuests[id] = false
	end
	return true
end

function ProfileData.normalize(raw: any, day: number, config: any): (Profile?, string?)
	if raw == nil then
		return ProfileData.fresh(day), nil
	end
	if type(raw) ~= "table" then
		return nil, "InvalidRecord"
	end
	local version = raw.SchemaVersion
	if version ~= nil then
		if type(version) ~= "number" or version ~= version or version % 1 ~= 0 or version < 0 then
			return nil, "InvalidSchema"
		end
		if version > ProfileData.SchemaVersion then
			return nil, "FutureSchema"
		end
	end
	-- Legacy records survive migration. New action-qualified goals start empty:
	-- old wins and Flawless counts cannot prove a pickup or reactor contribution.
	local data = ProfileData.fresh(day)
	data.Coins = integer(raw.Coins, 0)
	data.XP = integer(raw.XP, 0)
	data.Wins = integer(raw.Wins, 0)
	data.BestRunScore = integer(raw.BestRunScore, 0)
	data.BestRunSurvived = integer(raw.BestRunSurvived, 0, integer(config.RuleCount, 6))
	data.BestPracticeSeconds = practiceSeconds(raw.BestPracticeSeconds)
	local flawless = if type(raw.Flawless) == "table" then raw.Flawless else {}
	-- The service supplies the current server rule catalog; unknown keys never persist.
	for _, ruleId in config.RuleOrder or {} do
		local count = integer(flawless[ruleId], 0)
		if count > 0 then
			data.Flawless[ruleId] = count
		end
	end
	if type(version) == "number" and version >= 3 then
		local mastery = if type(raw.Mastery) == "table" then raw.Mastery else {}
		local collectors = if type(raw.CleanCollectors) == "table" then raw.CleanCollectors else {}
		local collectorCount = 0
		for _, ruleId in COLLECTOR_RULES do
			if collectors[ruleId] == true then
				data.CleanCollectors[ruleId] = true
				collectorCount += 1
			end
		end
		for _, milestone in config.MasteryMilestones or {} do
			local progress = if milestone.Id == "Collector"
				then collectorCount
				else integer(mastery[milestone.Id], 0, milestone.Target)
			data.Mastery[milestone.Id] = progress
			-- Repair interrupted/inconsistent flags only from completed server progress.
			if progress >= milestone.Target then
				data.UnlockedTitles[milestone.Id] = true
			end
		end
		if type(raw.EquippedTitle) == "string" and data.UnlockedTitles[raw.EquippedTitle] == true then
			data.EquippedTitle = raw.EquippedTitle
		end
	end
	if type(version) == "number" and version >= 4 then
		local preferences = if type(raw.Preferences) == "table" then raw.Preferences else {}
		local policy = config.PlayerPreferences
		for _, key in policy.Keys do
			data.Preferences[key] = policy.normalize(key, preferences[key])
		end
	end
	local owned = if type(raw.OwnedTrails) == "table" then raw.OwnedTrails else {}
	for _, trail in config.Trails do
		if owned[trail.Id] == true then
			data.OwnedTrails[trail.Id] = true
		end
	end
	if type(raw.EquippedTrail) == "string" and data.OwnedTrails[raw.EquippedTrail] then
		data.EquippedTrail = raw.EquippedTrail
	end
	data.QuestDay = integer(raw.QuestDay, day)
	local progress = if type(raw.Quests) == "table" then raw.Quests else {}
	local claimed = if type(raw.ClaimedQuests) == "table" then raw.ClaimedQuests else {}
	for _, id in QUEST_IDS do
		data.Quests[id] = integer(progress[id], 0, config.Quests[id].Target)
		data.ClaimedQuests[id] = claimed[id] == true
	end
	ProfileData.rollDay(data, day)
	return data, nil
end

function ProfileData.recordRun(data: Profile, score: any, survived: any, ruleCount: number): string
	local improvedScore, improvedSurvived = false, false
	if finiteNonnegative(score) then
		local boundedScore = integer(score, 0)
		if boundedScore > data.BestRunScore then
			data.BestRunScore = boundedScore
			improvedScore = true
		end
	end
	if finiteNonnegative(survived) and finiteNonnegative(ruleCount) and ruleCount > 0 then
		local boundedSurvived = integer(survived, 0, integer(ruleCount, 0))
		if boundedSurvived > data.BestRunSurvived then
			data.BestRunSurvived = boundedSurvived
			improvedSurvived = true
		end
	end
	return if improvedScore and improvedSurvived
		then "Score,Survived"
		elseif improvedScore then "Score"
		elseif improvedSurvived then "Survived"
		else ""
end

function ProfileData.setPreference(data: Profile, key: any, value: any, policy: any): boolean
	if not policy.isValid(key, value) or data.Preferences[key] == value then
		return false
	end
	data.Preferences[key] = value
	return true
end

function ProfileData.recordPractice(data: Profile, seconds: any): boolean
	local validSeconds = practiceSeconds(seconds)
	if not validSeconds or (data.BestPracticeSeconds ~= nil and validSeconds >= data.BestPracticeSeconds) then
		return false
	end
	data.BestPracticeSeconds = validSeconds
	return true
end

function ProfileData.recordFlawless(data: Profile, ruleId: any, ruleOrder: { string }): boolean
	if type(ruleId) ~= "string" or not table.find(ruleOrder, ruleId) then
		return false
	end
	local previous = data.Flawless[ruleId] or 0
	if previous >= MAX_VALUE then
		return false
	end
	data.Flawless[ruleId] = previous + 1
	return true
end

local function progressMastery(data: Profile, id: string, value: number, config: any): boolean
	for _, milestone in config.MasteryMilestones or {} do
		if milestone.Id == id then
			local previous = data.Mastery[id] or 0
			local progress = math.max(previous, integer(value, 0, milestone.Target))
			local unlock = progress >= milestone.Target and data.UnlockedTitles[id] ~= true
			data.Mastery[id] = progress
			if unlock then
				data.UnlockedTitles[id] = true
			end
			return progress ~= previous or unlock
		end
	end
	return false
end

function ProfileData.recordRunMastery(
	data: Profile,
	won: boolean,
	survived: any,
	stars: any,
	energy: any,
	ruleCount: number,
	config: any
): boolean
	if not finiteNonnegative(survived) or survived < 1 then
		return false
	end
	local changed = false
	if finiteNonnegative(stars) and stars >= 1 then
		changed = progressMastery(data, "FirstRun", 1, config) or changed
	end
	if won == true and finiteNonnegative(energy) and energy >= 1 then
		changed = progressMastery(data, "TeamVeteran", (data.Mastery.TeamVeteran or 0) + 1, config) or changed
		if survived == ruleCount then
			changed = progressMastery(data, "PerfectRun", 1, config) or changed
		end
	end
	return changed
end

function ProfileData.recordPracticeMastery(data: Profile, seconds: any, config: any): boolean
	if not practiceSeconds(seconds) then
		return false
	end
	return progressMastery(data, "Practice", 1, config)
end

function ProfileData.recordCleanCollector(data: Profile, ruleId: any, action: any, config: any): boolean
	if action ~= "Collected" or type(ruleId) ~= "string" or not table.find(COLLECTOR_RULES, ruleId) then
		return false
	end
	if data.CleanCollectors[ruleId] then
		return false
	end
	data.CleanCollectors[ruleId] = true
	local count = 0
	for _, id in COLLECTOR_RULES do
		if data.CleanCollectors[id] then
			count += 1
		end
	end
	progressMastery(data, "Collector", count, config)
	return true
end

function ProfileData.equipTitle(data: Profile, id: string, config: any): (boolean, string)
	if id ~= "None" then
		local known = false
		for _, milestone in config.MasteryMilestones or {} do
			if milestone.Id == id then
				known = true
				break
			end
		end
		if not known or data.UnlockedTitles[id] ~= true then
			return false, "Сначала выполни цель этого титула"
		end
	end
	local changed = data.EquippedTitle ~= id
	data.EquippedTitle = id
	return changed, if id == "None" then "Титул выключен" else "Титул выбран"
end

local function add(data: Profile, coins: number, xp: number)
	data.Coins = math.min(MAX_VALUE, data.Coins + coins)
	data.XP = math.min(MAX_VALUE, data.XP + xp)
end

function ProfileData.reward(data: Profile, kind: string, won: boolean, day: number, config: any): boolean
	local questId: string
	local rewards = config.Rewards
	if kind == "Survival" then
		questId = "survive"
	elseif kind == "Star" then
		questId = "stars"
	elseif kind == "Run" then
		questId = "runs"
	else
		return false
	end
	ProfileData.rollDay(data, day)
	if kind == "Survival" then
		add(data, rewards.SurvivalCoins, rewards.SurvivalXP)
	elseif kind == "Star" then
		add(data, rewards.StarCoins, rewards.StarXP)
	else
		add(data, rewards.RunCoins + (if won then rewards.WinCoins else 0), rewards.RunXP)
		if won then
			data.Wins = math.min(MAX_VALUE, data.Wins + 1)
		end
	end
	data.Quests[questId] = math.min(config.Quests[questId].Target, data.Quests[questId] + 1)
	return true
end

function ProfileData.purchase(data: Profile, id: string, config: any): (boolean, string)
	local selected = nil
	for _, trail in config.Trails do
		if trail.Id == id then
			selected = trail
			break
		end
	end
	if not selected then
		return false, "Неизвестный след"
	end
	if data.OwnedTrails[id] then
		return false, "Этот след уже открыт"
	end
	if selected.UnlockTitle and data.UnlockedTitles[selected.UnlockTitle] ~= true then
		return false,
			"Сначала выполни цель мастерства для этого следа"
	end
	if data.Coins < selected.Price then
		return false, "Недостаточно монет"
	end
	data.Coins -= selected.Price
	data.OwnedTrails[id] = true
	data.EquippedTrail = id
	return true,
		if selected.UnlockTitle
			then "Награда за мастерство получена и выбрана!"
			else "След открыт и выбран!"
end

function ProfileData.equip(data: Profile, id: string): (boolean, string)
	if not data.OwnedTrails[id] then
		return false, "Сначала открой этот след"
	end
	data.EquippedTrail = id
	return true, if id == "None" then "След выключен" else "След выбран"
end

function ProfileData.claim(data: Profile, id: string, day: number, config: any): (boolean, string)
	local quest = config.Quests[id]
	if not quest then
		return false, "Неизвестное задание"
	end
	ProfileData.rollDay(data, day)
	if data.ClaimedQuests[id] then
		return false, "Награда уже получена"
	end
	if data.Quests[id] < quest.Target then
		return false, "Задание ещё не выполнено"
	end
	-- Claim flag and balance are changed together without yielding, then saved together.
	data.ClaimedQuests[id] = true
	add(data, quest.Reward, 0)
	return true, "+" .. quest.Reward .. " монет за задание!"
end

function ProfileData.acquire(
	raw: any,
	owner: string,
	now: number,
	leaseSeconds: number,
	config: any
): (any, string?)
	if type(raw) == "table" and raw.Session ~= nil then
		local session = raw.Session
		if
			type(session) ~= "table"
			or type(session.Owner) ~= "string"
			or type(session.ExpiresAt) ~= "number"
		then
			return nil, "InvalidLease"
		end
		if session.ExpiresAt ~= session.ExpiresAt or math.abs(session.ExpiresAt) == math.huge then
			return nil, "InvalidLease"
		end
		if session.Owner ~= owner and session.ExpiresAt > now then
			return nil, "Busy"
		end
	end
	local data, reason = ProfileData.normalize(raw, ProfileData.day(now), config)
	if not data then
		return nil, reason
	end
	local record: any = data
	record.Session = { Owner = owner, ExpiresAt = now + leaseSeconds }
	if type(raw) == "table" and type(raw.WriteToken) == "string" and #raw.WriteToken <= 128 then
		record.WriteToken = raw.WriteToken
	end
	return record, nil
end

function ProfileData.prepareSave(
	raw: any,
	data: Profile,
	owner: string,
	now: number,
	leaseSeconds: number,
	release: boolean,
	writeToken: string
): (any, string?)
	if type(raw) ~= "table" then
		return nil, "MissingRecord"
	end
	if raw.WriteToken == writeToken then
		-- Retrying an uncertain response must not rewrite data after a new owner acquired it.
		return nil, "AlreadyWritten"
	end
	if raw.SchemaVersion ~= ProfileData.SchemaVersion or data.SchemaVersion ~= ProfileData.SchemaVersion then
		return nil, "SchemaChanged"
	end
	local session = raw.Session
	if type(session) ~= "table" or session.Owner ~= owner or type(session.ExpiresAt) ~= "number" then
		return nil, "LeaseLost"
	end
	if
		session.ExpiresAt <= now
		or session.ExpiresAt ~= session.ExpiresAt
		or math.abs(session.ExpiresAt) == math.huge
	then
		return nil, "LeaseExpired"
	end
	local record: any = ProfileData.clone(data)
	record.WriteToken = writeToken
	if not release then
		record.Session = { Owner = owner, ExpiresAt = now + leaseSeconds }
	end
	return record, nil
end

-- An acquire can commit even when its response is lost. Release only our unique
-- owner token, preserving the cloud record verbatim; never write fallback data.
function ProfileData.releaseUncertainAcquire(raw: any, owner: string): any
	if type(raw) ~= "table" or type(raw.Session) ~= "table" or raw.Session.Owner ~= owner then
		return nil
	end
	local record = table.clone(raw)
	record.Session = nil
	return record
end

return ProfileData
