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

-- Change a step by `increments` notches of the settings increment, kept within range.
function Settings.adjust(name: "throttleStep" | "brakeStep", increments: number)
	local current = Settings[name] :: number
	local value = round(current + increments * Controls.stepIncrement)
	Settings[name] = math.clamp(value, Controls.stepMin, Controls.stepMax)
end

function Settings.invertScroll()
	Settings.scrollFasterSign = -Settings.scrollFasterSign
end

return Settings
