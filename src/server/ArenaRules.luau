--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))
local RuleMath = require(script.Parent.RuleMath)
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
	waitFor: (number, ((number, number) -> ())?) -> boolean,
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
	local previousEffects = arena:FindFirstChild("RuleEffects")
	if previousEffects then
		previousEffects:Destroy()
	end
	local effects = Instance.new("Folder")
	effects.Name = "RuleEffects"
	effects.Parent = arena
	local rng = Random.new()

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
	local function restore()
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
	local function damageGate(cooldown: number): (Player, Humanoid, number) -> ()
		local last: { [Player]: number } = {}
		return function(player, humanoid, damage)
			local now = Workspace:GetServerTimeNow()
			if now - (last[player] or -math.huge) >= cooldown then
				last[player] = now
				humanoid:TakeDamage(damage)
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
	local function collect(context: RuleContext, pickups: { BasePart }, onCollected: (() -> ())?)
		context.roster.ForEachAlive(function(player, _, root)
			for index = #pickups, 1, -1 do
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
		damage: number
	): (number, number) -> ()
		local hit = damageGate(1.2)
		local previousZ = -29.5
		return function(elapsed)
			local z = RuleMath.pingPong(elapsed, sweepSeconds, 29.5)
			laser.CFrame = CFrame.new(0, 1.9, z)
			context.roster.ForEachAlive(function(player, humanoid, root)
				if
					RuleMath.sweptBeamIntersects(bodyBounds(humanoid, root), previousZ, z, 1.9, 0.5, 0.5, 30)
				then
					hit(player, humanoid, damage)
				end
			end)
			previousZ = z
		end
	end
	local function showBeam(warning: boolean)
		laser.CFrame = CFrame.new(0, 1.9, -29.5)
		laser.Transparency = if warning then 0.45 else 0.05
		laser.Color = if warning then Color3.fromRGB(255, 210, 88) else Config.Rules.LaserSweep.Accent
	end

	local function safeColor(context: RuleContext): boolean
		local previous = ""
		for callIndex = 1, Config.SafeColor.Calls do
			restoreTiles()
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
		showBeam(true)
		instruction(
			context,
			"Луч пока безопасный. Приготовься перепрыгнуть его три раза!"
		)
		if not context.waitFor(Config.LaserSweep.WarningSeconds, nil) then
			return false
		end
		showBeam(false)
		instruction(
			context,
			"Прыгай через красный луч! Каждое касание отнимает здоровье."
		)
		return context.waitFor(
			Config.LaserSweep.ActiveSeconds,
			beamUpdate(context, Config.LaserSweep.SweepSeconds, 35)
		)
	end

	local function lowGravity(context: RuleContext): boolean
		instruction(
			context,
			"Скоро лунная гравитация! Прыгай к звёздам ★, но не улетай за край."
		)
		if not context.waitFor(Config.LowGravity.WarningSeconds, nil) then
			return false
		end
		Workspace.Gravity = originalGravity * Config.LowGravityMultiplier
		local stars: { BasePart } = {}
		for x = -20, 20, 20 do
			for z = -20, 20, 20 do
				table.insert(stars, orb(#stars + 1, Vector3.new(x, 10, z)))
			end
		end
		instruction(
			context,
			"Выше прыжок — больше звёзд! ★ дают очки, монеты и опыт."
		)
		return context.waitFor(Config.LowGravity.ActiveSeconds, function()
			collect(context, stars, nil)
		end)
	end

	local function redLight(context: RuleContext): boolean
		for cycle = 1, 3 do
			local stars: { BasePart } = {}
			for index = 1, 4 do
				local tile = tiles[rng:NextInteger(1, #tiles)].part
				table.insert(stars, orb(index, tile.Position + Vector3.new(0, 3.5, 0)))
			end
			context.state:SetAttribute("Accent", Color3.fromRGB(66, 220, 169))
			for _, tile in tiles do
				tile.part.Color = Color3.fromRGB(46, 170, 121)
			end
			instruction(
				context,
				"▶ ЗЕЛЁНЫЙ — беги за звёздами! Сигнал " .. cycle .. "/3."
			)
			if not context.waitFor(2.4, function()
				collect(context, stars, nil)
			end) then
				return false
			end
			context.state:SetAttribute("Accent", Color3.fromRGB(255, 210, 88))
			instruction(context, "⏸ ПРИГОТОВЬСЯ ЗАМЕРЕТЬ!")
			if not context.waitFor(0.9, nil) then
				return false
			end
			local anchors: { [Player]: Vector3 } = {}
			context.roster.ForEachAlive(function(player, _, root)
				anchors[player] = root.Position
			end)
			context.state:SetAttribute("Accent", Config.Rules.RedLight.Accent)
			for _, tile in tiles do
				tile.part.Color = Color3.fromRGB(190, 50, 70)
			end
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
		for x = -20, 20, 20 do
			for z = -20, 20, 20 do
				part(
					"SafePlatform",
					Vector3.new(8, 4, 8),
					Vector3.new(x, 3, z),
					Color3.fromRGB(70, 180, 230),
					true
				)
			end
		end
		local lava =
			part("Lava", Vector3.new(60, 0.25, 60), Vector3.new(0, 1.15, 0), Config.Rules.LavaRise.Accent)
		lava.Transparency = 0.6
		instruction(
			context,
			"Лава поднимется! Запрыгни на одну из девяти голубых платформ."
		)
		if not context.waitFor(4, nil) then
			return false
		end
		instruction(
			context,
			"Оставайся на платформе! Оранжевый пол обжигает."
		)
		lava.Transparency = 0.2
		local hit = damageGate(0.75)
		return context.waitFor(14, function(elapsed)
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
		for wave = 1, 5 do
			local positions: { Vector3 } = {}
			context.roster.ForEachAlive(function(_, _, root)
				if #positions < 3 then
					table.insert(
						positions,
						Vector3.new(
							math.clamp(root.Position.X, -24, 24),
							0,
							math.clamp(root.Position.Z, -24, 24)
						)
					)
				end
			end)
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
			context.roster.ForEachAlive(function(_, humanoid, root)
				for _, position in positions do
					if RuleMath.insideZone(root.Position.X, root.Position.Z, position.X, position.Z, 5.5) then
						humanoid:TakeDamage(65)
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
		for wave = 1, 4 do
			restoreTiles()
			local doomed: { TileSnapshot } = {}
			for _, tile in tiles do
				local x = math.floor((tile.part.Position.X + 25) / 10)
				local z = math.floor((tile.part.Position.Z + 25) / 10)
				if (x + z + wave) % 3 == 0 then
					table.insert(doomed, tile)
					tile.part.Color = Color3.fromRGB(255, 160, 65)
					tile.part.Transparency = 0.15
					-- Steady text and symbol cues remain readable with reduced motion.
					for label in tile.texts do
						if label.Name == "Symbol" then
							label.Text = "⚠"
						elseif label.Name == "ColorText" then
							label.Text = "ПРОВАЛ"
						end
					end
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
			instruction(context, "ПРОВАЛЫ! Держись на оставшемся полу.")
			if not context.waitFor(1.5, nil) then
				return false
			end
		end
		return true
	end

	local function safeZone(context: RuleContext): boolean
		local corners = {
			Vector3.new(-15, 1.15, -15),
			Vector3.new(15, 1.15, -15),
			Vector3.new(15, 1.15, 15),
			Vector3.new(-15, 1.15, 15),
		}
		local previous = 0
		for wave = 1, 3 do
			local index = (previous + rng:NextInteger(1, 3) - 1) % 4 + 1
			previous = index
			local center = corners[index]
			local zone = part("SafeZone", Vector3.new(18, 0.2, 18), center, Color3.fromRGB(66, 255, 169))
			zone.Transparency = 0.25
			for _, tile in tiles do
				tile.part.Color = Color3.fromRGB(70, 81, 110)
			end
			instruction(
				context,
				"■ БЕГИ В ЗЕЛЁНЫЙ КВАДРАТ! Убежище " .. wave .. "/3."
			)
			if not context.waitFor(4.5, nil) then
				return false
			end
			local hit = damageGate(0.65)
			instruction(
				context,
				"ШТОРМ! Оставайся внутри зелёного квадрата."
			)
			if
				not context.waitFor(1.5, function()
					context.roster.ForEachAlive(function(player, humanoid, root)
						if
							not RuleMath.insideZone(root.Position.X, root.Position.Z, center.X, center.Z, 9)
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

	local function reactorRush(context: RuleContext): boolean
		local goal = RuleMath.teamGoal(context.roster.AliveCount())
		context.state:SetAttribute("TeamCharge", 0)
		context.state:SetAttribute("TeamGoal", goal)
		context.state:SetAttribute("FinaleSuccess", false)
		local pickups: { BasePart } = {}
		local shuffled = table.clone(tiles)
		for index = #shuffled, 2, -1 do
			local swap = rng:NextInteger(1, index)
			shuffled[index], shuffled[swap] = shuffled[swap], shuffled[index]
		end
		for index = 1, math.min(goal + 6, #shuffled) do
			table.insert(pickups, orb(index, shuffled[index].part.Position + Vector3.new(0, 3.5, 0), true))
		end
		showBeam(true)
		instruction(
			context,
			"ОБЩИЙ ФИНАЛ! Соберите "
				.. goal
				.. " зарядов ⚡ и перепрыгивайте луч."
		)
		if not context.waitFor(3, nil) then
			return false
		end
		showBeam(false)
		instruction(
			context,
			"Заряды общие для команды! ⚡ собирай бегом, красный луч перепрыгивай."
		)
		local charge = 0
		local sweep = beamUpdate(context, 7, 30)
		local completed = context.waitFor(19, function(elapsed, delta)
			sweep(elapsed, delta)
			collect(context, pickups, function()
				charge += 1
				context.state:SetAttribute("TeamCharge", charge)
				if charge >= goal then
					instruction(
						context,
						"⚡ РЕАКТОР ЗАРЯЖЕН! Доживи до конца, перепрыгивая луч!"
					)
				end
			end)
		end)
		context.state:SetAttribute(
			"FinaleSuccess",
			RuleMath.finaleSucceeded(charge, goal, completed, context.roster.AliveCount())
		)
		return completed
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
		ReactorRush = reactorRush,
	}
	return {
		ArenaSpawn = requiredPart(arena, "ArenaSpawn").CFrame,
		LobbySpawn = requiredPart(arena, "LobbySpawn").CFrame,
		Restore = restore,
		Run = function(id: string, context: RuleContext): boolean
			local handler = handlers[id]
			assert(handler, "Unknown rule " .. id)
			return handler(context)
		end,
		Destroy = function()
			restore()
			effects:Destroy()
		end,
	}
end
return ArenaRules
