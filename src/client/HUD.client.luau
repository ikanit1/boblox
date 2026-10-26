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
local ProximityPromptService = game:GetService("ProximityPromptService")

local CollectionPanel = require(script.Parent:WaitForChild("CollectionPanel"))
local CharacterPresentation = require(script.Parent:WaitForChild("CharacterPresentation"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local RunFeedback = require(script.Parent:WaitForChild("RunFeedback"))
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("RuleRoomHUD") :: ScreenGui
local root = gui:WaitForChild("Root") :: Frame
local header = root.Header :: Frame
local panel = root.RulePanel :: Frame
local column = panel.TextColumn :: Frame
local timer = panel.Timer :: Frame
local instructionBounds = column.Instruction:WaitForChild("TextBounds") :: UITextSizeConstraint
local countdownBounds = timer.Countdown:WaitForChild("TextBounds") :: UITextSizeConstraint
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
local config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local economy = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("EconomyConfig"))
local hints = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("PlayerHints"))
local feedback = RunFeedback.new(player, state, gui, root.FeedbackToast)
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
	{ Id = "Balanced", Name = "БАЛАНС", Detail = "Всего понемногу", Color = cyan },
	{ Id = "Reflex", Name = "РЕАКЦИЯ", Detail = "Движение и прыжки", Color = pink },
	{
		Id = "Cosmic",
		Name = "КОСМОС",
		Detail = "Гравитация и энергия",
		Color = green,
	},
}
local phase = "Waiting"
local deadline = 0
local shownSecond = -1
local selectedVote: string? = nil
local lastVoteAt = -math.huge
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

local function compactPlay(): boolean
	return (phase == "Rule" or phase == "Break")
		and player:GetAttribute("LobbyOnly") ~= true
		and (root.AbsoluteSize.Y < 470 or (UserInputService.TouchEnabled and root.AbsoluteSize.X < 750))
end

local function phoneCommand(): string
	if phase == "Break" then
		return str(state, "RuleName", "Следующее испытание")
	end
	if player:GetAttribute("Eliminated") == true then
		return "ВЫБЫЛ · следующий этап скоро"
	end
	if player:GetAttribute("InRound") ~= true then
		return "Войдёшь в следующем испытании"
	end
	local id = str(state, "RuleId", "")
	local stage = str(state, "HazardStage", "Warning")
	if id == "SafeColor" then
		local color = config.Colors[str(state, "SafeColor", "")]
		return if color
			then (if stage == "Warning" then "Встань на " else "Стой на ")
				.. color.Symbol
				.. " "
				.. color.Label
			else "Найди нужный цвет"
	elseif id == "RedLight" then
		return if stage == "Active"
			then "■ СТОЙ! Не двигайся"
			elseif stage == "Warning" then "⏸ ОСТАНОВИСЬ"
			else "▶ БЕГИ за звёздами"
	elseif id == "LaserSweep" then
		return "Прыгай через красный луч"
	elseif id == "LowGravity" then
		return "Прыгай к звёздам ★"
	elseif id == "LavaRise" then
		return if stage == "Warning"
			then "Запрыгни на голубую платформу"
			else "Оставайся на платформе"
	elseif id == "MeteorRain" then
		return "Уходи с красных меток"
	elseif id == "DisappearingTiles" then
		return if stage == "Warning"
			then "Уйди с плиток «ПРОВАЛ»"
			else "Держись на оставшемся полу"
	elseif id == "SafeZone" then
		return if stage == "Warning"
			then "Беги в зелёный квадрат"
			else "Стой внутри зелёного квадрата"
	elseif id == "Spinner" then
		return "Перепрыгивай вращающийся луч"
	elseif id == "ReactorRush" then
		return if num(state, "TeamCharge") >= num(state, "TeamGoal", 1)
			then "Заряжен! Продолжай прыгать"
			else "Собирай ⚡ и перепрыгивай луч"
	end
	return "Следи за комнатой"
end

