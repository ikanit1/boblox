--!strict
-- Full production CharacterPresentation with synthetic GUI/camera/social services.
-- These checks are not native touch, gamepad, friendship delivery or camera acceptance.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local checks, scenarios = 0, 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function harness(population: number)
	scenarios += 1
	local h: any = {
		People = {},
		Connections = {},
		Tasks = {},
		FriendCalls = {},
		FriendModes = {},
		Pending = {},
		Created = 0,
	}
	local function signal()
		local listeners = {}
		local value = {}
		function value:Connect(callback)
			local connection = { Connected = true, Callback = callback }
			function connection.Disconnect(handle)
				handle.Connected = false
			end
			table.insert(listeners, connection)
			table.insert(h.Connections, connection)
			return connection
		end
		function value:Once(callback)
			local connection
			connection = self:Connect(function(...)
				connection:Disconnect()
				callback(...)
			end)
			return connection
		end
		function value:Fire(...)
			for _, connection in table.clone(listeners) do
				if connection.Connected then
					connection.Callback(...)
				end
			end
		end
		return value
	end
	local methods = {}
	local function node(class: string, name: string, parent: any?): any
		h.Created += 1
		local value = setmetatable({
			properties = {
				Name = name,
				ClassName = class,
				Visible = true,
				Selectable = class == "TextButton",
				AbsoluteSize = Roblox.Vector2.new(700, 340),
				AbsolutePosition = Roblox.Vector2.zero,
				Activated = signal(),
				SelectionGained = signal(),
				Died = signal(),
				Health = 100,
			},
			children = {},
			propertiesChanged = {},
			attributes = {},
			attributeChanged = {},
		}, {
			__index = function(self, key)
				return methods[key] or self.children[key] or self.properties[key]
			end,
			__newindex = function(self, key, item)
				local previous = self.properties[key]
				if key == "Parent" then
					if previous then
						previous.children[self.Name] = nil
					end
					if item then
						item.children[self.Name] = self
					end
				end
				self.properties[key] = item
				if previous ~= item and self.propertiesChanged[key] then
					self.propertiesChanged[key]:Fire()
				end
			end,
		})
		value.Parent = parent
		return value
	end
	function methods:FindFirstChild(name)
		return self.children[name]
	end
	function methods:WaitForChild(name)
		return assert(self.children[name], "Missing fixture child " .. name)
	end
	function methods:FindFirstChildOfClass(class)
		for _, child in self.children do
			if child:IsA(class) then
				return child
			end
		end
		return nil
	end
	function methods:IsA(class)
		return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part")
	end
	function methods:IsDescendantOf(ancestor)
		local current = self.Parent
		while current do
			if current == ancestor then
				return true
			end
			current = current.Parent
		end
		return false
	end
	function methods:GetPropertyChangedSignal(name)
		self.propertiesChanged[name] = self.propertiesChanged[name] or signal()
		return self.propertiesChanged[name]
	end
	function methods:GetAttribute(name)
		return self.attributes[name]
	end
	function methods:GetAttributeChangedSignal(name)
		self.attributeChanged[name] = self.attributeChanged[name] or signal()
		return self.attributeChanged[name]
	end
	function methods:SetAttribute(name, item)
		if self.attributes[name] ~= item then
			self.attributes[name] = item
			self:GetAttributeChangedSignal(name):Fire()
		end
	end
	function methods:Destroy()
		for _, child in table.clone(self.children) do
			child:Destroy()
		end
		self.Parent = nil
	end
	function h.character()
		local model = node("Model", "Character")
		node("Humanoid", "Humanoid", model)
		node("Part", "HumanoidRootPart", model)
		return model
	end
	local players = { PlayerAdded = signal(), PlayerRemoving = signal() }
	function players:GetPlayers()
		return table.clone(h.People)
	end
	function h.add(id)
		local p = node("Player", "Player" .. id)
		p.UserId, p.DisplayName = id, "Участник " .. id
		p.CharacterAdded, p.CharacterRemoving = signal(), signal()
		p.Character = h.character()
		p:SetAttribute("InRound", id ~= 1)
		p:SetAttribute("Eliminated", id == 1)
		table.insert(h.People, p)
		players.PlayerAdded:Fire(p)
		return p
	end
	function h.remove(p)
		players.PlayerRemoving:Fire(p)
		table.remove(h.People, assert(table.find(h.People, p), "Player exists"))
	end
	for id = 1, population do
		h.add(id)
	end
	h.LocalPlayer = h.People[1]
	function h.LocalPlayer:IsFriendsWithAsync(id)
		table.insert(h.FriendCalls, id)
		local mode = h.FriendModes[id]
		if mode == "Slow" then
			h.Pending[id] = h.Pending[id] or {}
			table.insert(h.Pending[id], coroutine.running())
			return coroutine.yield()
		elseif mode == "Error" then
			error("Synthetic friendship failure")
		end
		return mode == true
	end
	h.Camera = node("Camera", "Camera")
	h.Camera.CameraSubject = h.LocalPlayer.Character.Humanoid
	h.Camera.CameraType = Roblox.Enum.CameraType.Custom
	local workspace = node("Workspace", "Workspace")
	workspace.CurrentCamera = h.Camera
	h.Workspace = workspace
	h.Root = node("Frame", "Root")
	h.Button = node("TextButton", "SpectateNext", h.Root)
	h.Button.AbsoluteSize = Roblox.Vector2.new(206, 44)
	h.Button.AbsolutePosition = Roblox.Vector2.new(480, 60)
	h.Button.Visible = false
	h.Gui = node("GuiService", "GuiService")
	h.Gui.MenuIsOpen = false
	h.Input = {
		LastInputTypeChanged = signal(),
		GetLastInputType = function()
			return { Name = h.InputName or "Gamepad1" }
		end,
	}
	function h.input(name)
		h.InputName = name
		h.Input.LastInputTypeChanged:Fire({ Name = name })
	end
	h.Bindings = {}
	local services = {
		Players = players,
		Workspace = workspace,
		GuiService = h.Gui,
		ContextActionService = {
			BindAction = function(_, name, callback, touch, ...)
				assert(not touch, "Spectator menu must not manufacture touch-control buttons")
				h.Bindings[name] = { Callback = callback, Keys = { ... } }
			end,
			UnbindAction = function(_, name)
				h.Bindings[name] = nil
			end,
		},
		UserInputService = h.Input,
	}
	local production = luau.load(fs.readFile("src/client/CharacterPresentation.luau"), {
		debugName = "PRODUCTION_CharacterPresentation_Spectator",
		environment = {
			game = {
				GetService = function(_, name)
					return assert(services[name], name)
				end,
			},
			Instance = {
				new = function(class)
					return node(class, class)
				end,
			},
			Enum = Roblox.Enum,
			Color3 = Roblox.Color3,
			Vector3 = Roblox.Vector3,
			Vector2 = Roblox.Vector2,
			UDim2 = Roblox.UDim2,
			task = {
				spawn = function(callback)
					table.insert(h.Tasks, coroutine.create(callback))
				end,
				defer = function(callback)
					table.insert(h.Tasks, coroutine.create(callback))
				end,
			},
		},
	})()
	h.Controller = production.new(h.LocalPlayer, { Trails = {} }, h.Button)
	function h.flush()
		for _ = 1, 200 do
			if #h.Tasks == 0 then
				return
			end
			local thread = table.remove(h.Tasks, 1)
			local ok, problem = coroutine.resume(thread)
			assert(ok, tostring(problem))
		end
		error("Fixture task queue exceeded its bound")
	end
	function h.completeFriend(id, index, value)
		local thread = h.Pending[id][index]
		local ok, problem = coroutine.resume(thread, value)
		assert(ok, tostring(problem))
		h.flush()
	end
	function h.open()
		h.Button.Activated:Fire()
		return h.Root.SpectatorPicker
	end
	function h.spectate()
		h.flush()
		h.LocalPlayer:SetAttribute("Eliminated", false)
		h.Controller.SetPhase("Rule")
		h.LocalPlayer:SetAttribute("Eliminated", true)
	end
	function h.destroy()
		h.Controller.Destroy()
		h.Controller.Destroy()
		h.flush()
		for _, connection in h.Connections do
			expect(not connection.Connected, "Destroy disconnects every production observer")
		end
		expect(
			next(h.Bindings) == nil and h.Root.SpectatorPicker == nil,
			"Destroy removes picker and key binding"
		)
	end
	return h
