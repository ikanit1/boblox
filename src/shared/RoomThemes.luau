--!strict
-- Presentation-only palettes. Neither theme changes a hazard or a collision surface.
local RoomThemes = {}
local palettes = {
	Laboratory = {
		Name = "РЕАКТОРНАЯ ЛАБОРАТОРИЯ",
		Panel = { 36, 53, 73 },
		Frame = { 72, 98, 119 },
		Accent = { 139, 201, 226 },
		Orbit = false,
	},
	Orbital = {
		Name = "ОРБИТАЛЬНАЯ СТАНЦИЯ",
		Panel = { 25, 31, 54 },
		Frame = { 80, 82, 113 },
		Accent = { 177, 182, 235 },
		Orbit = true,
	},
}

function RoomThemes.id(round: any): string
	if type(round) ~= "number" or round ~= round or math.abs(round) == math.huge or round < 1 then
		return "Laboratory"
	end
	return if math.floor(round) % 2 == 0 then "Orbital" else "Laboratory"
end

function RoomThemes.palette(round: any): any
	return palettes[RoomThemes.id(round)]
end

function RoomThemes.style(round: any, role: any): ({ number }?, number?)
	local palette = RoomThemes.palette(round)
	if role == "Orbit" then
		return palette.Accent, if palette.Orbit then 0.15 else 1
	elseif role == "Panel" or role == "Frame" or role == "Accent" then
		return palette[role], 0
	end
	return nil, nil
end

return RoomThemes
