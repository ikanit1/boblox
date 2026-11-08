--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local SocialService = game:GetService("SocialService")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("StationHUD") :: ScreenGui
local bar = gui:WaitForChild("StationBar") :: Frame
local guide = gui:WaitForChild("Guide") :: Frame
local toggle = gui:WaitForChild("ExploreToggle") :: TextButton
local welcome = gui:WaitForChild("Welcome") :: Frame
local backdrop = gui:WaitForChild("ModalBackdrop") :: Frame
local invite = bar:WaitForChild("Invite") :: TextButton
local canInvite = false
local inviteCheckedAt = -math.huge
local invitePromptOpen = false
local inviteCheckPending = false
local invitePromptEpoch = 0
local destroyed = false
local waitingChoiceUntil = 0
local requestedChoice = false
local welcomeWasVisible = false
local shared = ReplicatedStorage:WaitForChild("RuleRoomShared")
local guides = require(shared:WaitForChild("RuleGuides"))
local config = require(shared:WaitForChild("GameConfig"))
local ProfileStatus = require(shared:WaitForChild("ProfileStatus"))
local PlayerHints = require(shared:WaitForChild("PlayerHints"))
local GuidePreview = require(script.Parent:WaitForChild("GuidePreview"))
local roomState = ReplicatedStorage:WaitForChild("RuleRoomState")
local normalWelcomeSteps = (welcome.Steps :: TextLabel).Text
local normalWelcomeDetail = (welcome.Detail :: TextLabel).Text
local remote = ReplicatedStorage:WaitForChild("RuleRoomRemotes"):WaitForChild("StationAction") :: RemoteEvent
local profileRemote =
	ReplicatedStorage:WaitForChild("RuleRoomRemotes"):WaitForChild("ProfileAction") :: RemoteEvent
local connections: { RBXScriptConnection } = {}
local previousSelection: GuiObject? = nil
local lastRequest = -math.huge
local motionReplaced = false
local mainGui = player.PlayerGui:WaitForChild("RuleRoomHUD") :: ScreenGui
local guidePreview = GuidePreview.new(guide, mainGui)
local collectionPanel =
	player.PlayerGui:WaitForChild("RuleRoomHUD"):WaitForChild("Root"):WaitForChild("CollectionPanel") :: Frame
local mainActions = mainGui.Root.Actions :: Frame
local decorations: { { part: BasePart, origin: CFrame } } = {}
local scene = Workspace:WaitForChild("Arena"):WaitForChild("Lobby")
local practiceCourse = scene:WaitForChild("Practice")
local practiceConsole = practiceCourse:WaitForChild("StartConsole")
local practicePrompt = practiceConsole:WaitForChild("Interact") :: ProximityPrompt
local practiceSign = practiceConsole:WaitForChild("Display")
local warmupFinishLabel =
	practiceCourse:WaitForChild("Checkpoint2"):WaitForChild("Number"):WaitForChild("Index") :: TextLabel
local practiceSignDefaults = {
	ActionText = practicePrompt.ActionText,
	ObjectText = practicePrompt.ObjectText,
	Heading = practiceSign.Heading.Text,
	Detail = practiceSign.Detail.Text,
	Finish = warmupFinishLabel.Text,
}
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
invite.NextSelectionDown = mainActions.Collection
invite.Text = PlayerHints.InviteLabel
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

-- Reload is an explicit pre-progress request; it never accepts temporary play or rejoins a run.
local retryProfile = (welcome.Play :: TextButton):Clone()
retryProfile.Name = "RetryProfile"
retryProfile.Text = "ПОВТОРИТЬ ЗАГРУЗКУ"
retryProfile.Position = UDim2.new(0, 16, 1, -122)
retryProfile.Size = UDim2.new(1, -32, 0, 44)
retryProfile.Visible = false
retryProfile.Parent = welcome
local retryAwaiting, retrySawLoading = false, false
local retryPendingUntil = 0
local retryLastRequest = -math.huge
local function retryView()
	local now = Workspace:GetServerTimeNow()
	local view = ProfileStatus.retry(
		player:GetAttribute("CanRetryProfile"),
		player:GetAttribute("ProfileRetryAt"),
		player:GetAttribute("ProfileRetryRemaining"),
		now
	)
	if retryAwaiting then
		if player:GetAttribute("DataStatus") == "Loading" then
			retrySawLoading = true
		elseif retrySawLoading or now >= retryPendingUntil then
			retryAwaiting, retrySawLoading = false, false
		end
	end
	if retryAwaiting then
		view.Visible, view.Enabled, view.Text = true, false, "ЗАГРУЗКА…"
	end
	return view
