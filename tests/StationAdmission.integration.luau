--!strict
-- Production Station.server handlers with local adapters; not a native-client playtest.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local ProfileStatus = require("../src/shared/ProfileStatus")
local PracticeMath = require("../src/shared/PracticeMath")
local Vector3, CFrame = Roblox.Vector3, Roblox.CFrame
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local entry = { active = true, callback = callback }
			table.insert(callbacks, entry)
			return {
				Disconnect = function()
					entry.active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in callbacks do
				if entry.active then
					entry.callback(...)
				end
			end
		end,
		Count = function()
			local count = 0
			for _, entry in callbacks do
				if entry.active then
					count += 1
				end
			end
			return count
		end,
	}
end
local function object(children: any?)
	local result: any = children or {}
	local attributes = {}
	local attributeSignals = {}
	function result:WaitForChild(name)
		return assert(self[name], name)
	end
	function result:FindFirstChild(name)
		return self[name]
	end
	function result:GetAttribute(name)
		return attributes[name]
	end
	function result:SetAttribute(name, value)
		local previous = attributes[name]
		attributes[name] = value
		if previous ~= value and attributeSignals[name] then
			attributeSignals[name]:Fire()
		end
	end
	function result:GetAttributeChangedSignal(name)
		if not attributeSignals[name] then
			attributeSignals[name] = signal()
		end
		return attributeSignals[name]
	end
	return result
end

local clock = 0
local players = object({ PlayerAdded = signal(), PlayerRemoving = signal(), list = {} })
function players:GetPlayers()
	return table.clone(self.list)
end
local heartbeat, promptSignal, destroying = signal(), signal(), signal()
local remote = object({ OnServerEvent = signal() })
local course = object({ StartPad = object({ Position = Vector3.new(-50, 2, 70) }) })
for index = 1, 7 do
	course["Checkpoint" .. index] = {
		Position = Vector3.new(-50, 2, 70 + index * 5),
		Size = Vector3.new(12, 2, 12),
	}
end
local lobby = object({ Practice = course })
function course.StartPad:IsA(class)
	return class == "BasePart"
end
function course.StartPad:IsDescendantOf(parent)
	return parent == lobby
end
course.StartPad:SetAttribute("StationAction", "Practice")
local arena = object({ Lobby = lobby, LobbySpawn = { Position = Vector3.new(0, 2, 80) } })
local workspace = object({ Arena = arena })
function workspace:GetServerTimeNow()
	return clock
end
local replicated = object({
	RuleRoomShared = object({ PracticeMath = PracticeMath, ProfileStatus = ProfileStatus }),
	RuleRoomRemotes = object({ StationAction = remote }),
})
local services = {
	Players = players,
	ReplicatedStorage = replicated,
	Workspace = workspace,
	ProximityPromptService = { PromptTriggered = promptSignal },
	RunService = { Heartbeat = heartbeat },
}
local practiceCalls = {}
local duringPracticeInvoke: (() -> ())? = nil
local bridgeFailure = false
local practiceBridge = {}
function practiceBridge:IsA(class)
	return class == "BindableFunction"
end
function practiceBridge:Invoke(player, seconds)
	if bridgeFailure then
		error("simulated bridge failure")
	end
	table.insert(practiceCalls, { Player = player, Seconds = seconds })
	if duringPracticeInvoke then
		duringPracticeInvoke()
	end
	return true
end
local serverFolder = object({ RuleRoomRecordPractice = practiceBridge })
local warnings = {}
luau.load(fs.readFile("src/server/Station.server.luau"), {
	debugName = "PRODUCTION_Station",
	environment = {
		game = {
			GetService = function(_, name)
				return assert(services[name], name)
			end,
		},
		script = { Parent = serverFolder, Destroying = destroying },
		require = function(module)
			return module
		end,
		Vector3 = Vector3,
		Vector2 = Roblox.Vector2,
		CFrame = CFrame,
		Enum = { HumanoidRigType = { R6 = "R6" } },
		warn = function(message)
			table.insert(warnings, message)
		end,
		os = {
			clock = function()
				return clock
			end,
		},
	},
})()

