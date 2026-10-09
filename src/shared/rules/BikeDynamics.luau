--!strict
-- Pure riding model: speed, gears, brakes, steering, lean, grip and falling. No Roblox
-- objects, so it runs under Lune in tests. The Roblox side only reads the new state and moves
-- the model.
-- In Roblox, modules are required by instance; under Lune (tests) by path.
local Gearbox = if typeof(script) == "Instance"
	then require(script.Parent.Gearbox)
	else require("./Gearbox")

local BikeDynamics = {}

export type Params = Gearbox.Params & {
	maxSpeed: number,
	rollingResistance: number,
	aeroDrag: number,
	shiftCutTime: number, -- no drive for this long after an upshift
	frontBrakeDecel: number, -- full front lever
	rearBrakeDecel: number, -- full rear pedal
	maxBrakeDecel: number, -- both together cannot exceed this (rear wheel lifts)
	maxCurvature: number,
	curvatureSpeedRef: number,
	leanRate: number,
	gravity: number,
	tyreGrip: number,
	steerAssist: number,
	lookGripLimit: number,
	slideDecel: number,
	lyingLean: number,
}

export type State = {
	speed: number, -- studs/s along the heading
	heading: number, -- radians, yaw
	lean: number, -- radians, positive = leaning right
	fallen: boolean,
	gear: number, -- 1..top
	shiftCut: number, -- seconds of upshift power cut left
}

export type Input = {
	throttle: number, -- 0..1
	brake: number, -- 0..1, front brake
	rearBrake: number?, -- 0..1
	steer: number, -- -1..1, positive = right. Keyboard steering, capped by the assist.
	-- Curvature asked for by the look target (1/studs, positive = right). When present it
	-- replaces `steer` and is NOT capped by the assist, so looking too sharply can ask for
	-- more grip than the tyres have.
	curvature: number?,
	shift: number?, -- +1 upshift, -1 downshift, this frame only
}

export type Events = {
	lostGrip: boolean,
	gripUsed: number, -- 0..1+, how much of the tyre grip budget is in use
	lateralG: number,
	rpm: number,
	shifted: boolean,
	shiftRefused: boolean,
}

function BikeDynamics.newState(heading: number): State
	return { speed = 0, heading = heading, lean = 0, fallen = false, gear = 1, shiftCut = 0 }
end

-- Clamp to [lo, hi]; NaN and non-numbers become 0.
function BikeDynamics.sanitize(value: any, lo: number, hi: number): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(value, lo, hi)
end

-- Tightest turn a look target may ask for: the steering lock, and `lookGripLimit` times the
-- tyre grip. A limit above 1 means a sharp enough look really can exceed the grip and drop
-- the bike; the cap only stops absurd demands (looking straight sideways at speed).
function BikeDynamics.lookCurvatureCap(speed: number, params: Params): number
	local byGrip = params.lookGripLimit
		* params.tyreGrip
		* params.gravity
		/ math.max(speed * speed, 1)
	return math.min(params.maxCurvature, byGrip)
end

-- Tightest turn a keyboard press can make at this speed, in 1/studs. Narrower at speed, and
-- capped so that a full-lock key press stays inside `steerAssist` of the tyre grip budget.
-- This is what makes keyboard steering safe.
function BikeDynamics.maxCurvatureAt(speed: number, params: Params): number
	local ratio = speed / params.curvatureSpeedRef
	local byGeometry = params.maxCurvature / (1 + ratio * ratio)
	local byGrip = params.steerAssist
		* params.tyreGrip
		* params.gravity
		/ math.max(speed * speed, 1)
	return math.min(byGeometry, byGrip)
end

-- Lean angle needed to hold a given lateral acceleration (steady cornering).
function BikeDynamics.leanForLateralAccel(lateralAccel: number, gravity: number): number
	return math.atan(lateralAccel / gravity)
end

-- Share of the grip budget in use, combining cornering and braking (friction circle).
function BikeDynamics.gripUsed(lateralG: number, longitudinalG: number, tyreGrip: number): number
	return math.sqrt(lateralG * lateralG + longitudinalG * longitudinalG) / tyreGrip
end

-- Forward push from the engine in the current gear (see Gearbox).
function BikeDynamics.driveAccel(
	speed: number,
	throttle: number,
	gear: number,
	params: Params
): number
	return Gearbox.driveAccel(speed, throttle, gear, params)
end

-- Everything slowing the bike apart from the brakes: rolling resistance, air drag (grows
-- with speed squared) and engine braking, which depends on gear and throttle.
function BikeDynamics.resistance(
	speed: number,
	throttle: number,
	gear: number,
	params: Params
): number
	if speed <= 0 then
		return 0
	end
	return params.rollingResistance
		+ params.aeroDrag * speed * speed
		+ Gearbox.engineBraking(speed, throttle, gear, params)
