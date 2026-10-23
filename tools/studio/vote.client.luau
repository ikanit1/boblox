-- Studio-only client fixture. Actual Vote RemoteEvent, real replicated VotedMode and HUD text.
-- Tester is native UserId -1; other native clients only record an observer snapshot.
-- Does not click UI, invoke callbacks, require PlayerModule, or alter production state/health/input.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsClient(), "Studio client only")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local scripts = player:WaitForChild("PlayerScripts", 15)
assert(
	scripts and not scripts:FindFirstChild("QAVoteEvidence"),
	"Observer already exists or PlayerScripts missing"
)
local report = Instance.new("Folder")
report.Name = "QAVoteEvidence"
report:SetAttribute("UserId", player.UserId)
report:SetAttribute("Role", if player.UserId == -1 then "tester" else "read_only_observer")
report:SetAttribute("Finished", false)
report:SetAttribute("Complete", false)
report:SetAttribute("Passed", false)
report:SetAttribute("CaseCount", 0)
report:SetAttribute("StartedAt", Workspace:GetServerTimeNow())
report.Parent = scripts
local expires = os.clock() + 300
local caseCount, allPassed = 0, true
local state = RS:WaitForChild("RuleRoomState", 20)
local remotes = RS:WaitForChild("RuleRoomRemotes", 20)
local remote = remotes and remotes:WaitForChild("Vote", 20)
local modes = { "Balanced", "Reflex", "Cosmic" }
local sendCount, lastSendAt = 0, nil

local function aliveTime()
	assert(os.clock() < expires, "Five-minute fixture deadline exceeded")
end
local function pause(seconds)
	aliveTime()
	task.wait(math.min(seconds, math.max(0, expires - os.clock())))
	aliveTime()
end
local function waitFor(predicate, reason)
	repeat
		aliveTime()
		if predicate() then
			return
		end
		task.wait(0.02)
	until os.clock() >= expires
	error("Timeout: " .. reason)
end
local function snapshot()
	local pg = player:FindFirstChild("PlayerGui")
	local gui = pg and pg:FindFirstChild("RuleRoomHUD")
	local root = gui and gui:FindFirstChild("Root")
	local panel = root and root:FindFirstChild("VotePanel")
	local cards = panel and panel:FindFirstChild("Cards")
	local texts, checks, complete = {}, {}, true
	for _, mode in modes do
		local button = cards and cards:FindFirstChild(mode)
		local text = if button and button:IsA("TextButton") then button.Text else nil
		texts[mode] = text
		checks[mode] = text ~= nil and string.find(text, "✓", 1, true) ~= nil
		complete = complete and text ~= nil
	end
	return {
		at = Workspace:GetServerTimeNow(),
		userId = player.UserId,
		phase = state and state:GetAttribute("Phase"),
		round = state and state:GetAttribute("Round"),
		phaseEndsAt = state and state:GetAttribute("PhaseEndsAt"),
		votedMode = player:GetAttribute("VotedMode") or "",
		dataStatus = player:GetAttribute("DataStatus"),
		cardTexts = texts,
		cardCheckmarks = checks,
		cardsPresent = complete,
		votePanelVisible = panel and panel.Visible,
	}
end
local function matches(expected)
	local value = snapshot()
	if not value.cardsPresent or value.votedMode ~= expected then
		return false, value
	end
	for _, mode in modes do
		if value.cardCheckmarks[mode] ~= (mode == expected) then
			return false, value
		end
	end
	return true, value
end
local function settled(expected, sentClock, minimumWait)
	local firstMatch, matched, value
	repeat
		matched, value = matches(expected)
		local elapsed = os.clock() - sentClock
		if matched and not firstMatch then
			firstMatch = elapsed
		end
		if (elapsed >= minimumWait and matched) or elapsed >= 0.15 then
			value.firstExpectedMatchSeconds = firstMatch
			return matched and firstMatch ~= nil and firstMatch <= 0.15, value, elapsed
		end
		pause(math.min(0.01, math.max(0, 0.15 - elapsed)))
	until false
end
local function send(payload)
	aliveTime()
	sendCount += 1
	lastSendAt = os.clock()
	local serverAt = Workspace:GetServerTimeNow()
	remote:FireServer(payload)
	return lastSendAt, serverAt
end
local function record(name, passed, data)
	caseCount += 1
	allPassed = allPassed and passed
	data.name, data.passed = name, passed
	data.evidence =
		"Actual Vote FireServer; real replicated VotedMode and card Text, not button activation or pixel proof"
	local item = Instance.new("StringValue")
	item.Name = string.format("Case_%02d_%s", caseCount, name)
	item.Value = Http:JSONEncode(data)
	item.Parent = report
	report:SetAttribute("CaseCount", caseCount)
end

