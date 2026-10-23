-- Offline rbx-dom semantics: no Roblox physics, UI rendering, or live playtest.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local place = roblox.deserializePlace(fs.readFile("build/RuleRoom.rbxlx"))
local arena = place:GetService("Workspace").Arena
local counts = { Blue = 0, Pink = 0, Yellow = 0, Green = 0 }
for _, tile in arena.Tiles:GetChildren() do
	local color = tile:GetAttribute("ColorName")
	assert(counts[color] ~= nil, `Invalid tile attribute: {tostring(color)}`)
	counts[color] += 1
	assert(tile.Size == roblox.Vector3.new(10, 2, 10))
	assert(tile.Anchored and tile.CanCollide)
	assert(tile.TileLabel.ColorText.Text ~= "")
end
for color, count in counts do
	assert(count == 9, `{color} has {count} tiles, expected 9`)
end
assert(arena.LobbySpawn.CFrame.Position == roblox.Vector3.new(0, 3, 52))
assert(arena.ArenaSpawn.CFrame.Position == roblox.Vector3.new(0, 5, 0))
assert(arena.Laser.Transparency == 1 and not arena.Laser.CanCollide)
assert(place:GetService("StarterGui").RuleRoomHUD.ResetOnSpawn == false)
print("Offline model semantics passed: tile attributes, dimensions, spawn positions, HUD lifecycle.")
