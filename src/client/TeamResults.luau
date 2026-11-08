--!strict
-- Optional, paginated team results inside the existing scroll area. No input or camera takeover.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local View = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("ContributionView"))
local TeamResults = {}
local PAGE_SIZE, ROW_HEIGHT = 12, 82

function TeamResults.new(panel: ScrollingFrame, state: Instance, player: Player, returnButton: GuiButton)
	local connections = {}
	local owned = Instance.new("Frame")
	owned.Name = "TeamResults"
	owned.BackgroundTransparency = 1
	owned.Visible = false
	owned.Parent = panel
	local function text(class: string, id: string, height: number)
		local object = Instance.new(class) :: any
		object.Name = id
		object.Size = UDim2.new(1, 0, 0, height)
		object.Position = UDim2.fromOffset(0, 0)
		object.BackgroundTransparency = if class == "TextButton" then 0 else 1
		object.BackgroundColor3 = Color3.fromRGB(39, 56, 78)
		object.TextColor3 = Color3.fromRGB(239, 246, 255)
		object.Font = Enum.Font.GothamMedium
		object.TextSize = 14
		object.TextWrapped = true
		object.RichText = false
		object.Parent = owned
		return object
	end
	local toggle = text("TextButton", "Toggle", 44) :: TextButton
	local previous = text("TextButton", "Previous", 44) :: TextButton
	local nextPage = text("TextButton", "Next", 44) :: TextButton
	local note = text("TextLabel", "Note", 38) :: TextLabel
	previous.Text, nextPage.Text = "← НАЗАД", "ДАЛЕЕ →"
	local labels = {}
	for index = 1, PAGE_SIZE do
		local label = text("TextLabel", "Player" .. index, ROW_HEIGHT - 4) :: TextLabel
		label.TextXAlignment = Enum.TextXAlignment.Left
		labels[index] = label
	end
	local entries = {}
	local page, baseHeight = 1, 0
	local expanded, destroyed, truncated = false, false, false
	local lastRound = -1
	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end
	local function reveal(control: GuiObject)
		-- Selecting a control also brings it into the existing results scroll viewport.
		local target = baseHeight + control.Position.Y.Offset
		panel.CanvasPosition = Vector2.new(0, math.max(0, target - 8))
	end
	local function layout()
		owned.Position = UDim2.fromOffset(14, baseHeight)
		owned.Size = UDim2.new(1, -32, 0, 44)
		owned.Visible = state:GetAttribute("Phase") == "Results" and #entries > 0
		local active = owned.Visible
		toggle.Text = if expanded
			then "СКРЫТЬ ВКЛАД КОМАНДЫ ▲"
			else "ВКЛАД КОМАНДЫ · " .. #entries .. " ▼"
		toggle.Selectable = active
		local pages = math.max(1, math.ceil(#entries / PAGE_SIZE))
		page = math.clamp(page, 1, pages)
		local shown = math.min(PAGE_SIZE, math.max(0, #entries - (page - 1) * PAGE_SIZE))
		note.Visible = active and expanded
		note.Position = UDim2.fromOffset(0, 48)
		note.Text = "ВКЛАД ЗА ЗАБЕГ · "
			.. page
			.. "/"
			.. pages
			.. (
				if truncated
					then " · СПИСОК НЕПОЛНЫЙ"
					else " · БЕЗ ДОПОЛНИТЕЛЬНЫХ НАГРАД"
			)
		for index, label in labels do
			local entry = entries[(page - 1) * PAGE_SIZE + index]
			label.Visible = active and expanded and entry ~= nil
			label.Selectable = label.Visible
			label.Position = UDim2.fromOffset(0, 90 + (index - 1) * ROW_HEIGHT)
			if entry then
				label.Text = (if entry.UserId == player.UserId then "ТЫ · " else "")
					.. entry.Name
					.. "\n"
					.. entry.Detail
					.. "\n"
					.. entry.Outcome
			end
			label.NextSelectionUp = if index == 1 then toggle else labels[index - 1]
			label.NextSelectionDown = if index < shown
				then labels[index + 1]
				elseif pages > 1 then previous
				else toggle
		end
		local footer = 90 + shown * ROW_HEIGHT
		for index, button in { previous, nextPage } do
			button.Visible = active and expanded and pages > 1
			button.Selectable = button.Visible
			button.Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 4, 0, footer)
			button.Size = UDim2.new(0.5, -4, 0, 44)
		end
		local extra = if not active
			then 0
			elseif not expanded then 52
			else footer + (if pages > 1 then 52 else 8)
		owned.Size = UDim2.new(1, -32, 0, extra)
		panel.CanvasSize = UDim2.fromOffset(0, baseHeight + extra)
		toggle.NextSelectionDown = if expanded and shown > 0 then labels[1] else returnButton
		toggle.NextSelectionUp = returnButton
		previous.NextSelectionUp, nextPage.NextSelectionUp = toggle, toggle
		previous.NextSelectionRight, nextPage.NextSelectionLeft = nextPage, previous
		previous.NextSelectionDown, nextPage.NextSelectionDown = returnButton, returnButton
	end
	local function refresh()
		if destroyed then
			return
		end
		local round = state:GetAttribute("Round")
		if round ~= lastRound or state:GetAttribute("Phase") ~= "Results" then
			expanded, page = false, 1
			lastRound = round
		end
		local raw = state:GetAttribute("ContributionsJson")
		local payload = nil
		if type(raw) == "string" and #raw > 0 and #raw <= 32000 then
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok then
				payload = decoded
			end
		end
		entries = View.read(payload, round, state:GetAttribute("ContributionsRound")) or {}
		truncated = type(payload) == "table" and payload.Truncated == true
		layout()
		if
			not owned.Visible
			and GuiService.SelectedObject
			and GuiService.SelectedObject:IsDescendantOf(owned)
		then
			GuiService.SelectedObject = if returnButton.Visible then returnButton else nil
		end
	end
	connect(toggle.Activated, function()
		if destroyed or not owned.Visible then
			return
		end
		expanded = not expanded
		layout()
		reveal(toggle)
	end)
	for index, button in { previous, nextPage } do
		connect(button.Activated, function()
			if destroyed or not button.Visible then
				return
			end
			local pages = math.max(1, math.ceil(#entries / PAGE_SIZE))
			page = (page - 1 + (if index == 1 then -1 else 1)) % pages + 1
			layout()
			GuiService.SelectedObject = toggle
			reveal(toggle)
		end)
	end
	for _, button in { toggle, previous, nextPage } do
		connect(button.SelectionGained, function()
			reveal(button)
		end)
	end
	for _, label in labels do
		connect(label.SelectionGained, function()
			reveal(label)
		end)
	end
	connect(state.AttributeChanged, function(key)
		if key == "Phase" or key == "Round" or key == "ContributionsJson" or key == "ContributionsRound" then
			refresh()
		end
	end)
	refresh()
	return {
		Layout = function(height: number)
			if destroyed then
				return
			end
			baseHeight = height
			layout()
		end,
		FocusButton = function(): GuiButton?
			return if owned.Visible then toggle else nil
		end,
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(owned) then
				GuiService.SelectedObject = nil
			end
			owned:Destroy()
		end,
	}
end
return TeamResults
