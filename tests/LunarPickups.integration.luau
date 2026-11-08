--!strict
-- Executes the production lunar handler and visibility LocalScript offline.
-- Roster, signal and physics boundaries are adapters: this is not native multiplayer evidence.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local RuleMath = require("../src/server/RuleMath")
local TraversalMath = require("../src/server/TraversalMath")
local checks, scenarios = 0, 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
Roblox.implementMethod("Instance", "WaitForChild", function(instance, name)
	return assert(instance:FindFirstChild(name), "Missing fixture: " .. name)
end)

local function serverHarness(population: number)
	scenarios += 1
	local place = Roblox.deserializePlace(fs.readFile("build/RuleRoom.rbxlx"))
	local arena = place:GetService("Workspace").Arena
	for _, tile in arena.Tiles:GetChildren() do
		tile.Position = tile.CFrame.Position
	end
	local h: any = { records = {}, arena = arena, waitIndex = 0, awards = 0, awardCalls = 0 }
	function h.addPlayer()
		local player = Roblox.Instance.new("Player")
		player.UserId = #h.records + 1
		player:SetAttribute("InRound", true)
		local root = Roblox.Instance.new("Part")
		root.Position = Roblox.Vector3.new(0, 4, 0)
		local record = {
			player = player,
			root = root,
			humanoid = { Health = 100 },
			alive = true,
			connected = true,
			admitted = true,
			reject = false,
			awards = 0,
		}
		table.insert(h.records, record)
		return record
	end
	for _ = 1, population do
		h.addPlayer()
	end
	local config = luau.load(fs.readFile("src/shared/GameConfig.luau"), {
		environment = { Color3 = Roblox.Color3 },
	})()
	local storage = {
		WaitForChild = function()
			return {
				WaitForChild = function()
					return config
				end,
			}
		end,
	}
	local workspace = { Gravity = 196.2 }
	local state = Roblox.Instance.new("Folder")
	h.state = state
	local module = luau.load(fs.readFile("src/server/ArenaRules.luau"), {
		debugName = "PRODUCTION_ArenaRules_Lunar",
		environment = {
			game = {
				GetService = function(_, name)
					return if name == "Workspace" then workspace else storage
				end,
			},
			script = { Parent = { RuleMath = RuleMath, TraversalMath = TraversalMath, PlayerRoster = {} } },
			require = function(value)
				return value
			end,
			Instance = Roblox.Instance,
			Enum = Roblox.Enum,
			Color3 = Roblox.Color3,
			Vector3 = Roblox.Vector3,
			CFrame = Roblox.CFrame,
			UDim2 = Roblox.UDim2,
			Random = {
				new = function()
					return {
						NextInteger = function(_, minimum)
							return minimum
						end,
					}
				end,
			},
		},
	})()
	h.rules = module.new(arena)
	local function current(record)
		return record.alive and record.connected and record.admitted and record.humanoid.Health > 0
	end
	h.context = {
		state = state,
		roster = {
			ForEachAlive = function(callback)
				-- Lune has no assembled-character mass or force solver. Skip only the
				-- force-setup enumeration after the initial warning, not pickup admission.
				if h.skipForce then
					h.skipForce = false
					return
				end
				for _, record in h.records do
					if current(record) then
						callback(record.player, record.humanoid, record.root)
					end
				end
			end,
			AwardStar = function(player)
				h.awardCalls += 1
				for _, record in h.records do
					if record.player == player and current(record) and not record.reject then
						record.awards += 1
						h.awards += 1
						return true
					end
				end
				return false
			end,
		},
		waitFor = function(seconds, callback)
			h.waitIndex += 1
			if h.waitIndex == 1 then
				h.skipForce = true
				return true
			end
			return h.onActive(seconds, callback)
		end,
	}
	function h.star(index)
		return arena.RuleEffects:FindFirstChild("Star" .. index)
	end
	function h.move(record, index)
		record.root.Position = h.star(index).Position
	end
	function h.assertClear()
		h.rules.Restore()
		for _, record in h.records do
			if record.player:GetAttribute("LunarStarGoal") ~= nil then
				expect(record.player:GetAttribute("LunarStarGoal") == 0, "Restore closes personal goal")
				expect(record.player:GetAttribute("LunarStarMask") == 0, "Restore clears personal mask")
				expect(record.player:GetAttribute("LunarStarCount") == 0, "Restore clears personal count")
			end
		end
		expect(#arena.RuleEffects:GetChildren() == 0, "Restore removes all nine shared points")
	end
	function h.destroy()
		h.rules.Destroy()
		for _, record in h.records do
			record.player:Destroy()
			record.root:Destroy()
		end
		state:Destroy()
		place:Destroy()
	end
	return h
end

for _, population in { 1, 2, 12 } do
	local h = serverHarness(population)
	function h.onActive(_, tick)
		expect(#h.arena.RuleEffects:GetChildren() == 9, "Nine shared stars regardless of population")
		for index = 1, 9 do
			expect(h.star(index):GetAttribute("LunarStarIndex") == index, "Stable one-based star identity")
		end
		for index = 1, 4 do
			for _, record in h.records do
				h.move(record, index)
			end
			tick(0, 0)
			tick(0.05, 0.05)
			for _, record in h.records do
				local count = math.min(index, 3)
				expect(
					record.awards == count,
					"Simultaneous participants each get own star, once, capped at three"
				)
				expect(
					record.player:GetAttribute("LunarStarCount") == count,
					"Personal progress matches successful awards"
				)
				expect(
					record.player:GetAttribute("LunarStarMask") == 2 ^ count - 1,
					"Only successful personal indices enter mask"
				)
				expect(
					record.player:GetAttribute("LunarStarGoal") == 3,
					"Every admitted player gets same quota"
				)
			end
		end
		expect(h.awards == population * 3, "One, two and twelve players have equal per-player opportunity")
		expect(
			#h.arena.RuleEffects:GetChildren() == 9,
			"Personal collection never destroys another player's point"
		)
		return false
	end
	h.rules.Run("LowGravity", h.context)
	h.assertClear()
	h.destroy()
end

do
	local h = serverHarness(7)
	function h.onActive(_, tick)
		local rejected, dead, left, forfeited, warned, respawned, distant = table.unpack(h.records)
		for _, record in h.records do
			h.move(record, 9)
		end
		rejected.reject = true
		dead.humanoid.Health = 0
		left.connected = false
		forfeited.reject = true
		warned.player:SetAttribute("MovementWarning", true)
		local oldRoot = respawned.root
		respawned.root = Roblox.Instance.new("Part")
		h.move(respawned, 9)
		distant.root.Position += Roblox.Vector3.new(0, 0, 3.41)
		local late = h.addPlayer()
		h.move(late, 9)
		tick(0, 0)
		expect(
			h.awards == 0,
			"Rejected, dead, departed, forfeited, warned, respawned, distant and late players get nothing"
		)
		expect(h.awardCalls == 2, "Only current nearby original participants reach award authority")
		for _, record in h.records do
			expect((record.player:GetAttribute("LunarStarMask") or 0) == 0, "Rejection does not consume mask")
			expect(
				(record.player:GetAttribute("LunarStarCount") or 0) == 0,
				"Rejection does not consume quota"
			)
		end
		rejected.reject = false
		tick(0.05, 0.05)
		expect(rejected.awards == 1, "Later successful award may collect previously rejected point")
		expect(
			rejected.player:GetAttribute("LunarStarMask") == 256,
			"Ninth star uses bit eight of nine-bit mask"
		)
		expect(
			late.player:GetAttribute("LunarStarGoal") == nil,
			"A late arrival never receives admission attributes"
		)
		oldRoot:Destroy()
		return false
	end
	h.rules.Run("LowGravity", h.context)
	h.assertClear()
	h.destroy()
end

do
	local h = serverHarness(1)
	local attempts = 0
	function h.onActive(_, tick)
		attempts += 1
		local record = h.records[1]
		expect(record.player:GetAttribute("LunarStarCount") == 0, "Next trial starts at zero")
		expect(record.player:GetAttribute("LunarStarMask") == 0, "Next trial does not inherit old point mask")
		h.move(record, 1)
		tick(0, 0)
		expect(record.awards == attempts, "Same position can be earned again in a new trial")
		return false
	end
	for _ = 1, 2 do
		h.waitIndex = 0
		h.rules.Run("LowGravity", h.context)
		h.assertClear()
	end
	h.destroy()
end

-- Minimal event/Instance adapter: the production LocalScript is executed unchanged.
do
	local h = serverHarness(1)
	local callbacks = 0
	function h.onActive(_, tick)
		callbacks += 1
		local record = h.records[1]
		h.move(record, math.min(callbacks, 3))
		tick(0, 0)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			expect(
				string.find(h.state:GetAttribute("Instruction"), "ПРОВАЛ", 1, true) ~= nil,
				"Personal progress preserves server floor warning text"
			)
		end
		return true
	end
	expect(
		h.rules.Run("LowGravity", h.context),
		"Personal collection survives the full production lunar sequence"
	)
	expect(
		h.waitIndex == 6 and callbacks == 5,
		"Both floor-wave deadlines and final active wait still execute"
	)
	expect(h.records[1].awards == 3, "Full trial awards personal quota exactly once")
	-- Starting any other trial closes stale personal admission even before Restore.
	h.context.waitFor = function()
		return false
	end
	h.rules.Run("SafeColor", h.context)
	expect(h.records[1].player:GetAttribute("LunarStarGoal") == 0, "Next non-lunar trial closes lunar goal")
	expect(h.records[1].player:GetAttribute("LunarStarMask") == 0, "Run itself resets stale mask")
	expect(h.records[1].player:GetAttribute("LunarStarCount") == 0, "Run itself resets stale count")
	h.assertClear()
	h.destroy()
end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true, callback = callback }
			function connection:Disconnect()
				self.Connected = false
			end
			table.insert(listeners, connection)
			return connection
		end,
		Fire = function(_, ...)
			for _, listener in table.clone(listeners) do
				if listener.Connected then
					listener.callback(...)
				end
			end
		end,
	}
