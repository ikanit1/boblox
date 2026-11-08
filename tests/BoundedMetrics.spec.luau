--!strict
local Metrics = require("../src/shared/BoundedMetrics")
local checks = 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local sample = Metrics.new(100)
local empty = Metrics.summary(sample)
expect(empty.P50 == nil and empty.LifetimeMean == nil and empty.Count == 0, "No invented empty measurements")
for index = 1, 100 do
	Metrics.add(sample, index)
end
local full = Metrics.summary(sample)
expect(full.P50 == 50 and full.P95 == 95 and full.P99 == 99, "Exact nearest-rank quantiles")
expect(full.LifetimeMean == 50.5 and full.LifetimeMin == 1 and full.LifetimeMax == 100, "Lifetime aggregates")
Metrics.add(sample, 1000)
local rolled = Metrics.summary(sample)
expect(rolled.Count == 101 and rolled.WindowCount == 100 and rolled.Overwritten == 1, "Ring overflow counted")
expect(rolled.P50 == 51 and rolled.P95 == 96 and rolled.P99 == 100, "Quantiles use latest window only")
expect(rolled.LifetimeMin == 1 and rolled.LifetimeMax == 1000, "Lifetime extrema survive overwrite")
expect(sample.Values[1] == 1000 and sample.Values[2] == 2, "Summary does not mutate the ring")
for _, bad in { 0 / 0, math.huge, -math.huge, -1, "16", true, {} } do
	expect(not Metrics.add(sample, bad), "Reject malformed measurement")
end
expect(sample.Count == 101 and sample.Rejected == 7, "Invalid values cannot poison samples")
expect(Metrics.add(sample, 0), "Zero remains a valid observation")
for _, bad in { 0, -1, 1.5, math.huge, 0 / 0, 12001 } do
	expect(not pcall(Metrics.new, bad), "Capacity cannot grow without a bound")
end
local singleton = Metrics.new(1)
Metrics.add(singleton, 4)
Metrics.add(singleton, 8)
local one = Metrics.summary(singleton)
expect(one.P50 == 8 and one.P95 == 8 and one.P99 == 8 and one.LifetimeMean == 6, "Singleton rollover")
local soak = Metrics.new(6000)
for index = 1, 180000 do
	Metrics.add(soak, if index % 100 == 0 then 80 else 16)
end
local soaked = Metrics.summary(soak)
expect(#soak.Values == 6000 and soaked.Overwritten == 174000, "Synthetic soak retains bounded storage")
expect(soaked.P50 == 16 and soaked.P95 == 16 and soaked.P99 == 16, "Nearest-rank boundary at 99 percent")
expect(soaked.LifetimeMax == 80 and math.abs(soaked.LifetimeMean - 16.64) < 0.000001, "Long-run mean stable")
print("BoundedMetrics: " .. checks .. " checks passed (synthetic input, not device performance)")
