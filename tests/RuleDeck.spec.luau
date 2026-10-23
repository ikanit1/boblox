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
