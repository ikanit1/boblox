--!strict
-- Local integration harness, NOT Roblox cloud evidence.
-- Runs the production ProfileService source with deterministic service/network adapters.
-- From project root: lune run tests/ProfileService.integration.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Data = require("../src/server/ProfileData")
local Status = require("../src/shared/ProfileStatus")
local Preferences = require("../src/shared/PlayerPreferences")
local checks = 0
local scenarios: { string } = {}

local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = copy(child)
	end
	return result
end

local function signal()
	local callbacks = {}
	return {
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

local function attributes()
	local values = {}
	local signals = {}
	return {
		SetAttribute = function(self, name, value)
			local previous = values[name]
			values[name] = value
			if previous ~= value and signals[name] then
				signals[name]:Fire()
			end
			if self.onAttributeWrite then
				self.onAttributeWrite(name, value)
			end
		end,
		GetAttribute = function(_, name)
			return values[name]
		end,
		GetAttributeChangedSignal = function(_, name)
			signals[name] = signals[name] or signal()
			return signals[name]
		end,
	}
end

local function harness()
	local h: any =
		{ now = 0, queue = {}, warnings = {}, budgetTypes = {}, budget = 100, guid = 0, services = {} }
	local taskApi = {}
	function taskApi.spawn(callback, ...)
		local args = table.pack(...)
		local thread = coroutine.create(function()
			callback(table.unpack(args, 1, args.n))
		end)
		table.insert(h.queue, { at = h.now, thread = thread })
		return thread
	end
	function taskApi.wait(seconds)
		return coroutine.yield(math.max(seconds or 0.03, 0.001))
	end
	function h.advance(seconds)
		local target = h.now + seconds
		local iterations = 0
		while true do
			table.sort(h.queue, function(a, b)
				return a.at < b.at
			end)
			local entry = h.queue[1]
			if not entry or entry.at > target then
				break
			end
			table.remove(h.queue, 1)
			h.now = entry.at
			local ok, delay = coroutine.resume(entry.thread)
			assert(ok, tostring(delay))
			if coroutine.status(entry.thread) ~= "dead" then
				assert(type(delay) == "number", "Unexpected service yield")
				table.insert(h.queue, { at = h.now + delay, thread = entry.thread })
			end
			iterations += 1
			assert(iterations < 100000, "Adapter scheduler failed to make progress")
		end
		h.now = target
	end
	function h.run(callback, budget)
		local done = false
		taskApi.spawn(function()
			callback()
			done = true
		end)
		local untilAt = h.now + (budget or 40)
		while not done and h.now < untilAt do
			h.advance(0.05)
		end
		assert(done, "Service operation exceeded bounded test deadline")
	end
	h.task = taskApi
	local store: any = {
		records = {},
		plans = {},
		calls = 0,
		writes = 0,
		inFlight = 0,
		maxConcurrent = 0,
		metadata = { original = "preserve-me" },
		associated = {},
		failAll = false,
	}
	function store:UpdateAsync(key, transform)
		self.calls += 1
		self.inFlight += 1
		self.maxConcurrent = math.max(self.maxConcurrent, self.inFlight)
		local plan = table.remove(self.plans, 1) or {}
		local ok, result = pcall(function()
			if plan.DelayBefore then
				taskApi.wait(plan.DelayBefore)
			end
			if self.failAll or plan.FailBefore then
				error("Injected network failure before callback")
			end
			if plan.BeforeCallback then
				plan.BeforeCallback(self, key)
			end
			local info = {
				GetMetadata = function()
					return copy(self.metadata)
				end,
			}
			local updated, userIds, metadata = transform(copy(self.records[key]), info)
			if plan.ReplayCallback then
				-- UpdateAsync may rerun a transform; only its final return is committed.
				updated, userIds, metadata = transform(copy(self.records[key]), info)
			end
			if updated ~= nil then
				for _, userId in userIds or {} do
					assert(userId > 0, "Invalid associated Roblox user ID")
				end
				self.records[key] = copy(updated)
				self.associated[key] = copy(userIds)
				self.metadata = copy(metadata)
				self.writes += 1
			end
			if plan.DelayAfter then
				taskApi.wait(plan.DelayAfter)
			end
			if plan.FailAfter then
				error("Injected lost response after commit")
			end
			return copy(updated)
		end)
		self.inFlight -= 1
		if not ok then
			error(result)
		end
		return result
	end
	h.store = store

	function h.server(options: any)
		options = options or {}
		local players: any = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
		function players:GetPlayers()
			return table.clone(self.list)
		end
		function players:add(id, inRound)
			local player = attributes()
			player.UserId = id
			player.Parent = self
			player:SetAttribute("InRound", inRound ~= false)
			player:SetAttribute("RunSurvived", 0)
			player:SetAttribute("RunScore", 0)
			table.insert(self.list, player)
			self.PlayerAdded:Fire(player)
			return player
		end
		function players:remove(player)
			self.PlayerRemoving:Fire(player)
			local index = table.find(self.list, player)
			if index then
				table.remove(self.list, index)
			end
			player.Parent = nil
		end
		local state = attributes()
		state:SetAttribute("Round", 1)
		state:SetAttribute("RuleIndex", 1)
		local remote: any = {
			OnServerEvent = signal(),
			IsA = function(_, class)
				return class == "RemoteEvent"
			end,
		}
		local config = luau.load(fs.readFile("src/shared/EconomyConfig.luau"), {
			environment = {
				Color3 = {
					fromRGB = function(r, g, b)
						return { r, g, b }
					end,
				},
			},
		})()
		config.Persistence.TestPlaceId = 123
		config.Persistence.StudioDataStoreEnabled = options.optIn ~= false
		config.Persistence.RequestTimeoutSeconds = options.timeout or 15
		config.Persistence.AutosaveSeconds = options.autosave or 45
		local gameConfig = luau.load(fs.readFile("src/shared/GameConfig.luau"), {
			environment = {
				Color3 = {
					fromRGB = function(r, g, b)
						return { r, g, b }
					end,
				},
			},
		})()
		config.RuleOrder = gameConfig.RuleOrder
		config.RuleCount = gameConfig.RuleCount
		config.PlayerPreferences = Preferences
		local shared = {
			WaitForChild = function(_, name)
				assert(
					name == "EconomyConfig"
						or name == "ProfileStatus"
						or name == "GameConfig"
						or name == "PlayerPreferences",
					"Shared module lookup must use production modules"
				)
				return if name == "EconomyConfig"
					then config
					elseif name == "GameConfig" then gameConfig
					elseif name == "PlayerPreferences" then Preferences
					else Status
			end,
		}
		local remotes = {
			WaitForChild = function(_, name)
				assert(name == "ProfileAction", "Remote lookup must use production profile endpoint")
				return remote
			end,
		}
		local replicated = {
			WaitForChild = function(_, name)
				return ({ RuleRoomShared = shared, RuleRoomState = state, RuleRoomRemotes = remotes })[name]
			end,
		}
		local dataService = {
			GetDataStore = function(_, name)
				h.openedStore = name
				assert(name == config.Persistence.TestStoreName, "Harness must never target production store")
				return store
			end,
			GetRequestBudgetForRequestType = function(_, kind)
				h.budgetTypes[kind] = true
				return h.budget
			end,
		}
		local http = {
			GenerateGUID = function()
				h.guid += 1
				return "test-guid-" .. h.guid
			end,
		}
		local isStudio = options.studio ~= false
		local runService = {
			IsStudio = function()
				return isStudio
			end,
		}
		local closeCallbacks = {}
		local services = {
			Workspace = {
				GetServerTimeNow = function()
					return 1728000100 + h.now
				end,
			},
			Players = players,
			ReplicatedStorage = replicated,
			DataStoreService = dataService,
			HttpService = http,
			RunService = runService,
		}
		local gameAdapter = {
			PlaceId = 123,
			JobId = "local-integration-" .. (#h.services + 1),
			GetService = function(_, name)
				assert(services[name], name)
				return services[name]
			end,
			BindToClose = function(_, callback)
				table.insert(closeCallbacks, callback)
			end,
		}
		local bridgeInstances = {}
		local scriptParent: any = { ProfileData = options.profileModule or Data }
		function scriptParent:FindFirstChild(name)
			for _, object in bridgeInstances do
				if object.Parent == self and object.Name == name then
					return object
				end
			end
			return nil
		end
		local serviceModule = luau.load(fs.readFile("src/server/ProfileService.luau"), {
			debugName = "PRODUCTION_ProfileService",
			environment = {
				game = gameAdapter,
				script = { Parent = scriptParent },
				Instance = {
					new = function(className)
						assert(
							className == "BindableFunction",
							"Only the server practice bridge is instantiated"
						)
						local bridge: any = { Name = className }
						function bridge:Invoke(...)
							assert(
								self.Parent ~= nil and self.OnInvoke ~= nil,
								"Bridge must be published with its callback"
							)
							return self.OnInvoke(...)
						end
						function bridge:Destroy()
							self.Parent = nil
						end
						table.insert(bridgeInstances, bridge)
						return bridge
					end,
				},
				require = function(value)
					return value
				end,
				task = taskApi,
				os = {
					clock = function()
						return h.now
					end,
					time = function()
						return 1728000100 + math.floor(h.now)
					end,
				},
				math = setmetatable({
					random = function()
						return 0
					end,
				}, { __index = math }),
				Enum = {
					DataStoreRequestType = {
						StandardRead = "StandardRead",
						StandardWrite = "StandardWrite",
						GetAsync = "LEGACY_GetAsync",
						SetIncrementAsync = "LEGACY_SetIncrementAsync",
					},
				},
				warn = function(message)
					table.insert(h.warnings, message)
				end,
			},
		})()
		local service = serviceModule.new()
		local server = {
			service = service,
			players = players,
			state = state,
			remote = remote,
			config = config,
			parent = scriptParent,
			practiceBridge = scriptParent:FindFirstChild("RuleRoomRecordPractice"),
		}
		table.insert(h.services, server)
		function server:close()
			h.run(function()
				for _, callback in closeCallbacks do
					callback()
				end
				-- Main may also call Destroy; duplicate shutdown must stay idempotent.
				service.Destroy()
			end)
		end
		return server
	end
	return h
end

do
	local h = harness()
	local server = h.server({})
	h.store.plans = { { ReplayCallback = true } }
	local player = server.players:add(101)
	h.advance(0)
	expect(
		server.service.IsReady(player) and player:GetAttribute("DataStatus") == "Saved",
		"Actual service acquires through UpdateAsync"
	)
	for index = 1, 8 do
		server.state:SetAttribute("RuleIndex", index)
		server.service.AwardSurvival(player)
		server.service.AwardSurvival(player)
	end
	player:SetAttribute("RunSurvived", 8)
	server.remote.OnServerEvent:Fire(player, "ClaimQuest", "survive")
	server.remote.OnServerEvent:Fire(player, "ClaimQuest", "survive")
	server.remote.OnServerEvent:Fire(player, "Purchase", "Cyan")
	server.service.CompleteRun(player, true)
	server.service.CompleteRun(player, true)
	expect(
		player:GetAttribute("Coins") == 121 and player:GetAttribute("Wins") == 1,
		"Survival/run/claim idempotence and genuine purchase use service boundary"
	)
	expect(
		player:GetAttribute("Owned_Cyan") and player:GetAttribute("EquippedTrail") == "Cyan",
		"Purchase unlocks and equips"
	)
	server.players:remove(player)
	h.advance(0)
	local saved = h.store.records.Player_101
	expect(
		saved.Coins == 121 and saved.Session == nil,
		"PlayerRemoving saves earned balance and releases lease"
	)
	expect(
		saved.ClaimedQuests.survive and saved.EquippedTrail == "Cyan",
		"Claim and cosmetic saved in same snapshot"
	)
	expect(
		h.store.metadata.original == "preserve-me" and h.store.associated.Player_101[1] == 101,
		"Write preserves metadata and associated user"
	)
	local nextServer = h.server({})
	local rejoined = nextServer.players:add(101)
	h.advance(0)
	expect(
		rejoined:GetAttribute("Coins") == 121 and rejoined:GetAttribute("EquippedTrail") == "Cyan",
		"Independent service rejoin restores persisted purchase"
	)
	expect(
		rejoined:GetAttribute("Claimed_survive") == true and rejoined:GetAttribute("Wins") == 1,
		"Independent service rejoin restores claim and win"
	)
	nextServer.remote.OnServerEvent:Fire(rejoined, "ClaimQuest", "survive")
	expect(rejoined:GetAttribute("Coins") == 121, "Claim stays idempotent across rejoin")
	expect(
		h.budgetTypes.StandardRead and h.budgetTypes.StandardWrite and not h.budgetTypes.LEGACY_GetAsync,
		"Service queries current read/write budget APIs"
	)
	nextServer:close()
	server:close()
	table.insert(scenarios, "save, purchase, quest claim, leave and independent rejoin")
end

do
	local h = harness()
	local server = h.server({ optIn = false })
	local player = server.players:add(-1)
	h.advance(0)
	server.service.AwardStar(player)
	server:close()
	expect(
		player:GetAttribute("DataStatus") == "Session" and h.store.calls == 0,
		"Default Studio path never calls cloud adapter"
	)
	local cloud = h.server({})
	local localIdentity = cloud.players:add(-2)
	h.advance(0)
	expect(
		cloud.service.IsReady(localIdentity) and #h.store.associated["Player_-2"] == 0,
		"Studio test identity never becomes an invalid associated user ID"
	)
	cloud:close()
	table.insert(scenarios, "Studio opt-in isolation and local identity handling")
end

do
	local h = harness()
	local server = h.server({})
	local prior = Data.fresh(20000)
	prior.Coins = 480
	h.store.records.Player_102 = copy(prior)
	h.store.failAll = true
	local player = server.players:add(102)
	h.advance(16)
	expect(
		player:GetAttribute("DataStatus") == "Unavailable" and not server.service.IsReady(player),
		"Failed load waits for explicit temporary-play choice"
	)
	player:SetAttribute("TemporaryPlayAccepted", true)
	expect(server.service.IsReady(player), "Accepted fallback can join a new trial")
	server.service.AwardSurvival(player)
	server.players:remove(player)
	h.advance(10)
	expect(
		h.store.records.Player_102.Coins == 480 and h.store.writes == 0,
		"Failure and shutdown never save defaults over cloud data"
	)
	h.store.failAll = false
	server:close()
	table.insert(scenarios, "failed load, session fallback and no overwrite")
end

do
	local h = harness()
	local serverA = h.server({})
	local a = serverA.players:add(103)
	h.advance(0)
	serverA.service.AwardSurvival(a)
	local owner = h.store.records.Player_103.Session.Owner
	local serverB = h.server({ timeout = 3 })
	local b = serverB.players:add(103)
	h.advance(3.5)
	expect(
		b:GetAttribute("DataStatus") == "Busy" and h.store.records.Player_103.Session.Owner == owner,
		"Second server cannot steal a live lease"
	)
	serverB.service.AwardStar(b)
	serverB:close()
	expect(
		h.store.records.Player_103.Session.Owner == owner,
		"Busy-session shutdown cannot release first server lease"
	)
	serverA:close()
	expect(
		h.store.records.Player_103.Coins == 12 and h.store.records.Player_103.Session == nil,
		"Only owning server persists and releases"
	)
	table.insert(scenarios, "concurrent ownership and busy fallback")
end

do
	local h = harness()
	local server = h.server({})
	h.store.plans = { { FailAfter = true }, { FailAfter = true }, { FailAfter = true } }
	local player = server.players:add(104)
	h.advance(10)
	expect(
		player:GetAttribute("DataStatus") == "Unavailable",
		"Ambiguous acquire never pretends a response was loaded"
	)
	expect(
		h.store.records.Player_104 ~= nil and h.store.records.Player_104.Session == nil,
		"Lost acquire responses do not strand the unique owner lease"
	)
	server.service.AwardStar(player)
	server:close()
	expect(
		h.store.records.Player_104.Coins == 0,
		"Uncertain acquire cleanup preserves cloud contents instead of fallback rewards"
	)
	table.insert(scenarios, "committed acquire with all responses lost")
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(105)
	h.advance(0)
	server.service.AwardStar(player)
	h.store.plans = {
		{ FailAfter = true },
		{
			BeforeCallback = function(store, key)
				local nextRecord = assert(
					Data.acquire(
						store.records[key],
						"other-server",
						1728000100 + math.floor(h.now),
						180,
						server.config
					)
				)
				nextRecord.Coins = 777
				store.records[key] = nextRecord
			end,
		},
	}
	server.players:remove(player)
	h.advance(3)
	expect(
		h.store.records.Player_105.Coins == 777 and h.store.records.Player_105.Session.Owner == "other-server",
		"Lost release receipt retry cannot overwrite new owner"
	)
	server:close()
	table.insert(scenarios, "lost final-save receipt and intervening new owner")
end

do
	local h = harness()
	local server = h.server({ autosave = 2 })
	local player = server.players:add(106)
	h.advance(0)
	server.service.AwardStar(player)
	h.store.plans = { { DelayBefore = 5 } }
	h.advance(2)
	server.service.AwardStar(player)
	server.players:remove(player)
	h.advance(7)
	expect(h.store.maxConcurrent == 1, "Autosave and leave are serialized for a player")
	expect(
		h.store.records.Player_106.Coins == 4 and h.store.records.Player_106.Session == nil,
		"Final save includes reward earned while autosave snapshot was in flight"
	)
	server:close()
	table.insert(scenarios, "slow autosave, concurrent reward and leaving")
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(107)
	h.advance(0)
	server.service.AwardStar(player)
	h.budget = 0
	local calls = h.store.calls
	server:close()
	expect(h.now <= 25.1 and h.store.calls == calls, "Shutdown is bounded when request budget is exhausted")
	expect(h.store.records.Player_107.Coins == 0, "No request is issued while budget is unavailable")
	table.insert(scenarios, "exhausted budget and bounded shutdown")
end

do
	local h = harness()
	local server = h.server({ timeout = 2 })
	h.store.plans = { { DelayAfter = 5 } }
	local player = server.players:add(108)
	h.advance(0)
	server.players:remove(player)
	h.advance(8)
	expect(
		h.store.records.Player_108.Session == nil,
		"Acquire completing after removal deadline eventually releases"
	)
	expect(not server.service.IsReady(player), "Late acquire never resurrects a removed player scope")
	server:close()
	table.insert(scenarios, "late acquire completion after removal")
end

do
	local h = harness()
	local server = h.server({ optIn = false })
	local player = server.players:add(109)
	h.advance(0)
	expect(
		player:GetAttribute("DataPersistent") == false,
		"Studio fallback explicitly declares no persistence"
	)
	expect(not server.service.IsReady(player), "Studio entry requires explicit temporary-play consent")
	-- Existing-trial awards stay separate from new admission, including lease loss.
	for _ = 1, 30 do
		server.service.AwardStar(player)
	end
	server.remote.OnServerEvent:Fire(player, "Purchase", "Cyan")
	expect(
		player:GetAttribute("Coins") == 60 and player:GetAttribute("Owned_Cyan") ~= true,
		"Temporary purchase cannot bypass missing consent"
	)
	player:SetAttribute("TemporaryPlayAccepted", true)
	expect(server.service.IsReady(player), "Explicit choice allows Session admission")
	server.remote.OnServerEvent:Fire(player, "Purchase", "Cyan")
	expect(
		player:GetAttribute("Coins") == 0 and player:GetAttribute("Owned_Cyan") == true,
		"Accepted temporary purchase follows the normal server price"
	)
	server:close()
	expect(h.store.calls == 0, "Temporary consent never enables cloud writes")
	table.insert(scenarios, "explicit temporary admission and purchase consent")
end

do
	local h = harness()
	local server = h.server({ autosave = 2 })
	local player = server.players:add(110)
	h.advance(0)
	server.service.AwardStar(player)
	h.store.failAll = true
	h.advance(10)
	expect(
		player:GetAttribute("DataStatus") == "Unavailable" and player:GetAttribute("DataPersistent") == true,
		"Failed autosave distinguishes live-lease retry from memory fallback"
	)
	expect(server.service.IsReady(player), "Live lease allows play during automatic retry")
	h.store.failAll = false
	h.advance(4)
	expect(
		player:GetAttribute("DataStatus") == "Saved" and player:GetAttribute("DataPersistent") == true,
		"Successful automatic retry restores the persistent state"
	)
	expect(
		player:GetAttribute("ActionMessage") == "Сохранение восстановлено.",
		"Recovered save does not leave a stale failure message"
	)
	server:close()
	table.insert(scenarios, "autosave retry and clear recovery feedback")
end

do
	local h = harness()
	local server = h.server({ autosave = 400 })
	local player = server.players:add(111)
	h.advance(0)
	player:SetAttribute("TemporaryPlayAccepted", true)
	h.advance(181)
	server.service.AwardSurvival(player)
	expect(player:GetAttribute("Coins") == 12, "Lease loss preserves the already-started trial award")
	expect(
		player:GetAttribute("DataPersistent") == false
			and player:GetAttribute("TemporaryPlayAccepted") == false,
		"Lease loss revokes stale consent and declares temporary progress"
	)
	expect(not server.service.IsReady(player), "A new trial after lease loss requires a new choice")
	expect(
		player:GetAttribute("CanRetryProfile") == false,
		"Lease loss never offers a destructive in-session reload"
	)
	player:SetAttribute("TemporaryPlayAccepted", true)
	expect(server.service.IsReady(player), "Player may explicitly continue after lease loss")
	server:close()
	expect(h.store.records.Player_111.Coins == 0, "Expired owner never persists temporary rewards")
	table.insert(scenarios, "lease loss, current reward and renewed consent")
end

do
	local h = harness()
	local server = h.server({ autosave = 2, timeout = 2 })
	local player = server.players:add(112)
	h.advance(0)
	server.service.AwardStar(player)
	-- The autosave commits its snapshot at once, but its response returns long after
	-- PlayerRemoving has given up waiting for it.
	h.store.plans = { { DelayAfter = 6 } }
	h.advance(2.5)
	expect(h.store.inFlight == 1, "Autosave request is in flight before leaving")
	server.service.AwardStar(player)
	server.players:remove(player)
	h.advance(2.5)
	expect(
		h.store.inFlight == 1 and h.store.records.Player_112.Session ~= nil,
		"PlayerRemoving wait expired while the autosave is still running"
	)
	local closedFrom = h.now
	server:close()
	local saved = h.store.records.Player_112
	expect(
		saved.Coins == 4 and saved.Session == nil,
		"Destroy waits for in-flight autosave, then commits later rewards and releases"
	)
	expect(
		h.store.maxConcurrent == 1 and h.store.inFlight == 0 and h.now <= closedFrom + 25.1,
		"Shutdown drain stays serialized and bounded by ShutdownSeconds"
	)
	table.insert(scenarios, "autosave outlives PlayerRemoving wait, shutdown drains it")
end

do
	local h = harness()
	local server = h.server({ autosave = 70 })
	local player = server.players:add(113)
	h.advance(0)
	server.service.AwardStar(player)
	h.store.plans = {
		{
			-- The renewal commits, then the response and every later request are lost.
			BeforeCallback = function(store)
				store.failAll = true
			end,
			FailAfter = true,
		},
	}
	h.advance(181)
	local owner = h.store.records.Player_113.Session.Owner
	expect(
		h.store.records.Player_113.Coins == 2
			and h.store.records.Player_113.Session.ExpiresAt > 1728000100 + math.floor(h.now),
		"Renewal committed in the cloud although its response was lost"
	)
	-- No request is in flight now; the next player action notices the local expiry.
	server.service.AwardStar(player)
	expect(
		h.store.inFlight == 0 and player:GetAttribute("DataPersistent") == false,
		"Local lease is abandoned after the outage"
	)
	h.store.failAll = false
	server.players:remove(player)
	h.advance(10)
	local record = h.store.records.Player_113
	expect(record.Session == nil, "Leaving releases our own still-live cloud lease after lease loss")
	expect(
		record.Coins == 2 and owner:sub(1, 19) == "local-integration-1",
		"Lease release preserves cloud data and never writes temporary rewards"
	)
	local nextServer = h.server({ timeout = 3 })
	local rejoined = nextServer.players:add(113)
	h.advance(3.5)
	expect(
		rejoined:GetAttribute("DataStatus") == "Saved" and rejoined:GetAttribute("Coins") == 2,
		"Rejoin acquires instead of Busy"
	)
	nextServer:close()
	server:close()
	table.insert(scenarios, "lost renewal receipt, lease loss, release on leave and rejoin")
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(201)
	expect(not server.service.RecordPractice(player, 30), "Loading profiles reject practice records")
	expect(not server.service.RecordFlawless(player, "SafeColor"), "Loading profiles reject mastery")
	h.advance(0)
	expect(
		player:GetAttribute("BestRunScore") == 0
			and player:GetAttribute("BestRunSurvived") == 0
			and player:GetAttribute("BestPracticeSeconds") == nil
			and player:GetAttribute("NewRecord") == "",
		"New records replicate neutral defaults without inventing a practice time"
	)
	for _, ruleId in server.config.RuleOrder do
		expect(
			player:GetAttribute("Flawless_" .. ruleId) == 0,
			"Every configured rule has a mastery attribute"
		)
	end
	local function complete(round, score, survived)
		server.state:SetAttribute("Round", round)
		player:SetAttribute("RunScore", score)
		player:SetAttribute("RunSurvived", survived)
		server.service.CompleteRun(player, false)
	end
	complete(1, 100, 3)
	expect(player:GetAttribute("NewRecord") == "Score,Survived", "First positive run improves both records")
	complete(2, 100, 3)
	expect(player:GetAttribute("NewRecord") == "", "Tied records do not announce improvements")
	complete(3, 125, 2)
	expect(player:GetAttribute("NewRecord") == "Score", "Only the score record improved")
	complete(4, 120, 4)
	expect(player:GetAttribute("NewRecord") == "Survived", "Only the survival record improved")
	complete(5, 160, 6)
	local coins = player:GetAttribute("Coins")
	complete(5, 999, 6)
	expect(
		player:GetAttribute("BestRunScore") == 160
			and player:GetAttribute("BestRunSurvived") == 6
			and player:GetAttribute("NewRecord") == "Score,Survived"
			and player:GetAttribute("Coins") == coins,
		"Duplicate completion cannot alter a recorded result, its notice or rewards"
	)
	expect(server.practiceBridge.Parent == server.parent, "Practice bridge lives only in the server folder")
	expect(server.practiceBridge:Invoke(player, 25.5), "Practice bridge calls the current profile service")
	expect(not server.service.RecordPractice(player, 25.5), "Tied practice time is not a new record")
	expect(not server.service.RecordPractice(player, 30), "Slower practice time cannot replace the best")
	expect(server.service.RecordPractice(player, 20.125), "Faster fractional time improves the record")
	expect(server.service.RecordFlawless(player, "SafeColor"), "Valid admitted survivor can record mastery")
	expect(not server.service.RecordFlawless(player, "SafeColor"), "Mastery is at most once per trial")
	server.state:SetAttribute("RuleIndex", 2)
	expect(server.service.RecordFlawless(player, "LaserSweep"), "Independent trial has its own mastery gate")
	server.state:SetAttribute("Round", 6)
	server.state:SetAttribute("RuleIndex", 1)
	expect(server.service.RecordFlawless(player, "SafeColor"), "A later run can increase the same rule count")
	expect(player:GetAttribute("Coins") == coins, "Records and mastery add no currency")
	server.players:remove(player)
	expect(not server.service.RecordPractice(player, 1), "A departing scope cannot improve records")
	expect(not server.service.RecordFlawless(player, "Spinner"), "A departing scope cannot gain mastery")
	h.advance(0)
	local saved = h.store.records.Player_201
	expect(
		saved.SchemaVersion == 5
			and saved.BestRunScore == 160
			and saved.BestRunSurvived == 6
			and saved.BestPracticeSeconds == 20.125
			and saved.Flawless.SafeColor == 2
			and saved.Flawless.LaserSweep == 1
			and saved.Session == nil,
		"Final save writes records and v3 mastery together and releases the lease"
	)
	local nextServer = h.server({})
	local rejoined = nextServer.players:add(201)
	h.advance(0)
	expect(
		rejoined:GetAttribute("BestRunScore") == 160
			and rejoined:GetAttribute("BestRunSurvived") == 6
			and rejoined:GetAttribute("BestPracticeSeconds") == 20.125
			and rejoined:GetAttribute("Flawless_SafeColor") == 2
			and rejoined:GetAttribute("Flawless_LaserSweep") == 1
			and rejoined:GetAttribute("NewRecord") == "",
		"Independent service rejoin restores records/mastery but not a stale NewRecord notice"
	)
	nextServer:close()
	server:close()
	expect(server.practiceBridge.Parent == nil, "Destroy removes the server practice endpoint")
	expect(not server.service.RecordPractice(player, 0.1), "Destroyed service rejects record mutations")
	table.insert(scenarios, "v2 records, all NewRecord variants, mastery dedupe and independent rejoin")
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(202)
	h.advance(0)
	for _, invalid in { 0, -1, 0 / 0, math.huge, -math.huge, 1_000_000_001, "12", true, {} } do
		expect(not server.service.RecordPractice(player, invalid), "Malformed practice time is rejected")
	end
	expect(not server.service.RecordPractice(player, nil), "Missing practice time is rejected")
	expect(player:GetAttribute("BestPracticeSeconds") == nil, "Rejected times cannot invent a record")
	for _, invalid in { "Unknown", "", "safecolor", 1, true, {}, 0 / 0 } do
		expect(not server.service.RecordFlawless(player, invalid), "Malformed or unknown rule is rejected")
	end
	expect(not server.service.RecordFlawless(player, nil), "Missing rule is rejected")
	player:SetAttribute("InRound", false)
	expect(not server.service.RecordFlawless(player, "SafeColor"), "Lobby player cannot receive mastery")
	player:SetAttribute("InRound", true)
	player:SetAttribute("MovementWarning", true)
	expect(not server.service.RecordFlawless(player, "SafeColor"), "Movement warning disqualifies mastery")
	player:SetAttribute("MovementWarning", false)
	expect(
		server.service.RecordFlawless(player, "SafeColor"),
		"Rejected calls do not consume the mastery gate"
	)
	server:close()
	table.insert(scenarios, "records reject malformed values, unknown rules and ineligible players")
end

do
	local h = harness()
	local legacy: any = Data.fresh(20_000)
	legacy.SchemaVersion = 1
	legacy.Coins = 321
	legacy.XP = 600
	legacy.Wins = 7
	legacy.OwnedTrails.Cyan = true
	legacy.EquippedTrail = "Cyan"
	legacy.BestRunScore = nil
	legacy.BestRunSurvived = nil
	legacy.BestPracticeSeconds = nil
	legacy.Flawless = nil
	h.store.records.Player_203 = legacy
	local server = h.server({})
	local player = server.players:add(203)
	h.advance(0)
	expect(
		h.store.records.Player_203.SchemaVersion == 5
			and player:GetAttribute("Coins") == 321
			and player:GetAttribute("XP") == 600
			and player:GetAttribute("Wins") == 7
			and player:GetAttribute("Owned_Cyan") == true
			and player:GetAttribute("BestRunScore") == 0,
		"Actual acquire migrates a v1 record without losing earned progress"
	)
	-- A newer server replaces the schema while an older scope still holds its snapshot.
	server.service.RecordPractice(player, 15)
	h.store.records.Player_203.SchemaVersion = 6
	h.store.records.Player_203.FutureField = "preserve"
	server.players:remove(player)
	h.advance(0)
	local preserved = h.store.records.Player_203
	expect(
		preserved.SchemaVersion == 6
			and preserved.FutureField == "preserve"
			and preserved.BestPracticeSeconds == nil,
		"SchemaChanged refuses stale data while lease cleanup preserves the newer record"
	)
	server:close()
	table.insert(scenarios, "service migrates v1 and refuses an incompatible newer schema during save")
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(301)
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "FirstRun")
	expect(player:GetAttribute("EquippedTitle") == "None", "Loading scope cannot equip a title")
	expect(not server.service.AwardStar(player), "Loading profile explicitly refuses a pickup grant")
	h.advance(0)
	for _, milestone in server.config.MasteryMilestones do
		expect(
			player:GetAttribute("Mastery_" .. milestone.Id) == 0
				and player:GetAttribute("UnlockedTitle_" .. milestone.Id) == false,
			"Every permanent goal replicates neutral progress and a locked title"
		)
	end
	local function complete(round, survived, stars, energy, won)
		server.state:SetAttribute("Round", round)
		player:SetAttribute("RunSurvived", survived)
		player:SetAttribute("RunStars", stars)
		player:SetAttribute("RunEnergy", energy)
		server.service.CompleteRun(player, won)
	end
	complete(1, 6, 0, 0, true)
	expect(
		player:GetAttribute("Mastery_FirstRun") == 0
			and player:GetAttribute("Mastery_PerfectRun") == 0
			and player:GetAttribute("Mastery_TeamVeteran") == 0,
		"Passive survival, including a personal victory, cannot progress action-qualified titles"
	)
	complete(2, 0, 1, 1, true)
	expect(
		player:GetAttribute("Mastery_FirstRun") == 0,
		"An ineligible completion cannot unlock the first run"
	)
	complete(2, 1, 1, 0, false)
	expect(
		player:GetAttribute("UnlockedTitle_FirstRun") == true,
		"Eligible collected completion unlocks first run"
	)
	complete(3, 6, 1, 1, false)
	expect(
		player:GetAttribute("Mastery_TeamVeteran") == 0,
		"Failed reactor never increments personal-win mastery"
	)
	complete(4, 5, 1, 1, true)
	expect(
		player:GetAttribute("Mastery_TeamVeteran") == 1
			and player:GetAttribute("UnlockedTitle_PerfectRun") == false,
		"A partial-survival personal win counts for veteran but not perfect run"
	)
	complete(4, 6, 1, 1, true)
	expect(
		player:GetAttribute("Mastery_TeamVeteran") == 1
			and player:GetAttribute("UnlockedTitle_PerfectRun") == false,
		"Duplicate completion cannot upgrade its original mastery outcome"
	)
	complete(5, 6, 1, 1, true)
	expect(
		player:GetAttribute("UnlockedTitle_PerfectRun") == true,
		"A real six-trial contribution victory unlocks perfect run"
	)
	for round = 6, 10 do
		complete(round, 6, 1, 1, true)
	end
	expect(
		player:GetAttribute("Mastery_TeamVeteran") == 5
			and player:GetAttribute("UnlockedTitle_TeamVeteran") == true,
		"Five contributing wins unlock veteran once and progress stays bounded"
	)
	local coins, xp = player:GetAttribute("Coins"), player:GetAttribute("XP")
	for index, ruleId in { "LowGravity", "RedLight", "ReactorRush" } do
		server.state:SetAttribute("RuleIndex", index)
		expect(
			server.service.RecordFlawless(player, ruleId, "Collected"),
			"Clean admitted pickup trial qualifies"
		)
		expect(
			not server.service.RecordFlawless(player, ruleId, "Collected"),
			"Duplicate clean trial cannot award twice"
		)
		expect(
			player:GetAttribute("Mastery_Collector") == index,
			"Distinct qualifying trial progress replicates"
		)
	end
	expect(
		player:GetAttribute("UnlockedTitle_Collector") == true,
		"All three distinct collector rules unlock the title"
	)
	expect(
		server.practiceBridge:Invoke(player, 22.5),
		"Valid Station bridge finish unlocks practice and personal best"
	)
	expect(
		not server.practiceBridge:Invoke(player, 25),
		"Slower repeats retain the existing record return contract"
	)
	expect(
		player:GetAttribute("UnlockedTitle_Practice") == true,
		"Parkour completion publishes a permanent title"
	)
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "Collector")
	expect(
		player:GetAttribute("EquippedTitle") == "Collector",
		"Unlocked allowlisted title can be equipped by remote"
	)
	expect(
		player:GetAttribute("Coins") == coins and player:GetAttribute("XP") == xp,
		"Titles and mastery add no currency or XP"
	)
	expect(player:GetAttribute("DataStatus") == "Saved", "Cosmetic actions do not fabricate a new save state")
	server.players:remove(player)
	h.advance(0)
	local saved = h.store.records.Player_301
	expect(
		saved.SchemaVersion == 5 and saved.EquippedTitle == "Collector",
		"Final save stores schema v3 and equipped title"
	)
	for _, milestone in server.config.MasteryMilestones do
		expect(
			saved.Mastery[milestone.Id] == milestone.Target and saved.UnlockedTitles[milestone.Id] == true,
			"All five goals and their permanent unlock flags are persisted"
		)
	end
	local nextServer = h.server({})
	local joined = nextServer.players:add(301)
	h.advance(0)
	for _, milestone in nextServer.config.MasteryMilestones do
		expect(
			joined:GetAttribute("Mastery_" .. milestone.Id) == milestone.Target
				and joined:GetAttribute("UnlockedTitle_" .. milestone.Id) == true,
			"Independent server rejoin restores every permanent goal"
		)
	end
	expect(joined:GetAttribute("EquippedTitle") == "Collector", "Equipped title survives server replacement")
	local joinedCoins = joined:GetAttribute("Coins")
	expect(
		not nextServer.service.RecordPractice(joined, 24),
		"Rejoined slower practice cannot reaward a title"
	)
	expect(joined:GetAttribute("Coins") == joinedCoins, "Rejoin grants no repeated cosmetic bonus")
	nextServer:close()
	server:close()
	table.insert(
		scenarios,
		"five permanent cosmetic goals, action qualification, dedupe, save and independent rejoin"
	)
