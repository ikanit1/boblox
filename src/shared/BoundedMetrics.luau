--!strict
-- Exact nearest-rank percentiles for a bounded rolling window; lifetime totals are separate.
local BoundedMetrics = {}

export type Sample = {
	Capacity: number,
	Count: number,
	Rejected: number,
	Next: number,
	Values: { number },
	Mean: number,
	Minimum: number?,
	Maximum: number?,
}

function BoundedMetrics.new(capacity: number): Sample
	assert(
		capacity == capacity and capacity >= 1 and capacity <= 12000 and capacity % 1 == 0,
		"Metrics capacity must be an integer from 1 to 12000"
	)
	return { Capacity = capacity, Count = 0, Rejected = 0, Next = 1, Values = {}, Mean = 0 }
end

function BoundedMetrics.add(sample: Sample, value: any): boolean
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		sample.Rejected += 1
		return false
	end
	sample.Count += 1
	-- Incremental mean avoids an unbounded sum during long captures.
	sample.Mean += (value - sample.Mean) / sample.Count
	sample.Minimum = if sample.Minimum == nil then value else math.min(sample.Minimum, value)
	sample.Maximum = if sample.Maximum == nil then value else math.max(sample.Maximum, value)
	sample.Values[sample.Next] = value
	sample.Next = sample.Next % sample.Capacity + 1
	return true
end

function BoundedMetrics.summary(sample: Sample): { [string]: any }
	local sorted = table.clone(sample.Values)
	table.sort(sorted)
	local size = #sorted
	local function percentile(fraction: number): number?
		return if size == 0 then nil else sorted[math.max(1, math.ceil(size * fraction))]
	end
	return {
		Count = sample.Count,
		Rejected = sample.Rejected,
		WindowCount = size,
		WindowCapacity = sample.Capacity,
		Overwritten = math.max(0, sample.Count - size),
		PercentileScope = "latest_window_nearest_rank",
		P50 = percentile(0.5),
		P95 = percentile(0.95),
		P99 = percentile(0.99),
		LifetimeMean = if sample.Count > 0 then sample.Mean else nil,
		LifetimeMin = sample.Minimum,
		LifetimeMax = sample.Maximum,
	}
end

return BoundedMetrics
