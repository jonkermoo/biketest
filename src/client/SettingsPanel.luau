--!strict
-- Temporary settings panel, toggled with M. Rows of − / + buttons for wheel sensitivity and
-- a toggle for scroll direction. Shows the system cursor while open so the buttons are easy
-- to click.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

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
		for _, refresh in refreshers do
			refresh()
		end
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

local function stepper(
	list: Frame,
	order: number,
	title: string,
	name: "throttleStep" | "brakeStep"
)
	local r = row(list, order, title)
	local minus = button(r, "−", 30, function()
		Settings.adjust(name, -1)
	end)
	minus.Position = UDim2.new(1, -116, 0.5, -15)
	local value = text(r, "", 16, TEXT)
	value.Size = UDim2.fromOffset(52, 30)
	value.Position = UDim2.new(1, -84, 0.5, -15)
	local plus = button(r, "+", 30, function()
		Settings.adjust(name, 1)
	end)
	plus.Position = UDim2.new(1, -30, 0.5, -15)
	table.insert(refreshers, function()
		value.Text = string.format("%d%%", math.floor((Settings[name] :: number) * 100 + 0.5))
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
	panel.Size = UDim2.fromOffset(340, 236)
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

	stepper(list, 1, "Throttle per notch", "throttleStep")
	stepper(list, 2, "Brake per notch", "brakeStep")
	toggle(list, 3, "Invert scroll")

	local hint = text(list, "Press M to close", 13, MUTED)
	hint.LayoutOrder = 4
	hint.Size = UDim2.new(1, 0, 0, 30)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	for _, refresh in refreshers do
		refresh()
	end
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
