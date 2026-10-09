--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bike = require(Shared.config.Bike)
local Crash = require(Shared.rules.Crash)
local Respawn = require(Shared.rules.Respawn)
local BikeFactory = require(script.BikeFactory)

-- We control respawning: a dead rider waits for a validated RequestRespawn.
Players.CharacterAutoLoads = false

type RiderState = {
	health: number,
	lastRespawn: number,
	lastHit: number,
	history: { { t: number, speed: number } },
	pendingCrash: { startedAt: number, worstDrop: number }?,
	bike: Model?,
	connection: RBXScriptConnection?,
}

local states: { [Player]: RiderState } = {}

local requestRespawn = Instance.new("RemoteEvent")
requestRespawn.Name = Remotes.RequestRespawn
requestRespawn.Parent = ReplicatedStorage

local function horizontalSpeed(part: BasePart): number
	local v = part.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function cleanupBike(state: RiderState)
	if state.connection then
		state.connection:Disconnect()
		state.connection = nil
	end
	if state.bike then
		state.bike:Destroy()
		state.bike = nil
	end
end

local function spawnLocation(): CFrame
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	local base = if spawn then spawn.CFrame else CFrame.new(0, 5, 0)
	return base * CFrame.new(0, 4, 0)
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	cleanupBike(state)
	state.health = Bike.maxHealth
	table.clear(state.history)
	state.pendingCrash = nil

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local bike = BikeFactory.build(spawnLocation())
	bike.Parent = Workspace
	state.bike = bike

	local body = bike.PrimaryPart :: BasePart
	local seat = bike:FindFirstChild("BikeSeat") :: Seat

	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	task.wait()
	seat:Sit(humanoid)
	-- The rider's client drives the bike, so give them the physics.
	body:SetNetworkOwner(player)

	state.connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local speed = horizontalSpeed(body)
		local history = state.history
		while history[1] and now - history[1].t > Bike.crashWindow do
			table.remove(history, 1)
		end
		local recent = {}
		for _, sample in history do
			table.insert(recent, sample.speed)
		end
		table.insert(history, { t = now, speed = speed })

		-- A collision unfolds over several frames. Start a short settle period at the
		-- first big drop, track the worst drop, and apply damage once at the end.
		local drop = Crash.impactOverWindow(recent, speed, Bike.crashMinDrop)
		local pending = state.pendingCrash
		if pending then
			pending.worstDrop = math.max(pending.worstDrop, drop)
			if now - pending.startedAt >= Bike.crashSettle then
				state.pendingCrash = nil
				state.lastHit = now
				table.clear(history)
				local damage = Crash.damage(pending.worstDrop, Bike.maxSpeed, Bike.maxHealth)
				state.health = Crash.applyDamage(state.health, damage)
				print(
					`[crash] {player.Name} lost {pending.worstDrop} speed, took {damage}, health {state.health}`
				)
				if Crash.isDead(state.health) then
					humanoid.Health = 0
				end
			end
		elseif drop > 0 and now - state.lastHit >= Bike.crashHitCooldown then
			state.pendingCrash = { startedAt = now, worstDrop = drop }
		end
	end)
end

local function loadRider(player: Player)
	local state = states[player]
	if state then
		state.lastRespawn = os.clock()
	end
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(function(player)
	states[player] = {
		health = Bike.maxHealth,
		lastRespawn = -math.huge,
		lastHit = -math.huge,
		history = {},
		pendingCrash = nil,
		bike = nil,
		connection = nil,
	}
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	loadRider(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state then
		cleanupBike(state)
	end
	states[player] = nil
end)

requestRespawn.OnServerEvent:Connect(function(player: Player, ...: any)
	local state = states[player]
	if not state then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local isDead = humanoid == nil or humanoid.Health <= 0
	local allowed, reason =
		Respawn.check(select("#", ...), isDead, os.clock(), state.lastRespawn, Bike.respawnCooldown)
	if not allowed then
		print(`[respawn] denied for {player.Name}: {reason}`)
		return
	end
	loadRider(player)
end)
