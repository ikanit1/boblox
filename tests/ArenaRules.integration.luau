--!strict
-- Offline production-rule harness: rbx-dom Instances and deterministic adapters.
-- No Roblox physics, rendering, native clients, timing/latency or human acceptance.
-- Build the place first; run: lune run tests/ArenaRules.integration.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local RuleMath = require("../src/server/RuleMath")
local TraversalMath = require("../src/server/TraversalMath")
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
	local beamSnapshot = { cframe = arena.Laser.CFrame, size = arena.Laser.Size, color = arena.Laser.Color }
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
		-- Character adapter: pivoting moves the root part; no joints or physics.
		local character = {
			IsA = function(_, className)
				return className == "Model"
			end,
			GetPivot = function()
				return roblox.CFrame.new(root.Position)
			end,
			PivotTo = function(_, target)
				root.Position = target.Position
			end,
		}
		record.humanoid = {
			RigType = roblox.Enum.HumanoidRigType.R15,
			HipHeight = 2,
			Parent = character,
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
	h.config = config
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
			script = { Parent = { RuleMath = RuleMath, TraversalMath = TraversalMath, PlayerRoster = {} } },
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
							if h.randomMinimum then
								return minimum
							end
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
			AliveCount = function()
				local alive = 0
				for _, record in h.records do
					if record.alive then
						alive += 1
					end
				end
				return alive
			end,
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
		-- rbx-dom CFrame assignment can round the serialized position by a few microunits.
		expect(
			(arena.Laser.CFrame.Position - beamSnapshot.cframe.Position).Magnitude < 0.0001
				and (arena.Laser.CFrame.LookVector - beamSnapshot.cframe.LookVector).Magnitude < 0.0001
				and (arena.Laser.CFrame.UpVector - beamSnapshot.cframe.UpVector).Magnitude < 0.0001,
			"Restore returns authored beam transform"
		)
		expect(arena.Laser.Size == beamSnapshot.size, "Restore returns authored beam size")
		expect(arena.Laser.Color == beamSnapshot.color, "Restore returns authored beam color")
		expect(
			arena.Laser.Transparency == 1
				and not arena.Laser.CanCollide
				and not arena.Laser.CanTouch
				and not arena.Laser.CanQuery,
			"Restored beam is hidden and non-colliding"
		)
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
	local doomedTile = nil
	function h.onWait(_seconds, callback)
		waits += 1
		local phase = h.state:GetAttribute("HazardStage")
		local word = if phase == "Recovery"
			then "БЕГИ"
			elseif phase == "Warning" then "ЗАМРИ"
			else "СТОЙ"
		local symbol = if phase == "Recovery" then "▶" elseif phase == "Warning" then "⏸" else "■"
		local leaving = 0
		for _, tile in h.arena.Tiles:GetChildren() do
			if phase == "Recovery" and tile.TileLabel.ColorText.Text == "УЙДИ" then
				-- The tile under the player is the one that must be left during green.
				leaving += 1
				local p = h.records[1].root.Position
				expect(
					math.abs(p.X - tile.Position.X) <= 7 and math.abs(p.Z - tile.Position.Z) <= 7,
					"Green marks exactly the tile under the player"
				)
				expect(
					tile.TileLabel.Symbol.Text == "⚠" and tile.CanCollide,
					"Marked tile warns and is still solid"
				)
				doomedTile = tile
			elseif phase ~= "Recovery" and tile == doomedTile then
				expect(
					not tile.CanCollide and tile.Transparency == 1,
					"The marked tile vanishes when green ends"
				)
				expect(not tile.TileLabel.Enabled, "A vanished tile shows no label")
			else
				expect(
					tile.TileLabel.ColorText.Text == word,
					"RedLight floor words match the current permission"
				)
				expect(tile.TileLabel.Symbol.Text == symbol, "RedLight has a matching non-color cue")
				expect(tile.CanCollide, "Only the marked tile disappears")
			end
		end
		if phase == "Recovery" then
			expect(leaving == 1, "Standing still is not safe: one tile under the player is marked")
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

local function feetY(record): number
	return record.root.Position.Y - record.root.Size.Y / 2 - record.humanoid.HipHeight
end

-- LowGravity: every floor warning has its own deadline, including degenerate random draws.
for _, minimumDraws in { false, true } do
	local h = harness(1)
	h.randomMinimum = minimumDraws
	h.records[1].alive = false -- lune Parts have no AssemblyMass; join after lunar force setup
	h.records[1].root.Position = roblox.Vector3.new(7, 4.5, 7)
	local waits, wavesSeen, hiddenSeen = 0, 0, 0
	local durations = { 3, 4, 3, 3, 3, 4 }
	local stages = { "Warning", "Active", "Warning", "Active", "Warning", "Active" }
	local warned: { [any]: boolean } = {}
	function h.onWait(seconds, callback)
		waits += 1
		expect(seconds == durations[waits], "Each lunar subphase publishes its actual duration")
		local phase = h.state:GetAttribute("HazardStage")
		expect(phase == stages[waits], "Lunar warning and active waits alternate before danger")
		if waits == 1 then
			return true
		end
		h.records[1].alive = true
		assert(callback, "Lunar force and collection update during every lunar subphase")
		callback(0, 0.1)
		if phase == "Warning" then
			table.clear(warned)
		end
		local marked, gone = 0, 0
		local underPlayer = nil
		for _, tile in h.arena.Tiles:GetChildren() do
			local p = h.records[1].root.Position
			if math.abs(p.X - tile.Position.X) <= 7 and math.abs(p.Z - tile.Position.Z) <= 7 then
				underPlayer = tile
			end
			if tile.TileLabel.ColorText.Text == "ПРОВАЛ" and tile.CanCollide then
				marked += 1
				warned[tile] = true
				expect(tile.TileLabel.Symbol.Text == "⚠", "Doomed low-gravity tile has a symbol cue")
			elseif not tile.CanCollide then
				gone += 1
				expect(warned[tile] == true, "Only previously warned tiles vanish")
			end
		end
		if phase == "Warning" then
			wavesSeen += 1
			expect(warned[underPlayer] == true, "The tile under the player is always warned")
			expect(marked == 7, "Each wave warns the player's tile plus six distinct others")
			expect(gone == 0, "Previous holes restore before the next floor warning")
		elseif waits > 2 then
			hiddenSeen += 1
			expect(gone == 7, "Every warned tile vanishes after its warning")
		end
		return true
	end
	expect(h.rules.Run("LowGravity", h.context), "Production LowGravity completes")
	expect(wavesSeen == 2 and hiddenSeen == 2, "LowGravity runs two warned floor waves")
	expect(waits == #durations and h.now == 20, "Lunar phases retain the total three plus seventeen seconds")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

-- LavaRise: a survivor standing where a solid platform appears is lifted onto it.
do
	local h = harness(3)
	h.records[1].root.Position = roblox.Vector3.new(0, 4.5, 0) -- centre platform footprint
	h.records[2].root.Position = roblox.Vector3.new(14, 4.5, 14) -- open lava floor
	h.records[3].root.Position = roblox.Vector3.new(28, 7.6, 28) -- already on top
	local untouched = h.records[3].root.Position
	local warnings, actives = 0, 0
	function h.onWait(_seconds, callback)
		local stage = h.state:GetAttribute("HazardStage")
		if stage == "Warning" then
			warnings += 1
			local platforms = 0
			for _, child in h.arena.RuleEffects:GetChildren() do
				if child.Name == "SafePlatform" then
					platforms += 1
					expect(child.CanCollide, "Lava platforms are solid")
					local top = child.Position.Y + child.Size.Y / 2
					for _, record in h.records do
						local p = record.root.Position
						local inside = math.abs(p.X - child.Position.X)
								<= child.Size.X / 2 + record.root.Size.X / 2
							and math.abs(p.Z - child.Position.Z)
								<= child.Size.Z / 2 + record.root.Size.Z / 2
						expect(
							not inside or feetY(record) >= top,
							"No living body is embedded in a newly created platform"
						)
					end
				end
			end
			expect(platforms == 9, "LavaRise keeps nine platforms")
			expect(
				math.abs(feetY(h.records[1]) - 5.1) < 0.001,
				"Overlapping survivor stands on the platform top"
			)
			expect(h.records[2].root.Position.Y == 4.5, "A player on open floor is not moved")
			expect(h.records[3].root.Position == untouched, "A player already on top is not moved")
		elseif stage == "Active" then
			actives += 1
			assert(callback, "Active lava checks bodies")
			callback(4, 0.1)
			expect(h.records[1].damage == 0, "Lifted survivor is safe from rising lava")
			expect(h.records[2].damage > 0, "A player left on the floor is burned")
		end
		return true
	end
	expect(h.rules.Run("LavaRise", h.context), "Production LavaRise completes")
	expect(warnings == 1 and actives == 1, "LavaRise keeps one warning and one active phase")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

-- DisappearingTiles: each wave warns one third of the floor in text and removes exactly it.
do
	local h = harness(0)
	local waves, previous = 0, nil
	local warned: { [any]: boolean } = {}
	function h.onWait(_seconds, _callback)
		local stage = h.state:GetAttribute("HazardStage")
		if stage == "Warning" then
			waves += 1
			table.clear(warned)
			local signature = {}
			for _, tile in h.arena.Tiles:GetChildren() do
				if tile.TileLabel.ColorText.Text == "ПРОВАЛ" then
					expect(tile.TileLabel.Symbol.Text == "⚠", "Doomed tile has a non-colour symbol")
					expect(tile.CanCollide, "Doomed tile is still solid during its warning")
					warned[tile] = true
					table.insert(signature, tile.Name)
				end
			end
			table.sort(signature)
			local key = table.concat(signature, ",")
			expect(#signature == 12, "Each wave warns exactly one third of the floor")
			expect(key ~= previous, "Consecutive waves warn different tiles")
			previous = key
		elseif stage == "Active" then
			for _, tile in h.arena.Tiles:GetChildren() do
				expect((not tile.CanCollide) == (warned[tile] == true), "Exactly the warned tiles disappear")
			end
		end
		return true
	end
	expect(h.rules.Run("DisappearingTiles", h.context), "Production DisappearingTiles completes")
	expect(waves == 4, "DisappearingTiles keeps four waves")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

-- All six SafeColor waits are cancellable; inspect the production floor mask.
for stopAt = 0, 6 do
	local h = harness(0)
	local waits, previous = 0, nil
	function h.onWait(seconds, callback)
		waits += 1
		local selected = h.state:GetAttribute("SafeColor")
		local warning = h.state:GetAttribute("HazardStage") == "Warning"
		expect(callback == nil, "SafeColor changes floor state without a hidden damage callback")
		expect(
			seconds
				== (if warning then h.config.SafeColor.WarningSeconds else h.config.SafeColor.HiddenSeconds),
			"SafeColor uses the configured warning/hidden deadline"
		)
		if warning then
			expect(selected ~= previous, "Consecutive SafeColor calls select a different color")
			previous = selected
		end
		local solid = 0
		for _, snapshot in h.snapshots do
			local tile = snapshot.part
			local expected = warning or tile:GetAttribute("ColorName") == selected
			expect(
				tile.CanCollide == (expected and snapshot.collide)
					and tile.CanQuery == (expected and snapshot.query)
					and tile.CanTouch == (expected and snapshot.touch),
				"SafeColor collision and query mask matches announced color"
			)
			if tile.CanCollide then
				solid += 1
			end
		end
		expect(
			solid == (if warning then 36 else 9),
			"Warning preserves the floor; active keeps nine safe tiles"
		)
		return waits ~= stopAt
	end
	expect(
		h.rules.Run("SafeColor", h.context) == (stopAt == 0),
		"SafeColor cancellation never reports completion"
	)
	expect(waits == (if stopAt == 0 then 6 else stopAt), "SafeColor stops at the requested stage")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

-- Body positions are injected geometry samples, not a simulated jump trajectory.
-- Check both deliberate contact and clear vertical separation in actual handlers.
for _, ruleId in { "LaserSweep", "Spinner" } do
	for _, stopAt in { 0, 1, 2 } do
		local h = harness(3)
		local waits = 0
		h.records[1].root.Position = roblox.Vector3.new(0, 4, 0)
		h.records[2].root.Position = roblox.Vector3.new(0, 8, 0)
		h.records[3].root.Position = roblox.Vector3.new(41, 4, 41)
		for _, record in h.records do
			record.root.Size = roblox.Vector3.new(2, 2, 1)
		end
		function h.onWait(seconds, callback)
			waits += 1
			local warning = h.state:GetAttribute("HazardStage") == "Warning"
			if warning then
				expect(
					callback == nil and h.arena.Laser.Transparency >= 0.4,
					"Beam warning does not apply damage"
				)
				expect(
					h.records[1].damage == 0 and h.records[3].damage == 0,
					"No damage before the active stage"
				)
			else
				assert(callback, "Active beam requires its damage callback")
				local start = h.now
				for tick = 0, math.floor(seconds / 0.05) do
					local elapsed = tick * 0.05
					h.now = start + elapsed
					callback(elapsed, 0.05)
				end
				h.now = start
				expect(h.records[1].damage > 0, "Standing at beam contact receives damage")
				expect(h.records[3].damage > 0, "The arena corner is inside the beam's gameplay coverage")
				expect(h.records[2].damage == 0, "A geometrically clear raised body receives no damage")
				expect(
					h.records[1].player:GetAttribute("LastDamageRule") == ruleId,
					"Damage journal records the actual rule"
				)
				expect(
					h.records[2].player:GetAttribute("LastDamageAt") == nil,
					"Clear bodies have no hidden damage journal hit"
				)
				if ruleId == "LaserSweep" then
					expect(
						h.records[1].damage >= h.config.LaserSweep.Damage * 3,
						"All three configured sweep contacts are represented"
					)
				end
			end
			return waits ~= stopAt
		end
		expect(h.rules.Run(ruleId, h.context) == (stopAt == 0), "Beam cancellation never reports completion")
		expect(waits == (if stopAt == 0 then 2 else stopAt), "Beam cancellation stops later phases")
		h.assertRestored()
		h.destroy()
		scenarios += 1
	end
end

local reactorCases = {
	{ population = 1, charge = true },
	{ population = 2, charge = true },
	{ population = 12, charge = true },
	{ population = 1, charge = false },
	{ population = 2, charge = true, allDead = true },
	{ population = 2, charge = true, stopAt = 1 },
	{ population = 2, charge = true, stopAt = 2 },
	{ population = 2, charge = true, stopAt = 3 },
	{ population = 12, charge = true, stabilizationDeath = true },
}
for _, case in reactorCases do
	local h = harness(case.population)
	local waits = 0
	for _, record in h.records do
		record.root.Size = roblox.Vector3.new(2, 2, 1)
	end
	function h.onWait(seconds, callback)
		waits += 1
		local goal = RuleMath.teamGoal(case.population)
		expect(
			h.state:GetAttribute("TeamGoal") == goal,
			"Reactor goal uses admitted population, capped by policy"
		)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			expect(callback == nil and h.awarded == 0, "Reactor warning cannot collect or damage")
			expect(
				#h.arena.RuleEffects:GetChildren() == math.min(goal + 6, 36),
				"Reactor creates a finite unique pickup pool"
			)
		elseif h.state:GetAttribute("FinaleStage") == "Stabilizing" then
			assert(callback, "Stabilization has an active beam callback")
			expect(
				seconds == 4 and #h.arena.RuleEffects:GetChildren() == 0,
				"Stabilization is exactly four seconds with no remaining charges"
			)
			expect(
				h.state:GetAttribute("StabilizeEndsAt") == h.now + 4,
				"Stabilization publishes its own server deadline"
			)
			expect(
				h.state:GetAttribute("HazardStage") == "Active"
					and h.state:GetAttribute("FinaleSuccess") == false,
				"The existing hazard stays active and success is still pending"
			)
			local awarded = h.awarded
			callback(0, 0)
			callback(3.9, 3.9)
			expect(h.awarded == awarded, "Stabilization cannot create additional rewards")
			if case.stabilizationDeath then
				for _, record in h.records do
					record.alive = false
				end
			end
		elseif case.charge then
			assert(callback, "Active reactor requires its collection callback")
			local first = h.arena.RuleEffects:GetChildren()[1]
			for _, record in h.records do
				record.root.Position = first.Position + roblox.Vector3.new(0, 3, 0)
			end
			-- Denied rewards must leave the orb and team charge unchanged.
			local award = h.context.roster.AwardStar
			h.context.roster.AwardStar = function()
				return false
			end
			callback(0.1, 0.1)
			expect(
				first.Parent ~= nil and h.state:GetAttribute("TeamCharge") == 0,
				"Rejected reward cannot consume an orb or charge reactor"
			)
			h.context.roster.AwardStar = award
			callback(0.2, 0.1)
			expect(
				h.awarded == 1 and h.state:GetAttribute("TeamCharge") == 1,
				"Shared contact awards exactly once across all adapters"
			)
			callback(0.3, 0.1)
			expect(h.awarded == 1, "Repeated callback cannot award the consumed orb")
			for index = 2, goal do
				local pickup = h.arena.RuleEffects:GetChildren()[1]
				h.records[1].root.Position = pickup.Position + roblox.Vector3.new(0, 3, 0)
				callback(index / 10 + 0.3, 0.1)
			end
			expect(
				h.awarded == goal and h.state:GetAttribute("TeamCharge") == goal,
				"Accepted pickups alone advance charge to goal"
			)
			expect(
				h.state:GetAttribute("FinaleSuccess") == false,
				"Charging does not prematurely publish final success"
			)
			local charged = h.state:GetAttribute("TeamCharge")
			if case.allDead then
				for _, record in h.records do
					record.alive = false
				end
			elseif case.population > 1 then
				h.records[case.population].alive = false
			end
			expect(
				h.state:GetAttribute("TeamGoal") == goal and h.state:GetAttribute("TeamCharge") == charged,
				"A departure/death never duplicates contribution or reduces the goal"
			)
		else
			assert(callback, "Uncharged reactor still runs its active callback")
			for _, record in h.records do
				record.root.Position = roblox.Vector3.new(0, 20, 0)
			end
			callback(1, 0.1)
			expect(h.awarded == 0, "Surviving without contact earns no pickups")
		end
		return waits ~= case.stopAt
	end
	local completed = h.rules.Run("ReactorRush", h.context)
	expect(
		completed == (case.stopAt == nil and not case.allDead and not case.stabilizationDeath),
		"Reactor requires uninterrupted waits and at least one living participant"
	)
	expect(
		h.state:GetAttribute("FinaleSuccess")
			== (case.charge and not case.allDead and not case.stabilizationDeath and case.stopAt == nil),
		"Reactor requires charge, completed stabilization and a living participant"
	)
	expect(
		h.state:GetAttribute("FinaleStage")
			== (if h.state:GetAttribute("FinaleSuccess") then "Complete" else "Failed"),
		"Finale outcome is unambiguous"
	)
	expect(#h.arena.RuleEffects:GetChildren() == 0, "Reactor removes all unclaimed charges on every exit")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

-- Exact threshold and deadline policy executes the real reactor handler, including
-- the callback's early-completion signal consumed by production Main.waitFor.
for _, lastAt in { 23.999, 24, 30 } do
	local h = harness(1)
	local goal = RuleMath.teamGoal(1)
	local collectionCallback
	function h.onWait(_seconds, callback)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			return true
		elseif h.state:GetAttribute("FinaleStage") == "Collect" then
			collectionCallback = callback
			for index = 1, goal - 1 do
				local pickup = h.arena.RuleEffects:GetChildren()[1]
				h.records[1].root.Position = pickup.Position + roblox.Vector3.new(0, 3, 0)
				expect(callback(index / 10, 0.1) ~= true, "No early completion below the charge threshold")
			end
			local last = h.arena.RuleEffects:GetChildren()[1]
			h.records[1].root.Position = last.Position + roblox.Vector3.new(0, 3, 0)
			expect(
				callback(lastAt, 0.1) == (lastAt < 24),
				"Only a valid last charge before the deadline ends collection early"
			)
			callback(lastAt, 0)
			callback(0.1, 0)
			expect(
				h.awarded == (if lastAt < 24 then goal else goal - 1),
				"Duplicate, exact-deadline, late and reversed callbacks cannot add charges"
			)
		else
			expect(lastAt < 24, "Only a charged reactor enters stabilization")
			local before = h.awarded
			collectionCallback(1, 1)
			callback(1, 1)
			expect(h.awarded == before, "An old collection closure remains closed during stabilization")
		end
		return true
	end
	expect(
		h.rules.Run("ReactorRush", h.context),
		"A normal timer outcome returns completion to the round owner"
	)
	expect(
		h.state:GetAttribute("FinaleSuccess") == (lastAt < 24),
		"Final success distinguishes pre-deadline charge from timeout"
	)
	local awarded, damage = h.awarded, h.records[1].damage
	collectionCallback(1, 1)
	expect(
		h.awarded == awarded and h.records[1].damage == damage,
		"Closed collection cannot award or damage after the rule"
	)
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

do
	local h = harness(12)
	local goal = RuleMath.teamGoal(12)
	local savedCallbacks = {}
	for run = 1, 3 do
		function h.onWait(_seconds, callback)
			if h.state:GetAttribute("HazardStage") == "Warning" then
				local position = roblox.Vector3.new(0, 10, 0)
				for _, record in h.records do
					record.root.Position = position
				end
				for _, pickup in h.arena.RuleEffects:GetChildren() do
					pickup.Position = position
				end
			elseif h.state:GetAttribute("FinaleStage") == "Collect" then
				for _, previous in savedCallbacks do
					previous(0.5, 0.5)
				end
				table.insert(savedCallbacks, callback)
				expect(callback(1, 1) == true, "A same-step batch signals completion exactly at the goal")
				callback(1, 0)
				expect(
					h.awarded == goal * run and h.state:GetAttribute("TeamCharge") == goal,
					"Twelve overlapping adapters and excess orbs cannot over-award the threshold"
				)
			else
				callback(1, 1)
			end
			return true
		end
		expect(h.rules.Run("ReactorRush", h.context), "Repeated reactor runs finish independently")
		expect(
			h.state:GetAttribute("FinaleSuccess") and #h.arena.RuleEffects:GetChildren() == 0,
			"No excess charge objects survive a successful reactor"
		)
		h.rules.Restore()
	end
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

for _, mode in { "beamDeath", "resetCollect", "resetStabilizing" } do
	local h = harness(1)
	local callbackAfterReset
	function h.onWait(_seconds, callback)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			return true
		end
		if
			mode == "resetCollect"
			or (mode == "resetStabilizing" and h.state:GetAttribute("FinaleStage") == "Stabilizing")
		then
			callbackAfterReset = callback
			h.rules.Restore()
			callback(1, 1)
		elseif mode == "beamDeath" then
			h.records[1].root.Size = roblox.Vector3.new(2, 2, 1)
			h.records[1].root.Position = roblox.Vector3.new(0, 4.5, -41)
			for _, pickup in h.arena.RuleEffects:GetChildren() do
				pickup.Position = h.records[1].root.Position
			end
			h.records[1].humanoid.TakeDamage = function()
				h.records[1].alive = false
			end
			callback(0, 0)
			expect(h.awarded == 0, "A lethal beam is processed before pickup contact in the same step")
		else
			for index = 1, RuleMath.teamGoal(1) do
				local pickup = h.arena.RuleEffects:GetChildren()[1]
				h.records[1].root.Position = pickup.Position + roblox.Vector3.new(0, 3, 0)
				callback(index / 10, 0.1)
			end
		end
		return true
	end
	expect(not h.rules.Run("ReactorRush", h.context), "Death/reset interrupts collection or stabilization")
	local awarded = h.awarded
	if callbackAfterReset then
		callbackAfterReset(2, 1)
	end
	expect(
		h.awarded == awarded and not h.state:GetAttribute("FinaleSuccess"),
		"No stale callback can revive a cancelled finale"
	)
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

for _, mode in { "missedPass", "missedBounce", "lateEntry", "lateJump" } do
	local h = harness(1)
	local record = h.records[1]
	record.root.Size = roblox.Vector3.new(2, 2, 1)
	local collectAt = if mode == "missedBounce" then 8 else 2
	local z = if mode == "missedBounce" then 40 elseif mode == "lateEntry" then 30 else 0
	function h.onWait(_seconds, callback)
		if h.state:GetAttribute("HazardStage") == "Warning" then
			record.root.Position = roblox.Vector3.new(0, 8, z)
			for _, pickup in h.arena.RuleEffects:GetChildren() do
				pickup.Position = record.root.Position
			end
		elseif h.state:GetAttribute("FinaleStage") == "Collect" then
			expect(
				callback(collectAt, collectAt) == true,
				"The focused hitch scenario charges the real reactor"
			)
			expect(record.damage == 0, "A raised body is clear during charge setup")
		else
			record.root.Position = roblox.Vector3.new(0, 4, z)
			callback(0, 0)
			expect(record.damage == 0, "The stabilization beam has not reached this standing player yet")
			record.humanoid.TakeDamage = function(_, amount)
				record.damage += amount
				record.alive = false
			end
			if mode == "lateEntry" then
				record.root.Position = roblox.Vector3.new(0, 4, 0)
				h.now += 4
			elseif mode == "lateJump" then
				record.root.Position = roblox.Vector3.new(0, 8, 0)
				h.now += 4
			else
				h.now += 0.1
			end
			-- The adapter advances the remaining four seconds without another tick.
		end
		return true
	end
	local completed = h.rules.Run("ReactorRush", h.context)
	expect(
		record.damage == (if mode == "lateEntry" then 0 else 30),
		"Closing geometry covers the missed pass/turnaround while clipping post-deadline movement"
	)
	expect(
		completed == (mode == "lateEntry") and h.state:GetAttribute("FinaleSuccess") == completed,
		"Last-player death during closing geometry prevents reactor success"
	)
	expect(h.awarded == RuleMath.teamGoal(1), "Closing geometry never collects or awards extra charges")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

-- Cancellation at every remaining distinct wait boundary, including later waves.
-- The production owner (Main) restores after Run returns; this harness does the same.
for _, spec in
	{
		{ rule = "RedLight", first = 4, last = 9 },
		{ rule = "LowGravity", first = 1, last = 6 },
		{ rule = "LavaRise", first = 1, last = 2 },
		{ rule = "MeteorRain", first = 1, last = 10 },
		{ rule = "DisappearingTiles", first = 1, last = 8 },
		{ rule = "SafeZone", first = 1, last = 6 },
	}
do
	for stopAt = spec.first, spec.last do
		local h = harness(0)
		local waits = 0
		function h.onWait(_seconds, _callback)
			waits += 1
			return waits ~= stopAt
		end
		expect(
			not h.rules.Run(spec.rule, h.context),
			"Cancellation prevents successful completion: " .. spec.rule
		)
		expect(
			waits == stopAt and h.awarded == 0,
			"Cancelled rule neither starts later stages nor grants pickups"
		)
		h.assertRestored()
		h.destroy()
		scenarios += 1
	end
end

-- Snapshot tests execute the actual Studio driver's helper without creating a LocalScript
-- or claiming that MoveTo/Jump, PlayerModule, or native controls have run.
do
	local source = fs.readFile("tools/studio/rule_driver.client.luau"):gsub("\r\n", "\n")
	local helper = source:match("%-%- QA_FLOOR_ROUTING_BEGIN\n(.-)\n%-%- QA_FLOOR_ROUTING_END")
	assert(helper, "Locate the real QA floor routing helper")
	local driver = luau.load(helper .. "\nreturn { Target = safeFloorTarget, Visible = visiblePickup }", {
		debugName = "QA_DriverFloorRouting",
		environment = { Vector3 = roblox.Vector3 },
	})()
	local targetFor = driver.Target
	local attributes = { InRound = true, LunarStarGoal = 3, LunarStarCount = 0, LunarStarMask = 0 }
	local player = {
		GetAttribute = function(_, name)
			return attributes[name]
		end,
	}
	local index: number? = 1
	local pickup = {
		Transparency = 0,
		LocalTransparencyModifier = 0,
		GetAttribute = function()
			return index
		end,
	}
	expect(driver.Visible(player, pickup), "Driver accepts a fresh personal lunar target")
	attributes.LunarStarMask = 1
	expect(not driver.Visible(player, pickup), "Driver ignores already claimed lunar position")
	index = 2
	expect(driver.Visible(player, pickup), "Another personal lunar position remains available")
	attributes.LunarStarCount = 3
	expect(not driver.Visible(player, pickup), "Driver stops chasing personal stars after the quota")
	attributes.LunarStarCount = 0
	attributes.MovementWarning = true
	expect(not driver.Visible(player, pickup), "Driver respects forfeited lunar collection")
	attributes.MovementWarning = false
	attributes.LunarStarGoal = 0
	expect(
		not driver.Visible(player, pickup),
		"Driver ignores personal stars before admission or after cleanup"
	)
	index = nil
	expect(driver.Visible(player, pickup), "Shared RedLight stars keep their existing visibility contract")
	pickup.LocalTransparencyModifier = 1
	expect(not driver.Visible(player, pickup), "Driver honors local presentation hiding")
	local h = harness(0)
	local tiles = h.arena.Tiles:GetChildren()
	local function at(x, z)
		for _, tile in tiles do
			if tile.Position.X == x and tile.Position.Z == z then
				return tile
			end
		end
		error("Missing grid tile")
	end
	local start = at(-35, -35)
	for _, word in { "УЙДИ", "ПРОВАЛ" } do
		start.TileLabel.ColorText.Text = word
		local target, isPickup = targetFor(start.Position, tiles, {}, word)
		expect(
			target ~= nil and (target - start.Position).Magnitude == 14 and not isPickup,
			"Driver leaves a warned starting tile even after every star is gone"
		)
	end
	start.TileLabel.ColorText.Text = "СИНИЙ"
	local hole = at(-21, -35)
	hole.CanCollide = false
	local goal = { Position = at(-7, -35).Position + roblox.Vector3.new(0, 10, 0) }
	local detour, atPickup = targetFor(start.Position, tiles, { goal }, "ПРОВАЛ")
	expect(
		detour == at(-35, -21).Position and not atPickup,
		"Driver chooses an adjacent walking detour instead of crossing a hole"
	)
	goal.Position = hole.Position + roblox.Vector3.new(0, 10, 0)
	local hold, unsafePickup = targetFor(start.Position, tiles, { goal }, "ПРОВАЛ")
	expect(
		hold == start.Position and not unsafePickup,
		"Driver ignores an unreachable pickup above a vanished tile"
	)
	goal.Position = start.Position + roblox.Vector3.new(2, 10, 0)
	local collect, canJump = targetFor(start.Position, tiles, { goal }, "ПРОВАЛ")
	expect(collect == goal.Position and canJump, "A reachable local pickup remains a normal jump target")
	for _, tile in tiles do
		tile.CanCollide = false
	end
	local missing, phantom = targetFor(start.Position, tiles, {}, "ПРОВАЛ")
	expect(missing == nil and not phantom, "No safe route does not invent a teleport target")
	h.destroy()
end

-- Production traversal handlers. Scripted transforms are geometry samples, not
-- physical movement or permission to teleport players in the actual game.
for _, ruleId in { "PressureWave", "ChangingWalls" } do
	for _, safe in { true, false } do
		local h = harness(12)
		h.randomMinimum = true
		local callbacks = {}
		local waits = 0
		function h.onWait(seconds, callback)
			waits += 1
			local current = h.state:GetAttribute("HazardStage")
			if current == "Warning" then
				expect(seconds == 5 and callback == nil, "Every new direction receives the full warning")
				local source = h.arena.RuleEffects:FindFirstChild("TraversalSource")
				expect(
					source ~= nil and source.Transparency < 0.5,
					"A visible source cue exists throughout the warning"
				)
				if source then
					expect(
						math.abs(source.Position.X) + source.Size.X / 2 < h.config.ArenaHalfSize
							and math.abs(source.Position.Z) + source.Size.Z / 2 < h.config.ArenaHalfSize,
						"The warning source is entirely inside the floor, never behind an opaque boundary wall"
					)
					expect(
						source.Position.Y > 1 and source:FindFirstChild("TraversalLabel") ~= nil,
						"The source has an above-floor mark and a readable short label"
					)
				end
				local target = h.arena.RuleEffects:FindFirstChild(
					if ruleId == "PressureWave" then "PressureShelter1" else "WallOpening"
				)
				assert(target, "Traversal creates its advertised safe marker")
				for _, record in h.records do
					record.root.Position = if safe
						then roblox.Vector3.new(target.Position.X, 4.5, target.Position.Z)
						else roblox.Vector3.new(0, 4.5, -35)
				end
				for _, effect in h.arena.RuleEffects:GetChildren() do
					expect(
						effect:IsA("BasePart")
							and not effect.CanCollide
							and not effect.CanTouch
							and not effect.CanQuery,
						"No traversal screen can push or trap a character"
					)
				end
			elseif current == "Active" then
				assert(callback, "Traversal active stage updates swept geometry")
				table.insert(callbacks, callback)
				local positions = {}
				for index, record in h.records do
					positions[index] = record.root.Position
				end
				callback(seconds, seconds)
				callback(seconds, 0)
				for index, record in h.records do
					expect(
						record.root.Position == positions[index],
						"Server hazard never teleports or modifies a root transform"
					)
				end
			else
				expect(
					current == "Recovery" and seconds == 1 and #h.arena.RuleEffects:GetChildren() == 0,
					"Every recovery removes the previous pattern"
				)
			end
			return true
		end
		expect(h.rules.Run(ruleId, h.context), "Both traversal passes finish")
		expect(waits == 6 and h.awarded == 0, "Traversal uses six bounded stages and no extra pickup rewards")
		for _, record in h.records do
			expect(
				record.damage == (if safe then 0 else 130),
				"Each participant receives at most one hit per unsafe pass"
			)
			if not safe then
				expect(
					record.player:GetAttribute("LastDamageRule") == ruleId,
					"Traversal damage uses the existing cause/Flawless journal"
				)
			end
		end
		for _, callback in callbacks do
			callback(1, 1)
		end
		for _, record in h.records do
			expect(
				record.damage == (if safe then 0 else 130),
				"A stale callback after completion cannot deal damage"
			)
		end
		h.assertRestored()
		h.destroy()
		scenarios += 1
	end
	for stopAt = 1, 6 do
		local h = harness(1)
		local waits = 0
		function h.onWait(_seconds, _callback)
			waits += 1
			return waits ~= stopAt
		end
		expect(
			not h.rules.Run(ruleId, h.context) and waits == stopAt,
			"Cancellation stops at the exact traversal phase"
		)
		expect(
			#h.arena.RuleEffects:GetChildren() == 0 and h.state:GetAttribute("HazardStage") == "Recovery",
			"Cancelled traversal cleans its own geometry immediately"
		)
		h.assertRestored()
		h.destroy()
		scenarios += 1
	end
	local h = harness(1)
	local stale
	function h.onWait(_seconds, callback)
		if callback then
			stale = callback
			h.rules.Restore()
			callback(3, 3)
		end
		return true
	end
	expect(not h.rules.Run(ruleId, h.context), "Restore invalidates an in-flight traversal generation")
	assert(stale, "Reset scenario captured the active traversal callback")
	stale(7, 4)
	expect(h.records[1].damage == 0, "Reset cannot leave an active damage callback")
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

for _, mode in { "late", "sidestep", "noTicks" } do
	local h = harness(1)
	h.randomMinimum = true
	local waits = 0
	function h.onWait(_seconds, callback)
		waits += 1
		if waits == 1 then
			h.records[1].root.Position = if mode == "late"
				then roblox.Vector3.new(0, 4.5, 40)
				elseif mode == "sidestep" then roblox.Vector3.new(-21, 4.5, 0)
				else roblox.Vector3.new(0, 4.5, 0)
		elseif waits == 2 and mode == "late" then
			callback(6, 6)
			expect(h.records[1].damage == 0, "The wave has not reached the far edge yet")
			h.records[1].root.Position = roblox.Vector3.new(-21, 4.5, 40)
			callback(9, 3)
		elseif waits == 2 and mode == "sidestep" then
			callback(3.5, 3.5)
			expect(h.records[1].damage == 0, "Entering the moving plane through its gap is safe")
			h.records[1].root.Position = roblox.Vector3.new(0, 4.5, 0)
			callback(3.51, 0.01)
		end
		return waits < 3
	end
	expect(
		not h.rules.Run("ChangingWalls", h.context),
		"Focused wall regression cancels before the second pattern"
	)
	expect(
		h.records[1].damage == 65,
		"Late escape, overlapping sidestep and a whole-wave hitch cannot bypass the authoritative panel"
	)
	h.assertRestored()
	h.destroy()
	scenarios += 1
end

print(
	`ArenaRules offline integration: {checks} checks across {scenarios} scenarios; no native physics/render acceptance.`
)