local function applyCompactPlay()
	local compact = compactPlay()
	gui:SetAttribute("CompactPlayHUD", compact)
	if not compact then
		return
	end
	local width = math.min(520, root.AbsoluteSize.X - 24)
	local finale = phase == "Rule"
		and str(state, "RuleId", "") == "ReactorRush"
		and player:GetAttribute("InRound") == true
	header.Visible = false
	root.TrialProgress.Visible = false
	status.Visible = false
	controls.Visible = false
	actions.Visible = false
	panel.Position = UDim2.new(0.5, 0, 0, 4)
	panel.Size = UDim2.fromOffset(width, 48)
	panel.BackgroundTransparency = 0.18
	column.Position = UDim2.fromOffset(12, 0)
	column.Size = UDim2.new(1, -72, 1, 0)
	column.PhaseLabel.Visible = false
	column.RuleLabel.Visible = false
	column.RoundLabel.Visible = false
	column.Instruction.Position = UDim2.fromOffset(0, if finale then 5 else 7)
	column.Instruction.Size = UDim2.new(1, 0, 0, if finale then 22 else 28)
	column.Instruction.Text = phoneCommand()
	column.Instruction.TextSize = 18
	instructionBounds.MaxTextSize = 18
	column.Instruction.TextWrapped = false
	timer.Size = UDim2.fromOffset(44, 32)
	timer.Position = UDim2.new(1, -8, 0, 20)
	timer.BackgroundTransparency = 1
	timer.Countdown.Position = UDim2.fromOffset(0, 0)
	timer.Countdown.Size = UDim2.fromScale(1, 1)
	timer.Countdown.TextColor3 = white
	timer.Countdown.TextSize = 24
	countdownBounds.MaxTextSize = 24
	timer.UnitLabel.Visible = false
	healthBar.Size = UDim2.fromOffset(72, 2)
	healthBar.Visible = phase == "Rule" and player:GetAttribute("InRound") == true
	healthBar.Position = UDim2.new(0.5, if finale then width / 2 - 48 else 0, 0, 46)
	teamPanel.Visible = finale
	teamPanel.BackgroundTransparency = 1
	teamPanel.Position = UDim2.new(0.5, -36, 0, 35)
	teamPanel.Size = UDim2.fromOffset(width - 110, 14)
	teamPanel.ChargeLabel.Position = UDim2.fromOffset(0, 0)
	teamPanel.ChargeLabel.Size = UDim2.fromScale(1, 1)
	teamPanel.ChargeLabel.Text =
		string.format("⚡ %d / %d", num(state, "TeamCharge"), num(state, "TeamGoal"))
	teamPanel.ChargeLabel.TextSize = 12
	teamPanel.Meter.Visible = false
	root.FeedbackToast.Position = UDim2.new(0.5, 0, 0, 65)
	root.FeedbackToast.Size = UDim2.fromOffset(math.min(260, width), 18)
	root.FeedbackToast.BackgroundTransparency = 1
	root.FeedbackToast.Message.Position = UDim2.fromOffset(0, 0)
	root.FeedbackToast.Message.Size = UDim2.fromScale(1, 1)
	root.FeedbackToast.Message.TextStrokeTransparency = 0.2
	root.SpectateNext.AnchorPoint = Vector2.new(1, 0)
	root.SpectateNext.Position = UDim2.new(1, -12, 0, 60)
	root.SpectateNext.Size = UDim2.fromOffset(math.min(220, width), 44)
	root.SpectateNext.NextSelectionLeft = root.SpectateNext
	root.SpectateNext.NextSelectionRight = root.SpectateNext
	root.SpectateNext.NextSelectionDown = root.SpectateNext
	root.SpectateNext.NextSelectionUp = root.SpectateNext
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(actions) then
		GuiService.SelectedObject = if root.SpectateNext.Visible then root.SpectateNext else nil
	end
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
	status.Visible = phase ~= "Voting" and phase ~= "Results" and player:GetAttribute("LobbyOnly") ~= true
	if player:GetAttribute("InRound") == true and phase == "Rule" then
		status.Text = string.format(
			"В ИГРЕ  •  ЗДОРОВЬЕ %d  •  ОЧКИ %d",
			math.ceil(health),
			points
		)
		status.TextColor3 = if health <= 35 then pink else white
	elseif player:GetAttribute("Eliminated") == true and phase == "Rule" then
		local reason = str(player, "EliminationReason", str(state, "RuleId", ""))
		local hint = hints.Defeat[reason]
			or "Следи за предупреждениями комнаты."
		status.Text = "ВЫБЫЛ · "
			.. hint
			.. "\nВернёшься в следующем испытании."
		status.TextColor3 = pink
	elseif phase == "Rule" then
		status.Text =
			"СМОТРИ ЗА КОМНАТОЙ  •  ВХОД В СЛЕДУЮЩЕМ ИСПЫТАНИИ"
		status.TextColor3 = muted
	elseif phase == "Results" then
		status.Text = string.format(
			"ТВОЙ РЕЗУЛЬТАТ: %d ОЧКОВ  •  ПРОЙДЕНО %d / 6",
			points,
			num(player, "RunSurvived")
		)
		status.TextColor3 = yellow
	elseif phase == "Break" then
		status.Text = "ВСЕ СНОВА В ИГРЕ В СЛЕДУЮЩЕМ ИСПЫТАНИИ"
		status.TextColor3 = green
	else
		status.Text = "ВЫБЕРИ РЕЖИМ  •  6 ИСПЫТАНИЙ  •  ОБЩИЙ ФИНАЛ"
		status.TextColor3 = white
	end
	status.Size =
		UDim2.new(1, -24, 0, if phase == "Rule" and player:GetAttribute("Eliminated") == true then 42 else 22)
	local compactFinale = root.AbsoluteSize.Y < 260 and str(state, "RuleId", "") == "ReactorRush"
	healthBar.Visible = phase == "Rule" and player:GetAttribute("InRound") == true and not compactFinale
	healthBar.Fill.BackgroundColor3 = if health <= 35 then pink else green
	fillBar(healthBar.Fill, health / math.max(1, maxHealth))
	applyCompactPlay()
