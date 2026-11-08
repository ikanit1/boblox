--!strict
-- Copies only explicit known server flags; unknown attributes never become rule/code names.
local RuleAvailability = {}

function RuleAvailability.snapshot(
	attributes: { [string]: any },
	ruleOrder: { string }
): ({ [string]: boolean }?, string?)
	local disabled: { [string]: boolean } = {}
	for _, id in ruleOrder do
		local value = attributes["Disabled_" .. id]
		if value ~= nil and type(value) ~= "boolean" then
			return nil, "InvalidFlag"
		end
		if value == true then
			disabled[id] = true
		end
	end
	if disabled.ReactorRush then
		return nil, "FinaleDisabled"
	end
	return disabled, nil
end

function RuleAvailability.message(reason: string?): string
	if reason == "FinaleDisabled" then
		return "Реактор временно на обслуживании. Пока можно исследовать лабораторию."
	end
	return "Испытания временно на настройке. Можно исследовать лабораторию; забеги продолжатся после настройки."
end

return RuleAvailability