end
local function renderRetry(view, ready: boolean)
	retryProfile.Visible = welcome.Visible and view.Visible
	retryProfile.Active = retryProfile.Visible and view.Enabled
	retryProfile.Selectable = retryProfile.Active
	retryProfile.AutoButtonColor = retryProfile.Active
	retryProfile.BackgroundTransparency = if retryProfile.Active then 0 else 0.45
	retryProfile.Text = view.Text
	local up = if retryProfile.Selectable then retryProfile else nil
	welcome.Play.NextSelectionUp = up or welcome.Play
	welcome.Explore.NextSelectionUp = up or welcome.Explore
	retryProfile.NextSelectionUp, retryProfile.NextSelectionDown = welcome.Play, welcome.Play
	retryProfile.NextSelectionLeft, retryProfile.NextSelectionRight = retryProfile, retryProfile
	if GuiService.SelectedObject == retryProfile and not retryProfile.Selectable then
		GuiService.SelectedObject = if welcome.Visible
				and ready
				and welcome.Play.Selectable
			then welcome.Play
			else nil
	end
end
local function layoutWelcome(height: number)
	local modalHeight = math.min(306, math.max(210, height - 24))
	welcome.Size = UDim2.new(1, -24, 0, modalHeight)
	welcome.Eyebrow.Visible = modalHeight >= 260
	welcome.Heading.Position = UDim2.fromOffset(16, if modalHeight >= 260 then 34 else 8)
	welcome.Heading.Size = UDim2.new(1, -32, 0, if modalHeight >= 260 then 36 else 28)
	welcome.Steps.Position = UDim2.fromOffset(20, if modalHeight >= 260 then 78 else 40)
	welcome.Steps.Size = UDim2.new(1, -40, 0, modalHeight - (if modalHeight >= 260 then 194 else 153))
	if retryProfile.Visible then
		welcome.Steps.Size =
			UDim2.new(1, -40, 0, math.max(28, modalHeight - (if modalHeight >= 260 then 212 else 174)))
	end
	welcome.Detail.Visible = modalHeight >= 240 and not retryProfile.Visible
