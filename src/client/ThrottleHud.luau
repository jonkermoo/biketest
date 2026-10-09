--!strict
-- Small throttle gauge at the bottom right: a vertical bar filled to the throttle opening,
-- the percentage, and speed underneath.
local Players = game:GetService("Players")

local ThrottleHud = {}

local STUDS_PER_S_TO_KMH = 0.28 * 3.6 -- one stud is 0.28 m

local fill: Frame? = nil
local percent: TextLabel? = nil
local speedLabel: TextLabel? = nil
local root: ScreenGui? = nil

local function label(parent: Instance, name: string, y: number, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, y)
	text.Size = UDim2.fromOffset(90, size)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.6
	text.Font = Enum.Font.GothamBold
	text.TextSize = size
	text.Parent = parent
	return text
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
	panel.Size = UDim2.fromOffset(90, 230)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	label(panel, "Title", 0, 12).Text = "THROTTLE"

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 20)
	track.Size = UDim2.fromOffset(26, 150)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.35
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = panel
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = track

	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.fromScale(1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(255, 140, 30)
	bar.BorderSizePixel = 0
	bar.Parent = track

	percent = label(panel, "Percent", 176, 18)
	speedLabel = label(panel, "Speed", 200, 13)
	fill = bar
	root = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ThrottleHud.setVisible(visible: boolean)
	if not root then
		build()
	end
	(root :: ScreenGui).Enabled = visible
end

-- `throttle` 0..1, `speed` in studs/s
function ThrottleHud.update(throttle: number, speed: number)
	if not root then
		build()
	end
	(fill :: Frame).Size = UDim2.fromScale(1, throttle);
	(percent :: TextLabel).Text = string.format("%d%%", math.floor(throttle * 100 + 0.5));
	(speedLabel :: TextLabel).Text =
		string.format("%d km/h", math.floor(speed * STUDS_PER_S_TO_KMH + 0.5))
end

return ThrottleHud
