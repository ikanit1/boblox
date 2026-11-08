--!strict
-- Separate, unpublished Studio place only. No Main, profile service, remotes, or production assets.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "Experimental rules are Studio-only and not released content")
local Math = require(RS.PrototypeShared.ExperimentMath)
local Session = require(script.Parent.ExperimentSession)
local state = RS.PrototypeState
local root = Instance.new("Folder")
root.Name = "IsolatedExperiments"
root.Parent = workspace
local effects = Instance.new("Folder")
effects.Name = "TemporaryGeometry"
effects.Parent = root
local connections = {}
local destroyed = false
local active: any = nil
local entrants = {}
local seed = 0
local lastBeat, lastStage = 0, ""
local wave: BasePart? = nil

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, collidable: boolean): Part
	local object = Instance.new("Part")
	object.Name, object.Size, object.CFrame = name, size, cf
	object.Anchored, object.CanCollide, object.CanTouch, object.CanQuery = true, collidable, false, collidable
	object.Color, object.Material = color, Enum.Material.SmoothPlastic
	object.CastShadow = false
	object.Parent = root
	return object
end
part("TestFloor", Vector3.new(84, 2, 84), CFrame.new(0, 0, 0), Color3.fromRGB(35, 48, 65), true)
part("LobbyFloor", Vector3.new(70, 2, 40), CFrame.new(0, 0, 100), Color3.fromRGB(35, 48, 65), true)
for index, data in { { 0, -43, 88, 2 }, { 0, 43, 88, 2 }, { -43, 0, 2, 84 }, { 43, 0, 2, 84 } } do
	part(
		"Boundary" .. index,
		Vector3.new(data[3], 28, data[4]),
		CFrame.new(data[1], 14, data[2]),
		Color3.fromRGB(70, 90, 110),
		true
	).Transparency =
		0.75
end
local spawn = Instance.new("SpawnLocation")
spawn.Name, spawn.Anchored, spawn.Neutral = "ExperimentSpawn", true, true
spawn.Size, spawn.Position, spawn.Duration = Vector3.new(10, 1, 10), Vector3.new(0, 1.5, 110), 0
spawn.Parent = root

local function clearEffects()
	wave = nil
	effects:ClearAllChildren()
end
local function returnPlayer(player: Player, entry)
	if entry.Returned then
		return
	end
	entry.Returned = true
	local character = player.Character
	if character == entry.Character and character and character.Parent then
		local body = character:FindFirstChild("HumanoidRootPart")
		if body and body:IsA("BasePart") then
			character:PivotTo(entry.Return)
			body.AssemblyLinearVelocity, body.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end
end
local function safeReturn(player: Player, entry)
	local ok, err = pcall(returnPlayer, player, entry)
	if not ok then
		warn("Prototype return unavailable: " .. tostring(err))
	end
end
local function finish(stopped: boolean)
	if not active then
		return
	end
	local ending = active
	active = nil
	if stopped then
		local ok, err = pcall(ending.Stop)
		if not ok then
			warn("Prototype stop unavailable: " .. tostring(err))
		end
	end
	for player, entry in entrants do
		if player.Parent == Players then
			local result = ending.Players[player.UserId]
			player:SetAttribute(
				"PrototypeOutcome",
				if stopped then "Stopped" elseif result and result.Passed then "Passed" else "Failed"
			)
			safeReturn(player, entry)
		end
	end
	table.clear(entrants)
	clearEffects()
	state:SetAttribute("Stage", if stopped then "Stopped" else "Finished")
	state:SetAttribute("EndsAt", 0)
	state:SetAttribute(
		"Instruction",
		"Проверка окончена. Выбери опыт у терминала. Наград и сохранений нет."
	)
