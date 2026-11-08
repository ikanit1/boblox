--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local RuleMath = require(script.Parent.RuleMath)
local TraversalMath = require(script.Parent.TraversalMath)
local PlayerRoster = require(script.Parent.PlayerRoster)

type TileSnapshot = {
	part: BasePart,
	colorName: string,
	color: Color3,
	material: Enum.Material,
	transparency: number,
	canCollide: boolean,
	canQuery: boolean,
	canTouch: boolean,
	labels: { [SurfaceGui]: boolean },
	texts: { [TextLabel]: string },
}
export type RuleContext = {
	roster: PlayerRoster.Roster,
	state: Folder,
	waitFor: (number, ((number, number) -> boolean?)?) -> boolean,
}
local ArenaRules = {}
local function requiredPart(parent: Instance, name: string): BasePart
	local child = parent:WaitForChild(name, 20)
	assert(child and child:IsA("BasePart"), parent:GetFullName() .. "." .. name .. " must be a BasePart")
	return child
end
local function bodyBounds(humanoid: Humanoid, root: BasePart): RuleMath.BodyBounds
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
	return {
		x = root.Position.X,
		z = root.Position.Z,
		feetY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight - legs,
		headY = root.Position.Y + root.Size.Y / 2,
		halfX = root.Size.X / 2,
		halfZ = root.Size.Z / 2,
	}
end