end

-- Deceleration from the brakes. Front and rear add up, but together they cannot exceed the
-- point where the rear wheel lifts (`maxBrakeDecel`), so adding rear brake to a full front
-- brake only helps a little, as on a real sportbike.
function BikeDynamics.brakeDecel(front: number, rear: number, params: Params): number
	return math.min(
		front * params.frontBrakeDecel + rear * params.rearBrakeDecel,
		params.maxBrakeDecel
	)
end

local function stepFallen(state: State, dt: number, params: Params): State
	local side = if state.lean >= 0 then 1 else -1
	local lean = state.lean + (side * params.lyingLean - state.lean) * (1 - math.exp(-6 * dt))
	return {
		speed = math.max(state.speed - params.slideDecel * dt, 0),
		heading = state.heading,
		lean = lean,
		fallen = true,
		gear = state.gear,
		shiftCut = 0,
	}
end

-- Advance the bike by one frame. Returns the new state and what happened this frame.
function BikeDynamics.step(state: State, input: Input, params: Params, dt: number): (State, Events)
	if state.fallen then
		local rpm = Gearbox.rpm(state.speed, state.gear, params)
		return stepFallen(state, dt, params),
			{
				lostGrip = false,
				gripUsed = 0,
				lateralG = 0,
				rpm = rpm,
				shifted = false,
				shiftRefused = false,
			}
	end

	local throttle = BikeDynamics.sanitize(input.throttle, 0, 1)
	local brake = BikeDynamics.sanitize(input.brake, 0, 1)
	local rearBrake = BikeDynamics.sanitize(input.rearBrake, 0, 1)
	local steer = BikeDynamics.sanitize(input.steer, -1, 1)

	-- Gears
	local gear = math.clamp(math.floor(state.gear), 1, #params.gearRatios)
	local shiftCut = math.max(state.shiftCut - dt, 0)
	local shifted, shiftRefused = false, false
	local shiftInput = BikeDynamics.sanitize(input.shift, -1, 1)
	if shiftInput ~= 0 then
		gear, shifted = Gearbox.shift(gear, shiftInput, state.speed, params)
		shiftRefused = not shifted
		if shifted and shiftInput > 0 then
			shiftCut = params.shiftCutTime
		end
	end

	-- Speed
	local drive = if shiftCut > 0
		then 0
		else BikeDynamics.driveAccel(state.speed, throttle, gear, params)
	local braking = BikeDynamics.brakeDecel(brake, rearBrake, params)
	local change = drive - BikeDynamics.resistance(state.speed, throttle, gear, params) - braking
	local speed = math.clamp(state.speed + change * dt, 0, params.maxSpeed)

	-- The rider asks for a turn; the bike leans to hold that lateral acceleration.
	local demandedCurvature
	if input.curvature ~= nil then
		local cap = BikeDynamics.lookCurvatureCap(speed, params)
		demandedCurvature = BikeDynamics.sanitize(input.curvature, -cap, cap)
	else
		demandedCurvature = steer * BikeDynamics.maxCurvatureAt(speed, params)
	end
	local demandedAccel = speed * speed * demandedCurvature
	local targetLean = BikeDynamics.leanForLateralAccel(demandedAccel, params.gravity)
	local lean = state.lean + (targetLean - state.lean) * (1 - math.exp(-params.leanRate * dt))

	-- The turn the bike really makes comes from its lean angle.
	local lateralAccel = params.gravity * math.tan(lean)
	local curvature = lateralAccel / math.max(speed * speed, 1)
	curvature = math.clamp(curvature, -params.maxCurvature, params.maxCurvature)
	local heading = state.heading - speed * curvature * dt -- positive curvature turns right

	-- Grip: cornering plus braking share one budget.
	local lateralG = math.abs(lateralAccel) / params.gravity
	local longitudinalG = braking / params.gravity
	local used = BikeDynamics.gripUsed(lateralG, longitudinalG, params.tyreGrip)
	local lostGrip = used > 1

	local newState: State = {
		speed = speed,
		heading = heading,
		lean = lean,
		fallen = lostGrip,
		gear = gear,
		shiftCut = shiftCut,
	}
	return newState,
		{
			lostGrip = lostGrip,
			gripUsed = used,
			lateralG = lateralG,
			rpm = Gearbox.rpm(speed, gear, params),
			shifted = shifted,
			shiftRefused = shiftRefused,
		}
end

return BikeDynamics
