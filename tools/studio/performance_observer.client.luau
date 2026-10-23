-- Studio-only read-only performance observation. Owns only QAPerformance output.
-- No gameplay requires, inputs, state mutations, physics/network changes, or thresholds.
-- Schema 2 export: wait for Complete, then read Summary plus Snapshot0001..SnapshotNNNN.
-- Each Snapshot StringValue contains one complete JSON object; Summary never embeds them.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsRunning(), "Running Studio session only")
local IS_CLIENT = true
assert(if IS_CLIENT then RunService:IsClient() else RunService:IsServer(), "Wrong observer context")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local player = if IS_CLIENT then Players.LocalPlayer else nil
local parent = if player then player:WaitForChild("PlayerScripts", 15) else ReplicatedStorage
assert(parent, "Observer parent not ready")
assert(not parent:FindFirstChild("QAPerformance"), "QAPerformance already installed")
local statsAvailable, stats = pcall(function()
	return game:GetService("Stats")
end)
local output = Instance.new("Folder")
output.Name = "QAPerformance"
output:SetAttribute("Complete", false)
output:SetAttribute("Stop", false)
output:SetAttribute("DurationSeconds", 600)
output:SetAttribute("SchemaVersion", 2)
output:SetAttribute("Side", if IS_CLIENT then "Client" else "Server")
if player then
	output:SetAttribute("UserId", player.UserId)
end
output.Parent = parent

local RING_LIMIT, SNAPSHOT_LIMIT = 20000, 901
local startedAt, startedClock = Workspace:GetServerTimeNow(), os.clock()
output:SetAttribute("StartedAt", startedAt)
local active, finalized = true, false
local connections, ring, snapshots = {}, {}, {}
local nextSlot, count, validCount, invalidCount, sumDt = 1, 0, 0, 0, 0
local minDt, maxDt, lastSampleAt = nil, nil, nil
local snapshotDrops, memoryUnavailable = 0, 0
local memoryFirst, memoryLast, memoryMin, memoryMax
local focus = "unknown"
local errors = {}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function duration()
	local requested = output:GetAttribute("DurationSeconds")
	return if finite(requested) then math.clamp(requested, 300, 900) else 600
end
local function capture()
	local captureClock = os.clock()
	local arena = Workspace:FindFirstChild("Arena")
	local effects = arena and arena:FindFirstChild("RuleEffects")
	local state = ReplicatedStorage:FindFirstChild("RuleRoomState")
	local nativePlayers = Players:GetPlayers()
	local memory, memoryError
	if statsAvailable then
		local ok, value = pcall(function()
			return stats:GetTotalMemoryUsageMb()
		end)
		if ok and finite(value) and value >= 0 then
			memory = value
			memoryFirst = memoryFirst or value
			memoryLast = value
			memoryMin = math.min(memoryMin or value, value)
			memoryMax = math.max(memoryMax or value, value)
		else
			memoryError = if ok then "nonfinite/negative memory result" else tostring(value)
		end
	else
		memoryError = tostring(stats)
	end
	if memory == nil then
		memoryUnavailable += 1
	end
	local item = {
		at = Workspace:GetServerTimeNow(),
		elapsedSeconds = os.clock() - startedClock,
		callbackCount = count,
		memoryMb = memory,
		memoryUnavailable = memory == nil,
		memoryError = if memoryError then string.sub(memoryError, 1, 200) else nil,
		dataModelDescendants = #game:GetDescendants(),
		workspaceDescendants = #Workspace:GetDescendants(),
		arenaDescendants = if arena then #arena:GetDescendants() else nil,
		ruleEffectChildren = if effects then #effects:GetChildren() else 0,
		ruleEffectDescendants = if effects then #effects:GetDescendants() else 0,
		nativePlayerCount = #nativePlayers,
		phase = if state then state:GetAttribute("Phase") else nil,
		rule = if state then state:GetAttribute("RuleId") else nil,
		round = if state then state:GetAttribute("Round") else nil,
	}
	if IS_CLIENT then
		local camera = Workspace.CurrentCamera
		item.focusObserved = focus
		item.viewport = if camera then { camera.ViewportSize.X, camera.ViewportSize.Y } else nil
	else
		local pings = {}
		for _, nativePlayer in nativePlayers do
			local ok, value = pcall(function()
				return nativePlayer:GetNetworkPing()
			end)
			table.insert(pings, {
				userId = nativePlayer.UserId,
				getNetworkPingSeconds = if ok and finite(value) then value else nil,
				available = ok and finite(value),
				error = if not ok then string.sub(tostring(value), 1, 120) else nil,
			})
		end
		table.sort(pings, function(a, b)
			return a.userId < b.userId
		end)
		item.players = pings
	end
	item.observerCaptureCostMs = (os.clock() - captureClock) * 1000
	if #snapshots < SNAPSHOT_LIMIT then
		table.insert(snapshots, item)
	else
		snapshotDrops += 1
	end
