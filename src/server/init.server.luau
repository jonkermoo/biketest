--!strict
-- Spawns a bike for each rider and handles respawn requests. The rider's client drives the
-- bike (it owns the physics), so the server only builds, seats and resets.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bike = require(Shared.config.Bike)
local Respawn = require(Shared.rules.Respawn)
local BikeFactory = require(script.BikeFactory)

Players.CharacterAutoLoads = false

local bikes: { [Player]: Model } = {}
local lastRespawn: { [Player]: number } = {}

local requestRespawn = Instance.new("RemoteEvent")
requestRespawn.Name = Remotes.RequestRespawn
requestRespawn.Parent = ReplicatedStorage

local function spawnGround(): CFrame
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	local base = if spawn
		then spawn.Position + Vector3.new(0, spawn.Size.Y / 2, 0)
		else Vector3.zero
	return CFrame.new(base + Vector3.new(0, 0, -12))
end

local function removeBike(player: Player)
	local bike = bikes[player]
	if bike then
		bike:Destroy()
		bikes[player] = nil
	end
end

local function onCharacterAdded(player: Player, character: Model)
	removeBike(player)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local bike = BikeFactory.build(spawnGround())
	bike.Parent = Workspace
	bikes[player] = bike

	local seat = bike:FindFirstChild("BikeSeat") :: Seat
	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	task.wait()
	seat:Sit(humanoid)
	local root = bike.PrimaryPart :: BasePart
	root:SetNetworkOwner(player)
end

Players.PlayerAdded:Connect(function(player)
	lastRespawn[player] = -math.huge
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:LoadCharacter()
end)

Players.PlayerRemoving:Connect(function(player)
	removeBike(player)
	lastRespawn[player] = nil
end)

requestRespawn.OnServerEvent:Connect(function(player: Player, ...: any)
	local allowed, reason = Respawn.check(
		select("#", ...),
		os.clock(),
		lastRespawn[player] or -math.huge,
		Bike.respawnCooldown
	)
	if not allowed then
		print(`[respawn] denied for {player.Name}: {reason}`)
		return
	end
	lastRespawn[player] = os.clock()
	player:LoadCharacter()
end)
