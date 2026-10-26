-- QA movement driver: normal MoveTo/Jump only; default controls are restored on exit.
assert(game:GetService("RunService"):IsStudio(), "Studio-only QA driver")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local p = Players.LocalPlayer
local state = RS:WaitForChild("RuleRoomState")
local arena = workspace:WaitForChild("Arena")
local qa = RS:WaitForChild("QARuleCoverage", 30)
assert(qa, "Server fixture missing")
local telemetry = qa:WaitForChild("ClientTelemetry", 10)
local playerModule = p.PlayerScripts:WaitForChild("PlayerModule", 15)
assert(playerModule, "Default PlayerModule missing")
local controls = require(playerModule):GetControls()
local originallyEnabled = controls.controlsEnabled ~= false
local driverOwnsControls = false
local lastJump, lastEntry, jumpAttempts = 0, nil, 0
local previousBeamZ, previousBeamTime, beamDirection = nil, nil, 0
local mistakeTarget, mistakePart, mistakeKey = nil, nil, nil
local mistakeDirection = 1
-- Observe this LocalScript's own control instance. Requiring PlayerModule from a
-- Studio/MCP command environment can create a separate controller and change input.
local evidence = Instance.new("Folder")
evidence.Name = "Evidence"
evidence:SetAttribute("Complete", false)
evidence:SetAttribute(
	"Source",
	"Driver LocalScript control instance; client physics only; server trace remains independent"
)
evidence.Parent = script
local trace, observedHumanoid = nil, nil
local traceConnections, humanoidConnections = {}, {}
local lastTracePublish, stopped = 0, false
local function append(ring, value, limit)
	if #ring == limit then
		table.remove(ring, 1)
	end
	table.insert(ring, value)
end
local function controlSnapshot()
	local controller = controls.activeController
	return {
		controlsEnabled = if type(controls.controlsEnabled) == "boolean"
			then controls.controlsEnabled
			else "unavailable",
		activeControllerEnabled = if controller and type(controller.enabled) == "boolean"
			then controller.enabled
			else "unavailable",
		driverOwnsControls = driverOwnsControls,
	}
end
local function bodySample(kind)
	local character = p.Character
	local h = character and character:FindFirstChildOfClass("Humanoid")
	local r = character and character:FindFirstChild("HumanoidRootPart")
	local sample = {
		t = workspace:GetServerTimeNow(),
		kind = kind,
		entry = qa:GetAttribute("EntryIndex"),
		phase = state:GetAttribute("Phase"),
		rule = state:GetAttribute("RuleId"),
		inRound = p:GetAttribute("InRound") == true,
		controls = controlSnapshot(),
	}
	if h and r then
		sample.x, sample.y, sample.z = r.Position.X, r.Position.Y, r.Position.Z
		sample.vy, sample.anchored = r.AssemblyLinearVelocity.Y, r.Anchored
		sample.health, sample.jump = h.Health, h.Jump
		sample.state, sample.floor = h:GetState().Name, h.FloorMaterial.Name
		sample.jumpingEnabled = h:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		sample.stateMachine, sample.platformStand, sample.sit = h.EvaluateStateMachine, h.PlatformStand, h.Sit
		sample.jumpPower, sample.jumpHeight, sample.useJumpPower = h.JumpPower, h.JumpHeight, h.UseJumpPower
	end
	return sample
end
local function traceEvent(kind)
	if trace then
		local sample = bodySample(kind)
		append(trace.events, sample, 96)
		return sample
	end
	return nil
end
local function observeHumanoid(h)
	if observedHumanoid == h then
		return
	end
	for _, connection in humanoidConnections do
		connection:Disconnect()
	end
	table.clear(humanoidConnections)
	observedHumanoid = h
	if not h then
		return
	end
	traceEvent("character_observed")
	table.insert(
		humanoidConnections,
		h:GetPropertyChangedSignal("Jump"):Connect(function()
			if observedHumanoid == h then
				traceEvent("jump_property_changed")
			end
		end)
	)
	table.insert(
		humanoidConnections,
		h.StateChanged:Connect(function(previous, current)
			if observedHumanoid ~= h or not trace then
				return
			end
			local sample = traceEvent("state_changed")
			if sample then
				sample.fromState, sample.toState = previous.Name, current.Name
			end
			if current == Enum.HumanoidStateType.Jumping then
				trace.jumpingTransitions += 1
			end
		end)
	)
