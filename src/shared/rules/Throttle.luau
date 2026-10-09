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

-- Split the lever into throttle (0..1) and brake (0..1). Only one is ever non-zero.
function Throttle.split(lever: number): (number, number)
	if lever ~= lever then
		return 0, 0
	end
	local l = math.clamp(lever, -1, 1)
	return math.max(l, 0), math.max(-l, 0)
end

return Throttle
