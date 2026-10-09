--!strict
-- Pure respawn validation. The server calls this for every RequestRespawn.
local Respawn = {}

-- Returns whether to allow the respawn and, if not, why.
function Respawn.check(
	extraArgCount: number,
	isDead: boolean,
	now: number,
	lastRespawn: number,
	cooldown: number
): (boolean, string)
	if extraArgCount ~= 0 then
		return false, "unexpected payload"
	end
	if not isDead then
		return false, "not dead"
	end
	if now - lastRespawn < cooldown then
		return false, "cooldown"
	end
	return true, "ok"
end

return Respawn
