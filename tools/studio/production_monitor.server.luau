-- Production Main/roster/profiles own all gameplay and rewards. Exact-four is an explicit death injection.
-- Install BEFORE enabling Main. No production configuration or reward attributes are changed here.
local QAOptions = {} -- QA_OPTIONS
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsServer(), "Production monitor is Studio server only")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local state = RS:WaitForChild("RuleRoomState")
local shared = RS:WaitForChild("RuleRoomShared")
local config = require(shared:WaitForChild("GameConfig"))
local economy = require(shared:WaitForChild("EconomyConfig"))
assert(economy.Persistence.StudioDataStoreEnabled == false, "Only session profiles may be used")
local rewards = economy.Rewards
local targetClients = QAOptions.targetClients or 1
local runCount = QAOptions.runCount or 2
local secondCase = QAOptions.secondCase or "exact_four"
assert(
	type(targetClients) == "number" and targetClients % 1 == 0 and targetClients >= 1 and targetClients <= 12,
	"targetClients must be 1..12 native clients"
)
assert(runCount == 1 or runCount == 2, "runCount must be 1 or 2")
assert(
	secondCase == "charged_die" or secondCase == "exact_four" or secondCase == "success",
	"Unknown secondCase"
)
assert(not game.ServerScriptService.RuleRoomServer.Main.Enabled, "Install before Main starts")
assert(not RS:FindFirstChild("QARuleCoverage"), "Another QA driver/controller is already installed")
local originalConfiguration = config.VotingSeconds == 8
	and config.BreakSeconds == 3
	and config.ResultsSeconds == 7
	and config.RuleCount == 6
	and config.SurvivorPoints == 10
	and config.StarPoints == 2
local report = Instance.new("Folder")
report.Name = "QARuleCoverage"
report:SetAttribute("Behavior", "solve")
report:SetAttribute("JumpLead", 5)
report:SetAttribute("Complete", false)
report:SetAttribute("TargetClients", targetClients)
report:SetAttribute("RunCount", runCount)
report:SetAttribute("SecondCase", secondCase)
report:SetAttribute(
	"Fixture",
	"Production Main/profiles; Session data; MoveTo/Jump driver; exact_four injects death in trials 1 and 2 of run 2"
)
report:SetAttribute(
	"NetworkConditions",
	"Studio operator settings; unchanged and not measured by this monitor"
)
report.Parent = RS
local telemetry = Instance.new("RemoteEvent")
telemetry.Name = "ClientTelemetry"
telemetry.Parent = report
-- Capture round 1 from initial Voting, including profile loading before the first admission.
local firstFullRound = 1
local lastRound = firstFullRound + runCount - 1
report:SetAttribute("FirstFullRound", firstFullRound)
report:SetAttribute("LastRound", lastRound)
local started = os.clock()
local events, rounds, baselines, clientTelemetry = {}, {}, {}, {}
local lastKey = ""
local targetReached = false
local trialPlayerChecks, runPlayerChecks = 0, 0
local function caseForRound(number)
	return if number == 2 then secondCase else "success"
end

local function numeric(v)
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local telemetryConnection = telemetry.OnServerEvent:Connect(function(p, entry, jumps, owns)
	if
		numeric(entry)
		and entry % 1 == 0
		and entry >= 0
		and entry <= lastRound * 10 + 6
		and numeric(jumps)
		and jumps >= 0
		and jumps <= 1000
		and jumps % 1 == 0
		and type(owns) == "boolean"
	then
		clientTelemetry[tostring(p.UserId)] =
			{ entry = entry, jumps = jumps, ownsControls = owns, at = os.clock() - started }
	end
end)
local function players()
	local result = {}
	for _, p in Players:GetPlayers() do
		local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		result[tostring(p.UserId)] = {
			name = p.Name,
			coins = p:GetAttribute("Coins"),
			xp = p:GetAttribute("XP"),
			wins = p:GetAttribute("Wins"),
			sessionRuns = p:GetAttribute("SessionRuns"),
			score = p:GetAttribute("RunScore"),
			survived = p:GetAttribute("RunSurvived"),
			inRound = p:GetAttribute("InRound"),
			eliminated = p:GetAttribute("Eliminated"),
			health = h and h.Health,
			y = root and root.Position.Y,
			pingSeconds = p:GetNetworkPing(),
			dataStatus = p:GetAttribute("DataStatus"),
			movement = p:GetAttribute("MovementViolation"),
			telemetry = clientTelemetry[tostring(p.UserId)],
		}
	end
	return result
