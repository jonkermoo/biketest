--!strict
-- Drives the rider's bike: reads input (mouse wheel lever, brakes, gears, look steering),
-- steps the pure riding model, follows the ground with raycasts under each wheel, and places
-- the bike. The client owns the bike's physics, so the position replicates to the server and
-- to other players. Controls come from the rider's settings (rebindable in the panel).
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
local Gearbox = require(Shared.rules.Gearbox)
local LookSteer = require(Shared.rules.LookSteer)
local RiderSettings = require(Shared.rules.RiderSettings)
local Throttle = require(Shared.rules.Throttle)
local LookView = require(script.LookView)
local Settings = require(script.Settings)
local SettingsPanel = require(script.SettingsPanel)
local ThrottleHud = require(script.ThrottleHud)

local player = Players.LocalPlayer
local requestRespawn = ReplicatedStorage:WaitForChild(Remotes.RequestRespawn) :: RemoteEvent

task.spawn(Settings.load)

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
local lookTarget = { x = 0, z = 0 }
-- Where the rider has set the mouse-wheel lever: -1 full front brake, 0 closed, +1 full
-- throttle. It stays where it is left. It is a target: the hand moves there gradually.
local wheelLever = 0
-- Where the rider's right hand actually is, on the same scale. Throttle and front brake both
-- come from it, so they can never be on together.
local hand = 0
-- Gear change asked for since the last frame: +1 up, -1 down.
local pendingShift = 0
-- When the rear brake input went down (nil while released).
local rearHeldSince: number? = nil

local function groundHeight(at: Vector3, fallback: number): number
	local hit = Workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), groundParams)
	return if hit then hit.Position.Y else fallback
end

local function attach(model: Model)
	bike = model
	-- Start from the server's spawn pose, which physics cannot have disturbed.
	local spawnPose = model:GetAttribute("SpawnCFrame")
	local start: CFrame = if typeof(spawnPose) == "CFrame" then spawnPose else model:GetPivot()
	position = start.Position
	local _, yaw, _ = start:ToEulerAnglesYXZ()
	state = BikeDynamics.newState(yaw)
	wheelLever = 0
	hand = 0
	pendingShift = 0
	rearHeldSince = nil
	local ignore = { model, player.Character :: Model } :: { Instance }
	groundParams.FilterDescendantsInstances = ignore
	LookView.enable(ignore)
	ThrottleHud.setVisible(true)
end

-- The right hand: throttle and front brake are one hand. The wheel lever, the threshold
-- brake (held = a set %) and the full-brake key all set where the hand should go; the hand
-- then moves there at realistic speeds, rolling the throttle closed before the brake rises.
-- The rear brake is the right foot: separate, so it can drag while on the throttle. It builds
-- up exponentially while held and lets go the moment it is released.
-- Returns throttle, front brake, rear brake.
local function readHand(dt: number): (number, number, number)
	local s = Settings.current
	local target = wheelLever
	local rear = 0
	if SettingsPanel.isOpen() then
		rearHeldSince = nil -- the mouse buttons are clicking the panel
	else
		local thresholdHeld = Settings.isHeld("thresholdBrake")
		local fullHeld = Settings.isHeld("fullBrake")
		if thresholdHeld or fullHeld then
			-- Grabbing the front brake shuts the throttle for good: after letting go, the
			-- throttle stays closed until the rider scrolls it open again.
			wheelLever = math.min(wheelLever, 0)
			local squeeze = if fullHeld then 1 else s.thresholdBrake
			target = math.min(wheelLever, -squeeze)
		end

		if rearHeldSince and not Settings.isHeld("rearBrake") then
			rearHeldSince = nil -- released (even if the release event was missed)
		end
		local held = if rearHeldSince then os.clock() - rearHeldSince else nil
		rear = RiderSettings.rearBrakePressure(held, s.rearBrakeStart, s.rearBrakeGrowth)
	end
	hand = Throttle.approach(hand, target, dt, Bike)
	local throttle, front = Throttle.split(hand)
	return throttle, front, rear
end