task.spawn(function()
	local ok, failure = xpcall(function()
		assert(state and remote and remote:IsA("RemoteEvent"), "Production Vote/state missing")
		waitFor(function()
			return player:GetAttribute("DataStatus") == "Session" and snapshot().cardsPresent
		end, "Session profile and authored HUD")
		if player.UserId ~= -1 then
			record(
				"observer_snapshot",
				true,
				{ snapshot = snapshot(), requestsSent = 0, acceptance = "read_only_role_no_vote_tests" }
			)
			return
		end
		waitFor(function()
			return state:GetAttribute("Phase") == "Voting"
		end, "first Voting")
		local firstVoting = snapshot()
		assert(
			type(firstVoting.phaseEndsAt) == "number" and firstVoting.phaseEndsAt - firstVoting.at > 4.5,
			"First Voting has insufficient remaining time; scenario not achieved"
		)
		local reflexClock, reflexAt = send("Reflex")
		pause(0.12)
		local gap = os.clock() - reflexClock
		assert(gap < 0.4, "Scheduler delay exceeded vote cooldown; rapid-rejection scenario not achieved")
		local cosmicClock, cosmicAt = send("Cosmic")
		local matched, observed, settleSeconds = settled("Reflex", cosmicClock, 0.12)
		record("rate_limited_second_vote", matched and observed.phase == "Voting", {
			firstVoting = firstVoting,
			firstRequest = { mode = "Reflex", at = reflexAt },
			secondRequest = { mode = "Cosmic", at = cosmicAt },
			clientSendGapSeconds = gap,
			expected = "Reflex",
			observed = observed,
			settleSeconds = settleSeconds,
		})

		pause(0.5)
		assert(state:GetAttribute("Phase") == "Voting", "Voting ended before accepted change")
		local acceptedClock, acceptedAt = send("Cosmic")
		local accepted, acceptedSnapshot, acceptedSettle = settled("Cosmic", acceptedClock, 0.15)
		record("accepted_vote_change", accepted and acceptedSnapshot.phase == "Voting", {
			requestAt = acceptedAt,
			expected = "Cosmic",
			observed = acceptedSnapshot,
			settleSeconds = acceptedSettle,
		})

		local invalid = {
			{ name = "false", payload = false },
			{ name = "table", payload = { mode = "Balanced" } },
			{ name = "unknown", payload = "__QA_UNKNOWN_MODE" },
			{ name = "nil" },
		}
		for _, item in invalid do
			if lastSendAt then
				pause(math.max(0, 0.45 - (os.clock() - lastSendAt)))
			end
			assert(state:GetAttribute("Phase") == "Voting", "Voting ended before invalid " .. item.name)
			local previousSend = lastSendAt
			local clock, at = send(item.payload)
			local unchanged, value, elapsed = settled("Cosmic", clock, 0.15)
			record("invalid_" .. item.name, unchanged and value.phase == "Voting", {
				payloadKind = item.name,
				requestAt = at,
				clientSendGapSeconds = if previousSend then clock - previousSend else nil,
				expected = "Cosmic",
				observed = value,
				settleSeconds = elapsed,
			})
		end

		waitFor(function()
			return state:GetAttribute("Phase") == "Rule"
		end, "first Rule")
		local beforeOutside = snapshot()
		local outsideClock, outsideAt = send("Balanced")
		local unchanged, outsideSnapshot, outsideSettle = settled("Cosmic", outsideClock, 0.15)
		record(
			"outside_voting_rejected",
			unchanged and beforeOutside.phase == "Rule" and outsideSnapshot.phase ~= "Voting",
			{
				before = beforeOutside,
				requestAt = outsideAt,
				requested = "Balanced",
				expected = "Cosmic",
				observed = outsideSnapshot,
				settleSeconds = outsideSettle,
			}
		)

		waitFor(function()
			return state:GetAttribute("Phase") == "Voting"
		end, "next Voting")
		local resetClock = os.clock()
		local reset, value, elapsed = settled("", resetClock, 0.15)
		record("next_voting_reset", reset and value.phase == "Voting" and value.round ~= firstVoting.round, {
			expected = "",
			observed = value,
			settleSeconds = elapsed,
			firstRound = firstVoting.round,
		})
	end, debug.traceback)
	local tester = player.UserId == -1
	local achieved = ok and tester and allPassed and caseCount == 8
	report:SetAttribute("RequestsSent", sendCount)
	report:SetAttribute("Passed", achieved)
	report:SetAttribute("Complete", achieved)
	report:SetAttribute("Finished", true)
	report:SetAttribute("EndedAt", Workspace:GetServerTimeNow())
	report:SetAttribute(
		"Outcome",
		if not ok
			then "fixture_error"
			elseif not tester then "read_only_observer"
			elseif achieved then "all_eight_cases_achieved"
			else "observed_check_failure"
	)
	if not ok then
		report:SetAttribute("Error", tostring(failure))
	end
end)
return "QAVoteEvidence started; poll Finished; Complete/Passed require all 8 tester cases."
