--!strict
-- Event-driven cosmetic reactor, with no camera/input hooks or per-frame lighting work.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local Display = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("RoomDisplay"))
local Themes = require(ReplicatedStorage.RuleRoomShared:WaitForChild("RoomThemes"))
local arena = workspace:WaitForChild("Arena", 20)
local lobby = arena and arena:WaitForChild("Lobby", 20)
local reactor = lobby and lobby:WaitForChild("ReactorExhibit", 20)
local board = reactor and reactor:WaitForChild("StatusBoard", 10)
if not reactor or not board then
	return
end
local surface = board:FindFirstChild("Display")
local heading = surface and surface:FindFirstChild("Heading")
local detail = surface and surface:FindFirstChild("Detail")
if not heading or not heading:IsA("TextLabel") or not detail or not detail:IsA("TextLabel") then
	return
end
local segments: { BasePart } = {}
for index = 1, 6 do
	local segment = reactor:FindFirstChild("Progress" .. index)
	if segment and segment:IsA("BasePart") then
		table.insert(segments, segment)
	end
end
local themeParts: { BasePart } = {}
local atmosphere = arena:FindFirstChild("Atmosphere")
if atmosphere then
	for _, object in atmosphere:GetDescendants() do
		if object:IsA("BasePart") and #themeParts < 80 then
			table.insert(themeParts, object)
		end
	end
end
local themeId = ""
local stopped, pending = false, false
local function render()
	local round = state:GetAttribute("Round")
	local nextTheme = Themes.id(round)
	if nextTheme ~= themeId then
		themeId = nextTheme
		for _, part in themeParts do
			local rgb, transparency = Themes.style(round, part:GetAttribute("ThemeRole"))
			if rgb and transparency and part.Parent then
				part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
				part.Transparency = transparency
			end
		end
	end
	local data = Display.snapshot(function(name)
		return state:GetAttribute(name)
	end)
	heading.Text = data.Heading
	detail.Text = data.Detail
	for index, segment in segments do
		segment.Color = if data.Charged then Color3.fromRGB(255, 213, 79) else Color3.fromRGB(80, 225, 255)
		segment.Transparency = if index <= data.Lit then 0.08 else 0.75
	end
end
local connection = state.AttributeChanged:Connect(function()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		if not stopped then
			render()
		end
	end)
end)
script.Destroying:Connect(function()
	stopped = true
	connection:Disconnect()
end)
render()
