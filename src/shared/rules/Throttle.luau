--!strict
-- Pure twist-grip control on the mouse wheel. One lever runs from full brake (-1) through
-- closed (0) to full throttle (+1). Rolling toward "slower" closes the throttle, then starts
-- braking; rolling back releases the brake, then opens the throttle. It stays where the rider
-- leaves it.
local Throttle = {}

-- New lever position after a scroll. `notches` is positive for "faster" and negative for
-- "slower"; the client maps the mouse wheel's direction onto that (see the rider's settings).
-- The throttle side moves `throttleStep` per notch and the brake side `brakeStep`. A notch
-- never crosses closed: it stops at 0, so there is always one click between throttle and
-- brake and you cannot brake by accident while rolling off.
function Throttle.fromScroll(
	lever: number,
	notches: number,
	throttleStep: number,
	brakeStep: number
): number
	if lever ~= lever then
		lever = 0
	end
	lever = math.clamp(lever, -1, 1)
	if notches ~= notches or notches == 0 then
		return lever
	end
	local direction = if notches > 0 then 1 else -1
	local remaining = math.abs(notches)
	while remaining > 1e-9 do
		local amount = math.min(remaining, 1)
		remaining -= amount
		-- which side the lever is moving on decides the step size
		local onThrottleSide = lever > 0 or (lever == 0 and direction > 0)
		local step = if onThrottleSide then throttleStep else brakeStep
		local nextLever = lever + direction * amount * step
		if (lever > 0 and nextLever < 0) or (lever < 0 and nextLever > 0) then
			nextLever = 0 -- stop at closed
		end
		lever = math.clamp(nextLever, -1, 1)
	end
	return lever
end

export type HandRates = {
	throttleOpenRate: number, -- lever units per second
	throttleCloseRate: number,
	brakeApplyRate: number,
	brakeReleaseRate: number,
}

-- Move the rider's right hand from `current` toward `target` over `dt` seconds, at realistic
-- speeds. The hand is one lever (throttle above 0, front brake below), so going from throttle
-- to brake always rolls the throttle closed first and only then squeezes the brake, each at its
-- own rate. Throttle and front brake can never both be on.
function Throttle.approach(current: number, target: number, dt: number, rates: HandRates): number
	if current ~= current then
		current = 0
	end
	if target ~= target then
		target = current
	end
	current = math.clamp(current, -1, 1)
	target = math.clamp(target, -1, 1)
	local pos = current
	local remaining = math.max(dt, 0)
	while remaining > 1e-12 and pos ~= target do
		local down = target < pos
		local rate
		if down then
			rate = if pos > 0 then rates.throttleCloseRate else rates.brakeApplyRate
		else
			rate = if pos < 0 then rates.brakeReleaseRate else rates.throttleOpenRate
		end
		-- stop at closed (0) when crossing it, because the rate changes there
		local crossing = (pos > 0 and target < 0) or (pos < 0 and target > 0)
		local goal = if crossing then 0 else target
		local distance = math.abs(goal - pos)
		local reach = rate * remaining
		if reach >= distance then
			pos = goal
			remaining -= distance / rate
		else
			pos += if down then -reach else reach
			remaining = 0
		end
	end
	return pos
end

-- Split the lever into throttle (0..1) and brake (0..1). Only one is ever non-zero.
function Throttle.split(lever: number): (number, number)
	if lever ~= lever then
		return 0, 0
	end
	local l = math.clamp(lever, -1, 1)
	return math.max(l, 0), math.max(-l, 0)
end

return Throttle