end

local outcomeVisuals = {
	Pending = { Symbol = "·", Color = Color3.fromRGB(54, 70, 91), Ink = white },
	Playing = { Symbol = "▶", Color = cyan, Ink = Color3.fromRGB(18, 30, 50) },
	Survived = { Symbol = "✓", Color = green, Ink = Color3.fromRGB(18, 30, 50) },
	Eliminated = { Symbol = "×", Color = pink, Ink = Color3.fromRGB(18, 30, 50) },
	Skipped = { Symbol = "—", Color = Color3.fromRGB(64, 73, 88), Ink = muted },
}
local function renderOutcomes()
	for index = 1, 6 do
		local outcome = outcomeVisuals[str(player, "TrialOutcome_" .. index, "Pending")]
			or outcomeVisuals.Pending
		for _, strip in { root.TrialProgress, resultsPanel.Trials } do
			local step = strip["Step" .. index]
			step.BackgroundColor3 = outcome.Color
			step.Status.Text = tostring(index) .. " " .. outcome.Symbol
			step.Status.TextColor3 = outcome.Ink
		end
	end
end
local function nextGoal(): string
	for _, id in { "survive", "stars", "runs" } do
		local quest = economy.Quests[id]
		if num(player, "Quest_" .. id) >= quest.Target and player:GetAttribute("Claimed_" .. id) ~= true then
			return "ГОТОВА НАГРАДА: +"
				.. quest.Reward
				.. " монет — открой «Цели»."
		end
	end
	for _, trail in economy.Trails do
		if trail.Price > 0 and player:GetAttribute("Owned_" .. trail.Id) ~= true then
			local remaining = math.max(0, trail.Price - num(player, "Coins"))
			return if remaining == 0
				then "ДОСТУПЕН СЛЕД: " .. trail.Name .. " — загляни в коллекцию."
				else "СЛЕДУЮЩАЯ ЦЕЛЬ: "
					.. trail.Name
					.. " — ещё "
					.. remaining
					.. " монет."
		end
	end
	return "КОЛЛЕКЦИЯ СОБРАНА · Твой рекорд за сессию: "
		.. best
		.. " очков. Цель — пройти 6 из 6."
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
	local result = hints.Results[str(player, "RunResult", "None")] or hints.Results.None
	local resultReady = player:GetAttribute("ResultReady") == true
	resultsPanel.Heading.Text = if resultReady then result.Title else "ЗАБЕГ ЗАВЕРШЁН"
	resultsPanel.Summary.Text = if resultReady
		then result.Detail
		else "Твой следующий забег начнётся вместе со всеми."
	resultsPanel.Personal.Text = string.format(
		"%d / 6 ПРОЙДЕНО  ·  %d ОЧКОВ  ·  %d ЗАРЯДОВ",
		num(player, "RunSurvived"),
		num(player, "RunScore"),
		num(player, "RunStars")
	)
	resultsPanel.Rewards.Text = string.format(
		"+%d МОНЕТ  ·  +%d ОПЫТА",
		num(player, "RunCoinsEarned"),
		num(player, "RunXPEarned")
	)
	resultsPanel.Goal.Text = nextGoal()
	resultsPanel.Heading.TextColor3 = if resultReady and str(player, "RunResult", "None") == "Won"
		then green
		else yellow
	renderOutcomes()
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
		and not compactPlay()
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
	timer.Countdown.Text = if remaining >= 0
		then tostring(remaining) .. (if compactPlay() then "с" else "")
		else "—"
	timer.UnitLabel.Text = if remaining < 0 then "ЖДЁМ" else "СЕК"
	resultsPanel.Next.Text = if remaining >= 0
		then string.format(
			"НОВЫЙ ЗАБЕГ ЧЕРЕЗ %d СЕК · «Лаборатория» — сделать перерыв",
			remaining
		)
		else "Следующий забег готовится…"
