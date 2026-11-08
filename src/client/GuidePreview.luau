--!strict
-- A bounded 2D teaching diagram inside the archive. It never touches world/input/camera state.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Presentation =
	require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GuidePresentation"))
local GuidePreview = { bounds = Presentation.bounds }
local palette = {
	Floor = Color3.fromRGB(48, 65, 85),
	Void = Color3.fromRGB(18, 30, 50),
	Player = Color3.fromRGB(246, 248, 255),
	Safe = Color3.fromRGB(66, 220, 169),
	Warn = Color3.fromRGB(255, 213, 79),
	Danger = Color3.fromRGB(255, 106, 117),
	Blue = Color3.fromRGB(70, 168, 244),
	Pink = Color3.fromRGB(255, 115, 173),
	Yellow = Color3.fromRGB(255, 213, 79),
	Green = Color3.fromRGB(66, 220, 169),
	Gold = Color3.fromRGB(255, 213, 79),
}

function GuidePreview.new(guide: Frame, motionSource: Instance)
	local originalBody = guide:WaitForChild("Body") :: TextLabel
	local close = guide:WaitForChild("Close") :: TextButton
	local defaults = {
		BodyVisible = originalBody.Visible,
		CloseSize = close.Size,
		ClosePosition = close.Position,
		CloseAnchor = close.AnchorPoint,
	}
	local connections: { RBXScriptConnection } = {}
	local heartbeat: RBXScriptConnection? = nil
	local activeId: string? = nil
	local elapsed, manualStep = 0, 1
	local destroyed = false
	local content = Instance.new("ScrollingFrame")
	content.Name = "GuideDemonstration"
	content.Position = UDim2.fromOffset(12, 52)
	content.Size = UDim2.new(1, -24, 1, -112)
	content.CanvasSize = UDim2.fromOffset(0, 208)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Selectable = true
	content.Visible = false
	content.ClipsDescendants = true
	content.Parent = guide
	local function label(name: string, parent: Instance): TextLabel
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.TextColor3 = palette.Player
		item.Font = Enum.Font.GothamMedium
		item.TextSize = 13
		item.TextWrapped = true
		item.RichText = false
		item.Parent = parent
		return item
	end
	local heading = label("Step", content)
	heading.Position = UDim2.fromOffset(0, 0)
	heading.Size = UDim2.new(1, -8, 0, 26)
	local diagram = Instance.new("Frame")
	diagram.Name = "Diagram"
	diagram.Position = UDim2.fromOffset(0, 30)
	diagram.Size = UDim2.new(1, -8, 0, 96)
	diagram.BackgroundColor3 = palette.Void
	diagram.ClipsDescendants = true
	diagram.Parent = content
	local shapes: { TextLabel } = {}
	for index = 1, Presentation.MaxShapes do
		local shape = label("Shape" .. index, diagram)
		shape.BackgroundTransparency = 0
		shape.TextColor3 = palette.Void
		shape.TextScaled = true
		shape.Font = Enum.Font.GothamBold
		shape.Visible = false
		shape.ZIndex = 2
		table.insert(shapes, shape)
	end
	local tip = label("Tip", content)
	tip.Position = UDim2.fromOffset(0, 130)
	tip.Size = UDim2.new(1, -8, 0, 76)
	local replay = Instance.new("TextButton")
	replay.Name = "ReplayGuide"
	replay.AnchorPoint = Vector2.zero
	replay.Position = UDim2.new(0.5, 4, 1, -52)
	replay.Size = UDim2.new(0.5, -16, 0, 44)
	replay.BackgroundColor3 = Color3.fromRGB(39, 71, 96)
	replay.TextColor3 = palette.Player
	replay.Font = Enum.Font.GothamBold
	replay.TextSize = 13
	replay.TextWrapped = true
	replay.RichText = false
	replay.Selectable = true
	replay.Visible = false
	replay.Parent = guide
	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end
	local function stop()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end
	local function reduced(): boolean
		return motionSource:GetAttribute("ReducedMotion") == true
	end
	local function render()
		local snapshot = if activeId
			then Presentation.snapshot(activeId, elapsed, reduced(), manualStep)
			else nil
		if not snapshot then
			return
		end
		heading.Text = string.format("СХЕМА %d/3 · НЕ ИСПЫТАНИЕ", snapshot.Stage)
		tip.Text = snapshot.Command .. "\n" .. snapshot.Tip
		replay.Text = if reduced()
			then (if manualStep == 3 then "СНАЧАЛА" else "СЛЕДУЮЩИЙ ШАГ")
			else "ЕЩЁ РАЗ · 10 С"
		for index, object in shapes do
			local data = snapshot.Shapes[index]
			object.Visible = data ~= nil
			if data then
				object.Position = UDim2.fromScale(data.X, data.Y)
				object.Size = UDim2.fromScale(data.Width, data.Height)
				object.BackgroundColor3 = palette[data.Tone] or palette.Floor
				object.TextColor3 = if data.Tone == "Void" then palette.Player else palette.Void
				object.Text = data.Text
				object.Rotation = data.Angle
				object.ZIndex = if data.Tone == "Player" then 4 else 2
			end
		end
	end
	local function resume()
		stop()
		if
			destroyed
			or not activeId
			or not guide.Visible
			or reduced()
			or elapsed >= Presentation.Duration
		then
			return
		end
		local pending = 0
		heartbeat = RunService.Heartbeat:Connect(function(delta)
			if destroyed or not activeId or not guide.Visible then
				stop()
				return
			end
			elapsed = math.min(Presentation.Duration, elapsed + math.max(0, delta))
			pending += delta
			if pending >= 0.1 or elapsed >= Presentation.Duration then
				pending = 0
				render()
			end
			if elapsed >= Presentation.Duration then
				stop()
			end
		end)
	end
	local function hide()
		stop()
		activeId = nil
		content.Visible, replay.Visible = false, false
		originalBody.Visible = defaults.BodyVisible
		close.Size, close.Position, close.AnchorPoint =
			defaults.CloseSize, defaults.ClosePosition, defaults.CloseAnchor
		close.NextSelectionLeft, close.NextSelectionRight = close, close
		close.NextSelectionUp, close.NextSelectionDown = close, close
	end
	connect(replay.Activated, function()
		if destroyed or not activeId or not guide.Visible then
			return
		end
		if reduced() then
			manualStep = manualStep % 3 + 1
		else
			elapsed = 0
		end
		content.CanvasPosition = Vector2.zero
		render()
		resume()
	end)
	connect(guide:GetPropertyChangedSignal("Visible"), function()
		if not guide.Visible then
			hide()
		end
	end)
	connect(motionSource:GetAttributeChangedSignal("ReducedMotion"), function()
		if activeId then
			render()
			resume()
		end
	end)
	return {
		Show = function(ruleId: string): boolean
			if destroyed or not Presentation.snapshot(ruleId, 0, true, 1) then
				return false
			end
			activeId, elapsed, manualStep = ruleId, 0, 1
			originalBody.Visible = false
			content.Visible, replay.Visible = true, true
			content.CanvasPosition = Vector2.zero
			close.AnchorPoint = Vector2.zero
			close.Position, close.Size = UDim2.new(0, 12, 1, -52), UDim2.new(0.5, -16, 0, 44)
			close.NextSelectionLeft, close.NextSelectionRight = replay, replay
			close.NextSelectionUp, close.NextSelectionDown = content, content
			replay.NextSelectionLeft, replay.NextSelectionRight = close, close
			replay.NextSelectionUp, replay.NextSelectionDown = content, content
			content.NextSelectionUp, content.NextSelectionDown = close, replay
			render()
			resume()
			return true
		end,
		Hide = hide,
		Destroy = function()
			if destroyed then
				return
			end
			hide()
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			content:Destroy()
			replay:Destroy()
		end,
	}
end

return GuidePreview
