--!strict
-- Immediate local preferences with a bounded, serialized server acknowledgement queue.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("RuleRoomShared")
local Preferences = require(Shared:WaitForChild("PlayerPreferences"))
local ProfileStatus = require(Shared:WaitForChild("ProfileStatus"))
local AudioPreferences = {}
AudioPreferences.LocalAttributes = {
	EffectsVolume = "RuleRoomEffectsVolume",
	MusicVolume = "RuleRoomMusicVolume",
	AudioMuted = "RuleRoomAudioMuted",
	ReducedMotion = "RuleRoomUserReducedMotion",
}

function AudioPreferences.new(player: Player, remote: RemoteEvent)
	local values: { [string]: any } = table.clone(Preferences.Defaults)
	local dirty: { [string]: any } = {}
	local attempts: { [string]: number } = {}
	local failed: { [string]: boolean } = {}
	local receipts: { [string]: { value: any, revision: number } } = {}
	local connections: { RBXScriptConnection } = {}
	local inFlight: { key: string, value: any, revision: number, sentAt: number }? = nil
	local lastSent = -math.huge
	local destroyed = false
	local previouslySendable = false
	local function revision(): number
		local value = player:GetAttribute("PrefsRevision")
		return if typeof(value) == "number"
				and value >= 0
				and value < math.huge
				and value % 1 == 0
			then value
			else 0
	end
	local function sendable(): boolean
		return player:GetAttribute("PrefsReady") == true
			and ProfileStatus.canJoin(
				player:GetAttribute("DataStatus"),
				player:GetAttribute("DataPersistent"),
				player:GetAttribute("TemporaryPlayAccepted"),
				nil
			)
	end
	local function publish()
		for key, name in AudioPreferences.LocalAttributes do
			if player:GetAttribute(name) ~= values[key] then
				player:SetAttribute(name, values[key])
			end
		end
		local view =
			ProfileStatus.describe(player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent"))
		local text = if view.Loading or player:GetAttribute("PrefsReady") ~= true
			then "Работает здесь · профиль загружается"
			elseif view.Temporary then "Без сохранения · настройки до выхода"
			elseif next(failed) then "Работает здесь · профиль не подтвердил"
			elseif next(dirty) then "Применено · ждём подтверждения профиля"
			elseif view.Warning then "Применено · сохранение задерживается"
			else "Применено · сохраняется вместе с профилем"
		player:SetAttribute("RuleRoomPreferenceStatus", text)
	end
	local function step()
		if destroyed then
			return
		end
		local now = os.clock()
		if inFlight and now - inFlight.sentAt >= 2 then
			if (attempts[inFlight.key] or 0) >= 3 then
				failed[inFlight.key] = true
			end
			inFlight = nil
		end
		if not sendable() or inFlight or now - lastSent < 0.6 then
			publish()
			return
		end
		for _, key in Preferences.Keys do
			if dirty[key] ~= nil and not failed[key] then
				local value = dirty[key]
				inFlight = { key = key, value = value, revision = revision(), sentAt = now }
				receipts[key] = { value = value, revision = inFlight.revision }
				attempts[key] = (attempts[key] or 0) + 1
				lastSent = now
				-- A network error consumes this bounded attempt, never the local selection.
				pcall(function()
					remote:FireServer("SetPreference", key, value)
				end)
				break
			end
		end
		publish()
	end
	local function sync()
		if destroyed then
			return
		end
		local canSend = sendable()
		if canSend and not previouslySendable then
			table.clear(failed)
			table.clear(attempts)
		end
		previouslySendable = canSend
		if player:GetAttribute("PrefsReady") == true then
			for _, key in Preferences.Keys do
				local receipt = receipts[key]
				if
					receipt
					and revision() > receipt.revision
					and player:GetAttribute("Pref" .. key) == receipt.value
				then
					if dirty[key] == receipt.value then
						dirty[key], attempts[key], failed[key] = nil, nil, nil
					end
					if inFlight and inFlight.key == key and inFlight.value == receipt.value then
						inFlight = nil
					end
					receipts[key] = nil
				end
				if dirty[key] == nil then
					local stored = player:GetAttribute("Pref" .. key)
					values[key] = if Preferences.isValid(key, stored)
						then stored
						else Preferences.Defaults[key]
				end
			end
		end
		step()
	end
	for _, name in { "PrefsReady", "PrefsRevision", "DataStatus", "DataPersistent", "TemporaryPlayAccepted" } do
		table.insert(connections, player:GetAttributeChangedSignal(name):Connect(sync))
	end
	for _, key in Preferences.Keys do
		table.insert(connections, player:GetAttributeChangedSignal("Pref" .. key):Connect(sync))
	end
	local elapsed = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= 0.1 then
				elapsed = 0
				step()
			end
		end)
	)
	sync()
	return {
		Get = function(key: string): any
			return values[key]
		end,
		Set = function(key: string, value: any): boolean
			if destroyed or not Preferences.isValid(key, value) then
				return false
			end
			values[key], dirty[key] = value, value
			attempts[key], failed[key] = nil, nil
			step()
			return true
		end,
		Destroy = function()
			destroyed = true
			inFlight = nil
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
	}
end

return AudioPreferences
