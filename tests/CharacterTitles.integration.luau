--!strict
-- Production CharacterPresentation with native data-model GUI instances and signal adapters.
-- This validates ownership/lifecycle and fixed text, not native rendering or nameplate placement.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local checks, scenarios = 0, 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
local Economy = luau.load(fs.readFile("src/shared/EconomyConfig.luau"), {
	environment = { Color3 = Roblox.Color3 },
})()
local allConnections = {}
local function signal()
	local listeners = {}
	local s: any = {}
	function s:Connect(callback)
		local connection = { Connected = true, callback = callback }
		function connection.Disconnect(handle)
			handle.Connected = false
		end
		table.insert(listeners, connection)
		table.insert(allConnections, connection)
		return connection
	end
	function s:Once(callback)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end
	function s:Fire(...)
		for _, listener in table.clone(listeners) do
			if listener.Connected then
				listener.callback(...)
			end
		end
	end
	return s
end

local function character()
	local model = Roblox.Instance.new("Model")
	local root = Roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	local humanoid = {
		Health = 100,
		Died = signal(),
		IsA = function(_, name)
			return name == "Humanoid"
		end,
	}
	local c = { Model = model, Root = root, Humanoid = humanoid }
	function c:WaitForChild(name)
		return if name == "Humanoid" then humanoid else root
	end
	function c:FindFirstChild(name)
		return if name == "HumanoidRootPart" then root else nil
	end
	function c:FindFirstChildOfClass(name)
		return if name == "Humanoid" then humanoid else nil
	end
	return c
end
local function makePlayer(id)
	local p: any = {
		UserId = id,
		DisplayName = "Fixture " .. id,
		Character = character(),
		CharacterAdded = signal(),
		CharacterRemoving = signal(),
		attributes = {},
		signals = {},
	}
	function p:GetAttribute(name)
		return self.attributes[name]
	end
	function p:GetAttributeChangedSignal(name)
		self.signals[name] = self.signals[name] or signal()
		return self.signals[name]
	end
	function p:SetAttribute(name, value)
		self.attributes[name] = value
		self:GetAttributeChangedSignal(name):Fire()
	end
	p:SetAttribute("DataStatus", "Saved")
	p:SetAttribute("DataPersistent", true)
	p:SetAttribute("EquippedTrail", "None")
	p:SetAttribute("EquippedTitle", "FirstRun")
	p:SetAttribute("UnlockedTitle_FirstRun", true)
	return p
end

local function harness(population)
	scenarios += 1
	local people = {}
	local pending = {}
	for id = 1, population do
		table.insert(people, makePlayer(id))
	end
	local services = {
		Players = {
			GetPlayers = function()
				return people
			end,
			PlayerAdded = signal(),
			PlayerRemoving = signal(),
		},
		Workspace = {
			CurrentCamera = {},
			GetPropertyChangedSignal = function()
				return signal()
			end,
		},
		GuiService = { SelectedObject = nil },
	}
	local button = { Activated = signal(), Visible = false }
	local production = luau.load(fs.readFile("src/client/CharacterPresentation.luau"), {
		debugName = "PRODUCTION_CharacterPresentation_Titles",
		environment = {
			game = {
				GetService = function(_, name)
					return services[name]
				end,
			},
			Instance = Roblox.Instance,
			Enum = Roblox.Enum,
			Color3 = Roblox.Color3,
			Vector3 = Roblox.Vector3,
			UDim2 = Roblox.UDim2,
			NumberSequence = Roblox.NumberSequence,
			NumberSequenceKeypoint = Roblox.NumberSequenceKeypoint,
			ColorSequence = Roblox.ColorSequence,
			task = {
				spawn = function(callback)
					table.insert(pending, callback)
				end,
				defer = function(callback)
					table.insert(pending, callback)
				end,
			},
		},
	})()
	local controller = production.new(people[1], Economy, button)
	local h = { Players = people, Services = services, Controller = controller, Button = button }
	function h.flush()
		local callbacks = table.clone(pending)
		table.clear(pending)
		for _, callback in callbacks do
			callback()
		end
	end
	function h.title(player)
		return player.Character.Root:FindFirstChild("RuleRoomMasteryTitle")
	end
	h.flush()
	return h
end