local function addPlayer(name: string, savedBest: number?)
	local root = object({
		Position = Vector3.new(0, 4, 80),
		Size = Vector3.new(2, 2, 1),
		AssemblyLinearVelocity = Vector3.zero,
		AssemblyAngularVelocity = Vector3.zero,
	})
	function root:IsA(class)
		return class == "BasePart"
	end
	local humanoid = { Health = 100, RigType = "R15", HipHeight = 2, Died = signal() }
	local character = object({ HumanoidRootPart = root, Teleports = 0 })
	function character:FindFirstChildOfClass(class)
		return if class == "Humanoid" then humanoid else nil
	end
	function character:PivotTo(cf)
		self.Teleports += 1
		root.Position = cf.Position
	end
	local player = object({ Character = character, DisplayName = name })
	player:SetAttribute("InRound", false)
	player:SetAttribute("DataStatus", "Loading")
	player:SetAttribute("DataPersistent", false)
	player:SetAttribute("TemporaryPlayAccepted", false)
	player:SetAttribute("BestPracticeSeconds", savedBest)
	table.insert(players.list, player)
	players.PlayerAdded:Fire(player)
	return player, root, character, humanoid
end
local function send(player, action, consent, advance: number?)
	clock += advance or 0.5
	remote.OnServerEvent:Fire(player, action, consent)
end
local function step(seconds: number)
	clock += seconds
	heartbeat:Fire(seconds)
end
local function startPractice(player, root)
	root.Position = course.StartPad.Position + Vector3.new(0, 4, 0)
	clock += 0.5
	promptSignal:Fire({ Parent = course.StartPad, Enabled = true }, player)
	expect(player:GetAttribute("PracticeState") == "Running", "World prompt starts a server-owned attempt")
end
local function finishPractice(player, root)
	for index = 1, 7 do
		root.Position = course["Checkpoint" .. index].Position + Vector3.new(0, 4, 0)
		step(0.7)
		expect(player:GetAttribute("PracticeCheckpoint") == index, "Ordered checkpoint accepted")
	end
	expect(player:GetAttribute("PracticeState") == "Finished", "All seven checkpoints finish the attempt")
end

local player, root, character = addPlayer("Temporary")
expect(
	player:GetAttribute("LobbyOnly") and player:GetAttribute("EntryChoiceMade") == false,
	"Newcomer is not queued"
)
send(player, "Join", true)
expect(player:GetAttribute("LobbyOnly") == true, "Consent cannot bypass profile loading")
expect(player:GetAttribute("AnalyticsJoinIntent") == nil, "Rejected loading Join creates no repeat intent")
player:SetAttribute("DataStatus", "Session")
send(player, "Join", nil)
expect(
	player:GetAttribute("LobbyOnly") == true and player:GetAttribute("TemporaryPlayPrompt") == true,
	"Direct Join opens temporary choice instead of admitting"
)
for _, invalid in { "true", 1, {}, function() end } do
	send(player, "Join", invalid)
	expect(player:GetAttribute("TemporaryPlayAccepted") == false, "Malformed consent is rejected")
end
expect(player:GetAttribute("AnalyticsJoinIntent") == nil, "Malformed and unconsented Join create no intent")
send(player, "Join", true)
expect(player:GetAttribute("AnalyticsJoinIntent") == 1, "Accepted server Join publishes one intent sequence")
expect(
	player:GetAttribute("LobbyOnly") == false and player:GetAttribute("TemporaryPlayAccepted") == true,
	"Explicit temporary choice admits through production handler"
)
expect(
	player:GetAttribute("EntryChoiceMade") == true and player:GetAttribute("TemporaryPlayPrompt") == false,
	"Successful choice closes the prompt"
)
send(player, "Explore", nil)
expect(player:GetAttribute("AnalyticsJoinIntent") == 1, "Exploration is not an intention to play again")
send(player, "Join", nil)
expect(player:GetAttribute("LobbyOnly") == false, "Accepted temporary session can rejoin normally")
expect(player:GetAttribute("AnalyticsJoinIntent") == 2, "A later accepted Join advances the server sequence")

