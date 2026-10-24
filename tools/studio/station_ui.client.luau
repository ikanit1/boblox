-- Native Studio-only UI probe; not mapped into the game. One VirtualInput owner.
assert(game:GetService("RunService"):IsStudio(), "Studio-only UI probe")
local p = game.Players.LocalPlayer
local gui = p:WaitForChild("PlayerGui"):WaitForChild("StationHUD")
local input = game:GetService("UserInputService"):CreateVirtualInput()
assert(input, "VirtualInput unavailable")
local output = Instance.new("StringValue")
output.Name = "Result"
output.Parent = script
local busy = false
script:GetAttributeChangedSignal("Command"):Connect(function()
	if busy then
		return
	end
	busy = true
	local cmd = script:GetAttribute("Command")
	local count = 0
	local observed
	local ok, err = pcall(function()
		local button = if cmd == "Explore"
			then gui.ExploreToggle
			elseif cmd == "Join" then gui.StationBar.Join
			else gui.Guide.Close
		assert(button.Visible, "Target button is hidden")
		observed = button.Activated:Connect(function()
			count += 1
		end)
		local point = button.AbsolutePosition
			+ button.AbsoluteSize / 2
			+ game:GetService("GuiService"):GetGuiInset()
		input:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
		task.wait(0.12)
		input:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
		task.wait(0.5)
	end)
	if observed then
		observed:Disconnect()
	end
	output.Value = game:GetService("HttpService"):JSONEncode({
		command = cmd,
		ok = ok,
		error = if ok then nil else tostring(err),
		activated = count,
		lobbyOnly = p:GetAttribute("LobbyOnly"),
		guide = gui.Guide.Visible,
	})
	busy = false
end)