end
local function geometry()
	clearEffects()
	local plan = active.Plan
	local function at(x: number, y: number, z: number): CFrame
		local p = Math.worldPoint(Math.point(x, y, z), plan.Quarter)
		return CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, -plan.Quarter * math.pi / 2, 0)
	end
	if active.Kind == "PressureWave" then
		for index, x in plan.Covers do
			local cover = part(
				"Cover" .. index,
				Vector3.new(Math.CoverWidth, Math.CoverHeight, Math.CoverDepth),
				at(x, 7, Math.CoverZ),
				Color3.fromRGB(80, 210, 230),
				active.Stage == "Active"
			)
			cover.Transparency = if active.Stage == "Active" then 0.15 else 0.65
			cover.Parent = effects
			local marker = part(
				"Shelter" .. index,
				Vector3.new(Math.CoverWidth - 4, 0.12, 45),
				at(x, 1.1, 16),
				Color3.fromRGB(70, 180, 110),
				false
			)
			marker.Transparency, marker.Parent = 0.65, effects
		end
		wave = part(
			"PressureFront",
			Vector3.new(84, 24, 0.7),
			at(0, 13, -44),
			Color3.fromRGB(255, 185, 70),
			false
		)
		wave.Transparency, wave.Parent = 0.6, effects
	else
		for index, gate in plan.Gates do
			local leftEnd, rightStart = gate.X - Math.GapHalfWidth, gate.X + Math.GapHalfWidth
			for side, interval in { { -42, leftEnd }, { rightStart, 42 } } do
				local wall = part(
					"Gate" .. index .. "Wall" .. side,
					Vector3.new(interval[2] - interval[1], 24, 2),
					at((interval[1] + interval[2]) / 2, 13, gate.Z),
					Color3.fromRGB(125, 105, 190),
					true
				)
				-- The warning shows the next geometry without closing it around a character.
				wall.CanCollide = active.Stage == "Active"
				wall.Transparency = if wall.CanCollide then 0.15 else 0.7
				wall.Parent = effects
			end
			part(
				"Opening" .. index,
				Vector3.new((Math.GapHalfWidth - Math.BodyRadius) * 2, 0.12, 8),
				at(gate.X, 1.1, gate.Z),
				Color3.fromRGB(80, 230, 145),
				false
			).Parent =
				effects
		end
		part("FinishStrip", Vector3.new(82, 0.12, 9), at(0, 1.15, 35), Color3.fromRGB(90, 210, 255), false).Parent =
			effects
	end
end
local function liveRoot(player: Player): BasePart?
	if player.Parent ~= Players then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local body = character and character:FindFirstChild("HumanoidRootPart")
	return if character
			and character.Parent
			and humanoid
			and humanoid.Health > 0
			and body
			and body:IsA("BasePart")
		then body
		else nil
end
local function nearConsole(body: BasePart, console: BasePart): boolean
	local distance = (body.Position - console.Position).Magnitude
	return Math.finite(distance) and distance <= 13
end
local function start(player: Player, kind: string, console: BasePart)
	if active or destroyed then
		return
	end
	local body = liveRoot(player)
	if not body or not nearConsole(body, console) then
		return
	end
	local ids = {}
	local pending = {}
	for _, candidate in Players:GetPlayers() do
		local candidateRoot = liveRoot(candidate)
		if
			#ids < 12
			and candidateRoot
			and math.abs(candidateRoot.Position.X) <= 34
			and candidateRoot.Position.Z >= 82
			and candidateRoot.Position.Z <= 119
			and candidateRoot.Position.Y >= 1
			and candidateRoot.Position.Y <= 24
		then
			table.insert(ids, candidate.UserId)
			pending[candidate] = {
				Character = candidate.Character,
				Return = candidateRoot.CFrame,
				Returned = false,
				Slot = #ids,
			}
		end
	end
	if #ids == 0 then
		return
	end
	seed += 1
	active = Session.new(Math, kind, seed, ids, workspace:GetServerTimeNow())
	entrants = pending
	state:SetAttribute("Kind", kind)
	state:SetAttribute("Seed", seed)
	for candidate, entry in entrants do
		local x = ((entry.Slot - 1) % 4 - 1.5) * 8
		local z = (if kind == "ChangingWalls" then -36 else 25) + math.floor((entry.Slot - 1) / 4) * 5
		local position = Math.worldPoint(Math.point(x, 5, z), active.Plan.Quarter)
		entry.Character:PivotTo(CFrame.new(position.X, position.Y, position.Z))
		local candidateRoot = liveRoot(candidate)
		if candidateRoot then
			candidateRoot.AssemblyLinearVelocity, candidateRoot.AssemblyAngularVelocity =
				Vector3.zero, Vector3.zero
		end
		candidate:SetAttribute("PrototypeOutcome", "Playing")
	end
	lastBeat, lastStage = 0, ""