player:SetAttribute("InRound", true)
player:SetAttribute("DataStatus", "Unavailable")
player:SetAttribute("TemporaryPlayAccepted", false)
root.Position = Vector3.new(0, 4, 0)
local before = character.Teleports
clock += 0.11
heartbeat:Fire(0.11)
expect(
	character.Teleports == before and player:GetAttribute("TemporaryPlayPrompt") == false,
	"Lease loss never interrupts the active trial with a teleport/prompt"
)
player:SetAttribute("InRound", false)
clock += 0.11
heartbeat:Fire(0.11)
expect(
	player:GetAttribute("LobbyOnly") == true and player:GetAttribute("TemporaryPlayPrompt") == true,
	"Safe boundary removes unconsented fallback from queue"
)
expect(
	character.Teleports == before + 1 and root.Position.Z > 43,
	"Retained arena survivor returns to a usable lobby choice"
)
send(player, "Explore", nil)
expect(
	player:GetAttribute("LobbyOnly") == true and player:GetAttribute("TemporaryPlayPrompt") == false,
	"Explore dismisses warning without granting temporary admission"
)

local newcomer, newRoot = addPlayer("Busy")
newcomer:SetAttribute("DataStatus", "Busy")
local joinPart = object({ Position = newRoot.Position })
function joinPart:IsA(class)
	return class == "BasePart"
end
function joinPart:IsDescendantOf(parent)
	return parent == lobby
end
joinPart:SetAttribute("StationAction", "Join")
clock += 0.5
promptSignal:Fire({ Parent = joinPart, Enabled = true }, newcomer)
expect(
	newcomer:GetAttribute("LobbyOnly") == true and newcomer:GetAttribute("TemporaryPlayAccepted") == false,
	"Proximity Join cannot accept temporary mode"
)
send(newcomer, "Join", true, 0.05)
expect(newcomer:GetAttribute("LobbyOnly") == true, "Consent still obeys request cooldown")
newRoot.Position = Vector3.new(1000, 4, 80)
send(newcomer, "Join", true)
expect(newcomer:GetAttribute("LobbyOnly") == true, "Consent cannot bypass station bounds")
newRoot.Position = Vector3.new(0, 4, 80)
newcomer:SetAttribute("DataStatus", "Saved")
newcomer:SetAttribute("DataPersistent", true)
send(newcomer, "Join", nil)
expect(newcomer:GetAttribute("LobbyOnly") == false, "Saved profile joins without temporary consent")

local runner, runnerRoot = addPlayer("Practice", 20.5)
expect(runner:GetAttribute("PracticeBestSeconds") == 20.5, "Loaded profile seeds the compatible session best")
runnerRoot.Position = course.StartPad.Position + Vector3.new(0, 4, 0)
clock += 0.5
promptSignal:Fire({ Parent = course.StartPad, Enabled = true }, runner)
expect(
	runner:GetAttribute("PracticeState") ~= "Running"
		and runner:GetAttribute("EntryChoiceMade") == false
		and runner:GetAttribute("LobbyOnly") == true,
	"Profile loading rejects practice before starting an attempt or changing the entry choice"
)
expect(
	runner:GetAttribute("ActionMessage")
		== "Дождись загрузки прогресса, затем начни паркур.",
	"Rejected loading start explains when practice becomes available"
)
step(2)
expect(
	runner:GetAttribute("PracticeStartedAt") == nil
		and runner:GetAttribute("PracticeCheckpoint") == nil
		and #practiceCalls == 0,
	"Waiting after a rejected start creates no practice timer, checkpoints or record"
)
runner:SetAttribute("DataPersistent", true)
runner:SetAttribute("DataStatus", "Saved")
runner:SetAttribute("BestPracticeSeconds", 18.25)
expect(
	runner:GetAttribute("PracticeBestSeconds") == 18.25,
	"Later profile replication improves the session best"
)
runner:SetAttribute("BestPracticeSeconds", nil)
runner:SetAttribute("BestPracticeSeconds", 0 / 0)
runner:SetAttribute("BestPracticeSeconds", math.huge)
expect(
	runner:GetAttribute("PracticeBestSeconds") == 18.25,
	"Missing or malformed profile time never erases a valid best"
)
runner:SetAttribute("BestPracticeSeconds", 25)
expect(
	runner:GetAttribute("PracticeBestSeconds") == 18.25,
	"A slower profile update does not replace the session best"
)

