--!strict
-- Pure riding model: speed, steering, lean, grip and falling. No Roblox objects, so it runs
-- under Lune in tests. The Roblox side only reads the new state and moves the model.
local BikeDynamics = {}

export type Params = {
	maxSpeed: number,
	launchAccel: number, -- traction/wheelie-limited acceleration at low speed
	powerPerMass: number, -- engine power per unit mass: drive acceleration = this / speed
	rollingResistance: number,
	engineBraking: number, -- deceleration from a fully closed throttle
	aeroDrag: number,
	brakeDecel: number,
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
}

export type Input = {
	throttle: number, -- 0..1
	brake: number, -- 0..1
	steer: number, -- -1..1, positive = right. Keyboard steering, capped by the assist.
	-- Curvature asked for by the look target (1/studs, positive = right). When present it
	-- replaces `steer` and is NOT capped by the assist, so looking too sharply can ask for
	-- more grip than the tyres have.
	curvature: number?,
}

export type Events = {
	lostGrip: boolean,
	gripUsed: number, -- 0..1+, how much of the tyre grip budget is in use
	lateralG: number,
}

function BikeDynamics.newState(heading: number): State
	return { speed = 0, heading = heading, lean = 0, fallen = false }
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

-- Forward push from the engine. Power-limited: at low speed the bike can only use so much
-- before the front lifts or the tyre spins (`launchAccel`); above that, a fixed power gives
-- less acceleration the faster you go (power = force x speed).
function BikeDynamics.driveAccel(speed: number, throttle: number, params: Params): number
	return throttle * math.min(params.launchAccel, params.powerPerMass / math.max(speed, 1))
end

-- Everything slowing the bike apart from the brakes: rolling resistance, air drag (grows
-- with speed squared) and engine braking, which fades in as the throttle closes.
function BikeDynamics.resistance(speed: number, throttle: number, params: Params): number
	if speed <= 0 then
		return 0
	end
	return params.rollingResistance
		+ params.aeroDrag * speed * speed
		+ params.engineBraking * (1 - throttle)
end

local function stepFallen(state: State, dt: number, params: Params): State
	local side = if state.lean >= 0 then 1 else -1
	local lean = state.lean + (side * params.lyingLean - state.lean) * (1 - math.exp(-6 * dt))
	return {
		speed = math.max(state.speed - params.slideDecel * dt, 0),
		heading = state.heading,
		lean = lean,
		fallen = true,
	}
end

-- Advance the bike by one frame. Returns the new state and what happened this frame.
function BikeDynamics.step(state: State, input: Input, params: Params, dt: number): (State, Events)
	if state.fallen then
		return stepFallen(state, dt, params), { lostGrip = false, gripUsed = 0, lateralG = 0 }
	end

	local throttle = BikeDynamics.sanitize(input.throttle, 0, 1)
	local brake = BikeDynamics.sanitize(input.brake, 0, 1)
	local steer = BikeDynamics.sanitize(input.steer, -1, 1)

	-- Speed
	local change = BikeDynamics.driveAccel(state.speed, throttle, params)
		- BikeDynamics.resistance(state.speed, throttle, params)
		- params.brakeDecel * brake
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
	local longitudinalG = (params.brakeDecel * brake) / params.gravity
	local used = BikeDynamics.gripUsed(lateralG, longitudinalG, params.tyreGrip)
	local lostGrip = used > 1

	local newState: State = { speed = speed, heading = heading, lean = lean, fallen = lostGrip }
	return newState, { lostGrip = lostGrip, gripUsed = used, lateralG = lateralG }
end

return BikeDynamics
