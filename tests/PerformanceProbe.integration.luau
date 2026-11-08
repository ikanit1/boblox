--!strict
-- Executes the exact opt-in collector with synthetic services, not device measurements.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local Metrics = require("../src/shared/BoundedMetrics")
local source = fs.readFile("tools/studio/performance_probe.luau")
local checks, scenarios = 0, 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
local function signal()
	local entries = {}
	local value = {}
	function value:Connect(callback)
		local entry = { Callback = callback, Connected = true }
		table.insert(entries, entry)
		return {
			Disconnect = function()
				entry.Connected = false
			end,
		}
	end
	function value:Fire(...)
		for _, entry in entries do
			if entry.Connected then
				entry.Callback(...)
			end
		end
	end
	function value:Count()
		local count = 0
		for _, entry in entries do
			if entry.Connected then
				count += 1
			end
		end
		return count
	end
	return value
end
local function object(initial)
	local attributes = initial or {}
	local signals = {}
	local value = { Destroying = signal() }
	function value:GetAttribute(name)
		return attributes[name]
	end
	function value:GetAttributeChangedSignal(name)
		if not signals[name] then
			signals[name] = signal()
		end
		return signals[name]
	end
	function value:SetAttribute(name, item)
		if attributes[name] ~= item then
			attributes[name] = item
			if signals[name] then
				signals[name]:Fire()
			end
		end
	end
	return value
end
local function harness(client: boolean, duration: number, studio: boolean?)
	scenarios += 1
	local now = 0
	local created = {}
	local parent = {
		FindFirstChild = function()
			return nil
		end,
	}
	local scriptObject = object({ DurationSeconds = duration, SourceFingerprint = string.rep("a", 64) })
	local state = object({ Phase = "Waiting", Round = 0, RuleIndex = 0 })
	local heartbeat, render = signal(), signal()
	local services = {
		RunService = {
			IsStudio = function()
				return studio ~= false
			end,
			IsClient = function()
				return client
			end,
			Heartbeat = heartbeat,
			RenderStepped = render,
		},
		ReplicatedStorage = {
			WaitForChild = function(_, name)
				return if name == "RuleRoomState"
					then state
					else {
						WaitForChild = function()
							return "BoundedMetrics"
						end,
					}
			end,
		},
		Players = {
			GetPlayers = function()
				return { {}, {} }
			end,
			LocalPlayer = {
				WaitForChild = function()
					return parent
				end,
			},
		},
		HttpService = {
			JSONEncode = function(_, data)
				return serde.encode("json", data)
			end,
		},
		ServerStorage = parent,
		Stats = {
			GetTotalMemoryUsageMb = function()
				return 320 + now / 100
			end,
			InstanceCount = 1050,
			DataSendKbps = 12,
			DataReceiveKbps = 8,
		},
	}
	local run = luau.load(source, {
		debugName = "PerformanceProbe.production",
		environment = {
			game = {
				GetService = function(_, name)
					return assert(services[name], name)
				end,
			},
			script = scriptObject,
			workspace = {
				FindFirstChild = function()
					return nil
				end,
			},
			Instance = {
				new = function(class)
					local value = object()
					created[class] = value
					return value
				end,
			},
			os = {
				clock = function()
					return now
				end,
			},
			require = function()
				return Metrics
			end,
			print = function() end,
		},
		injectGlobals = true,
	})
	local ok, problem = pcall(run)
	return {
		Ok = ok,
		Problem = problem,
		Created = created,
		State = state,
		Script = scriptObject,
		Services = services,
		Heartbeat = heartbeat,
		Render = render,
		Step = function(dt)
			now += dt
			local stepSignal = if client then render else heartbeat
			stepSignal:Fire(dt)
		end,
		Result = function()
			return serde.decode("json", created.StringValue.Value)
		end,
	}
end
do
	local h = harness(false, 1800)
	expect(h.Ok and h.Heartbeat:Count() == 1 and h.Render:Count() == 0, "Server observes heartbeat only")
	for index = 1, 180001 do
		if index % 1000 == 0 then
			h.State:SetAttribute("Phase", if index % 2000 == 0 then "Rule" else "Results")
		end
		h.Step(0.01)
	end
	local result = h.Result()
	expect(h.Created.Folder:GetAttribute("Complete") == true, "Duration stops capture")
	expect(
		result.IntervalMs.WindowCount == 6000 and result.IntervalMs.Overwritten > 170000,
		"Frame ring remains bounded"
	)
	expect(
		#result.Checkpoints <= 60 and result.CheckpointsOverwritten > 100,
		"Checkpoint ring remains bounded"
	)
	expect(result.IntervalMs.P95 == 10 and result.IntervalMs.P99 == 10, "Synthetic interval percentiles")
	expect(#h.Created.StringValue.Value < 32000, "Long capture export stays within its byte budget")
	expect(
		h.Heartbeat:Count() == 0 and h.Script.Destroying:Count() == 0,
		"Finished probe disconnects sampling"
	)
	expect(
		result.SourceIdentityCheck == "caller_supplied_not_attested",
		"Supplied fingerprint is not source attestation"
	)
	local old = h.Created.StringValue.Value
	h.Step(1)
	expect(old == h.Created.StringValue.Value, "Late frames cannot alter completed report")
end
do
	local h = harness(true, 120)
	expect(
		h.Ok and h.Render:Count() == 1 and h.Heartbeat:Count() == 0,
		"Client observes rendering interval only"
	)
	h.Services.Stats.GetTotalMemoryUsageMb = function()
		error("Unavailable metric")
	end
	h.Step(1 / 30)
	h.Created.Folder:SetAttribute("Stop", true)
	local result = h.Result()
	expect(
		result.UnavailableMetrics.MemoryMb == true and result.MemoryMb.Count == 0,
		"Unavailable memory is not zero"
	)
	expect(
		result.Context == "StudioClient" and result.IntervalMs.Count == 1,
		"Manual stop exports observed samples"
	)
	expect(h.Render:Count() == 0, "Manual stop releases render listener")
end
do
	local h = harness(false, 15)
	h.Script.Destroying:Fire()
	expect(
		h.Created.Folder:GetAttribute("Complete") == true and h.Heartbeat:Count() == 0,
		"Removing probe stops sampling"
	)
	expect(h.Result().IntervalMs.P50 == nil, "Empty capture never fabricates percentiles")
end
do
	local h = harness(false, 120, false)
	expect(not h.Ok and next(h.Created) == nil, "Probe refuses to run outside Studio")
end
print(
	"PerformanceProbe integration: " .. checks .. " checks passed in " .. scenarios .. " synthetic scenarios"
)
