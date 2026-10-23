--!strict
-- Server-owned state drives this interface. Input sends intents only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local CollectionPanel = require(script.Parent:WaitForChild("CollectionPanel"))
local CharacterPresentation = require(script.Parent:WaitForChild("CharacterPresentation"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("RuleRoomHUD") :: ScreenGui
local root = gui:WaitForChild("Root") :: Frame
local header = root.Header :: Frame
local panel = root.RulePanel :: Frame
local column = panel.TextColumn :: Frame
local timer = panel.Timer :: Frame
local status = root.PlayerStatus :: TextLabel
local controls = root.ControlsTip :: TextLabel
local healthBar = root.HealthBar :: Frame
local teamPanel = root.TeamPanel :: Frame
local votePanel = root.VotePanel :: Frame
local resultsPanel = root.ResultsPanel :: Frame
local actions = root.Actions :: Frame
local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local remotes = ReplicatedStorage:WaitForChild("RuleRoomRemotes")
local voteRemote = remotes:WaitForChild("Vote") :: RemoteEvent
local profileRemote = remotes:WaitForChild("ProfileAction") :: RemoteEvent
local economy = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("EconomyConfig"))
local config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local collection = CollectionPanel.new(root, player, profileRemote, economy)
local characters = CharacterPresentation.new(player, economy, root.SpectateNext)
local audio = AudioController.new(player, state, root, root.Actions.Audio)

local cyan = Color3.fromRGB(70, 168, 244)
local white = Color3.fromRGB(246, 248, 255)
local muted = Color3.fromRGB(179, 197, 219)
local yellow = Color3.fromRGB(255, 213, 79)
local pink = Color3.fromRGB(255, 115, 173)
local green = Color3.fromRGB(66, 220, 169)
local phaseNames = {
	Waiting = "ЛАБОРАТОРИЯ / ГОТОВИМСЯ",
	Voting = "ВЫБЕРИ ХАРАКТЕР КОМНАТЫ",
	Rule = "ИСПЫТАНИЕ АКТИВНО",
	Break = "КОРОТКАЯ ПЕРЕДЫШКА",
	Results = "ЭКСПЕРИМЕНТ ЗАВЕРШЁН",
}
local modes = {
	{ Id = "Balanced", Color = cyan },
	{ Id = "Reflex", Color = pink },
	{ Id = "Cosmic", Color = green },
}
local phase = "Waiting"
local deadline = 0
local shownSecond = -1
local selectedVote: string? = nil
local lastVoteAt = 0
local short = false
local lastInput = UserInputService:GetLastInputType()
local reducedMotion = GuiService.ReducedMotionEnabled
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local health = 100
local maxHealth = 100
local best = 0
local onboardingRules = 0
local lastRuleKey = ""
local barTweens: { [Instance]: Tween } = {}
local destroyed = false
local compactChatHandled = false

local function connect(signal: RBXScriptSignal, callback)
	table.insert(connections, signal:Connect(callback))
end

local function initializeCompactChat()
	if
		compactChatHandled
		or not UserInputService.TouchEnabled
		or root.AbsoluteSize.X > 900
		or root.AbsoluteSize.Y >= 470
		or root.AbsoluteSize.Y <= 0
	then
		return
	end
	-- Collapse only the initial open window. The top-bar chat button remains usable,
	-- and later viewport changes or rounds never close chat opened by the player.
	compactChatHandled = true
	task.spawn(function()
		for _ = 1, 8 do
			if destroyed then
				return
			end
			if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then
				root:SetAttribute("CompactChatInitialState", "UserInterfaceActive")
				return
			end
			local available, active = pcall(function()
				return StarterGui:GetCore("ChatActive")
			end)
			if available and active == false then
				root:SetAttribute("CompactChatInitialState", "AlreadyClosed")
				return
			elseif available and active == true and not UserInputService:GetFocusedTextBox() then
				local closed = pcall(function()
					StarterGui:SetCore("ChatActive", false)
				end)
				if closed then
					root:SetAttribute("CompactChatInitialState", "Closed")
					return
				end
			end
			task.wait(0.25)
		end
		if not destroyed then
			root:SetAttribute("CompactChatInitialState", "Unavailable")
		end
	end)
end

local function num(source: Instance, name: string, fallback: number?): number
	local value = source:GetAttribute(name)
	return if typeof(value) == "number" then value else (fallback or 0)
end

local function str(source: Instance, name: string, fallback: string): string
	local value = source:GetAttribute(name)
	return if typeof(value) == "string" and value ~= "" then value else fallback
end

local function fillBar(fill: Frame, fraction: number)
	local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if barTweens[fill] then
		barTweens[fill]:Cancel()
		barTweens[fill] = nil
	end
	if reducedMotion then
		fill.Size = target
	else
		local tween = TweenService:Create(fill, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Size = target })
		barTweens[fill] = tween
		tween:Play()
	end
