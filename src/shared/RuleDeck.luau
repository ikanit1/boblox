--!strict
-- Pure and deterministic: modes affect variety, never reward rates or movement.
local RuleDeck = {}
export type Category = "Spatial" | "Reflex" | "Movement"
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
	"PressureWave",
	"ChangingWalls",
}
local CATEGORIES: { [string]: Category } = {
	SafeColor = "Spatial",
	DisappearingTiles = "Spatial",
	SafeZone = "Spatial",
	LavaRise = "Spatial",
	LaserSweep = "Reflex",
	Spinner = "Reflex",
	MeteorRain = "Reflex",
	RedLight = "Reflex",
	LowGravity = "Movement",
	PressureWave = "Spatial",
	ChangingWalls = "Movement",
}
local REFLEX: { [string]: boolean } =
	{ LaserSweep = true, RedLight = true, MeteorRain = true, Spinner = true, ChangingWalls = true }
local COSMIC: { [string]: boolean } =
	{ SafeColor = true, LowGravity = true, SafeZone = true, DisappearingTiles = true, PressureWave = true }

function RuleDeck.category(id: string): Category?
	return CATEGORIES[id]
end

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
	local lastCategory: Category? = nil
	local streak = 0
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
			if streak >= 2 and CATEGORIES[id] == lastCategory then
				weight = 0
			end
			weights[index] = weight
			total += weight
		end
		-- Stage 1 has three easy choices; stage 2 cannot have a category ban.
		-- At stages 3-5, at least seven rules remain. The largest category has five
		-- members and already used two, so other categories remain available.
		-- Thus every legal prefix can finish with positive weights in every mode.
		assert(total > 0, "A legal rule must remain available")
		local pick = random() * total
		local chosen: number? = nil
		for index, weight in weights do
			pick -= weight
			if pick < 0 then
				chosen = index
				break
			end
		end
		assert(chosen, "Weighted draw must select a legal rule")
		local selected = table.remove(available, chosen)
		assert(selected, "Weighted draw must select an available rule")
		table.insert(deck, selected)
		local category = CATEGORIES[selected]
		streak = if category == lastCategory then streak + 1 else 1
		lastCategory = category
	end
	table.insert(deck, "ReactorRush")
	return deck
end

-- Disabling rules changes which prefixes can finish. Weight only choices that still
-- have a legal completion; retries with another seed are never needed for recovery.
function RuleDeck.tryDraw(seed: any, mode: any, disabled: any): ({ string }?, string?)
	if type(seed) ~= "number" or seed ~= seed or math.abs(seed) == math.huge then
		return nil, "InvalidSeed"
	end
	if not RuleDeck.isMode(mode) then
		return nil, "InvalidMode"
	end
	if disabled ~= nil and type(disabled) ~= "table" then
		return nil, "InvalidDisabledRules"
	end
	disabled = disabled or {}
	if disabled.ReactorRush == true then
		return nil, "FinaleDisabled"
	elseif disabled.ReactorRush ~= nil and type(disabled.ReactorRush) ~= "boolean" then
		return nil, "InvalidDisabledRules"
	end
	local mask, count, disabledCount = 0, 0, 0
	local easy = { SafeColor = true, LowGravity = true, SafeZone = true }
	local hasFirst = false
	for index, id in RULES do
		if disabled[id] ~= nil and type(disabled[id]) ~= "boolean" then
			return nil, "InvalidDisabledRules"
		end
		if disabled[id] == true then
			disabledCount += 1
		else
			mask += bit32.lshift(1, index - 1)
			count += 1
			hasFirst = hasFirst or easy[id] == true
		end
	end
	if count < 5 then
		return nil, "NotEnoughRules"
	elseif not hasFirst then
		return nil, "NoReadableFirst"
	elseif disabledCount == 0 then
		-- Use the same deterministic catalog draw when no rule is disabled.
		return RuleDeck.draw(seed, mode), nil
	end
	local memo: { [string]: boolean } = {}
	local function canFinish(remaining: number, trial: number, last: Category?, streak: number): boolean
		if trial > 5 then
			return true
		end
		local key = tostring(remaining) .. ":" .. trial .. ":" .. (last or "") .. ":" .. streak
		if memo[key] ~= nil then
			return memo[key]
		end
		for index, id in RULES do
			local bit = bit32.lshift(1, index - 1)
			local category = CATEGORIES[id]
			if
				bit32.band(remaining, bit) ~= 0
				and (trial ~= 1 or easy[id] == true)
				and (streak < 2 or category ~= last)
				and canFinish(
					bit32.bxor(remaining, bit),
					trial + 1,
					category,
					if category == last then streak + 1 else 1
				)
			then
				memo[key] = true
				return true
			end
		end
		memo[key] = false
		return false
	end
	if not canFinish(mask, 1, nil, 0) then
		return nil, "NoLegalDeck"
	end
	local random = randomSource(seed)
	local deck: { string } = {}
	local last: Category? = nil
	local streak = 0
	for trial = 1, 5 do
		local weights = {}
		local total = 0
		for index, id in RULES do
			local bit = bit32.lshift(1, index - 1)
			local category = CATEGORIES[id]
			local weight = 0
			if
				bit32.band(mask, bit) ~= 0
				and (trial ~= 1 or easy[id] == true)
				and (streak < 2 or category ~= last)
				and canFinish(
					bit32.bxor(mask, bit),
					trial + 1,
					category,
					if category == last then streak + 1 else 1
				)
			then
				weight = if (mode == "Reflex" and REFLEX[id]) or (mode == "Cosmic" and COSMIC[id])
					then 3
					else 1
			end
			weights[index] = weight
			total += weight
		end
		if total == 0 then
			return nil, "NoLegalDeck"
		end
		local pick = random() * total
		for index, weight in weights do
			pick -= weight
			if pick < 0 then
				local id = RULES[index]
				local category = CATEGORIES[id]
				table.insert(deck, id)
				mask = bit32.bxor(mask, bit32.lshift(1, index - 1))
				streak = if category == last then streak + 1 else 1
				last = category
				break
			end
		end
	end
	table.insert(deck, "ReactorRush")
	return deck, nil
end
return RuleDeck
