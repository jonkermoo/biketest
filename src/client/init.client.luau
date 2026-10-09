--!strict
-- Drives the rider's bike: reads input, turns the look marker into a steering demand, steps
-- the pure riding model, follows the ground with raycasts under each wheel, and places the
-- bike through its align constraints. The client owns the bike's physics, so the position
-- replicates to the server and to other players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bike = require(Shared.config.Bike)
local Geometry = require(Shared.config.BikeGeometry)
local Look = require(Shared.config.Look)
local BikeDynamics = require(Shared.rules.BikeDynamics)
local LookSteer = require(Shared.rules.LookSteer)
local LookView = require(script.LookView)

local player = Players.LocalPlayer
local requestRespawn = ReplicatedStorage:WaitForChild(Remotes.RequestRespawn) :: RemoteEvent

local function key(code: Enum.KeyCode): number
	return if UserInputService:IsKeyDown(code) then 1 else 0
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
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- The bike's position is owned here, not read back from physics each frame.
local position = Vector3.zero
local hold: AlignPosition? = nil
local turn: AlignOrientation? = nil
local lookTarget = { x = 0, z = 0 }

local function groundHeight(at: Vector3, fallback: number): number
	local hit = Workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), groundParams)
	return if hit then hit.Position.Y else fallback
end

local function attach(model: Model)
	bike = model
	local root = model.PrimaryPart :: BasePart
	hold = root:FindFirstChild("Hold") :: AlignPosition?
	turn = root:FindFirstChild("Turn") :: AlignOrientation?
	position = if hold then hold.Position else model:GetPivot().Position
	local _, yaw, _ = (if turn then turn.CFrame else model:GetPivot()):ToEulerAnglesYXZ()
	state = BikeDynamics.newState(yaw)
	local ignore = { model, player.Character :: Model } :: { Instance }
	groundParams.FilterDescendantsInstances = ignore
	LookView.enable(ignore)
end

-- Steering demand: A/D override with assisted keyboard steering; otherwise steer to the
-- world marker, uncapped by the assist.
local function readInput(yaw: CFrame, dt: number): BikeDynamics.Input
	local throttle = key(Enum.KeyCode.W)
	local brake = key(Enum.KeyCode.S)
	local steer = key(Enum.KeyCode.D) - key(Enum.KeyCode.A)
	if steer ~= 0 then
		return { throttle = throttle, brake = brake, steer = steer }
	end

	local look = LookView.updateLook()
	local raw = { x = look.point.X, z = look.point.Z }
	lookTarget = LookSteer.fixate(lookTarget, raw, look.onHazard, Look.fixationStrength, dt)

	local offset = Vector3.new(lookTarget.x - position.X, 0, lookTarget.z - position.Z)
	local lateral = offset:Dot(yaw.RightVector)
	local forward = offset:Dot(yaw.LookVector)
	if forward > 0 and forward < Look.minLookAhead then
		forward = Look.minLookAhead
	end
	return {
		throttle = throttle,
		brake = brake,
		steer = 0,
		curvature = LookSteer.curvatureTo(lateral, forward),
	}
end

RunService.Heartbeat:Connect(function(dt: number)
	local model = findBike()
	if model ~= bike then
		if model then
			attach(model)
		else
			bike = nil
			LookView.disable()
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
	local input = readInput(CFrame.Angles(0, state.heading, 0), dt)
	if input.curvature == nil then
		LookView.updateLook() -- keep the dot and marker moving while steering by keys
	end
	state, events = BikeDynamics.step(state, input, Bike, dt)
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
	local frontY = groundHeight(pos + forward * Geometry.halfWheelbase, pos.Y)
	local rearY = groundHeight(pos - forward * Geometry.halfWheelbase, pos.Y)
	local pitch = math.atan2(frontY - rearY, Geometry.halfWheelbase * 2)
	position = Vector3.new(pos.X, (frontY + rearY) / 2, pos.Z)

	if hold and turn then
		hold.Position = position
		turn.CFrame = yaw * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, -state.lean)
	end
	LookView.updateCamera(position, yaw, pitch, state.lean)

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
	bike:SetAttribute("LookCurvature", input.curvature or 0)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		requestRespawn:FireServer()
	end
end)
