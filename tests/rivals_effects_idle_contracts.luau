local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3
Color3 = roblox.Color3
local Effects = require("../games/rivals/Effects")

local traversals = 0
local root = {
    GetDescendants = function()
        traversals += 1
        return {}
    end,
}
local effects = Effects.new({
    lighting = root,
    localPlayer = { FindFirstChildOfClass = function() return root end },
    playerGui = root,
    projectileAim = {},
    workspace = { CurrentCamera = root },
})
effects:update({ noFlash = false, noSmoke = false })
assert(traversals == 0, "disabled visual suppression must not traverse Lighting, Camera, or PlayerGui")
effects:stop()
print("rivals-effects-idle-contracts-ok")
