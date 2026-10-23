--!strict
-- Pure and deterministic: modes affect variety, never reward rates or movement.
local RuleDeck = {}
local MODES = { "Balanced", "Reflex", "Cosmic" }
local RULES = {
	"SafeColor",
	"LaserSweep",
	"LowGravity",
	"RedLight",
	"LavaRise",
	"MeteorRain",
	"DisappearingTiles",
	"SafeZone",
	"Spinner",
}
local REFLEX: { [string]: boolean } =
	{ LaserSweep = true, RedLight = true, MeteorRain = true, Spinner = true }
local COSMIC: { [string]: boolean } =
	{ SafeColor = true, LowGravity = true, SafeZone = true, DisappearingTiles = true }

function RuleDeck.isMode(id: unknown): boolean
	return id == "Balanced" or id == "Reflex" or id == "Cosmic"
end

local function randomSource(seed: number): () -> number
	assert(seed == seed and math.abs(seed) < math.huge, "Seed must be finite")
	local value = math.floor(math.abs(seed)) % 2147483646 + 1
	return function()
		value = (value * 16807) % 2147483647
		return (value - 1) / 2147483646
	end
end

function RuleDeck.chooseMode(counts: { [string]: number }, seed: number): string
	local tied: { string } = {}
	local highest = 0
	for _, id in MODES do
		local count = counts[id] or 0
		if count > highest then
			highest = count
			table.clear(tied)
		end
		if count == highest then
			table.insert(tied, id)
		end
	end
	if highest == 0 then
		return "Balanced"
	end
	return tied[math.floor(randomSource(seed)() * #tied) + 1]
end

function RuleDeck.draw(seed: number, mode: string): { string }
	assert(RuleDeck.isMode(mode), "Unknown mode")
	local random = randomSource(seed)
	local deck: { string } = {}
	local available = table.clone(RULES)
	for trial = 1, 5 do
		local weights: { number } = {}
		local total = 0
		for index, id in available do
			local weight = 1
			if mode == "Reflex" and REFLEX[id] then
				weight = 3
			end
			if mode == "Cosmic" and COSMIC[id] then
				weight = 3
			end
			-- First encounter always has one simple spatial instruction.
			if trial == 1 and id ~= "SafeColor" and id ~= "LowGravity" and id ~= "SafeZone" then
				weight = 0
			end
			weights[index] = weight
			total += weight
		end
		local pick = random() * total
		local chosen = #available
		for index, weight in weights do
			pick -= weight
			if pick < 0 then
				chosen = index
				break
			end
		end
		local selected = table.remove(available, chosen)
		assert(selected, "Weighted draw must select an available rule")
		table.insert(deck, selected)
	end
	table.insert(deck, "ReactorRush")
	return deck
end
return RuleDeck
