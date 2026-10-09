--!strict
-- Throttle and brake gauges at the bottom right: two vertical bars side by side, each filled
-- to its opening with the percentage underneath, and speed below both.
local Players = game:GetService("Players")

local ThrottleHud = {}

local STUDS_PER_S_TO_KMH = 0.28 * 3.6 -- one stud is 0.28 m

type Gauge = { fill: Frame, percent: TextLabel }

local root: ScreenGui? = nil
local throttleGauge: Gauge? = nil
local brakeGauge: Gauge? = nil
local speedLabel: TextLabel? = nil

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

local function gauge(parent: Instance, name: string, centreX: number, colour: Color3): Gauge
	label(parent, name .. "Title", centreX, 0, 80, 12).Text = string.upper(name)

	local track = Instance.new("Frame")
	track.Name = name .. "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromOffset(centreX, 20)
	track.Size = UDim2.fromOffset(26, 150)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.35
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = track

	return { fill = fill, percent = label(parent, name .. "Percent", centreX, 176, 80, 18) }
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
	panel.Size = UDim2.fromOffset(150, 230)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	brakeGauge = gauge(panel, "Brake", 35, Color3.fromRGB(225, 45, 45))
	throttleGauge = gauge(panel, "Throttle", 115, Color3.fromRGB(255, 140, 30))
	speedLabel = label(panel, "Speed", 75, 204, 150, 14)

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

-- `throttle` and `brake` 0..1, `speed` in studs/s
function ThrottleHud.update(throttle: number, brake: number, speed: number)
	if not root then
		build()
	end
	show(throttleGauge :: Gauge, throttle)
	show(brakeGauge :: Gauge, brake);
	(speedLabel :: TextLabel).Text =
		string.format("%d km/h", math.floor(speed * STUDS_PER_S_TO_KMH + 0.5))
end

return ThrottleHud
