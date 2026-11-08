--!strict
-- Optional station activities. All timing, queue membership and checkpoints are server-owned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PracticeMath = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("PracticeMath"))
local ProfileStatus = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("ProfileStatus"))
local remote = ReplicatedStorage:WaitForChild("RuleRoomRemotes"):WaitForChild("StationAction") :: RemoteEvent
local arena = Workspace:WaitForChild("Arena")
local lobby = arena:WaitForChild("Lobby")
local course = lobby:WaitForChild("Practice")
local startPad = course:WaitForChild("StartPad") :: BasePart
local spawn = arena:WaitForChild("LobbySpawn") :: BasePart
local checkpoints: { BasePart } = {}
for index = 1, 7 do
	checkpoints[index] = course:WaitForChild("Checkpoint" .. index) :: BasePart
end
type Attempt = {
	character: Model,
	warmup: boolean,
	goal: number,
	deathConnection: RBXScriptConnection?,
	index: number,
	started: number,
	checkpointAt: number,
	lastPosition: Vector3,
	lastAt: number,
}
local attempts: { [Player]: Attempt } = {}
local lastRequest: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local practiceRecordConnections: { [Player]: RBXScriptConnection } = {}
local admissionConnections: { [Player]: RBXScriptConnection } = {}
local warnedPracticeBridge = false

local function practiceTime(value: any): number?
	return if typeof(value) == "number"
			and value > 0
			and value <= 1_000_000_000
			and value == value
		then value
		else nil
end

local function syncPracticeBest(player: Player)
	local saved = practiceTime(player:GetAttribute("BestPracticeSeconds"))
	local current = practiceTime(player:GetAttribute("PracticeBestSeconds"))
	-- Profile loading can finish after Station starts or after a local attempt.
	-- A later profile update must never replace a faster result from this session.
	if saved and (not current or saved < current) then
		player:SetAttribute("PracticeBestSeconds", saved)
	end
end

local function recordPractice(player: Player, seconds: number)
	-- The bridge is server-only and owned by the existing ProfileService instance.
	-- Lookup stays lazy so script startup order cannot stall the station.
	local bridge = script.Parent:FindFirstChild("RuleRoomRecordPractice")
	if not bridge or not bridge:IsA("BindableFunction") then
		if not warnedPracticeBridge then
			warnedPracticeBridge = true
			warn("[RuleRoom station] Practice record service unavailable; session result retained.")
		end
		return
	end
	local ok, problem = pcall(function()
		bridge:Invoke(player, seconds)
	end)
	if not ok and not warnedPracticeBridge then
		warnedPracticeBridge = true
		warn("[RuleRoom station] Practice record failed; session result retained: " .. tostring(problem))
	end
end

local function stopAttempt(player: Player)
	local attempt = attempts[player]
	attempts[player] = nil
	if attempt and attempt.deathConnection then
		attempt.deathConnection:Disconnect()
	end
end

local function cancel(player: Player)
	stopAttempt(player)
	player:SetAttribute("PracticeState", "Idle")
	player:SetAttribute("PracticeMode", "")
	player:SetAttribute("PracticeGoal", 0)
	player:SetAttribute("PracticeCheckpoint", 0)
	player:SetAttribute("PracticeStartedAt", 0)
end

local function initializePlayer(player: Player)
	-- A first-time arrival chooses when to start. Main also checks EntryChoiceMade,
	-- so script initialization order cannot admit a still-loading newcomer.
	if player:GetAttribute("EntryChoiceMade") == nil then
		player:SetAttribute("LobbyOnly", true)
		player:SetAttribute("EntryChoiceMade", false)
	end
	if player:GetAttribute("TemporaryPlayPrompt") == nil then
		player:SetAttribute("TemporaryPlayPrompt", false)
	end
	if not practiceRecordConnections[player] then
		practiceRecordConnections[player] = player
			:GetAttributeChangedSignal("BestPracticeSeconds")
			:Connect(function()
				syncPracticeBest(player)
			end)
	end
	if not admissionConnections[player] then
		admissionConnections[player] = player:GetAttributeChangedSignal("InRound"):Connect(function()
			if player:GetAttribute("InRound") == true then
				-- Admission wins immediately. Never move a character after Main admits it.
				cancel(player)
			end
		end)
	end
	syncPracticeBest(player)
end
table.insert(connections, Players.PlayerAdded:Connect(initializePlayer))
for _, player in Players:GetPlayers() do
	initializePlayer(player)
end