end

do
	local h = harness(4)
	h.FriendModes[2], h.FriendModes[3], h.FriendModes[4] = "Error", true, false
	h.spectate()
	expect(
		h.Camera.CameraSubject == h.People[3].Character.Humanoid,
		"Initial camera prefers an already confirmed friend"
	)
	expect(
		string.find(h.Button.Text, "ДРУГ", 1, true) ~= nil,
		"Friend label requires a successful true response"
	)
	local picker = h.open()
	expect(
		picker.Visible and picker.Players.Player1.Text == "✓ Участник 3 · ДРУГ",
		"Explicit picker sorts a confirmed friend first"
	)
	expect(h.Gui.SelectedObject == picker.Players.Player1, "Gamepad opens on a concrete participant")
	expect(
		picker.Close.Size.Y.Offset == 44 and picker.Players.Player1.Size.Y.Offset == 44,
		"Picker has bounded touch targets"
	)
	expect(
		picker.Position.X.Offset >= 12
			and picker.Position.Y.Offset >= 12
			and picker.Position.X.Offset + picker.Size.X.Offset <= h.Root.AbsoluteSize.X - 12
			and picker.Position.Y.Offset + picker.Size.Y.Offset <= h.Root.AbsoluteSize.Y - 96,
		"Popup remains inside the root and above bottom touch controls"
	)
	picker.Players.Player3.Activated:Fire()
	expect(
		h.Camera.CameraSubject == h.People[4].Character.Humanoid and not picker.Visible,
		"Choosing a named participant changes the camera once and closes the menu"
	)
	expect(
		h.Gui.SelectedObject == h.Button and next(h.Bindings) == nil,
		"Selection returns to the existing button"
	)
	h.open()
	local binding = h.Bindings.RuleRoomSpectatorPicker
	expect(
		#binding.Keys == 2
			and binding.Keys[1] == Roblox.Enum.KeyCode.ButtonB
			and binding.Keys[2] == Roblox.Enum.KeyCode.Escape,
		"Only menu dismissal keys are bound"
	)
	binding.Callback("Close", Roblox.Enum.UserInputState.Begin)
	expect(
		not picker.Visible and h.Gui.SelectedObject == h.Button and next(h.Bindings) == nil,
		"B/Escape dismisses the picker and restores focus"
	)
	h.open()
	h.People[4].Character.Humanoid.Health = 0
	h.People[4].Character.Humanoid.Died:Fire()
	expect(
		h.Camera.CameraSubject == h.People[3].Character.Humanoid,
		"Dead target is replaced by a live participant"
	)
	expect(not picker.Players.Player3.Visible, "Dead target leaves the selectable list")
	h.remove(h.People[3])
	h.flush()
	expect(
		h.Camera.CameraSubject == h.People[2].Character.Humanoid,
		"Departure selects the remaining live participant"
	)
	h.People[2]:SetAttribute("InRound", false)
	expect(
		h.Camera.CameraSubject == h.LocalPlayer.Character.Humanoid
			and not picker.Visible
			and not h.Button.Visible,
		"No eligible targets restores the local camera and closes the menu"
	)
	h.destroy()
