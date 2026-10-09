--!strict
-- Input settings. These are the defaults; the in-game settings panel (M) can change them for
-- the current session.
return table.freeze({
	-- Mouse-wheel lever: share of full throttle / full brake per wheel notch
	throttleStep = 0.05,
	brakeStep = 0.05,
	-- Range and increment the settings panel allows for both steps
	stepMin = 0.01,
	stepMax = 0.25,
	stepIncrement = 0.01,

	-- Which wheel direction means "faster": notches = wheel delta * this sign. The first
	-- version used -1, and on the user's mouse that felt backwards (rolling the wheel down
	-- toward you slowed the bike), so it was flipped on 2026-10-09. The settings panel can
	-- invert it too.
	scrollFasterSign = 1,

	settingsKey = Enum.KeyCode.M,
})