local function characterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function teleport(character: Model, root: BasePart, position: Vector3)
	character:PivotTo(CFrame.new(position))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function setMode(player: Player, action: string, acceptTemporary: any)
	local character, humanoid, root = characterParts(player)
	if not character or not humanoid or not root then
		return
	end
	local warmup = action == "Practice"
		and player:GetAttribute("LobbyOnly") ~= true
		and player:GetAttribute("EntryChoiceMade") == true
	if
		action == "Practice"
		and ProfileStatus.describe(player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent")).Loading
	then
		-- Do not let a finish outrun profile loading and lose its persistent record.
		player:SetAttribute(
			"ActionMessage",
			"Дождись загрузки прогресса, затем начни паркур."
		)
		return
	end
	if
		warmup
		and not ProfileStatus.canJoin(
			player:GetAttribute("DataStatus"),
			player:GetAttribute("DataPersistent"),
			player:GetAttribute("TemporaryPlayAccepted"),
			nil
		)
	then
		return
	end
	if action == "Join" then
		local status, persistent = player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent")
		if
			not ProfileStatus.canJoin(
				status,
				persistent,
				player:GetAttribute("TemporaryPlayAccepted"),
				acceptTemporary
			)
		then
			if ProfileStatus.describe(status, persistent).Temporary then
				player:SetAttribute("TemporaryPlayPrompt", true)
			end
			return
		end
		if ProfileStatus.describe(status, persistent).Temporary and acceptTemporary == true then
			player:SetAttribute("TemporaryPlayAccepted", true)
		end
	end
	cancel(player)
	player:SetAttribute("TemporaryPlayPrompt", false)
	if not warmup then
		player:SetAttribute("LobbyOnly", action ~= "Join")
		player:SetAttribute("EntryChoiceMade", true)
		player:SetAttribute("VotedMode", "")
	end
	if action == "Practice" then
		local now = Workspace:GetServerTimeNow()
		teleport(character, root, startPad.Position + Vector3.new(0, 4, 0))
		local attempt: Attempt = {
			character = character,
			warmup = warmup,
			goal = if warmup then 2 else #checkpoints,
			index = 0,
			started = now,
			checkpointAt = now,
			lastPosition = root.Position,
			lastAt = now,
		}
		attempts[player] = attempt
		attempt.deathConnection = humanoid.Died:Connect(function()
			if attempts[player] == attempt then
				cancel(player)
			end
		end)
		player:SetAttribute("PracticeMode", if warmup then "Warmup" else "Course")
		player:SetAttribute("PracticeGoal", attempt.goal)
		player:SetAttribute("PracticeCheckpoint", 0)
		player:SetAttribute("PracticeStartedAt", now)
		player:SetAttribute("PracticeState", "Running")
	elseif action == "Join" then
		-- Only an accepted server action records intent; automatic queue admission does not.
		local intent = player:GetAttribute("AnalyticsJoinIntent")
		player:SetAttribute("AnalyticsJoinIntent", (if typeof(intent) == "number" then intent else 0) + 1)
		teleport(character, root, spawn.Position + Vector3.new(0, 2, -12))
	end
end

local function request(player: Player, action: any, distance: number, acceptTemporary: any)
	local now = os.clock()
	local elapsed = now - (lastRequest[player] or -math.huge)
	-- Throttle malformed requests too; never accept a client supplied checkpoint/time/position.
	lastRequest[player] = now
	if not PracticeMath.canInteract(action, player:GetAttribute("InRound") == true, distance, elapsed) then
		return
	end
	setMode(player, action, acceptTemporary)
end

table.insert(
	connections,
	remote.OnServerEvent:Connect(function(player, action, acceptTemporary)
		if action ~= "Explore" and action ~= "Join" then
			return
		end
		if acceptTemporary ~= nil and type(acceptTemporary) ~= "boolean" then
			return
		end
		local _, _, root = characterParts(player)
		if not root then
			return
		end
		local p = root.Position
		if math.abs(p.X) > 90 or p.Z < 43 or p.Z > 193 or p.Y < -5 or p.Y > 45 then
			return
		end
		request(player, action, 0, acceptTemporary)
	end)
)
table.insert(
	connections,
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local parent = prompt.Parent
		if
			not parent
			or not parent:IsA("BasePart")
			or not parent:IsDescendantOf(lobby)
			or not prompt.Enabled
		then
			return
		end
		local action = parent:GetAttribute("StationAction")
		local _, _, root = characterParts(player)
		if not root then
			return
		end
		-- A world prompt cannot silently accept loss of saved progress.
		request(player, action, (root.Position - parent.Position).Magnitude, nil)
	end)
)

