--!strict

-- Manual, read-only checks. This ModuleScript is never required by the game loop.
-- Run in the Studio SERVER command bar during Results / Voting / Break / Waiting:
-- require(game.ServerScriptService.RuleRoomServer.StudioChecks).AssertIdleRestoration()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("RuleRoomShared"):WaitForChild("GameConfig"))

local StudioChecks = {}

function StudioChecks.AssertIdleRestoration()
	assert(RunService:IsStudio() and RunService:IsServer(), "Run this check in a Studio server session")
	local state = ReplicatedStorage:FindFirstChild("RuleRoomState")
	assert(state and state:IsA("Folder"), "Replicated state folder exists")
	local phase = state:GetAttribute("Phase")
	assert(
		phase == "Results" or phase == "Voting" or phase == "Break" or phase == "Waiting",
		"Wait until the current rule ends"
	)
	assert(state:GetAttribute("RuleId") == "", "Idle state must not advertise a running rule")
	assert(state:GetAttribute("SafeColor") == "", "Safe color cue must be cleared")
	assert(state:GetAttribute("RuleCount") == 6, "Six trials per alpha run")
	assert(math.abs(Workspace.Gravity - 196.2) < 0.01, "Gravity must return to authored 196.2")
	local arena = Workspace:FindFirstChild("Arena")
	assert(arena, "Authored arena exists")
	local tiles = arena:FindFirstChild("Tiles")
	assert(tiles, "Floor tile folder exists")
	local count = 0
	for _, tile in tiles:GetChildren() do
		if tile:IsA("BasePart") then
			count += 1
			assert(tile.CanCollide and tile.CanQuery, "Floor collision/query must be restored: " .. tile.Name)
			assert(tile.Transparency == 0, "Floor tile must be visible: " .. tile.Name)
			local color = Config.Colors[tile:GetAttribute("ColorName")]
			for _, descendant in tile:GetDescendants() do
				if descendant:IsA("SurfaceGui") then
					assert(descendant.Enabled, "Floor text/symbol must be restored: " .. tile.Name)
				elseif descendant:IsA("TextLabel") and descendant.Name == "Symbol" then
					assert(descendant.Text == color.Symbol, "Warning symbol must be restored: " .. tile.Name)
				elseif descendant:IsA("TextLabel") and descendant.Name == "ColorText" then
					assert(descendant.Text == color.Label, "Warning text must be restored: " .. tile.Name)
				end
			end
		end
	end
	assert(count == 36, "All 36 authored floor tiles remain")
	local laser = arena:FindFirstChild("Laser")
	assert(laser and laser:IsA("BasePart"), "Laser exists")
	assert(laser.Transparency == 1 and not laser.CanCollide, "Laser is hidden and non-collidable")
	assert(
		laser.Size == Vector3.new(Config.ArenaHalfSize * 2, 1, 1),
		"Spinner must restore the authored beam size"
	)
	local effects = arena:FindFirstChild("RuleEffects")
	assert(not effects or #effects:GetChildren() == 0, "Temporary hazards, platforms and pickups are removed")
	for _, player in Players:GetPlayers() do
		assert(player:GetAttribute("InRound") == false, "Idle players must have no active round slot")
		local stats = player:FindFirstChild("leaderstats")
		assert(stats, "Session score folder exists")
		local score = stats:FindFirstChild("Score")
		local best = stats:FindFirstChild("Best")
		assert(score and score:IsA("IntValue") and best and best:IsA("IntValue"), "Both session scores exist")
		assert(score.Value >= 0 and best.Value >= 0 and best.Value <= score.Value, "Score invariants hold")
	end
	print(
		"[RuleRoom] Idle restoration checks passed: 36 tiles, labels, gravity, laser, pickups and player flags"
	)
	return true
end

return StudioChecks
