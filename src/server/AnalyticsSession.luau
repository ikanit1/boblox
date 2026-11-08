--!strict
-- Pure observation of server-owned state; emitted events never authorize gameplay.
local AnalyticsSession = {}
AnalyticsSession.FunnelName = "RuleRoomSessionV2"
AnalyticsSession.Version = 2

export type Event = { Kind: string, Name: string, Step: number?, Category: string? }
export type Snapshot = {
	Round: any,
	InRound: any,
	ResultReady: any,
	RunResult: any,
	DataStatus: any,
	DataPersistent: any,
}
export type Observer = {
	Observe: (Snapshot) -> (),
	Intent: (string) -> (),
	Close: () -> (),
}

local RESULTS = {
	Won = true,
	FinaleFailed = true,
	FinaleMissed = true,
	NotEnoughTrials = true,
	NoSurvival = true,
	Aborted = true,
}

local function roundNumber(value: any): number?
	return if type(value) == "number"
			and value > 0
			and value < math.huge
			and value % 1 == 0
		then value
		else nil
end

function AnalyticsSession.new(emit: (Event) -> ()): Observer
	local closed = false
	local steps: { [number]: boolean } = {}
	local profileKinds: { [string]: boolean } = {}
	local lastStarted = 0
	local lastResults = 0
	local intentAfter: number? = nil
	local previouslyPersistent = false
	local wasSaveDelayed = false
	local function custom(name: string, category: string)
		emit({ Kind = "Custom", Name = "RRV2_" .. name, Category = category })
	end
	local function step(index: number, name: string)
		if not steps[index] then
			steps[index] = true
			emit({ Kind = "Funnel", Name = name, Step = index })
		end
	end
	local function profile(kind: string)
		if not profileKinds[kind] then
			profileKinds[kind] = true
			custom("ProfileState", kind)
		end
	end
	step(1, "Joined")
	local session = {}
	function session.Observe(snapshot: Snapshot)
		if closed then
			return
		end
		local round = roundNumber(snapshot.Round)
		if round and snapshot.InRound == true and round > lastStarted then
			local first = lastStarted == 0
			local intentional = intentAfter ~= nil and round > intentAfter
			lastStarted = round
			step(2, "FirstTrialStarted")
			custom("RunStarted", if first then "First" elseif intentional then "AfterIntent" else "Automatic")
			if intentional then
				step(5, "IntentionalNextRunStarted")
				intentAfter = nil
			end
		end
		-- Availability is authoritative, but it does not prove that a GUI was viewed.
		-- Zero survivals, Forfeited and aborted runs remain observable.
		if round and round == lastStarted and snapshot.ResultReady == true and round > lastResults then
			lastResults = round
			step(3, "FirstResultsAvailable")
			local result = snapshot.RunResult
			custom(
				"ResultsAvailable",
				if type(result) == "string" and RESULTS[result] then result else "Unknown"
			)
		end
		local status = snapshot.DataStatus
		local persistent = snapshot.DataPersistent == true
		if status == "Loading" or status == nil then
			return
		elseif status == "Saved" and persistent then
			profile("Persistent")
			if wasSaveDelayed then
				profile("SaveRecovered")
			end
		elseif status == "Unavailable" and persistent then
			profile("SaveDelayed")
		elseif status == "Session" and not persistent then
			profile("SessionOnly")
		elseif status == "Busy" and not persistent then
			profile("Busy")
		elseif status == "Unavailable" and not persistent then
			profile("Unavailable")
		else
			return
		end
		if previouslyPersistent and not persistent then
			profile("PersistenceLost")
		end
		previouslyPersistent = persistent
		wasSaveDelayed = status == "Unavailable" and persistent
	end
	function session.Intent(source: string)
		if closed or lastResults == 0 or (source ~= "Join" and source ~= "Vote") or intentAfter ~= nil then
			return
		end
		-- A choice cannot retroactively turn an already auto-started run into interest.
		intentAfter = lastStarted
		step(4, "RepeatIntent")
		custom("RepeatIntent", source)
	end
	function session.Close()
		closed = true
	end
	return session
end

return AnalyticsSession
