--!strict
-- Local, bounded visual effects. Neither trails nor the spectator camera affect gameplay.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local CharacterPresentation = {}

function CharacterPresentation.new(localPlayer: Player, economy: any, nextButton: TextButton)
	local connections: { RBXScriptConnection } = {}
	local watched: { [Player]: { RBXScriptConnection } } = {}
	local effects: { [Player]: { Instance } } = {}
	local deathConnections: { [Player]: RBXScriptConnection } = {}
	local colors: { [string]: Color3 } = {}
	local phase = "Waiting"
	local reducedMotion = false
	local spectateSuspended = false
	local target: Player? = nil
	local destroyed = false
	for _, item in economy.Trails do
		colors[item.Id] = item.Color
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
		if reducedMotion or typeof(id) ~= "string" or id == "None" or not colors[id] then
			return
		end
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
		trail.Color = ColorSequence.new(colors[id])
		trail.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new(0.65, 0)
		trail.Lifetime = 0.28
		trail.MinLength = 0.12
		trail.FaceCamera = true
		trail.LightEmission = 0.35
		trail.Parent = rootPart
		effects[player] = { trail, left, right }
	end

	local function humanoidFor(player: Player): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end

	local function eligible(): { Player }
		local candidates = {}
		for _, player in Players:GetPlayers() do
			local humanoid = humanoidFor(player)
			if
				player ~= localPlayer
				and player:GetAttribute("InRound") == true
				and humanoid
				and humanoid.Health > 0
			then
				table.insert(candidates, player)
			end
		end
		table.sort(candidates, function(a, b)
			return a.UserId < b.UserId
		end)
		return candidates
	end

	local function refreshCamera(cycle: boolean?)
		if destroyed then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eliminated = phase == "Rule" and localPlayer:GetAttribute("Eliminated") == true
		local candidates = if eliminated then eligible() else {}
		if #candidates > 0 and not spectateSuspended then
			local current = if target then table.find(candidates, target) else nil
			local index = if current then current else 1
			if cycle and current then
				index = current % #candidates + 1
			end
			target = candidates[index]
			local humanoid = humanoidFor(candidates[index])
			if humanoid then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = humanoid
			end
			nextButton.Text = "СМОТРИМ: " .. candidates[index].DisplayName .. "  →"
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
		if not nextButton.Visible and GuiService.SelectedObject == nextButton then
			GuiService.SelectedObject = nil
		end
	end

	local function watch(player: Player)
		local list: { RBXScriptConnection } = {}
		watched[player] = list
		local function onCharacter(character: Model)
			clearTrail(player)
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
					refreshCamera()
					if humanoid and humanoid:IsA("Humanoid") then
						deathConnections[player] = humanoid.Died:Once(function()
							refreshCamera()
						end)
					end
				end
			end)
		end
		table.insert(list, player.CharacterAdded:Connect(onCharacter))
		table.insert(
			list,
			player:GetAttributeChangedSignal("EquippedTrail"):Connect(function()
				refreshTrail(player)
			end)
		)
		table.insert(
			list,
			player:GetAttributeChangedSignal("InRound"):Connect(function()
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
			clearTrail(player)
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
			spectateSuspended = false
			refreshCamera(true)
		end)
	)
	return {
		SetPhase = function(value: string)
			phase = value
			if phase ~= "Rule" then
				spectateSuspended = false
			end
			refreshCamera()
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
			end
			table.clear(watched)
		end,
	}
end

return CharacterPresentation
