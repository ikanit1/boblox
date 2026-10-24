--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("StationHUD") :: ScreenGui
local bar = gui:WaitForChild("StationBar") :: Frame
local guide = gui:WaitForChild("Guide") :: Frame
local toggle = gui:WaitForChild("ExploreToggle") :: TextButton
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
guide.SelectionGroup = true
guide.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
guide.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
guide.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
guide.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

local function closeGuide()
	guide.Visible = false
	ContextActionService:UnbindAction("CloseStationGuide")
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(guide) then
		GuiService.SelectedObject = if previousSelection
				and previousSelection:IsDescendantOf(player.PlayerGui)
			then previousSelection
			else nil
	end
	previousSelection = nil
end
local function send(action: string)
	if os.clock() - lastRequest < 0.45 then
		return
	end
	lastRequest = os.clock()
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
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who and who ~= player then
			return
		end
		if player:GetAttribute("InRound") == true then
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
	bar.Visible = exploring and not inRound and not collectionPanel.Visible and not guide.Visible
	mainActions.Visible = not guide.Visible
	local character = player.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local inLobby = rootPart and rootPart:IsA("BasePart") and rootPart.Position.Z > 43
	toggle.Visible = not exploring
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
	elseif motionReplaced then
		motionReplaced = false
		mainActions.Motion.Visible = not (
			mainGui.Root.AbsoluteSize.Y < 330 and mainGui.Root.SpectateNext.Visible
		)
		mainActions.Collection.NextSelectionRight = mainActions.Motion
		mainActions.Audio.NextSelectionLeft = mainActions.Motion
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
	local view = Workspace.CurrentCamera
	local height = if view then view.ViewportSize.Y else 720
	guide.Size = UDim2.new(1, -24, 0, math.min(320, math.max(180, height - 80)))
end
table.insert(connections, player.AttributeChanged:Connect(render))
table.insert(
	connections,
	player:GetAttributeChangedSignal("LobbyOnly"):Connect(function()
		if
			player:GetAttribute("LobbyOnly") == true
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
	for _, connection in connections do
		connection:Disconnect()
	end
	for _, entry in decorations do
		if entry.part.Parent then
			entry.part.CFrame = entry.origin
		end
	end
end)