end
local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
local function sameParticipants(before, after)
	if not before or count(before) ~= targetClients or count(after) ~= targetClients then
		return false
	end
	for id in before do
		if not after[id] then
			return false
		end
	end
	return true
end
local function save(value)
	table.insert(events, value)
	local encoded = Http:JSONEncode(value)
	local item = Instance.new("StringValue")
	item.Name = string.format("Entry%04d", #events)
	item.Value = encoded
	item.Parent = report
	print("[QA_PRODUCTION] " .. encoded)
end
local function restored()
	local arena = workspace.Arena
	local effects = arena:FindFirstChild("RuleEffects")
	local result = math.abs(workspace.Gravity - 196.2) < 0.001
		and (not effects or #effects:GetChildren() == 0)
		and arena.Laser.Transparency == 1
	for _, t in arena.Tiles:GetChildren() do
		result = result and t.CanCollide
	end
	return result
end
local function zeroRun(snapshot)
	local result = {}
	for id, value in snapshot or {} do
		result[id] = table.clone(value)
		-- Only these two fields reset in BeginRun; currency and lifetime counts do not.
		result[id].score = 0
		result[id].survived = 0
	end
	return result
end
local financialFields = { "coins", "xp", "wins", "sessionRuns", "score", "survived" }
local function financialCheck(before, after, completion, expectedWin, maxSurvival)
	for _, field in financialFields do
		if not numeric(before[field]) or not numeric(after[field]) then
			return { pass = false, reason = "Missing/non-finite " .. field }
		end
	end
	local survived = after.survived - before.survived
	local pickups = (after.score - before.score - config.SurvivorPoints * survived) / config.StarPoints
	local wins = after.wins - before.wins
	local runs = after.sessionRuns - before.sessionRuns
	local coinExpected = rewards.SurvivalCoins * survived
		+ rewards.StarCoins * pickups
		+ rewards.RunCoins * completion
		+ rewards.WinCoins * expectedWin
	local xpExpected = rewards.SurvivalXP * survived + rewards.StarXP * pickups + rewards.RunXP * completion
	return {
		pass = survived >= 0
			and survived <= maxSurvival
			and survived % 1 == 0
			and pickups >= 0
			and pickups % 1 == 0
			and wins == expectedWin
			and runs == completion
			and after.coins - before.coins == coinExpected
			and after.xp - before.xp == xpExpected,
		survivalAwards = survived,
		pickups = pickups,
		winExpected = expectedWin,
		winActual = wins,
		completionExpected = completion,
		completionActual = runs,
		coinExpected = coinExpected,
		coinActual = after.coins - before.coins,
		xpExpected = xpExpected,
		xpActual = after.xp - before.xp,
	}
end
save({
	kind = "Configuration",
	firstFullRound = firstFullRound,
	lastRound = lastRound,
	targetClients = targetClients,
	runCount = runCount,
	secondCase = secondCase,
	votingSeconds = config.VotingSeconds,
	breakSeconds = config.BreakSeconds,
	resultsSeconds = config.ResultsSeconds,
	survivorPoints = config.SurvivorPoints,
	starPoints = config.StarPoints,
	originalConfiguration = originalConfiguration,
	rewards = rewards,
	networkConditions = report:GetAttribute("NetworkConditions"),
})

local ok, failure = xpcall(function()
	while os.clock() - started < 650 do
		local phase = state:GetAttribute("Phase")
		local round = state:GetAttribute("Round") or 0
		local index = state:GetAttribute("RuleIndex") or 0
		local rule = state:GetAttribute("RuleId")
		report:SetAttribute("EntryIndex", round * 10 + index)
		local behavior = if caseForRound(round) == "charged_die" and rule == "ReactorRush"
			then "charged_die"
			else "solve"
		report:SetAttribute("Behavior", behavior)
		-- Refresh before trial 1 so asynchronous initial profile loads are included.
		if phase == "Voting" then
			baselines[round + 1] = players()
		end
		local key = round .. ":" .. index .. ":" .. tostring(phase)
		if key ~= lastKey then
			lastKey = key
			local snapshot = players()
			local event = {
				time = os.clock() - started,
				round = round,
				index = index,
				phase = phase,
				rule = rule,
				behavior = behavior,
				players = snapshot,
				charge = state:GetAttribute("TeamCharge"),
				goal = state:GetAttribute("TeamGoal"),
				finale = state:GetAttribute("FinaleSuccess"),
				text = state:GetAttribute("ResultsText"),
				restored = restored(),
			}
			if phase == "Voting" then
				baselines[round + 1] = snapshot
			end
			if round >= firstFullRound and round <= lastRound then
				local run = rounds[round]
				if not run then
					run = {
						starts = {},
						checks = {},
						injections = {},
						passed = true,
						baseline = zeroRun(baselines[round]),
					}
					rounds[round] = run
				end
				if phase == "Rule" then
					-- Previous Break/Voting includes any pickup in the first Rule callback.
					local before = if index == 1 then run.baseline else run.previousExit
					run.starts[index] = {
						before = before,
						admitted = snapshot,
						rule = rule,
						observedStart = workspace:GetServerTimeNow(),
					}
					local cohort = sameParticipants(run.baseline, snapshot)
					for _, person in snapshot do
						cohort = cohort and person.inRound == true and person.dataStatus == "Session"
					end
					run.passed = run.passed and cohort and before ~= nil
					event.cohortValid = cohort
					save(event)
				elseif phase == "Break" or phase == "Results" then
					local start = run.starts[index]
					local checks, winsExpected = {}, {}
					local valid = start ~= nil
						and start.before ~= nil
						and sameParticipants(run.baseline, snapshot)
					local driverObserved = count(snapshot) == targetClients
					for _, person in snapshot do
						local data = person.telemetry
						driverObserved = driverObserved
							and data ~= nil
							and data.entry == round * 10 + index
							and data.ownsControls == true
					end
					event.driverObserved = driverObserved
					if valid then
						for id, after in snapshot do
							local before = start.before[id]
							local survival = if before
									and numeric(before.survived)
									and numeric(after.survived)
								then after.survived - before.survived
								else -1
							local completion = if phase == "Results"
									and index == 6
									and numeric(after.survived)
									and after.survived >= 1
								then 1
								else 0
							local win = if completion == 1
									and event.finale == true
									and after.survived >= 4
									and survival == 1
								then 1
								else 0
							winsExpected[id] = win
							checks[id] = if before
								then financialCheck(before, after, completion, win, 1)
								else { pass = false, reason = "Missing trial baseline" }
							valid = valid and checks[id].pass
							trialPlayerChecks += 1
						end
					end
					valid = valid and event.restored and driverObserved and not run.checks[index]
					run.checks[index] = checks
					run.previousExit = snapshot
					run.passed = run.passed and valid
					event.rewardChecks = checks
					event.rewardChecksPassed = valid
					if phase == "Results" then
						local ledger = {}
						local ledgerPassed = index == 6
							and count(run.checks) == 6
							and sameParticipants(run.baseline, snapshot)
						for id, after in snapshot do
							local before = run.baseline[id]
							local completion = if index == 6
									and numeric(after.survived)
									and after.survived >= 1
								then 1
								else 0
							ledger[id] = if before and winsExpected[id] ~= nil
								then financialCheck(before, after, completion, winsExpected[id], 6)
								else { pass = false, reason = "Missing run/finale baseline" }
							ledgerPassed = ledgerPassed and ledger[id].pass
							runPlayerChecks += 1
						end
						run.passed = run.passed and ledgerPassed
						event.runLedger = ledger
						event.runLedgerPassed = ledgerPassed
						local charged = numeric(event.goal)
							and event.goal > 0
							and numeric(event.charge)
							and event.charge >= event.goal
						local allWinners = count(snapshot) == targetClients
						local allSix = count(snapshot) == targetClients
						local allExactlyFour = count(snapshot) == targetClients
						local allEliminated = count(snapshot) == targetClients
						for id, person in snapshot do
							allWinners = allWinners and winsExpected[id] == 1
							allSix = allSix and person.survived == 6
							allExactlyFour = allExactlyFour and person.survived == 4
							for trialIndex = 1, 6 do
								local trialCheck = run.checks[trialIndex] and run.checks[trialIndex][id]
								allExactlyFour = allExactlyFour
									and trialCheck ~= nil
									and trialCheck.survivalAwards == (if trialIndex <= 2 then 0 else 1)
							end
							allEliminated = allEliminated
								and person.eliminated == true
								and checks[id] ~= nil
								and checks[id].survivalAwards == 0
						end
						local injectedTwice = count(run.injections) == 2
							and run.injections[1] ~= nil
							and run.injections[1].complete == true
							and run.injections[2] ~= nil
							and run.injections[2].complete == true
						run.case = caseForRound(round)
						run.caseAchieved = if run.case == "charged_die"
							then charged and allEliminated and event.finale == false
							elseif run.case == "exact_four" then charged
								and event.finale == true
								and allWinners
								and allExactlyFour
								and injectedTwice
							else charged and event.finale == true and allWinners and allSix
						event.case = run.case
						event.caseAchieved = run.caseAchieved
						event.caseChecks = {
							charged = charged,
							allWinners = allWinners,
							allSix = allSix,
							allExactlyFour = allExactlyFour,
							allEliminated = allEliminated,
							injectedTwice = injectedTwice,
						}
						event.caseNote = if run.caseAchieved
							then "Observed"
							else "Desired case not achieved; not itself a game defect"
						save(event)
						task.wait(2)
						local stable = players()
						local stablePassed = state:GetAttribute("Phase") == "Results"
							and state:GetAttribute("Round") == round
							and sameParticipants(snapshot, stable)
						for id, person in stable do
							local before = snapshot[id]
							for _, field in financialFields do
								stablePassed = stablePassed
									and before ~= nil
									and person[field] == before[field]
							end
						end
						run.passed = run.passed and stablePassed
						run.completed = true
						save({
							phase = "ResultsStable",
							round = round,
							players = stable,
							noExtraAwards = stablePassed,
						})
						if round == lastRound then
							targetReached = true
							break
						end
					else
						save(event)
					end
				else
					save(event)
				end
			else
				save(event)
			end
		end
		-- Deliberate, one-shot native death injection. Never edits counters, attributes, or profiles.
		local run = rounds[round]
		local start = run and run.starts[index]
		if
			phase == "Rule"
			and caseForRound(round) == "exact_four"
			and (index == 1 or index == 2)
			and start
			and not run.injections[index]
			and workspace:GetServerTimeNow() - start.observedStart >= 1
		then
			local injection = {
				kind = "FaultInjection",
				round = round,
				index = index,
				rule = rule,
				serverTime = workspace:GetServerTimeNow(),
				afterObservedStart = workspace:GetServerTimeNow() - start.observedStart,
				method = "Set current admitted Humanoid.Health=0 once; no reward/counter edits",
				before = players(),
				targets = {},
				applied = 0,
			}
			run.injections[index] = injection
			for _, player in Players:GetPlayers() do
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if player:GetAttribute("InRound") == true and humanoid and humanoid.Health > 0 then
					local healthBefore = humanoid.Health
					humanoid.Health = 0
					injection.applied += 1
					injection.targets[tostring(player.UserId)] =
						{ healthBefore = healthBefore, healthAfter = humanoid.Health }
				end
			end
			injection.complete = sameParticipants(run.baseline, injection.before)
				and injection.applied == targetClients
			save(injection)
		end
		task.wait(0.05)
	end
end, debug.traceback)

local coveragePassed, casesAchieved, allChecksPassed = true, true, true
local roundSummary = {}
for round = firstFullRound, lastRound do
	local run = rounds[round]
	local full = run ~= nil
		and run.completed == true
		and count(run.checks) == 6
		and count(run.baseline) == targetClients
	coveragePassed = coveragePassed and full
	casesAchieved = casesAchieved and full and run.caseAchieved == true
	allChecksPassed = allChecksPassed and run ~= nil and run.passed == true
	roundSummary[tostring(round)] = {
		complete = full,
		trials = if run then count(run.checks) else 0,
		checksPassed = run ~= nil and run.passed == true,
		case = if run then run.case else "not reached",
		caseAchieved = run ~= nil and run.caseAchieved == true,
		injections = if run then count(run.injections) else 0,
	}
end
local checksPassed = ok
	and targetReached
	and originalConfiguration
	and coveragePassed
	and allChecksPassed
	and trialPlayerChecks == targetClients * runCount * 6
	and runPlayerChecks == targetClients * runCount
local summaryPassed = checksPassed and casesAchieved
local status = if not ok
	then "MONITOR_ERROR"
	elseif not targetReached then "INCOMPLETE"
	elseif not checksPassed then "CHECK_FAILED"
	elseif not casesAchieved then "CASE_UNACHIEVED"
	else "PASS"
save({
	kind = "Summary",
	status = status,
	summaryPassed = summaryPassed,
	checksPassed = checksPassed,
	coveragePassed = coveragePassed,
	casesAchieved = casesAchieved,
	rounds = roundSummary,
	trialPlayerChecks = trialPlayerChecks,
	runPlayerChecks = runPlayerChecks,
	expectedTrialPlayerChecks = targetClients * runCount * 6,
	expectedRunPlayerChecks = targetClients * runCount,
	elapsed = os.clock() - started,
	error = if ok then nil else tostring(failure),
})
report:SetAttribute("SummaryPassed", summaryPassed)
report:SetAttribute("Status", status)
report:SetAttribute("MonitorEnded", true)
-- Complete is an ended signal, not an assertion that acceptance passed.
report:SetAttribute("Complete", true)
telemetryConnection:Disconnect()