end

do
	local h = harness()
	local legacy: any = Data.fresh(20_000)
	legacy.SchemaVersion = 2
	legacy.Coins = 87
	legacy.BestRunScore = 250
	legacy.BestRunSurvived = 6
	legacy.BestPracticeSeconds = 10
	legacy.Flawless.LowGravity = 1e9
	h.store.records.Player_302 = legacy
	local server = h.server({})
	local player = server.players:add(302)
	h.advance(0)
	expect(
		h.store.records.Player_302.SchemaVersion == 5
			and player:GetAttribute("BestRunScore") == 250
			and player:GetAttribute("BestRunSurvived") == 6
			and player:GetAttribute("BestPracticeSeconds") == 10
			and player:GetAttribute("Flawless_LowGravity") == 1e9
			and player:GetAttribute("Coins") == 87,
		"Actual v2 acquire preserves records, capped statistics and currency"
	)
	expect(
		player:GetAttribute("Mastery_Practice") == 0,
		"Old practice record does not invent a newly observed finish"
	)
	expect(not server.service.RecordPractice(player, 15), "A valid slower finish is still not a new record")
	expect(
		player:GetAttribute("UnlockedTitle_Practice") == true
			and player:GetAttribute("BestPracticeSeconds") == 10,
		"A valid slower postmigration finish unlocks practice without erasing the old best"
	)
	expect(
		server.service.RecordFlawless(player, "LowGravity", "Collected"),
		"Saturated Flawless statistics do not block new clean-action mastery"
	)
	expect(
		player:GetAttribute("Mastery_Collector") == 1 and player:GetAttribute("Flawless_LowGravity") == 1e9,
		"Collector progress and historical Flawless counter stay independent"
	)
	server.state:SetAttribute("RuleIndex", 2)
	expect(
		server.service.RecordFlawless(player, "RedLight"),
		"Legacy two-argument method still records an undamaged survival"
	)
	expect(
		player:GetAttribute("Mastery_Collector") == 1,
		"A flawless survival without an accepted pickup adds no collector progress"
	)
	expect(
		not server.service.RecordFlawless(player, "RedLight", "Collected"),
		"Late action cannot upgrade an already finalized trial"
	)
	server.state:SetAttribute("RuleIndex", 3)
	expect(
		server.service.RecordFlawless(player, "RedLight", "Collected"),
		"The next clean pickup trial can qualify normally"
	)
	expect(
		player:GetAttribute("Mastery_Collector") == 2,
		"Distinct clean-rule flags survive mixed old and new API calls"
	)
	server:close()
	table.insert(
		scenarios,
		"v2 records migrate intact; slower parkour and saturated Flawless allow separate mastery"
	)
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(303)
	h.advance(0)
	for _, bad in { false, 1, {}, "collected", "", 0 / 0 } do
		expect(
			not server.service.RecordFlawless(player, "LowGravity", bad),
			"Malformed action proof rejects the entire request"
		)
	end
	for _, bad in { false, 0, -1, 1.5, math.huge, 0 / 0, "1" } do
		server.state:SetAttribute("Round", bad)
		expect(
			not server.service.RecordFlawless(player, "LowGravity", "Collected"),
			"A real positive integer run identity is required"
		)
	end
	server.state:SetAttribute("Round", 1)
	for _, bad in { false, 0, 7, 1.5, math.huge, 0 / 0, "1" } do
		server.state:SetAttribute("RuleIndex", bad)
		expect(
			not server.service.RecordFlawless(player, "LowGravity", "Collected"),
			"A real bounded trial identity is required"
		)
	end
	server.state:SetAttribute("RuleIndex", 1)
	player:SetAttribute("MovementWarning", true)
	expect(
		not server.service.RecordFlawless(player, "LowGravity", "Collected"),
		"Movement warning forbids clean-action mastery"
	)
	expect(not server.service.AwardStar(player), "Movement warning explicitly refuses pickup grants")
	player:SetAttribute("MovementWarning", false)
	player:SetAttribute("InRound", false)
	expect(
		not server.service.RecordFlawless(player, "LowGravity", "Collected"),
		"Lobby requests have no clean trial"
	)
	expect(not server.service.AwardStar(player), "Lobby requests explicitly refuse pickup grants")
	player:SetAttribute("InRound", true)
	expect(
		player:GetAttribute("Flawless_LowGravity") == 0 and player:GetAttribute("Mastery_Collector") == 0,
		"Rejected proof, identity and eligibility requests leave counters untouched"
	)
	expect(
		server.service.RecordFlawless(player, "LowGravity", "Collected"),
		"Invalid calls do not consume a valid trial's gate"
	)
	expect(server.service.AwardStar(player), "A valid admitted profile explicitly confirms a pickup grant")
	server:close()
	expect(not server.service.AwardStar(player), "Destroyed service explicitly refuses pickup grants")
	table.insert(
		scenarios,
		"collector action and trial-identity validation; explicit pickup grant acknowledgement"
	)
