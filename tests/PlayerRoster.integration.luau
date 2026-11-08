--!strict
-- Offline production-roster harness with deterministic service/character adapters.
-- This does not simulate native physics, replication latency or real clients.
-- From project root: lune run tests/PlayerRoster.integration.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local RuleMath = require("../src/server/RuleMath")
local ContributionLedger = require("../src/server/ContributionLedger")
local ContributionView = require("../src/shared/ContributionView")
local RunPresentation = require("../src/shared/RunPresentation")
local checks, scenarios = 0, 0

local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local function signal()
	local callbacks = {}
	return {
		ActiveCount = function()
			local count = 0
			for _, entry in callbacks do
				if entry.active then
					count += 1
				end
			end
			return count
		end,
		Connect = function(_, callback)
			local entry = { active = true, callback = callback }
			table.insert(callbacks, entry)
			return {
				Disconnect = function()
					entry.active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in table.clone(callbacks) do
				if entry.active then
					entry.callback(...)
				end
			end
		end,
	}
end

local function harness(population: number, existingGroup: boolean?)
	local h: any = { now = 0, grounded = true, instances = {}, records = {}, playerList = {}, nextId = 0 }
	local function instance(className: string)
		local values = {}
		local object: any = { Name = className, Parent = nil, Value = 0 }
		function object:IsA(name)
			return name == className or (className == "Part" and name == "BasePart")
		end
		function object:SetAttribute(name, value)
			values[name] = value
		end
		function object:GetAttribute(name)
			return values[name]
		end
		function object:GetChildren()
			local children = {}
			for _, candidate in h.instances do
				if candidate.Parent == self then
					table.insert(children, candidate)
				end
			end
			return children
		end
		function object:FindFirstChild(name)
			for _, child in self:GetChildren() do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function object:FindFirstChildOfClass(name)
			for _, child in self:GetChildren() do
				if child:IsA(name) then
					return child
				end
			end
			return nil
		end
		function object:IsDescendantOf(ancestor)
			local parent = self.Parent
			while parent do
				if parent == ancestor then
					return true
				end
				parent = parent.Parent
			end
			return false
		end
		function object:GetDescendants()
			local descendants = {}
			for _, candidate in h.instances do
				if candidate:IsDescendantOf(self) then
					table.insert(descendants, candidate)
				end
			end
			return descendants
		end
		table.insert(h.instances, object)
		return object
	end
	local players = { PlayerAdded = signal(), PlayerRemoving = signal() }
	function players:GetPlayers()
		return table.clone(h.playerList)
	end
	function h.makeCharacter()
		local character = instance("Model")
		character.pivotOffset = roblox.Vector3.zero
		character.DescendantAdded, character.DescendantRemoving, character.ChildAdded =
			signal(), signal(), signal()
		local root = instance("Part")
		root.Name, root.Parent = "HumanoidRootPart", character
		root.Position, root.Size = roblox.Vector3.zero, roblox.Vector3.new(2, 2, 1)
		root.CFrame = roblox.CFrame.identity
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = roblox.Vector3.zero, roblox.Vector3.zero
		root.CollisionGroup = "Default"
		local humanoid = instance("Humanoid")
		humanoid.Parent, humanoid.Died = character, signal()
		humanoid.HealthChanged = signal()
		humanoid.Health, humanoid.MaxHealth = 100, 100
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 16, 50, 7.2
		humanoid.AutoRotate, humanoid.UseJumpPower = true, true
		humanoid.HipHeight, humanoid.RigType = 2, roblox.Enum.HumanoidRigType.R15
		function character:GetPivot()
			return roblox.CFrame.new(root.Position + self.pivotOffset)
		end
		function character:PivotTo(target)
			root.Position = target.Position - self.pivotOffset
			root.CFrame = roblox.CFrame.new(root.Position)
		end
		return character, root, humanoid
	end
	function h.addPlayer(userId: number?)
		local player = instance("Player")
		h.nextId += 1
		player.UserId = userId or h.nextId
		player.Name = "Player" .. player.UserId
		player.DisplayName = "Display" .. player.UserId
		player.Parent = players
		player.CharacterAdded, player.CharacterRemoving = signal(), signal()
		player:SetAttribute("EntryChoiceMade", true)
		player:SetAttribute("Coins", 0)
		player:SetAttribute("XP", 0)
		local character, root, humanoid = h.makeCharacter()
		player.Character = character
		local record = {
			player = player,
			character = character,
			humanoid = humanoid,
			root = root,
			stars = 0,
			survivals = 0,
			flawless = {},
			cleanActions = {},
			completedRuns = {},
		}
		table.insert(h.records, record)
		table.insert(h.playerList, player)
		players.PlayerAdded:Fire(player)
		return record
	end
	for _ = 1, population do
		h.addPlayer()
	end
	local arena = instance("Model")
	local workspace = { Gravity = 196.2 }
	function workspace:FindFirstChild(name)
		assert(name == "Arena", "Roster only queries its authored arena")
		return arena
	end
	function workspace:GetServerTimeNow()
		return h.now
	end
	function workspace:Raycast(position, direction)
		-- A deterministic floor adapter, not a collision/physics simulation.
		if h.grounded then
			return { Position = position + direction, Normal = roblox.Vector3.yAxis }
		end
		return nil
	end
	local groups = { Default = true, OriginalAccessory = true }
	local matrix = {}
	local function pair(a, b)
		return if a < b then a .. ":" .. b else b .. ":" .. a
	end
	if existingGroup then
		groups.RuleRoomCharacters = true
		matrix[pair("RuleRoomCharacters", "Default")] = false
	end
	local physics = {}
	function physics:IsCollisionGroupRegistered(name)
		return groups[name] == true
	end
	function physics:RegisterCollisionGroup(name)
		groups[name] = true
	end
	function physics:UnregisterCollisionGroup(name)
		groups[name] = nil
	end
	function physics:CollisionGroupsAreCollidable(a, b)
		assert(groups[a] and groups[b], "Collision query uses registered groups")
		return matrix[pair(a, b)] ~= false
	end
	function physics:CollisionGroupSetCollidable(a, b, enabled)
		assert(groups[a] and groups[b], "Collision write uses registered groups")
		matrix[pair(a, b)] = enabled
	end
	h.physics = physics
	function h.addPart(character, group)
		local part = instance("Part")
		part.CollisionGroup, part.Parent = group or "Default", character
		character.DescendantAdded:Fire(part)
		return part
	end
	function h.replaceCharacter(record)
		local oldCharacter, oldRoot, oldHumanoid = record.character, record.root, record.humanoid
		record.player.CharacterRemoving:Fire(oldCharacter)
		record.character, record.root, record.humanoid = h.makeCharacter()
		record.player.Character = record.character
		record.player.CharacterAdded:Fire(record.character)
		return oldCharacter, oldRoot, oldHumanoid
	end
	local config = luau.load(fs.readFile("src/shared/GameConfig.luau"), {
		environment = { Color3 = roblox.Color3 },
	})()
	local shared = {}
	function shared:WaitForChild(name)
		assert(name == "GameConfig" or name == "RunPresentation", name)
		return if name == "GameConfig" then config else RunPresentation
	end
	local storage = { RuleRoomShared = shared }
	function storage:WaitForChild(name)
		assert(name == "RuleRoomShared", name)
		return shared
	end
	local services = {
		Players = players,
		Workspace = workspace,
		ReplicatedStorage = storage,
		PhysicsService = physics,
		HttpService = {
			JSONEncode = function(_, value)
				return serde.encode("json", value)
			end,
		},
	}
	local module = luau.load(fs.readFile("src/server/PlayerRoster.luau"), {
		debugName = "PRODUCTION_PlayerRoster",
		environment = {
			game = {
				GetService = function(_, name)
					assert(services[name], name)
					return services[name]
				end,
			},
			script = { Parent = { RuleMath = RuleMath, ContributionLedger = ContributionLedger } },
			require = function(value)
				return value
			end,
			os = {
				clock = function()
					return h.now
				end,
			},
			task = {
				spawn = function(callback, ...)
					return callback(...)
				end,
			},
			Instance = { new = instance },
			RaycastParams = {
				new = function()
					return {}
				end,
			},
			Enum = roblox.Enum,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
		},
	})()
	local function recordFor(player)
		for _, record in h.records do
			if record.player == player then
				return record
			end
		end
		error("Unknown reward recipient")
	end
	h.roster = module.new(roblox.CFrame.new(0, 4, 158), {
		IsReady = function()
			return true
		end,
		AwardStar = function(player)
			if h.rejectStar then
				return false
			end
			recordFor(player).stars += 1
			player:SetAttribute("Coins", player:GetAttribute("Coins") + 2)
			player:SetAttribute("XP", player:GetAttribute("XP") + 3)
			return if h.legacyStarAcknowledgement then nil else true
		end,
		AwardSurvival = function(player)
			recordFor(player).survivals += 1
			player:SetAttribute("Coins", player:GetAttribute("Coins") + 12)
			player:SetAttribute("XP", player:GetAttribute("XP") + 20)
		end,
		CompleteRun = function(player, won)
			table.insert(recordFor(player).completedRuns, won)
		end,
		RecordFlawless = function(player, ruleId, action)
			local record = recordFor(player)
			record.flawless[ruleId] = (record.flawless[ruleId] or 0) + 1
			if action == "Collected" then
				record.cleanActions[ruleId] = (record.cleanActions[ruleId] or 0) + 1
			else
				assert(action == nil, "Roster only emits the validated optional action literal")
			end
			return true
		end,
	})
	function h.start(ruleId: string, trial: number?)
		return h.roster.StartRound(roblox.CFrame.new(0, 5, 0), trial or 1, ruleId)
	end
	function h.sample(seconds: number)
		h.now += seconds
		h.roster.CheckBoundaries()
	end
	function h.airborneSamples(count: number)
		h.grounded = false
		for _ = 1, count do
			h.sample(0.125)
		end
	end
	function h.destroy()
		h.roster.Destroy()
	end
	function h.health(record, value: number, deferred: boolean?)
		record.humanoid.Health = value
		if not deferred then
			record.humanoid.HealthChanged:Fire(value)
		end
	end
	function h.remove(record)
		players.PlayerRemoving:Fire(record.player)
		record.player.Parent = nil
		local index = table.find(h.playerList, record.player)
		if index then
			table.remove(h.playerList, index)
		end
	end
	return h
end

local function finishFromMain(h, completed: boolean, teamGoal: boolean): boolean
	-- Execute the production completion branch, including its multiple-return handling.
	local source = fs.readFile("src/server/Main.server.luau"):gsub("\r\n", "\n")
	local completion = source:match("(local awarded[^\n]*\n.-)\n\t\t\tworld%.Restore%(%)")
	assert(completion, "Main must expose the trial completion branch")
	local finaleSuccess = teamGoal
	local state = {
		GetAttribute = function(_, name)
			assert(name == "FinaleSuccess", name)
			return finaleSuccess
		end,
		SetAttribute = function(_, name, value)
			assert(name == "FinaleSuccess", name)
			finaleSuccess = value
		end,
	}
	luau.load(completion, {
		debugName = "PRODUCTION_Main_TrialCompletion",
		environment = { roster = h.roster, completed = completed, ruleId = "ReactorRush", state = state },
	})()
	return finaleSuccess
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("SafeColor")
	r.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	local awarded, forfeitedAlive = h.roster.AwardSurvivors("SafeColor")
	expect(r.player:GetAttribute("TrialOutcome_1") == "Forfeited", "A warned survivor publishes Forfeited")
	expect(awarded == 0 and forfeitedAlive == 1, "Forfeited survival is counted separately from awards")
	expect(
		r.player:GetAttribute("LastTrialOutcome") == "Forfeited"
			and r.player:GetAttribute("LastTrialRule") == "SafeColor",
		"The latest trial display publishes the same forfeited outcome"
	)
	expect(
		r.survivals == 0
			and r.player:GetAttribute("RunSurvived") == 0
			and r.player:GetAttribute("RunScore") == 0
			and r.player:GetAttribute("Coins") == 0
			and r.player:GetAttribute("XP") == 0
			and next(r.flawless) == nil,
		"Forfeited survival grants no survival, points, currency, XP or mastery"
	)
	h.roster.EndRound()
	expect(r.player:GetAttribute("TrialOutcome_1") == "Forfeited", "EndRound preserves Forfeited")
	expect(
		h.roster.CompleteRun(true) == 0 and r.player:GetAttribute("RunResult") == "NoSurvival",
		"Forfeited participation does not increment the internal survived record"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(2)
	local a, b = h.records[1], h.records[2]
	for index = 1, 4 do
		h.start("SafeColor", index)
		h.roster.AwardSurvivors("SafeColor")
		h.roster.EndRound()
	end
	h.start("ReactorRush", 6)
	h.health(b, 0)
	b.humanoid.Died:Fire()
	a.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	local awarded, forfeitedAlive = h.roster.AwardSurvivors("ReactorRush")
	expect(awarded == 0 and forfeitedAlive == 1, "The only living finalist is counted despite forfeiture")
	expect(finishFromMain(h, true, true), "A completed charged reactor counts the forfeited survivor in Main")
	expect(
		not finishFromMain(h, true, false),
		"Living forfeited players cannot replace the reactor charge goal"
	)
	expect(
		not finishFromMain(h, false, true),
		"An interrupted finale cannot succeed through forfeited survivors"
	)
	local repeatedAwards, repeatedForfeited = h.roster.AwardSurvivors("ReactorRush")
	expect(
		repeatedAwards == 0 and repeatedForfeited == 1 and a.survivals == 4,
		"Repeated completion counts living forfeited players without duplicate rewards"
	)
	h.roster.EndRound()
	expect(
		a.player:GetAttribute("TrialOutcome_6") == "Forfeited"
			and b.player:GetAttribute("TrialOutcome_6") == "Eliminated",
		"Finale results distinguish a living forfeited player from an eliminated teammate"
	)
	expect(
		h.roster.CompleteRun(true) == 0 and a.player:GetAttribute("RunResult") == "FinaleMissed",
		"Four earlier survivals plus forfeited finale never set the personal finale win"
	)
	expect(a.player:GetAttribute("RunSurvived") == 4, "The forfeited finale does not add a survived trial")
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("Spinner")
	r.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	h.roster.EndRound()
	expect(
		r.player:GetAttribute("TrialOutcome_1") == "Forfeited"
			and r.player:GetAttribute("LastTrialOutcome") == "Forfeited",
		"Ending a warned survivor's trial without an award still publishes Forfeited"
	)
	expect(r.survivals == 0 and r.player:GetAttribute("RunSurvived") == 0, "EndRound grants no survival")
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	r.character.pivotOffset = roblox.Vector3.new(3, 1, 2)
	h.roster.BeginRun()
	expect(h.start("ReactorRush") == 1, "A ready player enters the trial")
	r.root.Position += roblox.Vector3.new(5, 0, 0)
	h.sample(0.1)
	local anchor = r.root.Position
	r.root.Position += roblox.Vector3.new(40, 0, 0)
	r.root.AssemblyLinearVelocity = roblox.Vector3.new(120, 15, 0)
	r.root.AssemblyAngularVelocity = roblox.Vector3.new(0, 20, 0)
	h.sample(0.1)
	expect(r.root.Position == anchor, "First Travel rewinds to the latest accepted trial sample")
	expect(r.humanoid.Health == 100 and h.roster.AliveCount() == 1, "First Travel does not kill or eliminate")
	expect(
		r.player:GetAttribute("InRound") == true and r.player:GetAttribute("Eliminated") == false,
		"Warned player remains admitted"
	)
	expect(
		r.player:GetAttribute("MovementWarning") == true
			and r.player:GetAttribute("MovementViolation") == "Travel",
		"Travel publishes the warning and diagnosis"
	)
	expect(
		r.root.AssemblyLinearVelocity == roblox.Vector3.zero
			and r.root.AssemblyAngularVelocity == roblox.Vector3.zero,
		"Rewind clears both velocities"
	)
	expect(not h.roster.AwardStar(r.player), "Warning forfeits collectible rewards for the trial")
	expect(h.roster.AwardSurvivors("ReactorRush") == 0, "Warning forfeits survival rewards for the trial")
	expect(
		r.stars == 0 and r.survivals == 0 and r.player:GetAttribute("RunScore") == 0,
		"Forfeiture makes no profile or score grant"
	)
	expect(next(r.flawless) == nil, "Movement warning forfeits mastery even without health damage")
	r.player:SetAttribute("MovementWarning", false)
	expect(
		h.roster.AwardSurvivors("ReactorRush") == 0 and next(r.flawless) == nil,
		"Clearing presentation warning cannot undo the trial's reward forfeiture"
	)
	expect(
		r.player:GetAttribute("RunEnergy") == 0 and r.player:GetAttribute("RunStars") == 0,
		"Rejected pickup grants no energy or stars"
	)
	h.sample(0.1)
	expect(h.roster.AliveCount() == 1, "The rewind itself does not cause a repeat violation")
	r.root.Position += roblox.Vector3.new(20, 0, 0)
	h.sample(0.1)
	expect(h.roster.AliveCount() == 1, "A fresh travel window permits ordinary movement after rewind")
	r.root.Position += roblox.Vector3.new(20, 0, 0)
	h.sample(0.1)
	expect(
		h.roster.AliveCount() == 0 and r.humanoid.Health == 0,
		"Second Travel eliminates in the same trial"
	)
	expect(
		r.player:GetAttribute("EliminationReason") == "Movement",
		"Repeat movement retains its explicit elimination reason"
	)
	expect(r.player:GetAttribute("MovementWarning") == false, "Elimination clears the warning")
	local awarded, forfeitedAlive = h.roster.AwardSurvivors("ReactorRush")
	expect(
		awarded == 0 and forfeitedAlive == 0 and r.player:GetAttribute("TrialOutcome_1") == "Eliminated",
		"A second movement violation eliminates and removes forfeited survivor eligibility"
	)
	h.roster.EndRound()
	expect(
		r.player:GetAttribute("TrialOutcome_1") == "Eliminated",
		"EndRound preserves repeat-violation elimination"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("LowGravity")
	r.root.Position += roblox.Vector3.new(0, 5, 0)
	h.airborneSamples(32)
	expect(
		r.player:GetAttribute("MovementWarning") ~= true,
		"Four seconds of unsupported observation remain within allowance"
	)
	local anchor = r.root.Position
	r.root.Position += roblox.Vector3.new(0, 2, 0)
	h.sample(0.125)
	expect(
		r.player:GetAttribute("MovementViolation") == "Airborne"
			and r.player:GetAttribute("MovementWarning") == true,
		"First excessive unsupported sample warns"
	)
	expect(
		r.root.Position == anchor and r.humanoid.Health == 100,
		"Airborne rewind uses the preceding fully plausible sample"
	)
	h.airborneSamples(32)
	expect(h.roster.AliveCount() == 1, "Rewind resets continuous airborne evidence and sample time")
	h.sample(0.125)
	expect(
		h.roster.AliveCount() == 0 and r.player:GetAttribute("EliminationReason") == "Movement",
		"A second Airborne violation eliminates"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("LaserSweep")
	r.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	h.airborneSamples(33)
	expect(
		h.roster.AliveCount() == 0 and r.humanoid.Health == 0,
		"Travel followed by Airborne shares one per-trial violation budget"
	)
	expect(r.player:GetAttribute("MovementWarning") == false, "Mixed-repeat elimination clears warning")
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("ReactorRush")
	r.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	h.roster.EndRound()
	expect(h.start("ReactorRush", 2) == 1, "A warned survivor can enter the next trial")
	expect(r.player:GetAttribute("MovementWarning") == false, "StartRound resets the previous trial warning")
	expect(
		h.roster.AwardStar(r.player) and r.player:GetAttribute("RunEnergy") == 1,
		"Next trial restores pickup and personal energy eligibility"
	)
	expect(
		h.roster.AwardSurvivors("ReactorRush") == 1 and r.survivals == 1,
		"Next trial restores survival eligibility"
	)
	expect(
		h.roster.AwardSurvivors("ReactorRush") == 0 and r.survivals == 1,
		"Survival rewards remain guarded against duplication"
	)
	r.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	expect(
		r.humanoid.Health == 100 and r.player:GetAttribute("MovementWarning") == true,
		"First violation in a later trial warns again"
	)
	h.destroy()
	scenarios += 1
end

for _, case in
	{
		{ position = roblox.Vector3.new(0, -16, 0), reason = "Fall" },
		{ position = roblox.Vector3.new(46, 5, 0), reason = "Boundary" },
		{ position = roblox.Vector3.new(0, 111, 0), reason = "Boundary" },
		{ position = roblox.Vector3.new(0 / 0, 5, 0), reason = "Movement" },
		{ position = roblox.Vector3.new(0, 5, math.huge), reason = "Movement" },
	}
do
	local h = harness(1)
	local r = h.records[1]
	h.start("ReactorRush")
	r.root.Position = case.position
	h.sample(0.1)
	expect(
		h.roster.AliveCount() == 0 and r.humanoid.Health == 0,
		"Hard invalid position eliminates immediately: " .. case.reason
	)
	expect(
		r.player:GetAttribute("EliminationReason") == case.reason,
		"Hard invalid position preserves its reason"
	)
	expect(
		r.player:GetAttribute("MovementWarning") == false,
		"Hard invalid position does not use the warning allowance"
	)
	expect(
		not h.roster.AwardStar(r.player) and r.player:GetAttribute("RunEnergy") == 0,
		"Eliminated player cannot collect energy"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(2)
	local a, b = h.records[1], h.records[2]
	expect(
		a.player:GetAttribute("RunEnergy") == 0 and b.player:GetAttribute("RunEnergy") == 0,
		"Adding each player initializes personal energy"
	)
	expect(not h.roster.AwardStar(a.player) and a.stars == 0, "Lobby-only reward requests are rejected")
	h.roster.BeginRun()
	h.start("LowGravity")
	expect(h.roster.AwardStar(a.player) and a.stars == 1, "An ordinary trial still grants real stars")
	expect(a.player:GetAttribute("RunEnergy") == 0, "Stars outside ReactorRush do not count as energy")
	h.roster.EndRound()
	h.start("ReactorRush", 6)
	expect(
		h.roster.AwardStar(a.player) and h.roster.AwardStar(a.player),
		"Two successful finale pickups grant two rewards"
	)
	expect(
		a.player:GetAttribute("RunEnergy") == 2 and a.player:GetAttribute("RunStars") == 3,
		"Personal energy counts only successful finale pickups"
	)
	expect(b.player:GetAttribute("RunEnergy") == 0, "One player's energy is not shared with teammates")
	expect(
		h.roster.AwardStar(b.player) and b.player:GetAttribute("RunEnergy") == 1,
		"A teammate has an independent energy ledger"
	)
	local newcomer = h.addPlayer()
	expect(newcomer.player:GetAttribute("RunEnergy") == 0, "Joining mid-run initializes energy independently")
	expect(
		not h.roster.AwardStar(newcomer.player) and newcomer.stars == 0,
		"A mid-trial newcomer cannot collect without admission"
	)
	h.roster.EndRound()
	expect(
		not h.roster.AwardStar(a.player) and a.player:GetAttribute("RunEnergy") == 2,
		"Out-of-trial request preserves the earned energy total"
	)
	h.roster.BeginRun()
	expect(
		a.player:GetAttribute("RunEnergy") == 0 and b.player:GetAttribute("RunEnergy") == 0,
		"BeginRun resets every player's energy display"
	)
	h.start("ReactorRush")
	expect(
		h.roster.AwardStar(a.player) and a.player:GetAttribute("RunEnergy") == 1,
		"BeginRun also resets the underlying energy ledger"
	)
	expect(
		a.stars == 4 and a.player:GetAttribute("RunStars") == 1,
		"Run-local stars reset while profile rewards remain earned"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	expect(r.player:GetAttribute("NewRecord") == "", "New players have an empty record announcement")
	r.player:SetAttribute("NewRecord", "Score,Survived")
	h.roster.BeginRun()
	expect(r.player:GetAttribute("NewRecord") == "", "BeginRun clears the prior record announcement")
	r.player:SetAttribute("LastDamageAt", 500)
	r.player:SetAttribute("LastDamageRule", "MeteorRain")
	h.start("SafeColor")
	expect(r.humanoid.HealthChanged:ActiveCount() == 1, "Admission owns one health observer")
	expect(h.roster.AwardSurvivors("SafeColor") == 1, "A clean participant earns survival")
	expect(r.flawless.SafeColor == 1, "Clean survival records mastery for its current rule")
	expect(r.humanoid.HealthChanged:ActiveCount() == 0, "Completed award releases the health observer")
	expect(
		h.roster.AwardSurvivors("SafeColor") == 0 and r.flawless.SafeColor == 1,
		"Repeated survival award cannot duplicate mastery"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("Spinner")
	h.health(r, 65)
	h.health(r, 100)
	expect(h.roster.AwardSurvivors("Spinner") == 1, "Healed survivor still earns ordinary survival")
	expect(next(r.flawless) == nil, "Health loss is remembered after full regeneration without a journal")
	h.roster.EndRound()
	h.health(r, 50)
	h.start("LaserSweep", 2)
	expect(r.humanoid.Health == 100, "Next trial restores health before observing damage")
	expect(
		h.roster.AwardSurvivors("LaserSweep") == 1 and r.flawless.LaserSweep == 1,
		"Earlier-trial and intermission damage cannot taint a later clean trial"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("MeteorRain")
	-- The hazard journal is synchronous even when health events have not been dispatched.
	r.player:SetAttribute("LastDamageAt", h.now)
	r.player:SetAttribute("LastDamageRule", "MeteorRain")
	h.health(r, 65, true)
	h.health(r, 100, true)
	expect(h.roster.AwardSurvivors("MeteorRain") == 1, "Deferred health events do not erase survival")
	expect(next(r.flawless) == nil, "Current-trial hazard journal rejects a healed hit at time zero")
	h.roster.EndRound()
	h.start("LavaRise", 2)
	h.health(r, 99, true)
	expect(h.roster.AwardSurvivors("LavaRise") == 1, "Unjournaled pending health event keeps normal rewards")
	expect(next(r.flawless) == nil, "Current health also rejects a damage event awaiting dispatch")
	h.destroy()
	scenarios += 1
end

for _, termination in { "Death", "Reset", "Leave", "EndRound", "Destroy" } do
	local h = harness(1)
	local r = h.records[1]
	h.start("SafeZone")
	if termination == "Death" then
		h.health(r, 0)
		r.humanoid.Died:Fire()
	elseif termination == "Reset" then
		r.player.CharacterRemoving:Fire(r.character)
	elseif termination == "Leave" then
		h.remove(r)
	elseif termination == "EndRound" then
		h.roster.EndRound()
	else
		h.destroy()
	end
	expect(r.humanoid.HealthChanged:ActiveCount() == 0, "Trial observer disconnects on " .. termination)
	expect(
		h.roster.AwardSurvivors("SafeZone") == 0 and next(r.flawless) == nil,
		"No mastery after " .. termination
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("SafeZone")
	local newcomer = h.addPlayer()
	h.roster.AwardSurvivors("SafeColor")
	expect(next(r.flawless) == nil, "A mismatched completion rule cannot create mastery")
	expect(next(newcomer.flawless) == nil, "A late spectator cannot receive mastery")
	h.destroy()
	scenarios += 1
end

local function prepareFinale(h)
	h.roster.BeginRun()
	for index, ruleId in { "SafeColor", "LaserSweep", "LowGravity", "SafeZone" } do
		h.start(ruleId, index)
		h.roster.AwardSurvivors(ruleId)
		h.roster.EndRound()
	end
	h.start("ReactorRush", 6)
end

do
	local h = harness(3)
	local normal, forfeited, dead = h.records[1], h.records[2], h.records[3]
	prepareFinale(h)
	local beforeCoins = forfeited.player:GetAttribute("Coins")
	local beforeXP = forfeited.player:GetAttribute("XP")
	local beforeScore = forfeited.player:GetAttribute("RunScore")
	forfeited.root.Position += roblox.Vector3.new(40, 0, 0)
	h.sample(0.1)
	h.health(dead, 0)
	dead.humanoid.Died:Fire()
	local awarded, livingForfeited = h.roster.AwardSurvivors("ReactorRush")
	expect(
		forfeited.player:GetAttribute("TrialOutcome_6") == "Forfeited",
		"A living warned participant finishes as Forfeited, not Eliminated"
	)
	expect(
		awarded == 1 and livingForfeited == 1,
		"Mixed finale reports rewarded and forfeited survivors separately"
	)
	expect(
		forfeited.player:GetAttribute("LastTrialOutcome") == "Forfeited"
			and forfeited.player:GetAttribute("Eliminated") == false,
		"Forfeiture publishes its own outcome without pretending the participant died"
	)
	expect(
		forfeited.player:GetAttribute("Coins") == beforeCoins
			and forfeited.player:GetAttribute("XP") == beforeXP
			and forfeited.player:GetAttribute("RunScore") == beforeScore
			and forfeited.player:GetAttribute("RunSurvived") == 4
			and forfeited.survivals == 4
			and forfeited.flawless.ReactorRush == nil,
		"Forfeited finale grants no points, survival, currency, XP or mastery"
	)
	expect(
		normal.player:GetAttribute("TrialOutcome_6") == "Survived"
			and dead.player:GetAttribute("TrialOutcome_6") == "Eliminated",
		"Ordinary success and death remain distinct from Forfeited"
	)
	forfeited.player:SetAttribute("MovementWarning", false)
	local repeated, repeatedForfeited = h.roster.AwardSurvivors("ReactorRush")
	expect(
		repeated == 0 and repeatedForfeited == 1 and h.roster.ForfeitedAliveCount() == 1,
		"Repeated finalization keeps current forfeited count without duplicating awards"
	)
	expect(
		not h.roster.AwardStar(forfeited.player) and forfeited.stars == 0,
		"Clearing the warning cannot re-enable rewards after finalized forfeiture"
	)
	local position = forfeited.root.Position
	h.roster.EndRound(true)
	expect(
		forfeited.player:GetAttribute("TrialOutcome_6") == "Forfeited" and forfeited.root.Position == position,
		"EndRound keeps a living forfeited participant on the arena and preserves the outcome"
	)
	expect(h.roster.ForfeitedAliveCount() == 0, "EndRound clears the live finalized roster")
	expect(h.roster.CompleteRun(true) == 1, "Only the ordinary eligible finalist receives a personal win")
	expect(
		#normal.completedRuns == 1
			and normal.completedRuns[1] == true
			and #forfeited.completedRuns == 1
			and forfeited.completedRuns[1] == false
			and forfeited.player:GetAttribute("RunResult") == "FinaleMissed",
		"Forfeited finalist contributes to team success without setting the personal finale flag"
	)
	h.roster.CompleteRun(true)
	expect(
		#forfeited.completedRuns == 1,
		"Repeated CompleteRun cannot duplicate a forfeited finalist's run reward"
	)
	h.destroy()
	scenarios += 1
end

for _, completed in { true, false } do
	local h = harness(2)
	prepareFinale(h)
	for _, record in h.records do
		record.root.Position += roblox.Vector3.new(40, 0, 0)
	end
	h.sample(0.1)
	local awarded, forfeited = h.roster.AwardSurvivors("ReactorRush")
	expect(
		awarded == 0 and forfeited == 2,
		"An all-forfeited finale has zero personal awards and two living finalists"
	)
	local teamSuccess = completed and (awarded > 0 or h.roster.ForfeitedAliveCount() > 0)
	expect(teamSuccess == completed, "Living forfeited players count only when reactor completion is true")
	expect(h.roster.CompleteRun(teamSuccess) == 0, "All-forfeited finale never awards a personal win")
	for _, record in h.records do
		expect(
			#record.completedRuns == 1
				and record.completedRuns[1] == false
				and record.player:GetAttribute("RunSurvived") == 4
				and record.flawless.ReactorRush == nil,
			"A forfeited finalist keeps earlier progress without finale survival or mastery"
		)
	end
	h.destroy()
	scenarios += 1
end

do
	local h = harness(2)
	h.start("ReactorRush", 6)
	for _, record in h.records do
		h.health(record, 0)
		record.humanoid.Died:Fire()
	end
	local awarded, forfeited = h.roster.AwardSurvivors("ReactorRush")
	expect(awarded == 0 and forfeited == 0, "Dead participants cannot be finalized as living forfeitures")
	expect(
		not (true and (awarded > 0 or h.roster.ForfeitedAliveCount() > 0)),
		"Full charge without anyone alive is not success"
	)
	expect(h.roster.CompleteRun(false) == 0, "All-dead finale has no winners")
	h.destroy()
	scenarios += 1
end

for _, termination in { "Death", "Reset", "Leave", "EndRound", "NextTrial", "Destroy" } do
	local h = harness(1)
	local r = h.records[1]
	h.start("SafeZone")
	r.player:SetAttribute("MovementWarning", true)
	local awarded, forfeited = h.roster.AwardSurvivors("SafeZone")
	expect(
		awarded == 0 and forfeited == 1,
		"A current MovementWarning alone cannot slip through the award gate"
	)
	r.root.Position = roblox.Vector3.new(r.root.Position.X, 0.5, r.root.Position.Z)
	expect(
		h.roster.ForfeitedAliveCount() == 0,
		"Finalized participants below the survival floor do not count"
	)
	r.root.Position = roblox.Vector3.new(r.root.Position.X, 5, r.root.Position.Z)
	expect(
		h.roster.ForfeitedAliveCount() == 1,
		"The forfeited count is a read-only view of current living participants"
	)
	if termination == "Death" then
		h.health(r, 0)
		r.humanoid.Died:Fire()
	elseif termination == "Reset" then
		r.player.CharacterRemoving:Fire(r.character)
	elseif termination == "Leave" then
		h.remove(r)
	elseif termination == "EndRound" or termination == "NextTrial" then
		h.roster.EndRound()
		if termination == "NextTrial" then
			h.start("SafeColor", 2)
			local nextAward, nextForfeit = h.roster.AwardSurvivors("SafeColor")
			expect(
				nextAward == 1 and nextForfeit == 0 and r.flawless.SafeColor == 1,
				"The next trial resets forfeiture and restores ordinary mastery eligibility"
			)
		end
	else
		h.destroy()
	end
	expect(h.roster.ForfeitedAliveCount() == 0, "No stale forfeited participant after " .. termination)
	h.destroy()
	scenarios += 1
end

-- Capacity uses player adapters, not native clients or load/performance evidence.
for _, population in { 0, 1, 2, 12, 13 } do
	local h = harness(population)
	h.roster.BeginRun({ "SafeColor", "Spinner" })
	expect(h.start("SafeColor") == math.min(population, 12), "Admission honors configured twelve-player cap")
	expect(h.roster.AliveCount() == math.min(population, 12), "Only admitted adapters count as alive")
	local awarded = h.roster.AwardSurvivors("SafeColor")
	expect(awarded == math.min(population, 12), "Exactly admitted adapters receive survival rewards")
	expect(h.roster.AwardSurvivors("SafeColor") == 0, "Repeated cap-wide award is idempotent")
	if population == 13 then
		local waiting = h.records[13]
		expect(
			waiting.player:GetAttribute("InRound") == false and waiting.survivals == 0,
			"Overflow stays outside rewards"
		)
		expect(not h.roster.AwardStar(waiting.player), "Overflow cannot collect an admitted player's star")
		h.remove(h.records[1])
		h.roster.EndRound()
		expect(h.start("Spinner", 2) == 12, "Vacated slot is available at next trial boundary")
		expect(waiting.player:GetAttribute("InRound") == true, "Previously waiting adapter enters next trial")
	end
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	h.roster.BeginRun({ "SafeColor", "Spinner" })
	h.start("SafeColor")
	local late = h.addPlayer()
	expect(
		late.player:GetAttribute("InRound") == false,
		"Late arrival remains a spectator during active hazard"
	)
	expect(not h.roster.AwardStar(late.player), "Late arrival cannot earn current-trial pickups")
	h.roster.EndRound()
	expect(h.start("Spinner", 2) == 2, "Late arrival enters on normal boundary")
	h.destroy()
	scenarios += 1
end

for _, existingGroup in { false, true } do
	local h = harness(2, existingGroup)
	local a, b = h.records[1], h.records[2]
	expect(
		not h.physics:CollisionGroupsAreCollidable("RuleRoomCharacters", "RuleRoomCharacters"),
		"Characters do not collide with each other"
	)
	expect(
		h.physics:CollisionGroupsAreCollidable("RuleRoomCharacters", "Default"),
		"Characters still collide with arena geometry"
	)
	expect(a.root.CollisionGroup == "RuleRoomCharacters", "Existing root joins character collision group")
	local part = h.addPart(a.character, "OriginalAccessory")
	expect(part.CollisionGroup == "RuleRoomCharacters", "Late accessory joins character group")
	-- A deferred removal signal may arrive after the new owner's added signal.
	part.Parent = b.character
	b.character.DescendantAdded:Fire(part)
	a.character.DescendantRemoving:Fire(part)
	expect(part.CollisionGroup == "RuleRoomCharacters", "Stale removal cannot reset a transferred accessory")
	h.remove(a)
	expect(a.root.CollisionGroup == "Default", "Leaving restores original root group")
	expect(
		part.CollisionGroup == "RuleRoomCharacters",
		"Previous owner leaving cannot reset new owner's part"
	)
	local removed = h.addPart(b.character, "OriginalAccessory")
	removed.Parent = nil
	b.character.DescendantRemoving:Fire(removed)
	expect(
		removed.CollisionGroup == "OriginalAccessory",
		"Unparented accessories restore their original group"
	)
	local externallyChanged = h.addPart(b.character)
	externallyChanged.CollisionGroup = "OriginalAccessory"
	h.destroy()
	expect(
		part.CollisionGroup == "OriginalAccessory",
		"Transfer preserves original group through final cleanup"
	)
	expect(b.root.CollisionGroup == "Default", "Destroy restores all roots")
	expect(
		externallyChanged.CollisionGroup == "OriginalAccessory",
		"Cleanup preserves another system's newer group"
	)
	if existingGroup then
		expect(h.physics:IsCollisionGroupRegistered("RuleRoomCharacters"), "Pre-existing group is retained")
		expect(
			h.physics:CollisionGroupsAreCollidable("RuleRoomCharacters", "RuleRoomCharacters"),
			"Pre-existing self collision is restored"
		)
		expect(
			not h.physics:CollisionGroupsAreCollidable("RuleRoomCharacters", "Default"),
			"Pre-existing world collision is restored"
		)
	else
		expect(
			not h.physics:IsCollisionGroupRegistered("RuleRoomCharacters"),
			"Owned group is removed on shutdown"
		)
	end
	expect(
		b.character.DescendantAdded.ActiveCount() == 0 and b.character.DescendantRemoving.ActiveCount() == 0,
		"Character collision listeners disconnect"
	)
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.roster.BeginRun({ "SafeColor", "Spinner" })
	h.start("SafeColor")
	local oldCharacter, oldRoot, oldHumanoid = h.replaceCharacter(r)
	expect(
		r.player:GetAttribute("InRound") == false and h.roster.AliveCount() == 0,
		"Respawn cannot re-enter the current hazard"
	)
	expect(
		oldRoot.CollisionGroup == "Default" and r.root.CollisionGroup == "RuleRoomCharacters",
		"Respawn moves collision ownership to the new character"
	)
	expect(
		oldCharacter.DescendantAdded.ActiveCount() == 0 and oldHumanoid.Died.ActiveCount() == 0,
		"Old character listeners are disconnected"
	)
	expect(not h.roster.AwardStar(r.player), "Replacement character has no old pickup eligibility")
	h.roster.EndRound()
	expect(h.start("Spinner", 2) == 1, "Replacement is admitted at the next boundary")
	oldHumanoid.Died:Fire()
	expect(
		r.player:GetAttribute("InRound") == true and h.roster.AliveCount() == 1,
		"Stale death cannot eliminate the new character"
	)
	h.destroy()
	expect(
		r.root.CollisionGroup == "Default" and r.humanoid.Died.ActiveCount() == 0,
		"Destroy restores and disconnects replacement"
	)
	expect(
		r.player.CharacterAdded.ActiveCount() == 0 and r.player.CharacterRemoving.ActiveCount() == 0,
		"Player character observers disconnect"
	)
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.roster.BeginRun()
	for index, ruleId in { "LowGravity", "RedLight", "ReactorRush" } do
		h.start(ruleId, index)
		expect(h.roster.AwardStar(r.player), "An admitted participant can perform a server-confirmed pickup")
		expect(h.roster.AwardSurvivors(ruleId) == 1, "Clean collector trial finishes successfully")
		expect(
			r.flawless[ruleId] == 1 and r.cleanActions[ruleId] == 1,
			"Roster passes clean pickup proof while retaining Flawless statistics"
		)
		expect(
			h.roster.AwardSurvivors(ruleId) == 0 and r.cleanActions[ruleId] == 1,
			"Repeated survivor processing cannot duplicate clean mastery proof"
		)
		expect(
			not h.roster.AwardStar(r.player),
			"Finalized trial cannot accept a late pickup after its mastery decision"
		)
		h.roster.EndRound()
	end
	expect(
		r.player:GetAttribute("RunStars") == 3 and r.player:GetAttribute("RunEnergy") == 1,
		"Run action counters reflect accepted pickups and reactor contribution"
	)
	h.start("LowGravity", 4)
	h.roster.AwardSurvivors("LowGravity")
	expect(
		r.flawless.LowGravity == 2 and r.cleanActions.LowGravity == 1,
		"Earlier trial stars cannot qualify a new passive trial"
	)
	h.roster.EndRound()
	r.player:SetAttribute("Mastery_FirstRun", 1)
	r.player:SetAttribute("EquippedTitle", "FirstRun")
	h.roster.BeginRun()
	h.start("ReactorRush", 1)
	h.roster.AwardSurvivors("ReactorRush")
	expect(
		r.cleanActions.ReactorRush == 1 and r.player:GetAttribute("RunStars") == 0,
		"New run clears action proof along with run stars"
	)
	expect(
		r.player:GetAttribute("Mastery_FirstRun") == 1
			and r.player:GetAttribute("EquippedTitle") == "FirstRun",
		"Run display reset preserves permanent mastery and title"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local r = h.records[1]
	h.start("ReactorRush")
	local score, coins, xp =
		r.player:GetAttribute("RunScore"), r.player:GetAttribute("Coins"), r.player:GetAttribute("XP")
	h.rejectStar = true
	expect(
		not h.roster.AwardStar(r.player),
		"Profile refusal is returned to the hazard so it can retain the pickup"
	)
	expect(
		r.stars == 0
			and r.player:GetAttribute("RunStars") == 0
			and r.player:GetAttribute("RunEnergy") == 0
			and r.player:GetAttribute("RunScore") == score
			and r.player:GetAttribute("Coins") == coins
			and r.player:GetAttribute("XP") == xp,
		"Rejected grant cannot mint score, currency, run stars or reactor contribution"
	)
	h.roster.AwardSurvivors("ReactorRush")
	expect(
		r.flawless.ReactorRush == 1 and r.cleanActions.ReactorRush == nil,
		"Refused pickup cannot become clean-action mastery"
	)
	h.roster.EndRound()
	h.start("ReactorRush", 2)
	h.rejectStar = false
	expect(h.roster.AwardStar(r.player), "A later accepted grant recovers normally")
	h.roster.AwardSurvivors("ReactorRush")
	expect(
		r.cleanActions.ReactorRush == 1 and r.player:GetAttribute("RunEnergy") == 1,
		"Only the successful recovery pickup supplies action proof"
	)
	h.roster.EndRound()
	h.start("LowGravity", 3)
	h.legacyStarAcknowledgement = true
	expect(h.roster.AwardStar(r.player), "Legacy trusted server adapters with no return remain compatible")
	h.destroy()
	scenarios += 1
end

for _, disqualifier in { "Damage", "Warning", "Reset", "Death" } do
	local h = harness(1)
	local r = h.records[1]
	h.start("LowGravity")
	expect(h.roster.AwardStar(r.player), "Action occurred before " .. disqualifier)
	if disqualifier == "Damage" then
		h.health(r, 70)
		h.health(r, 100)
	elseif disqualifier == "Warning" then
		r.player:SetAttribute("MovementWarning", true)
	elseif disqualifier == "Reset" then
		h.replaceCharacter(r)
	else
		h.health(r, 0)
		r.humanoid.Died:Fire()
	end
	h.roster.AwardSurvivors("LowGravity")
	expect(
		next(r.cleanActions) == nil and next(r.flawless) == nil,
		"Accepted pickup cannot bypass clean survival after " .. disqualifier
	)
	if disqualifier == "Reset" then
		h.roster.EndRound()
		h.start("LowGravity", 2)
		h.roster.AwardSurvivors("LowGravity")
		expect(
			r.flawless.LowGravity == 1 and next(r.cleanActions) == nil,
			"Replacement character's clean trial cannot reuse the removed character's pickup"
		)
	end
	h.destroy()
	scenarios += 1
end

local function contributionSnapshot(h, round: number)
	local snapshot = serde.decode("json", h.roster.Contributions(round))
	local clientRows = ContributionView.read(snapshot, round, round)
	expect(
		clientRows ~= nil and #clientRows == #snapshot.Players,
		"Production roster JSON is accepted by the actual shared client validator"
	)
	return snapshot
end

do
	local h = harness(2)
	local first, second = h.records[1], h.records[2]
	local spectator = h.addPlayer()
	spectator.player:SetAttribute("LobbyOnly", true)
	h.roster.BeginRun()
	h.start("LowGravity")
	h.roster.AwardStar(first.player)
	h.roster.AwardSurvivors("LowGravity")
	local realScore = first.player:GetAttribute("RunScore")
	first.player:SetAttribute("RunScore", 999999)
	first.player:SetAttribute("RunSurvived", 6)
	first.player:SetAttribute("RunEnergy", 999)
	h.roster.EndRound()
	h.remove(first)
	local late = h.addPlayer()
	h.start("ReactorRush", 2)
	h.roster.AwardStar(second.player)
	h.roster.AwardSurvivors("ReactorRush")
	h.roster.EndRound()
	expect(
		h.roster.CompleteRun(true) == 0,
		"Short social-history fixture does not change the four-survival victory rule"
	)
	local snapshot = contributionSnapshot(h, 11)
	expect(
		snapshot.Version == 1 and snapshot.Round == 11 and #snapshot.Players == 3 and not snapshot.Truncated,
		"Snapshot contains only the three actually admitted identities"
	)
	local a, b, c = snapshot.Players[1], snapshot.Players[2], snapshot.Players[3]
	expect(
		a.UserId == first.player.UserId
			and a.Left
			and a.Outcome == "Left"
			and a.Score == realScore
			and a.Survived == 1
			and a.Energy == 0,
		"Departed row retains real server counters and ignores tampered display attributes"
	)
	expect(
		b.UserId == second.player.UserId
			and b.Energy == 1
			and b.Survived == 2
			and b.Outcome == "NotEnoughTrials",
		"Present participant shares actual contribution and unchanged personal outcome"
	)
	expect(
		c.UserId == late.player.UserId and c.Survived == 1 and not c.Left,
		"Late join appears only after boundary admission"
	)
	expect(
		#first.completedRuns == 0 and #second.completedRuns == 1 and #late.completedRuns == 1,
		"Keeping departed rows adds no departed reward or extra completion"
	)
	local beforeCoins = second.player:GetAttribute("Coins")
	h.roster.Contributions(11)
	h.roster.CompleteRun(true)
	expect(
		#second.completedRuns == 1 and second.player:GetAttribute("Coins") == beforeCoins,
		"Snapshot reads and duplicate completion never award extra rewards"
	)
	h.roster.BeginRun()
	expect(#contributionSnapshot(h, 12).Players == 0, "Next run clears old contribution identities")
	h.destroy()
	scenarios += 1
end

do
	local h = harness(1)
	local original = h.records[1]
	h.roster.BeginRun()
	for index = 1, 3 do
		h.start("SafeColor", index)
		h.roster.AwardSurvivors("SafeColor")
		h.roster.EndRound()
	end
	local previousScore = original.player:GetAttribute("RunScore")
	h.remove(original)
	local returned = h.addPlayer(original.player.UserId)
	for index = 4, 6 do
		local ruleId = if index == 6 then "ReactorRush" else "SafeColor"
		h.start(ruleId, index)
		if index == 6 then
			h.roster.AwardStar(returned.player)
		end
		h.roster.AwardSurvivors(ruleId)
		h.roster.EndRound()
	end
	expect(
		h.roster.CompleteRun(true) == 0,
		"Rejoin contribution history cannot grant a personal victory to a three-trial segment"
	)
	local snapshot = contributionSnapshot(h, 1)
	expect(#snapshot.Players == 1, "Rejoining UserId shares one contribution row")
	local row = snapshot.Players[1]
	expect(
		row.Survived == 6
			and row.Score == previousScore + returned.player:GetAttribute("RunScore")
			and row.Energy == 1
			and row.Outcome == "NotEnoughTrials"
			and not row.Left,
		"Social totals sum both admitted segments while the personal outcome remains current"
	)
	expect(
		returned.player:GetAttribute("RunSurvived") == 3
			and #original.completedRuns == 0
			and returned.completedRuns[1] == false,
		"Social aggregation never modifies personal counters or reward recipients"
	)
	h.destroy()
	scenarios += 1
end

do
	local h = harness(12)
	h.roster.BeginRun()
	for index = 1, 6 do
		local cohort = {}
		for _, record in h.records do
			if record.player.Parent ~= nil then
				table.insert(cohort, record)
			end
		end
		local ruleId = if index == 6 then "ReactorRush" else "SafeColor"
		expect(
			h.start(ruleId, index) == 12,
			"Each cohort respects the simultaneous twelve-player admission limit"
		)
		if index == 6 then
			for _, record in cohort do
				h.roster.AwardStar(record.player)
			end
		end
		expect(h.roster.AwardSurvivors(ruleId) == 12, "Every admitted cohort finishes once")
		h.roster.EndRound()
		if index < 6 then
			for _, record in cohort do
				h.remove(record)
			end
			for _ = 1, 12 do
				h.addPlayer()
			end
		end
	end
	h.roster.CompleteRun(true)
	local encoded = h.roster.Contributions(15)
	local snapshot = serde.decode("json", encoded)
	local clientRows = ContributionView.read(snapshot, 15, 15)
	expect(
		clientRows ~= nil and #clientRows == 72,
		"Actual client accepts the real roster snapshot for six twelve-player cohorts"
	)
	expect(
		#snapshot.Players == 72 and not snapshot.Truncated and #encoded <= 32000,
		"All six successive cohorts survive the bounded result snapshot"
	)
	local departed, present = 0, 0
	for _, row in snapshot.Players do
		if row.Left then
			departed += 1
			expect(
				row.Outcome == "Left" and row.Survived == 1,
				"Departed cohort retains its actual single contribution"
			)
		else
			present += 1
			expect(
				row.Energy == 1 and row.Outcome == "NotEnoughTrials",
				"Final cohort's late personal outcome is honest"
			)
		end
	end
	expect(
		departed == 60 and present == 12,
		"Snapshot retains all departed identities, not only current Players"
	)
	for index, record in h.records do
		expect(
			#record.completedRuns == (if index <= 60 then 0 else 1),
			"Social retention never duplicates or awards a disconnected profile"
		)
	end
	h.destroy()
	scenarios += 1
end

for _, aborted in { false, true } do
	local h = harness(2)
	local active, warned = h.records[1], h.records[2]
	h.roster.BeginRun()
	h.start("ReactorRush", 6)
	h.roster.AwardStar(active.player)
	warned.player:SetAttribute("MovementWarning", true)
	h.roster.AwardSurvivors("ReactorRush")
	h.roster.EndRound()
	h.roster.CompleteRun(false, aborted)
	local rows = contributionSnapshot(h, 1).Players
	expect(
		rows[1].Outcome == (if aborted then "Aborted" else "FinaleFailed"),
		"Shared row mirrors the existing failed or aborted personal result"
	)
	expect(
		rows[2].Survived == 0
			and rows[2].Energy == 0
			and rows[2].Outcome == (if aborted then "Aborted" else "NoSurvival"),
		"Forfeited row cannot invent contribution or a victory"
	)
	expect(
		#active.completedRuns == (if aborted then 0 else 1) and #warned.completedRuns == 0,
		"Aborted and forfeited social rows remain independent of reward grants"
	)
	h.destroy()
	scenarios += 1
end

print("PlayerRoster integration: " .. checks .. " checks passed across " .. scenarios .. " scenarios")
