--!strict
-- Stored values are explicit choices. Missing fields use local defaults and never
-- mean that a player has disabled the device's accessibility preference.
local PlayerPreferences = {}
PlayerPreferences.Keys = table.freeze({ "EffectsVolume", "MusicVolume", "AudioMuted", "ReducedMotion" })
PlayerPreferences.Defaults = table.freeze({
	EffectsVolume = 1,
	MusicVolume = 0.5,
	AudioMuted = false,
	ReducedMotion = false,
})

local function volumeKey(key: any): boolean
	return key == "EffectsVolume" or key == "MusicVolume"
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function PlayerPreferences.isValid(key: any, value: any): boolean
	if volumeKey(key) then
		return finite(value) and value >= 0 and value <= 1
	end
	return (key == "AudioMuted" or key == "ReducedMotion") and type(value) == "boolean"
end

function PlayerPreferences.normalize(key: any, value: any): (number | boolean)?
	-- Repair finite stored volumes; requests use isValid and reject out-of-range input.
	if volumeKey(key) and finite(value) then
		return math.clamp(value, 0, 1)
	end
	if PlayerPreferences.isValid(key, value) then
		return value
	end
	return nil
end

function PlayerPreferences.effectiveReducedMotion(preference: any, systemPreference: any): boolean
	return systemPreference == true or preference == true
end

return table.freeze(PlayerPreferences)
