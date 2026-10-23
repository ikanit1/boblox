--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local RuleMath = require(script.Parent.RuleMath)

type Profiles = {
	IsReady: (Player) -> boolean,
	AwardSurvival: (Player) -> (),
	AwardStar: (Player) -> (),
	CompleteRun: (Player, boolean) -> (),
}
type Participant = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	alive: boolean,
	rewarded: boolean,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	lastPosition: Vector3,
	lastSampleAt: number,
	travelStartedAt: number,
	travelDistance: number,
	airborneSeconds: number,
}
type RunRecord = { points: number, survived: number, finale: boolean, completed: boolean }
type PlayerScope = {
	character: Model?,
	generation: number,
	ready: boolean,
	connections: { RBXScriptConnection },
	deathConnection: RBXScriptConnection?,
	score: IntValue,
	best: IntValue,
}
export type Roster = {
	BeginRun: () -> (),
	StartRound: (CFrame) -> number,
	EndRound: () -> (),
	PrepareIntermission: () -> (),
	CompleteRun: (boolean) -> number,
	CheckBoundaries: () -> (),
	AliveCount: () -> number,
	ForEachAlive: ((Player, Humanoid, BasePart) -> ()) -> (),
	AwardSurvivors: (string) -> number,
	AwardStar: (Player) -> boolean,
	Destroy: () -> (),
}
local PlayerRoster = {}

local function intValue(folder: Folder, name: string): IntValue
	local existing = folder:FindFirstChild(name)
	if existing then
		assert(existing:IsA("IntValue"))
		return existing
	end
	local value = Instance.new("IntValue")
	value.Name = name
	value.Parent = folder
	return value
end