end

do
	local h = harness()
	local server = h.server({})
	local player = server.players:add(304)
	h.advance(0)
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "PerfectRun")
	expect(player:GetAttribute("EquippedTitle") == "None", "Locked title equip is denied")
	server.service.RecordPractice(player, 30)
	for _, bad in { false, 1, {}, "Unknown", "Practice ", string.rep("A", 25), 0 / 0 } do
		h.advance(0.6)
		server.remote.OnServerEvent:Fire(player, "EquipTitle", bad)
		expect(
			player:GetAttribute("EquippedTitle") == "None",
			"Malformed or unknown title equip cannot change the selection"
		)
	end
	h.advance(3)
	local writes = h.store.writes
	for _ = 1, 5 do
		server.remote.OnServerEvent:Fire(player, "EquipTitle", "None")
	end
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "Practice")
	expect(
		player:GetAttribute("EquippedTitle") == "None",
		"Title equip uses the existing shared remote rate limit"
	)
	h.advance(0.6)
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "Practice")
	expect(
		player:GetAttribute("EquippedTitle") == "Practice",
		"Title equip resumes when a request token refills"
	)
	h.advance(0.6)
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "None")
	expect(player:GetAttribute("EquippedTitle") == "None", "Known None disables a cosmetic title")
	expect(h.store.writes == writes, "Title requests never synchronously call DataStore")
	server.players:remove(player)
	server.remote.OnServerEvent:Fire(player, "EquipTitle", "Practice")
	expect(player:GetAttribute("EquippedTitle") == "None", "A closing profile cannot equip a title")
	server:close()
	local memory = h.server({ optIn = false })
	local temporary = memory.players:add(305)
	h.advance(0)
	memory.service.RecordPractice(temporary, 30)
	memory.remote.OnServerEvent:Fire(temporary, "EquipTitle", "Practice")
	expect(
		temporary:GetAttribute("EquippedTitle") == "None",
		"Unconfirmed temporary play cannot change cosmetics"
	)
	temporary:SetAttribute("TemporaryPlayAccepted", true)
	memory.remote.OnServerEvent:Fire(temporary, "EquipTitle", "Practice")
	expect(
		temporary:GetAttribute("EquippedTitle") == "Practice"
			and temporary:GetAttribute("DataStatus") == "Session",
		"Accepted temporary title stays explicitly local instead of pretending to be cloud-saved"
	)
	memory:close()
	table.insert(
		scenarios,
		"title equip allowlist, malformed requests, shared rate limit, close and temporary-play gate"
	)