end
local function node(class, name, parent)
	local n: any = {
		ClassName = class,
		Name = name,
		Parent = parent,
		children = {},
		attributes = {},
		attributeSignals = {},
		ChildAdded = signal(),
		DescendantAdded = signal(),
		AncestryChanged = signal(),
		Destroying = signal(),
		LocalTransparencyModifier = 0,
		Enabled = true,
	}
	function n:IsA(kind)
		return self.ClassName == kind or (self.ClassName == "Part" and kind == "BasePart")
	end
	function n:GetAttribute(key)
		return self.attributes[key]
	end
	function n:GetAttributeChangedSignal(key)
		self.attributeSignals[key] = self.attributeSignals[key] or signal()
		return self.attributeSignals[key]
	end
	function n:SetAttribute(key, value)
		self.attributes[key] = value
		self:GetAttributeChangedSignal(key):Fire()
	end
	function n:FindFirstChild(key)
		for _, child in self.children do
			if child.Name == key then
				return child
			end
		end
		return nil
	end
	function n:WaitForChild(key)
		return assert(self:FindFirstChild(key), key)
	end
	function n:GetDescendants()
		local children = {}
		for _, child in self.children do
			table.insert(children, child)
			for _, descendant in child:GetDescendants() do
				table.insert(children, descendant)
			end
		end
		return children
	end
	function n:IsDescendantOf(ancestor)
		local current = self.Parent
		while current do
			if current == ancestor then
				return true
			end
			current = current.Parent
		end
		return false
	end
	if parent then
		table.insert(parent.children, n)
		parent.ChildAdded:Fire(n)
		local ancestor = parent
		while ancestor do
			ancestor.DescendantAdded:Fire(n)
			ancestor = ancestor.Parent
		end
	end
	return n
