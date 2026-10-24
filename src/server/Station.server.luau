--!strict
-- Optional station activities. All timing, queue membership and checkpoints are server-owned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PracticeMath = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("PracticeMath"))
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
	index: number,
	started: number,
	checkpointAt: number,
	lastPosition: Vector3,
	lastAt: number,
}
local attempts: { [Player]: Attempt } = {}
local lastRequest: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}

local function cancel(player: Player)
	attempts[player] = nil
	player:SetAttribute("PracticeState", "Idle")
	player:SetAttribute("PracticeCheckpoint", 0)
	player:SetAttribute("PracticeStartedAt", 0)
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

local function setMode(player: Player, action: string)
	local character, _, root = characterParts(player)
	if not character or not root then
		return
	end
	cancel(player)
	player:SetAttribute("LobbyOnly", action ~= "Join")
	player:SetAttribute("VotedMode", "")
	if action == "Practice" then
		local now = Workspace:GetServerTimeNow()
		teleport(character, root, startPad.Position + Vector3.new(0, 4, 0))
		attempts[player] = {
			character = character,
			index = 0,
			started = now,
			checkpointAt = now,
			lastPosition = root.Position,
			lastAt = now,
		}
		player:SetAttribute("PracticeCheckpoint", 0)
		player:SetAttribute("PracticeStartedAt", now)
		player:SetAttribute("PracticeState", "Running")
	elseif action == "Join" then
		teleport(character, root, spawn.Position + Vector3.new(0, 2, -12))
	end
end

local function request(player: Player, action: any, distance: number)
	local now = os.clock()
	local elapsed = now - (lastRequest[player] or -math.huge)
	-- Throttle malformed requests too; never accept a client supplied checkpoint/time/position.
	lastRequest[player] = now
	if not PracticeMath.canInteract(action, player:GetAttribute("InRound") == true, distance, elapsed) then
		return
	end
	setMode(player, action)
end

table.insert(
	connections,
	remote.OnServerEvent:Connect(function(player, action)
		if action ~= "Explore" and action ~= "Join" then
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
		request(player, action, 0)
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
		request(player, action, (root.Position - parent.Position).Magnitude)
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
		or player:GetAttribute("LobbyOnly") ~= true
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
			if attempt.index == #checkpoints then
				local seconds = math.floor((now - attempt.started) * 100) / 100
				local best = player:GetAttribute("PracticeBestSeconds")
				if typeof(best) ~= "number" or seconds < best then
					player:SetAttribute("PracticeBestSeconds", seconds)
				end
				player:SetAttribute("PracticeLastSeconds", seconds)
				player:SetAttribute("PracticeState", "Finished")
				attempts[player] = nil
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
		attempts[player] = nil
		lastRequest[player] = nil
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
	for player in attempts do
		cancel(player)
	end
end)