end
local function publishTrace(final)
	if not evidence.Parent then
		return
	end
	evidence:SetAttribute("ControlsNowJSON", HttpService:JSONEncode(controlSnapshot()))
	if not trace then
		lastTracePublish = os.clock()
		return
	end
	trace.controlsNow = controlSnapshot()
	trace.jumpAttempts = jumpAttempts
	trace.final = final
	local encoded = HttpService:JSONEncode(trace)
	evidence:SetAttribute("LatestJSON", encoded)
	evidence:SetAttribute("EntryIndex", trace.entry)
	if final then
		local value = Instance.new("StringValue")
		value.Name = string.format("Entry%04d", trace.entry)
		value.Value = encoded
		value.Parent = evidence
		local stored = evidence:GetChildren()
		if #stored > 40 then
			table.sort(stored, function(a, b)
				return a.Name < b.Name
			end)
			stored[1]:Destroy()
		end
	end
	lastTracePublish = os.clock()
end
local preSampleAt, postSampleAt = 0, 0
local function physicsSample(phase)
	if not trace or stopped then
		return
	end
	local now = os.clock()
	local previous = if phase == "pre_simulation" then preSampleAt else postSampleAt
	if now - previous < 0.04 then
		return
	end
	if phase == "pre_simulation" then
		preSampleAt = now
	else
		postSampleAt = now
	end
	local sample = bodySample(phase)
	append(if phase == "pre_simulation" then trace.preSimulation else trace.postSimulation, sample, 64)
	if
		sample.inRound
		and sample.phase == "Rule"
		and sample.y
		and math.abs(sample.x) <= 45
		and math.abs(sample.z) <= 45
	then
		trace.activeSamples += 1
		trace.maxY = math.max(trace.maxY or sample.y, sample.y)
		trace.minY = math.min(trace.minY or sample.y, sample.y)
		trace.maxUpVelocity = math.max(trace.maxUpVelocity or sample.vy, sample.vy)
		if sample.vy > 5 then
			trace.ascendingSamples += 1
		end
	end
end
table.insert(
	traceConnections,
	RunService.PreSimulation:Connect(function()
		physicsSample("pre_simulation")
	end)
)
table.insert(
	traceConnections,
	RunService.PostSimulation:Connect(function()
		physicsSample("post_simulation")
	end)
)
local function ownControls(enabled)
	if enabled and (not driverOwnsControls or controls.controlsEnabled ~= false) then
		controls:Disable()
		driverOwnsControls = true
	elseif not enabled and driverOwnsControls then
		if originallyEnabled then
			controls:Enable()
		else
			controls:Disable()
		end
		driverOwnsControls = false
	end
end
local function stopObservers()
	if stopped then
		return
	end
	stopped = true
	for _, connection in traceConnections do
		connection:Disconnect()
	end
	for _, connection in humanoidConnections do
		connection:Disconnect()
	end
	ownControls(false)
end
script.Destroying:Connect(stopObservers)
local function sendTelemetry()
	if telemetry then
		telemetry:FireServer(lastEntry, jumpAttempts, driverOwnsControls)
	end
