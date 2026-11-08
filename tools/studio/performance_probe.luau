--!strict
-- Install as a temporary Script (server) or LocalScript (client) in Studio Play only.
-- This fixture is not mapped into the shipped game. It never controls characters or uploads data.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "Performance probe is Studio-only")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local Metrics = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("BoundedMetrics"))
local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local client = RunService:IsClient()
local owner = if client
	then Players.LocalPlayer:WaitForChild("PlayerGui")
	else game:GetService("ServerStorage")
assert(
	not owner:FindFirstChild("RuleRoomPerformance"),
	"Export/remove the previous probe before starting another"
)
local report = Instance.new("Folder")
report.Name = "RuleRoomPerformance"
report:SetAttribute("Complete", false)
report:SetAttribute("Stop", false)
report.Parent = owner
local result = Instance.new("StringValue")
result.Name = "SummaryJSON"
result.Parent = report
local frames = Metrics.new(6000)
local memory = Metrics.new(1800)
local send = Metrics.new(1800)
local receive = Metrics.new(1800)
local checkpoints: { any } = {}
local checkpointCount = 0
local checkpointNext = 1
local missing: { [string]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local started = os.clock()
local requested = script:GetAttribute("DurationSeconds")
local duration = if typeof(requested) == "number" and requested == requested
	then math.clamp(requested, 15, 1800)
	else 120
local fingerprint = script:GetAttribute("SourceFingerprint")
local identity = if typeof(fingerprint) == "string"
		and #fingerprint == 64
		and string.match(fingerprint, "^%x+$")
	then fingerprint
	else "unverified"
local ended = false
local lastMetric, lastCheckpoint = -1, -30
local lastPhase = ""
local function readMetric(name: string, read: () -> number): number?
	local ok, value = pcall(read)
	if ok and typeof(value) == "number" and value == value and value >= 0 and value < math.huge then
		return value
	end
	missing[name] = true
	return nil
end
local function snapshot(now: number, phase: string, memoryMb: number?)
	checkpointCount += 1
	local arena = workspace:FindFirstChild("Arena")
	local effects = arena and arena:FindFirstChild("RuleEffects")
	checkpoints[checkpointNext] = {
		At = now,
		Phase = phase,
		Round = state:GetAttribute("Round"),
		RuleIndex = state:GetAttribute("RuleIndex"),
		RuleId = state:GetAttribute("RuleId"),
		Players = #Players:GetPlayers(),
		ActivePlayers = state:GetAttribute("AliveCount"),
		Instances = readMetric("InstanceCount", function()
			return Stats.InstanceCount
		end),
		MemoryMb = memoryMb,
		Effects = if effects then #effects:GetChildren() else 0,
	}
	checkpointNext = checkpointNext % 60 + 1
end
local function finish()
	if ended then
		return
	end
	ended = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.sort(checkpoints, function(a, b)
		return a.At < b.At
	end)
	local encoded = HttpService:JSONEncode({
		FormatVersion = 1,
		SourceFingerprint = identity,
		IdentityProvided = identity ~= "unverified",
		SourceIdentityCheck = "caller_supplied_not_attested",
		Context = if client then "StudioClient" else "StudioServer",
		Evidence = "diagnostic_capture_only_not_device_or_capacity_acceptance",
		DurationSeconds = os.clock() - started,
		IntervalMs = Metrics.summary(frames),
		MemoryMb = Metrics.summary(memory),
		-- Preserve Roblox's raw property names; these are not RTT or one-way latency.
		DataSendKbps = Metrics.summary(send),
		DataReceiveKbps = Metrics.summary(receive),
		Checkpoints = checkpoints,
		CheckpointsOverwritten = math.max(0, checkpointCount - #checkpoints),
		UnavailableMetrics = missing,
	})
	if report.Parent then
		if #encoded <= 32000 then
			result.Value = encoded
		else
			result.Value = HttpService:JSONEncode({ Error = "ExportSizeLimit", Bytes = #encoded })
		end
		report:SetAttribute("Complete", true)
	end
end
table.insert(
	connections,
	report:GetAttributeChangedSignal("Stop"):Connect(function()
		if report:GetAttribute("Stop") == true then
			finish()
		end
	end)
)
table.insert(connections, report.Destroying:Connect(finish))
table.insert(connections, script.Destroying:Connect(finish))
table.insert(
	connections,
	(if client then RunService.RenderStepped else RunService.Heartbeat):Connect(function(dt)
		Metrics.add(frames, dt * 1000)
		local now = os.clock() - started
		if now >= duration then
			finish()
			return
		end
		if now - lastMetric < 1 then
			return
		end
		lastMetric = now
		local memoryMb = readMetric("MemoryMb", function()
			return Stats:GetTotalMemoryUsageMb()
		end)
		if memoryMb ~= nil then
			Metrics.add(memory, memoryMb)
		end
		local sent = readMetric("DataSendKbps", function()
			return Stats.DataSendKbps
		end)
		local received = readMetric("DataReceiveKbps", function()
			return Stats.DataReceiveKbps
		end)
		if sent ~= nil then
			Metrics.add(send, sent)
		end
		if received ~= nil then
			Metrics.add(receive, received)
		end
		local phase = tostring(state:GetAttribute("Phase") or "Unknown")
		if phase ~= lastPhase or now - lastCheckpoint >= 30 then
			snapshot(now, phase, memoryMb)
			lastCheckpoint, lastPhase = now, phase
		end
	end)
)
print("[RuleRoom QA] Bounded performance probe started; source fingerprint: " .. identity)
