--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("EconomyConfig"))
local ProfileData = require(script.Parent.ProfileData)

type Profile = ProfileData.Profile
type Scope = {
	player: Player,
	data: Profile,
	owner: string,
	ready: boolean,
	loading: boolean,
	persistent: boolean,
	saving: boolean,
	closing: boolean,
	finalizing: boolean,
	finalized: boolean,
	leaseExpires: number,
	nextSave: number,
	tokens: number,
	tokenTime: number,
	lastSurvival: string,
	lastRun: number,
	sessionRuns: number,
	runCoinsEarned: number,
	runXPEarned: number,
}

export type Service = {
	IsReady: (player: Player) -> boolean,
	BeginRun: () -> (),
	AwardSurvival: (player: Player) -> (),
	AwardStar: (player: Player) -> (),
	CompleteRun: (player: Player, won: boolean) -> (),
	Destroy: () -> (),
}

local ProfileService = {}

local function currentDay(): number
	return ProfileData.day(os.time())
end

function ProfileService.new(): Service
	local persistence = Config.Persistence
	local isStudio = RunService:IsStudio()
	local sandbox = persistence.TestPlaceId > 0 and game.PlaceId == persistence.TestPlaceId
	local memoryMode = isStudio and not (persistence.StudioDataStoreEnabled and sandbox)
	local store = nil
	local storeAvailable = true
	if not memoryMode then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(
				if sandbox then persistence.TestStoreName else persistence.StoreName
			)
		end)
		if ok then
			store = result
		else
			storeAvailable = false
			warn("[RuleRoom profiles] Store unavailable; session-only progression.")
		end
	end

	local scopes: { [Player]: Scope } = {}
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local state = ReplicatedStorage:WaitForChild("RuleRoomState")
	local remotes = ReplicatedStorage:WaitForChild("RuleRoomRemotes")
	local profileAction = remotes:WaitForChild("ProfileAction")
	assert(profileAction:IsA("RemoteEvent"), "RuleRoomRemotes.ProfileAction must be a RemoteEvent")

	local function status(scope: Scope, value: string, message: string?)
		if scope.player.Parent ~= Players then
			return
		end
		scope.player:SetAttribute("DataStatus", value)
		if message then
			scope.player:SetAttribute("ActionMessage", message)
		end
	end

	local function replicateRunEarnings(scope: Scope)
		if scope.player.Parent ~= Players then
			return
		end
		scope.player:SetAttribute("RunCoinsEarned", scope.runCoinsEarned)
		scope.player:SetAttribute("RunXPEarned", scope.runXPEarned)
	end

	local function replicate(scope: Scope)
		local player, data = scope.player, scope.data
		if player.Parent ~= Players then
			return
		end
		player:SetAttribute("Coins", data.Coins)
		player:SetAttribute("XP", data.XP)
		player:SetAttribute("Level", ProfileData.level(data.XP))
		player:SetAttribute("Wins", data.Wins)
		player:SetAttribute("EquippedTrail", data.EquippedTrail)
		player:SetAttribute("SessionRuns", scope.sessionRuns)
		replicateRunEarnings(scope)
		for _, trail in Config.Trails do
			player:SetAttribute("Owned_" .. trail.Id, data.OwnedTrails[trail.Id] == true)
		end
		for id in Config.Quests do
			player:SetAttribute("Quest_" .. id, data.Quests[id])
			player:SetAttribute("Claimed_" .. id, data.ClaimedQuests[id])
		end
	end

	local function reward(scope: Scope, kind: string, won: boolean)
		local coinsBefore, xpBefore = scope.data.Coins, scope.data.XP
		if ProfileData.reward(scope.data, kind, won, currentDay(), Config) then
			-- Count the actual accepted reward, including caps, independently of
			-- purchases, quest claims and profile loads. These fields never persist.
			scope.runCoinsEarned += math.max(0, scope.data.Coins - coinsBefore)
			scope.runXPEarned += math.max(0, scope.data.XP - xpBefore)
		end
	end

	local function budgetReady(): boolean
		local ok, available = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead)
					>= 1
				and DataStoreService:GetRequestBudgetForRequestType(
						Enum.DataStoreRequestType.StandardWrite
					)
					>= 1
		end)
		return ok and available
	end

	local function associatedUsers(player: Player): { number }
		-- Studio's local multi-client identities are negative, not Roblox user IDs.
		return if player.UserId > 0 then { player.UserId } else {}
	end

	-- An in-flight engine request cannot be cancelled. Deadlines bound our retries and
	-- shutdown wait; its callback still rechecks ownership before any late write.
	local function request(callback: () -> any, deadline: number): (boolean, any)
		for attempt = 1, 3 do
			while os.clock() < deadline and not budgetReady() do
				task.wait(0.25)
			end
			if os.clock() >= deadline then
				return false, nil
			end
			local ok, result = pcall(callback)
			if ok then
				return true, result
			end
			local remaining = deadline - os.clock()
			if remaining <= 0 then
				break
			end
			task.wait(math.min(remaining, 2 ^ (attempt - 1) + math.random() * 0.3))
		end
		return false, nil
	end

	local function abandonLease(scope: Scope, reason: string)
		scope.persistent = false
		status(
			scope,
			"Unavailable",
			"Сохранение недоступно. Прогресс действует до выхода."
		)
		warn("[RuleRoom profiles] Session switched to memory: " .. reason)
	end

	local function releaseUncertainAcquire(scope: Scope)
		if not store then
			return
		end
		request(function()
			return store:UpdateAsync("Player_" .. scope.player.UserId, function(raw, keyInfo)
				if scope.persistent then
					return nil
				end
				local released = ProfileData.releaseUncertainAcquire(raw, scope.owner)
				if not released then
					return nil
				end
				return released, associatedUsers(scope.player), if keyInfo then keyInfo:GetMetadata() else {}
			end)
		end, os.clock() + 8)
	end

	local function save(scope: Scope, release: boolean, deadline: number): boolean
		if not scope.persistent or not store then
			return true
		end
		while scope.saving and os.clock() < deadline do
			task.wait(0.05)
		end
		if scope.saving or os.clock() >= deadline then
			return false
		end
		if not scope.persistent then
			return true
		end
		scope.saving = true
		local snapshot = ProfileData.clone(scope.data)
		local writeToken = HttpService:GenerateGUID(false)
		local refusal: string? = nil
		local confirmedExpiry = scope.leaseExpires
		local ok, result = request(function()
			return store:UpdateAsync("Player_" .. scope.player.UserId, function(raw, keyInfo)
				local updated, reason = ProfileData.prepareSave(
					raw,
					snapshot,
					scope.owner,
					os.time(),
					persistence.LeaseSeconds,
					release,
					writeToken
				)
				refusal = reason
				if updated and updated.Session then
					confirmedExpiry = updated.Session.ExpiresAt
				elseif reason == "AlreadyWritten" and raw.Session and raw.Session.Owner == scope.owner then
					confirmedExpiry = raw.Session.ExpiresAt
				end
				if not updated then
					return nil
				end
				local metadata = if keyInfo then keyInfo:GetMetadata() else {}
				return updated, associatedUsers(scope.player), metadata
			end)
		end, deadline)
		scope.saving = false
		local committed = ok and (result ~= nil or refusal == "AlreadyWritten")
		if committed then
			if release then
				scope.persistent = false
			elseif scope.persistent then
				-- The returned receipt is authoritative; never extend locally on an error.
				scope.leaseExpires = confirmedExpiry
				status(scope, "Saved")
			end
		elseif ok and refusal then
			abandonLease(scope, refusal)
		else
			status(
				scope,
				"Unavailable",
				"Не удалось сохранить. Повторим автоматически."
			)
			if os.time() >= scope.leaseExpires then
				abandonLease(scope, "lease expired during an outage")
			end
		end
		if not release and scope.closing and scope.persistent then
			-- A slow autosave may finish after PlayerRemoving exhausted its wait.
			-- Still attempt one serialized final release when that request returns.
			task.spawn(function()
				save(scope, true, os.clock() + 8)
			end)
		end
		return committed
	end

	local function finalize(scope: Scope, deadline: number)
		scope.closing = true
		if scope.finalizing or scope.finalized then
			return
		end
		scope.finalizing = true
		while scope.loading and os.clock() < deadline do
			task.wait(0.05)
		end
		if not scope.loading then
			save(scope, true, deadline)
		end
		scope.finalized = true
		scope.finalizing = false
		if scopes[scope.player] == scope then
			scopes[scope.player] = nil
		end
	end

	local function load(scope: Scope)
		if memoryMode or not storeAvailable then
			scope.ready = true
			scope.loading = false
			status(
				scope,
				if memoryMode then "Session" else "Unavailable",
				if memoryMode
					then "Тестовый режим: прогресс до выхода"
					else "Прогресс до выхода: облако недоступно"
			)
			replicate(scope)
			return
		end
		local deadline = os.clock() + persistence.RequestTimeoutSeconds
		local refusal: string? = nil
		local ok = false
		local record = nil
		-- A rejoin may briefly meet the previous server's final save. Bounded retries
		-- wait for release; they never steal a live lease.
		repeat
			ok, record = request(function()
				return store:UpdateAsync("Player_" .. scope.player.UserId, function(raw, keyInfo)
					if destroyed or scope.closing then
						refusal = "Cancelled"
						return nil
					end
					local acquired, reason =
						ProfileData.acquire(raw, scope.owner, os.time(), persistence.LeaseSeconds, Config)
					refusal = reason
					if not acquired then
						return nil
					end
					return acquired,
						associatedUsers(scope.player),
						if keyInfo then keyInfo:GetMetadata() else {}
				end)
			end, deadline)
			if not ok or record or refusal ~= "Busy" or scope.closing then
				break
			end
			task.wait(math.min(1.5, math.max(0, deadline - os.clock())))
		until os.clock() >= deadline
		if ok and record and record.Session and record.Session.Owner == scope.owner then
			local data = ProfileData.normalize(record, currentDay(), Config)
			if data then
				scope.data = data
				scope.persistent = true
				scope.leaseExpires = record.Session.ExpiresAt
				status(scope, "Saved", "Прогресс загружен")
			end
		end
		if not scope.persistent then
			status(
				scope,
				if refusal == "Busy" then "Busy" else "Unavailable",
				if refusal == "Busy"
					then "Профиль занят другой сессией. Этот забег без сохранения."
					else "Облако недоступно. Этот забег без сохранения."
			)
			-- Every UpdateAsync attempt may have committed before throwing. This
			-- best-effort cleanup never saves the fresh/session-only fallback profile.
			task.spawn(releaseUncertainAcquire, scope)
		end
		scope.loading = false
		scope.ready = not scope.closing and not destroyed
		replicate(scope)
		if scope.closing or destroyed then
			-- If the engine completed after the shutdown/removal deadline, release the
			-- acquired lease as best effort without resurrecting a player scope.
			task.spawn(function()
				save(scope, true, os.clock() + 8)
			end)
		end
	end

	local function addPlayer(player: Player)
		if scopes[player] or destroyed then
			return
		end
		local now = os.clock()
		local scope: Scope = {
			player = player,
			data = ProfileData.fresh(currentDay()),
			owner = game.JobId .. ":" .. HttpService:GenerateGUID(false),
			ready = false,
			loading = true,
			persistent = false,
			saving = false,
			closing = false,
			finalizing = false,
			finalized = false,
			leaseExpires = 0,
			nextSave = now + persistence.AutosaveSeconds + math.random() * 8,
			tokens = 5,
			tokenTime = now,
			lastSurvival = "",
			lastRun = -1,
			sessionRuns = 0,
			runCoinsEarned = 0,
			runXPEarned = 0,
		}
		scopes[player] = scope
		status(scope, "Loading", "Загружаем прогресс…")
		replicate(scope)
		task.spawn(load, scope)
	end

	local function readyScope(player: Player): Scope?
		local scope = scopes[player]
		if destroyed or not scope or not scope.ready or scope.closing or player.Parent ~= Players then
			return nil
		end
		if scope.persistent and os.time() >= scope.leaseExpires then
			abandonLease(scope, "lease expired before a player action")
		end
		return scope
	end

	local function consume(scope: Scope): boolean
		local now = os.clock()
		scope.tokens = math.min(5, scope.tokens + (now - scope.tokenTime) * 2)
		scope.tokenTime = now
		if scope.tokens < 1 then
			return false
		end
		scope.tokens -= 1
		return true
	end

	table.insert(
		connections,
		profileAction.OnServerEvent:Connect(function(player, action, id)
			local scope = readyScope(player)
			if not scope or not consume(scope) then
				return
			end
			if type(action) ~= "string" or type(id) ~= "string" or #id > 24 or #action > 12 then
				return
			end
			if action ~= "Purchase" and action ~= "Equip" and action ~= "ClaimQuest" then
				return
			end
			local dayChanged = ProfileData.rollDay(scope.data, currentDay())
			local changed, message = false, "Неизвестное действие"
			if action == "Purchase" then
				changed, message = ProfileData.purchase(scope.data, id, Config)
			elseif action == "Equip" then
				changed, message = ProfileData.equip(scope.data, id)
			elseif action == "ClaimQuest" then
				changed, message = ProfileData.claim(scope.data, id, currentDay(), Config)
			end
			-- No request yields or calls a datastore. Authority and price stay on server.
			player:SetAttribute("ActionMessage", message)
			if changed or dayChanged then
				replicate(scope)
			end
		end)
	)
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			local scope = scopes[player]
			if scope then
				task.spawn(finalize, scope, os.clock() + persistence.RequestTimeoutSeconds)
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end

	task.spawn(function()
		while not destroyed do
			task.wait(1)
			local now = os.clock()
			for _, scope in scopes do
				if scope.ready and not scope.closing then
					if ProfileData.rollDay(scope.data, currentDay()) then
						replicate(scope)
					end
					if scope.persistent and not scope.saving and now >= scope.nextSave then
						scope.nextSave = now + persistence.AutosaveSeconds + math.random() * 8
						task.spawn(save, scope, false, now + persistence.RequestTimeoutSeconds)
					end
				end
			end
		end
	end)

	local service: Service
	service = {
		IsReady = function(player: Player): boolean
			return readyScope(player) ~= nil
		end,
		BeginRun = function()
			if destroyed then
				return
			end
			for _, scope in scopes do
				if not scope.closing and scope.player.Parent == Players then
					scope.runCoinsEarned = 0
					scope.runXPEarned = 0
					replicateRunEarnings(scope)
				end
			end
		end,
		AwardSurvival = function(player: Player)
			local scope = readyScope(player)
			if not scope or player:GetAttribute("InRound") ~= true then
				return
			end
			local key = tostring(state:GetAttribute("Round"))
				.. ":"
				.. tostring(state:GetAttribute("RuleIndex"))
			if scope.lastSurvival == key then
				return
			end
			scope.lastSurvival = key
			reward(scope, "Survival", false)
			replicate(scope)
		end,
		AwardStar = function(player: Player)
			local scope = readyScope(player)
			if not scope or player:GetAttribute("InRound") ~= true then
				return
			end
			reward(scope, "Star", false)
			replicate(scope)
		end,
		CompleteRun = function(player: Player, won: boolean)
			local scope = readyScope(player)
			local round = state:GetAttribute("Round")
			local survived = player:GetAttribute("RunSurvived")
			if not scope or type(round) ~= "number" or type(survived) ~= "number" or survived < 1 then
				return
			end
			if scope.lastRun == round then
				return
			end
			scope.lastRun = round
			scope.sessionRuns += 1
			reward(scope, "Run", won == true)
			replicate(scope)
		end,
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			local deadline = os.clock() + persistence.ShutdownSeconds
			for _, scope in scopes do
				scope.closing = true
				task.spawn(finalize, scope, deadline)
			end
			while next(scopes) ~= nil and os.clock() < deadline do
				task.wait(0.05)
			end
		end,
	}
	game:BindToClose(function()
		service.Destroy()
	end)
	return service
end

return ProfileService
