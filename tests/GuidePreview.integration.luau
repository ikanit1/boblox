--!strict
-- Production archive diagrams and Station prompt wiring, with local GUI/service adapters.
-- Layout arithmetic is not native rendering, input, readability or learning acceptance.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local Presentation = require("../src/shared/GuidePresentation")
local checks = 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
local function harness()
	local h: any = { Created = 0, Connections = {} }
	local function signal()
		local listeners = {}
		local value = {}
		function value:Connect(callback)
			local entry = { Active = true, Callback = callback }
			function entry.Disconnect(handle)
				handle.Active = false
			end
			table.insert(listeners, entry)
			table.insert(h.Connections, entry)
			return entry
		end
		function value:Fire(...)
			for _, entry in table.clone(listeners) do
				if entry.Active then
					entry.Callback(...)
				end
			end
		end
		function value:Count()
			local n = 0
			for _, entry in listeners do
				if entry.Active then
					n += 1
				end
			end
			return n
		end
		return value
	end
	local methods = {}
	local function node(class, name, parent)
		h.Created += 1
		local object = setmetatable({
			Properties = {
				Name = name,
				ClassName = class,
				Visible = true,
				Size = Roblox.UDim2.fromOffset(144, 44),
				Position = Roblox.UDim2.new(),
				AnchorPoint = Roblox.Vector2.zero,
				Text = "",
				Activated = signal(),
			},
			Children = {},
			Changed = {},
			Attributes = {},
			AttributeSignals = {},
		}, {
			__index = function(self, key)
				return methods[key] or self.Children[key] or self.Properties[key]
			end,
			__newindex = function(self, key, value)
				local old = self.Properties[key]
				if key == "Parent" then
					if old then
						old.Children[self.Name] = nil
					end
					if value then
						value.Children[self.Name] = self
					end
				end
				self.Properties[key] = value
				if old ~= value and self.Changed[key] then
					self.Changed[key]:Fire()
				end
			end,
		})
		object.Parent = parent
		return object
	end
	function methods:WaitForChild(name)
		return assert(self.Children[name], "Missing fixture " .. name)
	end
	function methods:IsDescendantOf(parent)
		local cursor = self.Parent
		while cursor do
			if cursor == parent then
				return true
			end
			cursor = cursor.Parent
		end
		return false
	end
	function methods:GetPropertyChangedSignal(key)
		self.Changed[key] = self.Changed[key] or signal()
		return self.Changed[key]
	end
	function methods:GetAttribute(key)
		return self.Attributes[key]
	end
	function methods:GetAttributeChangedSignal(key)
		self.AttributeSignals[key] = self.AttributeSignals[key] or signal()
		return self.AttributeSignals[key]
	end
	function methods:SetAttribute(key, value)
		if self.Attributes[key] ~= value then
			self.Attributes[key] = value
			self:GetAttributeChangedSignal(key):Fire()
		end
	end
	function methods:Destroy()
		for _, child in table.clone(self.Children) do
			child:Destroy()
		end
		self.Parent = nil
	end
	h.Node, h.Signal = node, signal
	h.Guide = node("Frame", "Guide", nil)
	node("TextLabel", "Heading", h.Guide)
	node("TextLabel", "Body", h.Guide)
	node("TextButton", "Close", h.Guide)
	h.Guide.Visible = false
	h.Motion = node("ScreenGui", "RuleRoomHUD", nil)
	h.Heartbeat = signal()
	local shared = {
		WaitForChild = function(_, name)
			return name
		end,
	}
	local production = luau.load(fs.readFile("src/client/GuidePreview.luau"), {
		environment = {
			game = {
				GetService = function(_, name)
					if name == "RunService" then
						return { Heartbeat = h.Heartbeat }
					end
					assert(
						name == "ReplicatedStorage",
						"Preview must not access gameplay/input/camera services"
					)
					return {
						WaitForChild = function()
							return shared
						end,
					}
				end,
			},
			require = function(name)
				assert(name == "GuidePresentation", "Only pure presentation is required")
				return Presentation
			end,
			Instance = {
				new = function(class)
					return node(class, class, nil)
				end,
			},
			Color3 = Roblox.Color3,
			UDim2 = Roblox.UDim2,
			Vector2 = Roblox.Vector2,
			Enum = Roblox.Enum,
		},
	})()
	h.Controller = production.new(h.Guide, h.Motion)
	function h.Open(id)
		h.Guide.Visible = true
		return h.Controller.Show(id)
	end
	return h
end