end

local function renderStatus()
	local points = num(player, "RunScore")
	local index = num(state, "RuleIndex")
	local count = num(state, "RuleCount", 6)
	local nextTrial = if index < count
		then string.format("ИСПЫТАНИЕ %d/%d", index + 1, count)
		else "НОВЫЙ ЗАБЕГ"
	column.Instruction.Text = str(
		state,
		"Instruction",
		"Читай правило. Двигайся. Попробуй ещё раз!"
	)
	status.Visible = phase ~= "Voting" and phase ~= "Results"
	if player:GetAttribute("InRound") == true and phase == "Rule" then
		status.Text = string.format(
			"ЗДОРОВЬЕ %d  •  ЦЕЛЬ %d/4  •  ОЧКИ %d",
			math.ceil(health),
			math.min(4, num(player, "RunSurvived")),
			points
		)
		status.TextColor3 = if health <= 35 then pink else white
	elseif player:GetAttribute("Eliminated") == true and phase == "Rule" then
		status.Text = "ВЫБЫЛ  •  ВЕРНЁШЬСЯ: " .. nextTrial
		column.Instruction.Text = str(
			player,
			"LastTrialReason",
			"Это испытание закончено для тебя."
		) .. " Очки сохраняются."
		status.TextColor3 = pink
	elseif phase == "Rule" then
		status.Text = "НАБЛЮДАЕШЬ  •  ДАЛЬШЕ: " .. nextTrial
		status.TextColor3 = muted
	elseif phase == "Results" then
		status.Text = string.format(
			"ТВОЙ РЕЗУЛЬТАТ: %d ОЧКОВ  •  ПРОЙДЕНО %d / 6",
			points,
			num(player, "RunSurvived")
		)
		status.TextColor3 = yellow
	elseif phase == "Break" then
		local result = str(player, "TrialResult" .. tostring(index), "Pending")
		status.Text = if result == "Survived"
			then "✓ ИСПЫТАНИЕ ПРОЙДЕНО  •  ДАЛЬШЕ: " .. nextTrial
			else "ПРОБУЕМ СНОВА  •  ДАЛЬШЕ: " .. nextTrial
		status.TextColor3 = if result == "Survived" then green else white
	else
		status.Text = "ЦЕЛЬ: ВЫЖИТЬ 4 РАЗА И ПРОЙТИ ОБЩИЙ ФИНАЛ"
		status.TextColor3 = white
	end
	if phase == "Voting" then
		column.Instruction.Text = if root.AbsoluteSize.Y < 290
			then "4 испытания + выжить в финале"
			else "Выживи в 4 из 6 испытаний и в финале. Реактор заряжаем вместе!"
	elseif phase == "Results" and root.AbsoluteSize.Y < 290 then
		column.Instruction.Text = "Новый забег начнётся автоматически"
	end
	local compactFinale = root.AbsoluteSize.Y < 260 and str(state, "RuleId", "") == "ReactorRush"
	healthBar.Visible = phase == "Rule" and player:GetAttribute("InRound") == true and not compactFinale
	healthBar.Fill.BackgroundColor3 = if health <= 35 then pink else green
	fillBar(healthBar.Fill, health / math.max(1, maxHealth))
end

local function trackParticipation()
	-- Observing an ongoing trial must not consume a late joiner's first control hint.
	if
		phase ~= "Rule"
		or player:GetAttribute("InRound") ~= true
		or str(state, "RuleId", "") == "ReactorRush"
	then
		return
	end
	local ruleKey = tostring(num(state, "Round")) .. ":" .. tostring(num(state, "RuleIndex"))
	if ruleKey ~= lastRuleKey then
		lastRuleKey = ruleKey
		onboardingRules += 1
	end
end

