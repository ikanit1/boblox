--!strict
-- Local instance/signal adapters execute production preview and menu code; no native rendering proof.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local Hints = require("../src/shared/PlayerHints")
local ProfileStatus = require("../src/shared/ProfileStatus")
local checks = 0
local scenarios = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local Economy = luau.load(fs.readFile("src/shared/EconomyConfig.luau"), {
	environment = { Color3 = Roblox.Color3 },
})()
local Preview = luau.load(fs.readFile("src/client/CollectionPreview.luau"), {
	environment = {
		Instance = Roblox.Instance,
		Color3 = Roblox.Color3,
		Vector3 = Roblox.Vector3,
		CFrame = Roblox.CFrame,
		UDim2 = Roblox.UDim2,
		Enum = Roblox.Enum,
	},
})()

do
	scenarios += 1
	local container = Roblox.Instance.new("Frame")
	local function row()
		local frame = Roblox.Instance.new("Frame")
		frame.Parent = container
		for name, class in { Action = "TextButton", Preview = "TextButton", Detail = "TextLabel" } do
			local child = Roblox.Instance.new(class)
			child.Name = name
			child.Parent = frame
		end
		return frame
	end
	local first, second = row(), row()
	local controller = Preview.new()
	expect(controller.Toggle(first, Economy.Trails[2]), "A catalog item opens a local appearance sample")
	expect(controller.CurrentId() == "Cyan", "Preview selection is local to the controller")
	local viewport = first.AppearancePreview
	-- Lune's read adapter does not expose ViewportFrame.CurrentCamera; inspect the owned camera child.
	expect(
		viewport:IsA("ViewportFrame") and viewport.PreviewCamera:IsA("Camera"),
		"Sample owns its viewport camera"
	)
	expect(
		#viewport.AppearanceSample:GetChildren() == 18,
		"Preview has bounded mannequin and ribbon geometry"
	)
	for _, object in viewport.AppearanceSample:GetChildren() do
		expect(
			object.Anchored and not object.CanCollide and not object.CanTouch and not object.CanQuery,
			"Preview geometry cannot affect gameplay physics"
		)
	end
	expect(
		first.PreviewCaption.Text == "ПРИМЕРКА НА МАНЕКЕНЕ · БЕЗ ПОКУПКИ",
		"Preview is explicitly distinguished from ownership"
	)
	expect(
		first.Action.Position.Y.Offset >= 180 and first.Size.Y.Offset >= 230,
		"Actions sit below the preview content"
	)
	controller.Toggle(second, Economy.Trails[3])
	expect(
		first:FindFirstChild("AppearancePreview") == nil and first.Size.Y.Offset == 160,
		"Switching items disposes and collapses the old preview"
	)
	expect(controller.CurrentId() == "Pink", "Only the new item remains selected")
	controller.Toggle(second, Economy.Trails[3])
	expect(
		controller.CurrentId() == nil and second:FindFirstChild("AppearancePreview") == nil,
		"Activating the current preview toggles it off"
	)
	controller.Toggle(first, Economy.Trails[1])
	expect(
		#first.AppearancePreview.AppearanceSample:GetChildren() == 6,
		"No-trail sample contains the mannequin only"
	)
	controller.Clear()
	expect(first:FindFirstChild("AppearancePreview") == nil, "Clear removes all preview instances")
	controller.Toggle(first, Economy.Trails[2])
	first:Destroy()
	controller.Clear()
	expect(controller.CurrentId() == nil, "Cleanup tolerates an already destroyed catalog row")
	controller.Destroy()
	expect(
		not controller.Toggle(second, Economy.Trails[2]),
		"A destroyed controller cannot recreate the sample"
	)
	container:Destroy()
end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local listener = { Callback = callback, Active = true }
			table.insert(listeners, listener)
			return {
				Disconnect = function()
					listener.Active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, listener in listeners do
				if listener.Active then
					listener.Callback(...)
				end
			end
		end,
	}
end

