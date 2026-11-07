--!strict
-- Offline production-rule harness: rbx-dom Instances and deterministic adapters.
-- No Roblox physics, rendering, native clients, timing/latency or human acceptance.
-- Build the place first; run: lune run tests/ArenaRules.integration.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local RuleMath = require("../src/server/RuleMath")
local checks = 0
local scenarios = 0

local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

-- The authored model is already loaded. This adapter asserts required children;
-- it deliberately does not simulate streaming or yield/timeout behavior.
roblox.implementMethod("Instance", "WaitForChild", function(instance, name)
	local child = instance:FindFirstChild(name)
	assert(child, "Missing authored fixture child: " .. name)
	return child
end)

local function harness(population: number)
	local place = roblox.deserializePlace(fs.readFile("build/RuleRoom.rbxlx"))
	local arena = place:GetService("Workspace").Arena
	local h: any = { now = 0, awarded = 0, records = {}, arena = arena, snapshots = {} }
	local state = roblox.Instance.new("Folder")
	h.state = state
	for _, tile in arena.Tiles:GetChildren() do
		-- Serialized Parts store CFrame. These rules only read static floor
		-- Position, so materialize that value; no native transform simulation.
		tile.Position = tile.CFrame.Position
		local snapshot = {
			part = tile,
			color = tile.Color,
			material = tile.Material,
			transparency = tile.Transparency,
			collide = tile.CanCollide,
			query = tile.CanQuery,
			touch = tile.CanTouch,
			text = {},
			labels = {},
		}
		for _, child in tile:GetDescendants() do
			if child:IsA("TextLabel") then
				snapshot.text[child] = child.Text
			elseif child:IsA("SurfaceGui") then
				snapshot.labels[child] = child.Enabled
			end
		end
		table.insert(h.snapshots, snapshot)
	end
	for id = 1, population do
		local player = roblox.Instance.new("Player")
		player.UserId = id
		local root = roblox.Instance.new("Part")
		root.Position =
			roblox.Vector3.new(-35 + ((id - 1) % 6) * 14, 4.5, -35 + math.floor((id - 1) / 6) * 14)
		local record = { player = player, root = root, alive = true, damage = 0 }
		record.humanoid = {
			TakeDamage = function(_, amount)
				record.damage += amount
			end,
		}
		table.insert(h.records, record)
	end
	local randomSeed = 19
	local workspace = {
		Gravity = 196.2,
		GetServerTimeNow = function()
			return h.now
		end,
	}
	local config = luau.load(fs.readFile("src/shared/GameConfig.luau"), {
		environment = { Color3 = roblox.Color3 },
	})()
	local shared = {
		WaitForChild = function(_, name)
			assert(name == "GameConfig", "Fixture only exposes GameConfig")
			return config
		end,
	}
	local storage = {
		WaitForChild = function(_, name)
			assert(name == "RuleRoomShared", "Fixture only exposes RuleRoomShared")
			return shared
		end,
	}
	local module = luau.load(fs.readFile("src/server/ArenaRules.luau"), {
		debugName = "PRODUCTION_ArenaRules",
		environment = {
			game = {
				GetService = function(_, name)
					assert(name == "Workspace" or name == "ReplicatedStorage", name)
					return if name == "Workspace" then workspace else storage
				end,
			},
			script = { Parent = { RuleMath = RuleMath, PlayerRoster = {} } },
			require = function(value)
				return value
			end,
			Instance = roblox.Instance,
			Enum = roblox.Enum,
			Color3 = roblox.Color3,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			UDim2 = roblox.UDim2,
			Random = {
				new = function()
					return {
						NextInteger = function(_, minimum, maximum)
							randomSeed = randomSeed * 16807 % 2147483647
							return minimum + math.floor(randomSeed / 2147483647 * (maximum - minimum + 1))
						end,
					}
				end,
			},
		},
	})()
	h.rules = module.new(arena)
	h.context = {
		state = state,
		roster = {
			ForEachAlive = function(callback)
				for _, record in h.records do
					if record.alive then
						callback(record.player, record.humanoid, record.root)
					end
				end
			end,
			AwardStar = function()
				h.awarded += 1
				return true
			end,
		},
		waitFor = function(seconds, callback)
			local proceed = h.onWait(seconds, callback)
			h.now += seconds
			return proceed ~= false
		end,
	}
	function h.assertRestored()
		h.rules.Restore()
		for _, snapshot in h.snapshots do
			local tile = snapshot.part
			expect(
				tile.Color == snapshot.color and tile.Material == snapshot.material,
				"Restore returns tile appearance"
			)
			expect(tile.Transparency == snapshot.transparency, "Restore returns tile transparency")
			expect(
				tile.CanCollide == snapshot.collide
					and tile.CanQuery == snapshot.query
					and tile.CanTouch == snapshot.touch,
				"Restore preserves authored collision/query policy"
			)
			for label, text in snapshot.text do
				expect(label.Text == text, "Restore returns authored color names/symbols")
			end
			for label, enabled in snapshot.labels do
				expect(label.Enabled == enabled, "Restore returns authored label visibility")
			end
		end
		expect(#arena.RuleEffects:GetChildren() == 0, "Restore removes every temporary hazard/pickup")
		expect(state:GetAttribute("HazardStage") == "Recovery", "Restore returns the hazard to recovery")
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

-- A normal RedLight cycle and early exits in each distinct phase. The runner
-- invokes the production collection/movement callbacks, but not native physics.
for _, stopAt in { 0, 1, 2, 3 } do
	local h = harness(1)
	local waits, lastAwarded = 0, 0
	function h.onWait(_seconds, callback)
		waits += 1
		local phase = h.state:GetAttribute("HazardStage")
		local word = if phase == "Recovery"
			then "БЕГИ"
			elseif phase == "Warning" then "ЗАМРИ"
			else "СТОЙ"
		local symbol = if phase == "Recovery" then "▶" elseif phase == "Warning" then "⏸" else "■"
		for _, tile in h.arena.Tiles:GetChildren() do
			expect(tile.TileLabel.ColorText.Text == word, "RedLight floor words match the current permission")
			expect(tile.TileLabel.Symbol.Text == symbol, "RedLight has a matching non-color cue")
		end
		local pickups = h.arena.RuleEffects:GetChildren()
		if phase == "Recovery" then
			expect(#pickups == 4, "Each green phase starts with its existing four rewards")
			h.records[1].root.Position = pickups[1].Position
			assert(callback, "Green phase must collect")
			callback(0.1, 0.1)
			expect(h.awarded > lastAwarded, "A green-phase contact actually calls the reward adapter")
			lastAwarded = h.awarded
		else
			for _, star in pickups do
				expect(
					star.Transparency == 1 and not star.PickupLabel.Enabled,
					"Inactive pickups stop inviting movement"
				)
			end
			if callback then
				callback(0.1, 0.1)
			end
			expect(h.awarded == lastAwarded, "Yellow/red cannot award inactive stars")
		end
		return waits ~= stopAt
	end
	local completed = h.rules.Run("RedLight", h.context)
	expect(completed == (stopAt == 0), "Interrupted RedLight does not complete")
	expect(waits == (if stopAt == 0 then 9 else stopAt), "Cancellation stops without running later phases")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

do
	local h = harness(0)
	local previous, warnings = nil, 0
	function h.onWait(_seconds, callback)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			local zone = h.arena.RuleEffects.SafeZone
			warnings += 1
			expect(zone.Position ~= previous, "Production SafeZone changes destination each wave")
			expect(
				math.abs(zone.Size.X - 25.2) < 0.0001 and math.abs(zone.Size.Z - 25.2) < 0.0001,
				"Refuge size remains unchanged"
			)
			previous = zone.Position
		end
		if callback then
			callback(0.1, 0.1)
		end
		return true
	end
	expect(h.rules.Run("SafeZone", h.context), "Production SafeZone completes all waves")
	expect(warnings == 3, "SafeZone retains three warnings")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

do
	local h = harness(12)
	local warnings, counts = 0, {}
	function h.onWait(_seconds, callback)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			warnings += 1
			local fixedPositions = {}
			for index = 1, 3 do
				local meteor = h.arena.RuleEffects:FindFirstChild("Meteor" .. index)
				fixedPositions[index] = meteor.Position
				local found = false
				for _, record in h.records do
					local position = record.root.Position
					if position.X == meteor.Position.X and position.Z == meteor.Position.Z then
						local id = record.player.UserId
						counts[id] = (counts[id] or 0) + 1
						found = true
					end
				end
				expect(found, "Directed meteor snapshots a living player's location")
			end
			for _, record in h.records do
				record.root.Position += roblox.Vector3.new(0, 0, 2)
			end
			assert(callback, "Warning animates meteors")
			callback(2.7, 0.1)
			for index, position in fixedPositions do
				local meteor = h.arena.RuleEffects:FindFirstChild("Meteor" .. index)
				expect(
					meteor.Position.X == position.X and meteor.Position.Z == position.Z,
					"Warned impact stays fixed when the targeted player moves"
				)
			end
			for _, record in h.records do
				record.root.Position -= roblox.Vector3.new(0, 0, 2)
			end
			for _, child in h.arena.RuleEffects:GetChildren() do
				if child.Name == "ImpactWarning" then
					expect(
						child.Size.X == 11 and child.Size.Z == 11,
						"Warning still matches the square hit geometry"
					)
					expect(not child.CanCollide, "Meteor warnings never block movement")
				end
			end
		end
		return true
	end
	expect(h.rules.Run("MeteorRain", h.context), "Production MeteorRain completes all waves")
	expect(warnings == 5, "MeteorRain retains five warnings")
	for id = 1, 12 do
		expect(
			(counts[id] or 0) >= 1 and counts[id] <= 2,
			"Twelve adapter participants share fifteen directed warnings fairly"
		)
	end
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

print(
	`ArenaRules offline integration: {checks} checks across {scenarios} scenarios; no native physics/render acceptance.`
)