local function renderTrialProgress()
	local accentValue = state:GetAttribute("Accent")
	local accent = if typeof(accentValue) == "Color3" then accentValue else cyan
	for index = 1, 6 do
		local step = root.TrialProgress["Step" .. index] :: Frame
		local result = str(player, "TrialResult" .. index, "Pending")
		local mark = "·"
		local ink = muted
		local color = Color3.fromRGB(54, 70, 91)
		if result == "Survived" then
			mark, color, ink = "✓", green, Color3.fromRGB(18, 30, 50)
		elseif result == "Failed" then
			mark, color, ink = "×", pink, Color3.fromRGB(18, 30, 50)
		elseif result == "Active" then
			mark, color, ink = "▶", accent, Color3.fromRGB(18, 30, 50)
		elseif result == "Missed" then
			mark = "—"
		end
		step.BackgroundColor3 = color
		step.Mark.Text = string.format("%d %s", index, mark)
		step.Mark.TextColor3 = ink
	end
end

local function nextCollectionGoal(): string
	for id, quest in economy.Quests do
		if player:GetAttribute("Claimed_" .. id) ~= true and num(player, "Quest_" .. id) >= quest.Target then
			return "Награда за цель готова"
		end
	end
	local nextTrail = nil
	for _, trail in economy.Trails do
		if
			trail.Price > 0
			and player:GetAttribute("Owned_" .. trail.Id) ~= true
			and (not nextTrail or trail.Price < nextTrail.Price)
		then
			nextTrail = trail
		end
	end
	if nextTrail then
		local remaining = math.max(0, nextTrail.Price - num(player, "Coins"))
		return if remaining == 0
			then "Доступен след: " .. nextTrail.Name
			else string.format("%s: ещё %d монет", nextTrail.Name, remaining)
	end
	return "Все следы открыты"
end

local function renderNextRun()
	local remaining = math.max(0, math.ceil(deadline - Workspace:GetServerTimeNow()))
	resultsPanel.Next.Text =
		string.format("%s  •  новый забег: %d с", nextCollectionGoal(), remaining)
end

local function renderResults()
	local survived = num(player, "RunSurvived")
	local charges = num(player, "RunCharges")
	local won = player:GetAttribute("RunWon") == true
	local participated = survived > 0
	for index = 1, 6 do
		participated = participated or player:GetAttribute("TrialResult" .. index) == "Failed"
	end
	resultsPanel.Heading.Text = if won
		then "ТВОЯ ПОБЕДА!"
		elseif participated then "ТВОЙ РЕЗУЛЬТАТ"
		else "СЛЕДУЮЩИЙ ЗАБЕГ — ТВОЙ"
	local outcome: string
	if won then
		outcome = string.format("Реактор заряжен! Твои заряды: %d.", charges)
	elseif not participated then
		outcome = "Следующий забег — твой. Начнём вместе!"
	elseif state:GetAttribute("FinaleSuccess") ~= true then
		outcome = if num(state, "TeamGoal") > 0
				and num(state, "TeamCharge") >= num(state, "TeamGoal")
			then "Реактор заряжен, но финал не пережили."
			else string.format(
				"Реактор %d/%d. Твои заряды: %d.",
				num(state, "TeamCharge"),
				num(state, "TeamGoal", 1),
				charges
			)
	elseif survived < 4 then
		outcome = string.format(
			"Реактор заряжен. Выживаний %d/4 — нужно ещё.",
			survived
		)
	else
		outcome = "До победы осталось выжить в финале."
	end
	resultsPanel.Summary.Text = string.format(
		"%s\n+%d монет  •  +%d опыта",
		outcome,
		num(player, "RunCoinsEarned"),
		num(player, "RunXPEarned")
	)
	resultsPanel.Personal.Text = string.format(
		"%d очков  •  %d/6 выжил  •  рекорд %d",
		num(player, "RunScore"),
		survived,
		best
	)
	renderNextRun()
end

local function renderPlayer()
	-- Core chat can extend below the top-bar inset. Keep our brand out of that region.
	header.GameTitle.Visible = phase ~= "Rule" and root.AbsoluteSize.X >= 1000 and not short
	header.PersonalScore.Text =
		string.format("УР. %d  •  %d МОНЕТ", num(player, "Level", 1), num(player, "Coins"))
	column.RoundLabel.Text = string.format(
		"ЗАБЕГ %d  •  ИСПЫТАНИЕ %d / %d  •  ОЧКИ %d",
		num(state, "Round"),
		num(state, "RuleIndex"),
		num(state, "RuleCount", 6),
		num(player, "RunScore")
	)
	teamPanel.ChargeLabel.Text = string.format(
		"РЕАКТОР %d/%d  •  ТЫ ЗА ЗАБЕГ: %d",
		num(state, "TeamCharge"),
		num(state, "TeamGoal", 1),
		num(player, "RunCharges")
	)
	renderTrialProgress()
	renderResults()
	renderStatus()
