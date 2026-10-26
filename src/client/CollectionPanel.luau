--!strict
-- The catalog is authored as an inspectable template; only repeated rows are cloned.
-- Requests contain an allowlisted item id. Balances, ownership and rewards stay on the server.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local CollectionPanel = {}

function CollectionPanel.new(root: Frame, player: Player, remote: RemoteEvent, economy: any)
	local panel = root:WaitForChild("CollectionPanel") :: Frame
	local backdrop = root:WaitForChild("CollectionBackdrop") :: Frame
	local openButton = root.Actions.Collection :: TextButton
	local closeButton = panel.Close :: TextButton
	local cosmeticsTab = panel.CosmeticsTab :: TextButton
	local questsTab = panel.QuestsTab :: TextButton
	local scroll = panel.Items :: ScrollingFrame
	local template = panel.RowTemplate :: Frame
	local message = panel.Message :: TextLabel
	local connections: { RBXScriptConnection } = {}
	local rowConnections: { RBXScriptConnection } = {}
	local rows: { any } = {}
	local currentTab = "Cosmetics"
	local phase = "Waiting"
	local cyan = Color3.fromRGB(70, 168, 244)
	local dark = Color3.fromRGB(24, 36, 57)
	local muted = Color3.fromRGB(179, 197, 219)
	local lastAction = 0
	local previousSelection: GuiObject? = nil
	local closeAction = "RuleRoomCloseCollection"
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	local function numberAttribute(name: string): number
		local value = player:GetAttribute(name)
		return if typeof(value) == "number" then value else 0
	end
	local function rewardReady(): boolean
		for id, quest in economy.Quests do
			if
				numberAttribute("Quest_" .. id) >= quest.Target
				and player:GetAttribute("Claimed_" .. id) ~= true
			then
				return true
			end
		end
		return false
	end

	local function refresh()
		local ready = rewardReady()
		openButton.Text = if ready then "ЦЕЛИ: НАГРАДА!" else "КОСМЕТИКА / ЦЕЛИ"
		questsTab.Text = if ready then "ЗАДАНИЯ · НАГРАДА" else "ЗАДАНИЯ"
		local coins = numberAttribute("Coins")
		local loading = player:GetAttribute("DataStatus") == "Loading"
		for _, entry in rows do
			local row = entry.Frame
			local action = row.Action :: TextButton
			if currentTab == "Cosmetics" then
				local owned = player:GetAttribute("Owned_" .. entry.Id) == true or entry.Id == "None"
				local equipped = player:GetAttribute("EquippedTrail") == entry.Id
				row.Detail.Text = if entry.Id == "None"
					then "Обычный облик"
					elseif
						owned
					then "В твоей коллекции • только внешний вид"
					else tostring(entry.Data.Price) .. " монет • только внешний вид"
				entry.Action = if owned then "Equip" else "Purchase"
				entry.Enabled = not loading and not equipped and (owned or coins >= entry.Data.Price)
				action.Text = if loading
					then "ЗАГРУЗКА"
					elseif equipped then "НАДЕТО ✓"
					elseif owned then "НАДЕТЬ"
					elseif coins >= entry.Data.Price then "КУПИТЬ"
					else string.format("ЕЩЁ %d", entry.Data.Price - coins)
			else
				local progress = numberAttribute("Quest_" .. entry.Id)
				local claimed = player:GetAttribute("Claimed_" .. entry.Id) == true
				row.Detail.Text = string.format(
					"%d / %d  •  награда %d монет",
					math.min(progress, entry.Data.Target),
					entry.Data.Target,
					entry.Data.Reward
				)
				entry.Action = "ClaimQuest"
				entry.Enabled = not loading and not claimed and progress >= entry.Data.Target
				action.Text = if claimed
					then "ПОЛУЧЕНО ✓"
					elseif entry.Enabled then "ЗАБРАТЬ"
					else "В ПРОЦЕССЕ"
			end
			action.BackgroundColor3 = if entry.Enabled then cyan else Color3.fromRGB(45, 60, 78)
			action.TextColor3 = if entry.Enabled then Color3.fromRGB(18, 30, 50) else muted
			action.AutoButtonColor = entry.Enabled
		end
		local status = player:GetAttribute("DataStatus")
		local text = player:GetAttribute("ActionMessage")
		local defaultText = if currentTab == "Quests"
			then "Задания на сегодня. Пропуск дня не отнимает награды."
			else "Следы меняют только внешний вид. Монеты зарабатываются в испытаниях."
		message.Text = if typeof(text) == "string" and text ~= "" then text else defaultText
		if status == "Session" then
			message.Text ..= "  •  Тест Studio: без сохранения."
		elseif status == "Unavailable" or status == "Busy" then
			message.Text ..= "  •  Сейчас прогресс не сохраняется."
		elseif status == "Loading" then
			message.Text = "Загружаем коллекцию…"
		end
	end

	local function selectTab(tab: string)
		currentTab = tab
		for _, connection in rowConnections do
			connection:Disconnect()
		end
		table.clear(rowConnections)
		for _, entry in rows do
			entry.Frame:Destroy()
		end
		table.clear(rows)
		cosmeticsTab.BackgroundColor3 = if tab == "Cosmetics" then Color3.fromRGB(39, 71, 96) else dark
		questsTab.BackgroundColor3 = if tab == "Quests" then Color3.fromRGB(39, 71, 96) else dark
		local catalog = {}
		if tab == "Cosmetics" then
			for _, trail in economy.Trails do
				table.insert(catalog, { Id = trail.Id, Data = trail })
			end
		else
			for _, id in { "survive", "stars", "runs" } do
				table.insert(catalog, { Id = id, Data = economy.Quests[id] })
			end
		end
		for index, item in catalog do
			local row = template:Clone()
			row.Name = "Item_" .. item.Id
			row.LayoutOrder = index
			row.Title.Text = item.Data.Name
			row.Swatch.BackgroundColor3 = item.Data.Color or Color3.fromRGB(66, 220, 169)
			row.Visible = true
			row.Parent = scroll
			local entry = { Id = item.Id, Data = item.Data, Frame = row, Enabled = false, Action = "" }
			table.insert(rows, entry)
			table.insert(
				rowConnections,
				row.Action.Activated:Connect(function()
					if entry.Enabled and panel.Visible and os.clock() - lastAction >= 0.35 then
						lastAction = os.clock()
						remote:FireServer(entry.Action, entry.Id)
					end
				end)
			)
			table.insert(
				rowConnections,
				row.Action.SelectionGained:Connect(function()
					local top = row.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
					local bottom = top + row.AbsoluteSize.Y
					local y = scroll.CanvasPosition.Y
					if top < y then
						y = top
					elseif bottom > y + scroll.AbsoluteSize.Y then
						y = bottom - scroll.AbsoluteSize.Y
					end
					scroll.CanvasPosition = Vector2.new(
						0,
						math.clamp(y, 0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y))
					)
				end)
			)
		end
		for index, entry in rows do
			local action = entry.Frame.Action :: TextButton
			action.NextSelectionUp = if index == 1 then cosmeticsTab else rows[index - 1].Frame.Action
			action.NextSelectionDown = if index == #rows then closeButton else rows[index + 1].Frame.Action
			action.NextSelectionLeft = cosmeticsTab
			action.NextSelectionRight = questsTab
		end
		if #rows > 0 then
			cosmeticsTab.NextSelectionDown = rows[1].Frame.Action
			questsTab.NextSelectionDown = rows[1].Frame.Action
		end
		cosmeticsTab.NextSelectionRight = questsTab
		cosmeticsTab.NextSelectionLeft = questsTab
		questsTab.NextSelectionLeft = cosmeticsTab
		questsTab.NextSelectionRight = cosmeticsTab
		cosmeticsTab.NextSelectionUp = closeButton
		questsTab.NextSelectionUp = closeButton
		closeButton.NextSelectionDown = cosmeticsTab
		closeButton.NextSelectionLeft = cosmeticsTab
		closeButton.NextSelectionRight = questsTab
		closeButton.NextSelectionUp = if #rows > 0 then rows[#rows].Frame.Action else cosmeticsTab
		scroll.CanvasPosition = Vector2.zero
		refresh()
	end

	local function canRestore(object: GuiObject?): boolean
		if not object or not object:IsDescendantOf(root) or not object.Selectable then
			return false
		end
		local ancestor: Instance? = object
		while ancestor and ancestor ~= root do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				return false
			end
			ancestor = ancestor.Parent
		end
		return true
	end

	local function focusPanel()
		if not GuiService.MenuIsOpen and string.find(UserInputService:GetLastInputType().Name, "Gamepad") then
			local selected = GuiService.SelectedObject
			if not selected or not selected:IsDescendantOf(panel) then
				GuiService.SelectedObject = if currentTab == "Quests" then questsTab else cosmeticsTab
			end
		end
	end

	local setVisible: (boolean) -> ()
	setVisible = function(visible: boolean)
		if visible and not panel.Visible then
			previousSelection = GuiService.SelectedObject
		end
		panel.Visible = visible and phase ~= "Rule"
		backdrop.Visible = panel.Visible
		if panel.Visible then
			refresh()
			focusPanel()
			ContextActionService:BindAction(closeAction, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					setVisible(false)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
		else
			ContextActionService:UnbindAction(closeAction)
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
				GuiService.SelectedObject = if canRestore(previousSelection)
					then previousSelection
					elseif canRestore(openButton) then openButton
					else nil
			end
			previousSelection = nil
		end
	end

	connect(openButton.Activated, function()
		if not panel.Visible and rewardReady() then
			selectTab("Quests")
		end
		setVisible(not panel.Visible)
	end)
	connect(closeButton.Activated, function()
		setVisible(false)
	end)
	connect(cosmeticsTab.Activated, function()
		selectTab("Cosmetics")
	end)
	connect(questsTab.Activated, function()
		selectTab("Quests")
	end)
	connect(player.AttributeChanged, refresh)
	connect(UserInputService.LastInputTypeChanged, function()
		if panel.Visible then
			focusPanel()
		end
	end)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), function()
		panel.Size = UDim2.new(1, -24, 0, math.min(420, math.max(230, root.AbsoluteSize.Y - 20)))
	end)
	panel.Size = UDim2.new(1, -24, 0, math.min(420, math.max(230, root.AbsoluteSize.Y - 20)))
	selectTab("Cosmetics")

	return {
		Open = function()
			if rewardReady() then
				selectTab("Quests")
			end
			setVisible(true)
		end,
		SetPhase = function(newPhase: string)
			phase = newPhase
			openButton.Visible = phase ~= "Rule"
			if phase == "Rule" then
				setVisible(false)
			end
		end,
		IsOpen = function(): boolean
			return panel.Visible
		end,
		Destroy = function()
			setVisible(false)
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, connection in rowConnections do
				connection:Disconnect()
			end
		end,
	}
end

return CollectionPanel
