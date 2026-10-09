--!strict
-- Pure look-steering maths. The Roblox side turns the world marker into a position relative
-- to the bike (lateral, forward) and asks here for the curve that reaches it.
local LookSteer = {}

-- Curvature (1/studs, positive = right) of the arc that starts along the bike's heading and
-- passes through a point `lateral` studs to the right and `forward` studs ahead. This is the
-- pure-pursuit arc: k = 2x / d^2. A point behind the bike asks for the tightest turn on that
-- side; the riding model caps it.
function LookSteer.curvatureTo(lateral: number, forward: number): number
	if lateral ~= lateral or forward ~= forward then
		return 0
	end
	if forward <= 0 then
		if lateral > 0 then
			return math.huge
		elseif lateral < 0 then
			return -math.huge
		end
		return 0
	end
	local distanceSq = lateral * lateral + forward * forward
	return 2 * lateral / distanceSq
end

-- Target fixation (optional difficulty setting). While the look point sits on a hazard, the
-- target the bike steers to lets go of it slowly: your eyes have moved on but the bike is
-- still drawn to what you stared at. `strength` 0 = off, 1 = very sticky.
-- Positions are plain {x, z} tables in world studs so this stays pure.
export type Point = { x: number, z: number }

function LookSteer.fixate(
	previous: Point,
	raw: Point,
	onHazard: boolean,
	strength: number,
	dt: number
): Point
	if strength <= 0 or not onHazard then
		return raw
	end
	local s = math.clamp(strength, 0, 1)
	-- follow rate in 1/s: fast when s is small, slow when s is 1
	local rate = 12 * (1 - s) + 0.5
	local alpha = 1 - math.exp(-rate * dt)
	return {
		x = previous.x + (raw.x - previous.x) * alpha,
		z = previous.z + (raw.z - previous.z) * alpha,
	}
end

return LookSteer
