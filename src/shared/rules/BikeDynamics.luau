--!strict
-- Pure riding model: speed, steering, lean, grip and falling. No Roblox objects, so it runs
-- under Lune in tests. The Roblox side only reads the new state and moves the model.
local BikeDynamics = {}

export type Params = {
	maxSpeed: number,
	acceleration: number,
	brakeDecel: number,
	drag: number,
	maxCurvature: number,
	curvatureSpeedRef: number,
	leanRate: number,
	gravity: number,
	tyreGrip: number,
	steerAssist: number,
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
	steer: number, -- -1..1, positive = right. Keyboard now, look target later.
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

-- Tightest turn the bike can make at this speed, in 1/studs. Narrower at speed, and capped
-- so that a full-lock key press stays inside `steerAssist` of the tyre grip budget. This is
-- what makes keyboard steering safe. A look target (later) asks for curvature directly and
-- is not capped, which is how you can ask for a turn the tyres cannot hold.
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
	local change = if throttle > 0 then params.acceleration * throttle else -params.drag
	change -= params.brakeDecel * brake
	local speed = math.clamp(state.speed + change * dt, 0, params.maxSpeed)

	-- The rider asks for a turn; the bike leans to hold that lateral acceleration.
	local demandedCurvature = steer * BikeDynamics.maxCurvatureAt(speed, params)
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
