--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bike = require(Shared.config.Bike)
local BikeMotion = require(Shared.rules.BikeMotion)

local player = Players.LocalPlayer
local requestRespawn = ReplicatedStorage:WaitForChild(Remotes.RequestRespawn) :: RemoteEvent

-- Input layer: turns keys into plain numbers. Gamepad or touch would add sources here
-- and leave the bike code below untouched.
local function readInput(): (number, number, number)
	local throttle = if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0
	local brake = if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0
	local steer = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
		- (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
	return throttle, brake, steer
end

local function findBody(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat.Name == "BikeSeat" and seat.Parent then
		local body = seat.Parent:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			return body
		end
	end
	return nil
end

local activeBody: BasePart? = nil
local align: AlignOrientation? = nil
local heading = 0
local speed = 0

local function detach()
	if align then
		align:Destroy()
		align = nil
	end
	activeBody = nil
end

local function attach(body: BasePart)
	detach()
	activeBody = body
	local _, yaw, _ = body.CFrame:ToEulerAnglesYXZ()
	heading = yaw
	speed = 0

	local attachment = Instance.new("Attachment")
	attachment.Parent = body
	local alignment = Instance.new("AlignOrientation")
	alignment.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignment.Attachment0 = attachment
	alignment.RigidityEnabled = true
	alignment.CFrame = CFrame.Angles(0, heading, 0)
	alignment.Parent = body
	align = alignment
end

RunService.Heartbeat:Connect(function(dt: number)
	local body = findBody()
	if not body then
		if activeBody then
			detach()
		end
		return
	end
	if body ~= activeBody then
		attach(body)
	end

	local throttle, brake, steer = readInput()
	local velocity = body.AssemblyLinearVelocity
	local forward = CFrame.Angles(0, heading, 0).LookVector

	speed = BikeMotion.syncSpeed(speed, velocity:Dot(forward), Bike.syncSlack)
	speed = BikeMotion.step(speed, throttle, brake, dt, Bike)
	heading -= BikeMotion.turnRate(speed, steer, Bike) * dt

	local cframe = CFrame.Angles(0, heading, 0)
	if align then
		align.CFrame = cframe
	end
	body.AssemblyLinearVelocity = cframe.LookVector * speed + Vector3.new(0, velocity.Y, 0)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		requestRespawn:FireServer()
	end
end)