do
	local h = harness(2)
	local player = h.Players[1]
	local title = h.title(player)
	expect(
		title and title.Title.Text == "Первый шаг",
		"Authoritative unlocked title uses fixed catalog text"
	)
	expect(
		title.MaxDistance == 45 and not title.AlwaysOnTop,
		"Nameplate has bounded distance and does not cover through walls"
	)
	expect(not title.Title.RichText, "Title text never interprets markup")
	player:SetAttribute("EquippedTitle", "<font size='999'>injected</font>")
	expect(h.title(player) == nil, "Unknown arbitrary attribute text never appears above avatars")
	player:SetAttribute("EquippedTitle", "Collector")
	expect(h.title(player) == nil, "Known but locked title stays hidden")
	player:SetAttribute("UnlockedTitle_Collector", true)
	expect(
		h.title(player).Title.Text == "Точный собиратель",
		"Late unlock replication refreshes equipped title"
	)
	player:SetAttribute("DataStatus", "Session")
	player:SetAttribute("DataPersistent", false)
	expect(
		h.title(player).Title.Text == "Точный собиратель · временно",
		"Temporary profile title is visibly labeled temporary"
	)
	player:SetAttribute("InRound", true)
	expect(h.title(player) == nil, "InRound immediately hides title independently of phase replication")
	player:SetAttribute("InRound", false)
	expect(h.title(player) ~= nil, "Returning to lobby permits title again")
	h.Controller.SetPhase("Rule")
	for _, other in h.Players do
		expect(h.title(other) == nil, "Active trial contains no mastery billboards")
	end
	h.Controller.SetPhase("Break")
	expect(h.title(player) == nil, "Inter-trial break keeps arena uncluttered")
	h.Controller.SetPhase("Results")
	expect(h.title(player) ~= nil, "Results lobby may display titles again")
	player:SetAttribute("DataStatus", "Loading")
	expect(h.title(player) == nil, "Loading profile never displays stale earned title")
	player:SetAttribute("DataStatus", "Saved")
	player:SetAttribute("DataPersistent", true)
	for _ = 1, 8 do
		player:SetAttribute("EquippedTitle", "Collector")
	end
	expect(#player.Character.Root:GetChildren() == 1, "Repeated replication retains exactly one billboard")
	player:SetAttribute("EquippedTrail", "Cyan")
	expect(
		player.Character.Root:FindFirstChild("RuleRoomCosmeticTrail") ~= nil,
		"Existing trail still coexists with title"
	)
	h.Controller.SetReducedMotion(true)
	expect(
		player.Character.Root:FindFirstChild("RuleRoomCosmeticTrail") == nil,
		"Reduced motion retains its existing trail policy"
	)
	expect(h.title(player) ~= nil, "Static title is independent of optional animated trail")
	player.Character.Humanoid.Health = 0
	player.Character.Humanoid.Died:Fire()
	expect(h.title(player) == nil, "Death immediately removes stale title")
	local oldCharacter = player.Character
	player.CharacterRemoving:Fire(oldCharacter)
	player.Character = character()
	player.CharacterAdded:Fire(player.Character)
	h.flush()
	expect(
		oldCharacter.Root:FindFirstChild("RuleRoomMasteryTitle") == nil,
		"Respawn disposes the old character's title"
	)
	expect(h.title(player) ~= nil, "Respawn recreates title for current character only")
	local departing = h.Players[2]
	h.Services.Players.PlayerRemoving:Fire(departing)
	table.remove(h.Players, 2)
	h.flush()
	expect(h.title(departing) == nil, "Player departure removes title")
	departing:SetAttribute("EquippedTitle", "FirstRun")
	expect(h.title(departing) == nil, "Departed player has no remaining title listeners")
	h.Controller.Destroy()
	expect(h.title(player) == nil, "Controller destruction removes current title")
	player:SetAttribute("EquippedTitle", "FirstRun")
	expect(h.title(player) == nil, "Destroyed controller does not recreate title")
	oldCharacter.Model:Destroy()
	player.Character.Model:Destroy()
	departing.Character.Model:Destroy()
end

do
	local h = harness(12)
	for _, player in h.Players do
		expect(h.title(player) ~= nil, "Bounded twelve-player roster displays one title each in lobby")
	end
	local joining = makePlayer(13)
	h.Services.Players.PlayerAdded:Fire(joining)
	h.Services.Players.PlayerRemoving:Fire(joining)
	h.flush()
	expect(h.title(joining) == nil, "Departure before asynchronous character setup prevents leaked title")
	local localPlayer = h.Players[1]
	local pendingCharacter = character()
	localPlayer.CharacterRemoving:Fire(localPlayer.Character)
	localPlayer.Character = pendingCharacter
	localPlayer.CharacterAdded:Fire(pendingCharacter)
	h.Controller.Destroy()
	h.flush()
	expect(h.title(localPlayer) == nil, "Destroy before asynchronous setup prevents title resurrection")
	for _, player in h.Players do
		expect(h.title(player) == nil, "Destroy cleans every player's billboard")
		player.Character.Model:Destroy()
	end
	joining.Character.Model:Destroy()
end

do
	local h = harness(2)
	local player = h.Players[1]
	for _, item in Economy.Trails do
		if item.Id ~= "None" then
			player:SetAttribute("EquippedTrail", item.Id)
			local trail = player.Character.Root:FindFirstChild("RuleRoomCosmeticTrail")
			expect(trail ~= nil, "Every catalog style produces a real character Trail")
			expect(
				trail.Color.Keypoints[1].Value == item.Color
					and trail.Color.Keypoints[2].Value == (item.ColorEnd or item.Color),
				"Character uses the same gradient as the preview"
			)
			expect(
				math.abs(trail.Lifetime - (item.Lifetime or 0.28)) < 0.00001,
				"Style lifetime is applied without changing the old default"
			)
			expect(
				math.abs(trail.WidthScale.Keypoints[1].Value - (item.WidthScale or 0.65)) < 0.00001,
				"Style width is applied without changing the old default"
			)
			expect(
				#player.Character.Root:GetChildren() == 4,
				"Repeated changes retain exactly one trail, two attachments and the title"
			)
		end
	end
	h.Controller.SetReducedMotion(true)
	expect(
		player.Character.Root:FindFirstChild("RuleRoomCosmeticTrail") == nil,
		"New styles obey reduced motion"
	)
	h.Controller.Destroy()
	for _, person in h.Players do
		expect(#person.Character.Root:GetChildren() == 0, "Destroy removes every style and attachment")
		person.Character.Model:Destroy()
	end
end
for _, connection in allConnections do
	expect(not connection.Connected, "All production subscriptions are disconnected after cleanup")
end
print(string.format("CharacterTitles: %d checks / %d scenarios passed", checks, scenarios))