end

do
	local h = harness()
	local saved: any = Data.fresh(20_000)
	saved.SchemaVersion = 3
	saved.Mastery.FirstRun = 1
	saved.UnlockedTitles.FirstRun = true
	saved.EquippedTitle = "FirstRun"
	h.store.records.Player_306 = saved
	-- Same production guards with the previous ceiling, not a historical server binary.
	local oldData = luau.load(
		(
			fs.readFile("src/server/ProfileData.luau")
				:gsub("ProfileData.SchemaVersion = 5", "ProfileData.SchemaVersion = 2", 1)
		)
	)()
	local oldServer = h.server({ profileModule = oldData })
	local player = oldServer.players:add(306)
	h.advance(0)
	expect(
		player:GetAttribute("DataPersistent") == false and not oldServer.service.IsReady(player),
		"v2 ceiling refuses v3 data and falls back without persistent admission"
	)
	expect(
		h.store.writes == 0
			and h.store.records.Player_306.SchemaVersion == 3
			and h.store.records.Player_306.UnlockedTitles.FirstRun
			and h.store.records.Player_306.EquippedTitle == "FirstRun",
		"Rollback acquisition cannot overwrite the v3 title record with defaults"
	)
	oldServer:close()
	expect(h.store.writes == 0, "Rollback shutdown cannot persist the temporary fallback over v3")
	local oldRecord: any = Data.fresh(20_000)
	oldRecord.SchemaVersion = 2
	h.store.records.Player_307 = oldRecord
	local inFlight = h.server({ profileModule = oldData })
	local oldPlayer = inFlight.players:add(307)
	h.advance(0)
	expect(inFlight.service.IsReady(oldPlayer), "Previous ceiling can still acquire a compatible v2 profile")
	expect(inFlight.service.RecordPractice(oldPlayer, 20), "Old scope holds an unsaved local snapshot")
	local upgraded = Data.clone(saved)
	upgraded.BestPracticeSeconds = 8
	local cloudRecord: any = upgraded
	cloudRecord.Session = copy(h.store.records.Player_307.Session)
	cloudRecord.MigrationMarker = "v3-owner"
	h.store.records.Player_307 = cloudRecord
	inFlight.players:remove(oldPlayer)
	h.advance(0)
	local untouched = h.store.records.Player_307
	expect(
		untouched.SchemaVersion == 3
			and untouched.BestPracticeSeconds == 8
			and untouched.UnlockedTitles.FirstRun
			and untouched.EquippedTitle == "FirstRun"
			and untouched.MigrationMarker == "v3-owner"
			and untouched.Session == nil,
		"An acquired v2 scope refuses a migrated v3 snapshot and releases only its own lease"
	)
	inFlight:close()
	table.insert(scenarios, "previous schema-ceiling service rejects future profiles without cloud writes")
