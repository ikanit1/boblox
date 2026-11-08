--!strict
-- A local, scrollable settings panel. Gameplay controls remain outside its touch footprint.
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local AudioSettings = {}

function AudioSettings.bounds(width: number, height: number, touch: boolean): (number, number)
	local panelWidth = math.min(380, math.max(120, width - 24))
	local panelHeight = math.min(370, math.max(120, height - 16))
	if touch then
		if width > height then
			-- Keep the standard left/right movement controls outside the center column.
			panelWidth = math.min(panelWidth, math.max(120, width - 336))
		else
			panelHeight = math.min(panelHeight, math.max(120, height - 168))
		end
	end
	return panelWidth, panelHeight
end

function AudioSettings.new(root: Frame, player: Player, state: Instance, button: TextButton, preferences: any)
	local screen = root:FindFirstAncestorOfClass("ScreenGui")
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local previousSelection: GuiObject? = nil
	local deathConnection: RBXScriptConnection? = nil
	local characterEpoch = 0
	local actionName = "RuleRoomCloseAudioSettings"
	local ink = Color3.fromRGB(246, 248, 255)
	local blue = Color3.fromRGB(39, 71, 96)
	local panel = Instance.new("Frame")
	panel.Name = "AudioSettings"
	panel.BackgroundColor3 = Color3.fromRGB(18, 30, 50)
	panel.BackgroundTransparency = 0.02
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 8)
	panel.Visible = false
	panel.ZIndex = 30
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end
	local function label(parent: Instance, name: string, text: string): TextLabel
		local result = Instance.new("TextLabel")
		result.Name = name
		result.Text = text
		result.TextColor3 = ink
		result.BackgroundTransparency = 1
		result.Font = Enum.Font.GothamMedium
		result.TextSize = 14
		result.TextWrapped = true
		result.TextXAlignment = Enum.TextXAlignment.Left
		result.RichText = false
		result.ZIndex = 31
		result.Parent = parent
		return result
	end
	local function control(parent: Instance, name: string, text: string): TextButton
		local result = Instance.new("TextButton")
		result.Name = name
		result.Text = text
		result.Font = Enum.Font.GothamBold
		result.TextSize = 14
		result.TextColor3 = ink
		result.BackgroundColor3 = blue
		result.Size = UDim2.fromOffset(44, 44)
		result.Selectable = true
		result.AutoButtonColor = true
		result.ZIndex = 32
		result.Parent = parent
		local radius = Instance.new("UICorner")
		radius.CornerRadius = UDim.new(0, 7)
		radius.Parent = result
		return result
	end
	local title = label(panel, "Title", "ЗВУК И ЭФФЕКТЫ")
	title.Position = UDim2.fromOffset(12, 4)
	title.Size = UDim2.new(1, -72, 0, 44)
	local close = control(panel, "Close", "×")
	close.Position = UDim2.new(1, -52, 0, 4)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Options"
	scroll.Position = UDim2.fromOffset(10, 52)
	scroll.Size = UDim2.new(1, -20, 1, -104)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ClipsDescendants = true
	scroll.ZIndex = 31
	scroll.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	local status = label(panel, "Status", "")
	status.Position = UDim2.new(0, 12, 1, -48)
	status.Size = UDim2.new(1, -24, 0, 40)
	local optionButtons: { TextButton } = {}
	local volumeLabels: { [string]: TextLabel } = {}
	for index, info in
		{
			{ "EffectsVolume", "Сигналы и кнопки" },
			{ "MusicVolume", "Музыка лаборатории" },
		}
	do
		local row = Instance.new("Frame")
		row.Name = info[1]
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -6, 0, 80)
		row.LayoutOrder = index
		row.Parent = scroll
		local heading = label(row, "Label", info[2])
		heading.Size = UDim2.new(1, 0, 0, 28)
		local less = control(row, "Less", "−")
		less.Position = UDim2.fromOffset(0, 32)
		local more = control(row, "More", "+")
		more.Position = UDim2.new(1, -44, 0, 32)
		local value = label(row, "Value", "")
		value.Position = UDim2.fromOffset(48, 32)
		value.Size = UDim2.new(1, -96, 0, 44)
		value.TextXAlignment = Enum.TextXAlignment.Center
		volumeLabels[info[1]] = value
		for _, entry in { { less, -1 }, { more, 1 } } do
			local targetButton, delta = entry[1] :: TextButton, entry[2] :: number
			table.insert(optionButtons, targetButton)
			connect(targetButton.Activated, function()
				if panel.Visible then
					local current = preferences.Get(info[1])
					preferences.Set(info[1], math.clamp((math.round(current * 4) + delta) / 4, 0, 1))
				end
			end)
		end
		less.NextSelectionLeft, less.NextSelectionRight = more, more
		more.NextSelectionLeft, more.NextSelectionRight = less, less
	end
	local mute = control(scroll, "Mute", "")
	mute.Size = UDim2.new(1, -6, 0, 44)
	mute.LayoutOrder = 3
	table.insert(optionButtons, mute)
	local motionRow = Instance.new("Frame")
	motionRow.Name = "Motion"
	motionRow.BackgroundTransparency = 1
	motionRow.Size = UDim2.new(1, -6, 0, 76)
	motionRow.LayoutOrder = 4
	motionRow.Parent = scroll
	local motion = control(motionRow, "Toggle", "")
	motion.Size = UDim2.new(1, 0, 0, 44)
	table.insert(optionButtons, motion)
	local motionHint = label(motionRow, "Hint", "")
	motionHint.Position = UDim2.fromOffset(0, 46)
	motionHint.Size = UDim2.new(1, 0, 0, 30)
	local function unsafe(): boolean
		local phase = state:GetAttribute("Phase")
		return phase == "Rule" or phase == "Break" or player:GetAttribute("InRound") == true
	end
	local function render()
		for key, value in volumeLabels do
			value.Text = string.format("%d%%", math.round(preferences.Get(key) * 100))
		end
		local muted = preferences.Get("AudioMuted")
		mute.Text = if muted then "ВЕСЬ ЗВУК: ВЫКЛ" else "ВЕСЬ ЗВУК: ВКЛ"
		motion.Text = if preferences.Get("ReducedMotion")
			then "МЕНЬШЕ ЭФФЕКТОВ: ДА"
			else "МЕНЬШЕ ЭФФЕКТОВ: НЕТ"
		motionHint.Text = if GuiService.ReducedMotionEnabled
			then "Устройство всегда уменьшает эффекты"
			else "Убирает движение и лишние вспышки"
		status.Text = player:GetAttribute("RuleRoomPreferenceStatus")
			or "Настройки применяются здесь"
		button.Text = if unsafe()
			then (if muted then "ЗВУК: ВЫКЛ" else "ЗВУК: ВКЛ")
			else (if muted then "ЗВУК: ВЫКЛ" else "ЗВУК / FX")
	end
	local function visible(object: GuiObject?): boolean
		if not object or not object:IsDescendantOf(root) or not object.Selectable or not root.Visible then
			return false
		end
		local parent: Instance? = object
		while parent and parent ~= root do
			if parent:IsA("GuiObject") and not parent.Visible then
				return false
			end
			parent = parent.Parent
		end
		return true
	end
	local function closePanel()
		panel.Visible = false
		ContextActionService:UnbindAction(actionName)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
			GuiService.SelectedObject = if visible(previousSelection)
				then previousSelection
				elseif visible(button) then button
				else nil
		end
		previousSelection = nil
	end
	local function focusPanel()
		if
			not panel.Visible
			or GuiService.MenuIsOpen
			or not string.find(UserInputService:GetLastInputType().Name, "Gamepad")
		then
			return
		end
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(panel) then
			GuiService.SelectedObject = optionButtons[1]
		end
	end
	local function openPanel()
		local collection = root:FindFirstChild("CollectionPanel")
		if
			destroyed
			or unsafe()
			or not root.Visible
			or (screen and screen:GetAttribute("StationModal") ~= nil and screen:GetAttribute("StationModal") ~= "")
			or (collection and collection:IsA("GuiObject") and collection.Visible)
		then
			return
		end
		previousSelection = GuiService.SelectedObject
		panel.Visible = true
		render()
		focusPanel()
		ContextActionService:BindAction(actionName, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				closePanel()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	end
	local function layout()
		local width, height =
			AudioSettings.bounds(root.AbsoluteSize.X, root.AbsoluteSize.Y, UserInputService.TouchEnabled)
		panel.Size = UDim2.fromOffset(width, height)
	end
	for index, targetButton in optionButtons do
		targetButton.NextSelectionUp = if index == 1 then close else optionButtons[index - 1]
		targetButton.NextSelectionDown = if index == #optionButtons then close else optionButtons[index + 1]
		if index >= 5 then
			targetButton.NextSelectionLeft, targetButton.NextSelectionRight = close, close
		end
		connect(targetButton.SelectionGained, function()
			local top = targetButton.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
			local bottom = top + targetButton.AbsoluteSize.Y
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
	end
	close.NextSelectionDown, close.NextSelectionUp = optionButtons[1], motion
	close.NextSelectionLeft, close.NextSelectionRight = mute, mute
	connect(close.Activated, closePanel)
	connect(button.Activated, function()
		if unsafe() then
			preferences.Set("AudioMuted", not preferences.Get("AudioMuted"))
		elseif panel.Visible then
			closePanel()
		else
			openPanel()
		end
	end)
	connect(mute.Activated, function()
		if panel.Visible then
			preferences.Set("AudioMuted", not preferences.Get("AudioMuted"))
		end
	end)
	connect(motion.Activated, function()
		if panel.Visible then
			preferences.Set("ReducedMotion", not preferences.Get("ReducedMotion"))
		end
	end)
	connect(state:GetAttributeChangedSignal("Phase"), function()
		if unsafe() then
			closePanel()
		end
		render()
	end)
	connect(player.AttributeChanged, function(name)
		if
			(name == "InRound" and unsafe()) or (name == "Eliminated" and player:GetAttribute(name) == true)
		then
			closePanel()
		end
		if name == "InRound" or string.sub(name, 1, 8) == "RuleRoom" then
			render()
		end
	end)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), layout)
	connect(root:GetPropertyChangedSignal("Visible"), function()
		if not root.Visible then
			closePanel()
		end
	end)
	connect(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"), render)
	connect(UserInputService.LastInputTypeChanged, focusPanel)
	connect(GuiService:GetPropertyChangedSignal("MenuIsOpen"), focusPanel)
	if screen then
		connect(screen:GetAttributeChangedSignal("StationModal"), function()
			if screen:GetAttribute("StationModal") ~= "" then
				closePanel()
			end
		end)
	end
	local collection = root:FindFirstChild("CollectionPanel")
	if collection and collection:IsA("GuiObject") then
		connect(collection:GetPropertyChangedSignal("Visible"), function()
			if collection.Visible then
				closePanel()
			end
		end)
	end
	local function bindCharacter(character: Model)
		closePanel()
		characterEpoch += 1
		local epoch = characterEpoch
		if deathConnection then
			deathConnection:Disconnect()
			deathConnection = nil
		end
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if
				not destroyed
				and epoch == characterEpoch
				and player.Character == character
				and humanoid
				and humanoid:IsA("Humanoid")
			then
				deathConnection = humanoid.Died:Connect(closePanel)
			end
		end)
	end
	connect(player.CharacterAdded, bindCharacter)
	connect(player.CharacterRemoving, function()
		characterEpoch += 1
		closePanel()
		if deathConnection then
			deathConnection:Disconnect()
			deathConnection = nil
		end
	end)
	if player.Character then
		bindCharacter(player.Character)
	end
	layout()
	render()
	panel.Parent = root
	return {
		Open = openPanel,
		Close = closePanel,
		IsOpen = function(): boolean
			return panel.Visible
		end,
		Destroy = function()
			if destroyed then
				return
			end
			closePanel()
			destroyed = true
			characterEpoch += 1
			if deathConnection then
				deathConnection:Disconnect()
			end
			for _, connection in connections do
				connection:Disconnect()
			end
			panel:Destroy()
		end,
	}
end

return AudioSettings
