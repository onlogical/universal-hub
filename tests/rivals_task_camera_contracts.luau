local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector2 = roblox.Vector2
local TaskCamera = require("../games/rivals/TaskCamera")
local camera = { CFrame = CFrame.new(4, 5, 6) }
local rotation = Vector2.new(math.rad(-12), math.rad(70))
assert(TaskCamera.commit(camera, rotation) == true)
assert((camera.CFrame.Position - roblox.Vector3.new(4, 5, 6)).Magnitude < 1e-6, "task camera commit must preserve native camera position")
local expected = (CFrame.Angles(0, rotation.Y, 0) * CFrame.Angles(rotation.X, 0, 0)).LookVector
assert(camera.CFrame.LookVector:Dot(expected) > 0.9999, "task camera commit must visibly apply requested pitch and yaw even when native SetRotation is ignored")
print("rivals-task-camera-contracts-ok")