local function teleport(character: Model, root: BasePart, target: CFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(target)
end

function PlayerRoster.new(lobbyCFrame: CFrame, profiles: Profiles): Roster
	local scopes: { [Player]: PlayerScope } = {}
	local participants: { [Player]: Participant } = {}
	local records: { [Player]: RunRecord } = {}
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local arena = Workspace:FindFirstChild("Arena")
	assert(arena, "Arena must exist before the roster")
	local groundQuery = RaycastParams.new()
	groundQuery.FilterType = Enum.RaycastFilterType.Include
	groundQuery.FilterDescendantsInstances = { arena }
	groundQuery.RespectCanCollide = true
	groundQuery.IgnoreWater = true

	local function restoreMovement(participant: Participant)
		local humanoid = participant.humanoid
		if humanoid.Parent then
			humanoid.WalkSpeed = participant.walkSpeed
			humanoid.JumpPower = participant.jumpPower
			humanoid.JumpHeight = participant.jumpHeight
			humanoid.AutoRotate = participant.autoRotate
		end
	end

	local function eliminate(player: Player, kill: boolean)
		local entry = participants[player]
		if not entry or not entry.alive then
			return
		end
		entry.alive = false
		restoreMovement(entry)
		player:SetAttribute("InRound", false)
		player:SetAttribute("Eliminated", true)
		if kill and entry.humanoid.Health > 0 then
			entry.humanoid.Health = 0
		end
	end

	local function clearCharacter(scope: PlayerScope)
		scope.generation += 1
		scope.character = nil
		scope.ready = false
		if scope.deathConnection then
			scope.deathConnection:Disconnect()
			scope.deathConnection = nil
		end
	end

	local function bindCharacter(player: Player, character: Model)
		local scope = scopes[player]
		if destroyed or not scope or player.Character ~= character or scope.character == character then
			return
		end
		-- A replacement character is always a spectator until the next trial boundary.
		eliminate(player, false)
		clearCharacter(scope)
		scope.character = character
		local generation = scope.generation
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if
			destroyed
			or scopes[player] ~= scope
			or generation ~= scope.generation
			or player.Character ~= character
		then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			return
		end
		scope.deathConnection = humanoid.Died:Connect(function()
			local entry = participants[player]
			if entry and entry.character == character then
				eliminate(player, false)
			end
		end)
		teleport(character, root, lobbyCFrame + Vector3.new(((player.UserId % 5) - 2) * 3, 2, 0))
		scope.ready = true
	end

	local function addPlayer(player: Player)
		if destroyed or scopes[player] then
			return
		end
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			assert(stats:IsA("Folder"))
		else
			stats = Instance.new("Folder")
			stats.Name = "leaderstats"
			stats.Parent = player
		end
		local scope: PlayerScope = {
			character = nil,
			generation = 0,
			ready = false,
			connections = {},
			deathConnection = nil,
			score = intValue(stats :: Folder, "Score"),
			best = intValue(stats :: Folder, "Best"),
		}
		scopes[player] = scope
		player:SetAttribute("InRound", false)
		player:SetAttribute("Eliminated", false)
		player:SetAttribute("RunScore", 0)
		player:SetAttribute("RunSurvived", 0)
		table.insert(
			scope.connections,
			player.CharacterAdded:Connect(function(character)
				task.spawn(bindCharacter, player, character)
			end)
		)
		table.insert(
			scope.connections,
			player.CharacterRemoving:Connect(function(character)
				local entry = participants[player]
				if entry and entry.character == character then
					eliminate(player, false)
				end
				if scope.character == character then
					clearCharacter(scope)
				end
			end)
		)
		if player.Character then
			task.spawn(bindCharacter, player, player.Character)
		end
	end

	local function removePlayer(player: Player)
		local entry = participants[player]
		if entry then
			restoreMovement(entry)
		end
		local scope = scopes[player]
		if scope then
			clearCharacter(scope)
			for _, connection in scope.connections do
				connection:Disconnect()
			end
		end
		scopes[player] = nil
		participants[player] = nil
		records[player] = nil
	end

	local function isCurrent(player: Player, entry: Participant): boolean
		return entry.alive
			and player.Parent == Players
			and player.Character == entry.character
			and entry.humanoid.Health > 0
			and entry.root:IsDescendantOf(entry.character)
	end

	local function movementPlausible(player: Player, entry: Participant, position: Vector3): boolean
		local now = os.clock()
		local delta = position - entry.lastPosition
		entry.travelDistance += Vector2.new(delta.X, delta.Z).Magnitude
		local elapsed = now - entry.travelStartedAt
		if not RuleMath.travelPlausible(entry.travelDistance, elapsed, entry.walkSpeed) then
			player:SetAttribute("MovementViolation", "Travel")
			return false
		end
		if elapsed >= 1 then
			entry.travelDistance = 0
			entry.travelStartedAt = now
		end
		local legs = if entry.humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
		local groundDistance = entry.root.Size.Y / 2 + entry.humanoid.HipHeight + legs + 1
		local ground = Workspace:Raycast(position, Vector3.new(0, -groundDistance, 0), groundQuery)
		if ground then
			entry.airborneSeconds = 0
		else
			-- A stalled server may miss a legitimate landing; don't charge the player
			-- for a long interval during which there were no physics observations.
			entry.airborneSeconds += math.clamp(now - entry.lastSampleAt, 0, 0.25)
		end
		entry.lastSampleAt = now
		entry.lastPosition = position
		if not RuleMath.airbornePlausible(entry.airborneSeconds, Workspace.Gravity) then
			player:SetAttribute("MovementViolation", "Airborne")
			return false
		end
		return true
	end

	local function award(player: Player, amount: number): boolean
		local entry, scope, record = participants[player], scopes[player], records[player]
		if not entry or not scope or not record or not isCurrent(player, entry) then
			return false
		end
		record.points += amount
		scope.score.Value += amount
		scope.best.Value = math.max(scope.best.Value, record.points)
		player:SetAttribute("RunScore", record.points)
		return true
	end

	local roster = {} :: Roster
	function roster.BeginRun()
		table.clear(records)
		for _, player in Players:GetPlayers() do
			player:SetAttribute("RunScore", 0)
			player:SetAttribute("RunSurvived", 0)
			player:SetAttribute("Eliminated", false)
		end
	end

	function roster.StartRound(arenaCFrame: CFrame): number
		-- Main ends the previous trial before this atomic admission pass (no yields).
		assert(next(participants) == nil, "EndRound must precede StartRound")
		local entered = 0
		for _, player in Players:GetPlayers() do
			player:SetAttribute("InRound", false)
			player:SetAttribute("Eliminated", false)
			local scope = scopes[player]
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if
				entered < Config.MaxPlayers
				and profiles.IsReady(player)
				and scope
				and scope.ready
				and character
				and scope.character == character
				and humanoid
				and humanoid.Health > 0
				and root
				and root:IsA("BasePart")
			then
				records[player] = records[player]
					or { points = 0, survived = 0, finale = false, completed = false }
				participants[player] = {
					character = character,
					humanoid = humanoid,
					root = root,
					alive = true,
					rewarded = false,
					walkSpeed = humanoid.WalkSpeed,
					jumpPower = humanoid.JumpPower,
					jumpHeight = humanoid.JumpHeight,
					autoRotate = humanoid.AutoRotate,
					lastPosition = root.Position,
					lastSampleAt = os.clock(),
					travelStartedAt = os.clock(),
					travelDistance = 0,
					airborneSeconds = 0,
				}
				for _, child in character:GetChildren() do
					if child:IsA("ForceField") then
						child:Destroy()
					end
				end
				humanoid.Health = humanoid.MaxHealth
				local offset = Vector3.new((entered % 6 - 2.5) * 10, 0, (math.floor(entered / 6) - 0.5) * 20)
				teleport(character, root, arenaCFrame + offset)
				-- Only this server-authorized teleport resets the trial's movement anchor.
				participants[player].lastPosition = root.Position
				player:SetAttribute("MovementViolation", "")
				player:SetAttribute("InRound", true)
				entered += 1
			end
		end
		return entered
	end

	function roster.EndRound()
		for _, entry in participants do
			restoreMovement(entry)
		end
		table.clear(participants)
		for _, player in Players:GetPlayers() do
			player:SetAttribute("InRound", false)
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				teleport(character, root, lobbyCFrame + Vector3.new(((player.UserId % 5) - 2) * 3, 2, 0))
			end
		end
	end

	function roster.PrepareIntermission()
		for _, player in Players:GetPlayers() do
			player:SetAttribute("Eliminated", false)
		end
	end

	function roster.CheckBoundaries()
		for player, entry in participants do
			if entry.alive then
				if not isCurrent(player, entry) then
					eliminate(player, false)
				else
					local p = entry.root.Position
					if
						not RuleMath.isFinite(p.X)
						or not RuleMath.isFinite(p.Y)
						or not RuleMath.isFinite(p.Z)
						or p.Y < Config.EliminationY
						or p.Y > 110
						or math.abs(p.X) > Config.ArenaHalfSize + 3
						or math.abs(p.Z) > Config.ArenaHalfSize + 3
						or not movementPlausible(player, entry, p)
					then
						eliminate(player, true)
					end
				end
			end
		end
	end

	function roster.AliveCount(): number
		local count = 0
		for player, entry in participants do
			if isCurrent(player, entry) then
				count += 1
			end
		end
		return count
	end

	function roster.ForEachAlive(callback: (Player, Humanoid, BasePart) -> ())
		for player, entry in participants do
			if isCurrent(player, entry) then
				callback(player, entry.humanoid, entry.root)
			end
		end
	end

	function roster.AwardSurvivors(ruleId: string): number
		local awarded = 0
		for player, entry in participants do
			if not entry.rewarded and entry.root.Position.Y >= 1 and award(player, Config.SurvivorPoints) then
				entry.rewarded = true
				local record = records[player]
				record.survived += 1
				if ruleId == "ReactorRush" then
					record.finale = true
				end
				player:SetAttribute("RunSurvived", record.survived)
				profiles.AwardSurvival(player)
				awarded += 1
			end
		end
		return awarded
	end

	function roster.AwardStar(player: Player): boolean
		if not award(player, Config.StarPoints) then
			return false
		end
		profiles.AwardStar(player)
		return true
	end

	function roster.CompleteRun(teamSuccess: boolean): number
		local winners = 0
		for player, record in records do
			local eligible, won = RuleMath.runOutcome(record.survived, record.finale, teamSuccess)
			if eligible and not record.completed and player.Parent == Players then
				record.completed = true
				profiles.CompleteRun(player, won)
				if won then
					winners += 1
				end
			end
		end
		return winners
	end

	function roster.Destroy()
		if destroyed then
			return
		end
		roster.EndRound()
		destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		for player in scopes do
			removePlayer(player)
		end
	end
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	return roster
end
return PlayerRoster