startPractice(runner, runnerRoot)
runnerRoot.Position = course.Checkpoint7.Position + Vector3.new(0, 4, 0)
step(2)
expect(
	runner:GetAttribute("PracticeCheckpoint") == 0 and #practiceCalls == 0,
	"Skipping to the final platform cannot record practice"
)
startPractice(runner, runnerRoot)
duringPracticeInvoke = function()
	step(0.11)
	expect(#practiceCalls == 1, "Heartbeat during the bridge call cannot submit a duplicate finish")
end
finishPractice(runner, runnerRoot)
duringPracticeInvoke = nil
expect(
	#practiceCalls == 1
		and practiceCalls[1].Player == runner
		and practiceCalls[1].Seconds == runner:GetAttribute("PracticeLastSeconds")
		and practiceCalls[1].Seconds > 0,
	"Validated server finish calls RecordPractice with the actual player and measured time"
)
local sessionBest = runner:GetAttribute("PracticeBestSeconds")
runner:SetAttribute("BestPracticeSeconds", 12)
expect(
	runner:GetAttribute("PracticeBestSeconds") == sessionBest,
	"Late profile load preserves the faster completed run"
)
step(1)
expect(#practiceCalls == 1, "Completed attempts are not recorded again on later Heartbeats")

serverFolder.RuleRoomRecordPractice = nil
startPractice(runner, runnerRoot)
finishPractice(runner, runnerRoot)
expect(
	#practiceCalls == 1 and #warnings == 1 and runner:GetAttribute("PracticeBestSeconds") ~= nil,
	"Missing bridge retains the finished session result and reports one bounded warning"
)
serverFolder.RuleRoomRecordPractice = practiceBridge
bridgeFailure = true
startPractice(runner, runnerRoot)
finishPractice(runner, runnerRoot)
expect(#practiceCalls == 1 and #warnings == 1, "Bridge errors cannot break finish handling or flood warnings")
bridgeFailure = false

local late, lateRoot = addPlayer("LateProfile")
expect(late:GetAttribute("PracticeBestSeconds") == nil, "Absent profile record stays absent")
late:SetAttribute("BestPracticeSeconds", 9.75)
expect(
	late:GetAttribute("PracticeBestSeconds") == 9.75,
	"An asynchronously loaded profile initializes the best"
)
late:SetAttribute("DataStatus", "Session")
startPractice(late, lateRoot)
players.PlayerRemoving:Fire(late)
late:SetAttribute("BestPracticeSeconds", 8.25)
expect(late:GetAttribute("PracticeBestSeconds") == 9.75, "Leaving disconnects the profile record observer")

local warm, warmRoot, warmCharacter, warmHumanoid = addPlayer("Warmup", 8.5)
warm:SetAttribute("DataStatus", "Saved")
warm:SetAttribute("DataPersistent", true)
warm:SetAttribute("Coins", 42)
warm:SetAttribute("XP", 17)
warm:SetAttribute("Wins", 2)
warm:SetAttribute("PracticeLastSeconds", 10)
send(warm, "Join", nil)
warm:SetAttribute("VotedMode", "Cosmic")
local warmCalls, warmIntent = #practiceCalls, warm:GetAttribute("AnalyticsJoinIntent")
startPractice(warm, warmRoot)
expect(
	warm:GetAttribute("PracticeMode") == "Warmup" and warm:GetAttribute("PracticeGoal") == 2,
	"A queued player starts only the two-checkpoint warmup"
)
expect(
	warm:GetAttribute("LobbyOnly") == false
		and warm:GetAttribute("EntryChoiceMade") == true
		and warm:GetAttribute("VotedMode") == "Cosmic"
		and warm:GetAttribute("AnalyticsJoinIntent") == warmIntent,
	"Warmup preserves admission, vote and accepted Join intent without delaying the match"
)
expect(warmHumanoid.Died.Count() == 1, "An active attempt owns one death observer")
warmRoot.Position = course.Checkpoint2.Position + Vector3.new(0, 4, 6)
step(0.7)
expect(warm:GetAttribute("PracticeCheckpoint") == 0, "Warmup cannot skip the first landing")
for index = 1, 2 do
	warmRoot.Position = course["Checkpoint" .. index].Position + Vector3.new(0, 4, 0)
	step(0.7)
	expect(warm:GetAttribute("PracticeCheckpoint") == index, "Warmup accepts ordered stable landings")
end
expect(
	warm:GetAttribute("PracticeState") == "Finished" and warm:GetAttribute("LobbyOnly") == false,
	"Second landing completes warmup while the player stays queued"
)
local afterWarmFinish = warmCharacter.Teleports
step(2)
expect(
	#practiceCalls == warmCalls
		and warm:GetAttribute("PracticeBestSeconds") == 8.5
		and warm:GetAttribute("PracticeLastSeconds") == 10
		and warm:GetAttribute("Coins") == 42
		and warm:GetAttribute("XP") == 17
		and warm:GetAttribute("Wins") == 2,
	"Warmup changes no record, last course time, currency, XP or win"
)
expect(
	warmCharacter.Teleports == afterWarmFinish and warmHumanoid.Died.Count() == 0,
	"Warmup completion neither teleports nor leaves a death observer"
)

startPractice(warm, warmRoot)
local beforeAdmission = warmCharacter.Teleports
warmRoot.Position = Vector3.new(0, 5, 0)
warm:SetAttribute("InRound", true)
expect(
	warm:GetAttribute("PracticeState") == "Idle"
		and warm:GetAttribute("PracticeMode") == ""
		and warm:GetAttribute("PracticeGoal") == 0
		and warmHumanoid.Died.Count() == 0,
	"Admission immediately cancels warmup before the next Heartbeat"
)
step(1)
expect(
	warmCharacter.Teleports == beforeAdmission
		and warmRoot.Position == Vector3.new(0, 5, 0)
		and #practiceCalls == warmCalls,
	"Station never pulls an admitted character back from Main's arena position"
)
warm:SetAttribute("InRound", false)
startPractice(warm, warmRoot)
warmHumanoid.Health = 0
warmHumanoid.Died:Fire()
expect(
	warm:GetAttribute("PracticeState") == "Idle" and warmHumanoid.Died.Count() == 0,
	"Death cancels the current warmup synchronously and releases its observer"
)
warmHumanoid.Health = 100

startPractice(warm, warmRoot)
send(warm, "Explore", nil)
expect(
	warm:GetAttribute("LobbyOnly") == true and warm:GetAttribute("PracticeState") == "Idle",
	"Explicit Explore exits the queue and cancels warmup"
)
startPractice(warm, warmRoot)
expect(
	warm:GetAttribute("PracticeMode") == "Course" and warm:GetAttribute("PracticeGoal") == 7,
	"Exploration still starts the full record-bearing seven-checkpoint course"
)
finishPractice(warm, warmRoot)
expect(
	#practiceCalls == warmCalls + 1 and practiceCalls[#practiceCalls].Player == warm,
	"The full course still records exactly one server-measured finish after warmup"
)

warmRoot.Position = course.StartPad.Position + Vector3.new(0, 4, 0)
send(warm, "Join", nil)
startPractice(warm, warmRoot)
players.PlayerRemoving:Fire(warm)
expect(
	warmHumanoid.Died.Count() == 0 and warm:GetAttributeChangedSignal("InRound").Count() == 0,
	"Leaving disconnects warmup death and admission observers"
)
local leavingCalls, leavingTeleports = #practiceCalls, warmCharacter.Teleports
step(1)
expect(
	#practiceCalls == leavingCalls and warmCharacter.Teleports == leavingTeleports,
	"A removed attempt cannot finish or move the departing character"
)

destroying:Fire()
send(newcomer, "Explore", nil)
expect(newcomer:GetAttribute("LobbyOnly") == false, "Destroyed script disconnects admission handlers")
runner:SetAttribute("BestPracticeSeconds", 0.5)
expect(
	runner:GetAttribute("PracticeBestSeconds") == sessionBest,
	"Destroy disconnects remaining profile record observers"
)
print(
	"Station admission integration: "
		.. checks
		.. " checks passed (production handlers, local adapters; no Studio)"
)
