--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("StationHUD") :: ScreenGui
local bar = gui:WaitForChild("StationBar") :: Frame
local guide = gui:WaitForChild("Guide") :: Frame
local toggle = gui:WaitForChild("ExploreToggle") :: TextButton
local welcome = gui:WaitForChild("Welcome") :: Frame
local backdrop = gui:WaitForChild("ModalBackdrop") :: Frame
local waitingChoiceUntil = 0
local requestedChoice = false
local welcomeWasVisible = false
local shared = ReplicatedStorage:WaitForChild("RuleRoomShared")
local guides = require(shared:WaitForChild("RuleGuides"))
local config = require(shared:WaitForChild("GameConfig"))
local remote = ReplicatedStorage:WaitForChild("RuleRoomRemotes"):WaitForChild("StationAction") :: RemoteEvent
local connections: { RBXScriptConnection } = {}
local previousSelection: GuiObject? = nil
local lastRequest = -math.huge
local motionReplaced = false
local mainGui = player.PlayerGui:WaitForChild("RuleRoomHUD") :: ScreenGui
local collectionPanel =
	player.PlayerGui:WaitForChild("RuleRoomHUD"):WaitForChild("Root"):WaitForChild("CollectionPanel") :: Frame
local mainActions = mainGui.Root.Actions :: Frame
local decorations: { { part: BasePart, origin: CFrame } } = {}
local scene = Workspace:WaitForChild("Arena"):WaitForChild("Lobby")
for _, part in
	{
		scene.ReactorExhibit.EnergyCore,
		scene.RuleGallery.Exhibit_Spinner.Beam,
		scene.RuleGallery.Exhibit_Spinner.CrossBeam,
	}
do
	table.insert(decorations, { part = part, origin = part.CFrame })
end
bar.Join.NextSelectionRight = bar.Explore
bar.Join.NextSelectionLeft = bar.Explore
bar.Explore.NextSelectionLeft = bar.Join
bar.Explore.NextSelectionRight = bar.Join
bar.Join.NextSelectionDown = mainActions.Collection
bar.Explore.NextSelectionDown = mainActions.Collection
toggle.NextSelectionDown = mainActions.Collection
welcome.SelectionGroup = true
welcome.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
welcome.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
welcome.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
welcome.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
welcome.Play.NextSelectionLeft = welcome.Explore
welcome.Play.NextSelectionRight = welcome.Explore
welcome.Explore.NextSelectionLeft = welcome.Play
welcome.Explore.NextSelectionRight = welcome.Play
welcome.Play.NextSelectionUp = welcome.Play
welcome.Play.NextSelectionDown = welcome.Play
welcome.Explore.NextSelectionUp = welcome.Explore
welcome.Explore.NextSelectionDown = welcome.Explore
guide.SelectionGroup = true
guide.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
guide.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
guide.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
guide.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

local function canRestore(object: GuiObject?): boolean
	if not object or not object:IsDescendantOf(player.PlayerGui) or not object.Selectable then
		return false
	end
	local current: Instance? = object
	while current and current ~= player.PlayerGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("ScreenGui") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end
local function gamepad(): boolean
	return string.find(UserInputService:GetLastInputType().Name, "Gamepad") ~= nil
end
local focusEpoch = 0
local function restoreFocusAfterLayout(preferred: GuiObject?)
	focusEpoch += 1
	local epoch = focusEpoch
	-- render() restores the station bar and HUD before a hidden control can regain focus.
	task.delay(0.12, function()
		if epoch ~= focusEpoch or not gui.Parent or not gamepad() or GuiService.MenuIsOpen then
			return
		end
		if welcome.Visible or guide.Visible or mainGui:GetAttribute("StationModal") ~= "" then
			return
		end
		local selected = GuiService.SelectedObject
		if canRestore(selected) then
			return
		end
		if collectionPanel.Visible then
			if canRestore(collectionPanel.CosmeticsTab) then
				GuiService.SelectedObject = collectionPanel.CosmeticsTab
			end
			return
		end
		if canRestore(preferred) then
			GuiService.SelectedObject = preferred
			return
		end
		for _, candidate in
			{
				mainGui.Root.VotePanel.Cards.Balanced,
				bar.Join,
				toggle,
				mainActions.Collection,
				mainActions.Motion,
				mainActions.Audio,
			}
		do
			if canRestore(candidate) then
				GuiService.SelectedObject = candidate
				return
			end
		end
	end)
