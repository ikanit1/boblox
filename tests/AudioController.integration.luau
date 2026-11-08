--!strict
-- Production audio controller with local signal/sound adapters; no asset loading or listening proof.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Config = require("../src/shared/AudioConfig")
local checks = 0
local scenarios = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local function signal()
	local entries = {}
	return {
		Connect = function(_, callback)
			local entry = { Active = true, Callback = callback }
			table.insert(entries, entry)
			return {
				Disconnect = function()
					entry.Active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in entries do
				if entry.Active then
					entry.Callback(...)
				end
			end
		end,
	}
end

local function object(attributes: any?)
	local values = attributes or {}
	local signals = {}
	local result: any = { AttributeChanged = signal() }
	function result:GetAttribute(name)
		return values[name]
	end
	function result:GetAttributeChangedSignal(name)
		if not signals[name] then
			signals[name] = signal()
		end
		return signals[name]
	end
	function result:SetAttribute(name, value)
		local previous = values[name]
		values[name] = value
		if previous ~= value then
			if signals[name] then
				signals[name]:Fire()
			end
			self.AttributeChanged:Fire(name)
		end
	end
	return result
end

local function harness(stage: string, reduced: boolean?, options: any?)
	scenarios += 1
	options = options or {}
	local h: any = { Now = 100, Tasks = {}, Instances = {}, Heartbeat = signal() }
	h.Player = object({ InRound = true, LastTrialOutcome = "Playing" })
	h.Player.CharacterAdded = signal()
	h.Player.CharacterRemoving = signal()
	h.Player.PlayerGui = {
		FindFirstChild = function()
			return nil
		end,
	}
	h.State = object({
		Phase = "Rule",
		Round = 1,
		RuleIndex = 1,
		HazardCycle = 1,
		HazardStage = stage,
		PhaseEndsAt = 101,
	})
	h.Gui = object({ ReducedMotion = reduced == true })
	local root = {
		DescendantAdded = signal(),
		DescendantRemoving = signal(),
		GetDescendants = function()
			return {}
		end,
		FindFirstAncestorOfClass = function()
			return h.Gui
		end,
	}
	local muteButton = object()
	muteButton.Activated = signal()
	local function newInstance(className)
		local instance = object()
		instance.ClassName = className
		instance.Loaded = signal()
		instance.IsLoaded = options.loaded ~= false
		function instance:Play()
			if options.playError then
				error("Fixture audio unavailable")
			end
			self.Playing = true
		end
		function instance:Stop()
			self.Playing = false
		end
		function instance:Destroy()
			self.Destroyed = true
		end
		table.insert(h.Instances, instance)
		return instance
	end
	local shared = {
		WaitForChild = function()
			return "AudioConfig"
		end,
	}
	local services = {
		ContentProvider = {
			PreloadAsync = function()
				if options.preloadError then
					error("Fixture preload failure")
				end
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function()
				return shared
			end,
		},
		RunService = { Heartbeat = h.Heartbeat },
		SoundService = {},
		TweenService = {
			Create = function()
				return { Play = function() end, Cancel = function() end }
			end,
		},
		Workspace = {
			GetServerTimeNow = function()
				return h.Now
			end,
		},
	}
	local production = luau.load(fs.readFile("src/client/AudioController.luau"), {
		debugName = "AudioController.production",
		environment = {
			game = {
				GetService = function(_, name)
					return assert(services[name], name)
				end,
			},
			Instance = { new = newInstance },
			TweenInfo = { new = function() end },
			os = {
				clock = function()
					return h.Now
				end,
			},
			task = {
				spawn = function(callback)
					callback()
				end,
				defer = function(callback)
					callback()
				end,
				delay = function(seconds, callback)
					table.insert(h.Tasks, { At = h.Now + seconds, Callback = callback })
				end,
			},
			require = function()
				return Config
			end,
		},
		injectGlobals = true,
	})()
	h.Controller = production.new(h.Player, h.State, root, muteButton)
	h.Folder = h.Instances[1]
	function h:Named(name)
		for _, instance in self.Instances do
			if instance.Name == name then
				return instance
			end
		end
		return nil
	end
	function h:MusicCount()
		return self.Folder:GetAttribute("MusicPlaybackCount") or 0
	end
	function h:Lobby()
		self.State:SetAttribute("Phase", "Waiting")
		self.Player:SetAttribute("InRound", false)
	end
	function h:Count(cue)
		return self.Folder:GetAttribute("Played_" .. cue) or 0
	end
	function h:Advance(seconds)
		self.Now += seconds
		local pending = self.Tasks
		self.Tasks = {}
		for _, entry in pending do
			if entry.At <= self.Now then
				entry.Callback()
			else
				table.insert(self.Tasks, entry)
			end
		end
		self.Heartbeat:Fire(seconds)
	end
	return h
end

do
	local h = harness("Recovery")
	expect(h:Count("Safe") == 0, "Joining mid-recovery does not play a safety transition")
	h.State:SetAttribute("HazardCycle", 2)
	expect(h:Count("Safe") == 0, "A cycle update during recovery is not a new safety transition")
	h.State:SetAttribute("HazardStage", "Warning")
	h:Advance(0.2)
	expect(h:Count("WarningFinal") == 1, "The last warning second starts the rising cue")
	expect(h:Count("Countdown") == 0, "The final warning cue replaces the ordinary tick")
	h:Advance(0.2)
	expect(h:Count("WarningFinal") == 3, "Normal effects play all three final-warning notes")
	h:Advance(0.2)
	expect(h:Count("WarningFinal") == 3, "Repeated heartbeats do not replay the same countdown second")
	h.State:SetAttribute("HazardStage", "Active")
	h:Advance(1)
	h.State:SetAttribute("HazardStage", "Recovery")
	expect(h:Count("Safe") == 1, "Active to recovery starts the safe cue")
	h:Advance(0.2)
	expect(h:Count("Safe") == 2, "Safe cue uses its two-note sequence")
	h.State:SetAttribute("HazardCycle", 3)
	h:Advance(1)
	expect(h:Count("Safe") == 2, "Cycle replication never repeats the completed safe cue")
	h.Controller.Destroy()
end

do
	local h = harness("Warning", true)
	h:Advance(0.1)
	h:Advance(0.3)
	expect(h:Count("WarningFinal") == 1, "Reduced effects use one final-warning note")
	h.State:SetAttribute("HazardStage", "Active")
	h:Advance(1)
	h.State:SetAttribute("HazardStage", "Recovery")
	h:Advance(0.3)
	expect(h:Count("Safe") == 1, "Reduced effects use one safe note")
	h.Controller.Destroy()
end

do
	local h = harness("Warning")
	h:Advance(0.1)
	h.Controller.SetMuted(true)
	h:Advance(0.3)
	expect(h:Count("WarningFinal") == 1, "Muting cancels queued warning notes")
	h.State:SetAttribute("HazardStage", "Active")
	h.State:SetAttribute("HazardStage", "Recovery")
	h.Player:SetAttribute("LastTrialOutcome", "Forfeited")
	expect(h:Count("Safe") == 0 and h:Count("Forfeited") == 0, "Mute suppresses safety and forfeited cues")
	h.Controller.SetMuted(false)
	h.Player:SetAttribute("LastTrialOutcome", "Playing")
	h.Player:SetAttribute("LastTrialOutcome", "Forfeited")
	expect(h:Count("Forfeited") == 1, "Forfeited plays its distinct cue after a live outcome edge")
	expect(
		h:Count("Passed") == 0 and h:Count("Eliminated") == 0,
		"Forfeited never plays success or death cues"
	)
	h.State:SetAttribute("TeamCharge", 5)
	expect(h:Count("Forfeited") == 1, "Unrelated attributes do not replay the outcome cue")
	h.Controller.Destroy()
	h:Advance(2)
	expect(h.Folder.Destroyed == true, "Pending audio tasks tolerate controller cleanup")
end

do
	local h = harness("Recovery")
	h:Lobby()
	h:Advance(1.5)
	expect(h:MusicCount() == 1, "Waiting starts a quiet original laboratory phrase after a short rest")
	local count = 0
	for _, instance in h.Instances do
		if instance.ClassName == "Sound" then
			count += 1
		end
	end
	expect(count == 6, "Audio owns exactly four cue voices and two separate music voices")
	local musicMix, effectsMix = h:Named("RuleRoomMusicMix"), h:Named("RuleRoomMix")
	local baseMusicGain = musicMix.Volume
	h.Player:SetAttribute("Coins", 0)
	h.Player:SetAttribute("Coins", 1)
	expect(musicMix.Volume < baseMusicGain, "A real feedback cue ducks the background")
	h:Advance(0.9)
	expect(
		math.abs(musicMix.Volume - baseMusicGain) < 1e-8,
		"Background returns after the bounded duck window"
	)
	h.Player:SetAttribute("RuleRoomEffectsVolume", 0)
	local rewards = h:Count("Reward")
	h.Player:SetAttribute("Coins", 2)
	expect(
		effectsMix.Volume == 0 and h:Count("Reward") == rewards,
		"Effects zero suppresses cue playback and its group"
	)
	expect(musicMix.Volume > 0, "Effects volume does not mute music")
	h.Player:SetAttribute("RuleRoomEffectsVolume", 0.25)
	h.Player:SetAttribute("RuleRoomMusicVolume", 0)
	expect(musicMix.Volume == 0 and effectsMix.Volume > 0, "Music zero does not mute effects")
	expect(
		not h:Named("Laboratory_1").Playing and not h:Named("Laboratory_2").Playing,
		"Music zero immediately stops both voices"
	)
	h.Player:SetAttribute("RuleRoomMusicVolume", 0.5)
	h:Advance(1.5)
	h.Controller.SetMuted(true)
	expect(musicMix.Volume == 0 and effectsMix.Volume == 0, "Master mute silences both independent groups")
	local stopped = h:MusicCount()
	h:Advance(25)
	expect(h:MusicCount() == stopped, "Muted music schedules no delayed notes")
	h.Controller.SetMuted(false)
	h:Advance(1.5)
	for _, phase in { "Rule", "Break", "Results" } do
		h.State:SetAttribute("Phase", phase)
		stopped = h:MusicCount()
		h:Advance(4)
		expect(
			h:MusicCount() == stopped
				and not h:Named("Laboratory_1").Playing
				and not h:Named("Laboratory_2").Playing,
			"Background is silent outside Waiting/Voting: " .. phase
		)
	end
	h.State:SetAttribute("Phase", "Voting")
	h:Advance(1.5)
	expect(h:MusicCount() > stopped, "Voting permits the laboratory background")
	h.Player:SetAttribute("InRound", true)
	stopped = h:MusicCount()
	h:Advance(2)
	expect(h:MusicCount() == stopped, "Admission stops music even before phase replication")
	h:Lobby()
	h:Advance(1)
	local instanceCount = #h.Instances
	for _ = 1, 3000 do
		h:Advance(0.1)
	end
	expect(#h.Instances == instanceCount, "Five virtual minutes never allocate more music voices")
	expect(#h.Tasks == 0, "Music runs on the existing heartbeat without a delayed-task chain")
	stopped = h:MusicCount()
	h:Advance(100)
	expect(h:MusicCount() <= stopped + 1, "A long scheduling stall never replays a burst of missed notes")
	h.Controller.Destroy()
	h:Advance(100)
	expect(
		h.Folder.Destroyed and not h:Named("Laboratory_1").Playing and not h:Named("Laboratory_2").Playing,
		"Cleanup stops every music voice and invalidates callbacks"
	)
end

for _, options in { { loaded = false, preloadError = true }, { playError = true } } do
	local h = harness("Warning", false, options)
	h:Lobby()
	h:Advance(1.5)
	expect(h:MusicCount() == 0, "Unavailable or rejected music source is silently skipped")
	expect(
		(h.Folder:GetAttribute("PlaybackCount") or 0) == 0,
		"Unavailable cues never report a successful play"
	)
	if options.preloadError then
		expect(
			h.Folder:GetAttribute("PreloadCompleted") == false,
			"Asset load failure is observable without blocking UI"
		)
	else
		expect(
			h.Folder:GetAttribute("MusicPlaybackError") == true,
			"Playback errors are bounded and observable"
		)
	end
	h.Controller.Destroy()
end

do
	local h = harness("Recovery")
	h:Lobby()
	h:Advance(1.5)
	h.Player.CharacterRemoving:Fire()
	local before = h:MusicCount()
	h:Advance(5)
	expect(h:MusicCount() == before, "Character removal stops the phrase until a valid replacement")
	local humanoid = {
		Health = 100,
		HealthChanged = signal(),
		IsA = function(_, name)
			return name == "Humanoid"
		end,
	}
	local character = {
		WaitForChild = function()
			return humanoid
		end,
	}
	h.Player.Character = character
	h.Player.CharacterAdded:Fire(character)
	h:Advance(1.5)
	expect(h:MusicCount() == before + 1, "Healthy replacement resumes eligible lobby music")
	humanoid.Health = 0
	humanoid.HealthChanged:Fire(0)
	before = h:MusicCount()
	h:Advance(5)
	expect(h:MusicCount() == before, "Death stops the background without waiting for respawn")
	h.Controller.Destroy()
	humanoid.HealthChanged:Fire(100)
	h:Advance(3)
	expect(h:MusicCount() == before, "Old health callbacks cannot resurrect destroyed audio")
end

print("AudioController integration: " .. checks .. " checks passed in " .. scenarios .. " scenarios")
