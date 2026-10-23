-- Studio-only acceptance harness. Install as a Script with production Main disabled BEFORE Play.
-- Uses native Players, the real PlayerRoster and the real session-only ProfileService.
-- No ArenaRules, fake Players, cloud requests, Vote handler, or automatic run-win awards.
-- Commands: set arguments/Command first, increment CommandSeq LAST, await CompletedSeq and !Busy.
-- ExpectedPlayers is an exact native count. TargetAll=true broadcasts; TargetUserId=-1 is a real ID.
-- BeginTrial / FinishTrial / CheckLateJoin / Reset / DelayReady / SpamProfile / Snapshot / CheckEmpty / Stop.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "QALifecycle is restricted to Studio")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local modules = ServerScriptService:WaitForChild("RuleRoomServer")
local main = modules:WaitForChild("Main")
assert(main:IsA("Script") and not main.Enabled, "Disable production Main BEFORE starting Play")
assert(not ReplicatedStorage:FindFirstChild("QALifecycle"), "Only one lifecycle harness may run")
local shared = ReplicatedStorage:WaitForChild("RuleRoomShared")
local economy = require(shared:WaitForChild("EconomyConfig"))
local config = require(shared:WaitForChild("GameConfig"))
assert(economy.Persistence.StudioDataStoreEnabled == false, "Harness requires session-only profiles")
local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local originalState = state:GetAttributes()
local originalRespawnTime = Players.RespawnTime
local arena = Workspace:WaitForChild("Arena")
local lobby = arena:WaitForChild("LobbySpawn")
local spawn = arena:WaitForChild("ArenaSpawn")
assert(lobby:IsA("BasePart") and spawn:IsA("BasePart"), "Authored spawns required")

local report = Instance.new("Folder")
report.Name = "QALifecycle"
report:SetAttribute(
	"Fixture",
	"Native clients; production roster/profile; Session data; manual trial boundaries; no hazards/Main"
)
report:SetAttribute("Command", "")
report:SetAttribute("CommandSeq", 0)
report:SetAttribute("CompletedSeq", 0)
report:SetAttribute("ExpectedPlayers", 2)
report:SetAttribute("TargetUserId", -1)
report:SetAttribute("TargetAll", false)
report:SetAttribute("WaitSeconds", 12)
report:SetAttribute("SpamCount", 36)
report:SetAttribute("SpamInterval", 0.02)
report:SetAttribute("Busy", false)
report:SetAttribute("Complete", false)
report:SetAttribute("Ready", false)
local outcomes = Instance.new("Folder")
outcomes.Name = "Outcomes"
outcomes.Parent = report
local clientCommand = Instance.new("RemoteEvent")
clientCommand.Name = "ClientCommand"
clientCommand.Parent = report
local clientReport = Instance.new("RemoteEvent")
clientReport.Name = "ClientReport"
clientReport.Parent = report
report.Parent = ReplicatedStorage

local profiles = require(modules:WaitForChild("ProfileService")).new()
local blockedUserId = nil
local proxy = {
	IsReady = function(player)
		return player.UserId ~= blockedUserId and profiles.IsReady(player)
	end,
	AwardSurvival = profiles.AwardSurvival,
	AwardStar = profiles.AwardStar,
	CompleteRun = profiles.CompleteRun,
}
local roster = require(modules:WaitForChild("PlayerRoster")).new(lobby.CFrame, proxy)
Players.RespawnTime = 2
local stopped, active = false, false
local connections = {}
local admitted, admissionBefore = {}, {}
local clientReady, clientReplies = {}, {}
local clientSequence = 0
local characterIds = setmetatable({}, { __mode = "k" })
local characterCounter, trial, round = 0, 0, 1
local events, eventIndex, outcomeIndex = {}, 0, 0
local lastSequence = 0
local pendingBlock = nil
local currentSpamTargets = {}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function numberArg(name, fallback, minimum, maximum)
	local value = report:GetAttribute(name)
	return if finite(value) then math.clamp(math.floor(value), minimum, maximum) else fallback