end

local function renderControls()
	local hint = if string.find(lastInput.Name, "Gamepad")
		then "Левый стик — ходьба  •  A — прыжок"
		elseif
			lastInput == Enum.UserInputType.Touch or UserInputService.TouchEnabled
		then "Джойстик — ходьба  •  кнопка справа — прыжок"
		else "WASD — ходьба  •  ПРОБЕЛ — прыжок"
	controls.Text = hint
	controls.Visible = onboardingRules <= 1
		and phase == "Rule"
		and player:GetAttribute("InRound") == true
		and str(state, "RuleId", "") ~= "ReactorRush"
end

local function renderClock()
	local remaining = if deadline > 0
		then math.max(0, math.ceil(deadline - Workspace:GetServerTimeNow()))
		else -1
	if shownSecond == remaining then
		return
	end
	shownSecond = remaining
	timer.Countdown.Text = if remaining >= 0 then tostring(remaining) else "—"
	timer.UnitLabel.Text = if remaining < 0 then "ЖДЁМ" else "СЕК"
	if phase == "Results" then
		renderNextRun()
	end
end

local function renderVotes()
	local accepted = player:GetAttribute("VotedMode")
	selectedVote = nil
	for _, mode in modes do
		local button = votePanel.Cards[mode.Id] :: TextButton
		local selected = accepted == mode.Id
		if selected then
			selectedVote = mode.Id
		end
		local metadata = config.Modes[mode.Id]
		button.Text = string.format(
			"%s%s\n%s\n%d ГОЛОСОВ",
			if selected then "✓ " else "",
			metadata.Name,
			metadata.Description,
			num(state, "Votes" .. mode.Id)
		)
		button.BackgroundColor3 = if selected then mode.Color else Color3.fromRGB(39, 56, 78)
		button.TextColor3 = if selected then Color3.fromRGB(18, 30, 50) else white
	end
end

local applyComposition: () -> ()

local function renderState()
	local previousPhase = phase
	phase = str(state, "Phase", "Waiting")
	deadline = num(state, "PhaseEndsAt")
	local index = num(state, "RuleIndex")
	trackParticipation()
	column.PhaseLabel.Text = if phase == "Rule"
		then string.format(
			"ИСПЫТАНИЕ %d/%d  •  %s",
			index,
			num(state, "RuleCount", 6),
			if str(state, "RuleId", "") == "ReactorRush"
				then "СОБИРАЕМ ВМЕСТЕ"
				else "ВЫЖИВАЙ"
		)
		else phaseNames[phase] or "КОМНАТА ПРАВИЛ"
	column.RuleLabel.Text = str(state, "RuleName", "КОМНАТА ПРОСЫПАЕТСЯ")
	local color = state:GetAttribute("Accent")
	local accent = if typeof(color) == "Color3" then color else cyan
	panel.AccentBar.BackgroundColor3 = accent
	timer.BackgroundColor3 = accent
	teamPanel.Visible = phase == "Rule" and str(state, "RuleId", "") == "ReactorRush"
	local charge = num(state, "TeamCharge")
	local goal = num(state, "TeamGoal", 1)
	fillBar(teamPanel.Meter.Fill, charge / math.max(1, goal))
	votePanel.Visible = phase == "Voting"
	resultsPanel.Visible = phase == "Results"
	collection.SetPhase(phase)
	characters.SetPhase(phase)
	renderVotes()
	renderPlayer()
	renderControls()
	shownSecond = -2
	renderClock()
	if phase ~= previousPhase then
		applyComposition()
	end
	if
		phase == "Voting"
		and previousPhase ~= phase
		and not collection.IsOpen()
		and not GuiService.MenuIsOpen
		and string.find(lastInput.Name, "Gamepad")
	then
		GuiService.SelectedObject = votePanel.Cards.Balanced
	elseif
		phase ~= "Voting"
		and GuiService.SelectedObject
		and GuiService.SelectedObject:IsDescendantOf(votePanel)
	then
		GuiService.SelectedObject = nil
	end
