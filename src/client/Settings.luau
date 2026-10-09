--!strict
-- Rider settings for this session, starting from config/Controls. The settings panel changes
-- them; the controller reads them. Not saved between sessions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controls = require(ReplicatedStorage.Shared.config.Controls)

local Settings = {
	throttleStep = Controls.throttleStep,
	brakeStep = Controls.brakeStep,
	scrollFasterSign = Controls.scrollFasterSign,
}

local function round(value: number): number
	return math.floor(value / Controls.stepIncrement + 0.5) * Controls.stepIncrement
end

-- Set a step, snapped to the settings increment and kept within range.
function Settings.set(name: "throttleStep" | "brakeStep", value: number)
	if value ~= value then
		return
	end
	Settings[name] = math.clamp(round(value), Controls.stepMin, Controls.stepMax)
end

-- Change a step by `increments` notches of the settings increment, kept within range.
function Settings.adjust(name: "throttleStep" | "brakeStep", increments: number)
	Settings.set(name, (Settings[name] :: number) + increments * Controls.stepIncrement)
end

function Settings.invertScroll()
	Settings.scrollFasterSign = -Settings.scrollFasterSign
end

return Settings
