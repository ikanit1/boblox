--!strict
-- Minimal preview-only status; Roblox movement, jump and camera controls remain untouched.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local state = game:GetService("ReplicatedStorage"):WaitForChild("PrototypeState")
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "PrototypeStatus", false
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Size, label.Position = UDim2.new(0.86, 0, 0, 76), UDim2.new(0.07, 0, 0, 4)
label.BackgroundColor3, label.BackgroundTransparency = Color3.fromRGB(20, 35, 50), 0.12
label.TextColor3, label.TextSize = Color3.fromRGB(245, 245, 250), 14
label.TextWrapped, label.Font = true, Enum.Font.GothamMedium
label.Parent = gui
local elapsed = 0
local connection = RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.1 then
		return
	end
	elapsed = 0
	local deadline = state:GetAttribute("EndsAt")
	local seconds = if type(deadline) == "number"
		then math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		else 0
	local stage = state:GetAttribute("Stage")
	local title = if stage == "Warning"
		then "ПОДГОТОВЬСЯ"
		elseif stage == "Active" then "ДЕЙСТВУЙ"
		elseif stage == "Recovery" then "ПЕРЕДЫШКА"
		else "ПРОТОТИП · НЕ РЕЛИЗ"
	label.Text = title
		.. (if seconds > 0 then " · " .. seconds .. "с" else "")
		.. "\n"
		.. tostring(state:GetAttribute("Instruction") or "")
	if player:GetAttribute("PrototypeOutcome") == "Failed" then
		label.Text ..= "\nТЫ ВЫБЫЛ · попробуй снова после опыта"
	end
end)
script.Destroying:Connect(function()
	connection:Disconnect()
	gui:Destroy()
end)