end

applyComposition = function()
	short = root.AbsoluteSize.Y < 470
	local narrow = root.AbsoluteSize.X < 600
	local compactMenu = root.AbsoluteSize.Y < 330 and (phase == "Voting" or phase == "Results")
	local tinyMenu = compactMenu and root.AbsoluteSize.Y < 290
	local extremeMenu = compactMenu and root.AbsoluteSize.Y < 260
	local compactFinale = root.AbsoluteSize.Y < 260
		and phase == "Rule"
		and str(state, "RuleId", "") == "ReactorRush"
	local compactSpectate = root.AbsoluteSize.Y < 330 and phase == "Rule" and root.SpectateNext.Visible
	local height = if extremeMenu
		then 46
		elseif tinyMenu then 52
		elseif compactMenu then 62
		elseif short then 86
		else 116
	local top = if short then 28 else 32
	header.Position = UDim2.new(0.5, 0, 0, 2)
	header.GameTitle.Position = UDim2.fromScale(0.32, 0)
	header.GameTitle.Size = UDim2.fromScale(0.3, 1)
	header.GameTitle.TextXAlignment = Enum.TextXAlignment.Center
	header.PersonalScore.Position = UDim2.fromScale(0.62, 0)
	header.PersonalScore.Size = UDim2.fromScale(0.38, 1)
	panel.Position = UDim2.new(0.5, 0, 0, top)
	panel.Size = UDim2.new(1, -24, 0, height)
	column.Size = UDim2.new(1, if narrow then -88 else -100, 1, 0)
	column.PhaseLabel.Visible = not compactMenu
	column.PhaseLabel.Position = UDim2.fromOffset(0, if short then 4 else 8)
	column.PhaseLabel.Size = UDim2.new(1, 0, 0, if short then 13 else 16)
	column.RuleLabel.Position = UDim2.fromOffset(0, if compactMenu then 3 elseif short then 19 else 26)
	column.RuleLabel.Size = UDim2.new(1, 0, 0, if extremeMenu then 20 elseif short then 24 else 29)
	column.Instruction.Position = UDim2.fromOffset(
		0,
		if extremeMenu then 24 elseif tinyMenu then 28 elseif compactMenu then 29 elseif short then 45 else 57
	)
	column.Instruction.Size = UDim2.new(
		1,
		0,
		0,
		if extremeMenu then 20 elseif tinyMenu then 22 elseif compactMenu then 29 elseif short then 35 else 32
	)
	column.RoundLabel.Visible = not short
	timer.Size = UDim2.fromOffset(
		if narrow then 56 else 64,
		if extremeMenu then 40 elseif tinyMenu then 46 elseif compactMenu then 56 elseif short then 64 else 74
	)
	timer.Position = UDim2.new(1, -12, 0.5, 0)
	timer.Countdown.Size = UDim2.new(
		1,
		-8,
		0,
		if extremeMenu then 18 elseif tinyMenu then 24 elseif compactMenu then 32 elseif short then 40 else 48
	)
	timer.UnitLabel.Position = UDim2.new(0, 4, 1, if tinyMenu then -17 else -20)
	root.TrialProgress.Position = UDim2.new(0.5, 0, 0, top + height + 1)
	status.Position = UDim2.new(0.5, 0, 0, top + height + 15)
	status.Size = UDim2.new(1, -24, 0, if short then 20 else 22)
	healthBar.Position = UDim2.new(0.5, 0, 0, top + height + 39)
	controls.Position = UDim2.new(0.5, 0, 0, top + height + 47)
	teamPanel.Position = UDim2.new(0.5, 0, 0, top + height + (if compactFinale then 38 else 47))
	teamPanel.Size = UDim2.new(1, -48, 0, if compactFinale then 25 else 38)
	teamPanel.ChargeLabel.Position = UDim2.fromOffset(8, if compactFinale then 1 else 2)
	teamPanel.ChargeLabel.Size = UDim2.new(1, -16, 0, if compactFinale then 16 else 22)
	teamPanel.ChargeLabel.TextSize = if compactFinale then 12 else 13
	teamPanel.Meter.Position = UDim2.new(0, 8, 1, if compactFinale then -6 else -10)
	teamPanel.Meter.Size = UDim2.new(1, -16, 0, if compactFinale then 4 else 5)
	local menuTop = if short then top + height + 14 else math.max(220, root.AbsoluteSize.Y * 0.43)
	votePanel.Position = UDim2.new(0.5, 0, 0, menuTop)
	resultsPanel.Position = votePanel.Position
	local menuHeight = if tinyMenu then 106 elseif compactMenu then 114 elseif short then 132 else 154
	if short then
		menuHeight = math.min(menuHeight, root.AbsoluteSize.Y - 64 - menuTop)
	end
	votePanel.Size = UDim2.new(1, -32, 0, menuHeight)
	votePanel.Cards.Size = UDim2.new(1, -20, 0, if compactMenu then 54 elseif short then 62 else 78)
	votePanel.Heading.Size = UDim2.new(1, -24, 0, if tinyMenu then 20 elseif short then 23 else 28)
	votePanel.Cards.Position =
		UDim2.fromOffset(10, if tinyMenu then 28 elseif compactMenu then 30 elseif short then 33 else 39)
	votePanel.Hint.Size = UDim2.new(1, -20, 0, if tinyMenu then 16 elseif compactMenu then 18 else 25)
	votePanel.Hint.Position = UDim2.new(0, 10, 1, if tinyMenu then -20 elseif compactMenu then -23 else -29)
	votePanel.Hint.Visible = not extremeMenu
	resultsPanel.Size = UDim2.new(1, -36, 0, if short then menuHeight else 148)
	resultsPanel.Next.Visible = not extremeMenu
	resultsPanel.Heading.Position = UDim2.fromOffset(14, if compactMenu then 6 else 8)
	resultsPanel.Heading.Size =
		UDim2.new(1, -28, 0, if extremeMenu then 21 elseif compactMenu then 23 elseif short then 25 else 30)
	resultsPanel.Summary.Position =
		UDim2.fromOffset(14, if extremeMenu then 29 elseif compactMenu then 31 elseif short then 35 else 43)
	resultsPanel.Summary.Size = UDim2.new(1, -28, 0, if compactMenu then 28 elseif short then 37 else 46)
	resultsPanel.Personal.Position =
		UDim2.fromOffset(14, if extremeMenu then 59 elseif compactMenu then 61 elseif short then 76 else 92)
	resultsPanel.Personal.Size = UDim2.new(1, -28, 0, if compactMenu then 20 else 25)
	resultsPanel.Next.Position = UDim2.new(0, 14, 1, if compactMenu then -20 else -24)
	resultsPanel.Next.Size = UDim2.new(1, -28, 0, if compactMenu then 17 else 19)
	local collectionWidth = if narrow then 136 else 160
	local motionWidth = if narrow then 106 else 128
	local audioWidth = if narrow then 86 else 104
	local motionLeft = if phase == "Rule" then 0 else collectionWidth + 8
	local audioLeft = if compactSpectate then 214 else motionLeft + motionWidth + 8
	local actionWidth = audioLeft + audioWidth
	actions.Size = UDim2.fromOffset(actionWidth, 44)
	actions.Collection.Size = UDim2.fromOffset(collectionWidth, 44)
	actions.Motion.Position = UDim2.fromOffset(motionLeft, 0)
	actions.Motion.Size = UDim2.fromOffset(motionWidth, 44)
	actions.Motion.Visible = not compactSpectate
	actions.Audio.Position = UDim2.fromOffset(audioLeft, 0)
	actions.Audio.Size = UDim2.fromOffset(audioWidth, 44)
	actions.Motion.NextSelectionLeft = if phase == "Rule" then actions.Audio else actions.Collection
	actions.Audio.NextSelectionRight = if phase == "Rule" then actions.Motion else actions.Collection
	actions.Audio.NextSelectionLeft = actions.Motion
	root.SpectateNext.AnchorPoint = if compactSpectate then Vector2.zero else Vector2.new(0.5, 1)
	root.SpectateNext.Position = if compactSpectate
		then UDim2.new(0.5, -actionWidth / 2, 1, -56)
		else UDim2.new(0.5, 0, 1, -64)
	for _, button in { actions.Collection, actions.Motion, actions.Audio } do
		button.NextSelectionUp = if phase == "Voting" then votePanel.Cards.Balanced else button
		button.NextSelectionDown = button
	end
	if compactSpectate then
		actions.Audio.NextSelectionLeft = root.SpectateNext
		actions.Audio.NextSelectionRight = root.SpectateNext
		actions.Audio.NextSelectionUp = root.SpectateNext
		root.SpectateNext.NextSelectionLeft = actions.Audio
		root.SpectateNext.NextSelectionRight = actions.Audio
		root.SpectateNext.NextSelectionDown = actions.Audio
		if GuiService.SelectedObject == actions.Motion then
			GuiService.SelectedObject = root.SpectateNext
		end
	end
	initializeCompactChat()
	renderControls()
	renderPlayer()
