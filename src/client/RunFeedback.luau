--!strict
-- One bounded, non-interactive toast. Feedback never changes movement or simulation.
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local rewards =
	require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("EconomyConfig")).Rewards
local Hints = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("PlayerHints"))
local RunFeedback = {}

function RunFeedback.new(player: Player, state: Instance, gui: ScreenGui, toast: Frame)
	local connections: { RBXScriptConnection } = {}
	local tween: Tween? = nil
	local epoch = 0
	local priority = 0
	local untilAt = 0
	local destroyed = false
	local function clear()
		epoch += 1
		priority = 0
		untilAt = 0
		toast.Visible = false
		if tween then
			tween:Cancel()
			tween = nil
		end
	end
	local function show(text: string, color: Color3, level: number, compactText: string?)
		if destroyed or gui:GetAttribute("StationModal") ~= "" then
			return
		end
		if state:GetAttribute("Phase") ~= "Rule" and state:GetAttribute("Phase") ~= "Break" then
			return
		end
		if player:GetAttribute("LobbyOnly") == true then
			return
		end
		local compact = gui:GetAttribute("CompactPlayHUD") == true
		if compact then
			local stage = state:GetAttribute("HazardStage")
			if level == 2 or player:GetAttribute("Eliminated") == true or stage == "Warning" then
				return
			end
			if level == 1 and stage ~= "Recovery" and state:GetAttribute("RuleId") ~= "LowGravity" then
				return
			end
		end
		if Workspace:GetServerTimeNow() < untilAt and level < priority then
			return
		end
		clear()
		local thisEpoch = epoch
		priority = level
		local duration = if compact then 0.7 else 1.6
		untilAt = Workspace:GetServerTimeNow() + duration
		toast.Message.Text = if compact then compactText or text else text
		toast.Message.TextColor3 = color
		toast.Visible = true
		toast.Pulse.Scale = 1
		if not compact and gui:GetAttribute("ReducedMotion") ~= true then
			toast.Pulse.Scale = 1.035
			tween =
				TweenService:Create(toast.Pulse, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 1 })
			tween:Play()
		end
		task.delay(duration, function()
			if not destroyed and epoch == thisEpoch then
				clear()
			end
		end)
	end
	local previousStars = player:GetAttribute("RunStars") or 0
	local previousSurvived = player:GetAttribute("RunSurvived") or 0
	local previousOutcome = player:GetAttribute("LastTrialOutcome")
	table.insert(
		connections,
		player:GetAttributeChangedSignal("RunStars"):Connect(function()
			local stars = player:GetAttribute("RunStars") or 0
			if stars > previousStars then
				show(
					string.format(
						"★ ЗАРЯД СОБРАН  ·  +%d МОНЕТ  ·  +%d ОПЫТА",
						rewards.StarCoins,
						rewards.StarXP
					),
					Color3.fromRGB(255, 213, 79),
					1,
					string.format("★ +%d монеты", rewards.StarCoins)
				)
			end
			previousStars = stars
		end)
	)
	local function renderTrialFeedback()
		local survived = player:GetAttribute("RunSurvived") or 0
		local outcome = player:GetAttribute("LastTrialOutcome")
		-- These attributes may replicate in either order. Wait for both an awarded
		-- outcome and the increased total before announcing coins, once per increase.
		previousSurvived = math.min(previousSurvived, survived)
		local forfeited = outcome == "Forfeited" or player:GetAttribute("MovementWarning") == true
		if survived > previousSurvived and outcome == "Survived" and not forfeited then
			previousSurvived = survived
			show(
				string.format(
					"✓ ИСПЫТАНИЕ ПРОЙДЕНО  ·  +%d МОНЕТ  ·  +%d ОПЫТА",
					rewards.SurvivalCoins,
					rewards.SurvivalXP
				),
				Color3.fromRGB(66, 220, 169),
				3,
				string.format("✓ Пройдено · +%d монет", rewards.SurvivalCoins)
			)
		elseif outcome == "Forfeited" and outcome ~= previousOutcome then
			show(Hints.Forfeited.Toast, Color3.fromRGB(255, 213, 79), 3, Hints.Forfeited.CompactToast)
		end
		previousOutcome = outcome
	end
	table.insert(connections, player:GetAttributeChangedSignal("RunSurvived"):Connect(renderTrialFeedback))
	table.insert(
		connections,
		player:GetAttributeChangedSignal("LastTrialOutcome"):Connect(renderTrialFeedback)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal("MovementWarning"):Connect(renderTrialFeedback)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal("LastDamageAt"):Connect(function()
			local at = player:GetAttribute("LastDamageAt")
			local rule = player:GetAttribute("LastDamageRule")
			if
				player:GetAttribute("InRound") == true
				and typeof(at) == "number"
				and at > 0
				and Workspace:GetServerTimeNow() - at <= 2
				and typeof(rule) == "string"
				and rule ~= ""
			then
				show(
					"КАСАНИЕ ОПАСНОСТИ  ·  БЕРЕГИ ЗДОРОВЬЕ",
					Color3.fromRGB(255, 115, 173),
					2
				)
			end
		end)
	)
	table.insert(
		connections,
		state:GetAttributeChangedSignal("Phase"):Connect(function()
			if state:GetAttribute("Phase") ~= "Break" then
				clear()
			end
		end)
	)
	table.insert(connections, gui:GetAttributeChangedSignal("StationModal"):Connect(clear))
	table.insert(
		connections,
		state:GetAttributeChangedSignal("HazardStage"):Connect(function()
			if
				gui:GetAttribute("CompactPlayHUD") == true
				and state:GetAttribute("HazardStage") == "Warning"
			then
				clear()
			end
		end)
	)
	table.insert(connections, player:GetAttributeChangedSignal("LobbyOnly"):Connect(clear))
	return {
		Destroy = function()
			destroyed = true
			clear()
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
	}
end

return RunFeedback
