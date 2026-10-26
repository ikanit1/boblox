-- Isolated Studio QA: production rules/roster, mock profiles. Never changes network settings.
assert(game:GetService("RunService"):IsStudio(), "Studio-only QA fixture")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Config = require(RS.RuleRoomShared.GameConfig)
local modules = game.ServerScriptService.RuleRoomServer
local requestedScenarios = nil -- QA_SCENARIOS
local originalRespawnTime, originalGravity = Players.RespawnTime, workspace.Gravity
local state = RS.RuleRoomState
local report = Instance.new("Folder")
report.Name = "QARuleCoverage"
report:SetAttribute(
	"Fixture",
	"Production rules/roster; mock profiles; normal MoveTo/Jump except labeled injected faults; network settings untouched"
)
report:SetAttribute("Complete", false)
report:SetAttribute("Start", false)
report.Parent = RS
local telemetry = Instance.new("RemoteEvent")
telemetry.Name = "ClientTelemetry"
telemetry.Parent = report
local world, roster, current
local entryCount, errorCount = 0, 0
local failureGoalsAchieved, failureGoalsUnachieved, failureGoalErrors = 0, 0, 0
local behaviors = {
	solve = true,
	mistake = true,
	corner_idle = true,
	no_collect = true,
	charged_die = true,
	manual = true,
	fault_last_tick_death = true,
	fault_last_tick_low_y = true,
	fatal_beam = true,
	fault_reset = true,
}
local failureGoals = {
	SafeColor = {
		kind = "fall",
		text = "Fall through a tile of the wrong color and receive no survival award",
	},
	LaserSweep = { kind = "hurt", text = "Receive beam damage without jumping; death is not required" },
	LowGravity = {
		kind = "no_pickups",
		text = "Complete LowGravity alive without collecting stars; receive one survival award",
	},
	RedLight = { kind = "hurt", text = "Receive damage while continuing to walk through the red signal" },
	LavaRise = { kind = "hurt", text = "Receive lava damage while remaining on the floor" },
	MeteorRain = { kind = "hurt", text = "Receive meteor damage while staying on a warning marker" },
	DisappearingTiles = { kind = "fall", text = "Stay on a warned tile, fall, and receive no survival award" },
	SafeZone = { kind = "hurt", text = "Receive storm damage outside the safe zone" },
	Spinner = {
		kind = "hurt",
		text = "Receive spinner damage while idling in the corner; death is not required",
	},
	ReactorRush = {
		kind = "uncharged",
		text = "Survive the finale with insufficient team charge and no team success",
	},
}
local tileSnapshots = {}
for _, tile in workspace.Arena.Tiles:GetChildren() do
	if tile:IsA("BasePart") then
		table.insert(tileSnapshots, {
			part = tile,
			collide = tile.CanCollide,
			query = tile.CanQuery,
			touch = tile.CanTouch,
			transparency = tile.Transparency,
			color = tile.Color,
			material = tile.Material,
		})
	end
end
local function award(player, kind, won)
	if not current then
		return
	end
	local key = tostring(player.UserId)
	local counts = current.awards[key]
	if not counts then
		counts = { survival = 0, stars = 0, completion = 0, wins = 0 }
		current.awards[key] = counts
	end
	counts[kind] += 1
	if won then
		counts.wins += 1
	end
end
local profiles = {
	IsReady = function()
		return true
	end,
	AwardSurvival = function(p)
		award(p, "survival")
	end,
	AwardStar = function(p)
		award(p, "stars")
	end,
	CompleteRun = function(p, won)
		award(p, "completion", won)
	end,
}
local telemetryConnection = telemetry.OnServerEvent:Connect(function(player, index, attempts, disabled)
	if
		not current
		or current.index ~= index
		or type(attempts) ~= "number"
		or attempts ~= attempts
		or attempts < 0
		or attempts > 10000
		or attempts % 1 ~= 0
		or type(disabled) ~= "boolean"
	then
		return
	end
	local prior = current.clientTelemetry[tostring(player.UserId)]
	if not prior or attempts >= prior.jumpAttempts then
		current.clientTelemetry[tostring(player.UserId)] = {
			jumpAttempts = attempts,
			controlsDisabled = disabled,
			source = "client-reported input attempts; not proof of physical jump",
		}
	end
end)
local function elapsed(entry)
	return if entry.startedAt then workspace:GetServerTimeNow() - entry.startedAt else 0
