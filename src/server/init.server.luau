--!strict
-- Spawns a bike for each rider and handles respawn requests. The rider's client drives the
-- bike (it owns the physics), so the server only builds, seats and resets.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bike = require(Shared.config.Bike)
local Respawn = require(Shared.rules.Respawn)
local BikeFactory = require(script.BikeFactory)
local RiderProfiles = require(script.RiderProfiles)

RiderProfiles.start()

Players.CharacterAutoLoads = false

-- A seated rider's legs reach the road. If their body collides with the world it drags the
-- bike: measured in play, the bike crawled at 1.6 studs/s while the riding model said 120.
-- Riders do not collide with anything; crashes come from the riding model, not body contact.
local RIDER_GROUP = "Rider"
PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, "Default", false)
PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, RIDER_GROUP, false)

local function setRiderGroup(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = RIDER_GROUP
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = RIDER_GROUP
		end
	end)
end

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
	setRiderGroup(character)

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
