--!strict
-- Local, bounded visual effects. Neither trails nor the spectator camera affect gameplay.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local CharacterPresentation = {}

function CharacterPresentation.new(localPlayer: Player, economy: any, nextButton: TextButton)
	local connections: { RBXScriptConnection } = {}
	local watched: { [Player]: { RBXScriptConnection } } = {}
	local effects: { [Player]: { Instance } } = {}
	local titleEffects: { [Player]: BillboardGui } = {}
	local deathConnections: { [Player]: RBXScriptConnection } = {}
	local removingCharacters: { [Player]: Model } = {}
	local friends: { [Player]: boolean } = {}
	local friendQueue: { Player } = {}
	local friendRequests = 0
	local picker: Frame? = nil
	local pickerList: ScrollingFrame? = nil
	local pickerClose: TextButton? = nil
	local pickerRows: { TextButton } = {}
	local pickerPlayers: { Player } = {}
	local pickerOpen = false
	local refreshCamera: () -> ()
	local trailStyles: { [string]: any } = {}
	local titles: { [string]: string } = {}
	local phase = "Waiting"
	local reducedMotion = false
	local spectateSuspended = false
	local target: Player? = nil
	local destroyed = false
	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end
	local function displayName(player: Player): string
		local text = player.DisplayName:gsub("%c", "")
		local length = utf8.len(text)
		if not length or length == 0 then
			return "Игрок"
		end
		if length > 24 then
			text = string.sub(text, 1, (utf8.offset(text, 25) :: number) - 1)
		end
		return text
	end
	local function closePicker(restoreSelection: boolean?)
		pickerOpen = false
		if picker then
			picker.Visible = false
		end
		if ContextActionService then
			ContextActionService:UnbindAction("RuleRoomSpectatorPicker")
		end
		if picker and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(picker) then
			GuiService.SelectedObject = if restoreSelection and nextButton.Visible then nextButton else nil
		end
	end
	for _, item in economy.Trails do
		trailStyles[item.Id] = item
	end
	for _, milestone in economy.MasteryMilestones or {} do
		titles[milestone.Id] = milestone.Title
	end

	local function clearTitle(player: Player)
		local title = titleEffects[player]
		if title then
			title:Destroy()
			titleEffects[player] = nil
		end
	end

	local function refreshTitle(player: Player)
		clearTitle(player)
		if destroyed or phase == "Rule" or phase == "Break" or player:GetAttribute("InRound") == true then
			return
		end
		local id = player:GetAttribute("EquippedTitle")
		if
			typeof(id) ~= "string"
			or not titles[id]
			or player:GetAttribute("UnlockedTitle_" .. id) ~= true
		then
			return
		end
		local character = player.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			return
		end
		local status = player:GetAttribute("DataStatus")
		if status == nil or status == "Loading" then
			return
		end
		local temporary = player:GetAttribute("DataPersistent") == false
			or status == "Session"
			or status == "Busy"
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "RuleRoomMasteryTitle"
		billboard.Adornee = rootPart
		billboard.Size = UDim2.fromOffset(232, 24)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
		billboard.MaxDistance = 45
		billboard.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 13
		label.TextColor3 = Color3.fromRGB(255, 213, 79)
		label.TextStrokeTransparency = 0.4
		label.RichText = false
		-- Never display arbitrary attribute text above an avatar.
		label.Text = titles[id] .. if temporary then " · временно" else ""
		label.Parent = billboard
		billboard.Parent = rootPart
		titleEffects[player] = billboard
	end

	local function clearTrail(player: Player)
		for _, instance in effects[player] or {} do
			instance:Destroy()
		end
		effects[player] = nil
	end

	local function refreshTrail(player: Player)
		if destroyed then
			return
		end
		clearTrail(player)
		local id = player:GetAttribute("EquippedTrail")
		if reducedMotion or typeof(id) ~= "string" or id == "None" or not trailStyles[id] then
			return
		end
		local style = trailStyles[id]
		local character = player.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not rootPart or not rootPart:IsA("BasePart") then
			return
		end
		local left = Instance.new("Attachment")
		left.Name = "RuleRoomTrailLeft"
		left.Position = Vector3.new(-0.55, -0.7, 0.5)
		left.Parent = rootPart
		local right = Instance.new("Attachment")
		right.Name = "RuleRoomTrailRight"
		right.Position = Vector3.new(0.55, -0.7, 0.5)
		right.Parent = rootPart
		local trail = Instance.new("Trail")
		trail.Name = "RuleRoomCosmeticTrail"
		trail.Attachment0 = left
		trail.Attachment1 = right
		trail.Color = ColorSequence.new(style.Color, style.ColorEnd or style.Color)
		trail.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new(style.WidthScale or 0.65, 0)
		trail.Lifetime = style.Lifetime or 0.28
		trail.MinLength = 0.12
		trail.FaceCamera = true
		trail.LightEmission = 0.35
		trail.Parent = rootPart
		effects[player] = { trail, left, right }
	end

	local function humanoidFor(player: Player): Humanoid?
		local character = player.Character
		return if character and removingCharacters[player] ~= character
			then character:FindFirstChildOfClass("Humanoid")
			else nil
	end

	local function eligible(): { Player }
		local candidates = {}
		for _, player in Players:GetPlayers() do
			local humanoid = humanoidFor(player)
			if
				player ~= localPlayer
				and watched[player] ~= nil
				and player:GetAttribute("InRound") == true
				and humanoid
				and humanoid.Health > 0
			then
				table.insert(candidates, player)
			end
		end
		table.sort(candidates, function(a, b)
			if (friends[a] == true) ~= (friends[b] == true) then
				return friends[a] == true
			end
			return a.UserId < b.UserId
		end)
		return candidates
	end

	local function layoutPicker()
		if not picker or not pickerList or not pickerClose then
			return
		end
		local parent = nextButton.Parent :: GuiObject
		local available = parent.AbsoluteSize
		local width = math.max(120, math.min(296, available.X - 24))
		local height = math.min(188, math.max(88, available.Y - 120))
		local buttonAt = nextButton.AbsolutePosition - parent.AbsolutePosition
		local proposedY = buttonAt.Y + nextButton.AbsoluteSize.Y + 4
		local bottom = math.max(12, available.Y - height - 96)
		if proposedY > bottom then
			proposedY = buttonAt.Y - height - 4
		end
		picker.Size = UDim2.fromOffset(width, height)
		picker.Position = UDim2.fromOffset(
			math.clamp(
				buttonAt.X + nextButton.AbsoluteSize.X / 2 - width / 2,
				12,
				math.max(12, available.X - width - 12)
			),
			math.clamp(proposedY, 12, bottom)
		)
		pickerList.CanvasSize = UDim2.fromOffset(0, #pickerPlayers * 48)
		for index, button in pickerRows do
			local candidate = pickerPlayers[index]
			button.Visible = candidate ~= nil
			button.Selectable = pickerOpen and candidate ~= nil
			if candidate then
				button.Text = (if candidate == target then "✓ " else "")
					.. displayName(candidate)
					.. (if friends[candidate] == true then " · ДРУГ" else "")
			end
			button.NextSelectionUp = if index == 1 then pickerClose else pickerRows[index - 1]
			button.NextSelectionDown = if index < #pickerPlayers then pickerRows[index + 1] else pickerClose
			button.NextSelectionLeft, button.NextSelectionRight = button, button
		end
		pickerClose.NextSelectionDown = if #pickerPlayers > 0 then pickerRows[1] else pickerClose
		pickerClose.NextSelectionUp = if #pickerPlayers > 0 then pickerRows[#pickerPlayers] else pickerClose
		if
			GuiService.SelectedObject
			and GuiService.SelectedObject:IsDescendantOf(picker)
			and not GuiService.SelectedObject.Selectable
		then
			GuiService.SelectedObject = pickerClose
		end
	end

	local function focusPicker()
		local parent = nextButton.Parent :: GuiObject?
		if
			destroyed
			or not pickerOpen
			or not picker
			or not picker.Visible
			or not parent
			or not parent.Visible
			or not nextButton.Visible
			or phase ~= "Rule"
			or localPlayer:GetAttribute("InRound") == true
			or localPlayer:GetAttribute("Eliminated") ~= true
			or GuiService.MenuIsOpen
			or not string.find(UserInputService:GetLastInputType().Name, "Gamepad")
		then
			return
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(picker) and selected.Visible and selected.Selectable then
			return
		end
		GuiService.SelectedObject = if #pickerPlayers > 0 then pickerRows[1] else pickerClose
	end

	local function ensurePicker()
		if picker then
			return
		end
		local frame = Instance.new("Frame")
		frame.Name = "SpectatorPicker"
		frame.BackgroundColor3 = Color3.fromRGB(18, 30, 50)
		frame.BorderSizePixel = 0
		frame.ZIndex = 20
		frame.Visible = false
		frame.SelectionGroup = true
		frame.SelectionBehaviorUp, frame.SelectionBehaviorDown =
			Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
		frame.SelectionBehaviorLeft, frame.SelectionBehaviorRight =
			Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
		frame.Parent = nextButton.Parent
		picker = frame
		local function button(name: string, parent: Instance): TextButton
			local result = Instance.new("TextButton")
			result.Name = name
			result.Size = UDim2.new(1, -8, 0, 44)
			result.BackgroundColor3 = Color3.fromRGB(39, 56, 78)
			result.TextColor3 = Color3.fromRGB(239, 246, 255)
			result.Font = Enum.Font.GothamMedium
			result.TextSize = 13
			result.TextWrapped = true
			result.RichText = false
			result.ZIndex = 22
			result.Parent = parent
			return result
		end
		local heading = Instance.new("TextLabel")
		heading.Name = "Heading"
		heading.BackgroundTransparency = 1
		heading.Size = UDim2.new(1, -56, 0, 44)
		heading.Position = UDim2.fromOffset(8, 0)
		heading.Text = "КОГО СМОТРИМ"
		heading.Font = Enum.Font.GothamMedium
		heading.TextSize = 14
		heading.TextColor3 = Color3.fromRGB(239, 246, 255)
		heading.ZIndex = 22
		heading.Parent = frame
		local close = button("Close", frame)
		close.Text = "✕"
		close.Size = UDim2.fromOffset(44, 44)
		close.Position = UDim2.new(1, -44, 0, 0)
		pickerClose = close
		local list = Instance.new("ScrollingFrame")
		list.Name = "Players"
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.Size = UDim2.new(1, -8, 1, -48)
		list.Position = UDim2.fromOffset(4, 44)
		list.ScrollBarThickness = 4
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ZIndex = 21
		list.Parent = frame
		pickerList = list
		connect(close.Activated, function()
			closePicker(true)
		end)
		for index = 1, 12 do
			local row = button("Player" .. index, list)
			row.Position = UDim2.fromOffset(0, (index - 1) * 48)
			pickerRows[index] = row
			connect(row.Activated, function()
				local candidate = pickerPlayers[index]
				if not pickerOpen or not candidate or not table.find(eligible(), candidate) then
					return
				end
				target, spectateSuspended = candidate, false
				closePicker(true)
				refreshCamera()
			end)
			connect(row.SelectionGained, function()
				if not pickerOpen then
					return
				end
				list.CanvasPosition = Vector2.new(0, math.max(0, (index - 1) * 48 - 4))
			end)
		end
		connect((nextButton.Parent :: GuiObject):GetPropertyChangedSignal("AbsoluteSize"), layoutPicker)
		connect(nextButton:GetPropertyChangedSignal("AbsolutePosition"), layoutPicker)
		connect(nextButton:GetPropertyChangedSignal("Visible"), function()
			if not nextButton.Visible then
				closePicker(false)
			end
		end)
		connect((nextButton.Parent :: GuiObject):GetPropertyChangedSignal("Visible"), function()
			if not (nextButton.Parent :: GuiObject).Visible then
				closePicker(false)
			end
		end)
		connect(UserInputService.LastInputTypeChanged, focusPicker)
		connect(GuiService:GetPropertyChangedSignal("MenuIsOpen"), focusPicker)
	end

	refreshCamera = function()
		if destroyed then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			target = nil
			nextButton.Visible = false
			closePicker(false)
			return
		end
		local eliminated = phase == "Rule"
			and localPlayer:GetAttribute("Eliminated") == true
			and localPlayer:GetAttribute("InRound") ~= true
		local candidates = if eliminated then eligible() else {}
		if #candidates > 0 and not spectateSuspended then
			local current = if target then table.find(candidates, target) else nil
			local index = if current then current else 1
			target = candidates[index]
			local humanoid = humanoidFor(candidates[index])
			if humanoid then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = humanoid
			end
			nextButton.RichText = false
			nextButton.Text = "СМОТРИМ: "
				.. displayName(candidates[index])
				.. (if friends[candidates[index]] == true then " · ДРУГ" else "")
				.. " ▾"
			nextButton.Visible = true
		else
			target = nil
			nextButton.Visible = eliminated and #candidates > 0
			nextButton.Text = "НАБЛЮДАТЬ ЗА ИГРОКАМИ →"
			local ownHumanoid = humanoidFor(localPlayer)
			if ownHumanoid then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = ownHumanoid
			end
		end
		if not eliminated or #candidates == 0 or spectateSuspended then
			closePicker(false)
		end
		if pickerOpen then
			-- A late friendship result may update a badge, never move a row under a tap.
			local stable: { Player } = {}
			for _, candidate in pickerPlayers do
				if table.find(candidates, candidate) then
					table.insert(stable, candidate)
				end
			end
			for _, candidate in candidates do
				if not table.find(stable, candidate) then
					table.insert(stable, candidate)
				end
			end
			pickerPlayers = stable
		else
			pickerPlayers = candidates
		end
		while #pickerPlayers > 12 do
			table.remove(pickerPlayers)
		end
		layoutPicker()
		if not nextButton.Visible and GuiService.SelectedObject == nextButton then
			GuiService.SelectedObject = nil
		end
	end

	local function pumpFriends()
		while not destroyed and friendRequests < 2 and #friendQueue > 0 do
			local candidate = table.remove(friendQueue, 1)
			local scope = watched[candidate]
			if not scope then
				continue
			end
			friendRequests += 1
			task.spawn(function()
				if destroyed or watched[candidate] ~= scope then
					friendRequests -= 1
					pumpFriends()
					return
				end
				local ok, result = pcall(function()
					return localPlayer:IsFriendsWithAsync(candidate.UserId)
				end)
				friendRequests -= 1
				if not destroyed and watched[candidate] == scope then
					friends[candidate] = ok and result == true
					refreshCamera()
				end
				pumpFriends()
			end)
		end
	end

	local function watch(player: Player)
		if destroyed or watched[player] then
			return
		end
		local list: { RBXScriptConnection } = {}
		watched[player] = list
		local function onCharacter(character: Model)
			removingCharacters[player] = nil
			clearTrail(player)
			clearTitle(player)
			if deathConnections[player] then
				deathConnections[player]:Disconnect()
				deathConnections[player] = nil
			end
			task.spawn(function()
				local humanoid = character:WaitForChild("Humanoid", 10)
				character:WaitForChild("HumanoidRootPart", 10)
				if not destroyed and player.Character == character and watched[player] == list then
					if player == localPlayer then
						-- Respawn restores the lobby character's camera; the button resumes spectating.
						spectateSuspended = player:GetAttribute("Eliminated") == true
					end
					refreshTrail(player)
					refreshTitle(player)
					refreshCamera()
					if humanoid and humanoid:IsA("Humanoid") then
						deathConnections[player] = humanoid.Died:Once(function()
							if player.Character ~= character or watched[player] ~= list then
								return
							end
							if player == localPlayer then
								closePicker(false)
							end
							clearTitle(player)
							refreshCamera()
						end)
					end
				end
			end)
		end
		table.insert(list, player.CharacterAdded:Connect(onCharacter))
		table.insert(
			list,
			player.CharacterRemoving:Connect(function(character)
				if player.Character and player.Character ~= character then
					return
				end
				removingCharacters[player] = character
				if player == localPlayer then
					closePicker(false)
				end
				if deathConnections[player] then
					deathConnections[player]:Disconnect()
					deathConnections[player] = nil
				end
				clearTitle(player)
				clearTrail(player)
				refreshCamera()
			end)
		)
		for _, name in { "EquippedTitle", "DataStatus", "DataPersistent" } do
			table.insert(
				list,
				player:GetAttributeChangedSignal(name):Connect(function()
					refreshTitle(player)
				end)
			)
		end
		for id in titles do
			table.insert(
				list,
				player:GetAttributeChangedSignal("UnlockedTitle_" .. id):Connect(function()
					refreshTitle(player)
				end)
			)
		end
		table.insert(
			list,
			player:GetAttributeChangedSignal("EquippedTrail"):Connect(function()
				refreshTrail(player)
			end)
		)
		table.insert(
			list,
			player:GetAttributeChangedSignal("InRound"):Connect(function()
				refreshTitle(player)
				refreshCamera()
			end)
		)
		table.insert(
			list,
			player:GetAttributeChangedSignal("Eliminated"):Connect(function()
				if player == localPlayer then
					spectateSuspended = false
				end
				refreshCamera()
			end)
		)
		if player.Character then
			onCharacter(player.Character)
		end
		if player ~= localPlayer and player.UserId > 0 and #friendQueue < 12 then
			table.insert(friendQueue, player)
			pumpFriends()
		end
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			if deathConnections[player] then
				deathConnections[player]:Disconnect()
				deathConnections[player] = nil
			end
			for _, connection in watched[player] or {} do
				connection:Disconnect()
			end
			watched[player] = nil
			friends[player] = nil
			removingCharacters[player] = nil
			local queued = table.find(friendQueue, player)
			if queued then
				table.remove(friendQueue, queued)
			end
			clearTrail(player)
			clearTitle(player)
			task.defer(refreshCamera)
		end)
	)
	table.insert(
		connections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			refreshCamera()
		end)
	)
	table.insert(
		connections,
		nextButton.Activated:Connect(function()
			if
				destroyed
				or not nextButton.Visible
				or phase ~= "Rule"
				or localPlayer:GetAttribute("InRound") == true
			then
				return
			end
			if pickerOpen then
				closePicker(true)
				return
			end
			spectateSuspended = false
			refreshCamera()
			if #pickerPlayers == 0 then
				return
			end
			ensurePicker()
			pickerOpen = true
			(picker :: Frame).Visible = true
			(pickerList :: ScrollingFrame).CanvasPosition = Vector2.zero
			layoutPicker()
			ContextActionService:BindAction("RuleRoomSpectatorPicker", function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					closePicker(true)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
			focusPicker()
		end)
	)
	return {
		SetPhase = function(value: string)
			phase = value
			if phase ~= "Rule" then
				spectateSuspended = false
			end
			refreshCamera()
			for player in watched do
				refreshTitle(player)
			end
		end,
		SetReducedMotion = function(value: boolean)
			reducedMotion = value
			for _, player in Players:GetPlayers() do
				refreshTrail(player)
			end
		end,
		Destroy = function()
			if destroyed then
				return
			end
			phase = "Waiting"
			refreshCamera()
			destroyed = true
			closePicker(false)
			table.clear(friendQueue)
			for _, connection in deathConnections do
				connection:Disconnect()
			end
			table.clear(deathConnections)
			for _, connection in connections do
				connection:Disconnect()
			end
			for player, list in watched do
				for _, connection in list do
					connection:Disconnect()
				end
				clearTrail(player)
				clearTitle(player)
			end
			table.clear(watched)
			table.clear(friends)
			if picker then
				picker:Destroy()
			end
		end,
	}
end

return CharacterPresentation