local function updatePlayer(player: Player, now: number)
	local character, humanoid, root = characterParts(player)
	if not character or not humanoid or not root then
		if attempts[player] then
			cancel(player)
		end
		return
	end
	if
		player:GetAttribute("InRound") ~= true
		and player:GetAttribute("LobbyOnly") ~= true
		and ProfileStatus.describe(player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent")).Temporary
		and player:GetAttribute("TemporaryPlayAccepted") ~= true
	then
		-- Finish an already-started trial normally after lease loss. At the next safe
		-- boundary leave the queue until the player explicitly accepts temporary play.
		cancel(player)
		player:SetAttribute("LobbyOnly", true)
		player:SetAttribute("TemporaryPlayPrompt", true)
		player:SetAttribute("VotedMode", "")
		teleport(character, root, spawn.Position + Vector3.new(0, 2, 0))
	end
	if
		player:GetAttribute("LobbyOnly") == true
		and player:GetAttribute("InRound") ~= true
		and root.Position.Y < -10
	then
		teleport(character, root, spawn.Position + Vector3.new(0, 2, 0))
	end
	local attempt = attempts[player]
	if not attempt then
		return
	end
	if
		attempt.character ~= character
		or player:GetAttribute("InRound") == true
		or (attempt.warmup and (player:GetAttribute("LobbyOnly") == true or player:GetAttribute(
			"EntryChoiceMade"
		) ~= true))
		or (not attempt.warmup and player:GetAttribute("LobbyOnly") ~= true)
	then
		cancel(player)
		return
	end
	local target = checkpoints[attempt.index + 1]
	local position = root.Position
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
	local feetY = position.Y - root.Size.Y / 2 - humanoid.HipHeight - legs
	local elapsed = now - attempt.lastAt
	local horizontal =
		Vector2.new(position.X - attempt.lastPosition.X, position.Z - attempt.lastPosition.Z).Magnitude
	if horizontal > 24 * math.max(elapsed, 0.25) + 6 then
		-- Reset this attempt to its last checkpoint after implausible movement; no fake record.
		attempt.started = now
		player:SetAttribute("PracticeStartedAt", now)
		attempt.index = 0
		player:SetAttribute("PracticeCheckpoint", 0)
		teleport(character, root, startPad.Position + Vector3.new(0, 4, 0))
		attempt.checkpointAt = now
	elseif target then
		local top = target.Position.Y + target.Size.Y / 2
		if
			PracticeMath.canCheckpoint(
				attempt.index,
				attempt.index + 1,
				position.X - target.Position.X,
				position.Z - target.Position.Z,
				feetY - top,
				root.AssemblyLinearVelocity.Y,
				now - attempt.checkpointAt
			)
		then
			attempt.index += 1
			attempt.checkpointAt = now
			player:SetAttribute("PracticeCheckpoint", attempt.index)
			if attempt.index == attempt.goal then
				-- Warmup only teaches movement. Its finish never becomes a timed record.
				if attempt.warmup then
					stopAttempt(player)
					player:SetAttribute("PracticeState", "Finished")
					return
				end
				local seconds = math.floor((now - attempt.started) * 100) / 100
				local best = practiceTime(player:GetAttribute("PracticeBestSeconds"))
				if not best or seconds < best then
					player:SetAttribute("PracticeBestSeconds", seconds)
				end
				player:SetAttribute("PracticeLastSeconds", seconds)
				player:SetAttribute("PracticeState", "Finished")
				-- Complete before invoking the bridge, preventing a yielding callback from
				-- making a second Heartbeat submit the same finish again.
				stopAttempt(player)
				recordPractice(player, seconds)
			end
		elseif feetY < (if attempt.index > 0 then checkpoints[attempt.index].Position.Y - 0.5 else -4) then
			local pad = if attempt.index > 0 then checkpoints[attempt.index] else startPad
			teleport(character, root, pad.Position + Vector3.new(0, 4, 0))
		end
	end
	attempt.lastPosition = root.Position
	attempt.lastAt = now
end

table.insert(
	connections,
	Players.PlayerRemoving:Connect(function(player)
		stopAttempt(player)
		lastRequest[player] = nil
		local admission = admissionConnections[player]
		if admission then
			admission:Disconnect()
			admissionConnections[player] = nil
		end
		local connection = practiceRecordConnections[player]
		if connection then
			connection:Disconnect()
			practiceRecordConnections[player] = nil
		end
	end)
)
local accumulated, boardTime = 0, 0
table.insert(
	connections,
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		boardTime += dt
		if accumulated < 0.1 then
			return
		end
		accumulated = 0
		local now = Workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			updatePlayer(player, now)
		end
		if boardTime >= 2 then
			boardTime = 0
			local lines: { string } = {}
			local ranked = Players:GetPlayers()
			table.sort(ranked, function(a, b)
				return (a:GetAttribute("RunScore") or 0) > (b:GetAttribute("RunScore") or 0)
			end)
			for index = 1, math.min(5, #ranked) do
				local player = ranked[index]
				table.insert(
					lines,
					string.format(
						"%d. %s — %d очков",
						index,
						player.DisplayName,
						player:GetAttribute("RunScore") or 0
					)
				)
			end
			local board = lobby:FindFirstChild("SessionBoard")
			local display = if board then board:FindFirstChild("Display") else nil
			local detail = if display then display:FindFirstChild("Detail") else nil
			if detail and detail:IsA("TextLabel") then
				detail.Text = table.concat(lines, "\n")
			end
		end
	end)
)
script.Destroying:Connect(function()
	for _, connection in connections do
		connection:Disconnect()
	end
	for player, connection in practiceRecordConnections do
		connection:Disconnect()
		practiceRecordConnections[player] = nil
	end
	for player, connection in admissionConnections do
		connection:Disconnect()
		admissionConnections[player] = nil
	end
	for player in attempts do
		cancel(player)
	end
end)