end
local function observeHealth(entry, record, health)
	record.minHealth = math.min(record.minHealth, health)
	if health < record.lastHealth - 0.001 then
		if record.firstDamageAt == nil then
			record.firstDamageAt = elapsed(entry)
			record.firstDamageSource = if entry.injection.applied
				then "after_injected_fixture"
				else "production_rule_or_boundary"
		end
		if #record.damageTrace < 16 then
			local h, r = record.humanoid, record.root
			local legs = if h.RigType == Enum.HumanoidRigType.R6 then 2 else 0
			table.insert(record.damageTrace, {
				t = elapsed(entry),
				health = health,
				y = r.Position.Y,
				feetY = r.Position.Y - r.Size.Y / 2 - h.HipHeight - legs,
				velocityY = r.AssemblyLinearVelocity.Y,
				humanoidState = h:GetState().Name,
				instruction = state:GetAttribute("Instruction"),
			})
		end
	end
	record.lastHealth = health
end
local function sample(entry, force)
	local now = elapsed(entry)
	for _, record in entry.records do
		local h, r = record.humanoid, record.root
		observeHealth(entry, record, h.Health)
		record.maxY = math.max(record.maxY, r.Position.Y)
		record.minY = math.min(record.minY, r.Position.Y)
		record.maxAbsX = math.max(record.maxAbsX, math.abs(r.Position.X))
		if force or now >= record.nextSample then
			record.nextSample = now + 1
			local ok, ping = pcall(function()
				return record.player:GetNetworkPing()
			end)
			if ok and type(ping) == "number" and ping == ping and ping < math.huge then
				record.pingSeconds = ping
				record.maxPingSeconds = math.max(record.maxPingSeconds or 0, ping)
			end
			if #record.trace < 64 then
				table.insert(
					record.trace,
					{ t = now, health = h.Health, y = r.Position.Y, pingSeconds = record.pingSeconds }
				)
			end
		end
	end
end
local function injectFault(entry, activeElapsed)
	if entry.injection.applied or activeElapsed < 18.85 then
		return
	end
	if entry.behavior ~= "fault_last_tick_death" and entry.behavior ~= "fault_last_tick_low_y" then
		return
	end
	entry.injection.applied = true
	entry.injection.at = elapsed(entry)
	entry.injection.activeElapsed = activeElapsed
	roster.ForEachAlive(function(player, h, r)
		table.insert(entry.injection.players, player.Name)
		if entry.behavior == "fault_last_tick_death" then
			h.Health = 0
		else
			table.insert(entry.injectedRoots, { part = r, anchored = r.Anchored, cframe = r.CFrame })
			r.Anchored = true
			r.CFrame = CFrame.new(r.Position.X, 0.5, r.Position.Z) * r.CFrame.Rotation
		end
	end)
