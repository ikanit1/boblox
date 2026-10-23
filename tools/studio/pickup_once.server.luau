-- COMPONENT/MOCK only: production ArenaRules.Run; isolated arena/bodies and mock AwardStar.
-- Install in a fresh native Studio server with Main disabled and at least two players.
-- No movement, ProfileService, economy, networking, or natural-play acceptance is claimed.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsServer(), "Studio server only")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Http = game:GetService("HttpService")
local modules = assert(game.ServerScriptService:FindFirstChild("RuleRoomServer"), "Modules missing")
local main = assert(modules:FindFirstChild("Main"), "Main missing")
assert(not main.Enabled, "Production Main must be disabled before this component fixture")
assert(not RS:FindFirstChild("QARuleCoverage"), "Another rule fixture is installed")
assert(not RS:FindFirstChild("QALifecycle"), "Another lifecycle fixture is installed")
assert(not RS:FindFirstChild("QAPickupOnce"), "Pickup fixture already installed")
local participants = Players:GetPlayers()
assert(#participants >= 2, "Two native players are required as identity keys only")
table.sort(participants, function(a, b)
	return a.UserId < b.UserId
end)
local identities = { participants[1], participants[2] }
local arena = assert(workspace:FindFirstChild("Arena"), "Authored arena missing")
local productionState = assert(RS:FindFirstChild("RuleRoomState"), "Production state missing")
local ArenaRules = require(modules.ArenaRules)
local started = os.clock()
local gravityBefore = workspace.Gravity
local stateBefore = productionState:GetAttributes()
local playerBefore, geometryBefore = {}, {}
for _, player in participants do
	playerBefore[player] = { character = player.Character, attributes = player:GetAttributes() }
end
for _, item in arena:GetDescendants() do
	local properties = nil
	if item:IsA("BasePart") then
		properties = {
			CFrame = item.CFrame,
			Size = item.Size,
			Color = item.Color,
			Material = item.Material,
			Transparency = item.Transparency,
			CanCollide = item.CanCollide,
			CanQuery = item.CanQuery,
			CanTouch = item.CanTouch,
		}
	elseif item:IsA("SurfaceGui") then
		properties = { Enabled = item.Enabled }
	elseif item:IsA("TextLabel") then
		properties = { Text = item.Text }
	end
	if properties then
		geometryBefore[item] = properties
	end
end
local originalEffects = arena:FindFirstChild("RuleEffects")
local originalEffectCount = if originalEffects then #originalEffects:GetDescendants() else 0
local report = Instance.new("Folder")
report.Name = "QAPickupOnce"
report:SetAttribute("Complete", false)
report:SetAttribute("Scope", "COMPONENT/MOCK: production collector; isolated bodies; mock AwardStar")
report:SetAttribute("NaturalMovementAcceptance", false)
report:SetAttribute("ProfileAwardAcceptance", false)
report.Parent = RS
local resultValue = Instance.new("StringValue")
resultValue.Name = "ResultsJSON"
resultValue.Parent = report
local container, world
local cases, cleanupErrors = {}, {}
local function check(condition, message)
	assert(condition, message)
end
local function equalAttributes(before, current)
	for name, value in before do
		if current[name] ~= value then
			return false
		end
	end
	for name in current do
		if before[name] == nil then
			return false
		end
	end
	return true
end
local ok, failure = xpcall(function()
	container = Instance.new("Folder")
	container.Name = "QAPickupOnceIsolated"
	container.Parent = ServerStorage
	local clone = arena:Clone()
	clone.Name = "ArenaClone"
	for _, item in clone:GetDescendants() do
		check(not item:IsA("BaseScript"), "Arena clone must not contain executable scripts")
	end
	clone.Parent = container
	world = ArenaRules.new(clone)
	local bodies = {}
	for index = 1, 2 do
		local model = Instance.new("Model")
		model.Name = "ProxyBody" .. index
		model.Parent = container
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = model
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Anchored = true
		root.CanCollide, root.CanTouch, root.CanQuery = false, false, false
		root.Parent = model
		bodies[index] = { humanoid = humanoid, root = root }
	end
	for _, ruleId in { "LowGravity", "RedLight", "ReactorRush" } do
		for _, rejectFirst in { false, true } do
			world.Restore()
			local state = Instance.new("Folder")
			state.Name = "IsolatedState"
			state.Parent = container
			local result = {
				rule = ruleId,
				mode = if rejectFirst then "reject_first_accept_second" else "accept_first",
				attempts = { 0, 0 },
				accepted = { 0, 0 },
				repeatedUpdates = 12,
				proxyIdentities = { identities[1].UserId, identities[2].UserId },
				time = "Synthetic update elapsed 0..0.6; no task.wait or native body movement",
			}
			table.insert(cases, result)
			for _, body in bodies do
				body.humanoid.Health = 100
				body.root.Position = Vector3.new(0, 100, 0)
			end
			local tested = false
			local roster = {
				AliveCount = function()
					return 2
				end,
				ForEachAlive = function(callback)
					for index, player in identities do
						callback(player, bodies[index].humanoid, bodies[index].root)
					end
				end,
				AwardStar = function(player)
					local index = if player == identities[1] then 1 else 2
					check(player == identities[index], "Unexpected player identity")
					result.attempts[index] += 1
					if rejectFirst and index == 1 then
						return false
					end
					result.accepted[index] += 1
					return true
				end,
			}
			local completed = world.Run(ruleId, {
				roster = roster,
				state = state,
				waitFor = function(_, update)
					if not update then
						return true
					end
					check(not tested, "Fixture must stop after its first pickup update phase")
					tested = true
					local prefix = if ruleId == "ReactorRush" then "Energy" else "Star"
					local pickups = {}
					for _, part in clone.RuleEffects:GetChildren() do
						if part:IsA("BasePart") and string.sub(part.Name, 1, #prefix) == prefix then
							table.insert(pickups, part)
						end
					end
					table.sort(pickups, function(a, b)
						return a.Name < b.Name
					end)
					check(#pickups > 0 and #pickups <= 36, "Expected bounded production pickups")
					local target = pickups[1]
					local oldPosition = target.Position
					result.spawnedPickups, result.pickupName = #pickups, target.Name
					-- RedLight may randomly place multiple pickups on one tile. Separate the other
					-- real pickups on this isolated clone so this test concerns exactly one object.
					for index = 2, #pickups do
						pickups[index].Position = Vector3.new(10000 + index * 20, 100, 10000)
					end
					result.otherPickupsRelocated = #pickups - 1
					for _, body in bodies do
						body.root.Position = oldPosition
					end
					update(0, 0.05)
					check(target.Parent == nil, "Accepted pickup must be destroyed")
					check(result.accepted[1] + result.accepted[2] == 1, "Exactly one accepted award")
					check(result.attempts[1] == 1, "First candidate must be evaluated once")
					check(result.attempts[2] == (if rejectFirst then 1 else 0), "Second candidate policy")
					check(result.accepted[1] == (if rejectFirst then 0 else 1), "First candidate result")
					check(result.accepted[2] == (if rejectFirst then 1 else 0), "Second candidate result")
					for frame = 1, result.repeatedUpdates do
						update(frame * 0.05, 0.05)
					end
					check(result.accepted[1] + result.accepted[2] == 1, "No duplicate accepted awards")
					check(result.attempts[1] == 1, "Destroyed pickup cannot retry first candidate")
					check(result.attempts[2] == (if rejectFirst then 1 else 0), "No retry after removal")
					check(target.Parent == nil, "Pickup remains destroyed after repeated updates")
					result.pickupDestroyed = true
					result.teamCharge = state:GetAttribute("TeamCharge")
					if ruleId == "ReactorRush" then
						check(result.teamCharge == 1, "Team charge must advance exactly once")
					end
					return false -- Deliberate bounded component stop, not a completed gameplay trial.
				end,
			})
			check(tested and completed == false, "Pickup update ran and fixture stopped the trial")
			result.passed = true
			result.trialCompleted = completed
			world.Restore()
			state:Destroy()
		end
	end
end, debug.traceback)
-- Always restore the global gravity and destroy isolated world state, including after assertion failure.
if world then
	local restored, problem = pcall(world.Destroy)
	if not restored then
		table.insert(cleanupErrors, tostring(problem))
	end
end
workspace.Gravity = gravityBefore
if container then
	container:Destroy()
end
local cleanupOK, cleanupFailure = pcall(function()
	check(workspace.Gravity == gravityBefore, "Global gravity restored")
	check(not container or container.Parent == nil, "Isolated instances removed")
	check(main.Enabled == false, "Main remains disabled")
	check(equalAttributes(stateBefore, productionState:GetAttributes()), "Production state unchanged")
	for player, before in playerBefore do
		check(player.Character == before.character, "Native character identity unchanged")
		check(
			equalAttributes(before.attributes, player:GetAttributes()),
			"Native player attributes unchanged"
		)
	end
	for item, properties in geometryBefore do
		check(item:IsDescendantOf(arena), "Original arena object preserved")
		for property, value in properties do
			check(item[property] == value, "Original arena property changed: " .. property)
		end
	end
	check(arena:FindFirstChild("RuleEffects") == originalEffects, "Original effects folder preserved")
	check(
		not originalEffects or #originalEffects:GetDescendants() == originalEffectCount,
		"Original effects preserved"
	)
end)
if not cleanupOK then
	table.insert(cleanupErrors, tostring(cleanupFailure))
end
local passedCases = 0
for _, result in cases do
	if result.passed then
		passedCases += 1
	end
end
local passed = ok and passedCases == 6 and #cleanupErrors == 0
resultValue.Value = Http:JSONEncode({
	scope = report:GetAttribute("Scope"),
	passed = passed,
	cases = cases,
	passedCases = passedCases,
	expectedCases = 6,
	cleanupPassed = #cleanupErrors == 0,
	cleanupErrors = cleanupErrors,
	error = if ok then nil else tostring(failure),
	durationSeconds = os.clock() - started,
	limits = "No ProfileService/economy, movement, native race timing, network or full-trial acceptance",
})
report:SetAttribute("Passed", passed)
report:SetAttribute("CasesPassed", passedCases)
report:SetAttribute("CleanupPassed", #cleanupErrors == 0)
report:SetAttribute("Status", if passed then "PASS_COMPONENT_MOCK" else "FAIL_COMPONENT_MOCK")
report:SetAttribute("DurationSeconds", os.clock() - started)
report:SetAttribute("Complete", true)