end

do
	local h = harness()
	local legacy: any = Data.fresh(20_000)
	legacy.SchemaVersion = 3
	legacy.Preferences = nil
	legacy.Coins, legacy.XP, legacy.Wins = 99, 700, 8
	legacy.BestRunScore, legacy.BestRunSurvived, legacy.BestPracticeSeconds = 300, 6, 18.75
	legacy.Flawless.RedLight = 4
	legacy.Mastery.TeamVeteran, legacy.Mastery.Collector = 5, 3
	legacy.CleanCollectors = { LowGravity = true, RedLight = true, ReactorRush = true }
	legacy.UnlockedTitles = { TeamVeteran = true, Collector = true }
	legacy.EquippedTitle = "Collector"
	h.store.records.Player_401 = legacy
	h.store.plans = { { DelayBefore = 1 } }
	local server = h.server({ autosave = 400 })
	local player = server.players:add(401)
	expect(
		player:GetAttribute("PrefsReady") == false and player:GetAttribute("PrefsRevision") == 0,
		"Loading profile publishes an unready preference snapshot"
	)
	for _, key in Preferences.Keys do
		expect(
			player:GetAttribute("Pref" .. key) == nil,
			"Absent preferences are not replaced by server-selected defaults"
		)
	end
	server.remote.OnServerEvent:Fire(player, "SetPreference", "MusicVolume", 0.75)
	expect(
		player:GetAttribute("PrefsRevision") == 0 and player:GetAttribute("PrefMusicVolume") == nil,
		"Loading profile cannot accept a pending local preference"
	)
	local readySnapshot = nil
	player.onAttributeWrite = function(name, value)
		if name == "PrefsReady" and value == true and not readySnapshot then
			readySnapshot = {
				revision = player:GetAttribute("PrefsRevision"),
				title = player:GetAttribute("EquippedTitle"),
				volume = player:GetAttribute("PrefMusicVolume"),
			}
		end
	end
	h.advance(1.1)
	expect(
		readySnapshot ~= nil
			and readySnapshot.revision == 0
			and readySnapshot.title == "Collector"
			and readySnapshot.volume == nil,
		"Preference readiness follows the complete loaded snapshot"
	)
	expect(
		h.store.records.Player_401.SchemaVersion == 5
			and player:GetAttribute("Mastery_TeamVeteran") == 5
			and player:GetAttribute("Mastery_Collector") == 3
			and player:GetAttribute("UnlockedTitle_Collector")
			and player:GetAttribute("BestRunScore") == 300
			and player:GetAttribute("BestPracticeSeconds") == 18.75,
		"Actual v3 acquire migrates to v5 without clearing mastery or records"
	)
	local initialWrites = h.store.writes
	local chosen = { EffectsVolume = 0.25, MusicVolume = 0.75, AudioMuted = true, ReducedMotion = false }
	local acknowledged = 0
	player.onAttributeWrite = function(name, value)
		if name == "PrefsRevision" and value > acknowledged then
			acknowledged = value
			for index, key in Preferences.Keys do
				if index <= math.min(value, 4) then
					assert(
						player:GetAttribute("Pref" .. key) == chosen[key],
						"Acknowledgement must follow the accepted value"
					)
				end
			end
		end
	end
	for index, key in Preferences.Keys do
		server.remote.OnServerEvent:Fire(player, "SetPreference", key, chosen[key])
		expect(
			player:GetAttribute("Pref" .. key) == chosen[key]
				and player:GetAttribute("PrefsRevision") == index,
			"Accepted choice publishes its value before the in-memory acknowledgement"
		)
	end
	server.remote.OnServerEvent:Fire(player, "SetPreference", "ReducedMotion", false)
	expect(
		player:GetAttribute("PrefsRevision") == 5 and acknowledged == 5,
		"Idempotent accepted choice still acknowledges a pending client request"
	)
	expect(
		h.store.writes == initialWrites and next(h.store.records.Player_401.Preferences) == nil,
		"Preference acknowledgement does not imply a synchronous cloud save"
	)
	expect(
		player:GetAttribute("Coins") == 99
			and player:GetAttribute("XP") == 700
			and player:GetAttribute("Wins") == 8,
		"Settings never change economy or victory progress"
	)
	player.onAttributeWrite = nil
	server.players:remove(player)
	h.advance(0)
	local saved = h.store.records.Player_401
	expect(
		saved.SchemaVersion == 5 and saved.Session == nil and saved.Preferences.ReducedMotion == false,
		"Final save preserves explicit false and releases the v5 profile"
	)
	local nextServer = h.server({})
	local joined = nextServer.players:add(401)
	h.advance(0)
	for _, key in Preferences.Keys do
		expect(
			joined:GetAttribute("Pref" .. key) == chosen[key],
			"Each saved preference survives an independent server rejoin"
		)
	end
	expect(
		joined:GetAttribute("PrefsReady") == true and joined:GetAttribute("PrefsRevision") == 0,
		"Preference acknowledgements restart per session instead of persisting request counters"
	)
	expect(
		joined:GetAttribute("Mastery_Collector") == 3
			and joined:GetAttribute("EquippedTitle") == "Collector"
			and joined:GetAttribute("Flawless_RedLight") == 4,
		"Preference save/rejoin retains all prior mastery fields"
	)
	nextServer:close()
	server:close()
	table.insert(
		scenarios,
		"v4 preferences, late load publication, accepted acknowledgements and independent rejoin"
	)