end

local function setMotion(value: boolean)
	reducedMotion = value
	actions.Motion.Text = if value then "ЭФФЕКТЫ: МИН" else "ЭФФЕКТЫ: ВКЛ"
	characters.SetReducedMotion(value)
end

for index, mode in modes do
	local button = votePanel.Cards[mode.Id] :: TextButton
	button.NextSelectionLeft = votePanel.Cards[modes[(index - 2) % #modes + 1].Id]
	button.NextSelectionRight = votePanel.Cards[modes[index % #modes + 1].Id]
	button.NextSelectionDown = actions.Collection
	connect(button.Activated, function()
		if
			phase == "Voting"
			and not collection.IsOpen()
			and os.clock() - lastVoteAt >= config.VoteCooldown
		then
			lastVoteAt = os.clock()
			voteRemote:FireServer(mode.Id)
		end
	end)
end

actions.Collection.NextSelectionRight = actions.Motion
actions.Collection.NextSelectionLeft = actions.Audio
actions.Motion.NextSelectionRight = actions.Audio
actions.Audio.NextSelectionLeft = actions.Motion
connect(actions.Motion.Activated, function()
	setMotion(not reducedMotion)
end)
connect(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"), function()
	setMotion(GuiService.ReducedMotionEnabled)
end)
connect(UserInputService.LastInputTypeChanged, function(input)
	lastInput = input
	renderControls()
	if
		phase == "Voting"
		and not collection.IsOpen()
		and not GuiService.MenuIsOpen
		and string.find(input.Name, "Gamepad")
		and not GuiService.SelectedObject
	then
		GuiService.SelectedObject = votePanel.Cards[selectedVote or "Balanced"]
	end
end)
connect(root:GetPropertyChangedSignal("AbsoluteSize"), applyComposition)
connect(root.SpectateNext:GetPropertyChangedSignal("Visible"), applyComposition)
connect(player.AttributeChanged, function(name)
	if name == "InRound" then
		trackParticipation()
	end
	renderPlayer()
	if name == "VotedMode" then
		renderVotes()
	end
	if name == "InRound" or name == "Eliminated" then
		renderControls()
	end
end)
local pending = false
connect(state.AttributeChanged, function()
	if not pending then
		pending = true
		task.defer(function()
			pending = false
			if not destroyed then
				renderState()
			end
		end)
	end
end)

local function bindCharacter(character: Model)
	if destroyed or player.Character ~= character then
		return
	end
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not destroyed and humanoid and humanoid:IsA("Humanoid") and player.Character == character then
		local function updateHealth()
			health = humanoid.Health
			maxHealth = humanoid.MaxHealth
			renderStatus()
		end
		table.insert(characterConnections, humanoid.HealthChanged:Connect(updateHealth))
		table.insert(
			characterConnections,
			humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
		)
		updateHealth()
	end
end
connect(player.CharacterAdded, bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 10)
	local record = if stats then stats:WaitForChild("Best", 10) else nil
	if destroyed or not record or not record:IsA("IntValue") then
		return
	end
	local function updateRecord()
		best = record.Value
		renderPlayer()
	end
	connect(record:GetPropertyChangedSignal("Value"), updateRecord)
	updateRecord()
end)

local elapsed = 0
connect(RunService.Heartbeat, function(dt)
	elapsed += dt
	if elapsed >= 0.1 then
		elapsed = 0
		renderClock()
	end
end)
applyComposition()
setMotion(reducedMotion)
renderState()

connect(gui.Destroying, function()
	destroyed = true
	collection.Destroy()
	characters.Destroy()
	audio.Destroy()
	for _, list in { connections, characterConnections } do
		for _, connection in list do
			connection:Disconnect()
		end
		table.clear(list)
	end
	for _, tween in barTweens do
		tween:Cancel()
	end
end)