end

local function money(player)
	local result = {}
	for _, name in { "Coins", "XP", "Wins", "EquippedTrail", "SessionRuns" } do
		result[name] = player:GetAttribute(name)
	end
	for _, trail in economy.Trails do
		local name = "Owned_" .. trail.Id
		result[name] = player:GetAttribute(name)
	end
	for id in economy.Quests do
		result["Quest_" .. id] = player:GetAttribute("Quest_" .. id)
		result["Claimed_" .. id] = player:GetAttribute("Claimed_" .. id)
	end
	return result
end

local function same(left, right)
	for key, value in left do
		if right[key] ~= value then
			return false
		end
	end
	for key, value in right do
		if left[key] ~= value then
			return false
		end
	end
	return true
end

local function playerSnapshot(player)
	local character = player.Character
	if character and not characterIds[character] then
		characterCounter += 1
		characterIds[character] = characterCounter
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local parts, wrongGroups = 0, 0
	if character then
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				parts += 1
				if descendant.CollisionGroup ~= "RuleRoomCharacters" then
					wrongGroups += 1
				end
			end
		end
	end
	local position = nil
	if root and root:IsA("BasePart") then
		local p = root.Position
		position = { x = p.X, y = p.Y, z = p.Z }
	end
	return {
		userId = player.UserId,
		name = player.Name,
		characterId = if character then characterIds[character] else 0,
		health = if humanoid then humanoid.Health else 0,
		position = position,
		inRound = player:GetAttribute("InRound") == true,
		eliminated = player:GetAttribute("Eliminated") == true,
		runSurvived = player:GetAttribute("RunSurvived") or 0,
		runScore = player:GetAttribute("RunScore") or 0,
		movementViolation = player:GetAttribute("MovementViolation") or "",
		profileReady = profiles.IsReady(player),
		dataStatus = player:GetAttribute("DataStatus"),
		money = money(player),
		bodyParts = parts,
		wrongCollisionGroups = wrongGroups,
		clientReady = clientReady[player] == true,
	}
end

local function snapshot()
	local players = {}
	for _, player in Players:GetPlayers() do
		players[tostring(player.UserId)] = playerSnapshot(player)
	end
	return {
		time = Workspace:GetServerTimeNow(),
		players = players,
		playerCount = #Players:GetPlayers(),
		aliveCount = roster.AliveCount(),
		active = active,
		round = round,
		trial = trial,
		phase = state:GetAttribute("Phase"),
	}
end

local function event(kind, player)
	eventIndex += 1
	table.insert(events, {
		index = eventIndex,
		time = Workspace:GetServerTimeNow(),
		kind = kind,
		userId = if player then player.UserId else 0,
		inRound = if player then player:GetAttribute("InRound") == true else false,
		nativePlayerCount = #Players:GetPlayers(),
	})
	if #events > 80 then
		table.remove(events, 1)
	end
end

local function check(result, label, condition, detail)
	table.insert(result.checks, { name = label, passed = condition == true, detail = detail })
	if not condition then
		result.ok = false
	end
end

local function waitUntil(predicate, seconds)
	local deadline = os.clock() + seconds
	repeat
		if stopped then
			return false
		end
		if predicate() then
			return true
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return predicate()
end

local function readyPlayers(expected, seconds)
	return waitUntil(function()
		local list = Players:GetPlayers()
		if #list ~= expected then
			return false
		end
		for _, player in list do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not profiles.IsReady(player) or not humanoid or humanoid.Health <= 0 or not root then
				return false
			end
		end
		return true
	end, seconds)
end

local function targetPlayer()
	local id = report:GetAttribute("TargetUserId")
	for _, player in Players:GetPlayers() do
		if player.UserId == id then
			return player
		end
	end
	return nil
end

