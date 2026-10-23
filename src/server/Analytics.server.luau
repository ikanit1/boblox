--!strict
-- Observes authoritative progression. No client event or external SDK.
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local enabled = not RunService:IsStudio() and game.GameId > 0
local scopes: { [Player]: { RBXScriptConnection } } = {}
local warned = false

local function addPlayer(player: Player)
	if scopes[player] then
		return
	end
	local connections: { RBXScriptConnection } = {}
	scopes[player] = connections
	local sent: { [number]: boolean } = {}
	local firstRun: number? = nil
	local sessionId = HttpService:GenerateGUID(false)
	local function step(index: number, label: string)
		if sent[index] then
			return
		end
		sent[index] = true
		-- Readable in local QA; this does not claim delivery to Creator Analytics.
		player:SetAttribute("AnalyticsStep", index)
		if enabled then
			local ok = pcall(function()
				AnalyticsService:LogFunnelStepEvent(player, "RuleRoomSession", sessionId, index, label)
			end)
			if not ok and not warned then
				warned = true
				warn("[RuleRoom] Analytics unavailable; gameplay continues.")
			end
		end
	end
	step(1, "Joined")
	local function entered()
		if player:GetAttribute("InRound") ~= true then
			return
		end
		local round = state:GetAttribute("Round")
		if typeof(round) ~= "number" then
			return
		end
		if firstRun == nil then
			firstRun = round
			step(2, "FirstTrialStarted")
		elseif round ~= firstRun and sent[4] then
			step(5, "SecondRunStarted")
		end
	end
	table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(entered))
	table.insert(
		connections,
		player:GetAttributeChangedSignal("RunSurvived"):Connect(function()
			local count = player:GetAttribute("RunSurvived")
			if typeof(count) == "number" and count > 0 then
				step(3, "FirstTrialCompleted")
			end
		end)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal("SessionRuns"):Connect(function()
			local count = player:GetAttribute("SessionRuns")
			if typeof(count) == "number" and count > 0 then
				step(4, "FirstRunCompleted")
			end
		end)
	)
	entered()
end

local function removePlayer(player: Player)
	for _, connection in scopes[player] or {} do
		connection:Disconnect()
	end
	scopes[player] = nil
end

Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(removePlayer)
for _, player in Players:GetPlayers() do
	addPlayer(player)
end
