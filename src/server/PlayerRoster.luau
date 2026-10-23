--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
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
	trialIndex: number,
	ruleName: string,
}
type RunRecord = { points: number, survived: number, finale: boolean, completed: boolean, charges: number }
type PlayerScope = {
	character: Model?,
	generation: number,
	ready: boolean,
	connections: { RBXScriptConnection },
	deathConnection: RBXScriptConnection?,
	collisionConnections: { RBXScriptConnection },
	partGroups: { [BasePart]: string },
	score: IntValue,
	best: IntValue,
}
export type Roster = {
	BeginRun: () -> (),
	StartRound: (CFrame, number?, string?) -> number,
	EndRound: () -> (),
	PrepareIntermission: () -> (),
	CompleteRun: (boolean) -> number,
	CheckBoundaries: () -> (),
	AliveCount: () -> number,
	ForEachAlive: ((Player, Humanoid, BasePart) -> ()) -> (),
	AwardSurvivors: (string) -> (),
	AwardStar: (Player) -> boolean,
	AwardCharge: (Player) -> boolean,
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
	local currentTrial = 0
	local runInProgress = false
	local characterGroup = "RuleRoomCharacters"
	local createdCharacterGroup = not PhysicsService:IsCollisionGroupRegistered(characterGroup)
	if createdCharacterGroup then
		PhysicsService:RegisterCollisionGroup(characterGroup)
	end
	local originalSelfCollision = PhysicsService:CollisionGroupsAreCollidable(characterGroup, characterGroup)
	local originalWorldCollision = PhysicsService:CollisionGroupsAreCollidable(characterGroup, "Default")
	PhysicsService:CollisionGroupSetCollidable(characterGroup, characterGroup, false)
	PhysicsService:CollisionGroupSetCollidable(characterGroup, "Default", true)
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

	local function eliminate(player: Player, kill: boolean, reason: string?)
		local entry = participants[player]
		if not entry or not entry.alive then
			return
		end
		entry.alive = false
		restoreMovement(entry)
		player:SetAttribute("InRound", false)
		player:SetAttribute("Eliminated", true)
		player:SetAttribute("TrialResult" .. entry.trialIndex, "Failed")
		player:SetAttribute("LastTrialReason", reason or ("Опасность: " .. entry.ruleName))
		if kill and entry.humanoid.Health > 0 then
			entry.humanoid.Health = 0
		end
	end

	local function restorePartGroup(scope: PlayerScope, descendant: Instance)
		if not descendant:IsA("BasePart") then
			return
		end
		local original = scope.partGroups[descendant]
		if original then
			if descendant.Parent and descendant.CollisionGroup == characterGroup then
				descendant.CollisionGroup = if PhysicsService:IsCollisionGroupRegistered(original)
					then original
					else "Default"
			end
			scope.partGroups[descendant] = nil
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
		for _, connection in scope.collisionConnections do
			connection:Disconnect()
		end
		table.clear(scope.collisionConnections)
		for descendant in scope.partGroups do
			restorePartGroup(scope, descendant)
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
		local function assignCollisionGroup(descendant: Instance)
			if
				destroyed
				or scopes[player] ~= scope
				or scope.generation ~= generation
				or scope.character ~= character
				or not descendant:IsDescendantOf(character)
			then
				return
			end
			if descendant:IsA("BasePart") and not scope.partGroups[descendant] then
				scope.partGroups[descendant] = descendant.CollisionGroup
				descendant.CollisionGroup = characterGroup
			end
		end
		table.insert(scope.collisionConnections, character.DescendantAdded:Connect(assignCollisionGroup))
		table.insert(
			scope.collisionConnections,
			character.DescendantRemoving:Connect(function(descendant)
				if scope.generation == generation and scope.character == character then
					restorePartGroup(scope, descendant)
				end
			end)
		)
		for _, descendant in character:GetDescendants() do
			assignCollisionGroup(descendant)
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
			collisionConnections = {},
			partGroups = {},
			deathConnection = nil,
			score = intValue(stats :: Folder, "Score"),
			best = intValue(stats :: Folder, "Best"),
		}
		scopes[player] = scope
		player:SetAttribute("InRound", false)
		player:SetAttribute("Eliminated", false)
		player:SetAttribute("RunScore", 0)
		player:SetAttribute("RunSurvived", 0)
		player:SetAttribute("RunCharges", 0)
		player:SetAttribute("RunWon", false)
		player:SetAttribute("LastTrialReason", "")
		for index, result in
			RuleMath.joinedTrialResults(if runInProgress then currentTrial else 0, Config.RuleCount)
		do
			player:SetAttribute("TrialResult" .. index, result)
		end
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
		currentTrial = 0
		runInProgress = true
		for _, player in Players:GetPlayers() do
			player:SetAttribute("RunScore", 0)
			player:SetAttribute("RunSurvived", 0)
			player:SetAttribute("Eliminated", false)
			player:SetAttribute("RunCharges", 0)
			player:SetAttribute("RunWon", false)
			player:SetAttribute("LastTrialReason", "")
			for index = 1, Config.RuleCount do
				player:SetAttribute("TrialResult" .. index, "Pending")
			end
		end
	end

	function roster.StartRound(arenaCFrame: CFrame, trialIndex: number?, ruleId: string?): number
		-- Main ends the previous trial before this atomic admission pass (no yields).
		assert(next(participants) == nil, "EndRound must precede StartRound")
		local index = trialIndex or math.min(currentTrial + 1, Config.RuleCount)
		assert(index % 1 == 0 and index >= 1 and index <= Config.RuleCount, "Invalid trial index")
		currentTrial = index
		runInProgress = true
		local metadata = if ruleId then Config.Rules[ruleId] else nil
		local ruleName = if metadata then metadata.Name else "испытание комнаты"
		local entered = 0
		for _, player in Players:GetPlayers() do
			player:SetAttribute("InRound", false)
			player:SetAttribute("Eliminated", false)
			for previous = 1, index do
				local attribute = "TrialResult" .. previous
				local result = player:GetAttribute(attribute)
				if result == nil or result == "Pending" then
					player:SetAttribute(attribute, "Missed")
				end
			end
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
					or { points = 0, survived = 0, finale = false, completed = false, charges = 0 }
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
					trialIndex = index,
					ruleName = ruleName,
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
				player:SetAttribute("TrialResult" .. index, "Active")
				player:SetAttribute("LastTrialReason", "")
				player:SetAttribute("InRound", true)
				entered += 1
			end
		end
		return entered
	end

	function roster.EndRound()
		for player, entry in participants do
			restoreMovement(entry)
			if player:GetAttribute("TrialResult" .. entry.trialIndex) == "Active" then
				player:SetAttribute("TrialResult" .. entry.trialIndex, "Failed")
				player:SetAttribute("LastTrialReason", "Испытание не завершено")
			end
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
					local reason: string? = nil
					if
						not RuleMath.isFinite(p.X)
						or not RuleMath.isFinite(p.Y)
						or not RuleMath.isFinite(p.Z)
					then
						reason = "Некорректное положение персонажа"
					elseif p.Y < Config.EliminationY then
						reason = "Упал за край или в провал"
					elseif
						p.Y > 110
						or math.abs(p.X) > Config.ArenaHalfSize + 3
						or math.abs(p.Z) > Config.ArenaHalfSize + 3
					then
						reason = "Вышел за пределы комнаты"
					elseif not movementPlausible(player, entry, p) then
						reason = if player:GetAttribute("MovementViolation") == "Travel"
							then "Слишком резкое перемещение"
							else "Слишком долго без опоры"
					end
					if reason then
						eliminate(player, true, reason)
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

	function roster.AwardSurvivors(ruleId: string)
		for player, entry in participants do
			if not entry.rewarded and entry.root.Position.Y >= 1 and award(player, Config.SurvivorPoints) then
				entry.rewarded = true
				local record = records[player]
				record.survived += 1
				if ruleId == "ReactorRush" then
					record.finale = true
				end
				player:SetAttribute("RunSurvived", record.survived)
				player:SetAttribute("TrialResult" .. entry.trialIndex, "Survived")
				player:SetAttribute("LastTrialReason", "Испытание пройдено")
				profiles.AwardSurvival(player)
			end
		end
	end

	function roster.AwardStar(player: Player): boolean
		if not award(player, Config.StarPoints) then
			return false
		end
		profiles.AwardStar(player)
		return true
	end

	function roster.AwardCharge(player: Player): boolean
		local entry, record = participants[player], records[player]
		if not entry or not record or not isCurrent(player, entry) then
			return false
		end
		record.charges += 1
		player:SetAttribute("RunCharges", record.charges)
		return true
	end

	function roster.CompleteRun(teamSuccess: boolean): number
		runInProgress = false
		local winners = 0
		for player, record in records do
			local eligible, won = RuleMath.runOutcome(record.survived, record.finale, teamSuccess)
			if eligible and not record.completed and player.Parent == Players then
				record.completed = true
				player:SetAttribute("RunWon", won)
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
		if createdCharacterGroup then
			PhysicsService:UnregisterCollisionGroup(characterGroup)
		else
			PhysicsService:CollisionGroupSetCollidable(characterGroup, characterGroup, originalSelfCollision)
			PhysicsService:CollisionGroupSetCollidable(characterGroup, "Default", originalWorldCollision)
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
