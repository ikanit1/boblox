--!strict
-- Server-only analytics with bounded asynchronous delivery. No client telemetry remote.
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AnalyticsSession = require(script.Parent.AnalyticsSession)

local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local enabled = not RunService:IsStudio() and game.GameId > 0
local MAX_QUEUE = 32
local MAX_FUNNEL_ATTEMPTS = 3
local MODES = { Balanced = true, Reflex = true, Cosmic = true }
type Event = AnalyticsSession.Event
type Scope = {
	Active: boolean,
	Connections: { RBXScriptConnection },
	Queue: { Event },
	Working: boolean,
	Pending: boolean,
	Session: AnalyticsSession.Observer?,
	Id: string,
	Events: number,
	Dropped: number,
	Failures: number,
}
local scopes: { [Player]: Scope } = {}
local connections: { RBXScriptConnection } = {}
local closed = false
local warned = false

local function addPlayer(player: Player)
	if closed or scopes[player] then
		return
	end
	local scope: Scope = {
		Active = true,
		Connections = {},
		Queue = {},
		Working = false,
		Pending = false,
		Session = nil,
		Id = HttpService:GenerateGUID(false),
		Events = 0,
		Dropped = 0,
		Failures = 0,
	}
	scopes[player] = scope
	player:SetAttribute("AnalyticsVersion", AnalyticsSession.Version)
	player:SetAttribute("AnalyticsDeliveryEnabled", enabled)
	player:SetAttribute("AnalyticsStep", 0)
	player:SetAttribute("AnalyticsQueueDepth", 0)
	player:SetAttribute("AnalyticsDropped", 0)
	player:SetAttribute("AnalyticsDeliveryFailures", 0)
	local function enqueue(event: Event)
		if not scope.Active then
			return
		end
		scope.Events += 1
		player:SetAttribute("AnalyticsEvents", scope.Events)
		player:SetAttribute("AnalyticsLastEvent", event.Name)
		if event.Step then
			player:SetAttribute("AnalyticsStep", event.Step)
		end
		if not enabled then
			return
		end
		if #scope.Queue >= MAX_QUEUE then
			scope.Dropped += 1
			player:SetAttribute("AnalyticsDropped", scope.Dropped)
			return
		end
		table.insert(scope.Queue, event)
		player:SetAttribute("AnalyticsQueueDepth", #scope.Queue)
		if scope.Working then
			return
		end
		scope.Working = true
		-- Deferred work never puts an AnalyticsService call on the gameplay callback stack.
		task.defer(function()
			while scope.Active and #scope.Queue > 0 do
				local nextEvent = scope.Queue[1]
				-- Funnel retries use the same session/step, deduplicated by Roblox.
				-- Custom events have no idempotency key: never retry an ambiguous failure.
				local attempts = if nextEvent.Kind == "Funnel" then MAX_FUNNEL_ATTEMPTS else 1
				for attempt = 1, attempts do
					if not scope.Active then
						return
					end
					local ok = pcall(function()
						if nextEvent.Kind == "Funnel" then
							AnalyticsService:LogFunnelStepEvent(
								player,
								AnalyticsSession.FunnelName,
								scope.Id,
								nextEvent.Step or 1,
								nextEvent.Name
							)
						else
							AnalyticsService:LogCustomEvent(player, nextEvent.Name, 1, {
								[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = nextEvent.Category,
							})
						end
					end)
					if not scope.Active then
						return
					end
					if ok then
						break
					end
					scope.Failures += 1
					player:SetAttribute("AnalyticsDeliveryFailures", scope.Failures)
					if not warned then
						warned = true
						warn("[RuleRoom] Analytics unavailable; gameplay continues.")
					end
					if attempt < attempts then
						task.wait(attempt * 0.5)
					end
				end
				table.remove(scope.Queue, 1)
				player:SetAttribute("AnalyticsQueueDepth", #scope.Queue)
				task.wait(0.1)
			end
			scope.Working = false
		end)
	end
	local session = AnalyticsSession.new(enqueue)
	scope.Session = session
	local function observe()
		if scope.Active then
			session.Observe({
				Round = state:GetAttribute("Round"),
				InRound = player:GetAttribute("InRound"),
				ResultReady = player:GetAttribute("ResultReady"),
				RunResult = player:GetAttribute("RunResult"),
				DataStatus = player:GetAttribute("DataStatus"),
				DataPersistent = player:GetAttribute("DataPersistent"),
			})
		end
	end
	local function schedule()
		if scope.Active and not scope.Pending then
			scope.Pending = true
			task.defer(function()
				scope.Pending = false
				observe()
			end)
		end
	end
	for _, attribute in { "InRound", "ResultReady", "RunResult", "DataStatus", "DataPersistent" } do
		table.insert(scope.Connections, player:GetAttributeChangedSignal(attribute):Connect(schedule))
	end
	table.insert(scope.Connections, state:GetAttributeChangedSignal("Round"):Connect(schedule))
	local function intent(source: string)
		task.defer(function()
			if scope.Active then
				observe()
				session.Intent(source)
			end
		end)
	end
	local initialJoin = player:GetAttribute("AnalyticsJoinIntent")
	local lastJoin = if typeof(initialJoin) == "number" then initialJoin else 0
	table.insert(
		scope.Connections,
		player:GetAttributeChangedSignal("AnalyticsJoinIntent"):Connect(function()
			local current = player:GetAttribute("AnalyticsJoinIntent")
			if
				typeof(current) == "number"
				and current < math.huge
				and current % 1 == 0
				and current > lastJoin
			then
				lastJoin = current
				intent("Join")
			end
		end)
	)
	table.insert(
		scope.Connections,
		player:GetAttributeChangedSignal("VotedMode"):Connect(function()
			local mode = player:GetAttribute("VotedMode")
			if state:GetAttribute("Phase") == "Voting" and typeof(mode) == "string" and MODES[mode] then
				intent("Vote")
			end
		end)
	)
	observe()
end

local function removePlayer(player: Player)
	local scope = scopes[player]
	if not scope then
		return
	end
	scope.Active = false
	if scope.Session then
		scope.Session.Close()
	end
	table.clear(scope.Queue)
	for _, connection in scope.Connections do
		connection:Disconnect()
	end
	scopes[player] = nil
end

table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
for _, player in Players:GetPlayers() do
	addPlayer(player)
end
local function cleanup()
	if closed then
		return
	end
	closed = true
	for player in scopes do
		removePlayer(player)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
end
script.Destroying:Connect(cleanup)
game:BindToClose(cleanup)
