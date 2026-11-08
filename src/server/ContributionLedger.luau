--!strict
-- Presentation-only run history. No player references, profile writes or rewards.
local ContributionLedger = {}
ContributionLedger.MaxEntries = 72
ContributionLedger.MaxBytes = 32_000
local MAX_VALUE = 1_000_000_000
local OUTCOMES = {
	Won = true,
	FinaleFailed = true,
	FinaleMissed = true,
	NotEnoughTrials = true,
	NoSurvival = true,
	Aborted = true,
}

export type Row = {
	UserId: number,
	Name: string,
	Survived: number,
	Score: number,
	Energy: number,
	Outcome: string,
	Left: boolean,
}
export type Snapshot = { Version: number, Round: number, Players: { Row }, Truncated: boolean }
type Entry = {
	row: Row,
	token: number,
	active: boolean,
	baseScore: number,
	baseSurvived: number,
	baseEnergy: number,
}
export type Ledger = {
	Admit: (userId: number, name: string) -> number?,
	Update: (
		userId: number,
		token: number?,
		score: number,
		survived: number,
		energy: number,
		outcome: string?
	) -> (),
	Leave: (userId: number, token: number?) -> (),
	Snapshot: (round: number) -> Snapshot,
	Encode: (round: number, encoder: (any) -> string) -> string,
	Reset: () -> (),
}

local function bounded(value: any, maximum: number): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.clamp(math.floor(value), 0, maximum)
end

local function safeName(value: any): string
	if type(value) ~= "string" then
		return "Игрок"
	end
	local clean = value:gsub("%c", "")
	local length = utf8.len(clean)
	if not length or length == 0 then
		return "Игрок"
	end
	if length > 24 then
		local last = utf8.offset(clean, 25)
		clean = string.sub(clean, 1, (last :: number) - 1)
	end
	return clean
end

function ContributionLedger.new(capacity: number, ruleCount: number): Ledger
	local limit =
		math.clamp(bounded(capacity, ContributionLedger.MaxEntries), 1, ContributionLedger.MaxEntries)
	local trialLimit = math.clamp(bounded(ruleCount, 6), 1, 6)
	local entries: { Entry } = {}
	local byUserId: { [number]: Entry } = {}
	local nextToken = 0
	local truncated = false
	local ledger = {} :: Ledger

	function ledger.Admit(userId: number, name: string): number?
		if type(userId) ~= "number" or userId == 0 or userId % 1 ~= 0 or math.abs(userId) > 1e12 then
			return nil
		end
		local entry = byUserId[userId]
		if entry and entry.active then
			return entry.token
		end
		if not entry then
			if #entries >= limit then
				truncated = true
				return nil
			end
			entry = {
				row = {
					UserId = userId,
					Name = safeName(name),
					Survived = 0,
					Score = 0,
					Energy = 0,
					Outcome = "Aborted",
					Left = false,
				},
				token = 0,
				active = false,
				baseScore = 0,
				baseSurvived = 0,
				baseEnergy = 0,
			}
			byUserId[userId] = entry
			table.insert(entries, entry)
		end
		-- A returning identity gets one new segment. Old callbacks cannot write it.
		nextToken += 1
		entry.token = nextToken
		entry.active = true
		entry.baseScore, entry.baseSurvived, entry.baseEnergy =
			entry.row.Score, entry.row.Survived, entry.row.Energy
		entry.row.Name = safeName(name)
		entry.row.Left = false
		entry.row.Outcome = "Aborted"
		return entry.token
	end

	function ledger.Update(
		userId: number,
		token: number?,
		score: number,
		survived: number,
		energy: number,
		outcome: string?
	)
		local entry = byUserId[userId]
		if not entry or not entry.active or entry.token ~= token then
			return
		end
		entry.row.Score =
			math.max(entry.row.Score, math.min(MAX_VALUE, entry.baseScore + bounded(score, MAX_VALUE)))
		entry.row.Survived = math.max(
			entry.row.Survived,
			math.min(trialLimit, entry.baseSurvived + bounded(survived, trialLimit))
		)
		entry.row.Energy =
			math.max(entry.row.Energy, math.min(MAX_VALUE, entry.baseEnergy + bounded(energy, MAX_VALUE)))
		if outcome ~= nil and OUTCOMES[outcome] then
			entry.row.Outcome = outcome
		end
	end

	function ledger.Leave(userId: number, token: number?)
		local entry = byUserId[userId]
		if entry and entry.active and entry.token == token then
			entry.active = false
			entry.row.Left = true
			entry.row.Outcome = "Left"
		end
	end

	function ledger.Snapshot(round: number): Snapshot
		local rows = {}
		for _, entry in entries do
			table.insert(rows, table.clone(entry.row))
		end
		return { Version = 1, Round = bounded(round, MAX_VALUE), Players = rows, Truncated = truncated }
	end

	function ledger.Encode(round: number, encoder: (any) -> string): string
		local snapshot = ledger.Snapshot(round)
		while true do
			local ok, encoded = pcall(encoder, snapshot)
			if ok and type(encoded) == "string" and #encoded <= ContributionLedger.MaxBytes then
				return encoded
			end
			if #snapshot.Players == 0 then
				-- Keep game flow intact even if a presentation-only serializer fails.
				return '{"Version":1,"Round":' .. snapshot.Round .. ',"Players":[],"Truncated":true}'
			end
			table.remove(snapshot.Players)
			snapshot.Truncated = true
		end
	end

	function ledger.Reset()
		table.clear(entries)
		table.clear(byUserId)
		truncated = false
		-- Tokens remain monotonic so delayed callbacks from a previous run stay stale.
	end

	return ledger
end

return ContributionLedger
