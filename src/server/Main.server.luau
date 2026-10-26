--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("RuleRoomShared")
local Config = require(Shared:WaitForChild("GameConfig"))
local RuleDeck = require(Shared:WaitForChild("RuleDeck"))
local ArenaRules = require(script.Parent.ArenaRules)
local PlayerRoster = require(script.Parent.PlayerRoster)
local ProfileService = require(script.Parent.ProfileService)
local state = ReplicatedStorage:WaitForChild("RuleRoomState") :: Folder
local vote = ReplicatedStorage:WaitForChild("RuleRoomRemotes"):WaitForChild("Vote") :: RemoteEvent

local initialAttributes = {
	Phase = "Waiting",
	RuleId = "",
	RuleName = "ДОБРО ПОЖАЛОВАТЬ",
	Instruction = "Шесть испытаний. После поражения вернёшься в следующем!",
	PhaseEndsAt = 0,
	Round = 0,
	RuleIndex = 0,
	RuleCount = Config.RuleCount,
	SafeColor = "",
	Accent = Color3.fromRGB(122, 169, 255),
	ModeId = "Balanced",
	VotesBalanced = 0,
	VotesReflex = 0,
	VotesCosmic = 0,
	TeamCharge = 0,
	TeamGoal = 0,
	FinaleSuccess = false,
	ResultsText = "",
	AliveCount = 0,
}
for name, value in initialAttributes do
	state:SetAttribute(name, value)
end
local arena = Workspace:WaitForChild("Arena", 20)
assert(arena and arena:IsA("Model"), "Workspace.Arena must be the authored model")
local profiles = ProfileService.new()
local world = ArenaRules.new(arena)
local roster = PlayerRoster.new(world.LobbySpawn, profiles)
local running = true
local runNumber = 0
local rng = Random.new()
local votes: { [Player]: string } = {}
local lastVote: { [Player]: number } = {}
local respawnTime = Players.RespawnTime
Players.RespawnTime = 2

