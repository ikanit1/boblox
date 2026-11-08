--!strict
-- Production preferences/settings with deterministic service and GUI adapters.
-- No cloud receipt, native touch footprint, font-layout or listening acceptance is implied.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local Rules = require("../src/shared/PlayerPreferences")
local ProfileStatus = require("../src/shared/ProfileStatus")
local checks, scenarios = 0, 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function signal()
	local listeners = {}
	local s = {}
	function s:Connect(callback)
		local entry = { Active = true, Callback = callback }
		table.insert(listeners, entry)
		return {
			Disconnect = function()
				entry.Active = false
			end,
		}
	end
	function s:Fire(...)
		for _, listener in table.clone(listeners) do
			if listener.Active then
				listener.Callback(...)
			end
		end
	end
	function s:Count()
		local n = 0
		for _, listener in listeners do
			if listener.Active then
				n += 1
			end
		end
		return n
	end
	return s
end
local function attributes(initial)
	local values = initial or {}
	local signals = {}
	local object: any =
		{ AttributeChanged = signal(), CharacterAdded = signal(), CharacterRemoving = signal() }
	function object:GetAttribute(name)
		return values[name]
	end
	function object:GetAttributeChangedSignal(name)
		signals[name] = signals[name] or signal()
		return signals[name]
	end
	function object:SetAttribute(name, value)
		if values[name] ~= value then
			values[name] = value
			self:GetAttributeChangedSignal(name):Fire()
			self.AttributeChanged:Fire(name)
		end
	end
	function object:SubscriptionCount()
		local count = self.AttributeChanged:Count()
		for _, changed in signals do
			count += changed:Count()
		end
		return count
	end
	return object
end

local function preferencesHarness()
	scenarios += 1
	local h: any = { Now = 0, Calls = {}, Heartbeat = signal() }
	h.Player =
		attributes({ DataStatus = "Loading", DataPersistent = false, PrefsReady = false, PrefsRevision = 0 })
	local shared = {
		WaitForChild = function(_, name)
			return name
		end,
	}
	local production = luau.load(fs.readFile("src/client/AudioPreferences.luau"), {
		environment = {
			game = {
				GetService = function(_, name)
					return if name == "RunService"
						then { Heartbeat = h.Heartbeat }
						else {
							WaitForChild = function()
								return shared
							end,
						}
				end,
			},
			require = function(name)
				return if name == "PlayerPreferences" then Rules else ProfileStatus
			end,
			os = {
				clock = function()
					return h.Now
				end,
			},
		},
	})()
	h.Model = production.new(h.Player, {
		FireServer = function(_, action, key, value)
			table.insert(h.Calls, { Action = action, Key = key, Value = value, At = h.Now })
			if h.Throw then
				error("Fixture transport unavailable")
			end
		end,
	})
	function h.Advance(seconds)
		h.Now += seconds
		h.Heartbeat:Fire(seconds)
	end
	function h.Load(saved, temporary)
		for _, key in Rules.Keys do
			h.Player:SetAttribute("Pref" .. key, saved[key])
		end
		h.Player:SetAttribute("DataPersistent", not temporary)
		h.Player:SetAttribute("DataStatus", if temporary then "Session" else "Saved")
		h.Player:SetAttribute("PrefsReady", true)
	end
	function h.Ack(request, reverse)
		local revision = h.Player:GetAttribute("PrefsRevision") + 1
		if reverse then
			h.Player:SetAttribute("PrefsRevision", revision)
		end
		h.Player:SetAttribute("Pref" .. request.Key, request.Value)
		if not reverse then
			h.Player:SetAttribute("PrefsRevision", revision)
		end
	end
	return h
end

