--!strict
-- Short, local 2D cues derived from replicated gameplay state. Audio never drives gameplay.
-- Four cue voices and two quiet laboratory voices; no audio remotes or external assets.
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

local function volumeAttribute(player: Player, name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number"
			and value == value
			and math.abs(value) < math.huge
		then math.clamp(value, 0, 1)
		else fallback
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
	local musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "RuleRoomMusicMix"
	musicGroup.Parent = folder
	local connections: { RBXScriptConnection } = {}
	local healthConnection: RBXScriptConnection? = nil
	local buttons: { [GuiButton]: RBXScriptConnection } = {}
	local pools: { [string]: { any } } = {}
	local preload: { Instance } = {}
	local cooldowns: { [string]: number } = {}
	local destroyed = false
	local muted = player:GetAttribute("RuleRoomAudioMuted") == true
	local effectsVolume = 1
	local musicVolume = 0.5
	local musicVoices: { any } = {}
	local musicStartedAt: number? = nil
	local musicIndex = 1
	local musicCount = 0
	local duckUntil = 0
	local characterAlive = true
	local sequenceEpoch = 0
	local characterEpoch = 0
	local lastRule = ""
	local lastResultRun = -1
	local lastStage = ""
	local lastOutcome = ""
	local teamReady = false
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

	for index = 1, Config.Music.Voices do
		local sound = Instance.new("Sound")
		sound.Name = "Laboratory_" .. index
		sound.SoundId = Config.Sources.Tone.SoundId
		sound.Volume = 0
		sound.Looped = false
		sound.SoundGroup = musicGroup
		sound.Parent = folder
		table.insert(musicVoices, { Sound = sound, Until = 0, Playing = false })
		table.insert(preload, sound)
	end
	folder:SetAttribute("MusicPlaybackCount", 0)

	local function stopMusic()
		musicStartedAt = nil
		musicIndex = 1
		for _, voice in musicVoices do
			voice.Sound:Stop()
			voice.Sound.Volume = 0
			voice.Playing = false
			voice.Until = 0
		end
		folder:SetAttribute("MusicActive", false)
	end

	local function stopCues()
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
	local function stopAll()
		stopCues()
		stopMusic()
	end
	local function musicGain(now: number)
		musicGroup.Volume = if muted or not Config.Enabled
			then 0
			else gain(Config.MasterGainDb) * musicVolume * (if now < duckUntil
				then Config.Music.DuckGain
				else 1)
	end
	local function updateMusic()
		local phase = state:GetAttribute("Phase")
		if
			destroyed
			or muted
			or not Config.Enabled
			or musicVolume <= 0
			or not characterAlive
			or player:GetAttribute("InRound") == true
			or (phase ~= "Waiting" and phase ~= "Voting")
		then
			if musicStartedAt then
				stopMusic()
			end
			return
		end
		local now = os.clock()
		musicGain(now)
		if not musicStartedAt then
			musicStartedAt = now + 1.5
			musicIndex = 1
			folder:SetAttribute("MusicActive", true)
		end
		local elapsedMusic = now - musicStartedAt
		if elapsedMusic >= Config.Music.LoopSeconds then
			musicStartedAt += math.floor(elapsedMusic / Config.Music.LoopSeconds) * Config.Music.LoopSeconds
			elapsedMusic = now - musicStartedAt
			musicIndex = 1
		end
		for _, voice in musicVoices do
			if voice.Playing then
				local remaining = voice.Until - now
				if remaining <= 0 then
					voice.Sound:Stop()
					voice.Playing = false
				else
					voice.Sound.Volume = gain(Config.Music.GainDb)
						* math.min(1, remaining / Config.Music.FadeSeconds)
				end
			end
		end
		-- Skip notes missed during a stall; never catch up with an audible burst.
		local played = false
		while musicIndex <= #Config.Music.Notes and Config.Music.Notes[musicIndex].At <= elapsedMusic do
			local note = Config.Music.Notes[musicIndex]
			musicIndex += 1
			if not played and elapsedMusic - note.At <= 0.25 then
				for _, voice in musicVoices do
					if not voice.Playing and voice.Sound.IsLoaded then
						local ok = pcall(function()
							voice.Sound:Stop()
							voice.Sound.TimePosition = 0
							voice.Sound.PlaybackSpeed = note.Speed
							voice.Sound.Volume = gain(Config.Music.GainDb)
							voice.Sound:Play()
						end)
						if ok then
							voice.Playing = true
							voice.Until = now + Config.Music.Seconds + Config.Music.FadeSeconds
							musicCount += 1
							folder:SetAttribute("MusicPlaybackCount", musicCount)
						else
							folder:SetAttribute("MusicPlaybackError", true)
						end
						played = true
						break
					end
				end
			end
		end
	end

	local function applyMute()
		muted = player:GetAttribute("RuleRoomAudioMuted") == true
		effectsVolume = volumeAttribute(player, "RuleRoomEffectsVolume", 1)
		musicVolume = volumeAttribute(player, "RuleRoomMusicVolume", 0.5)
		group.Volume = if muted or not Config.Enabled then 0 else gain(Config.MasterGainDb) * effectsVolume
		musicGain(os.clock())
		muteButton:SetAttribute("Muted", muted)
		folder:SetAttribute("Muted", muted)
		if muted then
			stopAll()
		elseif effectsVolume == 0 then
			stopCues()
		end
		if musicVolume == 0 then
			stopMusic()
		end
		updateMusic()
	end

	local function playNote(id: string, cue, multiplier: number)
		if destroyed or muted or effectsVolume <= 0 or not Config.Enabled then
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
		duckUntil = math.max(duckUntil, now + Config.Music.DuckSeconds)
		musicGain(now)
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

	local function reducedMotion(): boolean
		local screen = root:FindFirstAncestorOfClass("ScreenGui")
		return screen ~= nil and screen:GetAttribute("ReducedMotion") == true
	end

	local function cue(id: string)
		if destroyed or muted or effectsVolume <= 0 or not Config.Enabled then
			return
		end
		local definition = Config.Cues[id]
		local now = os.clock()
		if not definition or now < (cooldowns[id] or 0) then
			return
		end
		cooldowns[id] = now + definition.Cooldown
		local epoch = sequenceEpoch
		local notes = if reducedMotion() and definition.ReducedNotes
			then definition.ReducedNotes
			else definition.Notes or { 1 }
		for index, note in notes do
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
		updateMusic()
		local phase = state:GetAttribute("Phase")
		local participating = player:GetAttribute("InRound") == true
		if phase == "Rule" and participating then
			local key = tostring(state:GetAttribute("Round"))
				.. ":"
				.. tostring(state:GetAttribute("RuleIndex"))
			if key ~= lastRule then
				lastRule = key
				lastStage = ""
				teamReady = false
				table.clear(countdownSeen)
				cue("Rule")
			end
			local stageName = tostring(state:GetAttribute("HazardStage"))
			local stageKey = key .. ":" .. tostring(state:GetAttribute("HazardCycle")) .. ":" .. stageName
			if stageKey ~= lastStage then
				local previousStage = lastStage
				lastStage = stageKey
				if stageName == "Active" then
					cue("Danger")
				elseif stageName == "Warning" and previousStage ~= "" then
					cue("Warning")
				elseif
					stageName == "Recovery"
					and previousStage ~= ""
					and not string.match(previousStage, ":Recovery$")
				then
					-- Only a live transition counts; joining mid-Recovery stays silent.
					-- A separately replicated cycle index must not replay the safe cue.
					cue("Safe")
				end
			end
			local goal = numberAttribute(state, "TeamGoal")
			if
				state:GetAttribute("RuleId") == "ReactorRush"
				and goal > 0
				and numberAttribute(state, "TeamCharge") >= goal
				and not teamReady
			then
				teamReady = true
				cue("TeamReady")
			end
		elseif
			phase == "Results"
			and player:GetAttribute("ResultReady") == true
			and player:GetAttribute("LobbyOnly") ~= true
			and lastResultRun ~= numberAttribute(state, "Round")
		then
			lastResultRun = numberAttribute(state, "Round")
			cue(if player:GetAttribute("RunResult") == "Won" then "Finale" else "RunEnd")
		end
		local outcome = tostring(player:GetAttribute("LastTrialOutcome"))
		-- Playing/Pending reset this edge. A global index reset at Voting must not replay a win.
		if outcome ~= lastOutcome then
			lastOutcome = outcome
			if player:GetAttribute("LobbyOnly") ~= true then
				if outcome == "Survived" then
					cue("Passed")
				elseif outcome == "Eliminated" then
					cue("Eliminated")
				elseif outcome == "Forfeited" then
					-- Survived, reward withdrawn: neither the success chime nor the defeat cue.
					cue("Forfeited")
				end
			end
		end
	end

	local function bindCharacter(character: Model)
		characterAlive = false
		stopMusic()
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
			characterAlive = previous > 0
			updateMusic()
			healthConnection = humanoid.HealthChanged:Connect(function(value)
				local tookDamage = value < previous
				previous = value
				characterAlive = value > 0
				if not characterAlive then
					stopMusic()
				end
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
	local stationGui = player.PlayerGui:FindFirstChild("StationHUD")
	if stationGui then
		for _, instance in stationGui:GetDescendants() do
			bindButton(instance)
		end
		connect(stationGui.DescendantAdded, bindButton)
	end
	connect(root.DescendantAdded, bindButton)
	connect(root.DescendantRemoving, function(instance)
		if instance:IsA("GuiButton") and buttons[instance] then
			buttons[instance]:Disconnect()
			buttons[instance] = nil
		end
	end)
	connect(player:GetAttributeChangedSignal("RuleRoomAudioMuted"), applyMute)
	connect(player:GetAttributeChangedSignal("RuleRoomEffectsVolume"), applyMute)
	connect(player:GetAttributeChangedSignal("RuleRoomMusicVolume"), applyMute)
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
	connect(player.CharacterRemoving, function()
		characterEpoch += 1
		characterAlive = false
		stopAll()
		if healthConnection then
			healthConnection:Disconnect()
			healthConnection = nil
		end
	end)
	connect(player.AttributeChanged, function(name)
		if name == "InRound" or name == "LastTrialOutcome" or name == "ResultReady" then
			task.defer(function()
				if not destroyed then
					renderState()
				end
			end)
		elseif name == "LobbyOnly" and player:GetAttribute("LobbyOnly") == true then
			stopAll()
		end
	end)
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
		updateMusic()
		if
			state:GetAttribute("Phase") == "Rule"
			and state:GetAttribute("HazardStage") == "Warning"
			and player:GetAttribute("InRound") == true
		then
			local deadline = numberAttribute(state, "PhaseEndsAt")
			local remaining = math.ceil(deadline - Workspace:GetServerTimeNow())
			if remaining >= 1 and remaining <= 3 then
				local key = lastRule
					.. ":"
					.. tostring(state:GetAttribute("HazardCycle"))
					.. ":"
					.. tostring(remaining)
				if not countdownSeen[key] then
					countdownSeen[key] = true
					-- The final second rises instead of ticking, so "move now" sounds different.
					cue(if remaining == 1 then "WarningFinal" else "Countdown")
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