end
local function closeGuide()
	if not guide.Visible then
		return
	end
	local restore = previousSelection
	guide.Visible = false
	ContextActionService:UnbindAction("CloseStationGuide")
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(guide) then
		GuiService.SelectedObject = nil
	end
	previousSelection = nil
	restoreFocusAfterLayout(restore)
end
local function send(action: string)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 or player:GetAttribute("DataStatus") == "Loading" then
		return
	end
	if welcome.Visible and os.clock() < waitingChoiceUntil then
		return
	end
	if os.clock() - lastRequest < 0.45 then
		return
	end
	lastRequest = os.clock()
	if welcome.Visible then
		waitingChoiceUntil = os.clock() + 3
		requestedChoice = true
	end
	closeGuide()
	remote:FireServer(action)
end
table.insert(
	connections,
	(bar.Join :: TextButton).Activated:Connect(function()
		send("Join")
	end)
)
table.insert(
	connections,
	(bar.Explore :: TextButton).Activated:Connect(function()
		send("Explore")
	end)
)
table.insert(
	connections,
	toggle.Activated:Connect(function()
		send("Explore")
	end)
)
table.insert(connections, (guide.Close :: TextButton).Activated:Connect(closeGuide))
table.insert(
	connections,
	(welcome.Play :: TextButton).Activated:Connect(function()
		send("Join")
	end)
)
table.insert(
	connections,
	(welcome.Explore :: TextButton).Activated:Connect(function()
		send("Explore")
	end)
)
table.insert(
	connections,
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who and who ~= player then
			return
		end
		if player:GetAttribute("InRound") == true or welcome.Visible or collectionPanel.Visible then
			return
		end
		local parent = prompt.Parent
		if not parent or not parent:IsDescendantOf(Workspace:WaitForChild("Arena")) then
			return
		end
		local action = parent:GetAttribute("StationAction")
		if typeof(action) ~= "string" or string.sub(action, 1, 6) ~= "Guide:" then
			return
		end
		local id = string.sub(action, 7)
		if not guides[id] or not config.Rules[id] then
			return
		end
		previousSelection = GuiService.SelectedObject
		focusEpoch += 1
		guide.Heading.Text = config.Rules[id].Name
		guide.Body.Text = guides[id]
		guide.Visible = true
		ContextActionService:BindAction("CloseStationGuide", function(_, state)
			if state == Enum.UserInputState.Begin then
				closeGuide()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
		if
			GuiService:IsTenFootInterface()
			or string.find(game:GetService("UserInputService"):GetLastInputType().Name, "Gamepad")
		then
			GuiService.SelectedObject = guide.Close
		end
	end)
)

