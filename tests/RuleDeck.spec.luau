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
	ReactorRush = true,
}
local easy = { SafeColor = true, LowGravity = true, SafeZone = true }
local reflex = { LaserSweep = true, RedLight = true, MeteorRain = true, Spinner = true }
local totals: { [string]: number } = { Balanced = 0, Reflex = 0, Cosmic = 0 }
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

local function expectSame(actual: { string }, expected: { string }, message: string)
	expect(#actual == #expected, message)
	for index, id in actual do
		expect(id == expected[index], message)
	end
end

local function expectNext(previous: { string }, deck: { string })
	expect(#deck == 6 and deck[6] == "ReactorRush", "Memory keeps six trials and the fixed finale")
	expect(easy[deck[1]] == true and deck[1] ~= previous[1], "A different safe opener starts each run")
	local seen: { [string]: boolean } = {}
	local fresh = 0
	for index = 1, 5 do
		local id = deck[index]
		expect(allowed[id] == true and id ~= "ReactorRush" and not seen[id], "Ordinary trials stay unique")
		seen[id] = true
		if not table.find(previous, id) then
			fresh += 1
		end
	end
	expect(fresh == 4, "Every next run contains all four unseen ordinary rules and one repeat")
	for _, id in previous do
		seen[id] = true
	end
	seen.ReactorRush = true
	for id in allowed do
		expect(seen[id] == true, "Two consecutive complete decks cover the entire catalog: " .. id)
	end
end

-- Exercise changing vote outcomes across multiple runs, not only one history input.
local modes = { "Balanced", "Reflex", "Cosmic" }
for _, startMode in modes do
	for seed = 1, 250 do
		local previous = table.freeze(RuleDeck.draw(seed * 7919, startMode))
		for run = 2, 7 do
			local mode = modes[(seed + run) % #modes + 1]
			local nextSeed = seed * 7919 + run * 104729
			local deck = RuleDeck.draw(nextSeed, mode, previous)
			expectNext(previous, deck)
			expectSame(deck, RuleDeck.draw(nextSeed, mode, previous), "History preserves seed determinism")
			previous = table.freeze(deck)
		end
	end
end

-- Exhaust every possible five-rule set and every opener in that set. Even a
-- caller-supplied history with a non-safe first rule must have a valid successor.
local ordinary = {
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
local combinations = 0
local function visitCombination(chosen: { string }, nextIndex: number)
	if #chosen == 5 then
		combinations += 1
		for _, first in chosen do
			local previous = { first }
			for _, id in chosen do
				if id ~= first then
					table.insert(previous, id)
				end
			end
			table.insert(previous, "ReactorRush")
			table.freeze(previous)
			for _, mode in modes do
				for _, seed in { 0, -17, 917911, 2147483646 } do
					expectNext(previous, RuleDeck.draw(seed, mode, previous))
				end
			end
		end
		return
	end
	for index = nextIndex, #ordinary do
		table.insert(chosen, ordinary[index])
		visitCombination(chosen, index + 1)
		table.remove(chosen)
	end
end
visitCombination({}, 1)
expect(combinations == 126, "All nine-choose-five history sets were exercised")

local allOpenersSeen = { "SafeColor", "LowGravity", "SafeZone", "LaserSweep", "RedLight", "ReactorRush" }
for _, mode in modes do
	for seed = 1, 50 do
		local deck = RuleDeck.draw(seed * 7919, mode, allOpenersSeen)
		expectNext(allOpenersSeen, deck)
		expect(deck[1] == "LowGravity" or deck[1] == "SafeZone", "An old safe opener uses the only repeat")
	end
end

-- The selected repeat still reflects the voted mode among eligible candidates.
local weightedHistory = { "SafeColor", "LaserSweep", "LowGravity", "LavaRise", "Spinner", "ReactorRush" }
local repeatTotals = { Balanced = 0, Reflex = 0, Cosmic = 0 }
for _, mode in modes do
	for seed = 1, 1000 do
		local deck = RuleDeck.draw(seed * 7919, mode, weightedHistory)
		for index = 1, 5 do
			local id = deck[index]
			if reflex[id] and table.find(weightedHistory, id) then
				repeatTotals[mode] += 1
			end
		end
	end
end
expect(
	repeatTotals.Reflex > repeatTotals.Balanced and repeatTotals.Balanced > repeatTotals.Cosmic,
	"Mode weights remain meaningful among eligible history repeats"
)

local malformed: { any } = {
	false,
	123,
	"SafeColor",
	{},
	{ "SafeColor", "LaserSweep", "LowGravity", "RedLight" },
	{ "SafeColor", "LaserSweep", "LowGravity", "RedLight", "Unknown" },
	{ "SafeColor", "LaserSweep", "LowGravity", "RedLight", "SafeColor" },
	{ "SafeColor", "LaserSweep", "LowGravity", "RedLight", "LavaRise", "Unknown" },
	{ "SafeColor", "LaserSweep", "LowGravity", "RedLight", "LavaRise", "ReactorRush", "Spinner" },
	{ "SafeColor", "LaserSweep", "LowGravity", "RedLight", false },
	{ [1] = "SafeColor", [2] = "LaserSweep", [3] = "LowGravity", [4] = "RedLight", [6] = "ReactorRush" },
	{
		[1] = "SafeColor",
		[2] = "LaserSweep",
		[3] = "LowGravity",
		[4] = "RedLight",
		[5] = "LavaRise",
		extra = "Spinner",
	},
	{
		[1] = "SafeColor",
		[2] = "LaserSweep",
		[3] = "LowGravity",
		[4] = "RedLight",
		[5] = "LavaRise",
		[0.5] = "Spinner",
	},
}
for _, mode in modes do
	local baseline = RuleDeck.draw(7919, mode)
	expectSame(RuleDeck.draw(7919, mode, nil), baseline, "Optional history keeps the two-argument API")
	for _, badHistory in malformed do
		expectSame(RuleDeck.draw(7919, mode, badHistory), baseline, "Malformed history falls back safely")
	end
	local fiveRules = table.clone(weightedHistory)
	table.remove(fiveRules)
	expectSame(
		RuleDeck.draw(7919, mode, fiveRules),
		RuleDeck.draw(7919, mode, weightedHistory),
		"History accepts five ordinary rules with or without the fixed finale"
	)
end

expect(RuleDeck.chooseMode({}, 42) == "Balanced", "No-vote fallback is balanced")
expect(RuleDeck.chooseMode({ Balanced = 1, Reflex = 4, Cosmic = 2 }, 42) == "Reflex", "Majority wins")
local tie = RuleDeck.chooseMode({ Reflex = 4, Cosmic = 4 }, 7711)
expect(tie == "Reflex" or tie == "Cosmic", "Tiebreak chooses a tied mode only")
expect(not RuleDeck.isMode("Balanced ") and not RuleDeck.isMode(123), "Malformed remote payloads rejected")
expect(not RuleDeck.isMode({}) and not RuleDeck.isMode(nil), "Non-string remote payloads rejected")
expect(RuleDeck.isMode("Cosmic"), "Known vote accepted")
expect(not pcall(RuleDeck.draw, 1, "Admin"), "Invalid deck modes are rejected")
expect(not pcall(RuleDeck.draw, 0 / 0, "Balanced"), "Invalid seeds rejected")
print("RuleDeck: " .. checks .. " checks passed")