-- Steering demand: A/D override with assisted keyboard steering; otherwise steer to the
-- world marker, uncapped by the assist.
local function readInput(yaw: CFrame, dt: number): BikeDynamics.Input
	local throttle, front, rear = readHand(dt)
	-- Automatic gearbox shifts for the rider; the shift keys are ignored while it is on.
	local shift = if Settings.current.autoShift
		then Gearbox.autoShift(
			state.speed,
			state.gear,
			throttle,
			Bike,
			Bike.autoUpshiftRpm,
			Bike.autoDownshiftRpm
		)
		else pendingShift
	pendingShift = 0
	local steer = key(Enum.KeyCode.D) - key(Enum.KeyCode.A)
	-- While the settings panel is open the mouse is for clicking, so hold straight unless
	-- the rider steers with the keys.
	if steer ~= 0 or SettingsPanel.isOpen() then
		return { throttle = throttle, brake = front, rearBrake = rear, steer = steer, shift = shift }
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
		brake = front,
		rearBrake = rear,
		steer = 0,
		curvature = LookSteer.curvatureTo(lateral, forward),
		shift = shift,
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
			ThrottleHud.setVisible(false)
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
	if state.fallen then
		-- the engine cuts and the rider lets go when the bike goes down
		wheelLever = 0
		hand = 0
		rearHeldSince = nil
	end
	ThrottleHud.update({
		throttle = input.throttle,
		front = input.brake,
		rear = input.rearBrake or 0,
		speed = state.speed,
		gear = state.gear,
		auto = Settings.current.autoShift,
		rpm = events.rpm,
		redline = Bike.redlineRpm,
		rpmScale = 17000,
	})
	if events.lostGrip then
		print(
			string.format(
				"[bike] lost grip at %.0f studs/s, lean %.0f deg",
				state.speed,
				math.deg(state.lean)
			)
		)
	end
	if events.shiftRefused and (input.shift or 0) < 0 then
		print(
			string.format(
				"[bike] downshift refused: would over-rev (%.0f km/h in gear %d)",
				state.speed * 1.008,
				state.gear
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

	-- Place the bike exactly, every frame. Velocity is set too so physics and replication
	-- interpolate smoothly between frames. (Rigid align constraints were tried and did not
	-- hold the bike: it fell 2,000+ studs behind its target. See traps.md.)
	bike:PivotTo(
		CFrame.new(position) * yaw * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, -state.lean)
	)
	root.AssemblyLinearVelocity = forward * state.speed
	root.AssemblyAngularVelocity = Vector3.zero

	-- Wheels roll with speed (visual only).
	wheelSpin -= state.speed / Geometry.wheelRadius * dt
	for _, id in { "front_wheel", "rear_wheel" } do
		local motor = root:FindFirstChild(id .. "_motor") :: Motor6D?
		if motor then
			motor.Transform = CFrame.Angles(wheelSpin, 0, 0)
		end
	end

	-- Debug readout for tests.
	bike:SetAttribute("Speed", state.speed)
	bike:SetAttribute("LeanDeg", math.deg(state.lean))
	bike:SetAttribute("GripUsed", events.gripUsed)
	bike:SetAttribute("Fallen", state.fallen)
	bike:SetAttribute("LookCurvature", input.curvature or 0)
	bike:SetAttribute("Throttle", input.throttle)
	bike:SetAttribute("Brake", input.brake)
	bike:SetAttribute("RearBrake", input.rearBrake or 0)
	bike:SetAttribute("Gear", state.gear)
	bike:SetAttribute("Rpm", events.rpm)
end)

-- Camera every rendered frame, from the bike as drawn (after physics), so the head stays
-- fixed on the bike at any speed.
RunService:BindToRenderStep("BikeCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local root = bike and bike.PrimaryPart
	if root then
		LookView.updateCamera(root.CFrame, state.lean)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or Settings.capturing then
		return -- typing in chat, clicking UI, or choosing a new binding
	end
	if Settings.matches("settings", input) then
		SettingsPanel.toggle()
		return
	end
	if SettingsPanel.isOpen() or not bike then
		return
	end
	if Settings.matches("upshift", input) then
		pendingShift = 1
	elseif Settings.matches("downshift", input) then
		pendingShift = -1
	elseif Settings.matches("respawn", input) then
		requestRespawn:FireServer()
	elseif Settings.matches("rearBrake", input) then
		rearHeldSince = os.clock()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if Settings.matches("rearBrake", input) then
		rearHeldSince = nil -- the rear brake lets go instantly
	end
end)

-- The wheel sets the lever target: toward "faster" releases the brake then opens the
-- throttle; toward "slower" closes the throttle then brakes. The hand follows gradually.
-- Direction and step sizes come from the rider's settings.
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	if bike and not state.fallen then
		local s = Settings.current
		wheelLever = Throttle.fromScroll(
			wheelLever,
			input.Position.Z * s.scrollFasterSign,
			s.throttleStep,
			s.brakeStep
		)
	end
end)
