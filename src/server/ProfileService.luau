--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("EconomyConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local ProfileStatus = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("ProfileStatus"))
local PlayerPreferences =
	require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("PlayerPreferences"))
local ProfileData = require(script.Parent.ProfileData)
-- Keep the persistence allowlist tied to the actual game catalog without changing it.
local DataConfig = table.clone(Config)
DataConfig.RuleOrder = GameConfig.RuleOrder
DataConfig.RuleCount = GameConfig.RuleCount
DataConfig.PlayerPreferences = PlayerPreferences

type Profile = ProfileData.Profile
type Scope = {
	player: Player,
	data: Profile,
	owner: string,
	ready: boolean,
	loading: boolean,
	persistent: boolean,
	-- True from a confirmed acquire until our own cloud lease is known to be released.
	leaseHeld: boolean,
	saving: boolean,
	closing: boolean,
	finalizing: boolean,
	finalized: boolean,
	leaseExpires: number,
	nextSave: number,
	tokens: number,
	tokenTime: number,
	lastSurvival: string,
	lastFlawless: string,
	lastRun: number,
	sessionRuns: number,
	preferencesRevision: number,
	retryAttempts: number,
	retryAt: number,
	retryBlocked: boolean,
	status: string,
	admissionConnections: { RBXScriptConnection },
}

export type Service = {
	IsReady: (player: Player) -> boolean,
	AwardSurvival: (player: Player) -> (),
	AwardStar: (player: Player) -> boolean,
	CompleteRun: (player: Player, won: boolean) -> (),
	RecordPractice: (player: Player, seconds: number) -> boolean,
	RecordFlawless: (player: Player, ruleId: string, action: "Collected"?) -> boolean,
	Destroy: () -> (),
}

local ProfileService = {}

local function currentDay(): number
	return ProfileData.day(os.time())
end