function ArenaRules.new(arena: Model)
	local folder = arena:WaitForChild("Tiles", 20)
	assert(folder, "Arena.Tiles is missing")
	local tiles: { TileSnapshot } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local colorName = child:GetAttribute("ColorName")
			assert(typeof(colorName) == "string" and Config.Colors[colorName], "Tile color missing")
			local labels: { [SurfaceGui]: boolean } = {}
			local texts: { [TextLabel]: string } = {}
			for _, descendant in child:GetDescendants() do
				if descendant:IsA("SurfaceGui") then
					labels[descendant] = descendant.Enabled
				elseif descendant:IsA("TextLabel") then
					texts[descendant] = descendant.Text
				end
			end
			table.insert(tiles, {
				part = child,
				colorName = colorName,
				color = child.Color,
				material = child.Material,
				transparency = child.Transparency,
				canCollide = child.CanCollide,
				canQuery = child.CanQuery,
				canTouch = child.CanTouch,
				labels = labels,
				texts = texts,
			})
		end
	end
	assert(#tiles == 36, "Expected exactly 36 authored tiles")
	table.sort(tiles, function(a, b)
		return a.part.Name < b.part.Name
	end)
	local laser = requiredPart(arena, "Laser")
	local laserCFrame, laserColor, laserSize = laser.CFrame, laser.Color, laser.Size
	local originalGravity = Workspace.Gravity
	local lunarForces: { { root: BasePart, humanoid: Humanoid, attachment: Attachment, force: VectorForce } } =
		{}
	local previousEffects = arena:FindFirstChild("RuleEffects")
	if previousEffects then
		previousEffects:Destroy()
	end
	local effects = Instance.new("Folder")
	effects.Name = "RuleEffects"
	effects.Parent = arena
	local rng = Random.new()
	local function randomInteger(minimum: number, maximum: number): number
		return rng:NextInteger(minimum, maximum)
	end
	local currentRule = ""
	local generation = 0
	local currentState: Folder? = nil
	local lunarCollectors: { [Player]: { root: BasePart, mask: number, count: number } } = {}
	local function resetLunarPickups()
		for player in lunarCollectors do
			-- Clear the goal first so delayed client replication cannot expose stale pickups.
			player:SetAttribute("LunarStarGoal", 0)
			player:SetAttribute("LunarStarMask", 0)
			player:SetAttribute("LunarStarCount", 0)
		end
		table.clear(lunarCollectors)
	end

	local function restoreTiles()
		for _, tile in tiles do
			local p = tile.part
			p.Color = tile.color
			p.Material = tile.material
			p.Transparency = tile.transparency
			p.CanCollide = tile.canCollide
			p.CanQuery = tile.canQuery
			p.CanTouch = tile.canTouch
			for label, enabled in tile.labels do
				label.Enabled = enabled
			end
			for label, originalText in tile.texts do
				label.Text = originalText
			end
		end
	end
	local function hideTile(tile: TileSnapshot)
		tile.part.CanCollide = false
		tile.part.CanQuery = false
		tile.part.CanTouch = false
		tile.part.Transparency = 1
		for label in tile.labels do
			label.Enabled = false
		end
	end
	-- Text and symbol cue that a tile is about to vanish; readable without colour or motion.
	local function warnTile(tile: TileSnapshot, word: string)
		tile.part.Color = Color3.fromRGB(255, 160, 65)
		tile.part.Transparency = 0.15
		for label in tile.texts do
			if label.Name == "Symbol" then
				label.Text = "⚠"
			elseif label.Name == "ColorText" then
				label.Text = word
			end
		end
	end
	local function tileUnder(position: Vector3): TileSnapshot?
		local half = Config.TileSize / 2
		for _, tile in tiles do
			local p = tile.part.Position
			if math.abs(position.X - p.X) <= half and math.abs(position.Z - p.Z) <= half then
				return tile
			end
		end
		return nil
	end
	local function restore()
		generation += 1
		resetLunarPickups()
		for _, binding in lunarForces do
			binding.root:SetAttribute("TrialGravityScale", nil)
			binding.force:Destroy()
			binding.attachment:Destroy()
		end
		table.clear(lunarForces)
		Workspace.Gravity = originalGravity
		restoreTiles()
		laser.CFrame = laserCFrame
		laser.Color = laserColor
		laser.Size = laserSize
		laser.Transparency = 1
		laser.CanCollide = false
		laser.CanTouch = false
		laser.CanQuery = false
		effects:ClearAllChildren()
		if currentState then
			currentState:SetAttribute("HazardStage", "Recovery")
			currentState:SetAttribute("FinaleStage", "")
			currentState:SetAttribute("StabilizeEndsAt", 0)
		end
	end
	local function part(
		name: string,
		size: Vector3,
		position: Vector3,
		color: Color3,
		collide: boolean?
	): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = position
		p.Color = color
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = collide == true
		p.CanTouch = false
		p.CanQuery = collide == true
		p.Parent = effects
		return p
	end
	local function instruction(context: RuleContext, text: string)
		context.state:SetAttribute("Instruction", text)
	end
	local function stage(context: RuleContext, value: string)
		if value == "Warning" then
			context.state:SetAttribute("HazardCycle", (context.state:GetAttribute("HazardCycle") or 0) + 1)
		end
		context.state:SetAttribute("HazardStage", value)
	end
	local function damagePlayer(player: Player, humanoid: Humanoid, amount: number)
		player:SetAttribute("LastDamageRule", currentRule)
		player:SetAttribute("LastDamageAt", Workspace:GetServerTimeNow())
		humanoid:TakeDamage(amount)
	end
	local function damageGate(cooldown: number): (Player, Humanoid, number) -> ()
		local last: { [Player]: number } = {}
		return function(player, humanoid, damage)
			local now = Workspace:GetServerTimeNow()
			if now - (last[player] or -math.huge) >= cooldown then
				last[player] = now
				damagePlayer(player, humanoid, damage)
			end
		end
	end
	local function orb(index: number, position: Vector3, energy: boolean?): BasePart
		local p = part(
			if energy then "Energy" .. index else "Star" .. index,
			Vector3.new(1.8, 1.8, 1.8),
			position,
			if energy then Color3.fromRGB(80, 225, 255) else Color3.fromRGB(255, 220, 85)
		)
		p.Shape = Enum.PartType.Ball
		local gui = Instance.new("BillboardGui")
		gui.Name = "PickupLabel"
		gui.Size = UDim2.fromOffset(64, 32)
		gui.StudsOffset = Vector3.new(0, 1.8, 0)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = if energy then "⚡ +1" else "★ +2"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 22
		label.TextColor3 = p.Color
		label.TextStrokeTransparency = 0.25
		label.Parent = gui
		gui.Parent = p
		return p
	end
	local function collect(
		context: RuleContext,
		pickups: { BasePart },
		onCollected: (() -> ())?,
		canCollect: (() -> boolean)?
	)
		context.roster.ForEachAlive(function(player, _, root)
			for index = #pickups, 1, -1 do
				if canCollect and not canCollect() then
					return
				end
				local pickup = pickups[index]
				if
					(pickup.Position - root.Position).Magnitude <= Config.LowGravity.CollectionRadius
					and context.roster.AwardStar(player)
				then
					pickup:Destroy()
					table.remove(pickups, index)
					if onCollected then
						onCollected()
					end
				end
			end
		end)
	end
	local function beamUpdate(
		context: RuleContext,
		sweepSeconds: number,
		damage: number,
		maximumElapsed: number
	): (number, number, number?) -> ()
		local hit = damageGate(1.2)
		local edge = Config.ArenaHalfSize - 0.5
		local epoch = generation
		local previousElapsed = 0
		local previous: { [Player]: { root: BasePart, body: TraversalMath.Body } } = {}
		context.roster.ForEachAlive(function(player, humanoid, root)
			previous[player] = { root = root, body = bodyBounds(humanoid, root) }
		end)
		-- Bound work by the configured trial, never by a delayed frame's delta.
		assert(
			sweepSeconds > 0 and maximumElapsed > 0 and maximumElapsed / sweepSeconds <= 8,
			"Beam timeline must contain at most eight sweeps"
		)
		return function(elapsed, _delta, observedElapsed)
			local observed = observedElapsed or elapsed
			if
				epoch ~= generation
				or not RuleMath.isFinite(elapsed)
				or not RuleMath.isFinite(observed)
				or elapsed < previousElapsed
				or observed < elapsed
			then
				return
			end
			elapsed = math.min(elapsed, maximumElapsed)
			local z = RuleMath.pingPong(elapsed, sweepSeconds, edge)
			laser.CFrame = CFrame.new(0, 1.9, z)
			local cuts = { previousElapsed }
			local firstTurn = math.floor(previousElapsed / sweepSeconds) + 1
			local lastTurn = math.min(8, math.floor(elapsed / sweepSeconds))
			for turn = firstTurn, lastTurn do
				local at = turn * sweepSeconds
				if at < elapsed then
					table.insert(cuts, at)
				end
			end
			table.insert(cuts, elapsed)
			context.roster.ForEachAlive(function(player, humanoid, root)
				local measured = bodyBounds(humanoid, root)
				local sample = previous[player]
				local before = if sample and sample.root == root then sample.body else measured
				local fraction = if observed > previousElapsed
					then math.clamp((elapsed - previousElapsed) / (observed - previousElapsed), 0, 1)
					else 1
				local after = TraversalMath.lerpBody(before, measured, fraction)
				local span = elapsed - previousElapsed
				for index = 2, #cuts do
					local start, finish = cuts[index - 1], cuts[index]
					local a = if span > 0 then (start - previousElapsed) / span else 0
					local b = if span > 0 then (finish - previousElapsed) / span else 1
					if
						TraversalMath.beamContact(
							TraversalMath.lerpBody(before, after, a),
							TraversalMath.lerpBody(before, after, b),
							RuleMath.pingPong(start, sweepSeconds, edge),
							RuleMath.pingPong(finish, sweepSeconds, edge),
							Config.ArenaHalfSize
						)
					then
						hit(player, humanoid, damage)
						break
					end
				end
				previous[player] = { root = root, body = after }
			end)
			previousElapsed = elapsed
		end
	end
	local function showBeam(warning: boolean)
		laser.CFrame = CFrame.new(0, 1.9, -Config.ArenaHalfSize + 0.5)
		laser.Transparency = if warning then 0.45 else 0.05
		laser.Color = if warning then Color3.fromRGB(255, 210, 88) else Config.Rules.LaserSweep.Accent
	end

	local function safeColor(context: RuleContext): boolean
		local previous = ""
		for callIndex = 1, Config.SafeColor.Calls do
			restoreTiles()
			stage(context, "Warning")
			local choices: { string } = {}
			for _, name in Config.ColorOrder do
				if name ~= previous then
					table.insert(choices, name)
				end
			end
			local selected = choices[rng:NextInteger(1, #choices)]
			previous = selected
			local color = Config.Colors[selected]
			context.state:SetAttribute("SafeColor", selected)
			context.state:SetAttribute("Accent", color.Color)
			instruction(
				context,
				string.format(
					"%s %s! Найди такую плитку. Смена %d/3.",
					color.Symbol,
					color.Label,
					callIndex
				)
			)
			if not context.waitFor(Config.SafeColor.WarningSeconds, nil) then
				return false
			end
			for _, tile in tiles do
				if tile.colorName ~= selected then
					hideTile(tile)
				end
			end
			stage(context, "Active")
			instruction(
				context,
				color.Symbol .. " " .. color.Label .. " — держись на своей плитке!"
			)
			if not context.waitFor(Config.SafeColor.HiddenSeconds, nil) then
				return false
			end
		end
		return true
	end

	local function laserSweep(context: RuleContext): boolean
		stage(context, "Warning")
		showBeam(true)
		instruction(
			context,
			"Луч пока безопасный. Приготовься перепрыгнуть его три раза!"
		)
		if not context.waitFor(Config.LaserSweep.WarningSeconds, nil) then
			return false
		end
		stage(context, "Active")
		showBeam(false)
		instruction(
			context,
			"Прыгай через красный луч! Каждое касание отнимает здоровье."
		)
		return context.waitFor(
			Config.LaserSweep.ActiveSeconds,
			beamUpdate(
				context,
				Config.LaserSweep.SweepSeconds,
				Config.LaserSweep.Damage,
				Config.LaserSweep.ActiveSeconds
			)
		)
	end

	local function lowGravity(context: RuleContext): boolean
		-- Freeze admission before the warning. A replacement character or a late arrival
		-- cannot inherit a participant's remaining personal pickups.
		context.roster.ForEachAlive(function(player, _, root)
			lunarCollectors[player] = { root = root, mask = 0, count = 0 }
			player:SetAttribute("LunarStarMask", 0)
			player:SetAttribute("LunarStarCount", 0)
			player:SetAttribute("LunarStarGoal", Config.LowGravity.PersonalStarGoal)
		end)
		stage(context, "Warning")
		instruction(
			context,
			"Скоро лунная гравитация! У каждого свои 3 звезды ★. Не улетай за край."
		)
		if not context.waitFor(Config.LowGravity.WarningSeconds, nil) then
			return false
		end
		-- Lunar physics belongs only to admitted participants. Changing Workspace.Gravity
		-- would also change every explorer's jump launch/trajectory in the separate station.
		context.roster.ForEachAlive(function(_, humanoid, root)
			root:SetAttribute("TrialGravityScale", Config.LowGravityMultiplier)
			local attachment = Instance.new("Attachment")
			attachment.Name = "RuleRoomLunarAttachment"
			attachment.Parent = root
			local force = Instance.new("VectorForce")
			force.Name = "RuleRoomLunarForce"
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = true
			force.Force =
				Vector3.new(0, originalGravity * (1 - Config.LowGravityMultiplier) * root.AssemblyMass, 0)
			force.Parent = root
			table.insert(
				lunarForces,
				{ root = root, humanoid = humanoid, attachment = attachment, force = force }
			)
		end)
		local stars: { BasePart } = {}
		stage(context, "Active")
		for x = -Config.TileSize * 2, Config.TileSize * 2, Config.TileSize * 2 do
			for z = -Config.TileSize * 2, Config.TileSize * 2, Config.TileSize * 2 do
				local pickup = orb(#stars + 1, Vector3.new(x, 10, z))
				pickup:SetAttribute("LunarStarIndex", #stars + 1)
				table.insert(stars, pickup)
			end
		end
		instruction(
			context,
			"Собери свои 3 звезды ★: по 2 монеты и 3 опыта. Другим они тоже доступны."
		)
		local function updateLunar()
			for _, binding in lunarForces do
				binding.force.Force = if binding.root.Parent
						and not binding.root.Anchored
						and binding.humanoid.Health > 0
					then Vector3.new(
						0,
						originalGravity * (1 - Config.LowGravityMultiplier) * binding.root.AssemblyMass,
						0
					)
					else Vector3.zero
			end
			context.roster.ForEachAlive(function(player, _, root)
				local collector = lunarCollectors[player]
				if
					not collector
					or collector.root ~= root
					or player:GetAttribute("MovementWarning") == true
					or collector.count >= Config.LowGravity.PersonalStarGoal
				then
					return
				end
				for index, pickup in stars do
					local bit = bit32.lshift(1, index - 1)
					if
						bit32.band(collector.mask, bit) == 0
						and (pickup.Position - root.Position).Magnitude <= Config.LowGravity.CollectionRadius
						and context.roster.AwardStar(player)
					then
						-- AwardStar owns current-roster, life and forfeiture checks. Rejection
						-- must consume neither this pickup nor the participant's personal quota.
						collector.mask = bit32.bor(collector.mask, bit)
						collector.count += 1
						player:SetAttribute("LunarStarMask", collector.mask)
						player:SetAttribute("LunarStarCount", collector.count)
						if collector.count >= Config.LowGravity.PersonalStarGoal then
							break
						end
					end
				end
			end)
		end
		-- Each floor warning owns a real wait/deadline, so the HUD and final warning
		-- sound count down to the disappearing floor rather than the end of the trial.
		local waves = Config.LowGravity.FloorWaves
		local elapsed = 0
		for wave, settings in waves do
			if not context.waitFor(settings.WarnAt - elapsed, updateLunar) then
				return false
			end
			restoreTiles()
			local doomed: { [TileSnapshot]: boolean } = {}
			context.roster.ForEachAlive(function(_, _, root)
				local tile = tileUnder(root.Position)
				if tile then
					doomed[tile] = true
				end
			end)
			local candidates: { TileSnapshot } = {}
			for _, tile in tiles do
				if not doomed[tile] then
					table.insert(candidates, tile)
				end
			end
			-- Draw without replacement: even repeated random indices add six distinct tiles.
			for _ = 1, math.min(Config.LowGravity.ExtraDoomedTiles, #candidates) do
				local tile = table.remove(candidates, rng:NextInteger(1, #candidates))
				doomed[tile] = true
			end
			for tile in doomed do
				warnTile(tile, "ПРОВАЛ")
			end
			stage(context, "Warning")
			instruction(
				context,
				"⚠ Пол «ПРОВАЛ» исчезнет — перепрыгни на другую плитку! Волна "
					.. wave
					.. "/"
					.. #waves
					.. "."
			)
			if not context.waitFor(settings.WarningSeconds, updateLunar) then
				return false
			end
			for tile in doomed do
				hideTile(tile)
			end
			stage(context, "Active")
			instruction(
				context,
				"Прыгай по оставшимся плиткам и собирай ★!"
			)
			elapsed = settings.WarnAt + settings.WarningSeconds
		end
		return context.waitFor(Config.LowGravity.ActiveSeconds - elapsed, updateLunar)
	end

	local function redLight(context: RuleContext): boolean
		local function signalFloor(color: Color3, word: string, symbol: string)
			for _, tile in tiles do
				tile.part.Color = color
				for label in tile.texts do
					if label.Name == "Symbol" then
						label.Text = symbol
					elseif label.Name == "ColorText" then
						label.Text = word
					end
				end
			end
		end
		for cycle = 1, 3 do
			-- The previous cycle's vanished tiles return before the next green signal.
			restoreTiles()
			stage(context, "Recovery")
			local stars: { BasePart } = {}
			for index = 1, 4 do
				local tile = tiles[rng:NextInteger(1, #tiles)].part
				table.insert(stars, orb(index, tile.Position + Vector3.new(0, 3.5, 0)))
			end
			context.state:SetAttribute("Accent", Color3.fromRGB(66, 220, 169))
			signalFloor(Color3.fromRGB(46, 170, 121), "БЕГИ", "▶")
			-- Green is a real decision: the tile each player stands on vanishes when it ends,
			-- so standing still is not a safe strategy. Red still punishes moving.
			local doomed: { [TileSnapshot]: boolean } = {}
			context.roster.ForEachAlive(function(_, _, root)
				local tile = tileUnder(root.Position)
				if tile and not doomed[tile] then
					doomed[tile] = true
					warnTile(tile, "УЙДИ")
				end
			end)
			instruction(
				context,
				"▶ ЗЕЛЁНЫЙ — уйди с плитки «УЙДИ ⚠» и беги за звёздами! Сигнал "
					.. cycle
					.. "/3."
			)
			if not context.waitFor(2.4, function()
				collect(context, stars, nil)
			end) then
				return false
			end
			for tile in doomed do
				hideTile(tile)
			end
			context.state:SetAttribute("Accent", Color3.fromRGB(255, 210, 88))
			signalFloor(Color3.fromRGB(255, 210, 88), "ЗАМРИ", "⏸")
			-- Collection has ended for this cycle. Do not leave visible rewards
			-- inviting players to move during the stop warning or red phase.
			for _, star in stars do
				star.Transparency = 1
				local label = star:FindFirstChild("PickupLabel")
				if label and label:IsA("BillboardGui") then
					label.Enabled = false
				end
			end
			stage(context, "Warning")
			instruction(context, "⏸ ПРИГОТОВЬСЯ ЗАМЕРЕТЬ!")
			if not context.waitFor(0.9, nil) then
				return false
			end
			local anchors: { [Player]: Vector3 } = {}
			context.roster.ForEachAlive(function(player, _, root)
				anchors[player] = root.Position
			end)
			context.state:SetAttribute("Accent", Config.Rules.RedLight.Accent)
			stage(context, "Active")
			signalFloor(Color3.fromRGB(190, 50, 70), "СТОЙ", "■")
			instruction(
				context,
				"■ КРАСНЫЙ — стой! Движение отнимает здоровье."
			)
			local hit = damageGate(0.9)
			if
				not context.waitFor(2.7, function()
					context.roster.ForEachAlive(function(player, humanoid, root)
						local anchor = anchors[player]
						local delta = if anchor then root.Position - anchor else Vector3.zero
						if Vector2.new(delta.X, delta.Z).Magnitude > 0.85 then
							hit(player, humanoid, 35)
							anchors[player] = root.Position
						end
					end)
				end)
			then
				return false
			end
			for _, star in stars do
				star:Destroy()
			end
		end
		return true
	end

	local function lavaRise(context: RuleContext): boolean
		stage(context, "Warning")
		local platformSize = Vector3.new(Config.TileSize * 0.8, 4, Config.TileSize * 0.8)
		local platformCenterY = 3
		local platformTop = platformCenterY + platformSize.Y / 2
		local centers: { Vector3 } = {}
		for x = -Config.TileSize * 2, Config.TileSize * 2, Config.TileSize * 2 do
			for z = -Config.TileSize * 2, Config.TileSize * 2, Config.TileSize * 2 do
				table.insert(centers, Vector3.new(x, platformCenterY, z))
			end
		end
		-- Survivors keep their break position. A solid platform must not appear inside
		-- someone: lift anyone whose body overlaps a footprint onto its top first.
		context.roster.ForEachAlive(function(_, humanoid, root)
			local bounds = bodyBounds(humanoid, root)
			for _, center in centers do
				if
					math.abs(bounds.x - center.X) <= platformSize.X / 2 + bounds.halfX
					and math.abs(bounds.z - center.Z) <= platformSize.Z / 2 + bounds.halfZ
					and bounds.feetY < platformTop
				then
					local character = humanoid.Parent
					if character and character:IsA("Model") then
						local lift = platformTop + 0.1 - bounds.feetY
						character:PivotTo(character:GetPivot() + Vector3.new(0, lift, 0))
						root.AssemblyLinearVelocity = Vector3.zero
					end
					break
				end
			end
		end)
		for _, center in centers do
			part("SafePlatform", platformSize, center, Color3.fromRGB(70, 180, 230), true)
		end
		local lava = part(
			"Lava",
			Vector3.new(Config.ArenaHalfSize * 2, 0.25, Config.ArenaHalfSize * 2),
			Vector3.new(0, 1.15, 0),
			Config.Rules.LavaRise.Accent
		)
		lava.Transparency = 0.6
		instruction(
			context,
			"Лава поднимется! Запрыгни на одну из девяти голубых платформ."
		)
		if not context.waitFor(Config.LavaRise.WarningSeconds, nil) then
			return false
		end
		instruction(
			context,
			"Оставайся на платформе! Оранжевый пол обжигает."
		)
		lava.Transparency = 0.2
		stage(context, "Active")
		local hit = damageGate(0.75)
		return context.waitFor(Config.LavaRise.ActiveSeconds, function(elapsed)
			local height = 1.2 + math.min(elapsed / 4, 1) * 1.3
			lava.Position = Vector3.new(0, height, 0)
			context.roster.ForEachAlive(function(player, humanoid, root)
				if bodyBounds(humanoid, root).feetY < height + 0.15 then
					hit(player, humanoid, 30)
				end
			end)
		end)
	end

	local function meteorRain(context: RuleContext): boolean
		local targetQueue: { number } = {}
		for wave = 1, 5 do
			stage(context, "Warning")
			local positions: { Vector3 } = {}
			local aliveIds: { number } = {}
			local aliveRoots: { [number]: BasePart } = {}
			context.roster.ForEachAlive(function(player, _, root)
				table.insert(aliveIds, player.UserId)
				aliveRoots[player.UserId] = root
			end)
			local targets
			targets, targetQueue = RuleMath.rotateMeteorTargets(aliveIds, targetQueue, 3, randomInteger)
			for _, id in targets do
				local position = aliveRoots[id].Position
				table.insert(
					positions,
					Vector3.new(
						math.clamp(position.X, -Config.ArenaHalfSize + 5.5, Config.ArenaHalfSize - 5.5),
						0,
						math.clamp(position.Z, -Config.ArenaHalfSize + 5.5, Config.ArenaHalfSize - 5.5)
					)
				)
			end
			while #positions < 5 do
				local tile = tiles[rng:NextInteger(1, #tiles)].part
				table.insert(positions, Vector3.new(tile.Position.X, 0, tile.Position.Z))
			end
			local markers: { BasePart } = {}
			local meteors: { BasePart } = {}
			for index, position in positions do
				local marker = part(
					"ImpactWarning",
					Vector3.new(11, 0.15, 11),
					position + Vector3.new(0, 1.15, 0),
					Color3.fromRGB(255, 75, 95)
				)
				marker.Transparency = 0.25
				table.insert(markers, marker)
				local meteor = part(
					"Meteor" .. index,
					Vector3.new(4, 4, 4),
					position + Vector3.new(0, 38, 0),
					Config.Rules.MeteorRain.Accent
				)
				meteor.Shape = Enum.PartType.Ball
				table.insert(meteors, meteor)
			end
			instruction(
				context,
				"⚠ Уйди с красных квадратов! Метеоры: " .. wave .. "/5."
			)
			if
				not context.waitFor(3, function(elapsed)
					for index, meteor in meteors do
						meteor.Position = positions[index]
							+ Vector3.new(0, 38 - math.max(0, elapsed - 2.3) / 0.7 * 35, 0)
					end
				end)
			then
				return false
			end
			stage(context, "Active")
			context.roster.ForEachAlive(function(player, humanoid, root)
				for _, position in positions do
					if RuleMath.insideZone(root.Position.X, root.Position.Z, position.X, position.Z, 5.5) then
						damagePlayer(player, humanoid, 65)
						break
					end
				end
			end)
			for _, marker in markers do
				marker.Color = Color3.fromRGB(255, 235, 190)
			end
			instruction(context, "УДАР! Следи за следующими метками.")
			if not context.waitFor(0.5, nil) then
				return false
			end
			for _, p in markers do
				p:Destroy()
			end
			for _, p in meteors do
				p:Destroy()
			end
		end
		return true
	end

	local function disappearingTiles(context: RuleContext): boolean
		-- Random diagonal direction and phase per trial: the pattern stays readable within
		-- a run but cannot be memorised as one fixed safe tile sequence across runs.
		local phase = rng:NextInteger(0, 2)
		local mirrored = rng:NextInteger(0, 1) == 1
		for wave = 1, 4 do
			restoreTiles()
			stage(context, "Warning")
			local doomed: { TileSnapshot } = {}
			for _, tile in tiles do
				local x = math.floor(
					(tile.part.Position.X + Config.ArenaHalfSize - Config.TileSize / 2) / Config.TileSize
				)
				local z = math.floor(
					(tile.part.Position.Z + Config.ArenaHalfSize - Config.TileSize / 2) / Config.TileSize
				)
				local diagonal = if mirrored then x - z else x + z
				if (diagonal + wave + phase) % 3 == 0 then
					table.insert(doomed, tile)
					-- Steady text and symbol cues remain readable with reduced motion.
					warnTile(tile, "ПРОВАЛ")
				end
			end
			instruction(
				context,
				"⚠ Плитки «ПРОВАЛ» исчезнут! Перейди на обычные. Волна "
					.. wave
					.. "/4."
			)
			if not context.waitFor(3, nil) then
				return false
			end
			for _, tile in doomed do
				hideTile(tile)
			end
			stage(context, "Active")
			instruction(context, "ПРОВАЛЫ! Держись на оставшемся полу.")
			if not context.waitFor(1.5, nil) then
				return false
			end
		end
		return true
	end

	local function safeZone(context: RuleContext): boolean
		local corners = {
			Vector3.new(-Config.ArenaHalfSize / 2, 1.15, -Config.ArenaHalfSize / 2),
			Vector3.new(Config.ArenaHalfSize / 2, 1.15, -Config.ArenaHalfSize / 2),
			Vector3.new(Config.ArenaHalfSize / 2, 1.15, Config.ArenaHalfSize / 2),
			Vector3.new(-Config.ArenaHalfSize / 2, 1.15, Config.ArenaHalfSize / 2),
		}
		local previous = 0
		for wave = 1, 3 do
			stage(context, "Warning")
			local index = RuleMath.nextSafeZone(previous, randomInteger)
			previous = index
			local center = corners[index]
			local zone = part(
				"SafeZone",
				Vector3.new(Config.ArenaHalfSize * 0.6, 0.2, Config.ArenaHalfSize * 0.6),
				center,
				Color3.fromRGB(66, 255, 169)
			)
			zone.Transparency = 0.25
			for _, tile in tiles do
				tile.part.Color = Color3.fromRGB(70, 81, 110)
				-- A grey floor must not keep naming its old colour; restoreTiles returns the text.
				for label in tile.texts do
					if label.Name == "Symbol" or label.Name == "ColorText" then
						label.Text = ""
					end
				end
			end
			instruction(
				context,
				"■ БЕГИ В ЗЕЛЁНЫЙ КВАДРАТ! Убежище " .. wave .. "/3."
			)
			if not context.waitFor(5.5, nil) then
				return false
			end
			local hit = damageGate(0.65)
			stage(context, "Active")
			instruction(
				context,
				"ШТОРМ! Оставайся внутри зелёного квадрата."
			)
			if
				not context.waitFor(1.5, function()
					context.roster.ForEachAlive(function(player, humanoid, root)
						if
							not RuleMath.insideZone(
								root.Position.X,
								root.Position.Z,
								center.X,
								center.Z,
								Config.ArenaHalfSize * 0.3
							)
						then
							hit(player, humanoid, 40)
						end
					end)
				end)
			then
				return false
			end
			zone:Destroy()
		end
		return true
	end

	local function spinner(context: RuleContext): boolean
		stage(context, "Warning")
		local halfLength = RuleMath.spinnerHalfLength(Config.ArenaHalfSize)
		laser.Size = Vector3.new(halfLength * 2, 1, 1)
		laser.CFrame = CFrame.new(0, 1.9, 0)
		laser.Color = Color3.fromRGB(255, 210, 88)
		laser.Transparency = 0.4
		instruction(
			context,
			"Луч начнёт вращаться. Прыгай через него и держись подальше от центра!"
		)
		if not context.waitFor(3, nil) then
			return false
		end
		laser.Color = Config.Rules.Spinner.Accent
		stage(context, "Active")
		laser.Transparency = 0.05
		instruction(context, "↻ ПРЫГАЙ ЧЕРЕЗ ВРАЩАЮЩИЙСЯ ЛУЧ!")
		local hit = damageGate(1.2)
		local previousAngle = 0
		return context.waitFor(15, function(elapsed)
			local angle = elapsed * math.pi / 4
			laser.CFrame = CFrame.new(0, 1.9, 0) * CFrame.Angles(0, angle, 0)
			local steps = math.clamp(math.ceil((angle - previousAngle) / 0.035), 1, 16)
			context.roster.ForEachAlive(function(player, humanoid, root)
				local bounds = bodyBounds(humanoid, root)
				for step = 1, steps do
					if
						RuleMath.spinnerIntersects(
							bounds,
							previousAngle + (angle - previousAngle) * step / steps,
							halfLength,
							0.5
						)
					then
						hit(player, humanoid, 35)
						break
					end
				end
			end)
			previousAngle = angle
		end)
	end

	local function traversal(context: RuleContext, pressure: boolean): boolean
		local settings = if pressure then Config.PressureWave else Config.ChangingWalls
		local quarter = randomInteger(0, 3)
		local gapX = Config.ChangingWalls.GapOffset * (if randomInteger(0, 1) == 0 then -1 else 1)
		local epoch = generation
		local function finish(completed: boolean): boolean
			if epoch == generation then
				effects:ClearAllChildren()
				stage(context, "Recovery")
			end
			return completed
		end
		local function world(point: TraversalMath.Point, plan: TraversalMath.Plan): Vector3
			local p = TraversalMath.worldPoint(point, plan.Quarter)
			return Vector3.new(p.X, p.Y, p.Z)
		end
		local function planarPart(
			name: string,
			width: number,
			height: number,
			depth: number,
			x: number,
			y: number,
			z: number,
			plan: TraversalMath.Plan,
			color: Color3
		): BasePart
			local size = if plan.Quarter % 2 == 0
				then Vector3.new(width, height, depth)
				else Vector3.new(depth, height, width)
			-- Energy screens affect the hazard, never character physics. They cannot
			-- spawn a solid volume around a player or push one out of a safe area.
			return part(name, size, world({ X = x, Y = y, Z = z }, plan), color, false)
		end
		local function label(parent: BasePart, text: string)
			local gui = Instance.new("BillboardGui")
			gui.Name = "TraversalLabel"
			gui.Size = UDim2.fromOffset(170, 32)
			gui.StudsOffset = Vector3.new(0, 2, 0)
			gui.MaxDistance = 110
			local caption = Instance.new("TextLabel")
			caption.Size = UDim2.fromScale(1, 1)
			caption.BackgroundTransparency = 0.25
			caption.BackgroundColor3 = Color3.fromRGB(15, 28, 40)
			caption.TextColor3 = Color3.new(1, 1, 1)
			caption.TextScaled = true
			caption.Text = text
			caption.Parent = gui
			gui.Parent = parent
		end
		for beat = 1, settings.Beats do
			effects:ClearAllChildren()
			local plan = TraversalMath.plan(quarter, beat, Config.ArenaHalfSize, gapX)
			local movers: { { part: BasePart, x: number } } = {}
			local frontStart = TraversalMath.front(0, Config.ArenaHalfSize, settings.BodyRadius)
			local green = Color3.fromRGB(66, 220, 169)
			local accent = Config.Rules[if pressure then "PressureWave" else "ChangingWalls"].Accent
			-- The real front starts outside the floor, behind the authored opaque walls.
			-- Keep its warning source visible inside the room without changing hit geometry.
			local source = planarPart(
				"TraversalSource",
				(Config.ArenaHalfSize - settings.BodyRadius) * 2,
				0.12,
				0.7,
				0,
				1.12,
				-Config.ArenaHalfSize + 1.5,
				plan,
				Color3.fromRGB(255, 213, 79)
			)
			source.Transparency = 0.15
			label(source, if pressure then "ВОЛНА ОТСЮДА" else "СТЕНА ОТСЮДА")
			if pressure then
				local cover = Config.PressureWave
				local shadowStart = cover.CoverZ + cover.CoverDepth / 2 + cover.BodyRadius
				local shadowEnd = Config.ArenaHalfSize - cover.BodyRadius
				for index, x in plan.Covers do
					local screen = planarPart(
						"PressureScreen" .. index,
						cover.CoverWidth,
						cover.CoverHeight,
						cover.CoverDepth,
						x,
						1 + cover.CoverHeight / 2,
						cover.CoverZ,
						plan,
						accent
					)
					screen.Transparency = 0.6
					local shadow = planarPart(
						"PressureShelter" .. index,
						cover.CoverWidth - cover.BodyRadius * 2,
						0.1,
						shadowEnd - shadowStart,
						x,
						1.08,
						(shadowStart + shadowEnd) / 2,
						plan,
						green
					)
					shadow.Transparency = 0.45
					label(shadow, "↓ ЗА ЭКРАНОМ")
				end
				local wave = planarPart(
					"PressureFront",
					Config.ArenaHalfSize * 2,
					settings.Height,
					0.5,
					0,
					1 + settings.Height / 2,
					frontStart,
					plan,
					accent
				)
				wave.Transparency = 0.7
				table.insert(movers, { part = wave, x = 0 })
				instruction(
					context,
					if beat == 1
						then "Волна идёт от яркой стены! Встань на зелёный след ЗА экраном."
						else "Волна с другой стороны! Найди НОВЫЙ зелёный след за экраном."
				)
			else
				local half = Config.ArenaHalfSize
				local opening = Config.ChangingWalls.GapHalfWidth
				for index, segment in { { -half, plan.GapX - opening }, { plan.GapX + opening, half } } do
					local center = (segment[1] + segment[2]) / 2
					local wall = planarPart(
						"ChangingWall" .. index,
						segment[2] - segment[1],
						settings.Height,
						1,
						center,
						1 + settings.Height / 2,
						frontStart,
						plan,
						accent
					)
					wall.Transparency = 0.5
					table.insert(movers, { part = wall, x = center })
				end
				local lane = planarPart(
					"WallOpening",
					(opening - settings.BodyRadius) * 2,
					0.1,
					(half - settings.BodyRadius) * 2,
					plan.GapX,
					1.08,
					0,
					plan,
					green
				)
				lane.Transparency = 0.5
				label(lane, "↕ ПРОЁМ")
				instruction(
					context,
					if beat == 1
						then "Стена с проёмом пойдёт через комнату. Перейди на зелёную полосу!"
						else "Следующая стена с другой стороны! Зелёный проём СМЕНИЛ МЕСТО."
				)
			end
			stage(context, "Warning")
			if not context.waitFor(settings.WarningSeconds, nil) or epoch ~= generation then
				return finish(false)
			end
			local previous: { [Player]: { root: BasePart, point: TraversalMath.Point } } = {}
			local hit: { [Player]: boolean } = {}
			context.roster.ForEachAlive(function(player, _, root)
				previous[player] =
					{ root = root, point = { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z } }
			end)
			local previousElapsed = 0
			local startedAt = Workspace:GetServerTimeNow()
			local active = true
			local function safe(before: TraversalMath.Point, after: TraversalMath.Point): boolean
				if pressure then
					local c = Config.PressureWave
					local first = TraversalMath.shelterIndex(
						before,
						plan,
						c.CoverWidth,
						c.CoverDepth,
						c.CoverZ,
						c.CoverHeight,
						c.BodyRadius
					)
					return first ~= nil
						and first
							== TraversalMath.shelterIndex(
								after,
								plan,
								c.CoverWidth,
								c.CoverDepth,
								c.CoverZ,
								c.CoverHeight,
								c.BodyRadius
							)
				end
				return TraversalMath.inGap(
					before,
					plan,
					Config.ChangingWalls.GapHalfWidth,
					settings.BodyRadius
				) and TraversalMath.inGap(
					after,
					plan,
					Config.ChangingWalls.GapHalfWidth,
					settings.BodyRadius
				)
			end
			local function update(elapsed: number, _delta: number)
				if
					not active
					or epoch ~= generation
					or not TraversalMath.finite(elapsed)
					or elapsed < previousElapsed
				then
					return
				end
				local clippedElapsed = math.min(elapsed, settings.ActiveSeconds)
				local frontBefore = TraversalMath.front(
					previousElapsed / settings.ActiveSeconds,
					Config.ArenaHalfSize,
					settings.BodyRadius
				)
				local frontAfter = TraversalMath.front(
					clippedElapsed / settings.ActiveSeconds,
					Config.ArenaHalfSize,
					settings.BodyRadius
				)
				for _, moving in movers do
					moving.part.Position =
						world({ X = moving.x, Y = 1 + settings.Height / 2, Z = frontAfter }, plan)
				end
				context.roster.ForEachAlive(function(player, humanoid, root)
					local sample = previous[player]
					local position = { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z }
					local point = if sample and sample.root == root
						then TraversalMath.clip(
							sample.point,
							position,
							previousElapsed,
							elapsed,
							settings.ActiveSeconds
						)
						else nil
					local unsafe = point == nil
					if point and sample then
						local enter, leave = TraversalMath.contactInterval(
							sample.point,
							point,
							frontBefore,
							frontAfter,
							plan.Quarter,
							settings.BodyRadius
						)
						if enter and leave then
							unsafe = not safe(
								TraversalMath.lerp(sample.point, point, enter),
								TraversalMath.lerp(sample.point, point, leave)
							)
						end
						previous[player] = { root = root, point = point }
					end
					if unsafe and not hit[player] then
						hit[player] = true
						damagePlayer(player, humanoid, settings.Damage)
					end
				end)
				previousElapsed = clippedElapsed
			end
			stage(context, "Active")
			for _, moving in movers do
				moving.part.Transparency = if pressure then 0.7 else 0.3
			end
			instruction(
				context,
				if pressure
					then "ВОЛНА! Держись зелёного следа за экраном, пока фронт не пройдёт."
					else "СТЕНА ДВИЖЕТСЯ! Пройди через зелёный проём — перепрыгнуть стену нельзя."
			)
			local completed = context.waitFor(settings.ActiveSeconds, update)
			if completed and epoch == generation then
				-- Main's half-open timer deliberately omits a late callback. Close only
				-- swept geometry here, clipped to the deadline; never pickups or rewards.
				update(math.max(settings.ActiveSeconds, Workspace:GetServerTimeNow() - startedAt), 0)
			end
			active = false
			if not completed or epoch ~= generation then
				return finish(false)
			end
			effects:ClearAllChildren()
			stage(context, "Recovery")
			if not context.waitFor(settings.RecoverySeconds, nil) or epoch ~= generation then
				return finish(false)
			end
		end
		return finish(true)
	end

	local function reactorRush(context: RuleContext): boolean
		local epoch = generation
		stage(context, "Warning")
		local goal = RuleMath.teamGoal(context.roster.AliveCount())
		context.state:SetAttribute("TeamCharge", 0)
		context.state:SetAttribute("TeamGoal", goal)
		context.state:SetAttribute("FinaleSuccess", false)
		context.state:SetAttribute("FinaleStage", "Collect")
		context.state:SetAttribute("StabilizeEndsAt", 0)
		local pickups: { BasePart } = {}
		local shuffled = table.clone(tiles)
		for index = #shuffled, 2, -1 do
			local swap = rng:NextInteger(1, index)
			shuffled[index], shuffled[swap] = shuffled[swap], shuffled[index]
		end
		for index = 1, math.min(goal + 6, #shuffled) do
			table.insert(pickups, orb(index, shuffled[index].part.Position + Vector3.new(0, 3.5, 0), true))
		end
		local function clearPickups()
			for _, pickup in pickups do
				pickup:Destroy()
			end
			table.clear(pickups)
		end
		local function fail(completed: boolean): boolean
			clearPickups()
			if epoch == generation then
				context.state:SetAttribute("FinaleStage", "Failed")
				context.state:SetAttribute("StabilizeEndsAt", 0)
				context.state:SetAttribute("FinaleSuccess", false)
			end
			return completed
		end
		showBeam(true)
		instruction(
			context,
			"ОБЩИЙ ФИНАЛ! Соберите "
				.. goal
				.. " зарядов ⚡ и перепрыгивайте луч."
		)
		if not context.waitFor(Config.ReactorRush.WarningSeconds, nil) or epoch ~= generation then
			return fail(false)
		end
		showBeam(false)
		stage(context, "Active")
		instruction(
			context,
			"Заряды общие для команды! ⚡ собирай бегом, красный луч перепрыгивай."
		)
		local charge = 0
		local sweep = beamUpdate(
			context,
			Config.ReactorRush.SweepSeconds,
			30,
			Config.ReactorRush.ActiveSeconds + Config.ReactorRush.StabilizeSeconds
		)
		local collecting = true
		local collectElapsed = 0
		local completed = context.waitFor(Config.ReactorRush.ActiveSeconds, function(elapsed, delta)
			if not collecting or epoch ~= generation then
				return false
			end
			-- Collection is half-open; a delayed or exact-deadline callback cannot
			-- create a last charge, even if an adapter erroneously invokes it.
			if not RuleMath.isFinite(elapsed) or elapsed < collectElapsed then
				return false
			end
			if elapsed >= Config.ReactorRush.ActiveSeconds then
				collecting = false
				return false
			end
			collectElapsed = elapsed
			sweep(elapsed, delta)
			if context.roster.AliveCount() == 0 then
				return false
			end
			collect(context, pickups, function()
				charge += 1
				context.state:SetAttribute("TeamCharge", charge)
			end, function()
				return charge < goal and epoch == generation
			end)
			if charge >= goal then
				collecting = false
				return true
			end
			return false
		end)
		collecting = false
		clearPickups()
		if not completed or epoch ~= generation or context.roster.AliveCount() == 0 then
			return fail(false)
		end
		if charge < goal then
			return fail(true)
		end
		context.state:SetAttribute("FinaleStage", "Stabilizing")
		context.state:SetAttribute(
			"StabilizeEndsAt",
			Workspace:GetServerTimeNow() + Config.ReactorRush.StabilizeSeconds
		)
		instruction(
			context,
			"⚡ ЗАРЯД СОБРАН! Стабилизация 4 секунды — перепрыгивай луч!"
		)
		local stabilizing = true
		local stabilizeElapsed = 0
		local stabilizeStartedAt = Workspace:GetServerTimeNow()
		local stabilized = context.waitFor(Config.ReactorRush.StabilizeSeconds, function(elapsed, delta)
			if
				stabilizing
				and epoch == generation
				and RuleMath.isFinite(elapsed)
				and elapsed >= stabilizeElapsed
				and elapsed < Config.ReactorRush.StabilizeSeconds
			then
				stabilizeElapsed = elapsed
				-- The existing beam continues from its collected-charge position.
				-- No new hazard or unannounced direction reset starts here.
				sweep(collectElapsed + elapsed, delta)
			end
			return false
		end)
		stabilizing = false
		if stabilized and epoch == generation then
			-- Close geometry only. A late root observation is interpolated back to
			-- the stabilization deadline, and turnaround segments are checked separately.
			sweep(
				collectElapsed + Config.ReactorRush.StabilizeSeconds,
				0,
				collectElapsed
					+ math.max(
						Config.ReactorRush.StabilizeSeconds,
						Workspace:GetServerTimeNow() - stabilizeStartedAt
					)
			)
		end
		local success = epoch == generation
			and RuleMath.finaleSucceeded(charge, goal, stabilized, context.roster.AliveCount())
		if not success then
			return fail(false)
		end
		context.state:SetAttribute("FinaleSuccess", true)
		context.state:SetAttribute("FinaleStage", "Complete")
		context.state:SetAttribute("StabilizeEndsAt", 0)
		return true
	end

	local handlers: { [string]: (RuleContext) -> boolean } = {
		SafeColor = safeColor,
		LaserSweep = laserSweep,
		LowGravity = lowGravity,
		RedLight = redLight,
		LavaRise = lavaRise,
		MeteorRain = meteorRain,
		DisappearingTiles = disappearingTiles,
		SafeZone = safeZone,
		Spinner = spinner,
		PressureWave = function(context)
			return traversal(context, true)
		end,
		ChangingWalls = function(context)
			return traversal(context, false)
		end,
		ReactorRush = reactorRush,
	}
	return {
		ArenaSpawn = requiredPart(arena, "ArenaSpawn").CFrame,
		LobbySpawn = requiredPart(arena, "LobbySpawn").CFrame,
		Restore = restore,
		Run = function(id: string, context: RuleContext): boolean
			local handler = handlers[id]
			assert(handler, "Unknown rule " .. id)
			resetLunarPickups()
			generation += 1
			currentRule = id
			currentState = context.state
			context.state:SetAttribute("HazardCycle", 0)
			context.state:SetAttribute("FinaleStage", "")
			context.state:SetAttribute("StabilizeEndsAt", 0)
			return handler(context)
		end,
		Destroy = function()
			restore()
			effects:Destroy()
		end,
	}
end
return ArenaRules