local function queuedCount(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("LobbyOnly") ~= true and player:GetAttribute("EntryChoiceMade") == true then
			count += 1
		end
	end
	return count
end

local function counts(): { [string]: number }
	local totals: { [string]: number } = { Balanced = 0, Reflex = 0, Cosmic = 0 }
	for player, mode in votes do
		if
			player.Parent == Players
			and player:GetAttribute("LobbyOnly") ~= true
			and player:GetAttribute("EntryChoiceMade") == true
			and player:GetAttribute("VotedMode") == mode
		then
			totals[mode] += 1
		end
	end
	return totals
end
local function publishVotes()
	for mode, count in counts() do
		state:SetAttribute("Votes" .. mode, count)
	end
end
local voteConnection = vote.OnServerEvent:Connect(function(player, mode)
	local now = os.clock()
	if now - (lastVote[player] or -math.huge) < Config.VoteCooldown then
		return
	end
	lastVote[player] = now
	if
		state:GetAttribute("Phase") ~= "Voting"
		or not RuleDeck.isMode(mode)
		or not profiles.IsReady(player)
		or player:GetAttribute("LobbyOnly") == true
		or player:GetAttribute("EntryChoiceMade") ~= true
	then
		return
	end
	votes[player] = mode
	player:SetAttribute("VotedMode", mode)
	publishVotes()
end)
local queueConnections: { [Player]: RBXScriptConnection } = {}
local function watchQueue(player: Player)
	queueConnections[player] = player:GetAttributeChangedSignal("LobbyOnly"):Connect(function()
		votes[player] = nil
		publishVotes()
	end)
end
for _, player in Players:GetPlayers() do
	watchQueue(player)
end
local joinConnection = Players.PlayerAdded:Connect(watchQueue)
local leaveConnection = Players.PlayerRemoving:Connect(function(player)
	if queueConnections[player] then
		queueConnections[player]:Disconnect()
		queueConnections[player] = nil
	end
	votes[player] = nil
	lastVote[player] = nil
	publishVotes()
end)

local function publish(phase: string, title: string, instruction: string)
	state:SetAttribute("RuleId", "")
	state:SetAttribute("RuleName", title)
	state:SetAttribute("Instruction", instruction)
	state:SetAttribute("SafeColor", "")
	state:SetAttribute("Accent", Color3.fromRGB(122, 169, 255))
	state:SetAttribute("PhaseEndsAt", 0)
	state:SetAttribute("AliveCount", roster.AliveCount())
	state:SetAttribute("Phase", phase)
end

local function waitFor(seconds: number, active: boolean, update: ((number, number) -> ())?): boolean
	local startedAt = Workspace:GetServerTimeNow()
	local deadline = startedAt + seconds
	local previousAt = startedAt
	state:SetAttribute("PhaseEndsAt", deadline)
	while running do
		local now = Workspace:GetServerTimeNow()
		if #Players:GetPlayers() == 0 then
			return false
		end
		if not active and queuedCount() == 0 then
			return false
		end
		if active then
			roster.CheckBoundaries()
			local alive = roster.AliveCount()
			if state:GetAttribute("AliveCount") ~= alive then
				state:SetAttribute("AliveCount", alive)
			end
			if alive == 0 then
				return false
			end
		end
		if now >= deadline then
			return true
		end
		if update then
			update(now - startedAt, now - previousAt)
		end
		previousAt = now
		task.wait(Config.StepSeconds)
	end
	return false
end

local function cleanup()
	if not running then
		return
	end
	running = false
	voteConnection:Disconnect()
	joinConnection:Disconnect()
	for _, connection in queueConnections do
		connection:Disconnect()
	end
	leaveConnection:Disconnect()
	world.Restore()
	roster.Destroy()
	Players.RespawnTime = respawnTime
	profiles.Destroy()
end
script.Destroying:Connect(cleanup)
game:BindToClose(cleanup)

local context: ArenaRules.RuleContext = {
	roster = roster,
	state = state,
	waitFor = function(seconds, update)
		return waitFor(seconds, true, update)
	end,
}

while running do
	world.Restore()
	roster.EndRound()
	if queuedCount() == 0 then
		publish(
			"Waiting",
			"ЛАБОРАТОРИЯ ОТКРЫТА",
			"Нажми «В испытания», когда будешь готов. Можно играть одному!"
		)
		repeat
			task.wait(0.25)
		until not running or queuedCount() > 0
		continue
	end
	roster.PrepareIntermission()
	table.clear(votes)
	publishVotes()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("VotedMode", "")
	end
	state:SetAttribute("RuleIndex", 0)
	state:SetAttribute("TeamCharge", 0)
	state:SetAttribute("TeamGoal", 0)
	state:SetAttribute("FinaleSuccess", false)
	state:SetAttribute("ResultsText", "")
	publish(
		"Voting",
		"ВЫБЕРИТЕ НАСТРОЕНИЕ КОМНАТЫ",
		"Микс, реакция или космос? Шесть испытаний и общий финал!"
	)
	if not waitFor(Config.VotingSeconds, false, nil) then
		continue
	end
	local seed = rng:NextInteger(1, 2147483646)
	local mode = RuleDeck.chooseMode(counts(), seed)
	state:SetAttribute("ModeId", mode)
	runNumber += 1
	state:SetAttribute("Round", runNumber)
	local deck = RuleDeck.draw(seed, mode)
	roster.BeginRun(deck)
	local completedRun = false
	local success, failure = xpcall(function()
		for index, ruleId in deck do
			if not running or queuedCount() == 0 then
				return
			end
			world.Restore()
			local entered = roster.StartRound(world.ArenaSpawn, index, ruleId)
			-- Joining/loading clients are never dropped into an already running hazard.
			while entered == 0 and running and queuedCount() > 0 do
				publish(
					"Waiting",
					"ГОТОВИМ ПЕРСОНАЖЕЙ",
					"Загрузка игрока. Испытание начнётся вместе со всеми."
				)
				task.wait(0.5)
				entered = roster.StartRound(world.ArenaSpawn, index, ruleId)
			end
			if not running or entered == 0 then
				return
			end
			local metadata = Config.Rules[ruleId]
			state:SetAttribute("RuleIndex", index)
			state:SetAttribute("RuleId", ruleId)
			state:SetAttribute("RuleName", metadata.Name)
			state:SetAttribute("SafeColor", "")
			state:SetAttribute("Accent", metadata.Accent)
			state:SetAttribute("AliveCount", entered)
			state:SetAttribute("Phase", "Rule")
			local completed = world.Run(ruleId, context)
			-- Check falls before restoring the floor, so it cannot rescue a lost player.
			roster.CheckBoundaries()
			local awarded = if completed then roster.AwardSurvivors(ruleId) else 0
			if ruleId == "ReactorRush" then
				state:SetAttribute(
					"FinaleSuccess",
					state:GetAttribute("FinaleSuccess") == true and awarded > 0
				)
			end
			world.Restore()
			roster.EndRound(index < #deck)
			if index < #deck then
				local nextName = Config.Rules[deck[index + 1]].Name
				publish(
					"Break",
					"ДАЛЬШЕ: " .. nextName,
					"Здоровье восстановится. Все возвращаются в следующее испытание!"
				)
				if not waitFor(Config.BreakSeconds, false, nil) then
					return
				end
			end
		end
		completedRun = true
	end, debug.traceback)
	world.Restore()
	roster.EndRound()
	if not running then
		break
	end
	local teamSuccess = success and completedRun and state:GetAttribute("FinaleSuccess") == true
	state:SetAttribute("FinaleSuccess", teamSuccess)
	local winners = roster.CompleteRun(teamSuccess, not success or not completedRun)
	if not success or not completedRun then
		if not success then
			warn("[RuleRoom] Run aborted and restored:\n" .. tostring(failure))
		end
		state:SetAttribute(
			"ResultsText",
			"Испытание остановлено. Все эффекты сброшены; начинаем новую игру."
		)
		publish("Results", "НОВАЯ ПОПЫТКА", "Комната перезагружается.")
	else
		local charged = (state:GetAttribute("TeamGoal") :: number) > 0
			and (state:GetAttribute("TeamCharge") :: number) >= (state:GetAttribute("TeamGoal") :: number)
		local result = if teamSuccess
			then "Реактор заряжен! Победителей: " .. winners .. "."
			elseif charged then "Заряд есть, но все выбыли."
			else "Реактору не хватило энергии. Собирайте заряды вместе!"
		state:SetAttribute(
			"ResultsText",
			result .. " Победа: 4 испытания + выжить в успешном финале."
		)
		publish(
			"Results",
			if teamSuccess then "КОМНАТА ПРОЙДЕНА!" else "ЕЩЁ ОДНА ПОПЫТКА?",
			result
		)
	end
	waitFor(Config.ResultsSeconds, false, nil)
end
