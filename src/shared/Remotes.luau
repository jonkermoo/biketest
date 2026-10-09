--!strict
-- Single source of truth for every client/server message name.
return table.freeze({
	RequestRespawn = "RequestRespawn", -- RemoteEvent, no payload
	GetRiderProfiles = "GetRiderProfiles", -- RemoteFunction: () -> { profiles, storage }
	SaveRiderProfiles = "SaveRiderProfiles", -- RemoteFunction: (profiles) -> { ok, storage }
})
