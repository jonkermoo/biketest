--!strict
-- Pure rider settings: defaults, allowed ranges, control bindings and saved profiles. The
-- server runs every save through `sanitizeProfiles`, so a client can never store anything
-- outside these rules. No Roblox objects, so it is tested under Lune.
local RiderSettings = {}

RiderSettings.MAX_PROFILES = 5

-- Actions the rider can bind, in the order the settings panel lists them.
RiderSettings.ACTIONS = {
	"upshift",
	"downshift",
	"thresholdBrake",
	"rearBrake",
	"fullBrake",
	"respawn",
	"settings",
}

RiderSettings.ACTION_LABELS = {
	upshift = "Shift up",
	downshift = "Shift down",
	thresholdBrake = "Threshold brake",
	rearBrake = "Rear brake",
	fullBrake = "Full front brake",
	respawn = "Respawn",
	settings = "Settings menu",
}

export type Bindings = { [string]: string }
export type Settings = {
	throttleStep: number,
	brakeStep: number,
	scrollFasterSign: number,
	thresholdBrake: number, -- front brake % while the threshold-brake button is held
	rearBrakeStart: number, -- rear brake pressure the moment the button goes down
	rearBrakeGrowth: number, -- exponential growth rate of rear brake pressure, per second
	autoShift: boolean, -- automatic gearbox
	bindings: Bindings,
}
export type Profiles = {
	active: number,
	slots: { Settings | false },
}

local DEFAULT_BINDINGS: Bindings = {
	upshift = "R",
	downshift = "E",
	thresholdBrake = "MouseButton1",
	rearBrake = "MouseButton2",
	fullBrake = "S",
	respawn = "Backspace",
	settings = "M",
}

local DEFAULTS = {
	throttleStep = 0.05,
	brakeStep = 0.05,
	scrollFasterSign = 1,
	thresholdBrake = 0.7,
	rearBrakeStart = 0.05,
	rearBrakeGrowth = 2.5,
	autoShift = false,
}

-- min, max, snap increment
RiderSettings.RANGES = {
	throttleStep = { 0.01, 0.25, 0.01 },
	brakeStep = { 0.01, 0.25, 0.01 },
	thresholdBrake = { 0.05, 1, 0.05 },
	rearBrakeStart = { 0.01, 0.5, 0.01 },
	rearBrakeGrowth = { 0.5, 8, 0.1 },
}

-- Inputs a control may be bound to. W/A/D are left out because they ride the bike (A/D
-- steer); Escape and Slash belong to Roblox (menu and chat).
local BINDABLE: { [string]: boolean } = { None = true }
for _, name in
	{
		"B",
		"C",
		"E",
		"F",
		"G",
		"H",
		"I",
		"J",
		"K",
		"L",
		"M",
		"N",
		"O",
		"P",
		"Q",
		"R",
		"S",
		"T",
		"U",
		"V",
		"X",
		"Y",
		"Z",
		"Zero",
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"Six",
		"Seven",
		"Eight",
		"Nine",
		"Space",
		"LeftShift",
		"RightShift",
		"LeftControl",
		"RightControl",
		"LeftAlt",
		"RightAlt",
		"Tab",
		"Backspace",
		"Return",
		"CapsLock",
		"Up",
		"Down",
		"Left",
		"Right",
		"F1",
		"F2",
		"F3",
		"F4",
		"F5",
		"F6",
		"F7",
		"F8",
		"F9",
		"F10",
		"F11",
		"F12",
		"MouseButton1",
		"MouseButton2",
		"MouseButton3",
	}
do
	BINDABLE[name] = true
end

function RiderSettings.isBindable(name: any): boolean
	return type(name) == "string" and BINDABLE[name] == true
end

function RiderSettings.defaults(): Settings
	local bindings = table.clone(DEFAULT_BINDINGS)
	local s = table.clone(DEFAULTS) :: any
	s.bindings = bindings
	return s
end

