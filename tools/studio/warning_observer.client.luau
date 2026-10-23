-- Scratch read-only LocalScript: observe replicated production state and client presentation.
-- Owns only PlayerScripts.QAWarningEvidence. Never changes input, health, movement, or game state.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
assert(RunService:IsStudio() and RunService:IsClient(), "Studio client only")
local player = Players.LocalPlayer
local scripts = player:WaitForChild("PlayerScripts", 20)
local state = RS:WaitForChild("RuleRoomState", 20)
local arena = Workspace:WaitForChild("Arena", 20)
assert(scripts and state and arena, "Client game not ready")
assert(not scripts:FindFirstChild("QAWarningEvidence"), "Observer already installed")
local output = Instance.new("Folder")
output.Name = "QAWarningEvidence"
output:SetAttribute("SchemaVersion", 1)
output:SetAttribute("Complete", false)
output:SetAttribute("Stop", false)
output:SetAttribute("CaseCount", 0)
output:SetAttribute("Truncated", false)
output:SetAttribute("StartedAt", Workspace:GetServerTimeNow())
output:SetAttribute("UserId", player.UserId)
output:SetAttribute(
	"Evidence",
	"Client read-only 20Hz post-render state/HUD/world observation; health event timestamps"
)
output.Parent = scripts
local MAX_CASES, MAX_EVENTS, MAX_DAMAGE = 64, 160, 40
local expires = os.clock() + 1200
local current, lastSignature, lastSample, baseline
local frameConnection, healthConnection, humanoid
local active, count, characterGeneration = true, 0, 0
local errors = {}

local function round(value)
	return math.floor(value * 1000 + 0.5) / 1000
end
local function vector(value)
	return { round(value.X), round(value.Y), round(value.Z) }
end
local function color(value)
	return { math.round(value.R * 255), math.round(value.G * 255), math.round(value.B * 255) }
end
local function onscreen(part)
	local camera = Workspace.CurrentCamera
	if not camera or part.Transparency >= 1 or part.LocalTransparencyModifier >= 1 then
		return false
	end
	local point, visible = camera:WorldToViewportPoint(part.Position)
	return visible and point.Z > 0 -- Bounds-center test only; does not prove lack of occlusion.
end
local function displayed(label)
	if not label or not label:IsA("TextLabel") then
		return { exists = false, renderEligible = false }
	end
	local position, size = label.AbsolutePosition, label.AbsoluteSize
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	local left, top = math.max(0, position.X), math.max(0, position.Y)
	local right = math.min(viewport.X, position.X + size.X)
	local bottom = math.min(viewport.Y, position.Y + size.Y)
	local visible = label.TextTransparency < 1 and size.X > 0 and size.Y > 0
	local ancestor = label
	while ancestor and ancestor ~= player.PlayerGui do
		if ancestor:IsA("GuiObject") then
			visible = visible and ancestor.Visible
			if ancestor.ClipsDescendants then
				local p, s = ancestor.AbsolutePosition, ancestor.AbsoluteSize
				left, top = math.max(left, p.X), math.max(top, p.Y)
				right, bottom = math.min(right, p.X + s.X), math.min(bottom, p.Y + s.Y)
			end
		elseif ancestor:IsA("ScreenGui") then
			visible = visible and ancestor.Enabled
		end
		ancestor = ancestor.Parent
	end
	local textFits
	pcall(function()
		textFits = label.TextFits
	end)
	return {
		exists = true,
		text = label.Text,
		renderEligible = visible and right > left and bottom > top,
		fullyOnScreen = left <= position.X
			and top <= position.Y
			and right >= position.X + size.X
			and bottom >= position.Y + size.Y,
		textFits = textFits,
		rect = { round(position.X), round(position.Y), round(size.X), round(size.Y) },
		textSize = label.TextSize,
	}