end
for index, kind in { "PressureWave", "ChangingWalls", "Stop" } do
	local console = part(
		kind,
		Vector3.new(12, 4, 5),
		CFrame.new((index - 2) * 20, 3, 92),
		Color3.fromRGB(85, 140, 190),
		true
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if kind == "Stop" then "Остановить опыт" else "Начать опыт"
	prompt.ObjectText = if kind == "PressureWave"
		then "ВОЛНА ДАВЛЕНИЯ"
		elseif kind == "ChangingWalls" then "МЕНЯЮЩИЕСЯ СТЕНЫ"
		else "СТОП"
	prompt.MaxActivationDistance, prompt.RequiresLineOfSight, prompt.HoldDuration = 10, false, 0.5
	prompt.Parent = console
	table.insert(
		connections,
		prompt.Triggered:Connect(function(player)
			if destroyed then
				return
			end
			local body = liveRoot(player)
			if not body or not nearConsole(body, console) then
				return
			end
			local ok, err = pcall(function()
				if kind == "Stop" then
					finish(true)
				else
					start(player, kind, console)
				end
			end)
			if not ok then
				warn("Prototype could not start: " .. tostring(err))
				finish(true)
			end
		end)
	)
end
state:SetAttribute("Stage", "Waiting")
state:SetAttribute(
	"Instruction",
	"ИЗОЛИРОВАННЫЕ ОПЫТЫ · Выбери терминал. Нет профиля, монет и побед основного режима."
)
local function updateExperiment()
	local samples = {}
	for player, entry in entrants do
		local body = liveRoot(player)
		if player.Parent == Players and player.Character == entry.Character and body then
			samples[player.UserId] = Math.point(body.Position.X, body.Position.Y, body.Position.Z)
		end
	end
	active.Update(workspace:GetServerTimeNow(), samples)
	for player, entry in entrants do
		if not active.Players[player.UserId].Alive and not entry.Returned then
			player:SetAttribute("PrototypeOutcome", "Failed")
			safeReturn(player, entry)
		end
	end
	if active.Completed then
		finish(false)
		return
	end
	if active.Beat ~= lastBeat or active.Stage ~= lastStage then
		if active.Kind == "PressureWave" and active.Stage == "Active" then
			local remaining = 0
			for player, entry in entrants do
				local result = active.Players[player.UserId]
				local body = liveRoot(player)
				if result.Alive and body then
					local p = Math.localPoint(
						Math.point(body.Position.X, body.Position.Y, body.Position.Z),
						active.Plan.Quarter
					)
					local overlaps = false
					for _, x in active.Plan.Covers do
						if
							math.abs(p.X - x) <= Math.CoverWidth / 2 + Math.BodyRadius + 0.05
							and math.abs(p.Z - Math.CoverZ)
								<= Math.CoverDepth / 2 + Math.BodyRadius + 0.05
						then
							overlaps = true
							break
						end
					end
					if overlaps then
						-- Fail a body inside the preview before activating collision, never kick it out.
						active.Leave(player.UserId)
						player:SetAttribute("PrototypeOutcome", "Failed")
						safeReturn(player, entry)
					else
						remaining += 1
					end
				end
			end
			if remaining == 0 then
				finish(false)
				return
			end
		end
		if active.Kind == "ChangingWalls" and active.Stage == "Active" then
			-- A preview can be explored freely; each timed route starts on its own start line.
			for player, entry in entrants do
				if active.Players[player.UserId].Alive then
					local p = Math.worldPoint(
						Math.point(
							((entry.Slot - 1) % 4 - 1.5) * 8,
							5,
							-36 + math.floor((entry.Slot - 1) / 4) * 5
						),
						active.Plan.Quarter
					)
					entry.Character:PivotTo(CFrame.new(p.X, p.Y, p.Z))
					local body = liveRoot(player)
					if body then
						body.AssemblyLinearVelocity, body.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
					end
					active.Players[player.UserId].Previous = p
				end
			end
		end
		lastBeat, lastStage = active.Beat, active.Stage
		geometry()
		state:SetAttribute("Beat", active.Beat)
		state:SetAttribute("Stage", active.Stage)
		state:SetAttribute("EndsAt", active.EndsAt)
		state:SetAttribute(
			"Instruction",
			if active.Kind == "PressureWave"
				then "Встань в зелёную тень ЗА укрытием. До волны выйди из самого экрана: внутри нельзя. Прыжок не спасает."
				elseif
					active.Stage == "Warning"
				then "Осмотри зелёные проёмы. Перед стартом вернём на линию: пройди 1 → 2 → голубой финиш."
				else "Пройди оба зелёных проёма ПО ПОРЯДКУ и останься на голубом финише. Затем путь меняется."
		)
	end
	if wave and active.Stage == "Active" then
		local p = Math.worldPoint(Math.point(0, 13, active.Front or -44), active.Plan.Quarter)
		wave.CFrame = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, -active.Plan.Quarter * math.pi / 2, 0)
	end
end
local elapsed = 0
table.insert(
	connections,
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if destroyed or elapsed < 0.05 or not active then
			return
		end
		elapsed = 0
		local ok, err = pcall(updateExperiment)
		if not ok then
			warn("Prototype stopped: " .. tostring(err))
			finish(true)
		end
	end)
)
table.insert(
	connections,
	Players.PlayerRemoving:Connect(function(player)
		if active then
			active.Leave(player.UserId)
		end
		entrants[player] = nil
	end)
)
script.Destroying:Connect(function()
	if destroyed then
		return
	end
	destroyed = true
	finish(true)
	for _, connection in connections do
		connection:Disconnect()
	end
	root:Destroy()
	state:SetAttribute("Stage", "Stopped")
	state:SetAttribute("EndsAt", 0)
end)
