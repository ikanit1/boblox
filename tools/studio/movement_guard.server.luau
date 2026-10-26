-- Studio-only adversarial fixture; run after the rule suite has destroyed its roster.
assert(game:GetService("RunService"):IsStudio(), "Studio-only QA")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local modules = game.ServerScriptService.RuleRoomServer
assert(not modules.Main.Enabled, "Production Main must be disabled for isolation")
local report = Instance.new("Folder")
report.Name = "QAMovementGuard"
report.Parent = RS
local awards = {}
local profiles = {
	IsReady = function()
		return true
	end,
	AwardSurvival = function(p)
		awards[tostring(p.UserId)] = (awards[tostring(p.UserId)] or 0) + 1
	end,
	AwardStar = function() end,
	CompleteRun = function() end,
}
local world = require(modules.ArenaRules).new(workspace.Arena)
local roster = require(modules.PlayerRoster).new(world.LobbySpawn, profiles)
local injectedRoot
local ok, err = xpcall(function()
	task.wait(1)
	roster.BeginRun({ "ReactorRush" })
	assert(roster.StartRound(world.ArenaSpawn, 1, "ReactorRush") == 2, "Two clients required")
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	local subject = list[1]
	injectedRoot = subject.Character.HumanoidRootPart
	injectedRoot.Anchored = true
	injectedRoot.CFrame += Vector3.new(0, 18, 0)
	local state = RS.RuleRoomState
	state:SetAttribute("RuleId", "ReactorRush")
	state:SetAttribute("HazardStage", "Active")
	state:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + 45)
	state:SetAttribute("Phase", "Rule")
	local started = os.clock()
	while os.clock() - started < 7 do
		roster.CheckBoundaries()
		task.wait(0.05)
	end
	roster.AwardSurvivors("ReactorRush")
	roster.AwardSurvivors("ReactorRush")
	local data = {
		source = "Injected anchored hover + grounded control; production roster, mock rewards",
		userId = subject.UserId,
		violation = subject:GetAttribute("MovementViolation"),
		airborneSeconds = subject:GetAttribute("MovementAirborneSeconds"),
		sampleSeconds = subject:GetAttribute("MovementSampleSeconds"),
		eliminated = subject:GetAttribute("Eliminated"),
		awards = awards,
	}
	data.passed = data.violation == "Airborne"
		and data.eliminated == true
		and (awards[tostring(subject.UserId)] or 0) == 0
		and awards[tostring(list[2].UserId)] == 1
	report:SetAttribute("ResultJSON", game:GetService("HttpService"):JSONEncode(data))
	report:SetAttribute("Ready", true)
	-- Bounded opportunity to inspect the production death/spectate HUD before cleanup.
	local deadline = os.clock() + 45
	repeat
		task.wait(0.1)
	until report:GetAttribute("Finish") == true or os.clock() > deadline
end, debug.traceback)
if injectedRoot and injectedRoot.Parent then
	injectedRoot.Anchored = false
end
roster.EndRound()
roster.Destroy()
world.Restore()
report:SetAttribute("Complete", true)
report:SetAttribute("ExecutionOK", ok)
if not ok then
	report:SetAttribute("Error", tostring(err))
end
