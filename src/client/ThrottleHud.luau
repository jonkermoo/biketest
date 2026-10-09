--!strict
-- Riding HUD at the bottom right: gear and an rpm bar on top, then three vertical gauges
-- (front brake, rear brake, throttle), each filled to its opening with the percentage
-- underneath, and speed below.
local Players = game:GetService("Players")

local ThrottleHud = {}

local STUDS_PER_S_TO_KMH = 0.28 * 3.6 -- one stud is 0.28 m
local PANEL_WIDTH = 210

type Gauge = { fill: Frame, percent: TextLabel }

local root: ScreenGui? = nil
local frontGauge: Gauge? = nil
local rearGauge: Gauge? = nil
local throttleGauge: Gauge? = nil
local speedLabel: TextLabel? = nil
local gearLabel: TextLabel? = nil
local rpmFill: Frame? = nil
local rpmLabel: TextLabel? = nil
local redZone: Frame? = nil

local function label(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	width: number,
	size: number
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromOffset(x, y)
	text.Size = UDim2.fromOffset(width, size)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.6
	text.Font = Enum.Font.GothamBold
	text.TextSize = size
	text.Parent = parent
	return text
end

local function track(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local t = Instance.new("Frame")
	t.Name = name
	t.Position = position
	t.Size = size
	t.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	t.BackgroundTransparency = 0.35
	t.BorderSizePixel = 0
	t.ClipsDescendants = true
	t.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = t
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = t
	return t
end

local function gauge(
	parent: Instance,
	name: string,
	title: string,
	centreX: number,
	top: number,
	colour: Color3
): Gauge
	label(parent, name .. "Title", centreX, top, 70, 12).Text = title
	local t = track(
		parent,
		name .. "Track",
		UDim2.fromOffset(centreX - 13, top + 20),
		UDim2.fromOffset(26, 150)
	)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = t
	return { fill = fill, percent = label(parent, name .. "Percent", centreX, top + 176, 70, 18) }
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ThrottleHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -24, 1, -24)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 300)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	-- Gear and rpm
	local gear = label(panel, "Gear", 22, 0, 44, 40)
	gear.AnchorPoint = Vector2.new(0.5, 0)
	gearLabel = gear
	local rpmTrack =
		track(panel, "RpmTrack", UDim2.fromOffset(52, 6), UDim2.fromOffset(PANEL_WIDTH - 52, 14))
	local zone = Instance.new("Frame")
	zone.Name = "Redline"
	zone.AnchorPoint = Vector2.new(1, 0)
	zone.Position = UDim2.fromScale(1, 0)
	zone.BackgroundColor3 = Color3.fromRGB(225, 45, 45)
	zone.BackgroundTransparency = 0.5
	zone.BorderSizePixel = 0
	zone.Parent = rpmTrack
	redZone = zone
	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = rpmTrack
	rpmFill = bar
	local rpmText = label(panel, "Rpm", 52 + (PANEL_WIDTH - 52) / 2, 24, PANEL_WIDTH - 52, 12)
	rpmLabel = rpmText

	frontGauge = gauge(panel, "Brake", "FRONT", 35, 48, Color3.fromRGB(225, 45, 45))
	rearGauge = gauge(panel, "Rear", "REAR", 105, 48, Color3.fromRGB(170, 60, 200))
	throttleGauge = gauge(panel, "Throttle", "THROTTLE", 175, 48, Color3.fromRGB(255, 140, 30))
	speedLabel = label(panel, "Speed", PANEL_WIDTH / 2, 248, PANEL_WIDTH, 14)

	root = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ThrottleHud.setVisible(visible: boolean)
	if not root then
		build()
	end
	(root :: ScreenGui).Enabled = visible
end

local function show(g: Gauge, value: number)
	g.fill.Size = UDim2.fromScale(1, value)
	g.percent.Text = string.format("%d%%", math.floor(value * 100 + 0.5))
end

export type Reading = {
	throttle: number,
	front: number,
	rear: number,
	speed: number, -- studs/s
	gear: number,
	rpm: number,
	redline: number,
	rpmScale: number, -- rpm at the right end of the bar
}

function ThrottleHud.update(r: Reading)
	if not root then
		build()
	end
	show(throttleGauge :: Gauge, r.throttle)
	show(frontGauge :: Gauge, r.front)
	show(rearGauge :: Gauge, r.rear);
	(speedLabel :: TextLabel).Text =
		string.format("%d km/h", math.floor(r.speed * STUDS_PER_S_TO_KMH + 0.5));
	(gearLabel :: TextLabel).Text = tostring(r.gear)
	local fraction = math.clamp(r.rpm / r.rpmScale, 0, 1);
	(rpmFill :: Frame).Size = UDim2.fromScale(fraction, 1);
	(rpmFill :: Frame).BackgroundColor3 = if r.rpm >= r.redline * 0.97
		then Color3.fromRGB(255, 70, 70)
		else Color3.new(1, 1, 1);
	(redZone :: Frame).Size = UDim2.fromScale(math.clamp(1 - r.redline / r.rpmScale, 0, 1), 1);
	(rpmLabel :: TextLabel).Text = string.format("%d rpm", math.floor(r.rpm / 100 + 0.5) * 100)
end

return ThrottleHud
