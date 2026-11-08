--!strict
local Themes = require("../src/shared/RoomThemes")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
expect(Themes.id(nil) == "Laboratory", "Late loading starts with the authored laboratory")
for _, invalid in { false, "2", -1, 0, math.huge, -math.huge, 0 / 0 } do
	expect(Themes.id(invalid) == "Laboratory", "Malformed round never exposes an unknown theme")
end
for round = 1, 12 do
	expect(
		Themes.id(round) == (if round % 2 == 0 then "Orbital" else "Laboratory"),
		"Both room variants recur"
	)
	for _, role in { "Panel", "Frame", "Accent", "Orbit" } do
		local rgb, transparency = Themes.style(round, role)
		expect(rgb ~= nil and #rgb == 3, "Each decorative role has an RGB palette")
		for _, channel in rgb :: { number } do
			expect(channel >= 0 and channel <= 255 and channel % 1 == 0, "Channels stay in the engine range")
		end
		expect(
			transparency == (if role == "Orbit" then (if round % 2 == 0 then 0.15 else 1) else 0),
			"Orbital silhouette visibility is independent of gameplay"
		)
	end
end
for _, hazard in { "Tile", "Laser", "Reactor", "SafeColor", "PressureWave", "ChangingWalls", "" } do
	local rgb, transparency = Themes.style(2, hazard)
	expect(rgb == nil and transparency == nil, "Gameplay surfaces cannot acquire decorative palettes")
end
print("RoomThemes: " .. checks .. " checks passed (cosmetic policy, not rendering)")
