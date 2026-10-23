-- MCP execute_luau SERVER snippet, not an auto-start Script.
-- Observe the real production Main after its production monitor has completed.
-- Run this first, then the first/last CLIENT snippets in their respective native clients.
-- The original scratch sequence ran live; the guards/reporting in this reusable copy need rerunning.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsServer(), "Studio server MCP context required")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local state = assert(RS:FindFirstChild("RuleRoomState"), "Production state missing")
local monitor = assert(RS:FindFirstChild("QARuleCoverage"), "Production monitor missing")
local modules = assert(game.ServerScriptService:FindFirstChild("RuleRoomServer"), "Modules missing")
local main = assert(modules:FindFirstChild("Main"), "Main missing")
assert(main.Enabled, "Production Main must be running")
assert(monitor:GetAttribute("Complete") == true, "Wait for the production monitor to finish")
assert(not RS:FindFirstChild("QAProductionLeave"), "Leave observer already installed")
assert(#Players:GetPlayers() == 2, "Exactly two native clients required")
assert(Players:GetPlayerByUserId(-1) and Players:GetPlayerByUserId(-2), "Expected native users -1/-2")
local arena = assert(workspace:FindFirstChild("Arena"), "Arena missing")
local gravityBefore = workspace.Gravity
local report = Instance.new("Folder")
report.Name = "QAProductionLeave"
report:SetAttribute("Scope", "Native leave observation of production Main; MCP snippets; no profile mocks")
report:SetAttribute("ExpectedPlayers", 2)
report:SetAttribute("FirstUserId", -1)
report:SetAttribute("LastUserId", -2)
report:SetAttribute("MainEnabledAtInstall", true)
report:SetAttribute("Complete", false)
report:SetAttribute("Status", "OBSERVING")
report.Parent = RS
local index, running = 0, true
local connections, departures = {}, {}
local function save(kind, details)
	if not report.Parent then
		return
	end
	index += 1
	local value = Instance.new("StringValue")
	value.Name = string.format("Result%03d", index)
	value.Value = Http:JSONEncode({
		kind = kind,
		at = workspace:GetServerTimeNow(),
		state = state:GetAttributes(),
		count = #Players:GetPlayers(),
		details = details,
	})
	value.Parent = report
	local oldest = report:FindFirstChild(string.format("Result%03d", index - 32))
	if oldest then
		oldest:Destroy()
	end
end
local function cleanup()
	if not running then
		return
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
end
save("Installed", { gravity = gravityBefore, timeoutSeconds = 300 })
table.insert(connections, report.Destroying:Connect(cleanup))
table.insert(
	connections,
	Players.PlayerRemoving:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local departure = {
			userId = player.UserId,
			phaseAtLeave = state:GetAttribute("Phase"),
			voted = player:GetAttribute("VotedMode"),
			inRound = player:GetAttribute("InRound") == true,
			health = humanoid and humanoid.Health,
		}
		departures[player.UserId] = departure
		save("NativeLeaving", departure)
		task.delay(0.3, function()
			if not running or not report.Parent then
				return
			end
			departure.afterCount = #Players:GetPlayers()
			departure.votesReflexAfter = state:GetAttribute("VotesReflex")
			save("NativeLeave", departure)
		end)
	end)
)
task.spawn(function()
	local ok, failure = xpcall(function()
		local deadline = os.clock() + 300
		while running and #Players:GetPlayers() > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		while running and state:GetAttribute("Phase") ~= "Waiting" and os.clock() < deadline do
			task.wait(0.1)
		end
		if not running then
			return
		end
		-- Allow the last PlayerRemoving observation to finish before disconnecting its observer.
		task.wait(0.35)
		if not running then
			return
		end
		local effects = arena:FindFirstChild("RuleEffects")
		local effectCount = if effects then #effects:GetChildren() else -1
		local empty = #Players:GetPlayers() == 0 and state:GetAttribute("Phase") == "Waiting"
		local first, last = departures[-1], departures[-2]
		local voteLeave = first ~= nil
			and first.phaseAtLeave == "Voting"
			and first.voted == "Reflex"
			and first.afterCount == 1
			and first.votesReflexAfter == 0
		local lastAliveLeave = last ~= nil
			and last.phaseAtLeave == "Rule"
			and last.inRound
			and type(last.health) == "number"
			and last.health > 0
			and last.afterCount == 0
		local cleanupPassed = empty and effectCount == 0 and workspace.Gravity == gravityBefore
		local passed = voteLeave and lastAliveLeave and cleanupPassed
		save("EmptyWaiting", {
			passed = passed,
			emptyReached = empty,
			voteLeavePassed = voteLeave,
			lastAliveLeavePassed = lastAliveLeave,
			cleanupPassed = cleanupPassed,
			gravity = workspace.Gravity,
			expectedGravity = gravityBefore,
			effects = effectCount,
			timedOut = os.clock() >= deadline,
		})
		report:SetAttribute("EmptyReached", empty)
		report:SetAttribute("Passed", passed)
		report:SetAttribute("Status", if passed then "PASS" else "CASE_UNACHIEVED")
	end, debug.traceback)
	cleanup()
	if report.Parent then
		if not ok then
			report:SetAttribute("Status", "OBSERVER_ERROR")
			report:SetAttribute("Error", tostring(failure))
		end
		report:SetAttribute("Complete", true)
	end
end)
return "Production leave observer installed; run first on -1 and last on -2 via client MCP contexts"