local function render()
	local exploring = player:GetAttribute("LobbyOnly") == true
	local inRound = player:GetAttribute("InRound") == true
	welcome.Visible = player:GetAttribute("EntryChoiceMade") ~= true and not inRound
	if inRound or collectionPanel.Visible or welcome.Visible then
		closeGuide()
	end
	local modal = if welcome.Visible then "Welcome" elseif guide.Visible then "Guide" else ""
	mainGui:SetAttribute("StationModal", modal)
	backdrop.Visible = modal ~= ""
	bar.Visible = exploring and not inRound and not collectionPanel.Visible and modal == ""
	mainActions.Visible = modal == "" and mainGui:GetAttribute("CompactPlayHUD") ~= true
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local ready = humanoid ~= nil and humanoid.Health > 0 and player:GetAttribute("DataStatus") ~= "Loading"
	local waiting = os.clock() < waitingChoiceUntil
	for _, button in { welcome.Play, welcome.Explore } do
		button.Active = ready and not waiting
		button.AutoButtonColor = ready and not waiting
		button.Selectable = ready and not waiting
		button.BackgroundTransparency = if ready and not waiting then 0 else 0.45
	end
	welcome.Status.Text = if not ready
		then "Подготавливаем персонажа…"
		elseif waiting then "Подключаем к выбранному режиму…"
		elseif
			requestedChoice
		then "Не удалось войти. Нажми ещё раз, когда персонаж появится в лаборатории."
		else "Можно играть одному или вместе с друзьями."
	if welcome.Visible and not welcomeWasVisible then
		ContextActionService:BindAction("WelcomeExplore", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				send("Explore")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB)
	elseif not welcome.Visible and welcomeWasVisible then
		ContextActionService:UnbindAction("WelcomeExplore")
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(welcome) then
			GuiService.SelectedObject = nil
		end
		restoreFocusAfterLayout(nil)
	end
	welcomeWasVisible = welcome.Visible
	if welcome.Visible and ready and not waiting and gamepad() and not GuiService.MenuIsOpen then
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(welcome) or not selected.Selectable then
			GuiService.SelectedObject = welcome.Play
		end
	end
	local character = player.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local inLobby = rootPart and rootPart:IsA("BasePart") and rootPart.Position.Z > 43
	toggle.Visible = not welcome.Visible
		and mainGui:GetAttribute("CompactPlayHUD") ~= true
		and not exploring
		and not inRound
		and not collectionPanel.Visible
		and not guide.Visible
		and inLobby == true
		and not mainGui.Root.SpectateNext.Visible
	-- Reuse the settings slot while queued. A floating button would cover voting cards
	-- on phones; the motion setting stays available in exploration and active trials.
	if toggle.Visible then
		motionReplaced = true
		mainActions.Motion.Visible = false
		toggle.Position =
			UDim2.fromOffset(mainActions.Motion.AbsolutePosition.X, mainActions.Motion.AbsolutePosition.Y)
		toggle.Size = UDim2.fromOffset(mainActions.Motion.AbsoluteSize.X, mainActions.Motion.AbsoluteSize.Y)
		mainActions.Collection.NextSelectionRight = toggle
		toggle.NextSelectionLeft = mainActions.Collection
		toggle.NextSelectionRight = mainActions.Audio
		mainActions.Audio.NextSelectionLeft = toggle
		if GuiService.SelectedObject == mainActions.Motion and gamepad() and not GuiService.MenuIsOpen then
			GuiService.SelectedObject = toggle
		end
	elseif motionReplaced then
		motionReplaced = false
		mainActions.Motion.Visible = not (
			mainGui.Root.AbsoluteSize.Y < 330 and mainGui.Root.SpectateNext.Visible
		)
		mainActions.Collection.NextSelectionRight = mainActions.Motion
		mainActions.Audio.NextSelectionLeft = mainActions.Motion
		if GuiService.SelectedObject == toggle then
			GuiService.SelectedObject = nil
			restoreFocusAfterLayout(mainActions.Motion)
		end
	end
	if collectionPanel.Visible then
		closeGuide()
	end
	if inRound then
		closeGuide()
	end
	if exploring then
		mainActions.Collection.NextSelectionUp = bar.Join
	end
	local running = player:GetAttribute("PracticeState") == "Running"
	local completed = player:GetAttribute("PracticeState") == "Finished"
	local best = player:GetAttribute("PracticeBestSeconds")
	bar.Status.Text = if running
		then string.format(
			"ПАРКУР / %d ИЗ 7 КОНТРОЛЬНЫХ ТОЧЕК",
			player:GetAttribute("PracticeCheckpoint") or 0
		)
		elseif completed then string.format(
			"ФИНИШ! %.2f СЕК",
			player:GetAttribute("PracticeLastSeconds") or 0
		)
		else "ЛАБОРАТОРИЯ / СВОБОДНЫЙ РЕЖИМ"
	local seconds = math.max(
		0,
		Workspace:GetServerTimeNow()
			- (player:GetAttribute("PracticeStartedAt") or Workspace:GetServerTimeNow())
	)
	bar.Detail.Text = if running
		then string.format(
			"Время %.1f сек · падение вернёт к последней точке",
			seconds
		)
		elseif typeof(best) == "number" then string.format(
			"Твой рекорд здесь: %.2f сек · хранится до выхода с сервера",
			best
		)
		else "Паркур слева · архив правил справа · галерея впереди"
	bar.Explore.Text = if running
		then "ЗАКОНЧИТЬ ТРЕНИРОВКУ"
		else "СВОБОДНАЯ ПРОГУЛКА"
	local height = mainGui.Root.AbsoluteSize.Y
	local modalHeight = math.min(306, math.max(210, height - 24))
	guide.Size = UDim2.new(1, -24, 0, math.min(320, math.max(180, height - 24)))
	welcome.Size = UDim2.new(1, -24, 0, modalHeight)
	welcome.Eyebrow.Visible = modalHeight >= 260
	welcome.Heading.Position = UDim2.fromOffset(16, if modalHeight >= 260 then 34 else 8)
	welcome.Heading.Size = UDim2.new(1, -32, 0, if modalHeight >= 260 then 36 else 28)
	welcome.Steps.Position = UDim2.fromOffset(20, if modalHeight >= 260 then 78 else 40)
	welcome.Steps.Size = UDim2.new(1, -40, 0, modalHeight - (if modalHeight >= 260 then 194 else 153))
	welcome.Detail.Visible = modalHeight >= 240
