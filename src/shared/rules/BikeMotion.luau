--!strict
-- Pure bike motion maths. No Roblox objects, so it runs under Lune in tests.
local BikeMotion = {}

export type MotionConfig = {
	maxSpeed: number,
	acceleration: number,
	brakeDecel: number,
	drag: number,
	maxTurnRate: number,
	turnFalloff: number,
}

-- Clamp an input axis to [-1, 1]; NaN and non-numbers become 0.
function BikeMotion.sanitizeAxis(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(value, -1, 1)
end

-- Advance forward speed by one frame. Speed never goes below 0 (no reverse yet).
function BikeMotion.step(
	speed: number,
	throttle: number,
	brake: number,
	dt: number,
	config: MotionConfig
): number
	local t = math.max(BikeMotion.sanitizeAxis(throttle), 0)
	local b = math.max(BikeMotion.sanitizeAxis(brake), 0)
	local change = 0
	if t > 0 then
		change += config.acceleration * t
	else
		change -= config.drag
	end
	change -= config.brakeDecel * b
	return math.clamp(speed + change * dt, 0, config.maxSpeed)
end

-- Turn rate in rad/s (positive = right). Slower bikes turn tighter than fast ones.
function BikeMotion.turnRate(speed: number, steer: number, config: MotionConfig): number
	local s = BikeMotion.sanitizeAxis(steer)
	local ratio = math.clamp(speed / config.maxSpeed, 0, 1)
	return s * config.maxTurnRate * (1 - config.turnFalloff * ratio)
end

-- If physics slowed the bike (a wall, a ramp) by more than `slack`, trust physics.
-- Without this the controller would keep pushing the bike through obstacles.
function BikeMotion.syncSpeed(intended: number, actual: number, slack: number): number
	if actual < intended - slack then
		return math.max(actual, 0)
	end
	return intended
end

return BikeMotion
