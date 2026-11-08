--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local RunPresentation = require(ReplicatedStorage.RuleRoomShared:WaitForChild("RunPresentation"))
local RuleMath = require(script.Parent.RuleMath)
local ContributionLedger = require(script.Parent.ContributionLedger)

type Profiles = {
	IsReady: (Player) -> boolean,
	AwardSurvival: (Player) -> (),
	AwardStar: (Player) -> boolean?,
	CompleteRun: (Player, boolean) -> (),
	RecordFlawless: (Player, string, "Collected"?) -> boolean,
}
type Participant = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	alive: boolean,
	rewarded: boolean,
	forfeited: boolean,
	rewardForfeited: boolean,
	generation: number,
	movementViolations: number,
	damaged: boolean,
	lastHealth: number,
	trialStartedAt: number,
	trialStars: number,
	damageConnection: RBXScriptConnection?,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	lastPosition: Vector3,
	lastSampleAt: number,
	travelStartedAt: number,
	travelDistance: number,
	airborneSeconds: number,
	lastVerticalVelocity: number,
	trialIndex: number,
	ruleId: string,
}
type RunRecord = {
	contributionToken: number?,
	points: number,
	survived: number,
	finale: boolean,
	completed: boolean,
	coins: number,
	xp: number,
	stars: number,
	energy: number,
}
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
	BeginRun: ({ string }?) -> (),
	StartRound: (CFrame, number?, string?) -> number,
	EndRound: (boolean?) -> (),
	PrepareIntermission: () -> (),
	CompleteRun: (boolean, boolean?) -> number,
	Contributions: (number) -> string,
	CheckBoundaries: () -> (),
	AliveCount: () -> number,
	ForEachAlive: ((Player, Humanoid, BasePart) -> ()) -> (),
	AwardSurvivors: (string) -> (number, number),
	ForfeitedAliveCount: () -> number,
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
	local contributions = ContributionLedger.new(Config.MaxPlayers * Config.RuleCount, Config.RuleCount)
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local currentTrial = 0
	local runDeck: { string } = {}
	local arena = Workspace:FindFirstChild("Arena")
	assert(arena, "Arena must exist before the roster")
	local characterGroup = "RuleRoomCharacters"
	local createdCharacterGroup = not PhysicsService:IsCollisionGroupRegistered(characterGroup)
	if createdCharacterGroup then
		PhysicsService:RegisterCollisionGroup(characterGroup)
	end
	local originalSelfCollision = PhysicsService:CollisionGroupsAreCollidable(characterGroup, characterGroup)
	local originalWorldCollision = PhysicsService:CollisionGroupsAreCollidable(characterGroup, "Default")
	PhysicsService:CollisionGroupSetCollidable(characterGroup, characterGroup, false)
	PhysicsService:CollisionGroupSetCollidable(characterGroup, "Default", true)
	local partOwners: { [BasePart]: PlayerScope } = {}
	local groundQuery = RaycastParams.new()
	groundQuery.FilterType = Enum.RaycastFilterType.Include
	groundQuery.FilterDescendantsInstances = { arena }
	groundQuery.RespectCanCollide = true
	groundQuery.IgnoreWater = true

	local function resetRunDisplay(player: Player)
		player:SetAttribute("ResultReady", false)
		player:SetAttribute("RunResult", "None")
		player:SetAttribute("NewRecord", "")
		player:SetAttribute("RunScore", 0)
		player:SetAttribute("RunSurvived", 0)
		player:SetAttribute("RunCoinsEarned", 0)
		player:SetAttribute("RunXPEarned", 0)
		player:SetAttribute("RunStars", 0)
		player:SetAttribute("RunEnergy", 0)
		player:SetAttribute("LastTrialOutcome", "Pending")
		player:SetAttribute("LastTrialRule", "")
		for index = 1, Config.RuleCount do
			player:SetAttribute(
				"TrialOutcome_" .. index,
				if index <= currentTrial then "Skipped" else "Pending"
			)
			player:SetAttribute("TrialRule_" .. index, runDeck[index] or "")
		end
	end

	local function publishOutcome(player: Player, entry: Participant, outcome: string)
		player:SetAttribute("TrialOutcome_" .. entry.trialIndex, outcome)
		player:SetAttribute("TrialRule_" .. entry.trialIndex, entry.ruleId)
		player:SetAttribute("LastTrialRule", entry.ruleId)
		player:SetAttribute("LastTrialOutcome", outcome)
	end

	local function captureReward(player: Player, grant: () -> ())
		local coins, xp = player:GetAttribute("Coins"), player:GetAttribute("XP")
		-- Production reward methods mutate and replicate synchronously; there is no yield
		-- in this interval, so purchases and quest claims cannot enter this ledger.
		grant()
		local record = records[player]
		if record then
			record.coins += RunPresentation.rewardDelta(coins, player:GetAttribute("Coins"))
			record.xp += RunPresentation.rewardDelta(xp, player:GetAttribute("XP"))
			player:SetAttribute("RunCoinsEarned", record.coins)
			player:SetAttribute("RunXPEarned", record.xp)
		end
	end

	local function restoreMovement(participant: Participant)
		local humanoid = participant.humanoid
		if humanoid.Parent then
			humanoid.WalkSpeed = participant.walkSpeed
			humanoid.JumpPower = participant.jumpPower
			humanoid.JumpHeight = participant.jumpHeight
			humanoid.AutoRotate = participant.autoRotate
		end
	end

	local function stopDamageTracking(entry: Participant)
		if entry.damageConnection then
			entry.damageConnection:Disconnect()
			entry.damageConnection = nil
		end
	end

	local function eliminate(player: Player, kill: boolean, reason: string?)
		local entry = participants[player]
		if not entry or not entry.alive then
			return
		end
		entry.alive = false
		stopDamageTracking(entry)
		player:SetAttribute("MovementWarning", false)
		local lastDamageAt = player:GetAttribute("LastDamageAt")
		local lastDamageRule = player:GetAttribute("LastDamageRule")
		local recentDamage = typeof(lastDamageAt) == "number"
			and Workspace:GetServerTimeNow() - lastDamageAt <= 1
			and typeof(lastDamageRule) == "string"
			and lastDamageRule ~= ""
		player:SetAttribute("EliminationReason", reason or (if recentDamage then lastDamageRule else "Reset"))
		publishOutcome(player, entry, "Eliminated")
		restoreMovement(entry)
		player:SetAttribute("InRound", false)
		player:SetAttribute("Eliminated", true)
		if kill and entry.humanoid.Health > 0 then
			entry.humanoid.Health = 0
		end
	end

	local function restorePartGroup(scope: PlayerScope, descendant: Instance)
		if not descendant:IsA("BasePart") then
			return
		end
		local original = scope.partGroups[descendant]
		if not original then
			return
		end
		scope.partGroups[descendant] = nil
		if partOwners[descendant] ~= scope then
			return
		end
		partOwners[descendant] = nil
		-- Removed accessories can already be unparented when deferred signals run.
		if descendant.CollisionGroup == characterGroup then
			descendant.CollisionGroup = if PhysicsService:IsCollisionGroupRegistered(original)
				then original
				else "Default"
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
				local previousOwner = partOwners[descendant]
				local original = descendant.CollisionGroup
				-- Preserve the original group if an accessory moves between two characters.
				if previousOwner and previousOwner ~= scope then
					if original == characterGroup then
						original = previousOwner.partGroups[descendant] or "Default"
					end
					previousOwner.partGroups[descendant] = nil
				end
				scope.partGroups[descendant] = original
				partOwners[descendant] = scope
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
		local function tryReady()
			if
				destroyed
				or scopes[player] ~= scope
				or generation ~= scope.generation
				or player.Character ~= character
				or scope.ready
			then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not root or not root:IsA("BasePart") then
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
		-- A delayed avatar can become ready even after the old ten-second timeout.
		-- The callback is generation-bound and is disconnected on replacement/removal.
		table.insert(scope.collisionConnections, character.ChildAdded:Connect(tryReady))
		tryReady()
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
		player:SetAttribute("MovementWarning", false)
		resetRunDisplay(player)
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
		local record = records[player]
		if record then
			contributions.Leave(player.UserId, record.contributionToken)
		end
		local entry = participants[player]
		if entry then
			stopDamageTracking(entry)
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
		local scope = scopes[player]
		return scope ~= nil
			and scope.generation == entry.generation
			and scope.character == entry.character
			and entry.alive
			and player.Parent == Players
			and player.Character == entry.character
			and entry.humanoid.Health > 0
			and entry.root:IsDescendantOf(entry.character)
	end

	local function resetMovementWindow(entry: Participant)
		local now = os.clock()
		entry.lastPosition = entry.root.Position
		entry.lastSampleAt = now
		entry.travelStartedAt = now
		entry.travelDistance = 0
		entry.airborneSeconds = 0
		entry.lastVerticalVelocity = 0
	end

	local function warnMovement(player: Player, entry: Participant)
		-- Keep the model's pivot offset so the root returns to the last accepted sample.
		local target = entry.character:GetPivot() + (entry.lastPosition - entry.root.Position)
		teleport(entry.character, entry.root, target)
		resetMovementWindow(entry)
		entry.rewardForfeited = true
		player:SetAttribute("MovementWarning", true)
	end

	local function movementPlausible(player: Player, entry: Participant, position: Vector3): boolean
		local now = os.clock()
		local sampleSeconds = now - entry.lastSampleAt
		local verticalVelocity = entry.root.AssemblyLinearVelocity.Y
		local gravityScale = if entry.root:GetAttribute("TrialGravityScale")
				== Config.LowGravityMultiplier
			then Config.LowGravityMultiplier
			else 1
		local effectiveGravity = Workspace.Gravity * gravityScale
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
		local landedBetweenSamples = false
		if
			not ground
			and entry.lastVerticalVelocity < -1
			and verticalVelocity > 1
			and sampleSeconds <= 0.25
		then
			local jumpSpeed = if entry.humanoid.UseJumpPower
				then entry.jumpPower
				else math.sqrt(2 * Workspace.Gravity * entry.jumpHeight)
			local distance = groundDistance + jumpSpeed * jumpSpeed / (2 * effectiveGravity) + 1
			local support = Workspace:Raycast(position, Vector3.new(0, -distance, 0), groundQuery)
			local previousSupport =
				Workspace:Raycast(entry.lastPosition, Vector3.new(0, -distance, 0), groundQuery)
			if
				support
				and previousSupport
				and support.Normal.Y >= 0.7
				and previousSupport.Normal.Y >= 0.7
				and math.abs(support.Position.Y - previousSupport.Position.Y) <= 0.5
			then
				local feetOffset = groundDistance - 1
				landedBetweenSamples = RuleMath.missedLanding(
					entry.lastPosition.Y - feetOffset - previousSupport.Position.Y,
					position.Y - feetOffset - support.Position.Y,
					entry.lastVerticalVelocity,
					verticalVelocity,
					sampleSeconds,
					effectiveGravity,
					jumpSpeed
				)
			end
		end
		if ground or landedBetweenSamples or sampleSeconds > 0.25 then
			entry.airborneSeconds = 0
		else
			-- A gap over 250ms invalidates continuous airborne evidence: it may hide
			-- a landing. Otherwise preserve the existing 4s/7s maximum continuous flight.
			entry.airborneSeconds += math.max(0, sampleSeconds)
		end
		if not RuleMath.airbornePlausible(entry.airborneSeconds, effectiveGravity) then
			player:SetAttribute("MovementViolation", "Airborne")
			player:SetAttribute("MovementAirborneSeconds", entry.airborneSeconds)
			player:SetAttribute("MovementSampleSeconds", sampleSeconds)
			player:SetAttribute("MovementVerticalVelocity", verticalVelocity)
			return false
		end
		-- An airborne failure must not replace the position used for recovery.
		entry.lastSampleAt = now
		entry.lastPosition = position
		entry.lastVerticalVelocity = verticalVelocity
		return true
	end

	local function canAward(player: Player): boolean
		local entry, scope, record = participants[player], scopes[player], records[player]
		return entry ~= nil
			and scope ~= nil
			and record ~= nil
			and not entry.rewardForfeited
			and player:GetAttribute("MovementWarning") ~= true
			and isCurrent(player, entry)
	end

	local function award(player: Player, amount: number): boolean
		if not canAward(player) then
			return false
		end
		local scope, record = scopes[player], records[player]
		record.points += amount
		scope.score.Value += amount
		scope.best.Value = math.max(scope.best.Value, record.points)
		player:SetAttribute("RunScore", record.points)
		return true
	end

	local roster = {} :: Roster
	function roster.BeginRun(deck: { string }?)
		table.clear(records)
		contributions.Reset()
		currentTrial = 0
		runDeck = if deck then table.clone(deck) else {}
		for _, player in Players:GetPlayers() do
			resetRunDisplay(player)
			player:SetAttribute("Eliminated", false)
		end
	end

	function roster.StartRound(arenaCFrame: CFrame, trialIndex: number?, ruleId: string?): number
		-- Main ends the previous trial before this atomic admission pass (no yields).
		assert(next(participants) == nil, "EndRound must precede StartRound")
		currentTrial = math.clamp(math.floor(trialIndex or math.max(1, currentTrial)), 1, Config.RuleCount)
		local currentRule = ruleId or runDeck[currentTrial] or ""
		runDeck[currentTrial] = currentRule
		local entered = 0
		for _, player in Players:GetPlayers() do
			player:SetAttribute("InRound", false)
			player:SetAttribute("Eliminated", false)
			player:SetAttribute("MovementWarning", false)
			for index = 1, currentTrial do
				local outcome = player:GetAttribute("TrialOutcome_" .. index)
				if outcome == nil or outcome == "Pending" then
					player:SetAttribute("TrialOutcome_" .. index, "Skipped")
				end
				player:SetAttribute("TrialRule_" .. index, runDeck[index] or "")
			end
			local scope = scopes[player]
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if
				entered < Config.MaxPlayers
				and profiles.IsReady(player)
				and player:GetAttribute("LobbyOnly") ~= true
				and player:GetAttribute("EntryChoiceMade") == true
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
					or {
						contributionToken = contributions.Admit(
							player.UserId,
							player.DisplayName or player.Name
						),
						points = 0,
						survived = 0,
						finale = false,
						completed = false,
						coins = 0,
						xp = 0,
						stars = 0,
						energy = 0,
					}
				participants[player] = {
					character = character,
					humanoid = humanoid,
					root = root,
					alive = true,
					rewarded = false,
					forfeited = false,
					rewardForfeited = false,
					generation = scope.generation,
					movementViolations = 0,
					damaged = false,
					lastHealth = humanoid.MaxHealth,
					trialStartedAt = Workspace:GetServerTimeNow(),
					trialStars = 0,
					damageConnection = nil,
					walkSpeed = humanoid.WalkSpeed,
					jumpPower = humanoid.JumpPower,
					jumpHeight = humanoid.JumpHeight,
					autoRotate = humanoid.AutoRotate,
					lastPosition = root.Position,
					lastSampleAt = os.clock(),
					travelStartedAt = os.clock(),
					travelDistance = 0,
					airborneSeconds = 0,
					lastVerticalVelocity = 0,
					trialIndex = currentTrial,
					ruleId = currentRule,
				}
				root:SetAttribute("TrialGravityScale", nil)
				player:SetAttribute("LastDamageRule", "")
				player:SetAttribute("LastDamageAt", 0)
				player:SetAttribute("EliminationReason", "")
				publishOutcome(player, participants[player], "Playing")
				for _, child in character:GetChildren() do
					if child:IsA("ForceField") then
						child:Destroy()
					end
				end
				humanoid.Health = humanoid.MaxHealth
				local entry = participants[player]
				entry.damageConnection = humanoid.HealthChanged:Connect(function(health)
					-- Remember every health decrease even if regeneration restores full health.
					-- A stale character/trial callback must never taint a later admission.
					if participants[player] == entry and entry.alive and not entry.rewarded then
						if health < entry.lastHealth then
							entry.damaged = true
						end
						entry.lastHealth = health
					end
				end)
				local offset = Vector3.new((entered % 6 - 2.5) * 10, 0, (math.floor(entered / 6) - 0.5) * 20)
				teleport(character, root, arenaCFrame + offset)
				-- Server-authorized teleports start a fresh movement observation window.
				resetMovementWindow(participants[player])
				player:SetAttribute("MovementViolation", "")
				player:SetAttribute("MovementAirborneSeconds", nil)
				player:SetAttribute("MovementSampleSeconds", nil)
				player:SetAttribute("MovementVerticalVelocity", nil)
				player:SetAttribute("InRound", true)
				entered += 1
			end
		end
		return entered
	end

	function roster.EndRound(keepInArena: boolean?)
		local retained: { [Player]: boolean } = {}
		for player, entry in participants do
			stopDamageTracking(entry)
			if
				not entry.rewarded
				and not entry.forfeited
				and player:GetAttribute("TrialOutcome_" .. entry.trialIndex) == "Playing"
			then
				if
					isCurrent(player, entry)
					and entry.root.Position.Y >= 1
					and (entry.rewardForfeited or player:GetAttribute("MovementWarning") == true)
				then
					-- Interrupted cleanup may skip AwardSurvivors; never present a living
					-- warned participant as dead or grant a reward while closing the trial.
					entry.forfeited = true
					entry.rewardForfeited = true
					publishOutcome(player, entry, "Forfeited")
				else
					publishOutcome(player, entry, "Eliminated")
				end
			end
			retained[player] = keepInArena == true
				and isCurrent(player, entry)
				and (entry.rewarded or entry.forfeited)
			restoreMovement(entry)
			entry.root:SetAttribute("TrialGravityScale", nil)
		end
		table.clear(participants)
		for _, player in Players:GetPlayers() do
			player:SetAttribute("InRound", false)
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if
				player:GetAttribute("LobbyOnly") ~= true
				and not retained[player]
				and character
				and humanoid
				and humanoid.Health > 0
				and root
				and root:IsA("BasePart")
			then
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
					local reason: string? = "Movement"
					if RuleMath.isFinite(p.X) and RuleMath.isFinite(p.Y) and RuleMath.isFinite(p.Z) then
						if p.Y < Config.EliminationY then
							reason = "Fall"
						elseif
							p.Y > 110
							or math.abs(p.X) > Config.ArenaHalfSize + 3
							or math.abs(p.Z) > Config.ArenaHalfSize + 3
						then
							reason = "Boundary"
						elseif movementPlausible(player, entry, p) then
							reason = nil
						else
							entry.movementViolations += 1
							if RuleMath.movementResponse(entry.movementViolations) == "Warn" then
								warnMovement(player, entry)
								reason = nil
							end
						end
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

	function roster.ForfeitedAliveCount(): number
		local count = 0
		for player, entry in participants do
			if entry.forfeited and entry.root.Position.Y >= 1 and isCurrent(player, entry) then
				count += 1
			end
		end
		return count
	end

	function roster.AwardSurvivors(ruleId: string): (number, number)
		local awarded = 0
		for player, entry in participants do
			if
				not entry.rewarded
				and not entry.forfeited
				and entry.root.Position.Y >= 1
				and isCurrent(player, entry)
				and (entry.rewardForfeited or player:GetAttribute("MovementWarning") == true)
			then
				-- A warning removes rewards, not survival. Finalize without touching the
				-- personal success ledger; the reactor can still count this living player.
				entry.forfeited = true
				entry.rewardForfeited = true
				stopDamageTracking(entry)
				publishOutcome(player, entry, "Forfeited")
			elseif
				not entry.rewarded
				and not entry.forfeited
				and entry.root.Position.Y >= 1
				and award(player, Config.SurvivorPoints)
			then
				entry.rewarded = true
				local record = records[player]
				record.survived += 1
				if ruleId == "ReactorRush" then
					record.finale = true
				end
				player:SetAttribute("RunSurvived", record.survived)
				contributions.Update(
					player.UserId,
					record.contributionToken,
					record.points,
					record.survived,
					record.energy,
					nil
				)
				captureReward(player, function()
					profiles.AwardSurvival(player)
				end)
				local lastDamageAt = player:GetAttribute("LastDamageAt")
				-- Hazards publish this journal synchronously before TakeDamage. It also
				-- covers damage and healing before deferred HealthChanged callbacks run.
				local journaledDamage = typeof(lastDamageAt) == "number"
					and lastDamageAt >= entry.trialStartedAt
					and player:GetAttribute("LastDamageRule") ~= ""
				if
					not entry.damaged
					and not journaledDamage
					and entry.humanoid.Health >= entry.lastHealth
					and not entry.rewardForfeited
					and player:GetAttribute("MovementWarning") ~= true
					and ruleId == entry.ruleId
				then
					profiles.RecordFlawless(player, ruleId, if entry.trialStars > 0 then "Collected" else nil)
				end
				stopDamageTracking(entry)
				publishOutcome(player, entry, "Survived")
				awarded += 1
			end
		end
		return awarded, roster.ForfeitedAliveCount()
	end

	function roster.AwardStar(player: Player): boolean
		if not canAward(player) or participants[player].rewarded or participants[player].forfeited then
			return false
		end
		local accepted: boolean? = nil
		captureReward(player, function()
			accepted = profiles.AwardStar(player)
		end)
		-- Production grants return an explicit acknowledgement. Legacy server test
		-- adapters may return nil; an explicit refusal never consumes a pickup.
		if accepted == false then
			return false
		end
		award(player, Config.StarPoints)
		participants[player].trialStars += 1
		local record = records[player]
		record.stars += 1
		player:SetAttribute("RunStars", record.stars)
		if participants[player].ruleId == "ReactorRush" then
			record.energy += 1
			player:SetAttribute("RunEnergy", record.energy)
		end
		contributions.Update(
			player.UserId,
			record.contributionToken,
			record.points,
			record.survived,
			record.energy,
			nil
		)
		return true
	end

	function roster.CompleteRun(teamSuccess: boolean, aborted: boolean?): number
		local winners = 0
		for player, record in records do
			local eligible, won = RuleMath.runOutcome(record.survived, record.finale, teamSuccess)
			if not record.completed and player.Parent == Players then
				record.completed = true
				if eligible and not aborted then
					captureReward(player, function()
						profiles.CompleteRun(player, won)
					end)
				end
				local outcome =
					RunPresentation.resultCode(record.survived, record.finale, teamSuccess, aborted)
				player:SetAttribute("RunResult", outcome)
				contributions.Update(
					player.UserId,
					record.contributionToken,
					record.points,
					record.survived,
					record.energy,
					outcome
				)
				-- Last write is the publication barrier for clients rendering this summary.
				player:SetAttribute("ResultReady", true)
				if won and not aborted then
					winners += 1
				end
			end
		end
		return winners
	end

	function roster.Contributions(round: number): string
		return contributions.Encode(round, function(snapshot)
			return HttpService:JSONEncode(snapshot)
		end)
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
		if PhysicsService:IsCollisionGroupRegistered(characterGroup) then
			if createdCharacterGroup then
				PhysicsService:UnregisterCollisionGroup(characterGroup)
			else
				PhysicsService:CollisionGroupSetCollidable(
					characterGroup,
					characterGroup,
					originalSelfCollision
				)
				PhysicsService:CollisionGroupSetCollidable(characterGroup, "Default", originalWorldCollision)
			end
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
