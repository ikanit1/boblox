--!strict
-- Actual catalog and display policy; no claim about native rendering or measured player income.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local Economy = luau.load(fs.readFile("src/shared/EconomyConfig.luau"), {
	environment = { Color3 = Roblox.Color3 },
})()
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local attrs = {}
local function read(name: string)
	return attrs[name]
end
local catalog, milestones = {}, {}
for _, milestone in Economy.MasteryMilestones do
	milestones[milestone.Id] = true
end
for _, item in Economy.Trails do
	expect(catalog[item.Id] == nil, "Every cosmetic has a stable unique id")
	catalog[item.Id] = item
	expect(item.Price >= 0 and item.Price % 1 == 0, "Prices are finite earned coin amounts")
	if item.UnlockTitle then
		expect(
			item.Price == 0 and milestones[item.UnlockTitle],
			"Mastery styles are free existing-goal rewards"
		)
		expect(item.ColorEnd ~= item.Color, "A mastery style has an actual two-color gradient")
		expect(item.WidthScale > 0 and item.WidthScale <= 1, "Ribbon width has a bounded presentation budget")
		expect(
			item.Lifetime >= 0.2 and item.Lifetime <= 0.5,
			"Ribbon lifetime has a bounded presentation budget"
		)
	end
end
expect(#Economy.Trails == 9, "Eight earnable styles plus the default is the complete small catalog")
for id, price in { None = 0, Cyan = 60, Pink = 100, Gold = 180, Emerald = 260 } do
	expect(
		catalog[id].Price == price and catalog[id].UnlockTitle == nil,
		"Existing items retain their ids and prices"
	)
end
expect(
	Economy.Rewards.SurvivalCoins * 6 + Economy.Rewards.RunCoins + Economy.Rewards.WinCoins == 107,
	"Catalog extension does not alter the existing successful-run coin formula"
)
expect(
	catalog.Cyan.Price <= Economy.Rewards.SurvivalCoins * 4 + Economy.Rewards.RunCoins,
	"First paid cosmetic remains affordable after a four-stage run before pickups or quests"
)
expect(Economy.trailState(catalog.None, read).Kind == "Owned", "Default cosmetic requires no claim")
attrs.EquippedTrail = "None"
expect(Economy.trailState(catalog.None, read).Kind == "Equipped", "Equipped state is authoritative")
expect(Economy.trailState(catalog.Aurora, read).Kind == "Locked", "Coins do not replace mastery proof")
attrs.Coins = 1_000_000
attrs.UnlockedTitle_Practice = "true"
attrs.Mastery_Practice = 1
expect(
	Economy.trailState(catalog.Aurora, read).Action == nil,
	"Only the strict server unlock flag permits a claim"
)
attrs.UnlockedTitle_Practice = true
local reward = Economy.trailState(catalog.Aurora, read)
expect(
	reward.Kind == "Available" and reward.Action == "Purchase",
	"Unlocked free reward uses the existing authoritative request"
)
expect(
	string.find(Economy.nextTrailGoal(read), "Полярное сияние", 1, true) ~= nil,
	"A ready reward takes precedence over spending"
)
attrs.Owned_Aurora = true
expect(
	Economy.trailState(catalog.Aurora, read).Kind == "Owned",
	"Owned mastery reward offers equip instead of a repeated claim"
)
attrs.EquippedTrail = "Aurora"
expect(
	Economy.trailState(catalog.Aurora, read).Action == nil,
	"Already equipped reward offers no duplicate request"
)
expect(
	string.find(Economy.nextTrailGoal(read), "Ионный след", 1, true) ~= nil,
	"An affordable old cosmetic remains an attainable next goal"
)
for _, bad in { -5, math.huge, 0 / 0, "999" } do
	attrs.Coins = bad
	local state = Economy.trailState(catalog.Cyan, read)
	expect(
		state.Kind == "Unaffordable" and state.Remaining == 60,
		"Invalid balances never fabricate affordability"
	)
end
attrs.Coins = 59
expect(Economy.trailState(catalog.Cyan, read).Remaining == 1, "Coin deficit is exact")
attrs.Coins = 60
expect(Economy.trailState(catalog.Cyan, read).Kind == "Affordable", "Exact price is affordable")
for _, id in { "Cyan", "Pink", "Gold", "Emerald" } do
	attrs["Owned_" .. id] = true
end
expect(
	string.find(Economy.nextTrailGoal(read), "Спектральная лента", 1, true) ~= nil,
	"After coin items the next goal is an unowned mastery style"
)
for _, item in Economy.Trails do
	attrs["Owned_" .. item.Id] = true
end
expect(Economy.nextTrailGoal(read) == nil, "A complete collection does not invent an unearned target")
print(string.format("EconomyConfig: %d checks passed (catalog and display policy)", checks))