do
	local h = preferencesHarness()
	h.Model.Set("MusicVolume", 0.25)
	h.Model.Set("MusicVolume", 0.75)
	h.Model.Set("EffectsVolume", 0.5)
	h.Model.Set("AudioMuted", true)
	expect(
		#h.Calls == 0 and h.Player:GetAttribute("RuleRoomMusicVolume") == 0.75,
		"Loading applies latest choice locally without sending"
	)
	h.Load({ MusicVolume = 0.1, EffectsVolume = 0.8, AudioMuted = false, ReducedMotion = true })
	expect(
		h.Model.Get("MusicVolume") == 0.75
			and h.Model.Get("EffectsVolume") == 0.5
			and h.Model.Get("AudioMuted"),
		"Late load cannot overwrite touched preferences"
	)
	expect(h.Model.Get("ReducedMotion") == true, "Untouched preference adopts the loaded profile")
	expect(
		#h.Calls == 1 and h.Calls[1].Key == "EffectsVolume",
		"Several local edits start only one serialized request"
	)
	h.Advance(0.2)
	expect(#h.Calls == 1, "No burst is sent while waiting for acknowledgement")
	h.Ack(h.Calls[1])
	h.Advance(0.4)
	expect(#h.Calls == 2 and h.Calls[2].Value == 0.75, "Coalesced latest music value sends after cooldown")
	h.Model.Set("MusicVolume", 0.25)
	h.Ack(h.Calls[2], true)
	expect(
		h.Model.Get("MusicVolume") == 0.25,
		"Old in-flight acknowledgement cannot undo a newer local choice"
	)
	h.Advance(0.61)
	expect(
		h.Calls[3].Key == "MusicVolume" and h.Calls[3].Value == 0.25,
		"Newer value survives revision-first replication"
	)
	h.Ack(h.Calls[3])
	h.Advance(0.61)
	expect(
		h.Calls[4].Key == "AudioMuted" and h.Calls[4].Value == true,
		"Boolean mute participates in the same bounded queue"
	)
	h.Ack(h.Calls[4])
	h.Model.Set("ReducedMotion", false)
	h.Advance(0.61)
	expect(
		h.Calls[5].Key == "ReducedMotion" and h.Calls[5].Value == false,
		"Explicit false is not dropped as an absent dirty value"
	)
	h.Ack(h.Calls[5], true)
	for index = 2, #h.Calls do
		expect(
			h.Calls[index].At - h.Calls[index - 1].At >= 0.59,
			"Requests respect the shared remote refill budget"
		)
	end
	expect(
		string.find(h.Player:GetAttribute("RuleRoomPreferenceStatus"), "сохраняется", 1, true)
			~= nil,
		"Acknowledgement describes future profile persistence, not a cloud receipt"
	)
	expect(
		Rules.effectiveReducedMotion(h.Model.Get("ReducedMotion"), true),
		"Saved false can never disable system reduced motion"
	)
	for _, key in { "Volume", "Exploit", "" } do
		expect(not h.Model.Set(key, 1), "Unknown preference key rejected locally")
	end
	for _, value in { -1, 2, math.huge, 0 / 0, "1", true } do
		expect(not h.Model.Set("EffectsVolume", value), "Malformed volume cannot enter queue")
	end
	h.Model.Destroy()
	expect(
		h.Heartbeat:Count() == 0 and h.Player:SubscriptionCount() == 0,
		"Preference destruction disconnects every subscription"
	)
end

do
	local h = preferencesHarness()
	h.Load({}, true)
	h.Model.Set("AudioMuted", true)
	h.Advance(10)
	expect(#h.Calls == 0 and h.Model.Get("AudioMuted"), "Unconsented session still has working local mute")
	expect(
		string.find(h.Player:GetAttribute("RuleRoomPreferenceStatus"), "до выхода", 1, true) ~= nil,
		"Temporary profile never promises saved settings"
	)
	h.Player:SetAttribute("TemporaryPlayAccepted", true)
	expect(#h.Calls == 1, "Accepted temporary play can synchronize its session preference")
	h.Ack(h.Calls[1])
	h.Model.Set("EffectsVolume", 0.25)
	h.Player:SetAttribute("TemporaryPlayAccepted", false)
	h.Advance(3)
	expect(
		#h.Calls == 1 and h.Model.Get("EffectsVolume") == 0.25,
		"Lost admission stops requests but keeps local accessibility controls"
	)
	h.Player:SetAttribute("TemporaryPlayAccepted", true)
	expect(
		#h.Calls == 2 and h.Calls[2].Key == "EffectsVolume",
		"Renewed consent resumes the coalesced local choice"
	)
	h.Model.Destroy()
end

do
	local h = preferencesHarness()
	h.Load({}, false)
	h.Model.Set("MusicVolume", 0.25)
	h.Player:SetAttribute("DataPersistent", false)
	h.Player:SetAttribute("DataStatus", "Unavailable")
	h.Player:SetAttribute("TemporaryPlayAccepted", false)
	h.Advance(3)
	expect(
		#h.Calls == 1 and h.Model.Get("MusicVolume") == 0.25,
		"Lease loss retains local volume without silently continuing requests"
	)
	expect(
		string.find(h.Player:GetAttribute("RuleRoomPreferenceStatus"), "до выхода", 1, true) ~= nil,
		"Lease loss removes any implication of persistent settings"
	)
	h.Player:SetAttribute("TemporaryPlayAccepted", true)
	expect(#h.Calls == 2, "Explicit temporary acceptance resumes the bounded queue after lease loss")
	h.Model.Destroy()
end

for _, throwing in { false, true } do
	local h = preferencesHarness()
	h.Load({}, false)
	h.Throw = throwing
	h.Model.Set("MusicVolume", 0.25)
	for _ = 1, 20 do
		h.Advance(2.1)
	end
	expect(#h.Calls == 3, "Missing acknowledgements or transport errors have a strict three-attempt limit")
	expect(h.Model.Get("MusicVolume") == 0.25, "Timeout never reverts the local choice")
	expect(
		string.find(h.Player:GetAttribute("RuleRoomPreferenceStatus"), "не подтвердил", 1, true)
			~= nil,
		"Exhausted retries are described honestly"
	)
	h.Ack(h.Calls[3], true)
	expect(
		string.find(h.Player:GetAttribute("RuleRoomPreferenceStatus"), "не подтвердил", 1, true)
			== nil,
		"Even a late acknowledgement can clear a bounded timeout"
	)
	h.Model.Set("MusicVolume", 0.5)
	expect(#h.Calls == 4, "A new deliberate choice may retry after a previous timeout")
	h.Model.Destroy()
	h.Advance(10)
	expect(#h.Calls == 4, "Destroyed queue never sends a retry")
end

local methods = {}
local function node(class, name, parent)
	local n = setmetatable({
		props = {
			Name = name,
			ClassName = class,
			Visible = true,
			Selectable = true,
			AbsoluteSize = Roblox.Vector2.new(232, 180),
			AbsolutePosition = Roblox.Vector2.zero,
			AbsoluteCanvasSize = Roblox.Vector2.new(232, 360),
			CanvasPosition = Roblox.Vector2.zero,
			Activated = signal(),
			SelectionGained = signal(),
		},
		children = {},
		signals = {},
		attrs = {},
	}, {
		__index = function(self, key)
			return methods[key] or self.children[key] or self.props[key]
		end,
		__newindex = function(self, key, value)
			local old = self.props[key]
			if key == "Parent" then
				if old then
					old.children[self.Name] = nil
				end
				if value then
					value.children[self.Name] = self
				end
			end
			self.props[key] = value
			if old ~= value and self.signals[key] then
				self.signals[key]:Fire()
			end
		end,
	})
	n.Parent = parent
	return n
end
function methods:IsA(kind)
	return self.ClassName == kind
		or (
			kind == "GuiObject"
			and table.find({ "Frame", "ScrollingFrame", "TextButton", "TextLabel" }, self.ClassName)
				~= nil
		)
end
function methods:FindFirstChild(name)
	return self.children[name]
end
function methods:FindFirstAncestorOfClass(class)
	local parent = self.Parent
	while parent do
		if parent:IsA(class) then
			return parent
		end
		parent = parent.Parent
	end
	return nil
end
function methods:IsDescendantOf(parent)
	local current = self.Parent
	while current do
		if current == parent then
			return true
		end
		current = current.Parent
	end
	return false
end
function methods:GetPropertyChangedSignal(key)
	self.signals[key] = self.signals[key] or signal()
	return self.signals[key]
end
methods.GetAttributeChangedSignal = methods.GetPropertyChangedSignal
function methods:GetAttribute(key)
	return self.attrs[key]
end
function methods:SetAttribute(key, value)
	self.attrs[key] = value
	self:GetAttributeChangedSignal(key):Fire()
end
function methods:Destroy()
	for _, child in table.clone(self.children) do
		child:Destroy()
	end
	self.Parent = nil
end

do
	local h = preferencesHarness()
	local screen = node("ScreenGui", "RuleRoomHUD", nil)
	screen:SetAttribute("StationModal", "")
	local root = node("Frame", "Root", screen)
	root.AbsoluteSize = Roblox.Vector2.new(568, 300)
	local actions = node("Frame", "Actions", root)
	local button = node("TextButton", "Audio", actions)
	local collection = node("Frame", "CollectionPanel", root)
	collection.Visible = false
	local state = attributes({ Phase = "Waiting" })
	local guiSignals = {}
	local gui = {
		SelectedObject = button,
		MenuIsOpen = false,
		ReducedMotionEnabled = false,
		GetPropertyChangedSignal = function(_, name)
			guiSignals[name] = guiSignals[name] or signal()
			return guiSignals[name]
		end,
	}
	local inputName = "Gamepad1"
	local bindings = {}
	local services = {
		GuiService = gui,
		UserInputService = {
			TouchEnabled = true,
			LastInputTypeChanged = signal(),
			GetLastInputType = function()
				return { Name = inputName }
			end,
		},
		ContextActionService = {
			BindAction = function(_, name, callback)
				bindings[name] = callback
			end,
			UnbindAction = function(_, name)
				bindings[name] = nil
			end,
		},
	}
	local production = luau.load(fs.readFile("src/client/AudioSettings.luau"), {
		environment = {
			game = {
				GetService = function(_, name)
					return services[name]
				end,
			},
			Instance = {
				new = function(class)
					return node(class, class, nil)
				end,
			},
			Enum = Roblox.Enum,
			Color3 = Roblox.Color3,
			Vector2 = Roblox.Vector2,
			UDim = Roblox.UDim,
			UDim2 = Roblox.UDim2,
			task = {
				spawn = function(callback)
					callback()
				end,
			},
		},
	})()
	local controller = production.new(root, h.Player, state, button, h.Model)
	local panel = root.AudioSettings
	button.Activated:Fire()
	expect(
		controller.IsOpen() and not h.Model.Get("AudioMuted"),
		"Lobby Audio opens settings without accidentally muting"
	)
	expect(
		panel.Size.X.Offset == 232 and panel.Size.Y.Offset == 284,
		"Short landscape uses the center strip between control areas"
	)
	expect(
		gui.SelectedObject == panel.Options.EffectsVolume.Less,
		"Gamepad starts on a reachable volume action"
	)
	panel.Options.EffectsVolume.Less.Activated:Fire()
	expect(
		h.Model.Get("EffectsVolume") == 0.75 and panel.Options.EffectsVolume.Value.Text == "75%",
		"Touch/gamepad volume steps apply and render immediately during Loading"
	)
	panel.Options.MusicVolume.Less.Activated:Fire()
	expect(
		h.Model.Get("MusicVolume") == 0.25 and h.Model.Get("EffectsVolume") == 0.75,
		"Music and effects controls remain independent"
	)
	panel.Options.Mute.Activated:Fire()
	expect(
		h.Model.Get("AudioMuted") and panel.Options.Mute.Text == "ВЕСЬ ЗВУК: ВЫКЛ",
		"Panel mute controls all game audio explicitly"
	)
	panel.Options.Motion.Toggle.Activated:Fire()
	expect(h.Model.Get("ReducedMotion"), "Reduced motion is an independent saved-choice intent")
	expect(#h.Calls == 0, "Settings remain local while the profile is Loading")
	for _, target in
		{
			panel.Close,
			panel.Options.EffectsVolume.Less,
			panel.Options.EffectsVolume.More,
			panel.Options.MusicVolume.Less,
			panel.Options.MusicVolume.More,
			panel.Options.Mute,
			panel.Options.Motion.Toggle,
		}
	do
		expect(target.Size.Y.Offset >= 44, "Every interactive target is at least 44px tall")
		expect(
			target.NextSelectionUp ~= nil and target.NextSelectionDown ~= nil,
			"Every gamepad target has bounded vertical navigation"
		)
	end
	bindings.RuleRoomCloseAudioSettings(nil, Roblox.Enum.UserInputState.Begin)
	expect(
		not controller.IsOpen() and gui.SelectedObject == button,
		"Gamepad Back closes and restores previous focus"
	)
	inputName = "Touch"
	controller.Open()
	expect(gui.SelectedObject == button, "Touch opening does not force gamepad focus")
	inputName = "Gamepad1"
	services.UserInputService.LastInputTypeChanged:Fire()
	expect(
		gui.SelectedObject == panel.Options.EffectsVolume.Less,
		"Switching from touch to gamepad enters the open panel"
	)
	gui.MenuIsOpen = true
	gui.SelectedObject = nil
	gui:GetPropertyChangedSignal("MenuIsOpen"):Fire()
	expect(gui.SelectedObject == nil, "System menu keeps its own focus")
	gui.MenuIsOpen = false
	gui:GetPropertyChangedSignal("MenuIsOpen"):Fire()
	expect(
		gui.SelectedObject == panel.Options.EffectsVolume.Less,
		"Returning from system menu restores settings navigation"
	)
	controller.Close()
	controller.Open()
	h.Player:SetAttribute("InRound", true)
	expect(not controller.IsOpen(), "Admission closes settings synchronously")
	button.Activated:Fire()
	expect(
		not h.Model.Get("AudioMuted") and not controller.IsOpen(),
		"In-trial Audio remains an immediate mute toggle"
	)
	h.Player:SetAttribute("InRound", false)
	for _, phase in { "Rule", "Break" } do
		state:SetAttribute("Phase", "Waiting")
		controller.Open()
		state:SetAttribute("Phase", phase)
		expect(not controller.IsOpen(), "Dangerous phase closes the panel: " .. phase)
	end
	state:SetAttribute("Phase", "Waiting")
	controller.Open()
	collection.Visible = true
	expect(not controller.IsOpen(), "Collection modal cannot overlap audio settings")
	collection.Visible = false
	controller.Open()
	screen:SetAttribute("StationModal", "Welcome")
	expect(not controller.IsOpen(), "Station modal closes audio settings")
	screen:SetAttribute("StationModal", "")
	controller.Open()
	root.Visible = false
	expect(
		not controller.IsOpen() and gui.SelectedObject == nil,
		"Hidden root closes and avoids restoring invisible focus"
	)
	root.Visible = true
	controller.Open()
	local humanoid = {
		Died = signal(),
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
	expect(not controller.IsOpen(), "Respawn closes audio settings")
	controller.Open()
	humanoid.Died:Fire()
	expect(not controller.IsOpen(), "Death closes audio settings")
	controller.Open()
	controller.Destroy()
	button.Activated:Fire()
	expect(root.AudioSettings == nil and next(bindings) == nil, "Destroy removes panel and Back binding")
	expect(
		button.Activated:Count() == 0 and humanoid.Died:Count() == 0,
		"Destroy disconnects UI and character observers"
	)
	for _, viewport in { { 320, 568 }, { 390, 844 }, { 568, 320 }, { 667, 375 }, { 844, 390 } } do
		local width, height = production.bounds(viewport[1], viewport[2], true)
		if viewport[1] > viewport[2] then
			expect(
				(viewport[1] - width) / 2 >= 168,
				"Supported landscape reserves both standard touch-control columns"
			)
		else
			expect(height + 8 <= viewport[2] - 160, "Portrait leaves the bottom controls outside the panel")
		end
	end
	h.Model.Destroy()
end

print(string.format("AudioSettings: %d checks / %d scenarios passed", checks, scenarios))