local methods = {}
local function node(class: string, name: string, parent: any?): any
	local object = setmetatable({
		properties = {
			Name = name,
			ClassName = class,
			Visible = true,
			Selectable = true,
			Active = true,
			AbsolutePosition = Roblox.Vector2.zero,
			AbsoluteSize = Roblox.Vector2.new(500, 200),
			AbsoluteCanvasSize = Roblox.Vector2.new(500, 1000),
			CanvasPosition = Roblox.Vector2.zero,
			Activated = signal(),
			SelectionGained = signal(),
		},
		children = {},
		signals = {},
	}, {
		__index = function(self, key)
			return methods[key] or self.children[key] or self.properties[key]
		end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				local previous = self.properties.Parent
				if previous then
					previous.children[self.Name] = nil
				end
				if value then
					value.children[self.Name] = self
				end
			end
			self.properties[key] = value
		end,
	})
	object.Parent = parent
	return object
end
function methods:FindFirstChild(name)
	return self.children[name]
end
function methods:WaitForChild(name)
	return assert(self.children[name], "Missing fixture child: " .. name)
end
function methods:IsA(class)
	return self.ClassName == class or class == "GuiObject"
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
function methods:GetPropertyChangedSignal(name)
	self.signals[name] = self.signals[name] or signal()
	return self.signals[name]
end
methods.GetAttributeChangedSignal = methods.GetPropertyChangedSignal
function methods:GetAttribute(name)
	return self.properties["Attribute_" .. name]
end
function methods:SetAttribute(name, value)
	self.properties["Attribute_" .. name] = value
	self:GetAttributeChangedSignal(name):Fire()
	if self.AttributeChanged then
		self.AttributeChanged:Fire(name)
	end
end
function methods:Destroy()
	for _, child in table.clone(self.children) do
		child:Destroy()
	end
	self.Parent = nil
end
function methods:Clone()
	local copy = node(self.ClassName, self.Name)
	for key, value in self.properties do
		if key ~= "Parent" and key ~= "Activated" and key ~= "SelectionGained" then
			copy.properties[key] = value
		end
	end
	for _, child in self.children do
		child:Clone().Parent = copy
	end
	return copy
end

local function menuHarness()
	scenarios += 1
	local now = 100
	local screen = node("ScreenGui", "Screen")
	local root = node("Frame", "Root", screen)
	local actions = node("Frame", "Actions", root)
	node("TextButton", "Collection", actions)
	local panel = node("Frame", "CollectionPanel", root)
	panel.Visible = false
	for _, name in { "Close", "CosmeticsTab", "QuestsTab" } do
		node("TextButton", name, panel)
	end
	node("TextLabel", "Message", panel)
	node("ScrollingFrame", "Items", panel)
	node("Frame", "CollectionBackdrop", root)
	local template = node("Frame", "RowTemplate", panel)
	for _, name in { "Title", "Detail" } do
		node("TextLabel", name, template)
	end
	node("Frame", "Swatch", template)
	node("TextButton", "Action", template)
	local player = node("Player", "Player")
	player.AttributeChanged = signal()
	player.CharacterAdded = signal()
	for name, value in { DataStatus = "Saved", DataPersistent = true, Coins = 500, EquippedTrail = "None" } do
		player:SetAttribute(name, value)
	end
	local calls = {}
	local remote = {
		FireServer = function(_, action, id)
			table.insert(calls, { action, id })
		end,
	}
	local selected: string? = nil
	local preview = {
		Toggle = function(_, trail)
			selected = if selected == trail.Id then nil else trail.Id
		end,
		Clear = function()
			selected = nil
		end,
		Destroy = function()
			selected = nil
		end,
	}
	local guiService = { MenuIsOpen = false, SelectedObject = nil }
	local input = {
		LastInputTypeChanged = signal(),
		GetLastInputType = function()
			return { Name = "Gamepad1" }
		end,
	}
	local replicated = node("Folder", "ReplicatedStorage")
	local shared = node("Folder", "RuleRoomShared", replicated)
	for _, name in { "ProfileStatus", "PlayerHints", "GameConfig" } do
		node("ModuleScript", name, shared)
	end
	local folder = node("Folder", "Client")
	node("ModuleScript", "CollectionPreview", folder)
	local services = {
		UserInputService = input,
		GuiService = guiService,
		ContextActionService = { BindAction = function() end, UnbindAction = function() end },
		ReplicatedStorage = replicated,
	}
	local modules = {
		CollectionPreview = {
			new = function()
				return preview
			end,
		},
		ProfileStatus = ProfileStatus,
		PlayerHints = Hints,
		GameConfig = { RuleOrder = { "SafeColor", "LaserSweep" }, RuleCount = 6 },
	}
	local production = luau.load(fs.readFile("src/client/CollectionPanel.luau"), {
		environment = {
			game = {
				GetService = function(_, name)
					return services[name]
				end,
			},
			script = { Parent = folder },
			require = function(module)
				return modules[module.Name]
			end,
			Enum = Roblox.Enum,
			Vector2 = Roblox.Vector2,
			Color3 = Roblox.Color3,
			UDim2 = Roblox.UDim2,
			os = {
				clock = function()
					return now
				end,
			},
			task = {
				defer = function(callback)
					callback()
				end,
			},
		},
	})()
	local controller = production.new(root, player, remote, Economy)
	return {
		Controller = controller,
		Panel = panel,
		Player = player,
		GuiService = guiService,
		Calls = calls,
		Row = function(id)
			return panel.Items:FindFirstChild("Item_" .. id)
		end,
		Selected = function()
			return selected
		end,
		Advance = function()
			now += 0.5
		end,
	}