end
table.insert(
	connections,
	retryProfile.Activated:Connect(function()
		local view = retryView()
		local now = Workspace:GetServerTimeNow()
		if
			destroyed
			or not welcome.Visible
			or player:GetAttribute("InRound") == true
			or not view.Enabled
			or now - retryLastRequest < 0.6
		then
			return
		end
		retryLastRequest = now
		retryAwaiting, retrySawLoading = true, false
		retryPendingUntil = now + 3
		local ok = pcall(function()
			profileRemote:FireServer("RetryLoad", "")
		end)
		if not ok then
			retryAwaiting = false
		end
		renderRetry(retryView(), false)
	end)
)
-- Archive cleanup preserves the independent welcome/profile choice.

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
	guidePreview.Hide()
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
table.insert(connections, player.CharacterRemoving:Connect(closeGuide))
local function send(action: string)
	if retryAwaiting then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local saveView =
		ProfileStatus.describe(player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent"))
	if not humanoid or humanoid.Health <= 0 or saveView.Loading then
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
	-- Only the clearly labelled welcome choice sends consent. Queue buttons and
	-- proximity prompts first ask the server to show that choice when required.
	remote:FireServer(action, action == "Join" and welcome.Visible and saveView.Temporary)
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

-- Invites are optional: any SocialService failure (Studio, privacy, policy) hides the button.
local function refreshInvite(force: boolean?)
	if destroyed or inviteCheckPending or (not force and os.clock() - inviteCheckedAt < 30) then
		return
	end
	inviteCheckedAt = os.clock()
	inviteCheckPending = true
	task.spawn(function()
		local ok, allowed = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		inviteCheckPending = false
		if destroyed then
			return
		end
		canInvite = ok and allowed == true
		gui:SetAttribute("InviteAvailable", canInvite)
	end)
end
table.insert(
	connections,
	invite.Activated:Connect(function()
		if
			destroyed
			or not invite.Visible
			or not bar.Visible
			or not canInvite
			or invitePromptOpen
			or os.clock() - lastRequest < 0.45
		then
			return
		end
		lastRequest = os.clock()
		invitePromptOpen = true
		invitePromptEpoch += 1
		local promptEpoch = invitePromptEpoch
		-- Never leave the button locked if the close signal is not delivered.
		task.delay(15, function()
			if not destroyed and invitePromptEpoch == promptEpoch then
				invitePromptOpen = false
			end
		end)
		local ok = pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		if not destroyed and not ok and invitePromptEpoch == promptEpoch then
			invitePromptOpen = false
			canInvite = false
			gui:SetAttribute("InviteAvailable", false)
		end
	end)
)
table.insert(
	connections,
	SocialService.GameInvitePromptClosed:Connect(function(who)
		if who == player then
			invitePromptOpen = false
		end
	end)
)
refreshInvite(true)
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
		guidePreview.Show(id)
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

-- Reuse authored world labels, leaving queued mobile HUD geometry unchanged.
local function renderPracticeSigns()
	local queued = player:GetAttribute("LobbyOnly") ~= true and player:GetAttribute("EntryChoiceMade") == true
	local warmup = player:GetAttribute("PracticeMode") == "Warmup"
	local running = player:GetAttribute("PracticeState") == "Running"
	local finished = player:GetAttribute("PracticeState") == "Finished"
	local progress = math.clamp(player:GetAttribute("PracticeCheckpoint") or 0, 0, 2)
	practicePrompt.ActionText = if queued
		then "Разминка / заново"
		else "Паркур / заново"
	practicePrompt.ObjectText = if queued
		then "2 ПРЫЖКА · ТЫ В ОЧЕРЕДИ"
		else "ПАРКУР · 7 ТОЧЕК"
	practiceSign.Heading.Text = if queued then "РАЗМИНКА / 02" else "ПАРКУР / 07"
	practiceSign.Detail.Text = if queued
			and warmup
			and finished
		then "Готово! Ты в очереди.\nВход в испытание — автоматически."
		elseif queued and warmup and running then string.format(
			"Разминка %d/2: прыгай 01 → 02.\nТы остаёшься в очереди.",
			progress
		)
		elseif queued then "Два прыжка, пока ждёшь.\nОчередь сохранится."
		else "Пройди все 7 точек.\nСтартуй и побей свой рекорд!"
	warmupFinishLabel.Text = if queued then "02\nГОТОВО" else "02"
end

local function restorePracticeSigns()
	practicePrompt.ActionText = practiceSignDefaults.ActionText
	practicePrompt.ObjectText = practiceSignDefaults.ObjectText
	practiceSign.Heading.Text = practiceSignDefaults.Heading
	practiceSign.Detail.Text = practiceSignDefaults.Detail
	warmupFinishLabel.Text = practiceSignDefaults.Finish
end

local function render()
	renderPracticeSigns()
	local exploring = player:GetAttribute("LobbyOnly") == true
	local inRound = player:GetAttribute("InRound") == true
	local saveView =
		ProfileStatus.describe(player:GetAttribute("DataStatus"), player:GetAttribute("DataPersistent"))
	welcome.Visible = (
		player:GetAttribute("EntryChoiceMade") ~= true
		or player:GetAttribute("TemporaryPlayPrompt") == true
	) and not inRound
	welcome.Heading.Text = saveView.Title
	welcome.Steps.Text = if saveView.Warning then saveView.Body else normalWelcomeSteps
	local profileRetry = retryView()
	if profileRetry.Visible then
		welcome.Steps.Text = if retryAwaiting
			then "Повторно загружаем прогресс. Подожди результата."
			else "Прогресс сейчас не сохранится.\n" .. profileRetry.Hint
	end
	-- Before admission, say what joining a run already in progress means (a save warning keeps priority).
	local lateNotice = PlayerHints.lateEntryNotice(
		roomState:GetAttribute("Phase"),
		roomState:GetAttribute("RuleIndex"),
		config.RuleCount
	)
	welcome.Detail.Text = if saveView.Warning then saveView.Hint else lateNotice or normalWelcomeDetail
	welcome.Play.Text = saveView.PlayText
	if inRound or collectionPanel.Visible or welcome.Visible then
		closeGuide()
	end
	local modal = if welcome.Visible then "Welcome" elseif guide.Visible then "Guide" else ""
	mainGui:SetAttribute("StationModal", modal)
	-- Only the first-entry choice owns a full-screen backdrop; archive controls are local to the panel.
	backdrop.Visible = welcome.Visible
	backdrop.Active = welcome.Visible
	bar.Visible = exploring and not inRound and not collectionPanel.Visible and modal == ""
	mainActions.Visible = modal == "" and mainGui:GetAttribute("CompactPlayHUD") ~= true
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local ready = humanoid ~= nil and humanoid.Health > 0 and not saveView.Loading
	if humanoid and humanoid.Health <= 0 then
		closeGuide()
	end
	local waiting = os.clock() < waitingChoiceUntil or retryAwaiting
	for _, button in { welcome.Play, welcome.Explore } do
		button.Active = ready and not waiting
		button.AutoButtonColor = ready and not waiting
		button.Selectable = ready and not waiting
		button.BackgroundTransparency = if ready and not waiting then 0 else 0.45
	end
	renderRetry(profileRetry, ready and not waiting)
	welcome.Status.Text = if retryAwaiting
		then "Повторно загружаем прогресс…"
		elseif not ready then "Подготавливаем персонажа…"
		elseif waiting then "Подключаем к выбранному режиму…"
		elseif
			requestedChoice
		then "Не удалось войти. Нажми ещё раз, когда персонаж появится в лаборатории."
		elseif saveView.Warning then saveView.Compact
		else saveView.Hint
	if welcome.Visible and not welcomeWasVisible then
		ContextActionService:BindAction("WelcomeExplore", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				send("Explore")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB)
	elseif not welcome.Visible and welcomeWasVisible then
		-- A completed choice must not colour the next opening of this modal as a failure.
		requestedChoice = false
		waitingChoiceUntil = 0
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
			"Твой рекорд паркура: %.2f сек",
			best
		)
		else "Паркур слева · архив правил справа · галерея впереди"
	if saveView.Warning and not running then
		bar.Detail.Text = saveView.Compact
	elseif lateNotice and not running then
		bar.Detail.Text = lateNotice
	end
	bar.Explore.Text = if running
		then "ЗАКОНЧИТЬ ТРЕНИРОВКУ"
		else "СВОБОДНАЯ ПРОГУЛКА"
	-- Lobby only: never during a trial run, a modal or an active parkour attempt.
	if bar.Visible then
		refreshInvite(false)
	end
	invite.Visible = canInvite and bar.Visible and not running
	local thirds = invite.Visible
	bar.Join.Size = UDim2.new(if thirds then 1 / 3 else 0.5, if thirds then -13 else -18, 0, 44)
	bar.Explore.Size = bar.Join.Size
	bar.Explore.Position = UDim2.new(if thirds then 1 / 3 else 0.5, if thirds then 7 else 6, 0, 59)
	bar.Join.NextSelectionLeft = if thirds then invite else bar.Explore
	bar.Explore.NextSelectionRight = if thirds then invite else bar.Join
	invite.NextSelectionLeft = bar.Explore
	invite.NextSelectionRight = bar.Join
	if not invite.Visible and GuiService.SelectedObject == invite then
		GuiService.SelectedObject = if canRestore(bar.Join) then bar.Join else nil
	end
	local height = mainGui.Root.AbsoluteSize.Y
	local guideWidth, guideHeight =
		GuidePreview.bounds(mainGui.Root.AbsoluteSize.X, height, UserInputService.TouchEnabled)
	guide.Size = UDim2.fromOffset(guideWidth, guideHeight)
	guide.AnchorPoint = Vector2.new(0.5, 0)
	guide.Position = UDim2.new(0.5, 0, 0, 8)
	layoutWelcome(height)
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
	destroyed = true
	restorePracticeSigns()
	invitePromptEpoch += 1
	closeGuide()
	guidePreview.Destroy()
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