end
local function worldSnapshot()
	local result = {
		gravity = round(Workspace.Gravity),
		tileCount = 0,
		tilesOnScreen = 0,
		warningTilesOnScreen = 0,
		solidTiles = 0,
		hiddenTiles = {},
		warningTiles = {},
		tileLabels = 0,
		tilePalette = {},
		effectsCount = 0,
		stars = 0,
		energy = 0,
		platforms = 0,
		markerWarnings = 0,
		markerImpacts = 0,
		markersOnScreen = 0,
		meteors = 0,
		starsOnScreen = 0,
		energyOnScreen = 0,
	}
	local palette = {}
	local folder = arena:FindFirstChild("Tiles")
	if folder then
		for _, tile in folder:GetChildren() do
			if tile:IsA("BasePart") then
				result.tileCount += 1
				local tileOnScreen = onscreen(tile)
				if tileOnScreen then
					result.tilesOnScreen += 1
				end
				if tile.CanCollide then
					result.solidTiles += 1
				else
					table.insert(result.hiddenTiles, tile.Name)
				end
				local rgb = color(tile.Color)
				local key = table.concat(rgb, ",")
					.. ":"
					.. tostring(round(tile.Transparency))
					.. ":"
					.. tostring(tile.CanCollide)
					.. ":"
					.. tostring(tile.CanQuery)
					.. ":"
					.. tostring(tile.CanTouch)
					.. ":"
					.. tile.Material.Name
				palette[key] = (palette[key] or 0) + 1
				if rgb[1] == 255 and rgb[2] == 160 and rgb[3] == 65 then
					table.insert(result.warningTiles, tile.Name)
					if tileOnScreen then
						result.warningTilesOnScreen += 1
					end
				end
				for _, item in tile:GetDescendants() do
					if item:IsA("TextLabel") and item.Name == "ColorText" and item.Text == "ПРОВАЛ" then
						local parentGui = item:FindFirstAncestorWhichIsA("SurfaceGui")
						if parentGui and parentGui.Enabled then
							result.tileLabels += 1
						end
					end
				end
			end
		end
	end
	table.sort(result.hiddenTiles)
	table.sort(result.warningTiles)
	for key, amount in palette do
		table.insert(result.tilePalette, key .. "=" .. amount)
	end
	table.sort(result.tilePalette)
	local laser = arena:FindFirstChild("Laser")
	if laser and laser:IsA("BasePart") then
		result.laser = {
			transparency = round(laser.Transparency),
			color = color(laser.Color),
			position = vector(laser.Position),
			size = vector(laser.Size),
			collide = laser.CanCollide,
			query = laser.CanQuery,
			touch = laser.CanTouch,
			onScreenCenter = onscreen(laser),
		}
	end
	local effects = arena:FindFirstChild("RuleEffects")
	if effects then
		result.effectsCount = #effects:GetChildren()
		for _, part in effects:GetChildren() do
			if part:IsA("BasePart") then
				if string.match(part.Name, "^Star%d+") then
					result.stars += 1
					if onscreen(part) then
						result.starsOnScreen += 1
					end
				elseif string.match(part.Name, "^Energy%d+") then
					result.energy += 1
					if onscreen(part) then
						result.energyOnScreen += 1
					end
				elseif part.Name == "SafePlatform" then
					result.platforms += 1
				elseif part.Name == "Lava" then
					result.lava = {
						y = round(part.Position.Y),
						transparency = round(part.Transparency),
						color = color(part.Color),
					}
				elseif part.Name == "SafeZone" then
					result.zone = {
						position = vector(part.Position),
						transparency = round(part.Transparency),
						color = color(part.Color),
						onScreenCenter = onscreen(part),
					}
				elseif part.Name == "ImpactWarning" then
					local rgb = color(part.Color)
					if rgb[2] > 200 then
						result.markerImpacts += 1
					else
						result.markerWarnings += 1
					end
					if onscreen(part) then
						result.markersOnScreen += 1
					end
				elseif string.match(part.Name, "^Meteor%d+") then
					result.meteors += 1
					result.meteorMinY = math.min(result.meteorMinY or math.huge, round(part.Position.Y))
				end
			end
		end
	end
	return result
end
local function cleanSignature(world)
	return Http:JSONEncode({
		world.gravity,
		world.tileCount,
		world.solidTiles,
		world.tilePalette,
		world.effectsCount,
		world.laser and world.laser.transparency,
		world.laser and world.laser.collide,
		world.laser and world.laser.query,
		world.laser and world.laser.touch,
		world.laser and world.laser.position,
		world.laser and world.laser.size,
		world.laser and world.laser.color,
	})