end

do
	local h = harness()
	local stored: any = Data.fresh(20_000)
	stored.Preferences =
		{ EffectsVolume = -9, MusicVolume = 9, AudioMuted = false, ReducedMotion = true, Unknown = true }
	h.store.records.Player_402 = stored
	local server = h.server({})
	local player = server.players:add(402)
	local atReady = nil
	player.onAttributeWrite = function(name, value)
		if name == "PrefsReady" and value == true then
			atReady = {
				player:GetAttribute("PrefEffectsVolume"),
				player:GetAttribute("PrefMusicVolume"),
				player:GetAttribute("PrefAudioMuted"),
				player:GetAttribute("PrefReducedMotion"),
			}
		end
	end
	h.advance(0)
	expect(
		atReady ~= nil and atReady[1] == 0 and atReady[2] == 1 and atReady[3] == false and atReady[4] == true,
		"Ready is published only after every normalized saved preference"
	)
	expect(
		h.store.records.Player_402.Preferences.Unknown == nil and player:GetAttribute("PrefUnknown") == nil,
		"Unknown stored keys never replicate or survive normalization"
	)
	player.onAttributeWrite = nil
	server:close()
	table.insert(scenarios, "stored preference bounds and initial publication barrier")
end

do
	local h = harness()
	local server = h.server({ autosave = 400 })
	local player = server.players:add(403)
	h.advance(0)
	local writes = h.store.writes
	local malformed = {
		{ "Unknown", true },
		{ "Coins", 999 },
		{ {}, 1 },
		{ 1, true },
		{ "EffectsVolume", -0.1 },
		{ "EffectsVolume", 1.1 },
		{ "EffectsVolume", 0 / 0 },
		{ "EffectsVolume", math.huge },
		{ "MusicVolume", -math.huge },
		{ "MusicVolume", "0.5" },
		{ "MusicVolume", false },
		{ "MusicVolume", {} },
		{ "MusicVolume" },
		{ "AudioMuted", "true" },
		{ "AudioMuted", 1 },
		{ "ReducedMotion", {} },
		{ "ReducedMotion" },
		{ string.rep("A", 25), true },
	}
	for _, request in malformed do
		h.advance(0.6)
		server.remote.OnServerEvent:Fire(player, "SetPreference", request[1], request[2])
		expect(
			player:GetAttribute("PrefsRevision") == 0,
			"Malformed or out-of-range settings request is not acknowledged"
		)
	end
	for _, invalidAction in { {}, false, 12, "SetPreferences", string.rep("a", 99) } do
		h.advance(0.6)
		server.remote.OnServerEvent:Fire(player, invalidAction, "AudioMuted", true)
		expect(
			player:GetAttribute("PrefsRevision") == 0,
			"Only the exact bounded SetPreference action is accepted"
		)
	end
	for _, key in Preferences.Keys do
		expect(player:GetAttribute("Pref" .. key) == nil, "Invalid requests never invent an explicit choice")
	end
	h.advance(3)
	for index = 1, 100 do
		server.remote.OnServerEvent:Fire(
			player,
			"SetPreference",
			"EffectsVolume",
			if index % 2 == 1 then 0.25 else 0.75
		)
	end
	expect(
		player:GetAttribute("PrefsRevision") == 5 and player:GetAttribute("PrefEffectsVolume") == 0.25,
		"One hundred immediate requests accept only the shared five-token burst"
	)
	h.advance(0.6)
	server.remote.OnServerEvent:Fire(player, "SetPreference", "EffectsVolume", 0.25)
	expect(
		player:GetAttribute("PrefsRevision") == 6 and player:GetAttribute("PrefEffectsVolume") == 0.25,
		"Refilled identical request acknowledges without changing its stored value"
	)
	expect(
		h.store.writes == writes
			and player:GetAttribute("Coins") == 0
			and player:GetAttribute("Quest_stars") == 0,
		"Malformed spam, valid spam and duplicate settings perform no datastore request or reward"
	)
	server.players:remove(player)
	server.remote.OnServerEvent:Fire(player, "SetPreference", "EffectsVolume", 1)
	expect(player:GetAttribute("PrefsRevision") == 6, "A departing scope cannot acknowledge new settings")
	server:close()
	table.insert(
		scenarios,
		"preferences reject malformed values and spam while duplicate changes stay idempotent"
	)
