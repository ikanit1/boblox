--!strict
-- Runs the actual isolated host and Session/Math with bounded service/character adapters.
-- Position samples are scripted inputs, not native movement, physics or multiplayer evidence.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Math = require("../prototypes/shared/ExperimentMath")
local Session = require("../prototypes/server/ExperimentSession")
local V, CF = roblox.Vector3, roblox.CFrame
local checks, scenarios = 0, 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function signal()
	local entries = {}
	return {
		Connect = function(_, callback)
			local entry = { active = true, callback = callback }
			table.insert(entries, entry)
			return {
				Disconnect = function()
					entry.active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in table.clone(entries) do
				if entry.active then
					entry.callback(...)
				end
			end
		end,
		Count = function()
			local count = 0
			for _, entry in entries do
				if entry.active then
					count += 1
				end
			end
			return count
		end,
	}
end

local function harness(population: number, studio: boolean?, missingModule: boolean?)
	local h: any =
		{ now = 0, players = {}, sessions = {}, warnings = {}, prompts = {}, created = {}, nextId = 0 }
	local function object(className)
		local props: any = {
			Name = className,
			ClassName = className,
			Position = V.zero,
			CFrame = CF.new(),
			children = {},
			attributes = {},
			pivots = 0,
		}
		local methods: any = {}
		local item: any
		function methods:IsA(class)
			return class == className
				or (class == "BasePart" and (className == "Part" or className == "SpawnLocation"))
		end
		function methods:GetChildren()
			return table.clone(props.children)
		end
		function methods:FindFirstChild(name)
			for _, child in props.children do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function methods:FindFirstChildOfClass(class)
			for _, child in props.children do
				if child:IsA(class) then
					return child
				end
			end
			return nil
		end
		function methods:IsDescendantOf(ancestor)
			local current = props.Parent
			while current do
				if current == ancestor then
					return true
				end
				current = current.Parent
			end
			return false
		end
		function methods:SetAttribute(name, value)
			props.attributes[name] = value
		end
		function methods:GetAttribute(name)
			return props.attributes[name]
		end
		function methods:ClearAllChildren()
			for _, child in self:GetChildren() do
				child:Destroy()
			end
		end
		function methods:Destroy()
			self:ClearAllChildren()
			self.Parent = nil
			props.Destroyed = true
		end
		function methods:PivotTo(target)
			if props.failPivot then
				error("Injected unavailable character pivot")
			end
			local body = self:FindFirstChild("HumanoidRootPart")
			assert(body, "Cannot pivot an adapter without its root")
			props.pivots += 1
			body.CFrame = target
		end
		item = setmetatable({}, {
			__index = function(_, key)
				return methods[key] or props[key]
			end,
			__newindex = function(_, key, value)
				if key == "Parent" then
					if props.Parent then
						local old = table.find(props.Parent.children, item)
						if old then
							table.remove(props.Parent.children, old)
						end
					end
					props.Parent = value
					if value then
						table.insert(value.children, item)
					end
				elseif key == "CFrame" then
					props.CFrame, props.Position = value, value.Position
				elseif key == "Position" then
					props.Position, props.CFrame = value, CF.new(value)
				else
					props[key] = value
				end
			end,
		})
		if className == "ProximityPrompt" then
			item.Triggered = signal()
		end
		return item
	end
	h.workspace = object("Workspace")
	h.workspace.GetServerTimeNow = function()
		return h.now
	end
	h.state = object("Folder")
	local players = object("Players")
	players.PlayerRemoving = signal()
	players.GetPlayers = function()
		return table.clone(h.players)
	end
	h.playersService = players
	function h.character()
		local character = object("Model")
		character.Parent = h.workspace
		local humanoid = object("Humanoid")
		humanoid.Health, humanoid.Parent = 100, character
		local body = object("Part")
		body.Name, body.Parent = "HumanoidRootPart", character
		body.AssemblyLinearVelocity, body.AssemblyAngularVelocity = V.zero, V.zero
		return character, body, humanoid
	end
	function h.add()
		h.nextId += 1
		local player = object("Player")
		player.UserId, player.Parent = h.nextId, players
		local character, body, humanoid = h.character()
		player.Character = character
		body.Position = V.new(((h.nextId - 1) % 4 - 1.5) * 8, 5, 100 + math.floor((h.nextId - 1) / 4) * 5)
		table.insert(h.players, player)
		return player, body, humanoid
	end
	for _ = 1, population do
		h.add()
	end
	function h.body(player)
		return player.Character:FindFirstChild("HumanoidRootPart")
	end
	function h.move(player, point)
		h.body(player).Position = if typeof(point) == "Vector3"
			then point
			else V.new(point.X, point.Y, point.Z)
	end
	function h.remove(player)
		players.PlayerRemoving:Fire(player)
		player.Parent = nil
		table.remove(h.players, table.find(h.players, player))
	end
	local heartbeat = signal()
	h.heartbeat = heartbeat
	h.destroySignal = signal()
	local sessionAdapter = {
		new = function(...)
			if h.failConstructor then
				error("Injected Session.new failure")
			end
			local session = Session.new(...)
			local update, stop = session.Update, session.Stop
			session.Update = function(...)
				if h.failUpdate then
					error("Injected Session.Update failure")
				end
				return update(...)
			end
			session.Stop = function()
				if h.failStop then
					error("Injected Session.Stop failure")
				end
				return stop()
			end
			table.insert(h.sessions, session)
			return session
		end,
	}
	local services = {
		Players = players,
		ReplicatedStorage = { PrototypeShared = { ExperimentMath = Math }, PrototypeState = h.state },
		RunService = {
			Heartbeat = heartbeat,
			IsStudio = function()
				return studio ~= false
			end,
		},
	}
	local program = luau.load(fs.readFile("prototypes/server/Experiments.server.luau"), {
		debugName = "PRODUCTION_ExperimentalHost",
		environment = {
			game = {
				GetService = function(_, name)
					assert(
						services[name],
						"Prototype must not request production/network/profile services: " .. name
					)
					return services[name]
				end,
			},
			workspace = h.workspace,
			script = { Parent = { ExperimentSession = sessionAdapter }, Destroying = h.destroySignal },
			require = function(value)
				if missingModule then
					error("Injected missing experiment module")
				end
				return value
			end,
			Instance = {
				new = function(class)
					assert(
						table.find({ "Folder", "Part", "SpawnLocation", "ProximityPrompt" }, class),
						"No runtime remotes or rewards in the isolated host"
					)
					local instance = object(class)
					table.insert(h.created, instance)
					if class == "ProximityPrompt" then
						table.insert(h.prompts, instance)
					end
					return instance
				end,
			},
			Vector3 = V,
			CFrame = CF,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			warn = function(message)
				table.insert(h.warnings, message)
			end,
		},
	})
	h.loaded, h.loadError = pcall(program)
	function h.prompt(kind, player)
		local root = assert(h.workspace:FindFirstChild("IsolatedExperiments"))
		local console = assert(root:FindFirstChild(kind))
		console:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
	end
	function h.start(kind, player)
		local root = h.workspace:FindFirstChild("IsolatedExperiments")
		local console = root:FindFirstChild(kind)
		h.move(player, console.Position + V.new(0, 2, 3))
		h.prompt(kind, player)
	end
	function h.tick(dt)
		h.now += dt
		heartbeat:Fire(dt)
	end
	function h.untilCondition(condition, maximum)
		local deadline = h.now + (maximum or 55)
		local iterations = 0
		while not condition() and h.now < deadline do
			h.tick(0.05)
			iterations += 1
			assert(iterations <= 1200, "Host adapter exceeded bounded scheduler work")
		end
		assert(condition(), "Host failed to reach its bounded expected state")
	end
	function h.effects()
		local root = h.workspace:FindFirstChild("IsolatedExperiments")
		return root and root:FindFirstChild("TemporaryGeometry")
	end
	function h.stop()
		h.destroySignal:Fire()
		h.destroySignal:Fire()
		expect(
			heartbeat:Count() == 0 and players.PlayerRemoving:Count() == 0,
			"Host cleanup disconnects heartbeat and player departure"
		)
		for _, prompt in h.prompts do
			expect(prompt.Triggered:Count() == 0, "Host cleanup disconnects every prompt")
		end
		expect(
			h.workspace:FindFirstChild("IsolatedExperiments") == nil,
			"Host cleanup destroys its complete isolated geometry"
		)
	end
	function h.walk(player, point)
		local target = V.new(point.X, point.Y, point.Z)
		local steps = 0
		while (target - h.body(player).Position).Magnitude > 0.01 do
			local delta = target - h.body(player).Position
			h.move(player, h.body(player).Position + delta.Unit * math.min(delta.Magnitude, 16 * 0.05))
			h.tick(0.05)
			steps += 1
			assert(steps <= 300, "Scripted waypoint walk is bounded")
			assert(
				player:GetAttribute("PrototypeOutcome") == "Playing",
				"A valid scripted route was rejected"
			)
		end
	end
	return h
end

for _, studio in { false, true } do
	local h = harness(1, studio, studio)
	expect(
		not h.loaded and #h.created == 0,
		"Studio guard or missing module aborts before any host geometry is created"
	)
	expect(h.heartbeat:Count() == 0, "Failed initialization creates no repeating heartbeat")
	scenarios += 1
end

do
	local h = harness(13)
	assert(h.loaded, h.loadError)
	local first, overflow = h.players[1], h.players[13]
	h.start("PressureWave", first)
	expect(#h.sessions == 1, "Valid prompt creates exactly one real production session")
	local session = h.sessions[1]
	expect(session.Plan.Quarter == 1, "First pressure session uses a rotated layout")
	for index = 1, 12 do
		local player = h.players[index]
		local p = Math.localPoint(
			Math.point(h.body(player).Position.X, 5, h.body(player).Position.Z),
			session.Plan.Quarter
		)
		expect(
			p.Z >= 25
				and p.Z <= 35
				and Math.inside(Math.point(h.body(player).Position.X, 5, h.body(player).Position.Z)),
			"Pressure admission uses the current layout's safe local start side"
		)
		expect(
			player:GetAttribute("PrototypeOutcome") == "Playing",
			"Only admitted participants enter the experiment"
		)
	end
	expect(
		overflow:GetAttribute("PrototypeOutcome") == nil and session.Players[overflow.UserId] == nil,
		"Thirteenth player stays outside the bounded cohort"
	)
	h.tick(0.05)
	for _, child in h.effects():GetChildren() do
		if child.Name:sub(1, 5) == "Cover" then
			expect(
				not child.CanCollide and child.Transparency >= 0.6,
				"Warning cover is visibly ghosted and cannot push a player"
			)
		end
	end
	h.start("Stop", overflow)
	expect(
		h.state:GetAttribute("Stage") == "Stopped" and #h.effects():GetChildren() == 0,
		"Nearby lobby observer can stop and clear the experiment"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(5)
	local starter, high, below, dead, missing = table.unpack(h.players)
	h.move(starter, V.new(0, 5, 0))
	h.prompt("PressureWave", starter)
	expect(#h.sessions == 0, "A distant prompt cannot start an experiment")
	for _, position in { V.new(0 / 0, 5, 95), V.new(-20, math.huge, 95), V.new(-20, 5, -math.huge) } do
		h.move(starter, position)
		h.prompt("PressureWave", starter)
		expect(#h.sessions == 0, "Non-finite root proximity cannot trigger an experiment")
	end
	local departed = h.add()
	h.move(departed, V.new(-20, 5, 95))
	h.remove(departed)
	h.prompt("PressureWave", departed)
	expect(#h.sessions == 0, "A departed identity cannot trigger a nearby prompt")
	h.move(high, V.new(0, 500, 100))
	h.move(below, V.new(0, -20, 100))
	dead.Character:FindFirstChildOfClass("Humanoid").Health = 0
	h.body(missing).Parent = nil
	h.start("PressureWave", starter)
	local count = 0
	for _ in h.sessions[1].Players do
		count += 1
	end
	expect(count == 1, "Admission excludes above/below-lobby, dead and missing-root characters")
	local late = h.add()
	h.start("ChangingWalls", late)
	expect(
		#h.sessions == 1 and h.sessions[1].Players[late.UserId] == nil,
		"A late prompt cannot add participants or replace an active session"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	local player = h.players[1]
	h.failConstructor = true
	h.start("PressureWave", player)
	expect(
		#h.sessions == 0 and #h.warnings == 1 and #h.effects():GetChildren() == 0,
		"Constructor failure is contained before admission or geometry commits"
	)
	expect(
		player:GetAttribute("PrototypeOutcome") == nil and player.Character.pivots == 0,
		"Failed constructor leaves the character untouched"
	)
	h.failConstructor = false
	h.start("PressureWave", player)
	expect(
		#h.sessions == 1 and player:GetAttribute("PrototypeOutcome") == "Playing",
		"Clean retry succeeds after a constructor failure"
	)
	h.failUpdate, h.failStop = true, true
	h.tick(0.05)
	expect(
		h.state:GetAttribute("Stage") == "Stopped" and #h.effects():GetChildren() == 0,
		"Update and Stop failures cannot leave active geometry or a stuck experiment"
	)
	expect(
		player:GetAttribute("PrototypeOutcome") == "Stopped" and h.body(player).Position.Z > 82,
		"Failure cleanup restores an admitted player to the laboratory"
	)
	h.failUpdate, h.failStop = false, false
	h.start("ChangingWalls", player)
	h.tick(0.05)
	expect(
		#h.sessions == 2 and h.state:GetAttribute("Stage") == "Warning",
		"Host accepts another valid experiment after module faults"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(2)
	local failing, healthy = h.players[1], h.players[2]
	failing.Character.failPivot = true
	h.start("PressureWave", failing)
	expect(
		h.state:GetAttribute("Stage") == "Stopped" and #h.effects():GetChildren() == 0,
		"Failed admission pivot stops the partially admitted cohort safely"
	)
	expect(
		healthy:GetAttribute("PrototypeOutcome") == "Stopped",
		"One unavailable character does not prevent cleanup of other entrants"
	)
	failing.Character.failPivot = false
	h.start("PressureWave", healthy)
	expect(#h.sessions == 2, "Unavailable character cleanup does not keep the active-session lock")
	h.stop()
	scenarios += 1
end

for _, termination in { "Death", "MissingRoot", "Respawn", "Leave", "Destroy" } do
	local h = harness(1)
	local player = h.players[1]
	h.start("PressureWave", player)
	h.tick(0.05)
	local original = player.Character
	local replacement = nil
	if termination == "Death" then
		player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	elseif termination == "MissingRoot" then
		h.body(player).Parent = nil
	elseif termination == "Respawn" then
		local character, body = h.character()
		body.Position = V.new(10, 5, 108)
		player.Character, replacement = character, character
	elseif termination == "Leave" then
		h.remove(player)
	else
		h.destroySignal:Fire()
	end
	if termination ~= "Destroy" then
		h.tick(0.05)
		expect(
			h.state:GetAttribute("Stage") == "Finished" and #h.effects():GetChildren() == 0,
			"Experiment terminates and clears transient geometry after " .. termination
		)
	end
	if replacement then
		expect(
			replacement.pivots == 0 and original.pivots == 1,
			"Failed old admission never teleports a replacement character"
		)
	end
	h.stop()
	scenarios += 1
end

do
	local h = harness(2)
	local overlap, safe = h.players[1], h.players[2]
	h.start("PressureWave", overlap)
	h.tick(0.05)
	local plan = h.sessions[1].Plan
	h.move(overlap, Math.worldPoint(Math.point(0, 5, Math.CoverZ), plan.Quarter))
	h.move(safe, Math.worldPoint(Math.point(0, 5, 25), plan.Quarter))
	local safePosition, safePivots = h.body(safe).Position, safe.Character.pivots
	h.untilCondition(function()
		return h.state:GetAttribute("Stage") == "Active"
	end, 6)
	expect(
		overlap:GetAttribute("PrototypeOutcome") == "Failed" and h.body(overlap).Position.Z > 82,
		"Overlapping preview camper is removed before cover collision activates"
	)
	expect(
		safe:GetAttribute("PrototypeOutcome") == "Playing"
			and safe.Character.pivots == safePivots
			and h.body(safe).Position == safePosition,
		"Safe pressure participant is not teleported or reset at activation"
	)
	for _, child in h.effects():GetChildren() do
		if child.Name:sub(1, 5) == "Cover" then
			expect(child.CanCollide, "Only active, cleared cover geometry becomes solid")
		end
	end
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	local player = h.players[1]
	h.start("PressureWave", player)
	h.tick(0.05)
	local firstPlan = h.sessions[1].Plan
	-- This valid first-wave shelter becomes the exact second-wave cover footprint.
	h.move(player, Math.worldPoint(Math.point(6, 5, 12), firstPlan.Quarter))
	h.untilCondition(function()
		return h.state:GetAttribute("Stage") == "Warning" and h.state:GetAttribute("Beat") == 2
	end, 14)
	local previewPosition, pivots = h.body(player).Position, player.Character.pivots
	expect(
		player:GetAttribute("PrototypeOutcome") == "Playing",
		"The first wave legitimately passed before the opposite layout"
	)
	for _, child in h.effects():GetChildren() do
		if child.Name:sub(1, 5) == "Cover" then
			expect(
				not child.CanCollide,
				"Opposite cover remains ghosted around the prior-wave position during warning"
			)
		end
	end
	h.tick(0.05)
	expect(
		h.body(player).Position == previewPosition and player.Character.pivots == pivots,
		"Warning flip does not physically move or teleport the camper"
	)
	h.untilCondition(function()
		return h.state:GetAttribute("Stage") == "Finished"
	end, 6)
	expect(
		player:GetAttribute("PrototypeOutcome") == "Failed" and #h.effects():GetChildren() == 0,
		"Remaining inside the new cover fails cleanly before solid geometry exists"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(2)
	local failed, survivor = h.players[1], h.players[2]
	h.start("PressureWave", failed)
	h.tick(0.05)
	local plan = h.sessions[1].Plan
	h.move(failed, Math.worldPoint(Math.point(14, 5, 25), plan.Quarter))
	h.move(survivor, Math.worldPoint(Math.point(0, 5, 25), plan.Quarter))
	h.untilCondition(function()
		return failed:GetAttribute("PrototypeOutcome") == "Failed"
	end, 12)
	local failedPivots = failed.Character.pivots
	local chosenLobbyPosition = h.body(failed).Position + V.new(4, 0, 0)
	h.move(failed, chosenLobbyPosition)
	h.untilCondition(function()
		return h.state:GetAttribute("Stage") == "Warning" and h.state:GetAttribute("Beat") == 2
	end, 4)
	local nextPlan = h.sessions[1].Plan
	h.move(survivor, Math.worldPoint(Math.point(nextPlan.Covers[1], 5, 25), nextPlan.Quarter))
	h.untilCondition(function()
		return h.state:GetAttribute("Stage") == "Finished"
	end, 12)
	expect(
		survivor:GetAttribute("PrototypeOutcome") == "Passed",
		"Real Session/host pass both pressure waves from safe scripted positions"
	)
	expect(
		failed.Character.pivots == failedPivots and h.body(failed).Position == chosenLobbyPosition,
		"Experiment completion does not teleport a previously returned participant again"
	)
	expect(
		#h.effects():GetChildren() == 0 and h.state:GetAttribute("EndsAt") == 0,
		"Successful pressure completion clears effects and deadline"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	local player = h.players[1]
	h.start("ChangingWalls", player)
	for beat = 1, 2 do
		h.untilCondition(function()
			return h.state:GetAttribute("Stage") == "Warning" and h.state:GetAttribute("Beat") == beat
		end, 20)
		for _, child in h.effects():GetChildren() do
			if child.Name:find("Wall", 1, true) then
				expect(
					not child.CanCollide and child.Size.X > 0,
					"Route preview walls are noncolliding positive geometry"
				)
			elseif child.Name:sub(1, 7) == "Opening" then
				expect(
					child.Size.X == 14,
					"Visible opening marks body-safe centre space, not the full collision gap"
				)
			end
		end
		h.move(player, Math.worldPoint(Math.point(0, 5, 35), h.sessions[1].Plan.Quarter))
		h.body(player).AssemblyLinearVelocity = V.new(50, 0, 0)
		h.untilCondition(function()
			return h.state:GetAttribute("Stage") == "Active"
		end, 6)
		local plan = h.sessions[1].Plan
		local startPoint =
			Math.localPoint(Math.point(h.body(player).Position.X, 5, h.body(player).Position.Z), plan.Quarter)
		expect(
			startPoint.Z == -36 and h.body(player).AssemblyLinearVelocity == V.zero,
			"Each timed leg resets the actual start line and prior velocity after preview"
		)
		for _, point in Math.route(plan) do
			h.walk(player, point)
		end
		expect(
			h.sessions[1].Players[player.UserId].Gate == 2,
			"Scripted walking crosses both actual gate checks in order"
		)
		if beat == 1 then
			h.untilCondition(function()
				return h.state:GetAttribute("Stage") == "Recovery"
			end, 16)
		else
			h.untilCondition(function()
				return h.state:GetAttribute("Stage") == "Finished"
			end, 16)
		end
	end
	expect(
		player:GetAttribute("PrototypeOutcome") == "Passed" and #h.effects():GetChildren() == 0,
		"Both changing-wall legs pass through production host/session without leftover walls"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	local player = h.players[1]
	local observer = h.add()
	h.move(observer, V.new(0, 50, 100))
	local baseline = #h.workspace:FindFirstChild("IsolatedExperiments"):GetChildren()
	for index = 1, 20 do
		h.move(observer, V.new(0, 50, 100))
		h.start(if index % 2 == 0 then "PressureWave" else "ChangingWalls", player)
		h.tick(0.05)
		h.start("Stop", observer)
		expect(
			#h.effects():GetChildren() == 0
				and #h.workspace:FindFirstChild("IsolatedExperiments"):GetChildren() == baseline,
			"Repeated start/stop retains only fixed scene geometry"
		)
		expect(
			h.heartbeat:Count() == 1 and h.playersService.PlayerRemoving:Count() == 1,
			"Repeated experiments reuse bounded host subscriptions"
		)
	end
	h.stop()
	scenarios += 1
end

do
	local h = harness(12)
	h.start("PressureWave", h.players[1])
	for beat = 1, 2 do
		h.untilCondition(function()
			return h.state:GetAttribute("Stage") == "Warning" and h.state:GetAttribute("Beat") == beat
		end, 15)
		local plan = h.sessions[1].Plan
		for index, player in h.players do
			local coverIndex = math.floor((index - 1) / 2) % #plan.Covers + 1
			local x = plan.Covers[coverIndex] + (if index % 2 == 0 then 3 else -3)
			local z = 10 + math.floor((index - 1) / (#plan.Covers * 2)) * 5
			h.move(player, Math.worldPoint(Math.point(x, 5, z), plan.Quarter))
		end
		expect(
			#h.effects():GetChildren() <= 7,
			"Pressure preview keeps a fixed small geometry budget for twelve adapters"
		)
		if beat == 1 then
			h.untilCondition(function()
				return h.state:GetAttribute("Stage") == "Recovery"
			end, 12)
		else
			h.untilCondition(function()
				return h.state:GetAttribute("Stage") == "Finished"
			end, 12)
		end
	end
	for _, player in h.players do
		expect(
			player:GetAttribute("PrototypeOutcome") == "Passed" and h.body(player).Position.Z >= 82,
			"Each of twelve scripted participants completes both pressure decisions and returns"
		)
	end
	expect(#h.effects():GetChildren() == 0, "Twelve-participant completion leaves no transient geometry")
	h.stop()
	scenarios += 1
end

print(
	"ExperimentHost integration: "
		.. checks
		.. " checks across "
		.. scenarios
		.. " scenarios (local host adapters)"
)
