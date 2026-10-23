--!strict
-- Local integration harness, NOT Roblox cloud evidence.
-- Runs the production ProfileService source with deterministic service/network adapters.
-- From project root: lune run tests/ProfileService.integration.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Data = require("../src/server/ProfileData")
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
	return {
		SetAttribute = function(_, name, value)
			values[name] = value
		end,
		GetAttribute = function(_, name)
			return values[name]
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
		function players:add(id)
			local player = attributes()
			player.UserId = id
			player.Parent = self
			player:SetAttribute("InRound", true)
			player:SetAttribute("RunSurvived", 0)
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
			environment = { Color3 = {
				fromRGB = function(r, g, b)
					return { r, g, b }
				end,
			} },
		})()
		config.Persistence.TestPlaceId = 123
		config.Persistence.StudioDataStoreEnabled = options.optIn ~= false
		config.Persistence.RequestTimeoutSeconds = options.timeout or 15
		config.Persistence.AutosaveSeconds = options.autosave or 45
		local shared = {
			WaitForChild = function(_, name)
				assert(name == "EconomyConfig", "Shared module lookup must use production config")
				return config
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
		local serviceModule = luau.load(fs.readFile("src/server/ProfileService.luau"), {
			debugName = "PRODUCTION_ProfileService",
			environment = {
				game = gameAdapter,
				script = { Parent = { ProfileData = Data } },
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
		local server =
			{ service = service, players = players, state = state, remote = remote, config = config }
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
		player:GetAttribute("DataStatus") == "Unavailable" and server.service.IsReady(player),
		"Failed load becomes explicitly session-only"
	)
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