end
local context = { state = state }
context.waitFor = function(seconds, update, finishWhen)
	local start = workspace:GetServerTimeNow()
	local segment = {
		index = #current.segments + 1,
		start = start,
		requestedSeconds = seconds,
		instruction = state:GetAttribute("Instruction"),
		updates = update ~= nil,
	}
	table.insert(current.segments, segment)
	local function finish(value, reason)
		segment.finish = workspace:GetServerTimeNow()
		segment.elapsed = segment.finish - start
		segment.reason = reason
		segment.timerReached = segment.elapsed >= seconds
		return value
	end
	local last = start
	local reactorActive = current.rule == "ReactorRush" and update ~= nil
	if reactorActive then
		current.activeStartedAt = elapsed(current)
	end
	state:SetAttribute("PhaseEndsAt", start + seconds)
	while workspace:GetServerTimeNow() - start < seconds do
		if current.behavior == "fault_reset" and not current.injection.applied and elapsed(current) > 1 then
			current.injection.applied = true
			current.injection.at = elapsed(current)
			roster.ForEachAlive(function(player, h)
				table.insert(current.injection.players, player.Name)
				h.Health = 0
			end)
		end
		roster.CheckBoundaries()
		state:SetAttribute("AliveCount", roster.AliveCount())
		sample(current, false)
		if roster.AliveCount() == 0 then
			return finish(false, "no_alive_players")
		end
		local now = workspace:GetServerTimeNow()
		if update then
			update(now - start, now - last)
		end
		if reactorActive then
			injectFault(current, now - start)
		end
		sample(current, false)
		if finishWhen and finishWhen() then
			roster.CheckBoundaries()
			return finish(roster.AliveCount() > 0, "finish_predicate")
		end
		last = now
		task.wait(0.05)
	end
	roster.CheckBoundaries()
	sample(current, true)
	return finish(roster.AliveCount() > 0, "deadline")