end
local function dist(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end
local function nearest(root, list, predicate)
	local result, best = nil, math.huge
	for _, v in list do
		if v:IsA("BasePart") and (not predicate or predicate(v)) then
			local d = dist(v.Position, root.Position)
			if d < best then
				best = d
				result = v
			end
		end
	end
	return result, best
end
local ok, message = xpcall(function()
	while not stopped and qa.Parent and not qa:GetAttribute("Complete") do
		local behavior = qa:GetAttribute("Behavior_" .. p.UserId) or qa:GetAttribute("Behavior") or "manual"
		ownControls(behavior ~= "manual")
		local index = qa:GetAttribute("EntryIndex")
		if index ~= lastEntry then
			publishTrace(true)
			lastEntry = index
			jumpAttempts = 0
			lastJump = 0
			mistakeTarget, mistakePart, mistakeKey = nil, nil, nil
			mistakeDirection = 1
			trace = {
				entry = index,
				startedAt = workspace:GetServerTimeNow(),
				events = {},
				preSimulation = {},
				postSimulation = {},
				activeSamples = 0,
				ascendingSamples = 0,
				jumpingTransitions = 0,
				inputScheduling = "Unchanged: MoveTo and Jump writes in task.wait(0.03) driver loop",
			}
			sendTelemetry()
		end
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local r = c and c:FindFirstChild("HumanoidRootPart")
		observeHumanoid(h)
		-- Manual is a true no-input branch: no MoveTo and no Jump writes.
		if
			behavior ~= "manual"
			and state:GetAttribute("Phase") == "Rule"
			and h
			and r
			and h.Health > 0
			and p:GetAttribute("InRound")
		then
			local id = state:GetAttribute("RuleId")
			local effects = arena:FindFirstChild("RuleEffects")
			local list = effects and effects:GetChildren() or {}
			local target = nil
			local jump = false
			local beamZ, beamTime = arena.Laser.Position.Z, os.clock()
			if previousBeamZ and previousBeamTime and beamTime > previousBeamTime then
				local delta = beamZ - previousBeamZ
				if math.abs(delta) > 0.01 then
					beamDirection = if delta > 0 then 1 else -1
				end
			end
			previousBeamZ, previousBeamTime = beamZ, beamTime
			local charged = tonumber(state:GetAttribute("TeamGoal")) or 0
			charged = charged > 0 and (tonumber(state:GetAttribute("TeamCharge")) or 0) >= charged
			-- These two negative cases intentionally use the same target without changing solve behavior.
			-- selene: allow(if_same_then_else)
			if behavior == "fatal_beam" and id == "LaserSweep" then
				target =
					Vector3.new(r.Position.X, r.Position.Y, math.clamp(beamZ + beamDirection * 2.5, -40, 40))
			elseif behavior == "mistake" and id ~= "ReactorRush" then
				-- Deliberately choose the warned danger using ordinary movement, never forced damage.
				if id == "SafeColor" then
					local safe = state:GetAttribute("SafeColor")
					if safe and safe ~= "" and mistakeKey ~= safe then
						local tile = nearest(r, arena.Tiles:GetChildren(), function(v)
							return v.CanCollide and v:GetAttribute("ColorName") ~= safe
						end)
						if tile then
							mistakeKey, mistakeTarget = safe, tile.Position
						end
					end
					target = mistakeTarget
				elseif id == "LaserSweep" then
					target = Vector3.new(-15, r.Position.Y, -5)
				elseif id == "LowGravity" then
					-- Bonus-rule negative case: stay on the floor and decline the airborne stars.
					target = Vector3.new(0, r.Position.Y, 0)
				elseif id == "RedLight" then
					target = Vector3.new(20 * mistakeDirection, r.Position.Y, 0)
					if dist(r.Position, target) < 3 then
						mistakeDirection = -mistakeDirection
						target = Vector3.new(20 * mistakeDirection, r.Position.Y, 0)
					end
				elseif id == "LavaRise" then
					-- (10,10) is floor between the nine platforms, not a platform center.
					target = Vector3.new(10, r.Position.Y, 10)
				elseif id == "MeteorRain" then
					if not mistakePart or not mistakePart.Parent then
						mistakePart = nearest(r, list, function(v)
							return v.Name == "ImpactWarning"
						end)
						if mistakePart then
							mistakeTarget = mistakePart.Position
						end
					end
					target = mistakeTarget
				elseif id == "DisappearingTiles" then
					local warning = state:GetAttribute("Instruction") or ""
					if string.find(warning, "Волна", 1, true) and mistakeKey ~= warning then
						local tile = nearest(r, arena.Tiles:GetChildren(), function(v)
							return v.CanCollide and v.Transparency >= 0.14 and v.Transparency < 0.3
						end)
						if tile then
							mistakeKey, mistakeTarget = warning, tile.Position
						end
					end
					-- Keep this target after collision disappears; do not seek a rescue tile.
					target = mistakeTarget
				elseif id == "SafeZone" then
					local zone = effects and effects:FindFirstChild("SafeZone")
					if zone then
						target = Vector3.new(-zone.Position.X, r.Position.Y, -zone.Position.Z)
					end
				elseif id == "Spinner" then
					target = Vector3.new(25, r.Position.Y, 25)
				end
			elseif behavior == "corner_idle" then
				target = Vector3.new(25, r.Position.Y, 25)
			elseif id == "ReactorRush" and (behavior == "no_collect" or behavior == "mistake") then
				target = Vector3.new(-28, r.Position.Y, -28)
				jump = arena.Laser.Transparency < 0.2
					and math.abs(r.Position.Z - arena.Laser.Position.Z)
						< (qa:GetAttribute("JumpLead") or 3)
			elseif id == "ReactorRush" and behavior == "charged_die" and charged then
				-- Anticipate the visible beam with ordinary walking; no forced damage/teleport.
				target =
					Vector3.new(r.Position.X, r.Position.Y, math.clamp(beamZ + beamDirection * 2.5, -40, 40))
			elseif id == "SafeColor" then
				local t = nearest(r, arena.Tiles:GetChildren(), function(v)
					return v.CanCollide and v:GetAttribute("ColorName") == state:GetAttribute("SafeColor")
				end)
				target = t and t.Position
			elseif id == "SafeZone" then
				local t = effects and effects:FindFirstChild("SafeZone")
				target = t and t.Position
			elseif id == "LavaRise" then
				local t, d = nearest(r, list, function(v)
					return v.Name == "SafePlatform"
				end)
				target = t and t.Position
				jump = t and r.Position.Y < 7 and d < 9.1
			elseif id == "DisappearingTiles" then
				local t = nearest(r, arena.Tiles:GetChildren(), function(v)
					return v.CanCollide and v.Transparency < 0.1
				end)
				target = t and t.Position
			elseif id == "LowGravity" or id == "RedLight" or id == "ReactorRush" then
				local prefix = if id == "ReactorRush" then "Energy" else "Star"
				local t, d = nearest(r, list, function(v)
					return string.sub(v.Name, 1, #prefix) == prefix
				end)
				target = t and t.Position
				if id == "LowGravity" then
					jump = t and d < 5
				end
				if
					id == "RedLight"
					and not string.find(state:GetAttribute("Instruction") or "", "ЗЕЛЁНЫЙ", 1, true)
				then
					target = r.Position
				end
				if id == "ReactorRush" then
					jump = arena.Laser.Transparency < 0.2
						and math.abs(r.Position.Z - arena.Laser.Position.Z)
							< (qa:GetAttribute("JumpLead") or 3)
				end
			elseif id == "MeteorRain" then
				local warnings = {}
				for _, v in list do
					if v.Name == "ImpactWarning" then
						table.insert(warnings, v)
					end
				end
				local t = nearest(r, arena.Tiles:GetChildren(), function(v)
					for _, w in warnings do
						if
							math.abs(v.Position.X - w.Position.X) < 7
							and math.abs(v.Position.Z - w.Position.Z) < 7
						then
							return false
						end
					end
					return true
				end)
				target = t and t.Position
			elseif id == "LaserSweep" then
				target = Vector3.new(-15, r.Position.Y, -5)
				jump = arena.Laser.Transparency < 0.2
					and math.abs(r.Position.Z - arena.Laser.Position.Z)
						< (qa:GetAttribute("JumpLead") or 3)
			elseif id == "Spinner" then
				-- Stay off the initial beam axis; standing on it would manufacture a t=0 hit.
				target = Vector3.new(15, r.Position.Y, 5)
				local localPoint = arena.Laser.CFrame:PointToObjectSpace(r.Position)
				jump = arena.Laser.Transparency < 0.2
					and math.abs(localPoint.Z) < (qa:GetAttribute("JumpLead") or 3)
			end
			if target then
				h:MoveTo(Vector3.new(target.X, r.Position.Y, target.Z))
			else
				h:MoveTo(r.Position)
			end
			if id == "ReactorRush" and behavior == "charged_die" and charged then
				h.Jump = false
			end
			if jump and h.FloorMaterial ~= Enum.Material.Air and os.clock() - lastJump > 0.45 then
				traceEvent("before_jump_write")
				h.Jump = true
				traceEvent("after_jump_write")
				lastJump = os.clock()
				jumpAttempts += 1
				sendTelemetry()
			end
		end
		if os.clock() - lastTracePublish >= 1 then
			publishTrace(false)
		end
		task.wait(0.03)
	end
end, debug.traceback)
-- Diagnostic failures must not leave the player's controls disabled or observers connected.
stopObservers()
local traceOK, traceMessage = pcall(publishTrace, true)
if not traceOK then
	ok = false
	message = tostring(message or "") .. " Final trace: " .. tostring(traceMessage)
end
evidence:SetAttribute("Complete", true)
evidence:SetAttribute("ControlsAfterJSON", HttpService:JSONEncode(controlSnapshot()))
evidence:SetAttribute("DriverOK", ok)
if not ok then
	evidence:SetAttribute("Error", tostring(message))
	warn("[QA_DRIVER] " .. tostring(message))
end
