-- Isolated Studio QA; install only as a native LocalScript. Not mapped into production.
assert(game:GetService("RunService"):IsStudio(), "Studio-only station driver")
local p = game.Players.LocalPlayer
local RS = game.ReplicatedStorage
local RunService = game:GetService("RunService")
local controls = require(p.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
local course = workspace.Arena.Lobby.Practice
local event = RS.RuleRoomRemotes.StationAction
local active = false
local function run()
	if active then
		return
	end
	active = true
	controls:Disable()
	script:SetAttribute("Result", "Running")
	local h = p.Character:FindFirstChildOfClass("Humanoid")
	local root = p.Character.HumanoidRootPart
	local jumpCount = 0
	local start = os.clock()
	local previousIndex = p:GetAttribute("PracticeCheckpoint") or 0
	local jumpAt = -100
	while active and os.clock() - start < 65 and p:GetAttribute("PracticeState") == "Running" do
		local index = p:GetAttribute("PracticeCheckpoint") or 0
		local target = course:FindFirstChild("Checkpoint" .. (index + 1))
		if not target then
			break
		end
		local previous = if index > 0 then course["Checkpoint" .. index] else course.StartPad
		if index ~= previousIndex then
			previousIndex = index
			jumpAt = -100
		end
		local position = root.Position
		local delta = Vector3.new(target.Position.X - position.X, 0, target.Position.Z - position.Z)
		local fromPrevious =
			Vector2.new(position.X - previous.Position.X, position.Z - previous.Position.Z).Magnitude
		local grounded = h.FloorMaterial ~= Enum.Material.Air
		h:MoveTo(Vector3.new(target.Position.X, position.Y, target.Position.Z))
		if grounded and fromPrevious >= 4.3 and os.clock() - jumpAt > 0.65 then
			h.Jump = true
			jumpAt = os.clock()
			jumpCount += 1
		end
		if delta.Magnitude < 0.5 then
			h:MoveTo(root.Position)
		end
		script:SetAttribute("ObservedCheckpoint", index)
		RunService.Heartbeat:Wait()
	end
	h:Move(Vector3.zero)
	controls:Enable()
	active = false
	script:SetAttribute("Jumps", jumpCount)
	script:SetAttribute("Result", p:GetAttribute("PracticeState"))
	script:SetAttribute("ObservedCheckpoint", p:GetAttribute("PracticeCheckpoint"))
end
local function command()
	local cmd = script:GetAttribute("Command")
	if cmd == "Start" or cmd == "DistantStart" then
		local prompt = course.StartConsole.Interact
		prompt:InputHoldBegin()
		task.wait(0.1)
		prompt:InputHoldEnd()
	elseif cmd == "Run" then
		task.spawn(run)
	elseif cmd == "Join" or cmd == "Explore" then
		event:FireServer(cmd)
	elseif cmd == "Malformed" then
		for _, value in { {}, "Practice", "GiveCoins", 1, true, string.rep("x", 300) } do
			event:FireServer(value)
		end
	elseif cmd == "Stop" then
		active = false
		controls:Enable()
		script:SetAttribute("Result", "Stopped")
	end
end
script:GetAttributeChangedSignal("Command"):Connect(command)
command()
script.Destroying:Connect(function()
	controls:Enable()
end)