end
local function finish(reason)
	if finalized then
		return
	end
	finalized, active = true, false
	for _, connection in connections do
		connection:Disconnect()
	end
	local endedAt = Workspace:GetServerTimeNow()
	local sorted = table.clone(ring)
	table.sort(sorted)
	local ringTotal = 0
	for _, value in sorted do
		ringTotal += value
	end
	local percentile = function(fraction)
		if #sorted == 0 then
			return nil
		end
		return sorted[math.max(1, math.ceil(#sorted * fraction))] * 1000
	end
	local result = {
		schemaVersion = 2,
		side = if IS_CLIENT then "Client" else "Server",
		userId = if player then player.UserId else nil,
		signal = if IS_CLIENT then "RunService.RenderStepped deltaTime" else "RunService.Heartbeat deltaTime",
		startedAt = startedAt,
		endedAt = endedAt,
		wallSeconds = os.clock() - startedClock,
		configuredDurationSeconds = duration(),
		endReason = reason,
		allObservedFrames = {
			callbackCount = count,
			validCount = validCount,
			invalidCount = invalidCount,
			meanMs = if validCount > 0 then sumDt / validCount * 1000 else nil,
			minMs = if minDt then minDt * 1000 else nil,
			maxMs = if maxDt then maxDt * 1000 else nil,
			deltaTimeSumSeconds = sumDt,
		},
		recentWindow = {
			method = "Exact nearest-rank percentiles over the most recent valid deltaTime values; not a histogram or full-run percentile after the ring wraps",
			sampleCount = #sorted,
			capacity = RING_LIMIT,
			discardedOlderSamples = math.max(0, validCount - #sorted),
			p50Ms = percentile(0.5),
			p95Ms = percentile(0.95),
			maxMs = if #sorted > 0 then sorted[#sorted] * 1000 else nil,
			deltaTimeSumSeconds = ringTotal,
			lastSampleAt = lastSampleAt,
		},
		memory = {
			firstMb = memoryFirst,
			lastMb = memoryLast,
			minMb = memoryMin,
			maxMb = memoryMax,
			unavailableSnapshots = memoryUnavailable,
			source = "Stats:GetTotalMemoryUsageMb, guarded; unavailable is not zero",
		},
		metadataIntervalSeconds = 1,
		metadataSnapshotCount = #snapshots,
		metadataDropped = snapshotDrops,
		snapshotStorage = {
			format = "individual_json_stringvalues",
			parent = "QAPerformance",
			nameFormat = "Snapshot%04d",
			firstIndex = 1,
			count = #snapshots,
			capacity = SNAPSHOT_LIMIT,
			order = "capture order",
			export = "Read every Snapshot0001..SnapshotNNNN sibling of Summary after Complete is true; decode each Value separately. Summary excludes snapshots.",
		},
		errors = errors,
		evidence = if validCount > 0 then "observed_statistics_only" else "no_frame_samples",
		limits = "Local Studio processes share host resources; background/minimized windows may throttle. DeltaTime is cadence, not CPU/GPU execution duration. Descendant counts include QA objects. The observer adds work; metadata capture cost is measured. No automatic performance PASS or production/device acceptance.",
	}
	-- Capture/frame observation has stopped. Export afterward so these objects are not
	-- included in this observer's descendant counts or frame statistics.
	local maxSnapshotBytes = 0
	for index, snapshot in snapshots do
		local encoded = HttpService:JSONEncode(snapshot)
		assert(#encoded < 200000, "Performance snapshot exceeds StringValue limit")
		local snapshotValue = Instance.new("StringValue")
		snapshotValue.Name = string.format("Snapshot%04d", index)
		snapshotValue.Value = encoded
		snapshotValue.Parent = output
		maxSnapshotBytes = math.max(maxSnapshotBytes, #encoded)
	end
	result.snapshotStorage.maxValueBytes = maxSnapshotBytes
	local item = Instance.new("StringValue")
	item.Name = "Summary"
	local encodedSummary = HttpService:JSONEncode(result)
	assert(#encodedSummary < 200000, "Performance summary exceeds StringValue limit")
	item.Value = encodedSummary
	item.Parent = output
	output:SetAttribute("EndReason", reason)
	output:SetAttribute("FrameCount", count)
	output:SetAttribute("SnapshotCount", #snapshots)
	output:SetAttribute("Complete", true)
end
if IS_CLIENT then
	local input = game:GetService("UserInputService")
	table.insert(
		connections,
		input.WindowFocused:Connect(function()
			focus = "focused"
		end)
	)
	table.insert(
		connections,
		input.WindowFocusReleased:Connect(function()
			focus = "unfocused"
		end)
	)
end
local signal = if IS_CLIENT then RunService.RenderStepped else RunService.Heartbeat
table.insert(
	connections,
	signal:Connect(function(delta)
		if not active then
			return
		end
		count += 1
		if not finite(delta) or delta < 0 then
			invalidCount += 1
			return
		end
		validCount += 1
		sumDt += delta
		minDt = math.min(minDt or delta, delta)
		maxDt = math.max(maxDt or delta, delta)
		lastSampleAt = Workspace:GetServerTimeNow()
		ring[nextSlot] = delta
		nextSlot = nextSlot % RING_LIMIT + 1
	end)
)
table.insert(
	connections,
	output:GetAttributeChangedSignal("Stop"):Connect(function()
		if output:GetAttribute("Stop") == true then
			finish("requested_stop")
		end
	end)
)
task.spawn(function()
	while active do
		local ok, err = xpcall(capture, debug.traceback)
		if not ok then
			table.insert(errors, tostring(err))
			finish("observer_error")
			break
		end
		output:SetAttribute("FrameCount", count)
		output:SetAttribute("SnapshotCount", #snapshots)
		if os.clock() - startedClock >= duration() then
			finish("duration_complete")
			break
		end
		task.wait(1)
	end
end)
return "QAPerformance active: " .. (if IS_CLIENT then "Client " .. player.UserId else "Server")