end
local function stage(rule, instruction, world)
	local laser = world.laser
	if rule == "LaserSweep" or rule == "Spinner" or rule == "ReactorRush" then
		if laser and laser.transparency <= 0.1 then
			return "active", "laser_transparency"
		end
		if laser and laser.transparency < 0.9 then
			return "warning", "laser_transparency"
		end
	elseif rule == "SafeColor" then
		if #world.hiddenTiles > 0 then
			return "active", "tile_collision"
		end
		if string.find(instruction, "Найди такую", 1, true) then
			return "warning", "instruction"
		end
	elseif rule == "DisappearingTiles" then
		if #world.hiddenTiles > 0 then
			return "active", "tile_collision"
		end
		if #world.warningTiles > 0 then
			return "warning", "tile_color_and_labels"
		end
	elseif rule == "LowGravity" then
		if world.gravity < 100 then
			return "active", "gravity"
		end
		if string.find(instruction, "Скоро лунная", 1, true) then
			return "warning", "instruction"
		end
	elseif rule == "RedLight" then
		if string.find(instruction, "КРАСНЫЙ", 1, true) then
			return "active", "instruction_and_accent"
		end
		if string.find(instruction, "ПРИГОТОВЬСЯ", 1, true) then
			return "warning", "instruction_and_accent"
		end
		if string.find(instruction, "ЗЕЛЁНЫЙ", 1, true) then
			return "green", "instruction_and_accent"
		end
	elseif rule == "LavaRise" then
		if world.lava then
			return if world.lava.transparency <= 0.3 then "active" else "warning", "lava_transparency"
		end
	elseif rule == "MeteorRain" then
		if world.markerImpacts > 0 then
			return "active", "marker_color"
		end
		if world.markerWarnings > 0 then
			return "warning", "marker_color"
		end
	elseif rule == "SafeZone" then
		if string.find(instruction, "ШТОРМ", 1, true) then
			return "active", "instruction_only_no_distinct_world_transition"
		end
		if world.zone then
			return "warning", "safe_zone_marker"
		end
	end
	return "none", "none"