function ProfileService.new(): Service
	assert(
		not script.Parent:FindFirstChild("RuleRoomRecordPractice"),
		"ProfileService is already initialized"
	)
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
	local shutdownDeadline: number? = nil
	-- Registry of persistence work (loads, saves, final and deferred releases). It is
	-- independent of `scopes`: a scope may leave that table while its request still runs.
	local pendingWork = 0
	local state = ReplicatedStorage:WaitForChild("RuleRoomState")
	local remotes = ReplicatedStorage:WaitForChild("RuleRoomRemotes")
	local profileAction = remotes:WaitForChild("ProfileAction")
	assert(profileAction:IsA("RemoteEvent"), "RuleRoomRemotes.ProfileAction must be a RemoteEvent")

	local function retryEligible(scope: Scope): boolean
		return not destroyed
			and scopes[scope.player] == scope
			and scope.player.Parent == Players
			and not memoryMode
			and storeAvailable
			and store ~= nil
			and scope.ready
			and not scope.loading
			and not scope.closing
			and not scope.persistent
			and not scope.leaseHeld
			and not scope.retryBlocked
			and scope.retryAttempts < 3
			and (scope.status == "Busy" or scope.status == "Unavailable")
			and scope.player:GetAttribute("TemporaryPlayAccepted") ~= true
			and scope.player:GetAttribute("InRound") ~= true
	end
	local function publishRetry(scope: Scope)
		if scopes[scope.player] ~= scope or scope.player.Parent ~= Players then
			return
		end
		scope.player:SetAttribute("ProfileRetryAt", scope.retryAt)
		scope.player:SetAttribute("ProfileRetryRemaining", math.max(0, 3 - scope.retryAttempts))
		scope.player:SetAttribute("CanRetryProfile", retryEligible(scope))
	end
	local function disconnectAdmission(scope: Scope)
		for _, connection in scope.admissionConnections do
			connection:Disconnect()
		end
		table.clear(scope.admissionConnections)
	end
	local function blockRetry(scope: Scope)
		scope.retryBlocked = true
		publishRetry(scope)
	end

	local function status(scope: Scope, value: string, message: string?)
		if scope.player.Parent ~= Players or scopes[scope.player] ~= scope then
			return
		end
		scope.status = value
		local previousStatus = scope.player:GetAttribute("DataStatus")
		local wasPersistent = scope.player:GetAttribute("DataPersistent")
		if wasPersistent == nil or wasPersistent ~= scope.persistent then
			scope.player:SetAttribute("TemporaryPlayAccepted", false)
		end
		-- Unavailable can mean either a pending autosave retry or permanent memory fallback.
		-- Publish the distinction before DataStatus, so UI never promises an unavailable save.
		scope.player:SetAttribute("DataPersistent", scope.persistent)
		scope.player:SetAttribute("DataStatus", value)
		if message then
			scope.player:SetAttribute("ActionMessage", message)
		elseif value == "Saved" and previousStatus == "Unavailable" then
			scope.player:SetAttribute("ActionMessage", "Сохранение восстановлено.")
		end
		publishRetry(scope)
	end

	local function replicate(scope: Scope)
		local player, data = scope.player, scope.data
		if player.Parent ~= Players or scopes[player] ~= scope then
			return
		end
		player:SetAttribute("Coins", data.Coins)
		player:SetAttribute("XP", data.XP)
		player:SetAttribute("Level", ProfileData.level(data.XP))
		player:SetAttribute("Wins", data.Wins)
		player:SetAttribute("BestRunScore", data.BestRunScore)
		player:SetAttribute("BestRunSurvived", data.BestRunSurvived)
		player:SetAttribute("BestPracticeSeconds", data.BestPracticeSeconds)
		for _, ruleId in GameConfig.RuleOrder do
			player:SetAttribute("Flawless_" .. ruleId, data.Flawless[ruleId] or 0)
		end
		for _, milestone in Config.MasteryMilestones do
			player:SetAttribute("Mastery_" .. milestone.Id, data.Mastery[milestone.Id] or 0)
			player:SetAttribute("UnlockedTitle_" .. milestone.Id, data.UnlockedTitles[milestone.Id] == true)
		end
		player:SetAttribute("EquippedTitle", data.EquippedTitle)
		player:SetAttribute("EquippedTrail", data.EquippedTrail)
		player:SetAttribute("SessionRuns", scope.sessionRuns)
		for _, trail in Config.Trails do
			player:SetAttribute("Owned_" .. trail.Id, data.OwnedTrails[trail.Id] == true)
		end
		for id in Config.Quests do
			player:SetAttribute("Quest_" .. id, data.Quests[id])
			player:SetAttribute("Claimed_" .. id, data.ClaimedQuests[id])
		end
		for _, key in PlayerPreferences.Keys do
			player:SetAttribute("Pref" .. key, data.Preferences[key])
		end
		-- Revision acknowledges an accepted in-memory choice, never a cloud write.
		player:SetAttribute("PrefsRevision", scope.preferencesRevision)
		-- Initial readiness is the publication barrier for all loaded preference fields.
		player:SetAttribute("PrefsReady", scope.ready)
		publishRetry(scope)
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

	local function spawnTracked(callback: () -> ())
		pendingWork += 1
		task.spawn(function()
			local ok, problem = pcall(callback)
			pendingWork -= 1
			if not ok then
				warn("[RuleRoom profiles] Persistence task failed: " .. tostring(problem))
			end
		end)
	end

	-- Follow-up work started after Destroy shares its deadline instead of outliving it.
	local function workDeadline(seconds: number): number
		local deadline = os.clock() + seconds
		return if shutdownDeadline then math.min(deadline, shutdownDeadline) else deadline
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

	-- Clears only our own Session.Owner and keeps the cloud record verbatim. Used after an
	-- uncertain acquire and after lease loss; the memory profile is never written.
	local function releaseOwnLease(scope: Scope, deadline: number)
		if not store then
			return
		end
		while scope.saving and os.clock() < deadline do
			task.wait(0.05)
		end
		if scope.saving or scope.persistent or os.clock() >= deadline then
			return
		end
		scope.saving = true
		local ok = request(function()
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
		end, deadline)
		scope.saving = false
		if ok then
			-- Either released now or the record no longer names us as owner.
			scope.leaseHeld = false
		end
	end

	local closeOut: (scope: Scope, deadline: number) -> ()

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
				scope.leaseHeld = false
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
		if not release and scope.closing and (scope.persistent or scope.leaseHeld) then
			-- A slow autosave may finish after PlayerRemoving exhausted its wait.
			-- Still attempt one serialized, tracked final release when that request returns.
			spawnTracked(function()
				closeOut(scope, workDeadline(8))
			end)
		end
		return committed
	end

	-- Final save with release while the lease is live; otherwise, if this scope once held
	-- a lease, release only our own Session.Owner. Duplicate calls are harmless.
	closeOut = function(scope: Scope, deadline: number)
		if scope.persistent then
			save(scope, true, deadline)
		end
		if not scope.persistent and scope.leaseHeld then
			releaseOwnLease(scope, deadline)
		end
	end

	local function finalize(scope: Scope, deadline: number)
		scope.closing = true
		disconnectAdmission(scope)
		publishRetry(scope)
		if scope.finalizing or scope.finalized then
			return
		end
		scope.finalizing = true
		while scope.loading and os.clock() < deadline do
			task.wait(0.05)
		end
		if not scope.loading then
			closeOut(scope, deadline)
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
						ProfileData.acquire(raw, scope.owner, os.time(), persistence.LeaseSeconds, DataConfig)
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
			local data = ProfileData.normalize(record, currentDay(), DataConfig)
			if data then
				scope.data = data
				scope.persistent = true
				scope.leaseHeld = true
				scope.leaseExpires = record.Session.ExpiresAt
				scope.retryBlocked = true
				status(scope, "Saved", "Прогресс загружен")
			end
		end
		if not scope.persistent then
			if scope.retryAttempts > 0 then
				scope.retryAt = Workspace:GetServerTimeNow() + 10
			end
			status(
				scope,
				if refusal == "Busy" then "Busy" else "Unavailable",
				if refusal == "Busy"
					then "Профиль занят другой сессией. Этот забег без сохранения."
					else "Облако недоступно. Этот забег без сохранения."
			)
			-- Every UpdateAsync attempt may have committed before throwing. This
			-- best-effort cleanup never saves the fresh/session-only fallback profile.
			spawnTracked(function()
				releaseOwnLease(scope, workDeadline(8))
			end)
		end
		scope.loading = false
		scope.ready = not scope.closing and not destroyed
		replicate(scope)
		if scope.closing or destroyed then
			-- If the engine completed after the shutdown/removal deadline, release the
			-- acquired lease as best effort without resurrecting a player scope.
			spawnTracked(function()
				closeOut(scope, workDeadline(8))
			end)
		end
	end

	local function createScope(player: Player, retryAttempts: number, retryAt: number): Scope
		local now = os.clock()
		local scope: Scope = {
			player = player,
			data = ProfileData.fresh(currentDay()),
			owner = game.JobId .. ":" .. HttpService:GenerateGUID(false),
			ready = false,
			loading = true,
			persistent = false,
			leaseHeld = false,
			saving = false,
			closing = false,
			finalizing = false,
			finalized = false,
			leaseExpires = 0,
			nextSave = now + persistence.AutosaveSeconds + math.random() * 8,
			tokens = 5,
			tokenTime = now,
			lastSurvival = "",
			lastFlawless = "",
			lastRun = -1,
			sessionRuns = 0,
			preferencesRevision = 0,
			retryAttempts = retryAttempts,
			retryAt = retryAt,
			retryBlocked = player:GetAttribute("TemporaryPlayAccepted") == true
				or player:GetAttribute("InRound") == true,
			status = "Loading",
			admissionConnections = {},
		}
		for _, name in { "TemporaryPlayAccepted", "InRound" } do
			table.insert(
				scope.admissionConnections,
				player:GetAttributeChangedSignal(name):Connect(function()
					if player:GetAttribute(name) == true then
						blockRetry(scope)
					end
				end)
			)
		end
		return scope
	end

	local function startLoad(scope: Scope)
		local player = scope.player
		scopes[player] = scope
		-- A fresh scope has a fresh immutable owner. Old cleanup can only release its own lease.
		player:SetAttribute("PrefsReady", false)
		player:SetAttribute("NewRecord", "")
		status(scope, "Loading", "Загружаем прогресс…")
		replicate(scope)
		spawnTracked(function()
			load(scope)
		end)
	end
	local function addPlayer(player: Player)
		if scopes[player] or destroyed then
			return
		end
		startLoad(createScope(player, 0, 0))
	end
	local function retryLoad(scope: Scope)
		if not retryEligible(scope) or Workspace:GetServerTimeNow() < scope.retryAt then
			return
		end
		-- Never replace a played temporary profile or reuse an owner captured by an old request.
		scope.closing = true
		disconnectAdmission(scope)
		local replacement =
			createScope(scope.player, scope.retryAttempts + 1, Workspace:GetServerTimeNow() + 10)
		startLoad(replacement)
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
		profileAction.OnServerEvent:Connect(function(player, action, id, value, ...)
			local scope = readyScope(player)
			if not scope or not consume(scope) then
				return
			end
			if action == "RetryLoad" then
				if id == "" and value == nil and select("#", ...) == 0 then
					retryLoad(scope)
				end
				return
			end
			if
				not ProfileStatus.canJoin(
					player:GetAttribute("DataStatus"),
					scope.persistent,
					player:GetAttribute("TemporaryPlayAccepted"),
					nil
				)
			then
				if action ~= "SetPreference" then
					player:SetAttribute(
						"ActionMessage",
						"Сначала выбери «Играть временно»: покупки здесь не сохранятся."
					)
				end
				return
			end
			if type(action) ~= "string" or type(id) ~= "string" or #id > 24 or #action > 13 then
				return
			end
			if action == "SetPreference" then
				if not PlayerPreferences.isValid(id, value) then
					return
				end
				ProfileData.setPreference(scope.data, id, value, PlayerPreferences)
				scope.preferencesRevision += 1
				replicate(scope)
				return
			end
			if
				action ~= "Purchase"
				and action ~= "Equip"
				and action ~= "ClaimQuest"
				and action ~= "EquipTitle"
			then
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
			elseif action == "EquipTitle" then
				changed, message = ProfileData.equipTitle(scope.data, id, Config)
			end
			-- No request yields or calls a datastore. Authority and price stay on server.
			player:SetAttribute("ActionMessage", message)
			if changed or dayChanged then
				if changed then
					blockRetry(scope)
				end
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
				local deadline = os.clock() + persistence.RequestTimeoutSeconds
				spawnTracked(function()
					finalize(scope, deadline)
				end)
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
						spawnTracked(function()
							save(scope, false, now + persistence.RequestTimeoutSeconds)
						end)
					end
				end
			end
		end
	end)

	local service: Service
	local practiceBridge = Instance.new("BindableFunction")
	practiceBridge.Name = "RuleRoomRecordPractice"
	service = {
		IsReady = function(player: Player): boolean
			local scope = readyScope(player)
			return scope ~= nil
				and ProfileStatus.canJoin(
					player:GetAttribute("DataStatus"),
					scope.persistent,
					player:GetAttribute("TemporaryPlayAccepted"),
					nil
				)
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
			ProfileData.reward(scope.data, "Survival", false, currentDay(), Config)
			blockRetry(scope)
			replicate(scope)
		end,
		AwardStar = function(player: Player): boolean
			local scope = readyScope(player)
			if
				not scope
				or player:GetAttribute("InRound") ~= true
				or player:GetAttribute("MovementWarning") == true
			then
				return false
			end
			ProfileData.reward(scope.data, "Star", false, currentDay(), Config)
			blockRetry(scope)
			replicate(scope)
			return true
		end,
		CompleteRun = function(player: Player, won: boolean)
			local scope = readyScope(player)
			local round = state:GetAttribute("Round")
			local survived = player:GetAttribute("RunSurvived")
			if
				not scope
				or type(round) ~= "number"
				or round ~= round
				or math.abs(round) == math.huge
				or type(survived) ~= "number"
				or survived ~= survived
				or math.abs(survived) == math.huge
				or survived < 1
			then
				return
			end
			if scope.lastRun == round then
				return
			end
			scope.lastRun = round
			scope.sessionRuns += 1
			blockRetry(scope)
			ProfileData.reward(scope.data, "Run", won == true, currentDay(), Config)
			local newRecord = ProfileData.recordRun(
				scope.data,
				player:GetAttribute("RunScore"),
				survived,
				GameConfig.RuleCount
			)
			player:SetAttribute("NewRecord", newRecord)
			ProfileData.recordRunMastery(
				scope.data,
				won == true,
				survived,
				player:GetAttribute("RunStars"),
				player:GetAttribute("RunEnergy"),
				GameConfig.RuleCount,
				Config
			)
			replicate(scope)
		end,
		RecordPractice = function(player: Player, seconds: number): boolean
			local scope = readyScope(player)
			if not scope then
				return false
			end
			local improved = ProfileData.recordPractice(scope.data, seconds)
			-- A migrated personal best must not make a valid slower finish ineligible.
			local masteryChanged = ProfileData.recordPracticeMastery(scope.data, seconds, Config)
			if improved or masteryChanged then
				blockRetry(scope)
				replicate(scope)
			end
			return improved
		end,
		RecordFlawless = function(player: Player, ruleId: string, action: "Collected"?): boolean
			local scope = readyScope(player)
			local round, index = state:GetAttribute("Round"), state:GetAttribute("RuleIndex")
			if
				not scope
				or player:GetAttribute("InRound") ~= true
				or player:GetAttribute("MovementWarning") == true
				or (action ~= nil and action ~= "Collected")
				or type(round) ~= "number"
				or round <= 0
				or round % 1 ~= 0
				or type(index) ~= "number"
				or index < 1
				or index > GameConfig.RuleCount
				or index % 1 ~= 0
			then
				return false
			end
			local key = tostring(round) .. ":" .. tostring(index)
			if
				scope.lastFlawless == key
				or type(ruleId) ~= "string"
				or not table.find(GameConfig.RuleOrder, ruleId)
			then
				return false
			end
			local flawlessChanged = ProfileData.recordFlawless(scope.data, ruleId, GameConfig.RuleOrder)
			local masteryChanged = ProfileData.recordCleanCollector(scope.data, ruleId, action, Config)
			if not flawlessChanged and not masteryChanged then
				return false
			end
			scope.lastFlawless = key
			blockRetry(scope)
			replicate(scope)
			return true
		end,
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			practiceBridge:Destroy()
			for _, connection in connections do
				connection:Disconnect()
			end
			local deadline = os.clock() + persistence.ShutdownSeconds
			shutdownDeadline = deadline
			for _, scope in scopes do
				scope.closing = true
				spawnTracked(function()
					finalize(scope, deadline)
				end)
			end
			-- Removed players may still have in-flight saves or deferred releases.
			while (next(scopes) ~= nil or pendingWork > 0) and os.clock() < deadline do
				task.wait(0.05)
			end
		end,
	}
	-- Install the non-yielding callback before publishing the server-only endpoint.
	practiceBridge.OnInvoke = service.RecordPractice
	practiceBridge.Parent = script.Parent
	game:BindToClose(function()
		service.Destroy()
	end)
	return service
end

return ProfileService