expect(#Presentation.RuleIds == 12, "All twelve production rule lessons are present")
for _, id in Presentation.RuleIds do
	for _, seconds in { 0, 4, 8, 10 } do
		local data = assert(Presentation.snapshot(id, seconds, false), id)
		expect(
			#data.Shapes <= Presentation.MaxShapes and #data.Shapes >= 3,
			"Every lesson has a bounded actual diagram"
		)
		expect(#data.Command > 0 and #data.Tip > 0, "Each stage explains an action and one advice")
		for _, shape in data.Shapes do
			expect(
				shape.X >= 0
					and shape.Y >= 0
					and shape.Width > 0
					and shape.Height > 0
					and shape.X + shape.Width <= 1.001
					and shape.Y + shape.Height <= 1.001,
				"Diagram geometry stays inside its local canvas: " .. id
			)
		end
	end
	for step = 1, 3 do
		local a = Presentation.snapshot(id, 0, true, step)
		local b = Presentation.snapshot(id, 100, true, step)
		expect(a.Stage == step and b.Stage == step, "Reduced motion advances only by explicit step")
		for index, shape in a.Shapes do
			local other = b.Shapes[index]
			expect(
				shape.X == other.X and shape.Y == other.Y and shape.Angle == other.Angle,
				"Reduced-motion geometry never animates with elapsed time"
			)
		end
	end
end
expect(Presentation.snapshot("Unknown", 0, false) == nil, "Unknown rules cannot manufacture a demonstration")
expect(Presentation.snapshot("ReactorRush", 5.9, false).Stage == 1, "Reactor first demonstrates gathering")
expect(
	Presentation.snapshot("ReactorRush", 6, false).Stage == 2,
	"Reactor visibly enters its four-second stabilization"
)
expect(Presentation.snapshot("ReactorRush", 9.99, false).Stage == 2, "A full reactor still needs survival")
expect(
	Presentation.snapshot("ReactorRush", 10, false).Stage == 3,
	"Reactor completion is shown only after stabilization"
)

do
	local h = harness()
	local created = h.Created
	for _, id in Presentation.RuleIds do
		expect(h.Open(id), "Production UI accepts supported rule: " .. id)
		expect(h.Heartbeat:Count() == 1, "At most one animation callback exists while showing a lesson")
		h.Heartbeat:Fire(10)
		expect(h.Heartbeat:Count() == 0, "Demonstration finishes after ten seconds without looping")
		expect(
			string.find(h.Guide.GuideDemonstration.Step.Text, "3/3", 1, true) ~= nil,
			"Final stage remains readable"
		)
		h.Guide.ReplayGuide.Activated:Fire()
		expect(h.Heartbeat:Count() == 1, "Explicit replay restarts the same bounded diagram")
	end
	expect(h.Created == created, "Rule changes and replays never allocate new diagram nodes")
	expect(
		h.Guide.Close.Size.Y.Offset == 44 and h.Guide.ReplayGuide.Size.Y.Offset == 44,
		"Both actions keep 44px targets"
	)
	h.Motion:SetAttribute("ReducedMotion", true)
	expect(h.Heartbeat:Count() == 0, "Reduced motion immediately disconnects animation")
	h.Guide.ReplayGuide.Activated:Fire()
	expect(
		string.find(h.Guide.GuideDemonstration.Step.Text, "2/3", 1, true) ~= nil,
		"Static scheme has explicit next-step control"
	)
	h.Guide.ReplayGuide.Activated:Fire()
	expect(
		string.find(h.Guide.GuideDemonstration.Step.Text, "3/3", 1, true) ~= nil,
		"Static scheme explains the completion step"
	)
	h.Controller.Hide()
	expect(
		h.Heartbeat:Count() == 0 and h.Guide.Body.Visible and not h.Guide.ReplayGuide.Visible,
		"Hiding restores authored text and stops all work"
	)
	h.Open("LaserSweep")
	h.Motion:SetAttribute("ReducedMotion", false)
	h.Guide.Visible = false
	expect(
		h.Heartbeat:Count() == 0 and not h.Guide.GuideDemonstration.Visible,
		"Panel hide cancels playback synchronously"
	)
	h.Open("SafeZone")
	h.Controller.Destroy()
	h.Controller.Destroy()
	expect(h.Guide.GuideDemonstration == nil and h.Guide.ReplayGuide == nil, "Destroy removes only owned GUI")
	expect(not h.Controller.Show("SafeZone"), "Destroyed preview cannot restart")
	for _, connection in h.Connections do
		expect(not connection.Active, "Destroy disconnects all preview observers")
	end
end

do
	local h = harness()
	local player = h.Node("Player", "Player", nil)
	player.CharacterRemoving = h.Signal()
	local arena = h.Node("Model", "Arena", nil)
	local terminal = h.Node("Part", "Terminal", arena)
	terminal:SetAttribute("StationAction", "Guide:PressureWave")
	local prompt = { Parent = terminal }
	local triggered = h.Signal()
	local bindings, connections = {}, {}
	local source = fs.readFile("src/client/Station.client.luau")
	local closeStart = assert(string.find(source, "local function closeGuide()", 1, true))
	local closeEnd = assert(string.find(source, "local function send(", closeStart, true))
	local openStart = assert(
		string.find(
			source,
			"table.insert(\n\tconnections,\n\tProximityPromptService.PromptTriggered",
			1,
			true
		)
	)
	local openEnd = assert(string.find(source, "-- Reuse authored world labels", openStart, true))
	local rules, names = {}, {}
	for _, id in Presentation.RuleIds do
		rules[id] = { Name = id }
		names[id] = "Full authored guide"
	end
	local gui = {
		SelectedObject = nil,
		IsTenFootInterface = function()
			return false
		end,
	}
	local controller = luau.load(
		string.sub(source, closeStart, closeEnd - 1)
			.. string.sub(source, openStart, openEnd - 1)
			.. "\nreturn closeGuide",
		{
			environment = {
				guide = h.Guide,
				guidePreview = h.Controller,
				player = player,
				welcome = { Visible = false },
				collectionPanel = { Visible = false },
				guides = names,
				config = { Rules = rules },
				GuiService = gui,
				Workspace = {
					WaitForChild = function()
						return arena
					end,
				},
				game = {
					GetService = function(_, name)
						assert(name == "UserInputService", "Station prompt uses only existing input hint")
						return {
							GetLastInputType = function()
								return { Name = "Gamepad1" }
							end,
						}
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
				Enum = Roblox.Enum,
				ProximityPromptService = { PromptTriggered = triggered },
				connections = connections,
				previousSelection = nil,
				focusEpoch = 0,
				restoreFocusAfterLayout = function() end,
			},
			injectGlobals = true,
		}
	)()
	triggered:Fire(prompt, player)
	expect(h.Guide.Visible and h.Heartbeat:Count() == 1, "Actual Station prompt opens its production diagram")
	expect(
		h.Guide.Heading.Text == "PressureWave" and gui.SelectedObject == h.Guide.Close,
		"Station retains title and gamepad close focus"
	)
	bindings.CloseStationGuide(nil, Roblox.Enum.UserInputState.Begin)
	expect(
		not h.Guide.Visible and h.Heartbeat:Count() == 0 and next(bindings) == nil,
		"Station dismissal cancels preview and binding"
	)
	triggered:Fire(prompt, player)
	player.CharacterRemoving:Fire()
	expect(
		not h.Guide.Visible and h.Heartbeat:Count() == 0,
		"Character removal closes the production archive path"
	)
	player:SetAttribute("InRound", true)
	triggered:Fire(prompt, player)
	expect(not h.Guide.Visible, "Admitted participants cannot open the archive")
	player:SetAttribute("InRound", false)
	terminal:SetAttribute("StationAction", "Guide:Unknown")
	triggered:Fire(prompt, player)
	expect(not h.Guide.Visible, "Unknown station lesson is ignored")
	controller()
	h.Controller.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
end

for _, reduced in { false, true } do
	for stage, seconds in { 0, 3, 8 } do
		local snapshot = assert(Presentation.snapshot("ChangingWalls", seconds, reduced, stage))
		local gapArrow = ""
		for _, shape in snapshot.Shapes do
			if shape.Tone == "Safe" then
				gapArrow = shape.Text
			end
		end
		expect(
			gapArrow == (if stage == 3 then "↑" else "↓"),
			"Both animated and reduced-motion wall lessons show the approaching wall direction"
		)
	end
end

for _, viewport in { { 320, 568 }, { 390, 844 }, { 568, 300 }, { 667, 375 }, { 844, 390 } } do
	local w, h = Presentation.bounds(viewport[1], viewport[2], true)
	if viewport[1] > viewport[2] then
		expect(
			(viewport[1] - w) / 2 >= 168,
			"Landscape archive keeps standard touch-control side columns clear"
		)
	else
		expect(h + 8 <= viewport[2] - 168, "Portrait archive leaves bottom touch controls clear")
	end
end
print(
	string.format(
		"GuidePreview: %d checks passed (production module and Station wiring; synthetic GUI)",
		checks
	)
)
