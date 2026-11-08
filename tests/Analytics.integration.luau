--!strict
-- Production analytics script with local services/clock; no Creator Analytics delivery.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Session = require("../src/server/AnalyticsSession")
local checks, scenarios = 0, 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local item = { Active = true, Callback = callback }
			table.insert(listeners, item)
			return {
				Disconnect = function()
					item.Active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, item in listeners do
				if item.Active then
					item.Callback(...)
				end
			end
		end,
	}
end
local function object(initial: any?)
	local attrs, signals = initial or {}, {}
	local obj: any = {}
	function obj:GetAttribute(name)
		return attrs[name]
	end
	function obj:GetAttributeChangedSignal(name)
		if not signals[name] then
			signals[name] = signal()
		end
		return signals[name]
	end
	function obj:SetAttribute(name, value)
		local previous = attrs[name]
		attrs[name] = value
		if previous ~= value and signals[name] then
			signals[name]:Fire()
		end
	end
	return obj
end
local function harness(studio: boolean, gameId: number)
	scenarios += 1
	local h: any = {
		Now = 0,
		Tasks = {},
		Calls = {},
		Warnings = {},
		Sequence = 0,
		FailFunnel = 0,
		FailCustom = false,
		Pause = false,
	}
	local function schedule(thread, at)
		h.Sequence += 1
		table.insert(h.Tasks, { Thread = thread, At = at, Order = h.Sequence })
	end
	function h:Advance(seconds)
		local target, iterations = self.Now + seconds, 0
		while true do
			table.sort(self.Tasks, function(a, b)
				return a.At < b.At or (a.At == b.At and a.Order < b.Order)
			end)
			local item = self.Tasks[1]
			if not item or item.At > target then
				break
			end
			table.remove(self.Tasks, 1)
			self.Now = item.At
			local ok, delay = coroutine.resume(item.Thread)
			assert(ok, tostring(delay))
			if coroutine.status(item.Thread) ~= "dead" then
				schedule(item.Thread, self.Now + (delay or 0))
			end
			iterations += 1
			assert(iterations < 5000, "Fixture task runaway")
		end
		self.Now = target
	end
	h.Player = object({
		DataStatus = "Session",
		DataPersistent = false,
		InRound = false,
		ResultReady = false,
		RunResult = "None",
		AnalyticsJoinIntent = 0,
	})
	h.Players = { PlayerAdded = signal(), PlayerRemoving = signal(), List = { h.Player } }
	function h.Players:GetPlayers()
		return table.clone(self.List)
	end
	h.State = object({ Round = 0, Phase = "Waiting" })
	h.Destroying = signal()
	local analytics = {}
	function analytics:LogFunnelStepEvent(player, name, id, step, label)
		table.insert(
			h.Calls,
			{ Kind = "Funnel", Player = player, Funnel = name, Id = id, Step = step, Name = label }
		)
		if h.Pause then
			coroutine.yield(100)
		end
		if h.FailFunnel > 0 then
			h.FailFunnel -= 1
			error("Simulated funnel failure")
		end
	end
	function analytics:LogCustomEvent(player, name, value, fields)
		table.insert(
			h.Calls,
			{ Kind = "Custom", Player = player, Name = name, Value = value, Category = fields.CustomField01 }
		)
		if h.FailCustom then
			error("Simulated custom failure")
		end
	end
	local services = {
		AnalyticsService = analytics,
		HttpService = {
			GenerateGUID = function()
				return "local-test-session"
			end,
		},
		Players = h.Players,
		ReplicatedStorage = {
			WaitForChild = function(_, name)
				assert(name == "RuleRoomState", "Analytics must use the authored state")
				return h.State
			end,
		},
		RunService = {
			IsStudio = function()
				return studio
			end,
		},
	}
	local gameMock = { GameId = gameId }
	function gameMock:GetService(name)
		return assert(services[name], name)
	end
	function gameMock:BindToClose(callback)
		h.Shutdown = callback
	end
	luau.load(fs.readFile("src/server/Analytics.server.luau"), {
		debugName = "PRODUCTION_Analytics",
		environment = {
			game = gameMock,
			script = { Parent = { AnalyticsSession = Session }, Destroying = h.Destroying },
			require = function(module)
				return module
			end,
			Enum = { AnalyticsCustomFieldKeys = { CustomField01 = { Name = "CustomField01" } } },
			task = {
				defer = function(callback)
					schedule(coroutine.create(callback), h.Now)
				end,
				wait = coroutine.yield,
			},
			warn = function(message)
				table.insert(h.Warnings, message)
			end,
		},
	})()
	function h:Count(name, category)
		local count = 0
		for _, call in self.Calls do
			if call.Name == name and (category == nil or call.Category == category) then
				count += 1
			end
		end
		return count
	end
	function h:Enter(round)
		self.State:SetAttribute("Round", round)
		self.State:SetAttribute("Phase", "Rule")
		self.Player:SetAttribute("ResultReady", false)
		self.Player:SetAttribute("RunResult", "None")
		self.Player:SetAttribute("InRound", true)
		self:Advance(0)
	end
	function h:Results(result)
		self.Player:SetAttribute("InRound", false)
		-- Deliberately reverse the production result writes within one callback turn.
		self.Player:SetAttribute("ResultReady", true)
		self.Player:SetAttribute("RunResult", result or "NoSurvival")
		self.State:SetAttribute("Phase", "Results")
		self:Advance(0)
	end
	function h:Leave()
		self.Players.List = {}
		self.Players.PlayerRemoving:Fire(self.Player)
	end
	return h
