--!strict
-- Settings panel, toggled with the settings key (M by default). Sections: profiles, mouse
-- wheel, brakes and controls. Every change saves to the active profile automatically. Shows
-- the system cursor while open so the controls are easy to use.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RiderSettings = require(ReplicatedStorage.Shared.rules.RiderSettings)
local Settings = require(script.Parent.Settings)

local SettingsPanel = {}

local TEXT = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(190, 190, 200)
local PANEL = Color3.fromRGB(18, 18, 22)
local BUTTON = Color3.fromRGB(45, 45, 55)
local ACCENT = Color3.fromRGB(255, 140, 30)
local DANGER = Color3.fromRGB(150, 45, 45)

local gui: ScreenGui? = nil
local refreshers: { () -> () } = {}
local open = false
local captureMessage: string? = nil

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
	b.TextSize = 15
	b.TextColor3 = TEXT
	b.Text = label
	b.Parent = parent
	corner(b, 6)
	b.Activated:Connect(onClick)
	return b
end

local function container(list: Instance, order: number, name: string, height: number): Frame
	local r = Instance.new("Frame")
	r.Name = name
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, height)
	r.BackgroundTransparency = 1
	r.Parent = list
	return r
end

local function heading(list: Instance, order: number, title: string)
	local r = container(list, order, title .. "Heading", 26)
	local t = text(r, title, 13, ACCENT)
	t.Size = UDim2.fromScale(1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Bottom
end

-- Title and value on top; below, [−] slider [+]. Drag the knob or click the track; the arrows
-- nudge by one increment.
local function slider(
	list: Instance,
	order: number,
	title: string,
	name: string,
	format: (number) -> string
)
	local r = container(list, order, title, 58)
	local range = RiderSettings.RANGES[name]
	local lo, hi = range[1], range[2]

	local label = text(r, title, 15, MUTED)
	label.Size = UDim2.new(0.6, 0, 0, 20)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local value = text(r, "", 15, TEXT)
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.new(0.4, 0, 0, 20)
	value.TextXAlignment = Enum.TextXAlignment.Right

	local minus = button(r, "−", 30, function()
		Settings.adjust(name, -1)
	end)
	minus.Name = "Minus"
	minus.TextSize = 18
	minus.Position = UDim2.fromOffset(0, 26)
	local plus = button(r, "+", 30, function()
		Settings.adjust(name, 1)
	end)
	plus.Name = "Plus"
	plus.TextSize = 18
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

	local function setFromScreenX(x: number)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		Settings.set(name, lo + fraction * (hi - lo))
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
		local current = (Settings.current :: any)[name] :: number
		local fraction = math.clamp((current - lo) / (hi - lo), 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		value.Text = format(current)
	end)
end

local function percent(v: number): string
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

-- An ON/OFF row. `isOn` reads the setting; `flip` changes it.
local function toggle(
	list: Instance,
	order: number,
	title: string,
	isOn: () -> boolean,
	flip: () -> ()
)
	local r = container(list, order, title, 36)
	local label = text(r, title, 15, MUTED)
	label.Size = UDim2.fromScale(0.6, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local b = button(r, "", 86, flip)
	b.Name = "Toggle"
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.fromScale(1, 0.5)
	table.insert(refreshers, function()
		local on = isOn()
		b.Text = if on then "ON" else "OFF"
		b.BackgroundColor3 = if on then ACCENT else BUTTON
	end)
end

local function bindingRow(list: Instance, order: number, action: string)
	local r = container(list, order, action, 34)
	local label = text(r, RiderSettings.ACTION_LABELS[action], 15, MUTED)
	label.Size = UDim2.fromScale(0.55, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local b = button(r, "", 130, function()
		Settings.capturing = if Settings.capturing == action then nil else action
		captureMessage = nil
		refreshAll()
	end)
	b.Name = "Bind"
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.fromScale(1, 0.5)
	table.insert(refreshers, function()
		if Settings.capturing == action then
			b.Text = captureMessage or "Press a key…"
			b.BackgroundColor3 = ACCENT
		else
			b.Text = Settings.displayName(Settings.current.bindings[action])
			b.BackgroundColor3 = BUTTON
		end
	end)
end

local function profilesRow(list: Instance, order: number)
	local r = container(list, order, "Profiles", 34)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = r
	for slot = 1, RiderSettings.MAX_PROFILES do
		local b = button(r, tostring(slot), 58, function()
			Settings.selectProfile(slot)
		end)
		b.Name = "Slot" .. slot
		b.LayoutOrder = slot
		table.insert(refreshers, function()
			local exists = Settings.profiles.slots[slot] ~= false
			local active = Settings.profiles.active == slot
			b.Text = if exists then `Profile {slot}` else "+ New"
			b.TextSize = 12
			b.BackgroundColor3 = if active then ACCENT elseif exists then BUTTON else PANEL
		end)
	end

	local actions = container(list, order + 1, "ProfileActions", 34)
	local del = button(actions, "Delete profile", 130, function()
		Settings.deleteProfile(Settings.profiles.active)
	end)
	del.Name = "Delete"
	del.BackgroundColor3 = DANGER
	local reset = button(actions, "Reset to defaults", 150, function()
		Settings.resetToDefaults()
	end)
	reset.Name = "Reset"
	reset.AnchorPoint = Vector2.new(1, 0)
	reset.Position = UDim2.fromScale(1, 0)
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
	panel.Size = UDim2.new(0, 400, 0.85, 0)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.08
	panel.Parent = screen
	corner(panel, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.75
	stroke.Thickness = 1.5
	stroke.Parent = panel
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(400, 640)
	sizeLimit.Parent = panel

	local header = text(panel, "SETTINGS", 18, TEXT)
	header.Position = UDim2.fromOffset(18, 14)
	header.Size = UDim2.new(1, -36, 0, 22)
	header.TextXAlignment = Enum.TextXAlignment.Left
	local status = text(panel, "", 12, MUTED)
	status.Name = "Status"
	status.Position = UDim2.fromOffset(18, 38)
	status.Size = UDim2.new(1, -36, 0, 16)
	status.TextXAlignment = Enum.TextXAlignment.Left
	table.insert(refreshers, function()
		local where = ({
			loading = "Loading your settings…",
			saved = "Changes save automatically to your account.",
			session = "Saving unavailable here: settings last for this session only.",
			error = "Could not reach the server: settings last for this session only.",
		})[Settings.storage] or ""
		local closeKey = Settings.displayName(Settings.current.bindings.settings)
		status.Text = `{where}  {closeKey} to close.`
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(18, 62)
	scroll.Size = UDim2.new(1, -30, 1, -76)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll

	heading(scroll, 1, "PROFILES")
	profilesRow(scroll, 2)

	heading(scroll, 10, "MOUSE WHEEL (THROTTLE / BRAKE LEVER)")
	slider(scroll, 11, "Throttle per notch", "throttleStep", percent)
	slider(scroll, 12, "Brake per notch", "brakeStep", percent)
	toggle(scroll, 13, "Invert scroll", function()
		return Settings.current.scrollFasterSign < 0
	end, Settings.invertScroll)

	heading(scroll, 15, "GEARBOX")
	toggle(scroll, 16, "Automatic gearbox", function()
		return Settings.current.autoShift
	end, Settings.toggleAutoShift)

	heading(scroll, 20, "BRAKES")
	slider(scroll, 21, "Threshold brake", "thresholdBrake", percent)
	slider(scroll, 22, "Rear brake build-up", "rearBrakeGrowth", function(growth)
		local full = RiderSettings.rearBrakeTimeToFull(Settings.current.rearBrakeStart, growth)
		return string.format("%.1f/s  (full in %.1f s)", growth, full)
	end)

	heading(scroll, 30, "CONTROLS (click, then press a key or mouse button)")
	for i, action in RiderSettings.ACTIONS do
		bindingRow(scroll, 30 + i, action)
	end

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	refreshAll()
end

-- While a binding button is waiting, the next key or mouse button is captured. Escape cancels.
UserInputService.InputBegan:Connect(function(input: InputObject)
	local action = Settings.capturing
	if not action or not open then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		Settings.capturing = nil
		refreshAll()
		return
	end
	local name = Settings.inputName(input)
	if name == nil then
		return -- mouse movement and the like
	end
	if not RiderSettings.isBindable(name) then
		captureMessage = `{name} can't be used`
		refreshAll()
		return
	end
	-- the click that pressed the binding button itself is a MouseButton1 Activated, which
	-- fires on release, so it is not captured here
	Settings.capturing = nil
	captureMessage = nil
	Settings.rebind(action, name)
end)

Settings.onChanged(function()
	if gui then
		refreshAll()
	end
end)

function SettingsPanel.isOpen(): boolean
	return open
end

function SettingsPanel.toggle()
	if not gui then
		build()
	end
	open = not open
	if not open then
		Settings.capturing = nil
	end
	(gui :: ScreenGui).Enabled = open
	-- show the real cursor while open; the look view hides it again when closed
	UserInputService.MouseIconEnabled = open
	refreshAll()
end

return SettingsPanel