end
local function cleanup(entry)
	local errors = {}
	local function attempt(label, fn)
		local ok, message = pcall(fn)
		if not ok then
			table.insert(errors, label .. ": " .. tostring(message))
		end
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	for _, saved in entry.injectedRoots do
		attempt("restore injected root", function()
			if saved.part.Parent then
				saved.part.CFrame = saved.cframe
				saved.part.Anchored = saved.anchored
			end
		end)
	end
	if world then
		attempt("world.Restore", world.Restore)
	end
	if roster then
		attempt("roster.EndRound", roster.EndRound)
	end
	local function verifyWorld()
		local effects = workspace.Arena:FindFirstChild("RuleEffects")
		local laser = workspace.Arena.Laser
		assert(math.abs(workspace.Gravity - originalGravity) < 0.001, "Gravity leaked")
		assert(not effects or #effects:GetChildren() == 0, "Effects leaked")
		assert(
			laser.Transparency == 1 and not laser.CanCollide and not laser.CanTouch and not laser.CanQuery,
			"Laser leaked"
		)
		for _, saved in tileSnapshots do
			local tile = saved.part
			assert(
				tile.CanCollide == saved.collide
					and tile.CanQuery == saved.query
					and tile.CanTouch == saved.touch,
				"Tile collision leaked"
			)
			assert(
				tile.Transparency == saved.transparency
					and tile.Color == saved.color
					and tile.Material == saved.material,
				"Tile presentation leaked"
			)
		end
	end
	-- Observe production cleanup before any fixture repair; recovery cannot turn a failure into a pass.
	local productionRestored, productionError = pcall(verifyWorld)
	if not productionRestored then
		table.insert(errors, "production restoration: " .. tostring(productionError))
	end
	local recovery = { attempted = false, ok = true }
	if not productionRestored or #errors > 0 then
		recovery.attempted = true
		local recovered, recoveryError = pcall(function()
			workspace.Gravity = originalGravity
			for _, saved in tileSnapshots do
				local tile = saved.part
				tile.CanCollide, tile.CanQuery, tile.CanTouch = saved.collide, saved.query, saved.touch
				tile.Transparency, tile.Color, tile.Material = saved.transparency, saved.color, saved.material
			end
			local effects = workspace.Arena:FindFirstChild("RuleEffects")
			if effects then
				effects:ClearAllChildren()
			end
			local laser = workspace.Arena.Laser
			laser.Transparency, laser.CanCollide, laser.CanTouch, laser.CanQuery = 1, false, false, false
			verifyWorld()
		end)
		recovery.ok = recovered
		recovery.error = if recovered then nil else tostring(recoveryError)
	end
	return {
		ok = #errors == 0 and productionRestored,
		errors = errors,
		productionRestored = productionRestored,
		recovery = recovery,
	}
end
local function publish(index, result)
	local encoded = Http:JSONEncode(result)
	report:SetAttribute("Result" .. index, encoded)
	local value = Instance.new("StringValue")
	value.Name = string.format("Entry%04d", index)
	value.Value = encoded
	value.Parent = report
	print("[QA_RULE] " .. encoded)
end
local function run(scenario, index)
	local ruleId, behavior = scenario.rule, scenario.behavior or "solve"
	local expected = if behavior == "mistake"
			or (behavior == "corner_idle" and ruleId == "Spinner")
			or (behavior == "no_collect" and ruleId == "ReactorRush")
		then failureGoals[ruleId]
		else nil
	local entry = {
		rule = ruleId,
		behavior = behavior,
		index = index,
		awards = {},
		records = {},
		connections = {},
		injectedRoots = {},
		clientTelemetry = {},
		segments = {},
		injection = { requested = string.sub(behavior, 1, 6) == "fault_", applied = false, players = {} },
	}
	current = entry
	local ok, message = xpcall(function()
		assert(Config.Rules[ruleId] and behaviors[behavior], "Unknown rule or behavior")
		assert(
			ruleId == "ReactorRush"
				or not (
					behavior == "no_collect"
					or behavior == "charged_die"
					or (entry.injection.requested and behavior ~= "fault_reset")
				),
			"Reactor behavior requires ReactorRush"
		)
		world.Restore()
		roster.EndRound()
		state:SetAttribute("Phase", "Break")
		state:SetAttribute("Instruction", "Локальная проверка: " .. ruleId)
		state:SetAttribute("Round", index)
		state:SetAttribute("TeamCharge", 0)
		state:SetAttribute("TeamGoal", 0)
		state:SetAttribute("FinaleSuccess", false)
		report:SetAttribute("Behavior", behavior)
		report:SetAttribute("Current", ruleId)
		report:SetAttribute("EntryIndex", index)
		task.wait(3)
		roster.BeginRun()
		local entered = roster.StartRound(world.ArenaSpawn, 1, ruleId)
		local deadline = os.clock() + 15
		while entered == 0 and os.clock() < deadline do
			task.wait(0.5)
			entered = roster.StartRound(world.ArenaSpawn, 1, ruleId)
		end
		assert(entered > 0, "Character admission timed out")
		entry.startedAt = workspace:GetServerTimeNow()
		roster.ForEachAlive(function(player, h, r)
			local record = {
				player = player,
				humanoid = h,
				root = r,
				minHealth = h.Health,
				lastHealth = h.Health,
				maxY = r.Position.Y,
				minY = r.Position.Y,
				maxAbsX = math.abs(r.Position.X),
				nextSample = 0,
				trace = {},
				damageTrace = {},
			}
			table.insert(entry.records, record)
			table.insert(
				entry.connections,
				h.HealthChanged:Connect(function(health)
					observeHealth(entry, record, health)
				end)
			)
		end)
		table.insert(
			entry.connections,
			state:GetAttributeChangedSignal("Instruction"):Connect(function()
				local text = state:GetAttribute("Instruction")
				if not entry.firstWarningAt and type(text) == "string" and text ~= "" then
					entry.firstWarningAt = elapsed(entry)
					entry.firstWarningText = text
				end
			end)
		)
		state:SetAttribute("RuleIndex", 1)
		state:SetAttribute("RuleId", ruleId)
		state:SetAttribute("RuleName", Config.Rules[ruleId].Name)
		state:SetAttribute("SafeColor", "")
		state:SetAttribute("Accent", Config.Rules[ruleId].Accent)
		state:SetAttribute("Phase", "Rule")
		sample(entry, true)
		entry.completed = world.Run(ruleId, context)
		roster.CheckBoundaries()
		if entry.completed then
			-- Intentional duplicate probe. Mock profile counters reveal production roster double-awards.
			roster.AwardSurvivors(ruleId)
			roster.AwardSurvivors(ruleId)
			roster.CompleteRun(state:GetAttribute("FinaleSuccess") == true)
			roster.CompleteRun(state:GetAttribute("FinaleSuccess") == true)
		end
	end, debug.traceback)
	local result = {
		rule = ruleId,
		behavior = behavior,
		ok = ok,
		completed = entry.completed == true,
		duration = elapsed(entry),
		serverStartedAt = entry.startedAt,
		segments = entry.segments,
		error = if ok then nil else tostring(message),
		charge = state:GetAttribute("TeamCharge"),
		goal = state:GetAttribute("TeamGoal"),
		finale = state:GetAttribute("FinaleSuccess"),
		finaleMeaning = "ArenaRules candidate before Main award-count normalization; this isolated harness does not execute Main",
		expectedFailureKind = if expected then expected.kind else nil,
		expectedFailureGoal = if expected then expected.text else nil,
		injection = entry.injection,
		evidence = if entry.injection.requested
			then "injected_fixture"
			elseif behavior == "manual" then "manual"
			else "normal_movement_driver",
		warningEvidence = "First server Instruction publication only; not proof of client-visible warning timing",
		firstWarningAt = entry.firstWarningAt,
		firstWarningText = entry.firstWarningText,
		activeStartedAt = entry.activeStartedAt,
		rewardProbe = "Duplicate AwardSurvivors/CompleteRun on one isolated trial; mock profiles, no actual economy",
		players = {},
	}
	local allExpected = expected ~= nil and #entry.records > 0
	for _, record in entry.records do
		local p, h, r = record.player, record.humanoid, record.root
		local counts = entry.awards[tostring(p.UserId)]
			or { survival = 0, stars = 0, completion = 0, wins = 0 }
		local violation = p:GetAttribute("MovementViolation") or ""
		local achieved = false
		if expected then
			if expected.kind == "hurt" then
				achieved = record.firstDamageAt ~= nil and violation == ""
			elseif expected.kind == "fall" then
				achieved = record.minY < Config.EliminationY and h.Health <= 0 and counts.survival == 0
			elseif expected.kind == "no_pickups" then
				achieved = entry.completed == true
					and h.Health > 0
					and counts.stars == 0
					and counts.survival == 1
			elseif expected.kind == "uncharged" then
				achieved = entry.completed == true
					and h.Health > 0
					and counts.survival == 1
					and result.goal > 0
					and result.charge < result.goal
					and result.finale == false
			end
			allExpected = allExpected and achieved
		end
		table.insert(result.players, {
			name = p.Name,
			health = h.Health,
			minHealth = record.minHealth,
			maxY = record.maxY,
			minY = record.minY,
			maxAbsX = record.maxAbsX,
			expectedFailureGoal = if expected then expected.text else nil,
			failureOutcome = if expected then (if achieved then "achieved" else "unachieved") else nil,
			pingSeconds = record.pingSeconds,
			maxPingSeconds = record.maxPingSeconds,
			trace = record.trace,
			damageTrace = record.damageTrace,
			clientTelemetry = entry.clientTelemetry[tostring(p.UserId)],
			firstDamageAt = record.firstDamageAt,
			firstDamageSource = record.firstDamageSource,
			warningBeforeFirstDamage = if record.firstDamageAt == nil
				then "no_damage"
				else entry.firstWarningAt ~= nil and entry.firstWarningAt <= record.firstDamageAt,
			awardCalls = counts,
			survivalAwardOnce = counts.survival <= 1,
			completionAwardOnce = counts.completion <= 1,
			inRound = p:GetAttribute("InRound"),
			survived = p:GetAttribute("RunSurvived"),
			movement = p:GetAttribute("MovementViolation"),
			trial = p:GetAttribute("TrialResult1"),
			charges = p:GetAttribute("RunCharges"),
			position = tostring(r.Position),
			walk = h.WalkSpeed,
			jumpPower = h.JumpPower,
			jumpHeight = h.JumpHeight,
			useJumpPower = h.UseJumpPower,
			rig = h.RigType.Name,
		})
	end
	result.cleanup = cleanup(entry)
	if not result.cleanup.ok then
		result.ok = false
	end
	if expected then
		result.failureOutcome = if not result.ok
			then "fixture_error"
			elseif allExpected then "achieved"
			else "unachieved"
		if not result.ok then
			failureGoalErrors += 1
		elseif allExpected then
			failureGoalsAchieved += 1
		else
			failureGoalsUnachieved += 1
		end
	end
	if not result.ok then
		errorCount += 1
	end
	entryCount += 1
	current = nil
	publish(index, result)
end
local suiteOK, suiteError = xpcall(function()
	local main = modules:FindFirstChild("Main")
	assert(
		not main or not main:IsA("Script") or not main.Enabled,
		"Disable production Main before QA fixture"
	)
	world = require(modules.ArenaRules).new(workspace.Arena)
	roster = require(modules.PlayerRoster).new(world.LobbySpawn, profiles)
	context.roster = roster
	Players.RespawnTime = 2
	state:SetAttribute("RuleCount", 6)
	state:SetAttribute("ModeId", "Balanced")
	state:SetAttribute("ResultsText", "")
	local scenarios = requestedScenarios
	if not scenarios then
		scenarios = {}
		for _, id in Config.RuleOrder do
			table.insert(scenarios, { rule = id, behavior = "solve" })
		end
		table.insert(scenarios, { rule = "Spinner", behavior = "corner_idle" })
	end
	report:SetAttribute("ScenariosJSON", Http:JSONEncode(scenarios))
	local startDeadline = os.clock() + 120
	repeat
		task.wait(0.1)
	until report:GetAttribute("Start") == true or os.clock() >= startDeadline
	assert(report:GetAttribute("Start") == true, "Operator did not start the prepared suite")
	-- Native clients connect after this server script starts. Prepare admission only
	-- after the operator has observed the expected connected clients and starts QA.
	for _, p in Players:GetPlayers() do
		p:SetAttribute("EntryChoiceMade", true)
		p:SetAttribute("LobbyOnly", false)
		p:SetAttribute("DataStatus", "QA local fixture")
		p:SetAttribute("Coins", 0)
		p:SetAttribute("XP", 0)
		p:SetAttribute("Level", 1)
	end
	for index, scenario in scenarios do
		run(scenario, index)
	end
end, debug.traceback)
local finalCleanup = cleanup(current or { connections = {}, injectedRoots = {} })
if roster then
	local ok, message = pcall(roster.Destroy)
	if not ok then
		finalCleanup.ok = false
		table.insert(finalCleanup.errors, tostring(message))
	end
end
telemetryConnection:Disconnect()
Players.RespawnTime = originalRespawnTime
state:SetAttribute("Phase", "Results")
state:SetAttribute("Instruction", "Локальная проверка завершена")
report:SetAttribute(
	"SummaryJSON",
	Http:JSONEncode({
		ok = suiteOK and finalCleanup.ok and errorCount == 0,
		entries = entryCount,
		errors = errorCount,
		failureGoalsAchieved = failureGoalsAchieved,
		failureGoalsUnachieved = failureGoalsUnachieved,
		failureGoalErrors = failureGoalErrors,
		outcomeMeaning = "ok means fixture execution/restoration; failureOutcome separately reports achieved or unachieved negative-case goals",
		suiteError = if suiteOK then nil else tostring(suiteError),
		cleanup = finalCleanup,
	})
)
report:SetAttribute("Complete", true)
print("[QA_RULE] COMPLETE " .. report:GetAttribute("SummaryJSON"))