end

do
	scenarios += 1
	local workspace = node("Workspace", "Workspace", nil)
	local arena = node("Model", "Arena", workspace)
	local effects = node("Folder", "RuleEffects", arena)
	local storage = node("Folder", "Storage", nil)
	local state = node("Folder", "RuleRoomState", storage)
	local player = node("Player", "Player", nil)
	local script = node("LocalScript", "LunarPickups", nil)
	state:SetAttribute("Phase", "Rule")
	state:SetAttribute("RuleId", "LowGravity")
	player:SetAttribute("InRound", true)
	player:SetAttribute("LunarStarGoal", 3)
	player:SetAttribute("LunarStarCount", 0)
	player:SetAttribute("LunarStarMask", 0)
	local stars = {}
	for index = 1, 9 do
		local star = node("Part", "Star" .. index, effects)
		star:SetAttribute("LunarStarIndex", index)
		node("BillboardGui", "PickupLabel", star)
		table.insert(stars, star)
	end
	local foreign = node("Part", "Star99", effects)
	node("BillboardGui", "PickupLabel", foreign)
	luau.load(fs.readFile("src/client/LunarPickups.client.luau"), {
		debugName = "PRODUCTION_LunarPickups_client",
		environment = {
			game = {
				GetService = function(_, name)
					return if name == "Players"
						then { LocalPlayer = player }
						elseif name == "Workspace" then workspace
						else storage
				end,
			},
			script = script,
		},
	})()
	local function visible(star, wanted, description)
		expect(star.LocalTransparencyModifier == (if wanted then 0 else 1), description .. ": geometry")
		expect(star:FindFirstChild("PickupLabel").Enabled == wanted, description .. ": label")
	end
	for _, star in stars do
		visible(star, true, "Own uncollected point is visible")
	end
	player:SetAttribute("LunarStarMask", 257)
	player:SetAttribute("LunarStarCount", 2)
	visible(stars[1], false, "First personal collection hides first point")
	visible(stars[9], false, "Ninth personal collection hides ninth point")
	visible(stars[2], true, "Uncollected point remains available")
	visible(foreign, true, "Non-lunar stars are never modified")
	player:SetAttribute("LunarStarCount", 3)
	for _, star in stars do
		visible(star, false, "Quota hides all optional lunar points")
	end
	player:SetAttribute("LunarStarGoal", 0)
	player:SetAttribute("LunarStarCount", 0)
	player:SetAttribute("LunarStarMask", 0)
	visible(stars[2], false, "Cleanup stays hidden while state resets")
	player:SetAttribute("LunarStarGoal", 3)
	visible(stars[2], true, "New trial resets local visibility")
	for _, key in { "InRound", "MovementWarning" } do
		player:SetAttribute(key, key == "MovementWarning")
		visible(stars[2], false, "Ineligible participant cannot see available optional pickups")
		player:SetAttribute(key, key == "InRound")
	end
	state:SetAttribute("Phase", "Break")
	visible(stars[2], false, "Break hides lunar pickups")
	state:SetAttribute("Phase", "Rule")
	state:SetAttribute("RuleId", "RedLight")
	visible(stars[2], false, "A different trial cannot expose stale lunar pickups")
	visible(foreign, true, "Shared red-light pickup remains untouched")
	state:SetAttribute("RuleId", "LowGravity")
	player:SetAttribute("LunarStarMask", 0 / 0)
	visible(stars[2], false, "Malformed replicated mask fails closed")
	player:SetAttribute("LunarStarMask", 2)
	local streamed = node("Part", "Star2", effects)
	streamed:SetAttribute("LunarStarIndex", 2)
	local lateLabel = node("BillboardGui", "PickupLabel", streamed)
	expect(
		streamed.LocalTransparencyModifier == 1 and not lateLabel.Enabled,
		"Late metadata and label use current personal mask"
	)
	streamed.Parent = nil
	streamed.AncestryChanged:Fire()
	player:SetAttribute("LunarStarMask", 0)
	expect(streamed.LocalTransparencyModifier == 1, "Removed streamed point is no longer watched")
	player:SetAttribute("LunarStarCount", 3)
	script.Destroying:Fire()
	visible(stars[2], true, "Script destruction restores only local rendering overrides")
	player:SetAttribute("LunarStarMask", 2)
	visible(stars[2], true, "Destroyed controller has no remaining attribute listeners")
end

print(string.format("LunarPickups: %d checks / %d scenarios passed", checks, scenarios))
