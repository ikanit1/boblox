--!strict
-- Production UI with local adapters; not native rendering/controller acceptance.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local Roblox = require("@lune/roblox")
local View = require("../src/shared/ContributionView")
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

local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local root = node("Frame", "Root")
local panel = node("ScrollingFrame", "ResultsPanel", root)
local returnButton = node("TextButton", "Collection", root)
local state = node("Folder", "State")
state.AttributeChanged = signal()
state:SetAttribute("Phase", "Results")
state:SetAttribute("Round", 2)
state:SetAttribute("ContributionsRound", 0)
local player = { UserId = 1 }
local gui = { SelectedObject = nil }
local shared = {
	WaitForChild = function()
		return "ContributionView"
	end,
}
local services = {
	HttpService = {
		JSONDecode = function(_, raw)
			return serde.decode("json", raw)
		end,
	},
	ReplicatedStorage = {
		WaitForChild = function()
			return shared
		end,
	},
	GuiService = gui,
}
local Controller = luau.load(fs.readFile("src/client/TeamResults.luau"), {
	environment = {
		game = {
			GetService = function(_, id)
				return assert(services[id], "Unexpected fixture service: " .. id)
			end,
		},
		Instance = {
			new = function(class)
				return node(class, class)
			end,
		},
		Enum = Roblox.Enum,
		Color3 = Roblox.Color3,
		UDim2 = Roblox.UDim2,
		Vector2 = Roblox.Vector2,
		require = function()
			return View
		end,
	},
	injectGlobals = true,
})()
local controller = Controller.new(panel, state, player, returnButton)
controller.Layout(350)
local owned = panel.TeamResults
expect(
	not owned.Visible and panel.CanvasSize.Y.Offset == 350,
	"Missing snapshot adds no empty screen or scroll space"
)
local data = { Version = 1, Round = 2, Players = {}, Truncated = false }
for index = 1, 72 do
	table.insert(data.Players, {
		UserId = index,
		Name = "Участник " .. index,
		Score = index,
		Survived = index % 7,
		Energy = index % 4,
		Outcome = if index == 2 then "Left" else "Won",
		Left = index == 2,
	})
end
state:SetAttribute("ContributionsJson", serde.encode("json", data))
expect(not owned.Visible, "JSON arriving before the publication barrier remains hidden")
state:SetAttribute("ContributionsRound", 2)
expect(
	owned.Visible and panel.CanvasSize.Y.Offset == 402,
	"Valid snapshot adds only a collapsed 44px control"
)
expect(
	owned.Toggle.Size.Y.Offset == 44 and controller.FocusButton() == owned.Toggle,
	"Touch target and gamepad entry remain explicit"
)
owned.Toggle.Activated:Fire()
expect(
	owned.Player1.Visible and owned.Player12.Visible and owned.Next.Visible,
	"At most twelve entries are shown on the first page"
)
expect(string.find(owned.Player1.Text, "ТЫ", 1, true) ~= nil, "Personal row is marked")
expect(string.find(owned.Player2.Text, "ВЫШЕЛ", 1, true) ~= nil, "Departed players remain visible")
expect(not owned.Player1.RichText, "Player names cannot inject rich text")
expect(
	owned.Toggle.NextSelectionDown == owned.Player1 and owned.Player12.NextSelectionDown == owned.Previous,
	"Controller focus visits every row before page actions"
)
owned.Player12.SelectionGained:Fire()
expect(panel.CanvasPosition.Y > 350, "Controller selection scrolls the selected contribution into view")
owned.Next.Activated:Fire()
expect(
	string.find(owned.Player1.Text, "Участник 13", 1, true) ~= nil
		and gui.SelectedObject == owned.Toggle,
	"Next page updates entries and returns focus to its heading"
)
owned.Previous.Activated:Fire()
expect(
	string.find(owned.Player1.Text, "Участник 1", 1, true) ~= nil,
	"Previous page restores the first cohort"
)
owned.Previous.Activated:Fire()
expect(
	string.find(owned.Player1.Text, "Участник 61", 1, true) ~= nil,
	"Pagination wraps within the fixed six-page bound"
)
controller.Layout(410)
expect(
	owned.Position.Y.Offset == 410 and panel.CanvasSize.Y.Offset > 410,
	"Responsive layout preserves expansion below personal results"
)
gui.SelectedObject = owned.Player1
state:SetAttribute("ContributionsJson", "malformed JSON")
expect(
	not owned.Visible and gui.SelectedObject == returnButton,
	"Malformed payload hides optional content and releases selection"
)
state:SetAttribute("ContributionsRound", 3)
state:SetAttribute("ContributionsJson", serde.encode("json", data))
expect(not owned.Visible, "New barrier cannot expose an old snapshot")
state:SetAttribute("ContributionsRound", 2)
state:SetAttribute("Phase", "Rule")
expect(not owned.Visible and controller.FocusButton() == nil, "Team UI cannot occupy gameplay")
state:SetAttribute("Phase", "Results")
expect(not owned.Player1.Visible, "Returning to results starts collapsed")
owned.Toggle.Activated:Fire()
data.Truncated = true
state:SetAttribute("ContributionsJson", serde.encode("json", data))
expect(string.find(owned.Note.Text, "НЕПОЛНЫЙ", 1, true) ~= nil, "Any truncation is explicit")
gui.SelectedObject = owned.Toggle
local oldToggle = owned.Toggle
controller.Destroy()
expect(
	panel:FindFirstChild("TeamResults") == nil and gui.SelectedObject == nil,
	"Destroy removes owned UI and releases focus"
)
state:SetAttribute("Phase", "Waiting")
oldToggle.Activated:Fire()
expect(panel:FindFirstChild("TeamResults") == nil, "Disconnected controls and state cannot recreate UI")
controller.Destroy()
print(string.format("TeamResults: %d checks passed (local UI adapters)", checks))
