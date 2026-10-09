--!strict
-- Temporary settings panel, toggled with M. Wheel sensitivity rows are a slider with − / +
-- arrows either side; scroll direction is a toggle. Shows the system cursor while open so
-- the controls are easy to use.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Controls = require(ReplicatedStorage.Shared.config.Controls)
local Settings = require(script.Parent.Settings)

local SettingsPanel = {}

local TEXT = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(190, 190, 200)
local PANEL = Color3.fromRGB(18, 18, 22)
local BUTTON = Color3.fromRGB(45, 45, 55)
local ACCENT = Color3.fromRGB(255, 140, 30)

local gui: ScreenGui? = nil
local refreshers: { () -> () } = {}
local open = false

local function refreshAll()
	for _, refresh in refreshers do
		refresh()
	end
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, value: string, size: number, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = colour
	t.Text = value
	t.Parent = parent
	return t
end

local function button(parent: Instance, label: string, width: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, 30)
	b.BackgroundColor3 = BUTTON
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = TEXT
	b.Text = label
	b.Parent = parent
	corner(b, 6)
	b.Activated:Connect(function()
		onClick()
		refreshAll()
	end)
	return b
end

local function row(list: Frame, order: number, title: string): Frame
	local r = Instance.new("Frame")
	r.Name = title
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, 36)
	r.BackgroundTransparency = 1
	r.Parent = list
	local label = text(r, title, 15, MUTED)
	label.Size = UDim2.fromScale(0.55, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return r
end

-- Title and value on top; below, [−] slider [+]. Drag the knob or click the track; the
-- arrows nudge by one increment.
local function slider(list: Frame, order: number, title: string, name: "throttleStep" | "brakeStep")
	local r = Instance.new("Frame")
	r.Name = title
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, 58)
	r.BackgroundTransparency = 1
	r.Parent = list

	local label = text(r, title, 15, MUTED)
	label.Size = UDim2.new(0.7, 0, 0, 20)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local value = text(r, "", 16, TEXT)
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromOffset(60, 20)
	value.TextXAlignment = Enum.TextXAlignment.Right

	local minus = button(r, "−", 30, function()
		Settings.adjust(name, -1)
	end)
	minus.Name = "Minus"
	minus.Position = UDim2.fromOffset(0, 26)
	local plus = button(r, "+", 30, function()
		Settings.adjust(name, 1)
	end)
	plus.Name = "Plus"
	plus.AnchorPoint = Vector2.new(1, 0)
	plus.Position = UDim2.new(1, 0, 0, 26)

	-- A tall invisible hit area makes the thin track easy to grab.
	local hit = Instance.new("TextButton")
	hit.Name = "Slider"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(42, 26)
	hit.Size = UDim2.new(1, -84, 0, 30)
	hit.Parent = r

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = BUTTON
	track.BorderSizePixel = 0
	track.Parent = hit
	corner(track, 3)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 3)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 8)

	local range = Controls.stepMax - Controls.stepMin
	local function setFromScreenX(x: number)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		Settings.set(name, Controls.stepMin + fraction * range)
		refreshAll()
	end

	local dragging = false
	hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	table.insert(refreshers, function()
		local current = Settings[name] :: number
		local fraction = math.clamp((current - Controls.stepMin) / range, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		value.Text = string.format("%d%%", math.floor(current * 100 + 0.5))
	end)
end

local function toggle(list: Frame, order: number, title: string)
	local r = row(list, order, title)
	local b = button(r, "", 86, function()
		Settings.invertScroll()
	end)
	b.Position = UDim2.new(1, -86, 0.5, -15)
	b.TextSize = 15
	table.insert(refreshers, function()
		local inverted = Settings.scrollFasterSign < 0
		b.Text = if inverted then "ON" else "OFF"
		b.BackgroundColor3 = if inverted then ACCENT else BUTTON
	end)
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SettingsPanel"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Enabled = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(340, 290)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.1
	panel.Parent = screen
	corner(panel, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.75
	stroke.Thickness = 1.5
	stroke.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = panel

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local header = text(list, "SETTINGS", 18, TEXT)
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, 24)
	header.TextXAlignment = Enum.TextXAlignment.Left

	slider(list, 1, "Throttle per notch", "throttleStep")
	slider(list, 2, "Brake per notch", "brakeStep")
	toggle(list, 3, "Invert scroll")

	local hint = text(list, "Press M to close", 13, MUTED)
	hint.LayoutOrder = 4
	hint.Size = UDim2.new(1, 0, 0, 30)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	refreshAll()
end

function SettingsPanel.isOpen(): boolean
	return open
end

function SettingsPanel.toggle()
	if not gui then
		build()
	end
	open = not open;
	(gui :: ScreenGui).Enabled = open
	-- show the real cursor while open; the look view hides it again when closed
	UserInputService.MouseIconEnabled = open
end

return SettingsPanel
