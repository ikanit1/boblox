--!strict
-- Server-owned state drives this interface. Input sends intents only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CollectionPanel = require(script.Parent:WaitForChild("CollectionPanel"))
local CharacterPresentation = require(script.Parent:WaitForChild("CharacterPresentation"))
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
local collection = CollectionPanel.new(root, player, profileRemote, economy)
local characters = CharacterPresentation.new(player, economy, root.SpectateNext)

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

local function connect(signal: RBXScriptSignal, callback)
	table.insert(connections, signal:Connect(callback))
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
	status.Visible = phase ~= "Voting" and phase ~= "Results"
	if player:GetAttribute("InRound") == true and phase == "Rule" then
		status.Text = string.format(
			"В ИГРЕ  •  ЗДОРОВЬЕ %d  •  ОЧКИ %d",
			math.ceil(health),
			points
		)
		status.TextColor3 = if health <= 35 then pink else white
	elseif player:GetAttribute("Eliminated") == true and phase == "Rule" then
		status.Text = "ВЕРНЁШЬСЯ В СЛЕДУЮЩЕМ ИСПЫТАНИИ  •  ОЧКИ " .. points
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
	healthBar.Visible = phase == "Rule" and player:GetAttribute("InRound") == true
	healthBar.Fill.BackgroundColor3 = if health <= 35 then pink else green
	fillBar(healthBar.Fill, health / math.max(1, maxHealth))
end

local function renderPlayer()
	-- Core chat can extend below the top-bar inset. Keep our brand out of that region.
	header.GameTitle.Visible = phase ~= "Rule" and root.AbsoluteSize.X >= 1000 and not short
	header.PersonalScore.Text =
		string.format("УР. %d  •  %d МОНЕТ", num(player, "Level", 1), num(player, "Coins"))
	resultsPanel.Personal.Text = string.format(
		"%d очков  •  %d / 6 испытаний  •  рекорд %d",
		num(player, "RunScore"),
		num(player, "RunSurvived"),
		best
	)
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
	controls.Visible = onboardingRules <= 1 and phase == "Rule" and str(state, "RuleId", "") ~= "ReactorRush"
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
end

local function renderVotes()
	for _, mode in modes do
		local button = votePanel.Cards[mode.Id] :: TextButton
		local selected = selectedVote == mode.Id
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

local function renderState()
	local previousPhase = phase
	phase = str(state, "Phase", "Waiting")
	deadline = num(state, "PhaseEndsAt")
	local index = num(state, "RuleIndex")
	local round = num(state, "Round")
	if phase == "Voting" and previousPhase ~= "Voting" then
		selectedVote = nil
	end
	local ruleKey = tostring(round) .. ":" .. tostring(index)
	if phase == "Rule" and ruleKey ~= lastRuleKey then
		lastRuleKey = ruleKey
		onboardingRules += 1
	end
	column.PhaseLabel.Text = phaseNames[phase] or "КОМНАТА ПРАВИЛ"
	column.RuleLabel.Text = str(state, "RuleName", "КОМНАТА ПРОСЫПАЕТСЯ")
	column.Instruction.Text = str(
		state,
		"Instruction",
		"Читай правило. Двигайся. Попробуй ещё раз!"
	)
	column.RoundLabel.Text = string.format(
		"ЗАБЕГ %d  •  ИСПЫТАНИЕ %d / %d  •  ОЧКИ %d",
		round,
		index,
		num(state, "RuleCount", 6),
		num(player, "RunScore")
	)
	local color = state:GetAttribute("Accent")
	local accent = if typeof(color) == "Color3" then color else cyan
	panel.AccentBar.BackgroundColor3 = accent
	timer.BackgroundColor3 = accent
	for step = 1, 6 do
		root.TrialProgress["Step" .. step].BackgroundColor3 = if step < index or phase == "Results"
			then green
			elseif step == index then accent
			else Color3.fromRGB(54, 70, 91)
	end
	teamPanel.Visible = phase == "Rule" and str(state, "RuleId", "") == "ReactorRush"
	local charge = num(state, "TeamCharge")
	local goal = num(state, "TeamGoal", 1)
	teamPanel.ChargeLabel.Text =
		string.format("ОБЩАЯ ЭНЕРГИЯ  %d / %d  •  СОБИРАЕМ ВМЕСТЕ", charge, goal)
	fillBar(teamPanel.Meter.Fill, charge / math.max(1, goal))
	votePanel.Visible = phase == "Voting"
	resultsPanel.Visible = phase == "Results"
	resultsPanel.Heading.Text = if state:GetAttribute("FinaleSuccess") == true
		then "РЕАКТОР ЗАРЯЖЕН!"
		else "ЭКСПЕРИМЕНТ ЗАВЕРШЁН"
	resultsPanel.Summary.Text = str(
		state,
		"ResultsText",
		"Каждая попытка помогает лучше узнать комнату."
	)
	collection.SetPhase(phase)
	characters.SetPhase(phase)
	renderVotes()
	renderPlayer()
	renderControls()
	shownSecond = -2
	renderClock()
	if phase == "Voting" and previousPhase ~= phase and string.find(lastInput.Name, "Gamepad") then
		GuiService.SelectedObject = votePanel.Cards.Balanced
	elseif
		phase ~= "Voting"
		and GuiService.SelectedObject
		and GuiService.SelectedObject:IsDescendantOf(votePanel)
	then
		GuiService.SelectedObject = nil
	end
