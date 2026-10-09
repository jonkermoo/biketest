--!strict
-- Drives the rider's bike: reads input, steps the pure riding model, follows the ground with
-- raycasts under each wheel, and places the bike. The client owns the bike's physics, so the
-- position it sets replicates to the server and to other players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bike = require(Shared.config.Bike)
local Geometry = require(Shared.config.BikeGeometry)
local BikeDynamics = require(Shared.rules.BikeDynamics)

local player = Players.LocalPlayer
local requestRespawn = ReplicatedStorage:WaitForChild(Remotes.RequestRespawn) :: RemoteEvent

-- Input layer: keys become plain numbers. The mouse look target will be another source here.
local function readInput(): BikeDynamics.Input
	local function key(code: Enum.KeyCode): number
		return if UserInputService:IsKeyDown(code) then 1 else 0
	end
	return {
		throttle = key(Enum.KeyCode.W),
		brake = key(Enum.KeyCode.S),
		steer = key(Enum.KeyCode.D) - key(Enum.KeyCode.A),
	}
end

local function findBike(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat.Name == "BikeSeat" and seat.Parent and seat.Parent:IsA("Model") then
		return seat.Parent
	end
	return nil
end

local bike: Model? = nil
local state: BikeDynamics.State = BikeDynamics.newState(0)
local wheelSpin = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundHeight(at: Vector3, fallback: number): number
	local hit = Workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position.Y else fallback
end

-- The bike's position is owned here, not read back from physics each frame, so stray
-- physics forces cannot accumulate into drift.
local position = Vector3.zero
local hold: AlignPosition? = nil
local turn: AlignOrientation? = nil

local function attach(model: Model)
	bike = model
	local root = model.PrimaryPart :: BasePart
	hold = root:FindFirstChild("Hold") :: AlignPosition?
	turn = root:FindFirstChild("Turn") :: AlignOrientation?
	-- Start from the server's spawn target, which physics cannot have disturbed.
	position = if hold then hold.Position else model:GetPivot().Position
	local _, yaw, _ = (if turn then turn.CFrame else model:GetPivot()):ToEulerAnglesYXZ()
	state = BikeDynamics.newState(yaw)
	rayParams.FilterDescendantsInstances = { model, player.Character :: Model }
end

RunService.Heartbeat:Connect(function(dt: number)
	local model = findBike()
	if model ~= bike then
		if model then
			attach(model)
		else
			bike = nil
		end
	end
	if not bike then
		return
	end
	local root = bike.PrimaryPart
	if not root then
		return
	end

	local events
	state, events = BikeDynamics.step(state, readInput(), Bike, dt)
	if events.lostGrip then
		print(
			string.format(
				"[bike] lost grip at %.0f studs/s, lean %.0f deg",
				state.speed,
				math.deg(state.lean)
			)
		)
	end

	-- Move along the heading, then sit the wheels on the ground.
	local yaw = CFrame.Angles(0, state.heading, 0)
	local forward = yaw.LookVector
	local pos = position + forward * state.speed * dt
	local frontAt = pos + forward * Geometry.halfWheelbase
	local rearAt = pos - forward * Geometry.halfWheelbase
	local frontY = groundHeight(frontAt, pos.Y)
	local rearY = groundHeight(rearAt, pos.Y)
	local pitch = math.atan2(frontY - rearY, Geometry.halfWheelbase * 2)
	position = Vector3.new(pos.X, (frontY + rearY) / 2, pos.Z)

	if hold and turn then
		hold.Position = position
		turn.CFrame = yaw * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, -state.lean)
	end

	-- Wheels roll with speed (visual only).
	wheelSpin -= state.speed / Geometry.wheelRadius * dt
	for _, id in { "front_wheel", "rear_wheel" } do
		local motor = root:FindFirstChild(id .. "_motor") :: Motor6D?
		if motor then
			motor.Transform = CFrame.Angles(wheelSpin, 0, 0)
		end
	end

	-- Debug readout for tests and a future HUD.
	bike:SetAttribute("Speed", state.speed)
	bike:SetAttribute("LeanDeg", math.deg(state.lean))
	bike:SetAttribute("GripUsed", events.gripUsed)
	bike:SetAttribute("Fallen", state.fallen)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		requestRespawn:FireServer()
	end
end)
