--!strict
-- Executes the complete production Main script with a bounded virtual scheduler.
-- Services, roster rewards and hazard simulation are adapters; this is not native multiplayer.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local RuleDeck = require("../src/shared/RuleDeck")
local RuleAvailability = require("../src/server/RuleAvailability")
local checks, scenarios = 0, 0
local function expect(value: boolean, message: string)
	assert(value, message)
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

local function attributes(initial)
	local values, signals = initial or {}, {}
	local object: any = {}
	function object:GetAttribute(name)
		return values[name]
	end
	function object:GetAttributes()
		return table.clone(values)
	end
	function object:GetAttributeChangedSignal(name)
		if not signals[name] then
			signals[name] = signal()
		end
		return signals[name]
	end
	function object:SetAttribute(name, value)
		if values[name] == value then
			return
		end
		values[name] = value
		if signals[name] then
			signals[name]:Fire()
		end
	end
	return object
end

local function harness(population: number, controlAttributes: any?)
	local h: any = {
		now = 0,
		nextId = 0,
		players = {},
		phases = {},
		begins = {},
		awards = {},
		completions = {},
		restores = 0,
		warnings = {},
		attempts = 0,
	}
	h.state = attributes()
	local function controls(initial)
		local object = attributes(initial)
		function object:IsA(name)
			return name == (h.controlClass or "Folder")
		end
		return object
	end
	if controlAttributes ~= false then
		h.controls = controls(controlAttributes)
	end
	local serverStorage = {
		FindFirstChild = function(_, name)
			assert(name == "RuleRoomControls", "Main reads only the server release controls")
			return h.controls
		end,
	}
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), RespawnTime = 7 }
	function players:GetPlayers()
		return table.clone(h.players)
	end
	h.playersService = players
	function h.add(queued: boolean?)
		h.nextId += 1
		local player = attributes({ EntryChoiceMade = queued ~= false, LobbyOnly = queued == false })
		player.UserId, player.Parent, player.ready, player.characterReady = h.nextId, players, true, true
		table.insert(h.players, player)
		players.PlayerAdded:Fire(player)
		return player
	end
	function h.remove(player)
		player.Parent = nil
		local index = table.find(h.players, player)
		if index then
			table.remove(h.players, index)
		end
		players.PlayerRemoving:Fire(player)
	end
	for _ = 1, population do
		h.add()
	end
	local config =
		luau.load(fs.readFile("src/shared/GameConfig.luau"), { environment = { Color3 = roblox.Color3 } })()
	h.config = config
	local active = {}
	local roster = {}
	function roster.AliveCount()
		local count = 0
		for player in active do
			if player.Parent == players and not player.dead then
				count += 1
			end
		end
		return count
	end
	function roster.EndRound()
		for player in active do
			player:SetAttribute("InRound", false)
		end
		table.clear(active)
	end
	function roster.PrepareIntermission() end
	function roster.BeginRun(deck)
		table.insert(h.begins, { round = h.state:GetAttribute("Round"), deck = table.clone(deck) })
	end
	function roster.StartRound(_, index, ruleId)
		h.attempts += 1
		assert(next(active) == nil, "Main ends participation before every admission pass")
		for _, player in h.players do
			if
				player.ready
				and player.characterReady
				and player:GetAttribute("EntryChoiceMade") == true
				and player:GetAttribute("LobbyOnly") ~= true
			then
				active[player] = true
				player.dead = false
				player:SetAttribute("InRound", true)
			end
		end
		h.lastAdmission = { index = index, rule = ruleId }
		return roster.AliveCount()
	end
	function roster.CheckBoundaries()
		h.boundaryChecks = (h.boundaryChecks or 0) + 1
	end
	function roster.AwardSurvivors(ruleId)
		table.insert(h.awards, {
			round = h.state:GetAttribute("Round"),
			index = h.state:GetAttribute("RuleIndex"),
			rule = ruleId,
			alive = roster.AliveCount(),
		})
		return roster.AliveCount(), 0
	end
	function roster.CompleteRun(teamSuccess, aborted)
		table.insert(
			h.completions,
			{ round = h.state:GetAttribute("Round"), success = teamSuccess, aborted = aborted }
		)
		return if teamSuccess then #h.players else 0
	end
	function roster.Contributions(round)
		assert(
			h.completions[#h.completions].round == round,
			"Contribution snapshot follows completion of the same run"
		)
		h.snapshotRounds = h.snapshotRounds or {}
		table.insert(h.snapshotRounds, round)
		return serde.encode("json", { Version = 1, Round = round, Players = {}, Truncated = false })
	end
	function roster.Destroy()
		h.rosterDestroyed = (h.rosterDestroyed or 0) + 1
		roster.EndRound()
	end
	local profiles = {
		IsReady = function(player)
			return player.ready
		end,
		Destroy = function()
			h.profilesDestroyed = (h.profilesDestroyed or 0) + 1
		end,
	}
	local world = { LobbySpawn = roblox.CFrame.new(0, 4, 158), ArenaSpawn = roblox.CFrame.new(0, 5, 0) }
	function world.Restore()
		h.restores += 1
	end
	function world.Run(ruleId, context)
		if h.failRule then
			error("Injected hazard failure")
		end
		if h.ruleBehavior then
			return h.ruleBehavior(ruleId, context)
		end
		local completed = context.waitFor(0.25, function()
			h.updates = (h.updates or 0) + 1
		end)
		if ruleId == "ReactorRush" then
			h.state:SetAttribute("TeamGoal", 5)
			h.state:SetAttribute("TeamCharge", 5)
			h.state:SetAttribute("FinaleSuccess", completed)
		end
		return completed
	end
	local arena = {
		IsA = function(_, name)
			return name == "Model"
		end,
	}
	local workspace = {
		WaitForChild = function(_, name)
			assert(name == "Arena", "Main requests the authored arena")
			return arena
		end,
		GetServerTimeNow = function()
			return h.now
		end,
	}
	local shared = {
		WaitForChild = function(_, name)
			assert(name == "GameConfig" or name == "RuleDeck", "Main requests known shared modules")
			return if name == "GameConfig" then config else RuleDeck
		end,
	}
	h.vote = { OnServerEvent = signal() }
	local remotes = {
		WaitForChild = function(_, name)
			assert(name == "Vote", "Main only handles the vote remote")
			return h.vote
		end,
	}
	local storage = {
		WaitForChild = function(_, name)
			local children = { RuleRoomShared = shared, RuleRoomState = h.state, RuleRoomRemotes = remotes }
			assert(children[name], name)
			return children[name]
		end,
	}
	local script = {
		Destroying = signal(),
		Parent = {
			RuleAvailability = RuleAvailability,
			ArenaRules = {
				new = function()
					return world
				end,
			},
			PlayerRoster = {
				new = function()
					return roster
				end,
			},
			ProfileService = {
				new = function()
					return profiles
				end,
			},
		},
	}
	h.script = script
	h.state:GetAttributeChangedSignal("Phase"):Connect(function()
		table.insert(
			h.phases,
			{ phase = h.state:GetAttribute("Phase"), round = h.state:GetAttribute("Round"), at = h.now }
		)
	end)
	local program = luau.load(fs.readFile("src/server/Main.server.luau"), {
		debugName = "PRODUCTION_MainLifecycle",
		environment = {
			game = {
				GetService = function(_, name)
					local services = {
						Players = players,
						ReplicatedStorage = storage,
						ServerStorage = serverStorage,
						Workspace = workspace,
					}
					assert(services[name], name)
					return services[name]
				end,
				BindToClose = function(_, callback)
					h.close = callback
				end,
			},
			script = script,
			require = function(value)
				return value
			end,
			Color3 = roblox.Color3,
			Instance = {
				new = function(name)
					assert(name == "Folder", "Main creates only the server control folder")
					h.controls = controls({})
					return h.controls
				end,
			},
			Random = {
				new = function()
					return {
						NextInteger = function(_, minimum)
							return minimum
						end,
					}
				end,
			},
			os = {
				clock = function()
					return h.now
				end,
			},
			task = {
				wait = function(seconds)
					return coroutine.yield(seconds or 0.03)
				end,
			},
			warn = function(message)
				table.insert(h.warnings, tostring(message))
			end,
		},
	})
	local thread = coroutine.create(program)
	function h.step()
		assert(coroutine.status(thread) ~= "dead", "Cannot advance a stopped Main")
		local ok, seconds = coroutine.resume(thread)
		assert(ok, tostring(seconds))
		if coroutine.status(thread) ~= "dead" then
			assert(
				type(seconds) == "number" and seconds > 0,
				"Every suspension must have a positive bounded wait"
			)
			h.now += seconds
		end
	end
	function h.untilCondition(predicate)
		for _ = 1, 10000 do
			if predicate() then
				return
			end
			h.step()
		end
		error("Main exceeded bounded scheduler budget")
	end
	function h.advance(seconds)
		local target = h.now + seconds
		h.untilCondition(function()
			return h.now >= target
		end)
	end
	function h.phase(name)
		h.untilCondition(function()
			return h.state:GetAttribute("Phase") == name
		end)
	end
	function h.stop()
		script.Destroying:Fire()
		h.close()
		h.untilCondition(function()
			return coroutine.status(thread) == "dead"
		end)
		expect(
			h.profilesDestroyed == 1 and h.rosterDestroyed == 1,
			"Repeated shutdown cleans services exactly once"
		)
		expect(players.RespawnTime == 7, "Shutdown restores respawn policy")
		expect(
			h.vote.OnServerEvent.Count() == 0
				and players.PlayerRemoving.Count() == 0
				and players.PlayerAdded.Count() == 0,
			"Shutdown disconnects service observers"
		)
		for _, player in h.players do
			expect(
				player:GetAttributeChangedSignal("LobbyOnly").Count() == 0,
				"Shutdown disconnects each queue observer"
			)
		end
	end
	h.step()
	return h
end

do
	local h = harness(2)
	local a, b = h.players[1], h.players[2]
	expect(h.state:GetAttribute("Phase") == "Voting", "Queued players enter voting")
	h.vote.OnServerEvent:Fire(a, "Balanced")
	expect(
		h.state:GetAttribute("VotesBalanced") == 1 and a:GetAttribute("VotedMode") == "Balanced",
		"Accepted vote is confirmed by server attributes"
	)
	h.vote.OnServerEvent:Fire(a, "Cosmic")
	expect(h.state:GetAttribute("VotesCosmic") == 0, "Immediate repeat vote is rate limited")
	h.advance(h.config.VoteCooldown + 0.05)
	h.vote.OnServerEvent:Fire(a, "Cosmic")
	expect(
		h.state:GetAttribute("VotesCosmic") == 1 and h.state:GetAttribute("VotesBalanced") == 0,
		"Replacement moves one vote, never duplicates it"
	)
	for _, invalid in { false, 42, 0 / 0, {}, "Unknown", string.rep("x", 2000) } do
		h.advance(h.config.VoteCooldown + 0.05)
		h.vote.OnServerEvent:Fire(a, invalid)
		expect(
			h.state:GetAttribute("VotesCosmic") == 1 and a:GetAttribute("VotedMode") == "Cosmic",
			"Malformed vote cannot replace an accepted vote"
		)
	end
	for _, reason in { "Loading", "Explorer", "Unconfirmed" } do
		h.advance(h.config.VoteCooldown + 0.05)
		b.ready = reason ~= "Loading"
		b:SetAttribute("LobbyOnly", reason == "Explorer")
		b:SetAttribute("EntryChoiceMade", reason ~= "Unconfirmed")
		h.vote.OnServerEvent:Fire(b, "Reflex")
		expect(h.state:GetAttribute("VotesReflex") == 0, "Ineligible vote rejected: " .. reason)
	end
	a:SetAttribute("LobbyOnly", true)
	expect(h.state:GetAttribute("VotesCosmic") == 0, "Exploring immediately removes prior vote")
	a:SetAttribute("LobbyOnly", false)
	h.advance(h.config.VoteCooldown + 0.05)
	h.vote.OnServerEvent:Fire(a, "Reflex")
	h.remove(a)
	expect(h.state:GetAttribute("VotesReflex") == 0, "Leaving removes prior vote")
	b.ready = true
	b:SetAttribute("LobbyOnly", false)
	b:SetAttribute("EntryChoiceMade", true)
	h.phase("Rule")
	h.vote.OnServerEvent:Fire(b, "Balanced")
	expect(h.state:GetAttribute("VotesBalanced") == 0, "Vote outside Voting is ignored")
	h.stop()
	scenarios += 1
end

for _, phase in { "Voting", "Rule", "Break", "Results" } do
	local h = harness(1)
	h.phase(phase)
	h.remove(h.players[1])
	h.phase("Waiting")
	local starts, completions = #h.begins, #h.completions
	h.advance(2)
	expect(
		#h.begins == starts and #h.completions == completions,
		"Empty server does not produce runs or completions from " .. phase
	)
	local newcomer = h.add()
	h.phase("Voting")
	expect(
		newcomer:GetAttribute("VotedMode") == "" and h.state:GetAttribute("VotesBalanced") == 0,
		"Returning player gets a clean voting cycle"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(2)
	h.untilCondition(function()
		return #h.completions == 2
	end)
	expect(#h.begins == 2 and #h.awards == 12, "Two full runs execute exactly twelve trial awards")
	local seen = {}
	for _, award in h.awards do
		local key = tostring(award.round) .. ":" .. award.index
		expect(not seen[key] and award.alive == 2, "Each run/trial is awarded once for the admitted adapters")
		seen[key] = true
	end
	for index, result in h.completions do
		expect(
			result.round == index and result.success and not result.aborted,
			"Complete run publishes one successful completion"
		)
	end
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.players[1].characterReady = false
	h.untilCondition(function()
		return h.attempts >= 3
	end)
	expect(
		#h.begins == 1 and #h.awards == 0 and #h.completions == 0,
		"Delayed character waits without awards or repeated run creation"
	)
	h.players[1].characterReady = true
	h.phase("Rule")
	expect(
		h.state:GetAttribute("RuleIndex") == 1,
		"Delayed character enters first hazard at an admission boundary"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.failRule = true
	h.phase("Results")
	expect(
		#h.warnings == 1 and string.find(h.warnings[1], "Injected hazard failure", 1, true) ~= nil,
		"Hazard error is reported rather than swallowed"
	)
	expect(
		#h.completions == 1 and h.completions[1].aborted and not h.completions[1].success,
		"Failed run receives only an aborted completion"
	)
	expect(#h.awards == 0 and h.restores >= 3, "Failed hazard awards nobody and restores the arena")
	h.failRule = false
	h.untilCondition(function()
		return #h.completions == 2
	end)
	expect(
		not h.completions[2].aborted and h.completions[2].success,
		"The next run recovers after a rule exception"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.phase("Rule")
	h.players[1].dead = true
	h.phase("Break")
	expect(#h.awards == 0, "No survival award when the active trial loses its last alive participant")
	h.untilCondition(function()
		return #h.completions == 1
	end)
	expect(
		#h.awards == 5 and not h.completions[1].aborted,
		"A lost trial still permits the remaining five trials"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.phase("Rule")
	local deadline = h.state:GetAttribute("PhaseEndsAt")
	expect(deadline > h.now, "Main publishes a future deadline before the active wait")
	local updates = h.updates or 0
	h.now = deadline
	h.step()
	expect((h.updates or 0) == updates, "No hazard callback executes at or beyond the deadline")
	expect(#h.awards == 1, "Completion awards once at the server deadline")
	h.stop()
	scenarios += 1
end

-- Every ordinary rule can be removed independently without changing the six-trial contract.
for _, disabledId in
	{
		"SafeColor",
		"LaserSweep",
		"LowGravity",
		"RedLight",
		"LavaRise",
		"MeteorRain",
		"DisappearingTiles",
		"SafeZone",
		"Spinner",
	}
do
	local h = harness(1, { ["Disabled_" .. disabledId] = true })
	h.phase("Rule")
	local deck = h.begins[1].deck
	expect(#deck == 6 and deck[6] == "ReactorRush", "Single disable retains five trials and mandatory finale")
	expect(
		table.find(deck, disabledId) == nil,
		"Disabled rule cannot enter a newly admitted run: " .. disabledId
	)
	expect(h.state:GetAttribute("RunsPaused") == false, "Legal single-disable configuration remains playable")
	h.stop()
	scenarios += 1
end

for _, case in
	{
		{ reason = "FinaleDisabled", flags = { Disabled_ReactorRush = true } },
		{
			reason = "NotEnoughRules",
			flags = {
				Disabled_PressureWave = true,
				Disabled_ChangingWalls = true,
				Disabled_SafeColor = true,
				Disabled_LaserSweep = true,
				Disabled_LowGravity = true,
				Disabled_RedLight = true,
				Disabled_LavaRise = true,
			},
		},
		{
			reason = "NoReadableFirst",
			flags = { Disabled_SafeColor = true, Disabled_LowGravity = true, Disabled_SafeZone = true },
		},
		{
			reason = "NoLegalDeck",
			flags = {
				Disabled_PressureWave = true,
				Disabled_ChangingWalls = true,
				Disabled_SafeColor = true,
				Disabled_LavaRise = true,
				Disabled_DisappearingTiles = true,
				Disabled_SafeZone = true,
			},
		},
		{ reason = "InvalidFlag", flags = { Disabled_Spinner = "true" } },
	}
do
	local h = harness(1, case.flags)
	expect(h.state:GetAttribute("Phase") == "Waiting", "Invalid configuration enters Waiting before Voting")
	expect(
		h.state:GetAttribute("RunsPaused") == true and h.state:GetAttribute("RunPauseReason") == case.reason,
		"Pause publishes a bounded diagnostic reason: " .. case.reason
	)
	expect(
		string.find(h.state:GetAttribute("Instruction"), "исследовать", 1, true) ~= nil,
		"Pause gives a player-readable alternative"
	)
	h.advance(30)
	expect(
		#h.begins == 0 and #h.awards == 0 and #h.completions == 0 and h.state:GetAttribute("Round") == 0,
		"An invalid configuration never starts a ledger or grants rewards"
	)
	local voting = 0
	for _, entry in h.phases do
		if entry.phase == "Voting" then
			voting += 1
		end
	end
	expect(voting == 0, "Paused configuration does not spam Voting cycles")
	for name in h.controls:GetAttributes() do
		h.controls:SetAttribute(name, false)
	end
	h.phase("Voting")
	expect(
		h.state:GetAttribute("RunsPaused") == false and h.state:GetAttribute("RunPauseReason") == "",
		"Correcting controls resumes normal Voting without restarting the server"
	)
	h.phase("Rule")
	expect(
		#h.begins == 1 and h.state:GetAttribute("Round") == 1,
		"First recovered run receives the first ledger"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1, false)
	expect(
		h.controls:IsA("Folder") and h.controls.Name == "RuleRoomControls",
		"Missing controls are created server-side"
	)
	for _, ruleId in h.config.RuleOrder do
		expect(
			h.controls:GetAttribute("Disabled_" .. ruleId) == false,
			"New controls default to enabled: " .. ruleId
		)
	end
	h.controls:SetAttribute("Disabled_ArbitraryCode", true)
	h.phase("Rule")
	expect(
		#h.begins == 1 and #h.begins[1].deck == 6,
		"Unknown flags cannot create a rule or block a valid deck"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.controlClass = "Part"
	h.untilCondition(function()
		return h.state:GetAttribute("RunsPaused") == true
	end)
	expect(
		h.state:GetAttribute("RunPauseReason") == "InvalidControls" and #h.begins == 0,
		"A wrongly typed controls instance fails closed at the final snapshot"
	)
	h.controlClass = "Folder"
	h.phase("Rule")
	expect(#h.begins == 1, "Replacing invalid controls allows a safe run")
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.controls:SetAttribute("Disabled_ReactorRush", true)
	h.untilCondition(function()
		return h.state:GetAttribute("RunsPaused") == true
	end)
	expect(
		#h.begins == 0 and h.state:GetAttribute("Round") == 0,
		"A disable accepted during Voting is rechecked before the run ledger starts"
	)
	h.remove(h.players[1])
	h.advance(2)
	expect(#h.begins == 0 and #h.completions == 0, "Paused empty server never creates a completion")
	h.controls:SetAttribute("Disabled_ReactorRush", false)
	h.add()
	h.phase("Rule")
	expect(#h.begins == 1, "New arrival can start after the paused empty server recovers")
	h.stop()
	scenarios += 1
end

do
	local h = harness(1)
	h.phase("Rule")
	local firstDeck = table.clone(h.begins[1].deck)
	local disabledId = firstDeck[2]
	h.controls:SetAttribute("Disabled_" .. disabledId, true)
	h.controls:SetAttribute("Disabled_ReactorRush", true)
	h.phase("Results")
	expect(
		#h.awards == 6 and #h.completions == 1 and h.completions[1].success,
		"A flag change cannot truncate an active run or steal its earned completion"
	)
	for index, award in h.awards do
		expect(award.rule == firstDeck[index], "Active run keeps its admitted deck order")
	end
	h.untilCondition(function()
		return h.state:GetAttribute("RunsPaused") == true
	end)
	expect(#h.begins == 1 and #h.completions == 1, "Finale disable pauses only the following run")
	h.advance(10)
	expect(#h.awards == 6 and #h.begins == 1, "Paused state adds no awards or repeated ledgers")
	h.controls:SetAttribute("Disabled_ReactorRush", false)
	h.phase("Rule")
	expect(
		#h.begins == 2 and table.find(h.begins[2].deck, disabledId) == nil,
		"Recovered next run respects ordinary disable while preserving mandatory finale"
	)
	h.stop()
	scenarios += 1
end

do
	local h = harness(1, { Disabled_ReactorRush = true })
	h.advance(1)
	h.stop()
	scenarios += 1
end

do
	local h = harness(2, { Disabled_ReactorRush = true })
	expect(h.state:GetAttribute("RunsPaused") == true, "Finale disable initially pauses queued players")
	for _, player in h.players do
		player:SetAttribute("LobbyOnly", true)
	end
	h.advance(1)
	expect(
		#h.players == 2 and #h.begins == 0 and h.state:GetAttribute("Phase") == "Waiting",
		"Explore empties the queue without disconnecting either player"
	)
	h.controls:SetAttribute("Disabled_ReactorRush", false)
	h.advance(1)
	expect(
		h.state:GetAttribute("RunsPaused") == false
			and h.state:GetAttribute("RunPauseReason") == ""
			and h.state:GetAttribute("RuleName") == "ЛАБОРАТОРИЯ ОТКРЫТА",
		"Restored controls clear the paused diagnostic while every player remains in Explore"
	)
	expect(
		#h.begins == 0 and #h.completions == 0,
		"Empty-queue control refresh cannot start or complete a run"
	)
	h.controls:SetAttribute("Disabled_Spinner", "invalid")
	h.advance(1)
	expect(
		h.state:GetAttribute("RunsPaused") == true and h.state:GetAttribute("RunPauseReason") == "InvalidFlag",
		"A newly invalid setting also updates while the queue stays empty"
	)
	h.controls:SetAttribute("Disabled_Spinner", false)
	h.advance(1)
	expect(
		h.state:GetAttribute("RunsPaused") == false and h.state:GetAttribute("RunPauseReason") == "",
		"Repeated empty-queue recovery leaves no stale reason"
	)
	h.players[1]:SetAttribute("LobbyOnly", false)
	h.phase("Rule")
	expect(
		#h.players == 2 and #h.begins == 1 and #h.completions == 0,
		"The same player requeues and starts one recovered run without a rejoin"
	)
	h.stop()
	scenarios += 1
end

for _, aborted in { false, true } do
	local h = harness(1)
	h.failRule = aborted
	local publications = {}
	h.state:GetAttributeChangedSignal("ContributionsJson"):Connect(function()
		local encoded = h.state:GetAttribute("ContributionsJson")
		if encoded ~= "" then
			local snapshot = serde.decode("json", encoded)
			table.insert(publications, {
				round = snapshot.Round,
				barrier = h.state:GetAttribute("ContributionsRound"),
				stateRound = h.state:GetAttribute("Round"),
				phase = h.state:GetAttribute("Phase"),
				completions = #h.completions,
			})
		end
	end)
	h.phase("Results")
	expect(
		#publications == 1 and #h.snapshotRounds == 1,
		"A completed or aborted run publishes exactly one immutable contribution snapshot"
	)
	local published = publications[1]
	expect(
		published.round == 1 and published.barrier == 1 and published.stateRound == 1,
		"JSON publication carries matching payload, barrier and live run identities"
	)
	expect(
		published.completions == 1 and published.phase ~= "Results",
		"Contribution snapshot follows completion and precedes Results phase publication"
	)
	local encoded = h.state:GetAttribute("ContributionsJson")
	h.advance(0.05)
	expect(h.state:GetAttribute("ContributionsJson") == encoded, "Results keeps the same immutable payload")
	h.failRule = false
	h.phase("Voting")
	expect(
		h.state:GetAttribute("ContributionsJson") == "" and h.state:GetAttribute("ContributionsRound") == 0,
		"Next voting period clears the previous run's snapshot"
	)
	h.stop()
	scenarios += 1
end

for _, dies in { false, true } do
	local h = harness(1)
	local earlyResult, callbacks, elapsed = nil, 0, nil
	h.ruleBehavior = function(_id, context)
		local started = h.now
		earlyResult = context.waitFor(5, function()
			callbacks += 1
			if dies then
				h.players[1].dead = true
			end
			return true
		end)
		elapsed = h.now - started
		return earlyResult
	end
	h.phase("Break")
	expect(callbacks == 1 and elapsed == 0, "Production wait loop permits a single early stage transition")
	expect(earlyResult == not dies, "Same-update last death overrides early completion")
	h.stop()
	scenarios += 1
end

print(
	"Main lifecycle integration: "
		.. checks
		.. " checks passed across "
		.. scenarios
		.. " scenarios (virtual services; no native clients)"
)
