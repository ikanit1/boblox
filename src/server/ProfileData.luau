--!strict
-- Pure data operations. No Instances, yields, DataStore calls, or client values.
local ProfileData = {}

ProfileData.SchemaVersion = 1
local MAX_VALUE = 1_000_000_000
local QUEST_IDS = { "survive", "stars", "runs" }

export type Profile = {
	SchemaVersion: number,
	Coins: number,
	XP: number,
	Wins: number,
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
	-- Version 0/missing schema used the same basic scalar fields. Normalize into v1.
	local data = ProfileData.fresh(day)
	data.Coins = integer(raw.Coins, 0)
	data.XP = integer(raw.XP, 0)
	data.Wins = integer(raw.Wins, 0)
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
	if data.Coins < selected.Price then
		return false, "Недостаточно монет"
	end
	data.Coins -= selected.Price
	data.OwnedTrails[id] = true
	data.EquippedTrail = id
	return true, "След открыт и выбран!"
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
	if raw.SchemaVersion ~= ProfileData.SchemaVersion then
		return nil, "SchemaChanged"
	end
	local session = raw.Session
	if type(session) ~= "table" or session.Owner ~= owner or type(session.ExpiresAt) ~= "number" then
		return nil, "LeaseLost"
	end
	if session.ExpiresAt <= now or session.ExpiresAt ~= session.ExpiresAt then
		return nil, "LeaseExpired"
	end
	local record: any = ProfileData.clone(data)
	record.WriteToken = writeToken
	if not release then
		record.Session = { Owner = owner, ExpiresAt = now + leaseSeconds }
	end
	return record, nil
end

return ProfileData
