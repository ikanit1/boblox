-- Studio-only observer. Main, Station, ProfileService and all hazards remain unmodified.
-- The paired client driver uses normal MoveTo/Jump; welcome is clicked separately.
assert(game:GetService("RunService"):IsStudio(), "Studio-only QA")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local state = RS:WaitForChild("RuleRoomState")
local report = Instance.new("Folder")
report.Name = "QARuleCoverage"
report:SetAttribute("Complete", false)
report:SetAttribute("Behavior", "solve")
report:SetAttribute("JumpLead", 4)
report:SetAttribute("EntryIndex", 0)
report:SetAttribute("StartedAt", workspace:GetServerTimeNow())
report.Parent = RS
local telemetry = Instance.new("RemoteEvent")
telemetry.Name = "ClientTelemetry"
telemetry.Parent = report
local result = Instance.new("StringValue")
result.Name = "ProductionJSON"
result.Parent = report
local evidence = {
	source = "Unmodified Main and Session profiles; native client movement",
	phases = {},
	results = {},
	breaks = {},
	errors = {},
}
local ended = false
local lastPhase, lastIndex, lastRound = "", -1, -1
local samples = 0
local function snapshot(p)
	local a = p:GetAttributes()
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local outcomes = {}
	for i = 1, 6 do
		outcomes[i] = a["TrialOutcome_" .. i] or "missing"
	end
	return {
		userId = p.UserId,
		health = h and h.Health,
		x = r and r.Position.X,
		y = r and r.Position.Y,
		z = r and r.Position.Z,
		choice = a.EntryChoiceMade,
		exploring = a.LobbyOnly,
		inRound = a.InRound,
		coins = a.Coins,
		xp = a.XP,
		wins = a.Wins,
		earnedCoins = a.RunCoinsEarned,
		earnedXP = a.RunXPEarned,
		survived = a.RunSurvived,
		stars = a.RunStars,
		result = a.RunResult,
		ready = a.ResultReady,
		outcomes = outcomes,
		reason = a.EliminationReason,
		movement = a.MovementViolation,
	}
end
local function publish()
	result.Value = Http:JSONEncode(evidence)
end
while report.Parent and not ended do
	local phase = state:GetAttribute("Phase")
	local index = state:GetAttribute("RuleIndex") or 0
	local round = state:GetAttribute("Round") or 0
	if phase ~= lastPhase or index ~= lastIndex or round ~= lastRound then
		lastPhase, lastIndex, lastRound = phase, index, round
		report:SetAttribute("EntryIndex", round * 10 + index)
		local event = {
			phase = phase,
			index = index,
			round = round,
			rule = state:GetAttribute("RuleId"),
			at = workspace:GetServerTimeNow(),
			players = {},
		}
		for _, p in Players:GetPlayers() do
			table.insert(event.players, snapshot(p))
		end
		table.insert(evidence.phases, event)
		if phase == "Results" then
			table.insert(evidence.results, event)
			if #evidence.results >= 2 then
				ended = true
			end
		end
		publish()
	end
	-- The second native player's second run deliberately makes natural mistakes.
	local ordered = Players:GetPlayers()
	table.sort(ordered, function(a, b)
		return a.UserId < b.UserId
	end)
	if #ordered >= 2 then
		report:SetAttribute("Behavior_" .. ordered[2].UserId, if round >= 2 then "mistake" else "solve")
	end
	if phase == "Break" then
		samples += 1
		if samples % 5 == 1 then
			local entry = { round = round, index = index, players = {} }
			for _, p in ordered do
				local s = snapshot(p)
				table.insert(entry.players, s)
				if s.outcomes[index] == "Survived" and s.exploring ~= true and s.z and math.abs(s.z) > 45 then
					table.insert(
						evidence.errors,
						"Survivor sent to lobby during break " .. round .. ":" .. index .. ":" .. p.UserId
					)
				end
			end
			table.insert(evidence.breaks, entry)
		end
	end
	if workspace:GetServerTimeNow() - report:GetAttribute("StartedAt") > 540 then
		table.insert(evidence.errors, "Observer timed out before two full runs")
		ended = true
	end
	task.wait(0.1)
end
publish()
report:SetAttribute("Complete", true)
print("[QA_LOOP] Complete; results=" .. #evidence.results .. " observerErrors=" .. #evidence.errors)