end

local function applyComposition()
	short = root.AbsoluteSize.Y < 470
	local narrow = root.AbsoluteSize.X < 600
	local height = if short then 86 else 116
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
	column.PhaseLabel.Position = UDim2.fromOffset(0, if short then 4 else 8)
	column.PhaseLabel.Size = UDim2.new(1, 0, 0, if short then 13 else 16)
	column.RuleLabel.Position = UDim2.fromOffset(0, if short then 19 else 26)
	column.RuleLabel.Size = UDim2.new(1, 0, 0, if short then 24 else 29)
	column.Instruction.Position = UDim2.fromOffset(0, if short then 45 else 57)
	column.Instruction.Size = UDim2.new(1, 0, 0, if short then 35 else 32)
	column.RoundLabel.Visible = not short
	timer.Size = UDim2.fromOffset(if narrow then 56 else 64, if short then 64 else 74)
	timer.Position = UDim2.new(1, -12, 0.5, 0)
	timer.Countdown.Size = UDim2.new(1, -8, 0, if short then 40 else 48)
	root.TrialProgress.Position = UDim2.new(0.5, 0, 0, top + height + 5)
	status.Position = UDim2.new(0.5, 0, 0, top + height + 13)
	healthBar.Position = UDim2.new(0.5, 0, 0, top + height + 39)
	controls.Position = UDim2.new(0.5, 0, 0, top + height + 47)
	teamPanel.Position = UDim2.new(0.5, 0, 0, top + height + 47)
	votePanel.Position =
		UDim2.new(0.5, 0, 0, if short then 125 else math.max(220, root.AbsoluteSize.Y * 0.43))
	resultsPanel.Position = votePanel.Position
	votePanel.Size = UDim2.new(1, -32, 0, if short then 132 else 154)
	votePanel.Cards.Size = UDim2.new(1, -20, 0, if short then 62 else 78)
	votePanel.Heading.Size = UDim2.new(1, -24, 0, if short then 23 else 28)
	votePanel.Cards.Position = UDim2.fromOffset(10, if short then 33 else 39)
	resultsPanel.Size = UDim2.new(1, -36, 0, if short then 132 else 148)
	resultsPanel.Heading.Size = UDim2.new(1, -28, 0, if short then 25 else 30)
	resultsPanel.Summary.Position = UDim2.fromOffset(14, if short then 35 else 43)
	resultsPanel.Summary.Size = UDim2.new(1, -28, 0, if short then 37 else 46)
	resultsPanel.Personal.Position = UDim2.fromOffset(14, if short then 76 else 92)
	actions.Size = UDim2.fromOffset(if narrow then 280 else 300, 36)
	actions.Collection.Size = UDim2.fromOffset(if narrow then 148 else 160, 36)
	actions.Motion.Position = UDim2.fromOffset(if narrow then 156 else 168, 0)
	actions.Motion.Size = UDim2.fromOffset(if narrow then 124 else 132, 36)
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
		if phase == "Voting" and not collection.IsOpen() and os.clock() - lastVoteAt >= 0.3 then
			lastVoteAt = os.clock()
			selectedVote = mode.Id
			voteRemote:FireServer(mode.Id)
			renderVotes()
		end
	end)
end

actions.Collection.NextSelectionRight = actions.Motion
actions.Motion.NextSelectionLeft = actions.Collection
connect(actions.Motion.Activated, function()
	setMotion(not reducedMotion)
end)
connect(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"), function()
	setMotion(GuiService.ReducedMotionEnabled)
end)
connect(UserInputService.LastInputTypeChanged, function(input)
	lastInput = input
	renderControls()
end)
connect(root:GetPropertyChangedSignal("AbsoluteSize"), applyComposition)
connect(player.AttributeChanged, renderPlayer)
local pending = false
connect(state.AttributeChanged, function()
	if not pending then
		pending = true
		task.defer(function()
			pending = false
			renderState()
		end)
	end
end)

local function bindCharacter(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") and player.Character == character then
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
	local stats = player:WaitForChild("leaderstats")
	local record = stats:WaitForChild("Best") :: IntValue
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
	collection.Destroy()
	characters.Destroy()
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