end

do
	local h = harness()
	local memory = h.server({ optIn = false })
	local temporary = memory.players:add(404)
	h.advance(0)
	local originalMessage = temporary:GetAttribute("ActionMessage")
	memory.remote.OnServerEvent:Fire(temporary, "SetPreference", "AudioMuted", true)
	expect(
		temporary:GetAttribute("PrefAudioMuted") == nil and temporary:GetAttribute("PrefsRevision") == 0,
		"Unconfirmed temporary profile leaves pre-consent settings local to the client"
	)
	expect(
		temporary:GetAttribute("ActionMessage") == originalMessage,
		"Rejected preference cannot overwrite an important profile-status explanation"
	)
	temporary:SetAttribute("TemporaryPlayAccepted", true)
	memory.remote.OnServerEvent:Fire(temporary, "SetPreference", "AudioMuted", true)
	expect(
		temporary:GetAttribute("PrefAudioMuted") == true
			and temporary:GetAttribute("PrefsRevision") == 1
			and temporary:GetAttribute("DataStatus") == "Session",
		"Accepted temporary setting remains explicitly session-only"
	)
	memory:close()
	expect(h.store.writes == 0, "Temporary preferences never create a cloud record")
	local server = h.server({ autosave = 400 })
	local player = server.players:add(405)
	h.advance(0)
	player:SetAttribute("TemporaryPlayAccepted", true)
	h.advance(181)
	server.remote.OnServerEvent:Fire(player, "SetPreference", "MusicVolume", 0.25)
	expect(
		player:GetAttribute("DataPersistent") == false
			and player:GetAttribute("TemporaryPlayAccepted") == false
			and player:GetAttribute("PrefsRevision") == 0,
		"Expired lease rejects preference write and revokes stale temporary consent"
	)
	player:SetAttribute("TemporaryPlayAccepted", true)
	server.remote.OnServerEvent:Fire(player, "SetPreference", "MusicVolume", 0.25)
	expect(
		player:GetAttribute("PrefMusicVolume") == 0.25
			and player:GetAttribute("PrefsRevision") == 1
			and player:GetAttribute("DataStatus") ~= "Saved",
		"Reconfirmed lease-loss setting is acknowledged only in temporary memory"
	)
	server:close()
	expect(
		next(h.store.records.Player_405.Preferences) == nil,
		"Expired writer cannot persist temporary settings over the cloud profile"
	)
	table.insert(
		scenarios,
		"preference temporary-consent and lease-loss gates never promise persistent saves"
	)
end

do
	local h = harness()
	local saved: any = Data.fresh(20_000)
	saved.Mastery.FirstRun, saved.UnlockedTitles.FirstRun = 1, true
	saved.SchemaVersion = 4
	saved.EquippedTitle = "FirstRun"
	saved.Preferences = { EffectsVolume = 0.5, MusicVolume = 0.25, AudioMuted = false, ReducedMotion = true }
	h.store.records.Player_406 = saved
	local source, replacements = fs.readFile("src/server/ProfileData.luau")
		:gsub("ProfileData.SchemaVersion = 5", "ProfileData.SchemaVersion = 3", 1)
	assert(replacements == 1, "Previous schema-ceiling adapter must actually lower the production guard")
	local oldData = luau.load(source)()
	local oldServer = h.server({ profileModule = oldData })
	local oldPlayer = oldServer.players:add(406)
	h.advance(0)
	expect(
		not oldServer.service.IsReady(oldPlayer) and oldPlayer:GetAttribute("DataPersistent") == false,
		"v3 ceiling refuses loading v4 instead of discarding Preferences"
	)
	oldServer:close()
	expect(
		h.store.writes == 0 and h.store.records.Player_406.Preferences.ReducedMotion == true,
		"Old reader fallback and shutdown leave v4 settings untouched"
	)
	local oldRecord: any = Data.clone(saved)
	oldRecord.SchemaVersion = 3
	oldRecord.Preferences = {}
	h.store.records.Player_407 = oldRecord
	local activeOld = h.server({ profileModule = oldData })
	local activePlayer = activeOld.players:add(407)
	h.advance(0)
	expect(
		activeOld.service.IsReady(activePlayer),
		"A previous-ceiling service can acquire its own supported v3 profile"
	)
	activeOld.service.RecordPractice(activePlayer, 30)
	local upgraded: any = Data.clone(saved)
	upgraded.Session = copy(h.store.records.Player_407.Session)
	upgraded.BestPracticeSeconds = 10
	h.store.records.Player_407 = upgraded
	activeOld.players:remove(activePlayer)
	h.advance(0)
	local kept = h.store.records.Player_407
	expect(
		kept.SchemaVersion == 4
			and kept.BestPracticeSeconds == 10
			and kept.Preferences.MusicVolume == 0.25
			and kept.Preferences.AudioMuted == false
			and kept.Preferences.ReducedMotion == true
			and kept.Mastery.FirstRun == 1
			and kept.UnlockedTitles.FirstRun
			and kept.EquippedTitle == "FirstRun"
			and kept.Session == nil,
		"Active v3 writer fails SchemaChanged then releases only its own lease without replacing v4 preferences or mastery"
	)
	activeOld:close()
	table.insert(
		scenarios,
		"v3 schema-ceiling reader and active writer preserve v4 preferences during rollback"
	)
end

do
	local h = harness()
	local stored = Data.fresh(20_000)
	stored.Coins, stored.XP = 37, 400
	stored.OwnedTrails.Cyan, stored.EquippedTrail = true, "Cyan"
	h.store.records.Player_601 = stored
	local server = h.server({})
	local player = server.players:add(601)
	h.advance(0)
	for _, id in { "Aurora", "Prism", "Solar", "Nova", "Unknown" } do
		server.remote.OnServerEvent:Fire(player, "Purchase", id)
		h.advance(0.6)
		expect(
			player:GetAttribute("Owned_" .. id) ~= true,
			"Unqualified or unknown mastery claims are rejected"
		)
	end
	server.remote.OnServerEvent:Fire(player, "Purchase", { Id = "Aurora", Price = 0 })
	player:SetAttribute("UnlockedTitle_Practice", true)
	server.remote.OnServerEvent:Fire(player, "Purchase", "Aurora")
	expect(
		player:GetAttribute("Owned_Aurora") ~= true,
		"Replicated presentation fields never replace the private unlock proof"
	)
	h.advance(0.6)
	expect(
		server.practiceBridge:Invoke(player, 22.5),
		"A validated practice finish supplies the actual unlock"
	)
	server.remote.OnServerEvent:Fire(player, "Purchase", "Aurora")
	h.advance(0.6)
	server.remote.OnServerEvent:Fire(player, "Purchase", "Aurora")
	expect(
		player:GetAttribute("Owned_Aurora") == true and player:GetAttribute("EquippedTrail") == "Aurora",
		"Actual profile action claims and equips the free style once"
	)
	expect(
		player:GetAttribute("Coins") == 37 and player:GetAttribute("XP") == 400,
		"Free reward and repeated request preserve all earned currencies"
	)
	server.players:remove(player)
	h.advance(0)
	local saved = h.store.records.Player_601
	expect(
		saved.SchemaVersion == 5
			and saved.OwnedTrails.Cyan
			and saved.OwnedTrails.Aurora
			and saved.Session == nil,
		"Saving retains old and new cosmetics in the same v5 profile"
	)
	local replacement = h.server({})
	local joined = replacement.players:add(601)
	h.advance(0)
	expect(
		joined:GetAttribute("Owned_Aurora") == true and joined:GetAttribute("EquippedTrail") == "Aurora",
		"An independent server restores the claimed style"
	)
	replacement.remote.OnServerEvent:Fire(joined, "Purchase", "Aurora")
	replacement.remote.OnServerEvent:Fire(joined, "Equip", "Cyan")
	expect(
		joined:GetAttribute("Coins") == 37 and joined:GetAttribute("EquippedTrail") == "Cyan",
		"Repeat claim after rejoin costs nothing and old cosmetics remain usable"
	)
	replacement:close()
	server:close()
	table.insert(
		scenarios,
		"mastery cosmetic private unlock, malformed claim, replay, old ownership and independent rejoin"
	)
