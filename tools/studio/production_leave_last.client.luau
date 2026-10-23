-- MCP execute_luau CLIENT snippet for native test user -2; NOT an auto-start LocalScript.
-- StudioTestService:LeaveTest may require the MCP execution identity; ordinary scripts are not assumed to work.
-- Leave the actual test only when this is the last living admitted participant in a production rule.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsClient(), "Studio client MCP context required")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player and player.UserId == -2, "Run only in native client -2")
local state = assert(RS:FindFirstChild("RuleRoomState"), "Production state missing")
local monitor = assert(RS:FindFirstChild("QARuleCoverage"), "Production monitor missing")
local report = assert(RS:FindFirstChild("QAProductionLeave"), "Install the server leave observer first")
assert(monitor:GetAttribute("Complete") == true, "Production monitor must be complete")
assert(report:GetAttribute("Complete") == false, "Leave observer already finished")
assert(report:GetAttribute("LastUserId") == player.UserId, "Unexpected observer target")
assert(report:GetAttribute("MainEnabledAtInstall") == true, "Observer was not installed against Main")
assert(#Players:GetPlayers() <= 2, "Unexpected native participant count")
assert(not player.PlayerScripts:FindFirstChild("QAProductionLeaveLast"), "Last leave already scheduled")
local service = game:GetService("StudioTestService")
assert(service:CanLeaveTest(), "Native LeaveTest unavailable in this execution context")
local status = Instance.new("Folder")
status.Name = "QAProductionLeaveLast"
status:SetAttribute("Status", "WAITING_FOR_LAST_ALIVE_RULE")
status.Parent = player.PlayerScripts
task.spawn(function()
	local ok, failure = xpcall(function()
		local deadline = os.clock() + 280
		local function ready()
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			return #Players:GetPlayers() == 1
				and state:GetAttribute("Phase") == "Rule"
				and player:GetAttribute("InRound") == true
				and humanoid ~= nil
				and humanoid.Health > 0
		end
		while not ready() and os.clock() < deadline do
			assert(report.Parent and not report:GetAttribute("Complete"), "Server observer stopped")
			task.wait(0.05)
		end
		assert(ready(), "Last living participant's Rule boundary not reached")
		task.wait(1)
		assert(ready(), "Last participant died or phase changed before leave")
		assert(report.Parent and not report:GetAttribute("Complete"), "Server observer stopped")
		status:SetAttribute("Status", "LEAVE_REQUESTED")
		service:LeaveTest()
	end, debug.traceback)
	if not ok and status.Parent then
		status:SetAttribute("Status", "CLIENT_ERROR")
		status:SetAttribute("Error", tostring(failure))
		warn("[QA_PRODUCTION_LEAVE_LAST] " .. tostring(failure))
	end
end)
return "Scheduled native client -2 leave as the last living admitted participant during Rule"