end
table.insert(connections, player.AttributeChanged:Connect(render))
table.insert(
	connections,
	UserInputService.LastInputTypeChanged:Connect(function()
		if not gamepad() or GuiService.MenuIsOpen then
			return
		end
		if guide.Visible then
			GuiService.SelectedObject = guide.Close
		elseif welcome.Visible then
			if welcome.Play.Selectable then
				GuiService.SelectedObject = welcome.Play
			end
		elseif bar.Visible then
			GuiService.SelectedObject = bar.Join
		end
	end)
)
table.insert(
	connections,
	player:GetAttributeChangedSignal("LobbyOnly"):Connect(function()
		if
			player:GetAttribute("LobbyOnly") == true
			and player:GetAttribute("EntryChoiceMade") == true
			and bar.Visible
			and not GuiService.MenuIsOpen
			and string.find(game:GetService("UserInputService"):GetLastInputType().Name, "Gamepad")
		then
			GuiService.SelectedObject = bar.Join
		end
	end)
)
local elapsed = 0
table.insert(
	connections,
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			render()
			local reduced = mainGui:GetAttribute("ReducedMotion") == true
			local now = Workspace:GetServerTimeNow()
			for index, entry in decorations do
				entry.part.CFrame = if reduced
					then entry.origin
					elseif index == 1 then entry.origin * CFrame.new(0, math.sin(now * 1.6) * 0.35, 0)
					else entry.origin * CFrame.Angles(0, now * 0.5, 0)
			end
		end
	end)
)
render()
gui.Destroying:Connect(function()
	closeGuide()
	focusEpoch += 1
	ContextActionService:UnbindAction("WelcomeExplore")
	mainGui:SetAttribute("StationModal", "")
	for _, connection in connections do
		connection:Disconnect()
	end
	for _, entry in decorations do
		if entry.part.Parent then
			entry.part.CFrame = entry.origin
		end
	end
end)