end

local function renderVotes()
	local acknowledged = player:GetAttribute("VotedMode")
	selectedVote = nil
	for _, mode in modes do
		local button = votePanel.Cards[mode.Id] :: TextButton
		local selected = acknowledged == mode.Id
		if selected then
			selectedVote = mode.Id
		end
		button.Text = string.format(
			"%s%s\n%s\n%d ГОЛОСОВ",
			if selected then "✓ " else "",
			mode.Name,
			mode.Detail,
			num(state, "Votes" .. mode.Id)
		)
		button.BackgroundColor3 = if selected then mode.Color else Color3.fromRGB(39, 56, 78)
		button.TextColor3 = if selected then Color3.fromRGB(18, 30, 50) else white
	end
end

local applyComposition: () -> ()

local function renderState()
	local exploring = player:GetAttribute("LobbyOnly") == true
	local previousPhase = phase
	local previousCompact = gui:GetAttribute("CompactPlayHUD") == true
	phase = str(state, "Phase", "Waiting")
	deadline = num(state, "PhaseEndsAt")
	local index = num(state, "RuleIndex")
	local round = num(state, "Round")
	local ruleKey = tostring(round) .. ":" .. tostring(index)
	if
		phase == "Rule"
		and player:GetAttribute("InRound") == true
		and index > 0
		and ruleKey ~= lastRuleKey
	then
		lastRuleKey = ruleKey
		onboardingRules += 1
	end
	local hazardStage = str(state, "HazardStage", "")
	column.PhaseLabel.Text = if phase == "Rule"
		then (if hazardStage == "Warning"
			then "ПРИГОТОВЬСЯ · ОПАСНОСТЬ СКОРО"
			elseif hazardStage == "Recovery" then "ПЕРЕДЫШКА · СЛЕДИ ЗА ПОЛЕМ"
			else "ИСПЫТАНИЕ АКТИВНО")
		else phaseNames[phase] or "КОМНАТА ПРАВИЛ"
	column.RuleLabel.Text = str(state, "RuleName", "КОМНАТА ПРОСЫПАЕТСЯ")
	column.Instruction.Text = str(
		state,
		"Instruction",
		"Читай правило. Двигайся. Попробуй ещё раз!"
	)
	local color = state:GetAttribute("Accent")
	local accent = if typeof(color) == "Color3" then color else cyan
	panel.AccentBar.BackgroundColor3 = accent
	timer.BackgroundColor3 = accent
	root.Visible = player:GetAttribute("EntryChoiceMade") == true and str(gui, "StationModal", "") == ""
	panel.Visible = not exploring and phase ~= "Results"
	root.TrialProgress.Visible = not exploring and phase ~= "Results"
	renderOutcomes()
	teamPanel.Visible = not exploring
		and phase == "Rule"
		and player:GetAttribute("Eliminated") ~= true
		and str(state, "RuleId", "") == "ReactorRush"
	local charge = num(state, "TeamCharge")
	local goal = num(state, "TeamGoal", 1)
	teamPanel.ChargeLabel.Text =
		string.format("ОБЩАЯ ЭНЕРГИЯ  %d / %d  •  СОБИРАЕМ ВМЕСТЕ", charge, goal)
	fillBar(teamPanel.Meter.Fill, charge / math.max(1, goal))
	votePanel.Visible = not exploring and phase == "Voting"
	resultsPanel.Visible = not exploring and phase == "Results"

	collection.SetPhase(if exploring then "Lobby" else phase)
	characters.SetPhase(if exploring then "Lobby" else phase)
	renderVotes()
	renderPlayer()
	renderControls()
	shownSecond = -2
	renderClock()
	if phase ~= previousPhase or previousCompact ~= compactPlay() then
		applyComposition()
	end
	if
		phase == "Voting"
		and not exploring
		and previousPhase ~= phase
		and not collection.IsOpen()
		and root.Visible
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
	-- Restore the desktop/menu composition before applying the independent compact play layout.
	header.Visible = true
	root.TrialProgress.Visible = player:GetAttribute("LobbyOnly") ~= true and phase ~= "Results"
	panel.BackgroundTransparency = 0.04
	column.Position = UDim2.fromOffset(16, 0)
	column.RuleLabel.Visible = true
	column.Instruction.Text =
		str(state, "Instruction", "Читай правило и следи за комнатой")
	column.Instruction.TextSize = 17
	instructionBounds.MaxTextSize = 17
	column.Instruction.TextWrapped = true
	timer.BackgroundTransparency = 0
	timer.Countdown.Position = UDim2.fromOffset(4, 4)
	timer.Countdown.TextColor3 = Color3.fromRGB(18, 30, 50)
	timer.Countdown.TextSize = 37
	countdownBounds.MaxTextSize = 37
	timer.UnitLabel.Visible = true
	healthBar.Size = UDim2.fromOffset(160, 4)
	teamPanel.BackgroundTransparency = 0
	teamPanel.Meter.Visible = true
	root.FeedbackToast.Size = UDim2.new(1, -48, 0, 38)
	root.FeedbackToast.BackgroundTransparency = 0.08
	root.FeedbackToast.Message.Position = UDim2.fromOffset(10, 4)
	root.FeedbackToast.Message.Size = UDim2.new(1, -20, 1, -8)
	root.FeedbackToast.Message.TextStrokeTransparency = 1
	root.SpectateNext.Size = UDim2.fromOffset(206, 44)
	actions.Visible = str(gui, "StationModal", "") == "" and not compactPlay()
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
	root.TrialProgress.Position = UDim2.new(0.5, 0, 0, top + height + 5)
	status.Position = UDim2.new(0.5, 0, 0, top + height + 24)
	healthBar.Position = UDim2.new(0.5, 0, 0, top + height + 49)
	controls.Position = UDim2.new(0.5, 0, 0, top + height + 57)
	teamPanel.Position = UDim2.new(0.5, 0, 0, top + height + (if compactFinale then 48 else 57))
	teamPanel.Size = UDim2.new(1, -48, 0, if compactFinale then 25 else 38)
	teamPanel.ChargeLabel.Position = UDim2.fromOffset(8, if compactFinale then 1 else 2)
	teamPanel.ChargeLabel.Size = UDim2.new(1, -16, 0, if compactFinale then 16 else 22)
	teamPanel.ChargeLabel.TextSize = if compactFinale then 12 else 13
	teamPanel.Meter.Position = UDim2.new(0, 8, 1, if compactFinale then -6 else -10)
	teamPanel.Meter.Size = UDim2.new(1, -16, 0, if compactFinale then 4 else 5)
	votePanel.Position = UDim2.new(
		0.5,
		0,
		0,
		if extremeMenu
			then 86
			elseif tinyMenu then 92
			elseif compactMenu then 102
			elseif short then 125
			else math.max(220, root.AbsoluteSize.Y * 0.43)
	)
	resultsPanel.Position = votePanel.Position
	local menuHeight = if extremeMenu
		then math.min(106, root.AbsoluteSize.Y - 64 - 86)
		elseif tinyMenu then 106
		elseif compactMenu then 114
		elseif short then 132
		else 154
	votePanel.Size = UDim2.new(1, -32, 0, menuHeight)
	votePanel.Cards.Size = UDim2.new(1, -20, 0, if compactMenu then 54 elseif short then 62 else 78)
	votePanel.Heading.Size = UDim2.new(1, -24, 0, if tinyMenu then 20 elseif short then 23 else 28)
	votePanel.Cards.Position =
		UDim2.fromOffset(10, if tinyMenu then 28 elseif compactMenu then 30 elseif short then 33 else 39)
	votePanel.Hint.Size = UDim2.new(1, -20, 0, if tinyMenu then 16 elseif compactMenu then 18 else 25)
	votePanel.Hint.Position = UDim2.new(0, 10, 1, if tinyMenu then -20 elseif compactMenu then -23 else -29)
	votePanel.Hint.Visible = not extremeMenu
	local resultTop = if root.AbsoluteSize.Y < 300 then 28 else 46
	local resultHeight = math.min(270, math.max(176, root.AbsoluteSize.Y - resultTop - 70))
	local compactResult = resultHeight < 225
	resultsPanel.Position = UDim2.new(0.5, 0, 0, resultTop)
	resultsPanel.Size = UDim2.new(1, -36, 0, resultHeight)
	resultsPanel.Heading.Position = UDim2.fromOffset(14, 8)
	resultsPanel.Heading.Size = UDim2.new(1, -28, 0, 28)
	resultsPanel.Summary.Position = UDim2.fromOffset(14, 39)
	resultsPanel.Summary.Size = UDim2.new(1, -28, 0, if compactResult then 30 else 38)
	resultsPanel.Personal.Position = UDim2.fromOffset(14, if compactResult then 73 else 82)
	resultsPanel.Personal.Size = UDim2.new(1, -28, 0, 21)
	resultsPanel.Rewards.Position = UDim2.fromOffset(14, if compactResult then 96 else 107)
	resultsPanel.Rewards.Size = UDim2.new(1, -28, 0, 22)
	resultsPanel.Trials.Position = UDim2.fromOffset(14, if compactResult then 122 else 136)
	resultsPanel.Goal.Visible = resultHeight >= 210
	resultsPanel.Goal.Position = UDim2.fromOffset(14, if compactResult then 147 else 168)
	resultsPanel.Goal.Size = UDim2.new(1, -28, 0, if compactResult then 34 else 42)
	resultsPanel.Next.Visible = true
	root.FeedbackToast.Position = UDim2.new(0.5, 0, 0, top + height + (if teamPanel.Visible then 111 else 86))
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
	gui:SetAttribute("ReducedMotion", value)
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
		and player:GetAttribute("LobbyOnly") ~= true
		and not collection.IsOpen()
		and root.Visible
		and not GuiService.MenuIsOpen
		and string.find(input.Name, "Gamepad")
		and not GuiService.SelectedObject
	then
		GuiService.SelectedObject = votePanel.Cards[selectedVote or "Balanced"]
	end
end)
connect(root:GetPropertyChangedSignal("AbsoluteSize"), applyComposition)
connect(gui:GetAttributeChangedSignal("StationModal"), renderState)
connect(root.SpectateNext:GetPropertyChangedSignal("Visible"), applyComposition)
connect(player.AttributeChanged, function(name)
	if name == "LobbyOnly" then
		renderState()
	end
	renderPlayer()
	if name == "VotedMode" then
		renderVotes()
	end
	if name == "InRound" or name == "Eliminated" or name == "EntryChoiceMade" then
		renderState()
		renderControls()
	end
end)
connect(ProximityPromptService.PromptTriggered, function(prompt, who)
	if who and who ~= player then
		return
	end
	if player:GetAttribute("InRound") == true then
		return
	end
	local parent = prompt.Parent
	if
		parent
		and parent:IsDescendantOf(Workspace:WaitForChild("Arena"))
		and parent:GetAttribute("StationAction") == "Collection"
	then
		collection.SetPhase("Lobby")
		collection.Open()
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
	feedback.Destroy()
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