local function cleanup()
	if stopped then
		return
	end
	stopped = true
	active = false
	report:SetAttribute("Complete", true)
	for _, connection in connections do
		connection:Disconnect()
	end
	roster.Destroy()
	profiles.Destroy()
	Players.RespawnTime = originalRespawnTime
	for name in state:GetAttributes() do
		if originalState[name] == nil then
			state:SetAttribute(name, nil)
		end
	end
	for name, value in originalState do
		state:SetAttribute(name, value)
	end
end

state:SetAttribute("Round", round)
state:SetAttribute("RuleIndex", 0)
state:SetAttribute("RuleCount", config.RuleCount)
state:SetAttribute("Phase", "Waiting")
state:SetAttribute("RuleId", "")
state:SetAttribute("RuleName", "QA: ЖИЗНЕННЫЙ ЦИКЛ")
state:SetAttribute(
	"Instruction",
	"Изолированная проверка допуска игроков; опасности выключены."
)
state:SetAttribute("PhaseEndsAt", 0)
state:SetAttribute("FinaleSuccess", false)
state:SetAttribute("AliveCount", 0)
roster.BeginRun()

local handlers = {}
handlers.Snapshot = function(result)
	check(result, "native player count", #Players:GetPlayers() == result.expectedPlayers)
end
handlers.BeginTrial = function(result)
	assert(not active, "FinishTrial must precede BeginTrial")
	assert(result.expectedPlayers > 0, "BeginTrial requires at least one native client")
	assert(
		readyPlayers(result.expectedPlayers, result.waitSeconds),
		"Native count/characters/profiles not ready"
	)
	-- Let CharacterAdded bind finish after the engine has supplied its root and humanoid.
	task.wait(0.1)
	trial += 1
	if trial > config.RuleCount then
		trial = 1
		round += 1
		state:SetAttribute("Round", round)
		roster.BeginRun()
	end
	state:SetAttribute("RuleIndex", trial)
	state:SetAttribute("RuleId", "SafeColor")
	state:SetAttribute("Phase", "Rule")
	state:SetAttribute("FinaleSuccess", false)
	admissionBefore = snapshot().players
	blockedUserId = pendingBlock
	pendingBlock = nil
	local blocked = blockedUserId
	local entered = roster.StartRound(spawn.CFrame)
	blockedUserId = nil
	admitted = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InRound") == true then
			admitted[player] = player.Character
		end
	end
	active = true
	state:SetAttribute("AliveCount", roster.AliveCount())
	result.entered, result.blockedUserId = entered, blocked
	local blockedPresent = false
	for _, player in Players:GetPlayers() do
		if player.UserId == blocked then
			blockedPresent = true
			check(result, "temporarily unready player not admitted", player:GetAttribute("InRound") ~= true)
		end
		if admitted[player] then
			local current = playerSnapshot(player)
			check(
				result,
				"admitted health and collision group " .. player.UserId,
				current.health == 100 and current.wrongCollisionGroups == 0
			)
		end
		check(result, "Session profile " .. player.UserId, player:GetAttribute("DataStatus") == "Session")
	end
	check(
		result,
		"exact admission count",
		entered == result.expectedPlayers - (if blockedPresent then 1 else 0)
	)
end
handlers.DelayReady = function(result)
	assert(not active, "DelayReady is configured between trials")
	local player = targetPlayer()
	assert(player, "TargetUserId is not a current native Player")
	pendingBlock = player.UserId
	result.blockedUserId = pendingBlock
	result.note =
		"Only proxy.IsReady is false for this player's next admission; production profile data remains unchanged"
end
handlers.CheckLateJoin = function(result)
	assert(active, "No active trial")
	assert(readyPlayers(result.expectedPlayers, result.waitSeconds), "Native clients not ready")
	local excluded = 0
	for _, player in Players:GetPlayers() do
		if not admitted[player] then
			excluded += 1
			check(result, "no mid-trial admission " .. player.UserId, player:GetAttribute("InRound") ~= true)
			local before = admissionBefore[tostring(player.UserId)]
			if before then
				check(
					result,
					"excluded player's profile unchanged " .. player.UserId,
					same(before.money, money(player))
				)
			else
				check(
					result,
					"new Session player has no rewards " .. player.UserId,
					player:GetAttribute("Coins") == 0
						and player:GetAttribute("XP") == 0
						and player:GetAttribute("Wins") == 0
						and player:GetAttribute("RunSurvived") == 0
				)
			end
		end
	end
	result.excluded = excluded
	check(result, "scenario includes a late/unready player", excluded > 0)
end
handlers.FinishTrial = function(result)
	assert(active, "No active trial")
	roster.CheckBoundaries()
	local before = snapshot().players
	local expectedAwards = 0
	local eligible = {}
	for _, player in Players:GetPlayers() do
		local current = before[tostring(player.UserId)]
		if
			admitted[player] == player.Character
			and current.inRound
			and current.health > 0
			and current.position
			and current.position.y >= 1
		then
			expectedAwards += 1
			eligible[tostring(player.UserId)] = true
		end
	end
	-- PR3 alone has a void return; PR2+PR3 returns a count. Verify observable awards in both.
	result.awardReturn = roster.AwardSurvivors("SafeColor")
	local once = snapshot().players
	result.repeatAwardReturn = roster.AwardSurvivors("SafeColor")
	local twice = snapshot().players
	local actualAwards = 0
	for id, first in before do
		local second, third = once[id], twice[id]
		local delta = second.runSurvived - first.runSurvived
		actualAwards += delta
		check(result, "exact individual survival " .. id, delta == (if eligible[id] then 1 else 0))
		check(
			result,
			"survival economy " .. id,
			second.money.Coins - first.money.Coins == delta * economy.Rewards.SurvivalCoins
				and second.money.XP - first.money.XP == delta * economy.Rewards.SurvivalXP
				and second.money.Wins == first.money.Wins
				and second.runScore - first.runScore == delta * config.SurvivorPoints
				and second.money.Quest_survive
					== math.min(first.money.Quest_survive + delta, economy.Quests.survive.Target)
		)
		check(
			result,
			"repeat award is inert " .. id,
			same(second.money, third.money)
				and second.runSurvived == third.runSurvived
				and second.runScore == third.runScore
		)
	end
	result.expectedAwards, result.actualAwards = expectedAwards, actualAwards
	check(result, "only current eligible characters awarded", actualAwards == expectedAwards)
	roster.EndRound()
	active = false
	state:SetAttribute("AliveCount", 0)
	state:SetAttribute("Phase", "Break")
	for _, player in Players:GetPlayers() do
		check(result, "EndRound clears admission " .. player.UserId, player:GetAttribute("InRound") ~= true)
	end
end
handlers.Reset = function(result)
	assert(active, "Reset requires an active trial")
	local player = targetPlayer()
	assert(
		player and admitted[player] == player.Character and player:GetAttribute("InRound") == true,
		"Target must be currently admitted"
	)
	local oldCharacter = player.Character
	local humanoid = oldCharacter:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Target humanoid missing")
	local before = playerSnapshot(player)
	result.injection =
		"Server sets the current Humanoid.Health=0 once; this tests death/respawn, not the Reset menu"
	humanoid.Health = 0
	local respawned = waitUntil(function()
		local character = player.Character
		local body = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return player.Parent == Players
			and character ~= oldCharacter
			and body
			and body.Health > 0
			and root
			and (root.Position - lobby.Position).Magnitude < 20
	end, result.waitSeconds)
	check(result, "new living character respawned in lobby", respawned)
	task.wait(0.15)
	roster.CheckBoundaries()
	local after = playerSnapshot(player)
	result.targetBefore, result.targetAfter = before, after
	check(
		result,
		"new body was not admitted mid-trial",
		not after.inRound and after.characterId ~= before.characterId
	)
	check(
		result,
		"death/respawn gave no economy reward",
		same(before.money, after.money)
			and before.runSurvived == after.runSurvived
			and before.runScore == after.runScore
	)
	check(
		result,
		"new character collision parts assigned",
		after.bodyParts > 0 and after.wrongCollisionGroups == 0
	)
end
handlers.CheckEmpty = function(result)
	check(result, "all real clients left", #Players:GetPlayers() == 0)
	roster.CheckBoundaries()
	check(result, "no active roster entries after leave", roster.AliveCount() == 0)
	if #Players:GetPlayers() == 0 then
		roster.EndRound()
		active = false
		admitted, admissionBefore = {}, {}
		state:SetAttribute("AliveCount", 0)
		state:SetAttribute("Phase", "Waiting")
	end
	result.note =
		"Harness manually ends the empty trial; this does not certify production Main's empty-server loop"
end
handlers.SpamProfile = function(result)
	local targets = {}
	for _, player in Players:GetPlayers() do
		if report:GetAttribute("TargetAll") == true or player == targetPlayer() then
			table.insert(targets, player)
		end
	end
	assert(#targets > 0, "No native clients selected")
	assert(
		waitUntil(function()
			for _, player in targets do
				if not clientReady[player] or not profiles.IsReady(player) then
					return false
				end
			end
			return true
		end, result.waitSeconds),
		"Client fixture/profile not ready"
	)
	local before = snapshot().players
	clientSequence += 1
	clientReplies, currentSpamTargets = {}, {}
	local count = numberArg("SpamCount", 36, 12, 48)
	local requestedInterval = report:GetAttribute("SpamInterval")
	local interval = if finite(requestedInterval) then math.clamp(requestedInterval, 0.02, 0.5) else 0.02
	result.spamCount = count
	result.spamInterval = interval
	result.ackWaitSeconds = math.max(result.waitSeconds, count * interval + 2)
	result.rateLimitEvidence = {
		capacity = 5,
		refillPerSecond = 2,
		consumedBeforePayloadValidation = true,
		intervalMeaning = "Configured client task.wait duration; actual scheduler/network spacing can be longer or bursty",
		validatorCoverage = "Unchanged server state and client acknowledgements do not prove every payload reached every validator; burst requests may be rate-limited first",
		pacedPrecondition = "Twelve requests at 0.4 seconds fit a full bucket; allow at least 2.5 seconds without ProfileAction traffic after a prior burst to refill",
	}
	for _, player in targets do
		currentSpamTargets[player] = true
		clientCommand:FireClient(player, clientSequence, "SpamProfile", count, interval)
	end
	local acknowledged = waitUntil(function()
		for _, player in targets do
			if not clientReplies[player] then
				return false
			end
		end
		return true
	end, result.ackWaitSeconds)
	-- Reliable remote traffic precedes the acknowledgement, but allow one further server turn.
	task.wait(0.25)
	check(result, "all requested clients acknowledged", acknowledged)
	result.clients = {}
	for _, player in targets do
		local reply = clientReplies[player]
		result.clients[tostring(player.UserId)] = reply or { acknowledged = false }
		check(
			result,
			"client sent bounded malformed requests " .. player.UserId,
			reply ~= nil
				and reply.sent == count
				and reply.transportErrors == 0
				and reply.spamInterval == interval
		)
	end
	for _, player in Players:GetPlayers() do
		local prior = before[tostring(player.UserId)]
		check(
			result,
			"authoritative profile unchanged " .. player.UserId,
			prior ~= nil and same(prior.money, money(player))
		)
	end
	result.note =
		"Client acknowledgement describes FireServer attempts; unchanged server snapshots are the reward assertion. No valid purchase/claim or Vote is sent."
	currentSpamTargets = {}
end
handlers.Stop = function(result)
	cleanup()
	check(result, "respawn setting restored", Players.RespawnTime == originalRespawnTime)
	check(result, "original state attributes restored", same(originalState, state:GetAttributes()))
	check(result, "main remains disabled", not main.Enabled)
end

table.insert(
	connections,
	clientReport.OnServerEvent:Connect(function(player, kind, sequence, sent, errors, firstError, interval)
		if kind == "Ready" then
			clientReady[player] = true
			return
		end
		if
			kind ~= "SpamDone"
			or sequence ~= clientSequence
			or not currentSpamTargets[player]
			or clientReplies[player]
		then
			return
		end
		if
			not finite(sent)
			or sent % 1 ~= 0
			or sent < 0
			or sent > 48
			or not finite(errors)
			or errors % 1 ~= 0
			or errors < 0
			or errors > 48
			or not finite(interval)
			or interval < 0.02
			or interval > 0.5
		then
			return
		end
		clientReplies[player] = {
			acknowledged = true,
			sequence = sequence,
			sent = sent,
			transportErrors = errors,
			spamInterval = interval,
			firstError = if type(firstError) == "string" then string.sub(firstError, 1, 200) else "",
		}
	end)
)
table.insert(
	connections,
	Players.PlayerAdded:Connect(function(player)
		event("PlayerAdded", player)
	end)
)
table.insert(
	connections,
	Players.PlayerRemoving:Connect(function(player)
		event("PlayerRemoving", player)
		clientReady[player], clientReplies[player], currentSpamTargets[player] = nil, nil, nil
	end)
)
local step = 0
table.insert(
	connections,
	RunService.Heartbeat:Connect(function(delta)
		step += delta
		if not active or step < 0.1 then
			return
		end
		step = 0
		local ok, failure = pcall(function()
			roster.CheckBoundaries()
			state:SetAttribute("AliveCount", roster.AliveCount())
		end)
		if not ok then
			active = false
			report:SetAttribute("ObserverError", tostring(failure))
		end
	end)
)
table.insert(
	connections,
	report:GetAttributeChangedSignal("CommandSeq"):Connect(function()
		local sequence = report:GetAttribute("CommandSeq")
		if stopped or not finite(sequence) or sequence % 1 ~= 0 or sequence <= lastSequence then
			return
		end
		if report:GetAttribute("Busy") then
			report:SetAttribute("RejectedSeq", sequence)
			return
		end
		lastSequence = sequence
		report:SetAttribute("Busy", true)
		local command = report:GetAttribute("Command")
		local result = {
			sequence = sequence,
			command = command,
			ok = true,
			checks = {},
			expectedPlayers = numberArg("ExpectedPlayers", 2, 0, 12),
			waitSeconds = numberArg("WaitSeconds", 12, 1, 20),
			before = snapshot(),
		}
		local ok, failure = xpcall(function()
			assert(type(command) == "string" and handlers[command], "Unknown QA command")
			handlers[command](result)
		end, debug.traceback)
		blockedUserId = nil
		if not ok then
			result.ok = false
			result.error = tostring(failure)
		end
		result.after = snapshot()
		result.events = table.clone(events)
		if report:GetAttribute("ObserverError") then
			result.ok = false
			result.observerError = report:GetAttribute("ObserverError")
		end
		outcomeIndex += 1
		local value = Instance.new("StringValue")
		value.Name = string.format("%03d_%s", outcomeIndex, tostring(command))
		value.Value = HttpService:JSONEncode(result)
		value.Parent = outcomes
		local stored = outcomes:GetChildren()
		if #stored > 64 then
			table.sort(stored, function(a, b)
				return a.Name < b.Name
			end)
			stored[1]:Destroy()
		end
		report:SetAttribute("LastOutcome", value.Name)
		report:SetAttribute("LastOK", result.ok)
		report:SetAttribute("CompletedSeq", sequence)
		report:SetAttribute("Busy", false)
	end)
)
script.Destroying:Connect(cleanup)
game:BindToClose(cleanup)
report:SetAttribute("Ready", true)
