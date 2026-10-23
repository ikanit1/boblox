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
local OPENERS: { [string]: boolean } = { SafeColor = true, LowGravity = true, SafeZone = true }

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

-- History is optional. Only a complete five-rule deck, with an optional finale,
-- can constrain the next run; malformed/partial input behaves like no history.
local function readPreviousDeck(previousDeck: { string }?): ({ [string]: boolean }?, string?)
	if type(previousDeck) ~= "table" then
		return nil, nil
	end
	local entries = 0
	for key in previousDeck do
		entries += 1
		if entries > 6 or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 6 then
			return nil, nil
		end
	end
	if entries ~= 5 and entries ~= 6 then
		return nil, nil
	end
	if entries == 6 and previousDeck[6] ~= "ReactorRush" then
		return nil, nil
	end
	local previous: { [string]: boolean } = {}
	for index = 1, 5 do
		local id = previousDeck[index]
		if type(id) ~= "string" or not table.find(RULES, id) or previous[id] then
			return nil, nil
		end
		previous[id] = true
	end
	return previous, previousDeck[1]
end

function RuleDeck.draw(seed: number, mode: string, previousDeck: { string }?): { string }
	assert(RuleDeck.isMode(mode), "Unknown mode")
	local random = randomSource(seed)
	local previous, previousFirst = readPreviousDeck(previousDeck)
	local repeated = false
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
			if trial == 1 and (not OPENERS[id] or id == previousFirst) then
				weight = 0
			end
			-- Five draws with at most one repeat must include all four unseen rules.
			-- If every opener was seen, a different opener uses the one repeat.
			if previous and repeated and previous[id] then
				weight = 0
			end
			weights[index] = weight
			total += weight
		end
		assert(total > 0, "Deck constraints must leave an eligible rule")
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
		if previous and previous[selected] then
			repeated = true
		end
		table.insert(deck, selected)
	end
	table.insert(deck, "ReactorRush")
	return deck
end
return RuleDeck