end
local function snapshot()
	local world = worldSnapshot()
	local playerGui = player:FindFirstChild("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("RuleRoomHUD")
	local root = gui and gui:FindFirstChild("Root")
	local panel = root and root:FindFirstChild("RulePanel")
	local column = panel and panel:FindFirstChild("TextColumn")
	local hud = displayed(column and column:FindFirstChild("Instruction"))
	local timer = panel and panel:FindFirstChild("Timer")
	local timerHud = displayed(timer and timer:FindFirstChild("Countdown"))
	local instruction = state:GetAttribute("Instruction") or ""
	hud.matchesInstruction = hud.text == instruction
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local health = character and character:FindFirstChildOfClass("Humanoid")
	local phase = state:GetAttribute("Phase")
	local rule = state:GetAttribute("RuleId") or ""
	local category, evidence = stage(rule, instruction, world)
	if phase ~= "Rule" then
		category, evidence = "outside", "phase"
	end
	return {
		at = Workspace:GetServerTimeNow(),
		phase = phase,
		rule = rule,
		round = state:GetAttribute("Round"),
		ruleIndex = state:GetAttribute("RuleIndex"),
		instruction = instruction,
		phaseEndsAt = state:GetAttribute("PhaseEndsAt"),
		timerHud = timerHud,
		accent = if typeof(state:GetAttribute("Accent")) == "Color3"
			then color(state:GetAttribute("Accent"))
			else nil,
		safeColor = state:GetAttribute("SafeColor"),
		stage = category,
		stageEvidence = evidence,
		hud = hud,
		world = world,
		health = if health then health.Health else nil,
		position = if rootPart then vector(rootPart.Position) else nil,
		inRound = player:GetAttribute("InRound"),
		eliminated = player:GetAttribute("Eliminated"),
		movementViolation = player:GetAttribute("MovementViolation"),
		teamCharge = state:GetAttribute("TeamCharge"),
		teamGoal = state:GetAttribute("TeamGoal"),
	}
end
local function signature(sample)
	local world, hud = sample.world, sample.hud
	return Http:JSONEncode({
		sample.phase,
		sample.rule,
		sample.instruction,
		sample.phaseEndsAt,
		sample.accent,
		sample.stage,
		hud.text,
		hud.renderEligible,
		hud.fullyOnScreen,
		hud.textFits,
		hud.matchesInstruction,
		sample.health,
		sample.inRound,
		sample.eliminated,
		sample.movementViolation,
		world.gravity,
		world.solidTiles,
		world.warningTiles,
		world.hiddenTiles,
		world.tileLabels,
		world.tilePalette,
		world.effectsCount,
		world.stars,
		world.energy,
		world.markerWarnings,
		world.markerImpacts,
		world.laser and world.laser.transparency,
		world.laser and world.laser.color,
		world.lava and world.lava.transparency,
		world.zone and world.zone.position,
		sample.teamCharge,
		sample.teamGoal,
	})
end
local function append(sample, reason)
	if not current then
		return
	end
	if #current.events < MAX_EVENTS then
		sample.reason = reason
		table.insert(current.events, sample)
	else
		current.truncated = true
		output:SetAttribute("Truncated", true)
	end
end
local function closeCase(reason, cleanupSample)
	if not current then
		return
	end
	current.closedAt = Workspace:GetServerTimeNow()
	current.closedReason = reason
	current.cleanup = {
		sample = cleanupSample,
		exactBaselineMatch = if baseline then cleanSignature(cleanupSample.world) == baseline else nil,
		heuristicClear = cleanupSample.world.tileCount == 36
			and cleanupSample.world.solidTiles == 36
			and cleanupSample.world.effectsCount == 0
			and cleanupSample.world.laser ~= nil
			and cleanupSample.world.laser.transparency == 1
			and math.abs(cleanupSample.world.gravity - 196.2) < 0.01,
		baselineAvailable = baseline ~= nil,
	}
	local item = Instance.new("StringValue")
	item.Name = string.format("Case_%03d", count)
	item.Value = Http:JSONEncode(current)
	item.Parent = output
	output:SetAttribute("CaseCount", count)
	current, baseline, lastSignature = nil, nil, nil
end
local function finish(reason)
	if not active then
		return
	end
	active = false
	if frameConnection then
		frameConnection:Disconnect()
	end
	if healthConnection then
		healthConnection:Disconnect()
	end
	if current and lastSample then
		closeCase(reason, lastSample)
	end
	output:SetAttribute("EndReason", reason)
	output:SetAttribute("ErrorsJSON", Http:JSONEncode(errors))
	output:SetAttribute("Complete", true)
end
local function bindHealth()
	local character = player.Character
	local candidate = character and character:FindFirstChildOfClass("Humanoid")
	if candidate == humanoid then
		return
	end
	if healthConnection then
		healthConnection:Disconnect()
	end
	humanoid = candidate
	characterGeneration += 1
	if not humanoid then
		return
	end
	local previous = humanoid.Health
	local observed = humanoid
	local generation = characterGeneration
	healthConnection = humanoid.HealthChanged:Connect(function(health)
		if current and generation == characterGeneration and observed == humanoid and health < previous then
			local sample = snapshot()
			local event = {
				at = Workspace:GetServerTimeNow(),
				from = previous,
				to = health,
				generation = generation,
				phase = sample.phase,
				instruction = sample.instruction,
				stage = sample.stage,
				hud = sample.hud,
				position = sample.position,
				inRound = sample.inRound,
				movementViolation = sample.movementViolation,
			}
			if sample.phase == "Rule" and sample.rule == current.rule then
				current.firstDamage = current.firstDamage or event
				if #current.damage < MAX_DAMAGE then
					table.insert(current.damage, event)
				else
					current.damageTruncated = true
				end
			end
		end
		previous = health
	end)
end
local function step()
	if not active then
		return
	end
	if output:GetAttribute("Stop") == true then
		finish("requested_stop")
		return
	end
	if os.clock() > expires then
		finish("time_limit")
		return
	end
	bindHealth()
	local sample = snapshot()
	lastSample = sample
	local coverage = RS:FindFirstChild("QARuleCoverage")
	local key, rule, entry, behavior
	if coverage and type(coverage:GetAttribute("EntryIndex")) == "number" then
		entry = coverage:GetAttribute("EntryIndex")
		rule = coverage:GetAttribute("Current")
		behavior = coverage:GetAttribute("Behavior")
		key = "coverage:" .. tostring(entry) .. ":" .. tostring(rule)
	elseif sample.phase == "Rule" then
		rule = sample.rule
		key = "main:" .. tostring(sample.round) .. ":" .. tostring(sample.ruleIndex) .. ":" .. rule
	end
	if current and key and key ~= current.key then
		closeCase("next_case_boundary", sample)
	end
	if not current and key and count < MAX_CASES then
		count += 1
		current = {
			schemaVersion = 1,
			key = key,
			rule = rule,
			entryIndex = entry,
			behavior = behavior,
			userId = player.UserId,
			playerName = player.Name,
			openedAt = sample.at,
			startedMidRule = sample.phase == "Rule",
			events = {},
			damage = {},
			truncated = false,
			limits = "Render eligibility and center projection, not pixel/occlusion proof; 50ms nominal samples; health event order is local replication order; no damage is not a timing pass",
		}
		baseline = if sample.phase ~= "Rule" then cleanSignature(sample.world) else nil
	end
	if count >= MAX_CASES and not current and key then
		finish("case_limit")
		return
	end
	if current then
		local nowSignature = signature(sample)
		if nowSignature ~= lastSignature then
			append(sample, "presentation_transition")
			lastSignature = nowSignature
		end
	end
	if coverage and coverage:GetAttribute("Complete") == true then
		finish("coverage_complete")
	elseif not coverage and current and sample.phase ~= "Rule" then
		closeCase("main_trial_boundary", sample)
	end
end
local elapsed = 0
frameConnection = RunService.RenderStepped:Connect(function(delta)
	elapsed += delta
	if elapsed < 0.05 then
		return
	end
	elapsed = 0
	local ok, err = xpcall(step, debug.traceback)
	if not ok then
		table.insert(errors, tostring(err))
		finish("observer_error")
	end
end)
return "QAWarningEvidence active on client " .. player.UserId
