local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local TeleportBehind = require("../games/duelinggrounds/features/TeleportBehind")
local localRoot = { CFrame = CFrame.new() }
local targetRoot = {
    Position = Vector3.new(10, 4, 5),
    CFrame = CFrame.lookAt(Vector3.new(10, 4, 5), Vector3.new(11, 4, 5)),
}
local frame = {
    localRoot = localRoot,
    targetRoot = targetRoot,
    distance = 3,
}

assert(TeleportBehind.update({ teleportBehind = true }, frame), "enabled teleport must update a valid local root")
assert((localRoot.CFrame.Position - Vector3.new(7, 4, 5)).Magnitude < 0.001, "destination must remain behind the target at target height")
assert(localRoot.CFrame.LookVector.X > 0.99, "local root must face the target after placement")

local before = localRoot.CFrame
assert(not TeleportBehind.update({ teleportBehind = false }, frame), "disabled teleport must be inert")
assert(localRoot.CFrame == before, "disabled teleport must not mutate placement")

frame.targetDead = true
assert(not TeleportBehind.update({ teleportBehind = true }, frame), "dead targets must be ignored")

frame.targetDead = false
frame.targetRoot = nil
assert(not TeleportBehind.update({ teleportBehind = true }, frame), "missing targets must be ignored")

print("duelinggrounds-teleport-behind-contracts-ok")
