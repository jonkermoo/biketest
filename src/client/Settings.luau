--!strict
-- The rider's settings on this client: the active profile's values, the 5 profile slots, and
-- helpers to read bindings. Changes save automatically to the active profile (the server
-- validates and stores them). Starts from defaults until the server answers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RiderSettings = require(ReplicatedStorage.Shared.rules.RiderSettings)

local Settings = {}

local SAVE_DELAY = 1 -- seconds of quiet before sending changes to the server

Settings.current = RiderSettings.defaults()
Settings.profiles = RiderSettings.sanitizeProfiles(nil) :: RiderSettings.Profiles
-- "loading", "saved" (stored on Roblox), "session" (DataStore unavailable), "error"
Settings.storage = "loading"
-- The action waiting for a new key in the settings panel, if any. Riding inputs are ignored
-- while this is set.
Settings.capturing = nil :: string?

local listeners: { () -> () } = {}
local saveToken = 0

local function changed()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

function Settings.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

local function remote(name: string): RemoteFunction?
	return ReplicatedStorage:WaitForChild(name, 10) :: RemoteFunction?
end

-- Ask the server for this rider's saved profiles.
function Settings.load()
	local fn = remote(Remotes.GetRiderProfiles)
	if not fn then
		Settings.storage = "error"
		changed()
		return
	end
	local ok, reply = pcall(function()
		return (fn :: RemoteFunction):InvokeServer()
	end)
	if ok and type(reply) == "table" then
		Settings.profiles = RiderSettings.sanitizeProfiles(reply.profiles)
		Settings.current =
			table.clone(Settings.profiles.slots[Settings.profiles.active] :: RiderSettings.Settings)
		Settings.current.bindings = table.clone(Settings.current.bindings)
		Settings.storage = if reply.storage == "saved" then "saved" else "session"
	else
		Settings.storage = "error"
	end
	changed()
end

local function sendSoon()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token ~= saveToken then
			return -- a newer change will send instead
		end
		local fn = remote(Remotes.SaveRiderProfiles)
		if not fn then
			return
		end
		local ok, reply = pcall(function()
			return (fn :: RemoteFunction):InvokeServer(Settings.profiles)
		end)
		if ok and type(reply) == "table" then
			Settings.storage = if reply.storage == "saved" then "saved" else "session"
		else
			Settings.storage = "error"
		end
		changed()
	end)
end

-- Copy the current values into the active profile and save it.
local function commit()
	local copy = table.clone(Settings.current)
	copy.bindings = table.clone(Settings.current.bindings)
	Settings.profiles.slots[Settings.profiles.active] = copy
	changed()
	sendSoon()
end

-- Set a numeric setting; it is snapped and kept within its range.
function Settings.set(name: string, value: number)
	local v = RiderSettings.clampSetting(name, value)
	if v ~= nil then
		(Settings.current :: any)[name] = v
		commit()
	end
end

-- Nudge a numeric setting by `steps` increments.
function Settings.adjust(name: string, steps: number)
	local range = RiderSettings.RANGES[name]
	Settings.set(name, (Settings.current :: any)[name] + steps * range[3])
end

function Settings.toggleAutoShift()
	Settings.current.autoShift = not Settings.current.autoShift
	commit()
end

function Settings.invertScroll()
	Settings.current.scrollFasterSign = -Settings.current.scrollFasterSign
	commit()
end

function Settings.rebind(action: string, input: string)
	Settings.current.bindings = RiderSettings.rebind(Settings.current.bindings, action, input)
	commit()
end

function Settings.resetToDefaults()
	Settings.current = RiderSettings.defaults()
	commit()
end

-- Switch to a profile slot. An empty slot becomes a new profile copied from the current
-- settings, so "pick an empty slot" is how you save a new profile.
function Settings.selectProfile(slot: number)
	if slot < 1 or slot > RiderSettings.MAX_PROFILES then
		return
	end
	Settings.profiles.active = slot
	local stored = Settings.profiles.slots[slot]
	if stored then
		Settings.current = table.clone(stored)
		Settings.current.bindings = table.clone(stored.bindings)
	end
	commit()
end

-- Delete a profile. You cannot delete the last one; deleting the active one switches to
-- another.
function Settings.deleteProfile(slot: number)
	local count = 0
	for _, s in Settings.profiles.slots do
		if s then
			count += 1
		end
	end
	if count <= 1 or not Settings.profiles.slots[slot] then
		return
	end
	Settings.profiles.slots[slot] = false
	if Settings.profiles.active == slot then
		for i, s in Settings.profiles.slots do
			if s then
				Settings.selectProfile(i)
				return
			end
		end
	end
	changed()
	sendSoon()
end

-- The binding name an input produces ("R", "MouseButton1", ...).
function Settings.inputName(input: InputObject): string?
	local t = input.UserInputType
	if t == Enum.UserInputType.Keyboard then
		return input.KeyCode.Name
	elseif
		t == Enum.UserInputType.MouseButton1
		or t == Enum.UserInputType.MouseButton2
		or t == Enum.UserInputType.MouseButton3
	then
		return t.Name
	end
	return nil
end

-- Does this input trigger the action?
function Settings.matches(action: string, input: InputObject): boolean
	local bound = Settings.current.bindings[action]
	return bound ~= nil and bound ~= "None" and Settings.inputName(input) == bound
end

-- Is the action's input held down right now?
function Settings.isHeld(action: string): boolean
	local bound = Settings.current.bindings[action]
	if bound == nil or bound == "None" then
		return false
	end
	if string.sub(bound, 1, 11) == "MouseButton" then
		return UserInputService:IsMouseButtonPressed((Enum.UserInputType :: any)[bound])
	end
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[bound]
	end)
	return ok and code ~= nil and UserInputService:IsKeyDown(code)
end

-- Readable name for a binding.
function Settings.displayName(bound: string): string
	if bound == "MouseButton1" then
		return "Left click"
	elseif bound == "MouseButton2" then
		return "Right click"
	elseif bound == "MouseButton3" then
		return "Middle click"
	elseif bound == "None" then
		return "—"
	end
	return bound
end

return Settings
