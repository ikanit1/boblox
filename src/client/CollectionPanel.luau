--!strict
-- The catalog is authored as an inspectable template; only repeated rows are cloned.
-- Requests contain an allowlisted item id. Balances, ownership and rewards stay on the server.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileStatus = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("ProfileStatus"))
local PlayerHints = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("PlayerHints"))
local GameConfig = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local CollectionPreview = require(script.Parent:WaitForChild("CollectionPreview"))

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
	local mastery: Frame? = nil
	local collectionGoal: Frame? = nil
	local preview = CollectionPreview.new()
	local destroyed = false
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
		return if typeof(value) == "number"
				and value == value
				and value >= 0
				and value <= 1_000_000_000
			then math.floor(value)
			else 0
	end
	local function read(name: string): unknown
		return player:GetAttribute(name)
	end
	local function milestoneFor(id: string): any
		for _, milestone in economy.MasteryMilestones do
			if milestone.Id == id then
				return milestone
			end
		end
		return nil
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

	local function masteryText(): string
		local rulesMastered, clears = PlayerHints.flawlessCount(function(name)
			return player:GetAttribute(name)
		end, GameConfig.RuleOrder)
		-- Persistent BestPracticeSeconds may be nil; the session best is the honest fallback.
		local practice = player:GetAttribute("BestPracticeSeconds")
		if typeof(practice) ~= "number" then
			practice = player:GetAttribute("PracticeBestSeconds")
		end
		return PlayerHints.masterySummary(
			player:GetAttribute("BestRunScore"),
			player:GetAttribute("BestRunSurvived"),
			practice,
			rulesMastered,
			clears,
			#GameConfig.RuleOrder,
			GameConfig.RuleCount
		)
	end

	local function refresh()
		local ready = rewardReady()
		if mastery then
			(mastery:FindFirstChild("Detail") :: TextLabel).Text = masteryText()
		end
		openButton.Text = if ready then "ЦЕЛИ: НАГРАДА!" else "КОСМЕТИКА / ЦЕЛИ"
		questsTab.Text = if ready then "ЗАДАНИЯ · НАГРАДА" else "ЗАДАНИЯ"
		local coins = numberAttribute("Coins")
		local saveView =
			ProfileStatus.describe(player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent"))
		local loading = saveView.Loading
		local needsConsent = saveView.Temporary and player:GetAttribute("TemporaryPlayAccepted") ~= true
		if collectionGoal then
			local owned, total = 0, 0
			for _, trail in economy.Trails do
				if trail.Id ~= "None" then
					total += 1
					if player:GetAttribute("Owned_" .. trail.Id) == true then
						owned += 1
					end
				end
			end
			collectionGoal.Title.Text = string.format("ТВОЯ КОЛЛЕКЦИЯ · %d / %d", owned, total)
			collectionGoal.Detail.Text = if loading
				then "Загружаем твои следы. Любой облик можно примерить бесплатно."
				else (if saveView.Temporary then "Временно · " else "") .. (economy.nextTrailGoal(
					read
				) or "Все следы открыты. Меняй облик и улучшай свои рекорды.")
		end
		for _, entry in rows do
			local row = entry.Frame
			local action = row.Action :: TextButton
			if currentTab == "Cosmetics" then
				local state = economy.trailState(entry.Data, read)
				local kind = state.Kind
				local milestone = if entry.Data.UnlockTitle then milestoneFor(entry.Data.UnlockTitle) else nil
				if kind == "Locked" and milestone then
					row.Detail.Text = "Бесплатно: "
						.. milestone.Goal
						.. string.format(
							" (%d/%d).",
							PlayerHints.masteryProgress(read("Mastery_" .. milestone.Id), milestone.Target),
							milestone.Target
						)
				elseif kind == "Available" then
					row.Detail.Text = "Мастерство подтверждено · забери бесплатно.\n"
						.. entry.Data.Style
				elseif kind == "Owned" or kind == "Equipped" then
					row.Detail.Text = if entry.Id == "None"
						then "Обычный облик · без эффектов"
						else "В коллекции · только внешний вид.\n"
							.. (entry.Data.Style or "Короткий одноцветный след")
				else
					row.Detail.Text = string.format(
						"Цена %d · у тебя %d монет.\nТолько внешний вид, без преимуществ.",
						entry.Data.Price,
						coins
					)
				end
				entry.Action = state.Action or ""
				entry.Enabled = not loading and state.Action ~= nil
				action.Text = if loading
					then "ЗАГРУЗКА"
					elseif kind == "Equipped" then "НАДЕТО ✓"
					elseif kind == "Owned" then "НАДЕТЬ"
					elseif kind == "Locked" then "ЦЕЛЬ МАСТЕРСТВА"
					elseif kind == "Available" then "ЗАБРАТЬ"
					elseif kind == "Affordable" then "КУПИТЬ"
					else string.format("ЕЩЁ %d", state.Remaining)
			elseif entry.Kind == "Mastery" then
				local progress = PlayerHints.masteryProgress(
					player:GetAttribute("Mastery_" .. entry.Id),
					entry.Data.Target
				)
				local unlocked = player:GetAttribute("UnlockedTitle_" .. entry.Id) == true
				local equipped = player:GetAttribute("EquippedTitle") == entry.Id
				row.Detail.Text = entry.Data.Description
					.. string.format(
						"\n%d / %d · награда: этот титул",
						progress,
						entry.Data.Target
					)
					.. if saveView.Temporary
						then "\nВременно · только до выхода"
						else "\nБез покупок · только внешний вид"
				entry.Action = "EquipTitle"
				entry.RequestId = if equipped then "None" else entry.Id
				entry.Enabled = not loading and unlocked
				action.Text = if loading
					then "ЗАГРУЗКА"
					elseif not unlocked then "НЕ ОТКРЫТ"
					elseif equipped then "СНЯТЬ ТИТУЛ"
					else "НАДЕТЬ ТИТУЛ"
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
			if needsConsent then
				entry.Enabled = false
				action.Text = "ВЫБЕРИ РЕЖИМ"
			end
			action.BackgroundColor3 = if entry.Enabled then cyan else Color3.fromRGB(45, 60, 78)
			action.TextColor3 = if entry.Enabled then Color3.fromRGB(18, 30, 50) else muted
			action.AutoButtonColor = entry.Enabled
		end
		local text = player:GetAttribute("ActionMessage")
		local defaultText = if currentTab == "Quests"
			then "Постоянные цели дают титулы. Задания на сегодня — ниже. Пропуск дня ничего не отнимает."
			else "Следы меняют только внешний вид. Монеты зарабатываются в испытаниях."
		message.Text = if typeof(text) == "string" and text ~= "" then text else defaultText
		if saveView.Loading then
			message.Text = "Загружаем коллекцию…"
		elseif needsConsent then
			message.Text =
				"Без сохранения. Закрой меню и выбери «В испытания» → «Играть временно», чтобы использовать награды."
		elseif saveView.Warning then
			message.Text = saveView.Compact .. "  •  " .. message.Text
		end
	end

	local function revealReadyReward()
		if currentTab ~= "Quests" or not rewardReady() then
			return
		end
		task.defer(function()
			if destroyed or not panel.Visible or currentTab ~= "Quests" then
				return
			end
			for _, entry in rows do
				if entry.Action == "ClaimQuest" and entry.Enabled then
					local row = entry.Frame
					local top = row.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
					scroll.CanvasPosition = Vector2.new(
						0,
						math.clamp(top, 0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y))
					)
					if
						not GuiService.MenuIsOpen
						and string.find(UserInputService:GetLastInputType().Name, "Gamepad")
					then
						GuiService.SelectedObject = row.Action
					end
					break
				end
			end
		end)
	end

	local function selectTab(tab: string)
		preview.Clear()
		currentTab = tab
		for _, connection in rowConnections do
			connection:Disconnect()
		end
		table.clear(rowConnections)
		for _, entry in rows do
			entry.Frame:Destroy()
		end
		table.clear(rows)
		if mastery then
			mastery:Destroy()
			mastery = nil
		end
		if collectionGoal then
			collectionGoal:Destroy()
			collectionGoal = nil
		end
		cosmeticsTab.BackgroundColor3 = if tab == "Cosmetics" then Color3.fromRGB(39, 71, 96) else dark
		questsTab.BackgroundColor3 = if tab == "Quests" then Color3.fromRGB(39, 71, 96) else dark
		local catalog = {}
		if tab == "Cosmetics" then
			for _, trail in economy.Trails do
				table.insert(catalog, { Id = trail.Id, Data = trail })
			end
		else
			for _, milestone in economy.MasteryMilestones or {} do
				table.insert(catalog, { Id = milestone.Id, Data = milestone, Kind = "Mastery" })
			end
			for _, id in { "survive", "stars", "runs" } do
				table.insert(catalog, { Id = id, Data = economy.Quests[id] })
			end
		end
		for index, item in catalog do
			local row = template:Clone()
			row.Name = "Item_" .. item.Id
			row.LayoutOrder = index
			row.Title.Text = if item.Kind == "Mastery"
				then "ТИТУЛ · " .. item.Data.Title
				else item.Data.Name
			row.Swatch.BackgroundColor3 = item.Data.Color or Color3.fromRGB(66, 220, 169)
			row.Visible = true
			row.Parent = scroll
			local previewButton: TextButton? = nil
			if tab == "Cosmetics" then
				row.Size = UDim2.new(1, -8, 0, 160)
				row.Title.Size = UDim2.new(1, -24, 0, 28)
				row.Detail.Position = UDim2.fromOffset(12, 36)
				row.Detail.Size = UDim2.new(1, -24, 0, 64)
				row.Detail.TextScaled = false
				row.Detail.TextSize = 14
				row.Detail.TextWrapped = true
				row.Detail.TextYAlignment = Enum.TextYAlignment.Top
				row.Action.Size = UDim2.new(0.5, -16, 0, 44)
				row.Action.Position = UDim2.new(0.5, 4, 0, 108)
				previewButton = row.Action:Clone()
				assert(previewButton, "The authored catalog action must be archivable")
				previewButton.Name = "Preview"
				previewButton.Text = "ПРИМЕРИТЬ"
				previewButton.Position = UDim2.fromOffset(12, 108)
				previewButton.BackgroundColor3 = Color3.fromRGB(39, 71, 96)
				previewButton.TextColor3 = Color3.fromRGB(246, 248, 255)
				previewButton.Parent = row
			elseif item.Kind == "Mastery" then
				-- Descriptions remain readable at phone widths; actions keep a separate
				-- 44px target below the text instead of squeezing beside it.
				row.Size = UDim2.new(1, -8, 0, 214)
				row.Title.Size = UDim2.new(1, -24, 0, 28)
				row.Detail.Position = UDim2.fromOffset(12, 36)
				row.Detail.Size = UDim2.new(1, -24, 0, 120)
				row.Detail.TextScaled = false
				row.Detail.TextSize = 13
				row.Detail.TextWrapped = true
				row.Detail.TextYAlignment = Enum.TextYAlignment.Top
				row.Action.Size = UDim2.new(1, -24, 0, 44)
				row.Action.Position = UDim2.fromOffset(12, 162)
			end
			local entry = {
				Id = item.Id,
				RequestId = item.Id,
				Kind = item.Kind,
				Data = item.Data,
				Frame = row,
				Enabled = false,
				Action = "",
			}
			table.insert(rows, entry)
			table.insert(
				rowConnections,
				row.Action.Activated:Connect(function()
					if entry.Enabled and panel.Visible and os.clock() - lastAction >= 0.35 then
						lastAction = os.clock()
						remote:FireServer(entry.Action, entry.RequestId)
					end
				end)
			)
			local function reveal(button: GuiObject)
				local top = button.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
				local bottom = top + button.AbsoluteSize.Y
				local y = scroll.CanvasPosition.Y
				if index == 1 and tab == "Quests" then
					-- Reveal the records when they fit, but never scroll the selected
					-- action out of view on a short viewport.
					y = math.max(0, bottom - scroll.AbsoluteSize.Y)
				elseif top < y then
					y = top
				elseif bottom > y + scroll.AbsoluteSize.Y then
					y = bottom - scroll.AbsoluteSize.Y
				end
				scroll.CanvasPosition = Vector2.new(
					0,
					math.clamp(y, 0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y))
				)
			end
			table.insert(
				rowConnections,
				row.Action.SelectionGained:Connect(function()
					reveal(row.Action)
				end)
			)
			if previewButton then
				local button = previewButton
				table.insert(
					rowConnections,
					button.Activated:Connect(function()
						if not destroyed and panel.Visible and phase ~= "Rule" then
							preview.Toggle(row, item.Data)
							-- Let the list layout settle before keeping the focused action reachable.
							task.defer(function()
								if not destroyed and button.Parent and panel.Visible then
									reveal(button)
								end
							end)
						end
					end)
				)
				table.insert(
					rowConnections,
					button.SelectionGained:Connect(function()
						reveal(button)
					end)
				)
			end
		end
		if tab == "Cosmetics" then
			local block = template:Clone()
			block.Name = "CollectionGoal"
			block.LayoutOrder = 0
			block.Size = UDim2.new(1, -8, 0, 112)
			block.Swatch.BackgroundColor3 = Color3.fromRGB(255, 213, 79)
			block.Title.Size = UDim2.new(1, -24, 0, 26)
			block.Detail.Position = UDim2.fromOffset(12, 33)
			block.Detail.Size = UDim2.new(1, -24, 0, 70)
			block.Detail.TextScaled = false
			block.Detail.TextSize = 14
			block.Detail.TextWrapped = true
			block.Detail.TextYAlignment = Enum.TextYAlignment.Top
			block.Action.Visible = false
			block.Action.Selectable = false
			block.Action.Active = false
			block.Visible = true
			block.Parent = scroll
			collectionGoal = block
		end
		if tab == "Quests" then
			-- Read-only summary above the quests; it has no button and is skipped by gamepad focus.
			local block = template:Clone()
			block.Name = "Mastery"
			block.LayoutOrder = 0
			block.Size = UDim2.new(1, -8, 0, 80)
			block.Swatch.BackgroundColor3 = Color3.fromRGB(255, 213, 79)
			block.Title.Text = PlayerHints.MasteryTitle
			block.Title.Size = UDim2.new(1, -24, 0, 26)
			block.Detail.Position = UDim2.fromOffset(12, 33)
			block.Detail.Size = UDim2.new(1, -24, 0, 40)
			block.Detail.TextColor3 = Color3.fromRGB(246, 248, 255)
			block.Action.Visible = false
			block.Action.Selectable = false
			block.Action.Active = false
			block.Visible = true
			block.Parent = scroll
			mastery = block
		end
		for index, entry in rows do
			local action = entry.Frame.Action :: TextButton
			local previewButton = entry.Frame:FindFirstChild("Preview") :: TextButton?
			action.NextSelectionUp = if index == 1 then cosmeticsTab else rows[index - 1].Frame.Action
			action.NextSelectionDown = if index == #rows then closeButton else rows[index + 1].Frame.Action
			action.NextSelectionLeft = previewButton or cosmeticsTab
			action.NextSelectionRight = previewButton or questsTab
			if previewButton then
				previewButton.NextSelectionLeft = action
				previewButton.NextSelectionRight = action
				previewButton.NextSelectionUp = if index == 1
					then cosmeticsTab
					else rows[index - 1].Frame.Preview
				previewButton.NextSelectionDown = if index == #rows
					then closeButton
					else rows[index + 1].Frame.Preview
			end
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
		revealReadyReward()
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
		local screen = root.Parent
		local stationModal = if screen then screen:GetAttribute("StationModal") else nil
		panel.Visible = visible and phase ~= "Rule" and (stationModal == nil or stationModal == "")
		backdrop.Visible = panel.Visible
		if panel.Visible then
			refresh()
			focusPanel()
			revealReadyReward()
			ContextActionService:BindAction(closeAction, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					setVisible(false)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
		else
			preview.Clear()
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
	connect(player.CharacterAdded, function()
		preview.Clear()
	end)
	if root.Parent then
		connect(root.Parent:GetAttributeChangedSignal("StationModal"), function()
			if root.Parent and root.Parent:GetAttribute("StationModal") ~= "" then
				setVisible(false)
			end
		end)
	end
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
			destroyed = true
			preview.Destroy()
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, connection in rowConnections do
				connection:Disconnect()
			end
			for _, entry in rows do
				entry.Frame:Destroy()
			end
			if mastery then
				mastery:Destroy()
			end
			if collectionGoal then
				collectionGoal:Destroy()
			end
		end,
	}
end

return CollectionPanel