local function snap(value: number, range: { number }): number
	local lo, hi, step = range[1], range[2], range[3]
	local snapped = lo + math.floor((value - lo) / step + 0.5) * step
	-- avoid float noise such as 0.15000000000000002
	snapped = math.floor(snapped * 1e6 + 0.5) / 1e6
	return math.clamp(snapped, lo, hi)
end

-- A valid value for a numeric setting, or nil if `value` is not a real number.
function RiderSettings.clampSetting(name: string, value: any): number?
	local range = RiderSettings.RANGES[name]
	if
		not range
		or type(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge
	then
		return nil
	end
	return snap(value, range)
end

-- Turn anything (a save from a client, old data) into valid settings. Unknown fields are
-- dropped, bad values fall back to defaults, and no two actions share an input.
function RiderSettings.sanitize(raw: any): Settings
	local s = RiderSettings.defaults()
	if type(raw) ~= "table" then
		return s
	end
	for name in RiderSettings.RANGES do
		local v = RiderSettings.clampSetting(name, raw[name])
		if v ~= nil then
			(s :: any)[name] = v
		end
	end
	if raw.scrollFasterSign == -1 or raw.scrollFasterSign == 1 then
		s.scrollFasterSign = raw.scrollFasterSign
	end
	if type(raw.autoShift) == "boolean" then
		s.autoShift = raw.autoShift
	end
	if type(raw.bindings) == "table" then
		local used: { [string]: boolean } = {}
		for _, action in RiderSettings.ACTIONS do
			local wanted = raw.bindings[action]
			local choice = if RiderSettings.isBindable(wanted)
				then wanted
				else DEFAULT_BINDINGS[action]
			if choice ~= "None" and used[choice] then
				choice = "None" -- a duplicate: unbind rather than fire two actions at once
			end
			s.bindings[action] = choice
			if choice ~= "None" then
				used[choice] = true
			end
		end
	end
	return s
end

-- Bind `action` to `input`. If another action already uses that input, the two swap, so a
-- key never does two things.
function RiderSettings.rebind(bindings: Bindings, action: string, input: string): Bindings
	local result = table.clone(bindings)
	if not RiderSettings.isBindable(input) or result[action] == nil then
		return result
	end
	local previous = result[action]
	for other, bound in result do
		if other ~= action and bound == input and input ~= "None" then
			result[other] = previous
		end
	end
	result[action] = input
	return result
end

-- Valid profile data: exactly MAX_PROFILES slots (settings or empty), an active slot that
-- exists, and at least one profile.
function RiderSettings.sanitizeProfiles(raw: any): Profiles
	local slots: { Settings | false } = {}
	local rawSlots = if type(raw) == "table" and type(raw.slots) == "table" then raw.slots else {}
	for i = 1, RiderSettings.MAX_PROFILES do
		local slot = rawSlots[i]
		slots[i] = if type(slot) == "table" then RiderSettings.sanitize(slot) else false
	end
	local active = if type(raw) == "table" then raw.active else nil
	if
		type(active) ~= "number"
		or active ~= active
		or active < 1
		or active > RiderSettings.MAX_PROFILES
	then
		active = 1
	end
	active = math.floor(active)
	if not slots[active] then
		slots[active] = RiderSettings.defaults()
	end
	return { active = active, slots = slots }
end

-- Rear brake pressure (0..1) after holding the rear-brake input for `held` seconds: starts at
-- `start` and grows exponentially at `growth` per second until full. Releasing resets it, so
-- the caller passes nil/negative when the input is up.
function RiderSettings.rearBrakePressure(held: number?, start: number, growth: number): number
	if held == nil or held ~= held or held < 0 then
		return 0
	end
	return math.clamp(start * math.exp(growth * held), 0, 1)
end

-- Seconds from pressing the rear brake until it reaches full pressure.
function RiderSettings.rearBrakeTimeToFull(start: number, growth: number): number
	return math.log(1 / start) / growth
end

return RiderSettings
