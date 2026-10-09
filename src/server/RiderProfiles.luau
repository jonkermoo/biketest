--!strict
-- Stores each rider's settings profiles in a DataStore. Every save from a client is run
-- through RiderSettings.sanitizeProfiles first. Writes are batched (at most one per player
-- every few seconds) to stay inside DataStore limits, and flushed when a player leaves or the
-- server shuts down. If DataStores are unavailable (an unpublished place, or Studio without
-- API access) settings still work for the session and the client is told they are not saved.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RiderSettings = require(ReplicatedStorage.Shared.rules.RiderSettings)

local RiderProfiles = {}

local STORE_NAME = "RiderSettings_v1"
local SAVE_INTERVAL = 6 -- seconds between writes per player

-- `loadFailed`: the saved data could not be read, so this session must never write; saving
-- defaults over it would wipe the rider's real settings.
type Entry = {
	profiles: RiderSettings.Profiles,
	dirty: boolean,
	loaded: boolean,
	loadFailed: boolean,
}

local warned: { [string]: boolean } = {}
local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn(message)
	end
end

local entries: { [Player]: Entry } = {}
local store: DataStore? = nil
local storeError: string? = nil

local ok, result = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
if ok then
	store = result
else
	storeError = tostring(result)
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function storageStatus(): string
	return if store and not storeError then "saved" else "session"
end

local function load(player: Player): Entry
	local entry = entries[player]
	if entry and entry.loaded then
		return entry
	end
	local raw = nil
	local loadFailed = false
	if store then
		local okGet, data = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if okGet then
			raw = data
		else
			loadFailed = true
			storeError = tostring(data)
			warnOnce(
				`[settings] could not load saved settings, not saving this session: {storeError}`
			)
		end
	end
	entry = {
		profiles = RiderSettings.sanitizeProfiles(raw),
		dirty = false,
		loaded = true,
		loadFailed = loadFailed,
	}
	entries[player] = entry
	return entry
end

local function save(player: Player)
	local entry = entries[player]
	if not entry or not entry.dirty or not store or entry.loadFailed then
		return
	end
	entry.dirty = false
	local okSet, err = pcall(function()
		(store :: DataStore):SetAsync(keyFor(player), entry.profiles, { player.UserId })
	end)
	if not okSet then
		entry.dirty = true -- try again next round
		storeError = tostring(err)
		warnOnce(`[settings] could not save settings: {storeError}`)
	else
		storeError = nil
	end
end

function RiderProfiles.start()
	local getRemote = Instance.new("RemoteFunction")
	getRemote.Name = Remotes.GetRiderProfiles
	getRemote.Parent = ReplicatedStorage
	local saveRemote = Instance.new("RemoteFunction")
	saveRemote.Name = Remotes.SaveRiderProfiles
	saveRemote.Parent = ReplicatedStorage

	getRemote.OnServerInvoke = function(player: Player)
		local entry = load(player)
		return { profiles = entry.profiles, storage = storageStatus() }
	end

	saveRemote.OnServerInvoke = function(player: Player, payload: any)
		local entry = load(player)
		entry.profiles = RiderSettings.sanitizeProfiles(payload)
		entry.dirty = true
		return { ok = true, storage = storageStatus() }
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		entries[player] = nil
	end)

	game:BindToClose(function()
		for player in entries do
			save(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for player in entries do
				task.spawn(save, player)
			end
		end
	end)

	if storeError then
		warn(
			`[settings] DataStore unavailable, settings will last for this session only: {storeError}`
		)
	end
end

return RiderProfiles