end

for _, flags in { { true, 123 }, { false, 0 } } do
	local h = harness(flags[1], flags[2])
	h:Advance(2)
	expect(
		#h.Calls == 0 and h.Player:GetAttribute("AnalyticsDeliveryEnabled") == false,
		"Studio and unpublished guards prevent external delivery"
	)
	h:Enter(4)
	h:Results("NoSurvival")
	expect(
		h.Player:GetAttribute("AnalyticsStep") == 3,
		"Zero-survival late entrant reaches results without SessionRuns"
	)
	h:Enter(5)
	expect(h.Player:GetAttribute("AnalyticsStep") == 3, "Automatic repeat does not imply intent")
	h.Destroying:Fire()
end

do
	local h = harness(false, 123)
	expect(#h.Calls == 0, "Logging is detached from the PlayerAdded callback")
	h:Advance(1)
	expect(
		h:Count("Joined") == 1 and h.Player:GetAttribute("AnalyticsVersion") == 2,
		"Versioned session emits once"
	)
	expect(h.Calls[1].Funnel == "RuleRoomSessionV2", "Old funnel semantics are not silently replaced")
	h.Player:SetAttribute("ResultReady", true)
	h:Advance(0)
	expect(h.Player:GetAttribute("AnalyticsStep") == 1, "Explorer does not claim participant results")
	h:Enter(7)
	h:Results("FinaleMissed")
	h:Advance(1)
	expect(
		h:Count("FirstResultsAvailable") == 1 and h:Count("RRV2_ResultsAvailable", "FinaleMissed") == 1,
		"Forfeited finale is measured as results, not a win"
	)
	h.Player:SetAttribute("ResultReady", false)
	h.Player:SetAttribute("ResultReady", true)
	h:Advance(1)
	expect(h:Count("FirstResultsAvailable") == 1, "Repeated readiness deduplicates")
	h.Player:SetAttribute("AnalyticsJoinIntent", 1)
	h:Advance(0)
	expect(h.Player:GetAttribute("AnalyticsStep") == 4, "Accepted server Join records repeat intent")
	h.Player:SetAttribute("AnalyticsJoinIntent", 2)
	h:Advance(0)
	h:Enter(8)
	h:Advance(2)
	expect(
		h:Count("RRV2_RepeatIntent", "Join") == 1,
		"Repeated Join before admission does not duplicate intent"
	)
	expect(
		h:Count("IntentionalNextRunStarted") == 1 and h:Count("RRV2_RunStarted", "AfterIntent") == 1,
		"Next admission is separately observed"
	)
	h.Shutdown()
end

do
	local h = harness(false, 123)
	h:Enter(1)
	h:Results()
	h.Player:SetAttribute("VotedMode", "Reflex")
	h:Advance(0)
	expect(h.Player:GetAttribute("AnalyticsStep") == 3, "Mode changes outside Voting are not accepted votes")
	h.State:SetAttribute("Phase", "Voting")
	h.Player:SetAttribute("VotedMode", "bad input")
	h:Advance(0)
	expect(h.Player:GetAttribute("AnalyticsStep") == 3, "Unknown vote does not count as intention")
	h.Player:SetAttribute("VotedMode", "Balanced")
	h:Advance(0)
	expect(h.Player:GetAttribute("AnalyticsStep") == 4, "A valid server vote is explicit repeat intent")
	h:Enter(2)
	h:Advance(3)
	expect(
		h:Count("RRV2_RepeatIntent", "Vote") == 1,
		"Accepted vote source has a fixed low-cardinality label"
	)
	h.Shutdown()
end

do
	local h = harness(false, 123)
	h.Player:SetAttribute("DataStatus", "Saved")
	h.Player:SetAttribute("DataPersistent", true)
	h:Advance(1)
	expect(
		h:Count("RRV2_ProfileState", "Persistent") == 1,
		"Deferred snapshot tolerates status/persistence write order"
	)
	h.Player:SetAttribute("DataStatus", "Unavailable")
	h:Advance(1)
	expect(
		h:Count("RRV2_ProfileState", "SaveDelayed") == 1
			and h:Count("RRV2_ProfileState", "PersistenceLost") == 0,
		"Delayed save retains a live lease"
	)
	h.Player:SetAttribute("DataStatus", "Saved")
	h:Advance(1)
	h.Player:SetAttribute("DataPersistent", false)
	h.Player:SetAttribute("DataStatus", "Unavailable")
	h:Advance(1)
	expect(
		h:Count("RRV2_ProfileState", "SaveRecovered") == 1
			and h:Count("RRV2_ProfileState", "PersistenceLost") == 1,
		"Recovery and persistence loss remain distinct"
	)
	h.Shutdown()
end

do
	local h = harness(false, 123)
	h.FailFunnel, h.FailCustom = 1000, true
	h:Advance(10)
	expect(h:Count("Joined") == 3, "Funnel failures stop after three attempts")
	expect(h:Count("RRV2_ProfileState") == 1, "Non-idempotent custom failures are not retried")
	expect(h.Player:GetAttribute("AnalyticsDeliveryFailures") == 4, "Failed attempts are visible locally")
	expect(
		h.Player:GetAttribute("AnalyticsQueueDepth") == 0 and #h.Tasks == 0,
		"Exhausted delivery leaves no endless retries"
	)
	expect(#h.Warnings == 1, "Failures have one bounded warning, without raw user data")
	for index = 1, 3 do
		expect(
			h.Calls[index].Id == h.Calls[1].Id and h.Calls[index].Step == 1,
			"Funnel retry preserves its dedupe identity"
		)
	end
	h.Shutdown()
end

do
	local h = harness(false, 123)
	h.Pause = true
	h:Advance(0)
	for round = 1, 40 do
		h:Enter(round)
		h:Results()
	end
	expect(
		h.Player:GetAttribute("AnalyticsQueueDepth") == 32 and h.Player:GetAttribute("AnalyticsDropped") > 0,
		"Slow provider cannot grow the queue beyond 32 events"
	)
	local before = #h.Calls
	h:Leave()
	h:Advance(200)
	expect(#h.Calls == before, "Late provider response after leave cannot send queued events")
	h.Player:SetAttribute("AnalyticsJoinIntent", 500)
	h:Advance(0)
	expect(#h.Calls == before, "Leave disconnects player event listeners")
	h.Shutdown()
	h.Shutdown()
	local late = object()
	h.Players.PlayerAdded:Fire(late)
	expect(late:GetAttribute("AnalyticsVersion") == nil, "Shutdown disconnects global listeners")
end
print("Analytics integration: " .. checks .. " checks passed in " .. scenarios .. " scenarios")
