--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Deck = require("../src/shared/RuleDeck")
local Hints = require("../src/shared/PlayerHints")
local Guides = require("../src/shared/RuleGuides")
local config =
	luau.load(fs.readFile("src/shared/GameConfig.luau"), { environment = { Color3 = roblox.Color3 } })()
local economy =
	luau.load(fs.readFile("src/shared/EconomyConfig.luau"), { environment = { Color3 = roblox.Color3 } })()
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
expect(#config.RuleOrder == 12 and config.RuleCount == 6, "Expanded catalog keeps the six-stage game loop")
local seen = {}
for _, id in config.RuleOrder do
	expect(not seen[id], "Catalog has no duplicate rule")
	seen[id] = true
	expect(config.Rules[id] ~= nil and #config.Rules[id].Name > 0, "Every rule has display metadata")
	expect(Guides[id] ~= nil and #Guides[id] > 20, "Every rule has an archive explanation")
	expect(
		Hints.Defeat[id] ~= nil and Hints.CompactDefeat[id] ~= nil,
		"Every rule has defeat coaching on both layouts"
	)
	expect(
		id == "ReactorRush" or Deck.category(id) ~= nil,
		"Every ordinary rule participates in varied decks"
	)
end
local values: { [string]: any } =
	{ DataStatus = "Saved", DataPersistent = true, UnlockedTitle_Practice = true }
local function read(name)
	return values[name]
end
local goal = Hints.nextGoal(read, economy, config.RuleCount)
expect(
	string.find(goal, "Полярное сияние", 1, true) ~= nil,
	"Results surfaces a newly unlocked free cosmetic before distant mastery"
)
values.Owned_Aurora = true
expect(
	not string.find(Hints.nextGoal(read, economy, config.RuleCount), "Полярное сияние", 1, true),
	"Claimed cosmetic no longer occupies the next goal"
)
values.DataStatus, values.DataPersistent = "Session", false
values.Owned_Aurora = false
expect(
	string.find(Hints.nextGoal(read, economy, config.RuleCount), "ЭТОЙ СЕССИИ", 1, true) ~= nil,
	"Temporary cosmetic goals remain explicit"
)
print("Catalog integration: " .. checks .. " checks passed")
