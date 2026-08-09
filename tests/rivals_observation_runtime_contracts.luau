local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
CFrame = roblox.CFrame
local ObservationRuntime = require("../games/rivals/ObservationRuntime")

local near = { character = {}, player = {}, position = Vector3.new(0, 0, -10) }
near.character.FindFirstChildOfClass = function() return { Health = 80, MaxHealth = 100 } end
local far = { character = {}, player = {}, position = Vector3.new(0, 0, -2001) }
far.character.FindFirstChildOfClass = near.character.FindFirstChildOfClass
local targeting = {
    observePlayers = function() return { near, far } end,
    observeCharacter = function() return nil end,
}
local workspace = {
    CurrentCamera = { CFrame = CFrame.identity },
    FindFirstChild = function() return nil end,
}
local runtime = ObservationRuntime.new({
    equippedWeapon = function() return "native item" end,
    getFighter = function() return nil end,
    isOpponent = function() return true end,
    targeting = targeting,
    workspace = workspace,
})
local observations = runtime:update(Vector2.zero)
assert(#observations == 1 and observations[1] == near)
assert(near.health == 80 and near.maxHealth == 100 and near.weapon == "native item")
near.character.FindFirstChildOfClass = function() return nil end
observations = runtime:update(Vector2.zero)
assert(observations[1].health == nil and observations[1].maxHealth == nil, "missing native health must remain unknown")

print("rivals-observation-runtime-contracts-ok")
