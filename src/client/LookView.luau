--!strict
-- First-person view: rider's-head camera, the faint screen cursor dot, and the world marker
-- placed where the look ray through the cursor hits the world.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Look = require(ReplicatedStorage.Shared.config.Look)

local LookView = {}

export type LookResult = {
	point: Vector3, -- where the rider is looking, in the world
	hitSomething: boolean, -- false when looking at the sky
	onHazard: boolean, -- the marker sits on a part tagged as a hazard
}

local player = Players.LocalPlayer
local cursor: Frame? = nil
local marker: Part? = nil
local active = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ensureCursor(): Frame
	if cursor and cursor.Parent then
		return cursor
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "LookCursor"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(Look.cursorSize, Look.cursorSize)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BackgroundTransparency = Look.cursorTransparency
	dot.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	dot.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	cursor = dot
	return dot
end

local function ensureMarker(): Part
	if marker and marker.Parent then
		return marker
	end
	-- Local to this client: other players do not see your eyes.
	local disc = Instance.new("Part")
	disc.Name = "LookMarker"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.12, Look.markerDiameter, Look.markerDiameter)
	disc.Material = Enum.Material.Neon
	disc.Color = Look.markerColor
	disc.Transparency = Look.markerTransparency
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Parent = Workspace
	marker = disc
	return disc
end

-- Start the first-person view. `ignore` are instances the look ray passes through.
function LookView.enable(ignore: { Instance })
	active = true
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Look.fieldOfView
	UserInputService.MouseIconEnabled = false
	ensureCursor().Visible = true
	ensureMarker().Transparency = Look.markerTransparency
	local filter = table.clone(ignore)
	table.insert(filter, ensureMarker())
	rayParams.FilterDescendantsInstances = filter
end

function LookView.disable()
	if not active then
		return
	end
	active = false
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseIconEnabled = true
	if cursor then
		cursor.Visible = false
	end
	if marker then
		marker.Transparency = 1
	end
end

-- Place the camera at the rider's head. `bikePose` is the bike's full pose (including lean);
-- the view only follows part of the lean, like a rider keeping their head nearer level.
function LookView.updateCamera(ground: Vector3, yaw: CFrame, pitch: number, lean: number)
	local bikePose = CFrame.new(ground)
		* yaw
		* CFrame.Angles(pitch, 0, 0)
		* CFrame.Angles(0, 0, -lean)
	local head = (bikePose * CFrame.new(Look.headOffset)).Position
	local view = yaw
		* CFrame.Angles(pitch, 0, 0)
		* CFrame.Angles(0, 0, -lean * Look.cameraLeanFollow)
	Workspace.CurrentCamera.CFrame = CFrame.new(head) * view

	-- The camera sits inside the rider; hide your own body from yourself.
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 1
			end
		end
	end
end

-- Cast the look ray through the mouse, move the dot and the marker, and report the look point.
function LookView.updateLook(): LookResult
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local mouse = UserInputService:GetMouseLocation()
	ensureCursor().Position = UDim2.fromOffset(mouse.X, mouse.Y)

	local ray = Workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * Look.maxLookDistance, rayParams)
	local disc = ensureMarker()
	if hit then
		-- Disc lies flat on the surface: its cylinder axis (X) along the surface normal.
		disc.CFrame = CFrame.lookAt(hit.Position, hit.Position + hit.Normal)
			* CFrame.Angles(0, math.rad(90), 0)
		disc.Transparency = Look.markerTransparency
		local onHazard = CollectionService:HasTag(hit.Instance, Look.hazardTag)
		return { point = hit.Position, hitSomething = true, onHazard = onHazard }
	end
	disc.Transparency = 1
	return {
		point = ray.Origin + ray.Direction.Unit * Look.skyLookDistance,
		hitSomething = false,
		onHazard = false,
	}
end

return LookView
