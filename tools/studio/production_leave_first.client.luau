-- MCP execute_luau CLIENT snippet for native test user -1; NOT an auto-start LocalScript.
-- StudioTestService:LeaveTest may require the MCP execution identity; ordinary scripts are not assumed to work.
-- This requests a real Reflex vote, observes server acknowledgement, then leaves the native test.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsClient(), "Studio client MCP context required")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player and player.UserId == -1, "Run only in native client -1")
local state = assert(RS:FindFirstChild("RuleRoomState"), "Production state missing")
local monitor = assert(RS:FindFirstChild("QARuleCoverage"), "Production monitor missing")
local report = assert(RS:FindFirstChild("QAProductionLeave"), "Install the server leave observer first")
assert(monitor:GetAttribute("Complete") == true, "Production monitor must be complete")
assert(report:GetAttribute("Complete") == false, "Leave observer already finished")
assert(report:GetAttribute("FirstUserId") == player.UserId, "Unexpected observer target")
assert(report:GetAttribute("MainEnabledAtInstall") == true, "Observer was not installed against Main")
assert(#Players:GetPlayers() == 2, "First leave requires exactly two native clients")
assert(not player.PlayerScripts:FindFirstChild("QAProductionLeaveFirst"), "First leave already scheduled")
local service = game:GetService("StudioTestService")
assert(service:CanLeaveTest(), "Native LeaveTest unavailable in this execution context")
local status = Instance.new("Folder")
status.Name = "QAProductionLeaveFirst"
status:SetAttribute("Status", "WAITING_FOR_VOTING")
status.Parent = player.PlayerScripts
task.spawn(function()
	local ok, failure = xpcall(function()
		local deadline = os.clock() + 240
		local function ready()
			return state:GetAttribute("Phase") == "Voting"
				and (state:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow() >= 3
				and state:GetAttribute("VotesReflex") == 0
				and player:GetAttribute("VotedMode") ~= "Reflex"
		end
		while not ready() and os.clock() < deadline do
			assert(report.Parent and not report:GetAttribute("Complete"), "Server observer stopped")
			task.wait(0.05)
		end
		assert(ready(), "Fresh Voting window with time to acknowledge was not reached")
		assert(#Players:GetPlayers() == 2, "Native participant count changed before vote")
		RS.RuleRoomRemotes.Vote:FireServer("Reflex")
		local voteDeadline = os.clock() + 2
		while
			(player:GetAttribute("VotedMode") ~= "Reflex" or state:GetAttribute("VotesReflex") ~= 1)
			and os.clock() < voteDeadline
		do
			task.wait(0.05)
		end
		assert(
			player:GetAttribute("VotedMode") == "Reflex" and state:GetAttribute("VotesReflex") == 1,
			"Vote acknowledgement missing or another voter interfered"
		)
		status:SetAttribute("Status", "VOTE_ACKNOWLEDGED")
		task.wait(0.3)
		assert(state:GetAttribute("Phase") == "Voting", "Voting ended before native leave")
		assert(#Players:GetPlayers() == 2, "Native participant count changed before leave")
		assert(report.Parent and not report:GetAttribute("Complete"), "Server observer stopped")
		status:SetAttribute("Status", "LEAVE_REQUESTED")
		service:LeaveTest()
	end, debug.traceback)
	if not ok and status.Parent then
		status:SetAttribute("Status", "CLIENT_ERROR")
		status:SetAttribute("Error", tostring(failure))
		warn("[QA_PRODUCTION_LEAVE_FIRST] " .. tostring(failure))
	end
end)
return "Scheduled native client -1 leave after server-acknowledged Reflex vote during Voting"