end
do
	local h = harness()
	local record = Data.fresh(20_000)
	record.SchemaVersion = 4
	record.Coins, record.OwnedTrails.Gold = 351, true
	record.Preferences = { MusicVolume = 0.25, AudioMuted = false }
	record.Session = { Owner = "other-server", ExpiresAt = 1728000600 }
	h.store.records.Player_701 = record
	local server = h.server({ timeout = 2 })
	local player = server.players:add(701, false)
	h.advance(2.1)
	expect(
		player:GetAttribute("DataStatus") == "Busy" and player:GetAttribute("CanRetryProfile") == true,
		"Untouched busy fallback offers a manual retry before temporary admission"
	)
	for _, args in { { "RetryLoad", "wrong" }, { "RetryLoad", "", true }, { "RetryLoad", "", nil, "extra" } } do
		server.remote.OnServerEvent:Fire(player, table.unpack(args, 1, if args[4] then 4 else #args))
	end
	expect(player:GetAttribute("ProfileRetryRemaining") == 3, "Malformed retry arguments spend no attempts")
	h.advance(2)
	h.store.records.Player_701.Session = nil
	local publications = {}
	player.onAttributeWrite = function(name, value)
		table.insert(publications, { name, value })
	end
	server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
	expect(
		player:GetAttribute("DataStatus") == "Loading"
			and player:GetAttribute("PrefsReady") == false
			and player:GetAttribute("CanRetryProfile") == false
			and player:GetAttribute("ProfileRetryRemaining") == 2,
		"Retry creates a single loading scope and closes the preference publication barrier"
	)
	server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
	h.advance(0)
	expect(
		player:GetAttribute("DataStatus") == "Saved"
			and player:GetAttribute("Coins") == 351
			and player:GetAttribute("Owned_Gold") == true
			and player:GetAttribute("PrefMusicVolume") == 0.25
			and player:GetAttribute("PrefAudioMuted") == false
			and player:GetAttribute("PrefsReady") == true,
		"Retry after the other server releases restores real progression and preferences"
	)
	expect(
		publications[1][1] == "PrefsReady" and publications[1][2] == false,
		"Clients see unready preferences before any replacement profile values"
	)
	expect(
		player:GetAttribute("TemporaryPlayAccepted") ~= true and player:GetAttribute("InRound") == false,
		"Retry does not accept temporary play or admit a player to a round"
	)
	expect(
		h.store.records.Player_701.SchemaVersion == 5,
		"Retry uses the same v4-to-v5 migration as a fresh join"
	)
	server:close()
	table.insert(
		scenarios,
		"manual busy retry restores cloud snapshot without temporary consent and publishes preferences atomically"
	)
end
do
	local h = harness()
	h.store.failAll = true
	local server = h.server({ timeout = 1 })
	local player = server.players:add(702, false)
	h.advance(1.1)
	expect(player:GetAttribute("CanRetryProfile") == true, "Initial unavailable fallback may be retried")
	for attempt = 1, 3 do
		server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
		for _ = 1, 30 do
			server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
		end
		h.advance(1.1)
		expect(
			player:GetAttribute("ProfileRetryRemaining") == 3 - attempt,
			"Concurrent retry spam starts only one replacement scope"
		)
		local retryAt = player:GetAttribute("ProfileRetryAt")
		expect(retryAt >= 1728000100 + h.now + 9.8, "Failed manual load starts a fresh ten-second cooldown")
		server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
		expect(
			player:GetAttribute("ProfileRetryRemaining") == 3 - attempt,
			"Cooldown requests do not consume another attempt"
		)
		h.advance(10.1)
	end
	expect(
		player:GetAttribute("CanRetryProfile") == false and player:GetAttribute("PrefsReady") == true,
		"Three failed manual attempts leave a usable fallback without an unbounded retry loop"
	)
	local calls = h.store.calls
	server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
	h.advance(1)
	expect(h.store.calls == calls, "Exhausted retry budget issues no further store requests")
	server:close()
	table.insert(scenarios, "manual retry single-flight, ten-second cooldown, spam and three-attempt budget")
end
for _, gate in { "consent", "admission", "progress", "local" } do
	local h = harness()
	if gate ~= "local" then
		h.store.failAll = true
	end
	local server = h.server({ timeout = 1, optIn = gate ~= "local" })
	local player = server.players:add(703, false)
	h.advance(1.1)
	if gate == "consent" then
		player:SetAttribute("TemporaryPlayAccepted", true)
		player:SetAttribute("TemporaryPlayAccepted", false)
	elseif gate == "admission" then
		player:SetAttribute("InRound", true)
		player:SetAttribute("InRound", false)
	elseif gate == "progress" then
		expect(server.service.RecordPractice(player, 25), "Fixture earns real server-side fallback progress")
	end
	local remaining = player:GetAttribute("ProfileRetryRemaining")
	server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
	expect(
		player:GetAttribute("CanRetryProfile") == false
			and player:GetAttribute("ProfileRetryRemaining") == remaining,
		"Consent, previous admission, actual progress or local-only mode permanently blocks scope replacement"
	)
	if gate == "progress" then
		expect(
			player:GetAttribute("BestPracticeSeconds") == 25,
			"Blocked reload retains the earned session record"
		)
	end
	server:close()
end
table.insert(scenarios, "retry cannot replace accepted, played, progressed or Studio-memory profiles")
do
	local h = harness()
	h.store.plans = { { FailBefore = true }, { DelayBefore = 30 } }
	local server = h.server({ timeout = 1 })
	local player = server.players:add(704, false)
	h.advance(1.1)
	expect(
		player:GetAttribute("CanRetryProfile") == true and h.store.inFlight == 1,
		"Fixture leaves old best-effort cleanup in flight while fallback is available"
	)
	server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
	h.advance(0)
	local owner = h.store.records.Player_704.Session.Owner
	expect(player:GetAttribute("DataStatus") == "Saved", "Replacement acquires a distinct new lease")
	h.advance(30)
	expect(
		h.store.records.Player_704.Session.Owner == owner and player:GetAttribute("DataStatus") == "Saved",
		"Late cleanup captured the old immutable owner and cannot release or downgrade the replacement lease"
	)
	server:close()
	table.insert(scenarios, "late failed-load cleanup cannot release a manual retry's new immutable owner")
end
do
	local h = harness()
	h.store.plans = { { FailBefore = true } }
	local server = h.server({ timeout = 1 })
	local player = server.players:add(705, false)
	h.advance(1.1)
	h.store.plans = { { DelayBefore = 20 } }
	server.remote.OnServerEvent:Fire(player, "RetryLoad", "")
	h.advance(0)
	server.players:remove(player)
	h.advance(1.1)
	local joined = server.players:add(705, false)
	h.advance(0)
	local owner = h.store.records.Player_705.Session.Owner
	h.advance(20)
	expect(
		joined:GetAttribute("DataStatus") == "Saved" and h.store.records.Player_705.Session.Owner == owner,
		"A cancelled retry callback cannot overwrite or release a later rejoin's lease"
	)
	server:close()
	table.insert(scenarios, "manual retry departure and rejoin reject late acquisition callbacks")
end
do
	local h = harness()
	local stored = Data.fresh(20_000)
	stored.OwnedTrails.Aurora, stored.EquippedTrail = true, "Aurora"
	stored.Flawless = { PressureWave = 2, ChangingWalls = 3 }
	stored.Preferences = { AudioMuted = false, MusicVolume = 0.25 }
	h.store.records.Player_706 = stored
	local oldSource = fs.readFile("src/server/ProfileData.luau")
		:gsub("ProfileData.SchemaVersion = 5", "ProfileData.SchemaVersion = 4", 1)
	local oldData = luau.load(oldSource)()
	local old = h.server({ profileModule = oldData })
	local player = old.players:add(706, false)
	h.advance(0)
	expect(
		player:GetAttribute("DataStatus") == "Unavailable" and player:GetAttribute("DataPersistent") == false,
		"A v4 ceiling cannot read the v5 catalog profile through obsolete allowlists"
	)
	old:close()
	expect(
		h.store.writes == 0
			and h.store.records.Player_706.OwnedTrails.Aurora
			and h.store.records.Player_706.Flawless.PressureWave == 2
			and h.store.records.Player_706.Preferences.AudioMuted == false,
		"Old-server fallback and cleanup preserve v5 rewards, new rule mastery and preferences"
	)
	local oldRecord = Data.fresh(20_000)
	oldRecord.SchemaVersion = 4
	h.store.records.Player_707 = oldRecord
	local activeOld = h.server({ profileModule = oldData })
	local activePlayer = activeOld.players:add(707)
	h.advance(0)
	activeOld.service.AwardStar(activePlayer)
	local upgraded = Data.clone(stored)
	upgraded.Session = copy(h.store.records.Player_707.Session)
	h.store.records.Player_707 = upgraded
	activeOld.players:remove(activePlayer)
	h.advance(0)
	local kept = h.store.records.Player_707
	expect(
		kept.SchemaVersion == 5
			and kept.OwnedTrails.Aurora
			and kept.EquippedTrail == "Aurora"
			and kept.Flawless.PressureWave == 2
			and kept.Flawless.ChangingWalls == 3
			and kept.Preferences.AudioMuted == false
			and kept.Coins == stored.Coins
			and kept.Session == nil,
		"An already-loaded v4 writer refuses SchemaChanged and releases only its lease, preserving every v5 extension"
	)
	activeOld:close()
	table.insert(
		scenarios,
		"v4 ceiling rejects expanded v5 catalog without losing new cosmetics or rule mastery"
	)
end
print(
	"ProfileService integration: "
		.. checks
		.. " checks across "
		.. #scenarios
		.. " scenarios passed (local adapters; no cloud)"
)
for _, name in scenarios do
	print("  " .. name)
end