end

do
	local h = harness(5)
	h.FriendModes[2], h.FriendModes[3], h.FriendModes[4], h.FriendModes[5] = "Slow", "Slow", true, true
	h.spectate()
	expect(#h.FriendCalls == 2, "At most two asynchronous friendship requests run together")
	expect(
		h.Camera.CameraSubject == h.People[2].Character.Humanoid,
		"Unknown friendship never blocks spectator selection"
	)
	local picker = h.open()
	picker.Players.Player3.Activated:Fire()
	local manuallyChosen = h.People[4]
	h.open()
	h.completeFriend(3, 1, true)
	expect(
		h.Camera.CameraSubject == manuallyChosen.Character.Humanoid,
		"Async friendship completion cannot replace an explicit selection"
	)
	expect(
		string.find(picker.Players.Player1.Text, "Участник 2", 1, true) ~= nil,
		"Late friendship badges do not reorder an open menu under a pending tap"
	)
	expect(#h.FriendCalls == 4, "Completed requests drain the bounded friendship queue")
	picker.Close.Activated:Fire()
	h.remove(h.People[2])
	local replacement = h.add(2)
	h.flush()
	expect(#h.Pending[2] == 2, "Rejoining Player identity starts a fresh generation-bound lookup")
	h.completeFriend(2, 1, true)
	h.open()
	local oldResponseMarked = false
	for _, row in picker.Players.children do
		if
			row.Visible
			and string.find(row.Text or "", "Участник 2", 1, true)
			and string.find(row.Text, "ДРУГ", 1, true)
		then
			oldResponseMarked = true
		end
	end
	expect(not oldResponseMarked, "Stale true response cannot label a rejoined Player as a friend")
	h.completeFriend(2, 2, false)
	expect(
		h.Camera.CameraSubject ~= replacement.Character.Humanoid,
		"Rejoin does not hijack the chosen camera"
	)
	h.destroy()
end

do
	local h = harness(12)
	h.spectate()
	local picker = h.open()
	expect(
		picker.Players.Player11.Visible and not picker.Players.Player12.Visible,
		"Twelve-player session exposes every other living participant"
	)
	local created = h.Created
	for _ = 1, 20 do
		picker.Close.Activated:Fire()
		h.open()
	end
	expect(h.Created == created, "Opening repeatedly reuses bounded picker objects")
	picker.Players.Player11.SelectionGained:Fire()
	expect(picker.Players.CanvasPosition.Y > 0, "Gamepad selection reveals a lower list row")
	h.Root.AbsoluteSize = Roblox.Vector2.new(320, 260)
	expect(
		picker.Size.X.Offset <= 296 and picker.Position.Y.Offset + picker.Size.Y.Offset <= 164,
		"Short viewport keeps the list above reserved bottom controls"
	)
	h.Root.Visible = false
	expect(
		not picker.Visible and next(h.Bindings) == nil and h.Gui.SelectedObject == nil,
		"Hiding the HUD closes picker bindings and focus"
	)
	h.Root.Visible = true
	h.open()
	h.LocalPlayer:SetAttribute("InRound", true)
	expect(
		h.Camera.CameraSubject == h.LocalPlayer.Character.Humanoid
			and not picker.Visible
			and not h.Button.Visible,
		"Admission has priority even before the eliminated attribute clears"
	)
	h.LocalPlayer:SetAttribute("InRound", false)
	h.open()
	h.Controller.SetPhase("Break")
	expect(
		not picker.Visible and h.Camera.CameraSubject == h.LocalPlayer.Character.Humanoid,
		"Leaving the active phase restores the own camera"
	)
	h.destroy()
end

do
	local h = harness(3)
	h.FriendModes[2], h.FriendModes[3] = "Slow", "Slow"
	h.spectate()
	local picker = h.open()
	local oldCharacter = h.LocalPlayer.Character
	h.LocalPlayer.CharacterRemoving:Fire(oldCharacter)
	expect(not picker.Visible and next(h.Bindings) == nil, "Reset closes the open picker before respawn")
	h.LocalPlayer.Character = h.character()
	h.LocalPlayer.CharacterAdded:Fire(h.LocalPlayer.Character)
	h.flush()
	expect(
		h.Camera.CameraSubject == h.LocalPlayer.Character.Humanoid and h.Button.Visible,
		"Respawn returns to the lobby character while keeping an explicit resume button"
	)
	h.open()
	expect(
		h.Camera.CameraSubject ~= h.LocalPlayer.Character.Humanoid and picker.Visible,
		"Explicit resume reopens participant choice"
	)
	h.LocalPlayer.Character.Humanoid.Health = 0
	h.LocalPlayer.Character.Humanoid.Died:Fire()
	expect(
		not picker.Visible and next(h.Bindings) == nil,
		"A new local death releases the picker immediately"
	)
	h.Workspace.CurrentCamera = nil
	expect(not h.Button.Visible, "Missing camera does not expose an unusable selector")
	local replacement = { CameraType = Roblox.Enum.CameraType.Scriptable }
	h.Workspace.CurrentCamera = replacement
	expect(
		replacement.CameraType == Roblox.Enum.CameraType.Custom and replacement.CameraSubject ~= nil,
		"A replaced CurrentCamera reacquires a valid subject"
	)
	h.open()
	h.destroy()
	local subject = replacement.CameraSubject
	h.completeFriend(2, 1, true)
	h.completeFriend(3, 1, true)
	expect(
		replacement.CameraSubject == subject and h.Root.SpectatorPicker == nil,
		"Friendship results arriving after Destroy cannot revive camera or UI ownership"
	)
end

do
	local h = harness(3)
	h.spectate()
	h.input("Touch")
	local picker = h.open()
	expect(h.Gui.SelectedObject == nil, "Touch opens the picker without taking gamepad selection")
	h.input("Gamepad1")
	expect(h.Gui.SelectedObject == picker.Players.Player1, "Switching to gamepad focuses the open picker")
	h.Gui.SelectedObject = picker.Players.Player2
	h.input("Gamepad2")
	expect(h.Gui.SelectedObject == picker.Players.Player2, "Input changes retain an eligible selected row")
	h.Gui.MenuIsOpen = true
	h.Gui.SelectedObject = h.Button
	h.input("MouseMovement")
	h.input("Gamepad1")
	expect(h.Gui.SelectedObject == h.Button, "System menu ownership prevents picker focus changes")
	h.Gui.MenuIsOpen = false
	expect(
		h.Gui.SelectedObject == picker.Players.Player1,
		"Leaving the system menu restores open-picker navigation"
	)
	picker.Close.Activated:Fire()
	h.Gui.MenuIsOpen = true
	h.open()
	expect(h.Gui.SelectedObject == h.Button, "Opening while the system menu is open does not steal selection")
	h.Gui.MenuIsOpen = false
	h.Root.Visible = false
	h.Gui.SelectedObject = h.Button
	h.input("Gamepad1")
	expect(h.Gui.SelectedObject == h.Button, "Hidden HUD never steals focus on an input change")
	h.Root.Visible = true
	h.open()
	h.Controller.SetPhase("Results")
	h.Gui.SelectedObject = h.Button
	h.input("Gamepad1")
	h.Gui.MenuIsOpen = true
	h.Gui.MenuIsOpen = false
	expect(h.Gui.SelectedObject == h.Button, "A finished phase never reacquires closed-picker focus")
	h.destroy()
end

do
	local h = harness(3)
	expect(#h.FriendCalls == 0, "Friendship tasks have not started before the scheduler runs")
	h.destroy()
	expect(#h.FriendCalls == 0, "Destroy prevents scheduled but not yet started friendship requests")
end

print(
	string.format(
		"Spectator: %d checks / %d scenarios passed (synthetic UI/camera/social services)",
		checks,
		scenarios
	)
)
