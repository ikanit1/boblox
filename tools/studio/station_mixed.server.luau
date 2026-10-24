-- Studio-only mixed-role test: two native clients, production station/rules/roster, mock awards.
-- Production Main must be disabled; install the station driver as Player2.PlayerGui.StationQADriver.
assert(game:GetService("RunService"):IsStudio(), "Studio-only mixed station test")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local modules = game.ServerScriptService.RuleRoomServer
assert(not modules.Main.Enabled, "Main must be isolated")
local world = require(modules.ArenaRules).new(workspace.Arena)
local awardCount = {}
local profiles = {
	IsReady = function()
		return true
	end,
	AwardStar = function(p)
		awardCount[p] = (awardCount[p] or 0) + 1
	end,
	AwardSurvival = function(p)
		awardCount[p] = (awardCount[p] or 0) + 1
	end,
	CompleteRun = function(p)
		awardCount[p] = (awardCount[p] or 0) + 1
	end,
}
local roster = require(modules.PlayerRoster).new(world.LobbySpawn, profiles)
local report = Instance.new("Folder")
report.Name = "QAStationMixed"
report.Parent = RS
local state = RS.RuleRoomState
local result = {
	level = "two_native_clients_production_rules_roster_station_mock_awards",
	maxRelativeHeight = 0,
	gravitySamples = 0,
	stayedOut = true,
}
local p1 = Players:FindFirstChild("Player1")
local p2 = Players:FindFirstChild("Player2")
assert(p1 and p2, "Exactly two native named test players expected")
local driver = p2.PlayerGui:WaitForChild("StationQADriver")
local function await(predicate, seconds)
	local deadline = os.clock() + seconds
	repeat
		task.wait(0.05)
	until predicate() or os.clock() > deadline
	assert(predicate(), "Mixed-role test deadline")
end
local ok, message = xpcall(function()
	task.wait(1)
	driver:SetAttribute("Command", "Explore")
	await(function()
		return p2:GetAttribute("LobbyOnly") == true
	end, 5)
	p2.Character:PivotTo(CFrame.new(-51, 4, 160))
	task.wait(1)
	driver:SetAttribute("Command", "Start")
	await(function()
		return p2:GetAttribute("PracticeState") == "Running"
	end, 5)
	result.coinsBefore = p2:GetAttribute("Coins")
	driver:SetAttribute("Command", "Run")
	local admitted = 0
	await(function()
		if admitted == 0 then
			admitted = roster.StartRound(world.ArenaSpawn)
		end
		return admitted > 0
	end, 10)
	result.onlyQueuedAdmitted = p1:GetAttribute("InRound") == true and p2:GetAttribute("InRound") ~= true
	assert(result.onlyQueuedAdmitted, "Explorer admitted to trial")
	state:SetAttribute("Phase", "Rule")
	state:SetAttribute("RuleId", "LowGravity")
	state:SetAttribute("RuleName", "ЛУННАЯ КОМНАТА")
	local context = { roster = roster, state = state }
	context.waitFor = function(seconds, update)
		local started = workspace:GetServerTimeNow()
		local previous = started
		state:SetAttribute("PhaseEndsAt", started + seconds)
		repeat
			local now = workspace:GetServerTimeNow()
			roster.CheckBoundaries()
			if update then
				update(now - started, now - previous)
			end
			previous = now
			result.stayedOut = result.stayedOut
				and p2:GetAttribute("InRound") ~= true
				and p2.Character.HumanoidRootPart.Position.Z > 43
			if p1.Character.HumanoidRootPart:FindFirstChild("RuleRoomLunarForce") then
				local root = p2.Character.HumanoidRootPart
				local h = p2.Character.Humanoid
				local index = p2:GetAttribute("PracticeCheckpoint") or 0
				local pad = if index > 0
					then workspace.Arena.Lobby.Practice["Checkpoint" .. index]
					else workspace.Arena.Lobby.Practice.StartPad
				local feet = root.Position.Y - root.Size.Y / 2 - h.HipHeight
				result.maxRelativeHeight =
					math.max(result.maxRelativeHeight, feet - (pad.Position.Y + pad.Size.Y / 2))
				assert(math.abs(workspace.Gravity - 196.2) < 0.01, "Trial changed global lobby gravity")
				assert(
					not root:FindFirstChild("RuleRoomLunarForce"),
					"Explorer received participant lunar force"
				)
				result.gravitySamples += 1
			end
			task.wait(0.05)
		until workspace:GetServerTimeNow() >= started + seconds
		return roster.AliveCount() > 0
	end
	result.ruleCompleted = world.Run("LowGravity", context)
	local before = p2.Character:GetPivot().Position
	world.Restore()
	assert(
		not p1.Character.HumanoidRootPart:FindFirstChild("RuleRoomLunarForce"),
		"Lunar force leaked after restore"
	)
	roster.EndRound()
	result.explorerEndRoundDisplacement = (p2.Character:GetPivot().Position - before).Magnitude
	assert(result.explorerEndRoundDisplacement < 1, "EndRound teleported explorer")
	assert(
		result.stayedOut and result.gravitySamples > 20 and result.maxRelativeHeight < 10,
		"Lobby gravity/isolation failed"
	)
	await(function()
		return p2:GetAttribute("PracticeState") == "Finished"
	end, 65)
	result.practiceFinished = true
	result.practiceBest = p2:GetAttribute("PracticeBestSeconds")
	result.checkpoints = p2:GetAttribute("PracticeCheckpoint")
	result.explorerAwards = awardCount[p2] or 0
	result.coinsAfter = p2:GetAttribute("Coins")
	assert(
		result.explorerAwards == 0 and result.coinsBefore == result.coinsAfter,
		"Practice granted economic award"
	)
	driver:SetAttribute("Command", "Join")
	await(function()
		return p2:GetAttribute("LobbyOnly") == false
	end, 5)
	result.practiceCanceledOnJoin = p2:GetAttribute("PracticeState") == "Idle"
	result.joinedAtNextAdmission = roster.StartRound(world.ArenaSpawn) == 2
	assert(result.practiceCanceledOnJoin and result.joinedAtNextAdmission, "Queue rejoin failed")
end, debug.traceback)
world.Restore()
roster.EndRound()
roster.Destroy()
result.ok, result.error = ok, if ok then nil else tostring(message)
state:SetAttribute("Phase", "Waiting")
state:SetAttribute("RuleId", "")
state:SetAttribute("Instruction", "Проверка лаборатории завершена")
report:SetAttribute("ResultsJSON", game:GetService("HttpService"):JSONEncode(result))
report:SetAttribute("Complete", true)
print("[QA_STATION] " .. report:GetAttribute("ResultsJSON"))
