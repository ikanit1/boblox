--!strict
-- Short, local 2D cues derived from replicated gameplay state. Audio never drives gameplay.
-- Four pooled voices; no remote requests, looping tracks, microphone or external dependencies.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("AudioConfig"))
local AudioController = {}

local function gain(db: number): number
	return 10 ^ (db / 20)
end

local function numberAttribute(source: Instance, name: string): number
	local value = source:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

function AudioController.new(player: Player, state: Instance, root: GuiObject, muteButton: TextButton)
	local folder = Instance.new("Folder")
	folder.Name = "RuleRoomAudio"
	folder:SetAttribute("PlaybackCount", 0)
	folder:SetAttribute("SourcePolicy", "RobloxBundledContent")
	folder.Parent = SoundService
	local group = Instance.new("SoundGroup")
	group.Name = "RuleRoomMix"
	group.Parent = folder
	local connections: { RBXScriptConnection } = {}
	local healthConnection: RBXScriptConnection? = nil
	local buttons: { [GuiButton]: RBXScriptConnection } = {}
	local pools: { [string]: { any } } = {}
	local preload: { Instance } = {}
	local cooldowns: { [string]: number } = {}
	local destroyed = false
	local muted = player:GetAttribute("RuleRoomAudioMuted") == true
	local sequenceEpoch = 0
	local characterEpoch = 0
	local lastRule = ""
	local lastPhase = ""
	local countdownSeen: { [string]: boolean } = {}
	local playbackCount = 0

	local function connect(signal: RBXScriptSignal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	for sourceId, source in Config.Sources do
		local pool = {}
		pools[sourceId] = pool
		folder:SetAttribute("Loaded_" .. sourceId, false)
		for index = 1, source.Voices do
			local sound = Instance.new("Sound")
			sound.Name = sourceId .. "_" .. index
			sound.SoundId = source.SoundId
			sound.Volume = 0
			sound.Looped = false
			sound.SoundGroup = group
			sound.Parent = folder
			table.insert(pool, { Sound = sound, Generation = 0, Until = 0, Priority = -1, Fade = nil })
			connect(sound.Loaded, function()
				if not destroyed then
					folder:SetAttribute("Loaded_" .. sourceId, true)
				end
			end)
			table.insert(preload, sound)
		end
	end

	local function stopAll()
		sequenceEpoch += 1
		for _, pool in pools do
			for _, voice in pool do
				voice.Generation += 1
				voice.Until = 0
				if voice.Fade then
					voice.Fade:Cancel()
					voice.Fade = nil
				end
				voice.Sound:Stop()
			end
		end
	end

	local function applyMute()
		muted = player:GetAttribute("RuleRoomAudioMuted") == true
		group.Volume = if muted or not Config.Enabled then 0 else gain(Config.MasterGainDb)
		muteButton.Text = if muted then "ЗВУК: ВЫКЛ" else "ЗВУК: ВКЛ"
		muteButton:SetAttribute("Muted", muted)
		folder:SetAttribute("Muted", muted)
		if muted then
			stopAll()
		end
	end

	local function playNote(id: string, cue, multiplier: number)
		if destroyed or muted or not Config.Enabled then
			return
		end
		local now = os.clock()
		local selected = nil
		for _, voice in pools[cue.Source] do
			if voice.Sound.IsLoaded then
				if voice.Until <= now then
					selected = voice
					break
				elseif
					cue.Priority >= voice.Priority
					and (
						not selected
						or voice.Priority < selected.Priority
						or (voice.Priority == selected.Priority and voice.Until < selected.Until)
					)
				then
					selected = voice
				end
			end
		end
		-- If a source cannot load, or only higher-priority voices are busy, drop the cue.
		-- This never waits for an asset or delays the HUD/gameplay.
		if not selected then
			return
		end
		local voice = selected
		local sound: Sound = voice.Sound
		if voice.Fade then
			voice.Fade:Cancel()
			voice.Fade = nil
		end
		voice.Generation += 1
		local generation = voice.Generation
		voice.Priority = cue.Priority
		voice.Until = now + cue.Seconds + Config.FadeSeconds
		local ok = pcall(function()
			sound:Stop()
			sound.TimePosition = 0
			sound.PlaybackSpeed = cue.Speed * multiplier
			sound.Volume = gain(cue.GainDb)
			sound:Play()
		end)
		if not ok then
			folder:SetAttribute("PlaybackError", true)
			return
		end
		playbackCount += 1
		folder:SetAttribute("PlaybackCount", playbackCount)
		folder:SetAttribute("LastCue", id)
		folder:SetAttribute("LastPlaybackAt", Workspace:GetServerTimeNow())
		folder:SetAttribute("Played_" .. id, (folder:GetAttribute("Played_" .. id) or 0) + 1)
		task.delay(cue.Seconds, function()
			if destroyed or voice.Generation ~= generation then
				return
			end
			voice.Fade = TweenService:Create(sound, TweenInfo.new(Config.FadeSeconds), { Volume = 0 })
			voice.Fade:Play()
			task.delay(Config.FadeSeconds, function()
				if not destroyed and voice.Generation == generation then
					sound:Stop()
					voice.Until = 0
					voice.Fade = nil
				end
			end)
		end)
	end

	local function cue(id: string)
		if destroyed or muted or not Config.Enabled then
			return
		end
		local definition = Config.Cues[id]
		local now = os.clock()
		if not definition or now < (cooldowns[id] or 0) then
			return
		end
		cooldowns[id] = now + definition.Cooldown
		local epoch = sequenceEpoch
		for index, note in definition.Notes or { 1 } do
			local delaySeconds = (index - 1) * (definition.Spacing or 0)
			if delaySeconds == 0 then
				playNote(id, definition, note)
			else
				task.delay(delaySeconds, function()
					if not destroyed and sequenceEpoch == epoch then
						playNote(id, definition, note)
					end
				end)
			end
		end
	end

	local function renderState()
		local phase = state:GetAttribute("Phase")
		if phase == "Rule" then
			local key = tostring(state:GetAttribute("Round"))
				.. ":"
				.. tostring(state:GetAttribute("RuleIndex"))
			if key ~= lastRule then
				lastRule = key
				table.clear(countdownSeen)
				cue("Rule")
			end
		elseif phase == "Results" and lastPhase ~= "Results" then
			cue(if state:GetAttribute("FinaleSuccess") == true then "Finale" else "RunEnd")
		end
		lastPhase = tostring(phase)
	end

	local function bindCharacter(character: Model)
		characterEpoch += 1
		local epoch = characterEpoch
		if healthConnection then
			healthConnection:Disconnect()
			healthConnection = nil
		end
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if
				destroyed
				or epoch ~= characterEpoch
				or player.Character ~= character
				or not humanoid
				or not humanoid:IsA("Humanoid")
			then
				return
			end
			local previous = humanoid.Health
			healthConnection = humanoid.HealthChanged:Connect(function(value)
				local tookDamage = value < previous
				previous = value
				if
					tookDamage
					and state:GetAttribute("Phase") == "Rule"
					and (player:GetAttribute("InRound") == true or player:GetAttribute("Eliminated") == true)
				then
					cue("Damage")
				end
			end)
		end)
	end

	local function bindButton(instance: Instance)
		if instance:IsA("GuiButton") and instance ~= muteButton and not buttons[instance] then
			buttons[instance] = instance.Activated:Connect(function()
				cue("UI")
			end)
		end
	end
	for _, instance in root:GetDescendants() do
		bindButton(instance)
	end
	connect(root.DescendantAdded, bindButton)
	connect(root.DescendantRemoving, function(instance)
		if instance:IsA("GuiButton") and buttons[instance] then
			buttons[instance]:Disconnect()
			buttons[instance] = nil
		end
	end)
	connect(muteButton.Activated, function()
		local value = not muted
		player:SetAttribute("RuleRoomAudioMuted", value)
		applyMute()
		if not value then
			cue("UI")
		end
	end)
	connect(player:GetAttributeChangedSignal("RuleRoomAudioMuted"), applyMute)
	local previousCoins = player:GetAttribute("Coins")
	connect(player:GetAttributeChangedSignal("Coins"), function()
		local value = numberAttribute(player, "Coins")
		if
			typeof(previousCoins) == "number"
			and value > previousCoins
			and player:GetAttribute("DataStatus") ~= "Loading"
		then
			cue("Reward")
		end
		previousCoins = value
	end)
	connect(player.CharacterAdded, bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
	local statePending = false
	connect(state.AttributeChanged, function()
		if not statePending then
			statePending = true
			task.defer(function()
				statePending = false
				if not destroyed then
					renderState()
				end
			end)
		end
	end)
	local elapsed = 0
	connect(RunService.Heartbeat, function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		if state:GetAttribute("Phase") == "Rule" and player:GetAttribute("InRound") == true then
			local deadline = numberAttribute(state, "PhaseEndsAt")
			local remaining = math.ceil(deadline - Workspace:GetServerTimeNow())
			if remaining >= 1 and remaining <= 3 then
				local key = lastRule .. ":" .. tostring(remaining)
				if not countdownSeen[key] then
					countdownSeen[key] = true
					cue("Countdown")
				end
			end
		end
	end)
	applyMute()
	-- Asset loading is deliberately detached from UI initialization and never waits on Loaded.
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
		if not destroyed then
			folder:SetAttribute("PreloadCompleted", ok)
			for sourceId, pool in pools do
				folder:SetAttribute("Loaded_" .. sourceId, pool[1].Sound.IsLoaded)
			end
		end
	end)
	renderState()

	return {
		SetMuted = function(value: boolean)
			if not destroyed then
				player:SetAttribute("RuleRoomAudioMuted", value)
				applyMute()
			end
		end,
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			stopAll()
			characterEpoch += 1
			if healthConnection then
				healthConnection:Disconnect()
			end
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, connection in buttons do
				connection:Disconnect()
			end
			table.clear(buttons)
			folder:Destroy()
		end,
	}
end

return AudioController