end

do
	local h = menuHarness()
	h.Controller.Open()
	local cyan = h.Row("Cyan")
	expect(
		cyan.Preview.Size.Y.Offset == 44 and cyan.Action.Size.Y.Offset == 44,
		"Preview and purchase retain separate touch targets"
	)
	expect(
		cyan.Action.NextSelectionLeft == cyan.Preview and cyan.Preview.NextSelectionRight == cyan.Action,
		"Gamepad can navigate between preview and purchase"
	)
	cyan.Preview.Activated:Fire()
	expect(
		h.Selected() == "Cyan" and #h.Calls == 0,
		"Preview activation sends no server purchase or equip intent"
	)
	expect(
		h.Player:GetAttribute("Coins") == 500 and h.Player:GetAttribute("EquippedTrail") == "None",
		"Try-on never changes coins or equipped attributes"
	)
	cyan.Action.Activated:Fire()
	expect(
		#h.Calls == 1 and h.Calls[1][1] == "Purchase" and h.Calls[1][2] == "Cyan",
		"Only the explicit purchase button sends its original allowlisted intent"
	)
	cyan.Action.Activated:Fire()
	expect(#h.Calls == 1, "Rapid repeat of the purchase action is still throttled")
	h.Player:SetAttribute("Owned_Cyan", true)
	h.Player:SetAttribute("EquippedTrail", "Cyan")
	expect(cyan.Action.Text == "НАДЕТО ✓", "Authoritative equip updates while preview is open")
	h.Panel.Close.Activated:Fire()
	expect(
		h.Selected() == nil and h.Player:GetAttribute("EquippedTrail") == "Cyan",
		"Closing preview preserves the actual server-equipped item"
	)
	h.Controller.Destroy()
end

do
	local h = menuHarness()
	h.Controller.Open()
	h.Row("Cyan").Preview.Activated:Fire()
	h.Player.CharacterAdded:Fire({})
	expect(h.Selected() == nil, "Respawn clears the local preview")
	h.Row("Cyan").Preview.Activated:Fire()
	h.Panel.QuestsTab.Activated:Fire()
	expect(
		h.Selected() == nil and h.Row("Cyan") == nil,
		"Changing tab clears preview before destroying catalog rows"
	)
	h.Panel.CosmeticsTab.Activated:Fire()
	h.Row("Pink").Preview.Activated:Fire()
	h.Controller.SetPhase("Rule")
	expect(
		h.Selected() == nil and not h.Controller.IsOpen(),
		"Starting an active trial clears and closes preview"
	)
	h.Row("Pink").Preview.Activated:Fire()
	expect(
		h.Selected() == nil and #h.Calls == 0,
		"Hidden catalog buttons cannot reopen preview during a rule"
	)
	h.Controller.SetPhase("Results")
	h.Controller.Open()
	local stale = h.Row("Cyan").Preview
	stale.Activated:Fire()
	h.Controller.Destroy()
	stale.Activated:Fire()
	expect(h.Selected() == nil, "Disposed menu disconnects stale preview actions")
end

do
	local h = menuHarness()
	h.Player:SetAttribute("DataStatus", "Session")
	h.Player:SetAttribute("DataPersistent", false)
	h.Controller.Open()
	local cyan = h.Row("Cyan")
	cyan.Preview.Activated:Fire()
	cyan.Action.Activated:Fire()
	expect(
		h.Selected() == "Cyan" and #h.Calls == 0,
		"Visual preview is available without consenting to temporary purchases"
	)
	expect(
		cyan.Action.Text == "ВЫБЕРИ РЕЖИМ",
		"Preview does not hide the temporary-profile purchase gate"
	)
	h.Controller.Destroy()
end

do
	local h = menuHarness()
	h.Controller.Open()
	h.Panel.QuestsTab.Activated:Fire()
	for _, milestone in Economy.MasteryMilestones do
		local row = h.Row(milestone.Id)
		expect(row ~= nil, "Every permanent milestone has its own row")
		expect(string.find(row.Title.Text, milestone.Title, 1, true) ~= nil, "Fixed catalog title is visible")
		expect(
			string.find(row.Detail.Text, milestone.Description, 1, true) ~= nil,
			"Exact qualifying action is explained"
		)
		expect(row.Action.Text == "НЕ ОТКРЫТ", "Missing unlock never implies earned title")
		expect(row.Action.Size.Y.Offset == 44, "Title action retains a full touch target")
		expect(
			row.Action.Position.Y.Offset >= row.Detail.Position.Y.Offset + row.Detail.Size.Y.Offset,
			"Title action does not overlap wrapped instructions"
		)
		row.Action.Activated:Fire()
	end
	expect(#h.Calls == 0, "Locked title actions send no requests")
	local first = h.Row("FirstRun")
	h.Player:SetAttribute("Mastery_FirstRun", 1)
	expect(first.Action.Text == "НЕ ОТКРЫТ", "Progress alone cannot locally unlock a title")
	h.Player:SetAttribute("UnlockedTitle_FirstRun", true)
	expect(first.Action.Text == "НАДЕТЬ ТИТУЛ", "Server unlock enables explicit equip")
	first.Action.Activated:Fire()
	expect(
		h.Calls[1][1] == "EquipTitle" and h.Calls[1][2] == "FirstRun",
		"Equip sends allowlisted title intent"
	)
	expect(h.Player:GetAttribute("EquippedTitle") == nil, "Client does not optimistically award or equip")
	h.Player:SetAttribute("EquippedTitle", "FirstRun")
	expect(first.Action.Text == "СНЯТЬ ТИТУЛ", "Server equip exposes explicit removal action")
	h.Advance()
	first.Action.Activated:Fire()
	expect(h.Calls[2][1] == "EquipTitle" and h.Calls[2][2] == "None", "Removal uses server's None intent")
	expect(
		h.Player:GetAttribute("EquippedTitle") == "FirstRun",
		"Removal also waits for authoritative replication"
	)
	expect(h.Player:GetAttribute("Coins") == 500, "Titles do not introduce a purchase or currency mutation")
	expect(first.Action.NextSelectionDown == h.Row("PerfectRun").Action, "Gamepad traverses milestone rows")
	expect(
		h.Row("TeamVeteran").Action.NextSelectionDown == h.Row("survive").Action,
		"Gamepad can continue into daily quests"
	)
	h.Player:SetAttribute("Mastery_Collector", math.huge)
	expect(
		string.find(h.Row("Collector").Detail.Text, "0 / 3", 1, true) ~= nil,
		"Malformed progress does not show completion"
	)
	h.Player:SetAttribute("Quest_survive", 8)
	h.Controller.Open()
	expect(
		h.GuiService.SelectedObject == h.Row("survive").Action,
		"Claimable daily reward stays directly reachable past new mastery rows"
	)
	first = h.Row("FirstRun")
	h.Advance()
	h.Row("survive").Action.Activated:Fire()
	expect(
		h.Calls[3][1] == "ClaimQuest" and h.Calls[3][2] == "survive",
		"Daily quest remains a distinct server claim"
	)
	h.Player:SetAttribute("DataStatus", "Session")
	h.Player:SetAttribute("DataPersistent", false)
	expect(
		string.find(first.Detail.Text, "только до выхода", 1, true) ~= nil,
		"Session title progress is explicitly temporary"
	)
	expect(
		first.Action.Text == "ВЫБЕРИ РЕЖИМ",
		"Temporary consent gate also protects title actions"
	)
	h.Player:SetAttribute("TemporaryPlayAccepted", true)
	expect(
		first.Action.Text == "СНЯТЬ ТИТУЛ",
		"Consented temporary player can use their temporary title"
	)
	local count = #h.Calls
	local staleAction = first.Action
	h.Panel.CosmeticsTab.Activated:Fire()
	h.Advance()
	staleAction.Activated:Fire()
	expect(#h.Calls == count, "Changing tab disconnects stale title actions")
	h.Controller.Destroy()
end

do
	local h = menuHarness()
	h.Controller.Open()
	local aurora = h.Row("Aurora")
	expect(
		aurora.Action.Text == "ЦЕЛЬ МАСТЕРСТВА",
		"Mastery style has an explicit locked state"
	)
	expect(
		string.find(aurora.Detail.Text, "паркура", 1, true) ~= nil,
		"A locked row explains the gameplay goal"
	)
	aurora.Action.Activated:Fire()
	aurora.Preview.Activated:Fire()
	expect(#h.Calls == 0 and h.Selected() == "Aurora", "Locked styles can be previewed but not claimed")
	h.Player:SetAttribute("Mastery_Practice", 1)
	expect(aurora.Action.Text == "ЦЕЛЬ МАСТЕРСТВА", "Counter alone never authorizes a reward")
	h.Player:SetAttribute("UnlockedTitle_Practice", true)
	expect(aurora.Action.Text == "ЗАБРАТЬ", "Server unlock exposes a clearly free claim")
	expect(
		string.find(h.Panel.Items.CollectionGoal.Detail.Text, "Полярное сияние", 1, true) ~= nil,
		"The ready reward becomes the single visible collection goal"
	)
	aurora.Action.Activated:Fire()
	expect(
		#h.Calls == 1 and h.Calls[1][1] == "Purchase" and h.Calls[1][2] == "Aurora",
		"Free claim sends only the existing action and catalog id"
	)
	expect(
		h.Player:GetAttribute("Owned_Aurora") == nil and h.Player:GetAttribute("Coins") == 500,
		"Claim does not fabricate ownership or change the local balance"
	)
	h.Player:SetAttribute("Owned_Aurora", true)
	h.Player:SetAttribute("EquippedTrail", "Aurora")
	expect(aurora.Action.Text == "НАДЕТО ✓", "Confirmed ownership and equip update the state")
	h.Player:SetAttribute("EquippedTrail", "None")
	expect(aurora.Action.Text == "НАДЕТЬ", "An owned reward can be reequipped")
	h.Advance()
	aurora.Action.Activated:Fire()
	expect(h.Calls[2][1] == "Equip" and h.Calls[2][2] == "Aurora", "Reequip never requests another claim")
	h.Player:SetAttribute("DataStatus", "Session")
	h.Player:SetAttribute("DataPersistent", false)
	expect(
		string.find(h.Panel.Items.CollectionGoal.Detail.Text, "Временно", 1, true) ~= nil,
		"Temporary collection goal does not promise cross-session progress"
	)
	expect(aurora.Action.Text == "ВЫБЕРИ РЕЖИМ", "Temporary consent also gates free reward use")
	h.Controller.Destroy()
	expect(h.Panel.Items:FindFirstChild("CollectionGoal") == nil, "Destroy disposes the local goal row")
end
do
	scenarios += 1
	local container = Roblox.Instance.new("Frame")
	local row = Roblox.Instance.new("Frame")
	row.Parent = container
	for name, class in { Action = "TextButton", Preview = "TextButton", Detail = "TextLabel" } do
		local child = Roblox.Instance.new(class)
		child.Name, child.Parent = name, row
	end
	local controller = Preview.new()
	for _, item in Economy.Trails do
		if item.UnlockTitle then
			controller.Toggle(row, item)
			local sample = row.AppearancePreview.AppearanceSample
			expect(#sample:GetChildren() == 18, "Every style keeps the same bounded geometry budget")
			expect(
				sample.Ribbon_1.Color == item.Color and sample.Ribbon_12.Color ~= sample.Ribbon_1.Color,
				"Preview shows the actual style gradient"
			)
			expect(
				math.abs(sample.Ribbon_1.Size.Z - 0.715 * item.WidthScale / 0.65) < 0.00001,
				"Preview width uses the same style parameter as the character"
			)
			expect(
				math.abs(sample.Ribbon_12.Position.X - (0.1 - 4.8 * item.Lifetime / 0.28)) < 0.00001,
				"Preview length distinguishes short and long styles"
			)
		end
	end
	controller.Destroy()
	expect(
		row:FindFirstChild("AppearancePreview") == nil,
		"Style switching leaves no preview instances after destroy"
	)
	container:Destroy()
end
print("CollectionPreview integration: " .. checks .. " checks passed in " .. scenarios .. " scenarios")
