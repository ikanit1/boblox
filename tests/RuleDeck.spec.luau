--!strict
local RuleDeck = require("../src/shared/RuleDeck")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local allowed = {
	SafeColor = true,
	LaserSweep = true,
	LowGravity = true,
	RedLight = true,
	LavaRise = true,
	MeteorRain = true,
	DisappearingTiles = true,
	SafeZone = true,
	Spinner = true,
	PressureWave = true,
	ChangingWalls = true,
	ReactorRush = true,
}
local easy = { SafeColor = true, LowGravity = true, SafeZone = true }
local categories: { [string]: string } = {
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
for id, category in categories do
	expect(RuleDeck.category(id) == category, "Rule exposes its action category: " .. id)
end
expect(RuleDeck.category("ReactorRush") == nil, "Finale is outside ordinary action categories")
expect(RuleDeck.category("Unknown") == nil, "Unknown rules have no action category")
local reflex = { LaserSweep = true, RedLight = true, MeteorRain = true, Spinner = true, ChangingWalls = true }
local cosmic =
	{ SafeColor = true, LowGravity = true, SafeZone = true, DisappearingTiles = true, PressureWave = true }
local totals: { [string]: number } = { Balanced = 0, Reflex = 0, Cosmic = 0 }
local cosmicTotals: { [string]: number } = { Balanced = 0, Reflex = 0, Cosmic = 0 }
local observed: { [string]: boolean } = {}
for _, mode in { "Balanced", "Reflex", "Cosmic" } do
	for seed = 1, 500 do
		local deck = RuleDeck.draw(seed * 7919, mode)
		local repeatDeck = RuleDeck.draw(seed * 7919, mode)
		expect(#deck == 6, "Exactly six trials")
		expect(deck[6] == "ReactorRush", "Co-op finale always last")
		expect(easy[deck[1]] == true, "First trial has a readable spatial objective")
		local seen: { [string]: boolean } = {}
		for index, id in deck do
			expect(allowed[id] == true and not seen[id], "Known, non-repeating rules")
			expect(id == repeatDeck[index], "Seed determinism")
			seen[id] = true
			observed[id] = true
			if reflex[id] then
				totals[mode] += 1
			end
			if cosmic[id] then
				cosmicTotals[mode] += 1
			end
			if index >= 3 and index <= 5 then
				expect(
					categories[id] ~= categories[deck[index - 1]]
						or categories[id] ~= categories[deck[index - 2]],
					"No three ordinary trials share an action category: "
						.. mode
						.. "/"
						.. seed
						.. "/"
						.. index
				)
			end
		end
	end
end
for id in allowed do
	expect(observed[id] == true, "Catalog rule is reachable: " .. id)
end
expect(
	totals.Reflex > totals.Balanced and totals.Balanced > totals.Cosmic,
	"Votes meaningfully change deck weights"
)
expect(
	cosmicTotals.Cosmic > cosmicTotals.Balanced and cosmicTotals.Balanced > cosmicTotals.Reflex,
	"Cosmic votes favor their rules despite the action category limit"
)
expect(RuleDeck.chooseMode({}, 42) == "Balanced", "No-vote fallback is balanced")
expect(RuleDeck.chooseMode({ Balanced = 1, Reflex = 4, Cosmic = 2 }, 42) == "Reflex", "Majority wins")
local tie = RuleDeck.chooseMode({ Reflex = 4, Cosmic = 4 }, 7711)
expect(tie == "Reflex" or tie == "Cosmic", "Tiebreak chooses a tied mode only")
expect(not RuleDeck.isMode("Balanced ") and not RuleDeck.isMode(123), "Malformed remote payloads rejected")
expect(not RuleDeck.isMode({}) and not RuleDeck.isMode(nil), "Non-string remote payloads rejected")
expect(RuleDeck.isMode("Cosmic"), "Known vote accepted")
expect(not pcall(RuleDeck.draw, 1, "Admin"), "Invalid deck modes are rejected")
expect(not pcall(RuleDeck.draw, 0 / 0, "Balanced"), "Invalid seeds rejected")

local ordinary = {}
for id in categories do
	table.insert(ordinary, id)
end
table.sort(ordinary)
-- Independent exhaustive prefix oracle: no weights, bitmask memo or production helpers.
local function hasLegalRoute(disabled: { [string]: boolean }): boolean
	local prefix, used = {}, {}
	local function search(): boolean
		if #prefix == 5 then
			return true
		end
		for _, id in ordinary do
			if
				not disabled[id]
				and not used[id]
				and (#prefix > 0 or easy[id])
				and (
					#prefix < 2
					or categories[id] ~= categories[prefix[#prefix]]
					or categories[id] ~= categories[prefix[#prefix - 1]]
				)
			then
				used[id] = true
				table.insert(prefix, id)
				if search() then
					return true
				end
				table.remove(prefix)
				used[id] = nil
			end
		end
		return false
	end
	return search()
end
for mask = 0, 2 ^ #ordinary - 1 do
	local disabled = {}
	for index, id in ordinary do
		if bit32.band(mask, bit32.lshift(1, index - 1)) ~= 0 then
			disabled[id] = true
		end
	end
	local possible = hasLegalRoute(disabled)
	for _, mode in { "Balanced", "Reflex", "Cosmic" } do
		for _, seed in { 1, 7919, 2147483646 } do
			local deck, reason = RuleDeck.tryDraw(seed, mode, disabled)
			expect(
				(deck ~= nil) == possible,
				"All catalog disable configurations agree with independent route search"
			)
			if deck then
				expect(
					reason == nil and #deck == 6 and deck[6] == "ReactorRush",
					"Restricted deck keeps six trials and required finale"
				)
				expect(easy[deck[1]] == true, "Restricted deck starts with a readable rule")
				local repeated = RuleDeck.tryDraw(seed, mode, disabled)
				local seen = {}
				for index, id in deck do
					expect(
						allowed[id] and not disabled[id] and not seen[id],
						"No disabled, unknown or duplicate trial"
					)
					expect(repeated ~= nil and repeated[index] == id, "Restricted draws are deterministic")
					if index >= 3 and index <= 5 then
						expect(
							categories[id] ~= categories[deck[index - 1]]
								or categories[id] ~= categories[deck[index - 2]],
							"Restricted draws keep the category cap"
						)
					end
					seen[id] = true
				end
				if mask == 0 then
					expect(
						table.concat(deck, ",") == table.concat(RuleDeck.draw(seed, mode), ","),
						"Empty restrictions match the current catalog draw exactly"
					)
				end
			else
				expect(
					reason == "NotEnoughRules" or reason == "NoReadableFirst" or reason == "NoLegalDeck",
					"Invalid configurations return a bounded reason instead of asserting"
				)
			end
		end
	end
end
for _, invalid in { 0 / 0, math.huge, "seed", false } do
	local deck, reason = RuleDeck.tryDraw(invalid, "Balanced", {})
	expect(deck == nil and reason == "InvalidSeed", "tryDraw rejects invalid seeds without throwing")
end
local noFinale, finaleReason = RuleDeck.tryDraw(1, "Balanced", { ReactorRush = true })
expect(
	noFinale == nil and finaleReason == "FinaleDisabled",
	"Disabled finale never becomes a reward shortcut"
)
local badFlag, flagReason = RuleDeck.tryDraw(1, "Balanced", { SafeColor = "false" })
expect(badFlag == nil and flagReason == "InvalidDisabledRules", "A malformed known flag fails closed")
local unknown = RuleDeck.tryDraw(1, "Balanced", { UnknownRule = true })
expect(
	unknown ~= nil and table.concat(unknown, ",") == table.concat(RuleDeck.draw(1, "Balanced"), ","),
	"Unknown flags cannot insert arbitrary rule IDs"
)
print("RuleDeck: " .. checks .. " checks passed")
print(
	string.format(
		"RuleDeck frequencies per 2500 ordinary trials: Reflex rules B/R/C=%d/%d/%d; Cosmic rules B/R/C=%d/%d/%d",
		totals.Balanced,
		totals.Reflex,
		totals.Cosmic,
		cosmicTotals.Balanced,
		cosmicTotals.Reflex,
		cosmicTotals.Cosmic
	)
)
