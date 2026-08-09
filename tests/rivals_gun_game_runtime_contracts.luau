local GunGameRuntime = require("../games/rivals/GunGameRuntime")

local touches = {}
local now = 10
local enabled = false
local nativeGunGame = true
local drop = {
    Name = "_drop",
    Parent = nil,
    FindFirstChild = function(_self, name) return name == "Health" and {} or nil end,
    IsA = function(_self, name) return name == "BasePart" end,
}
local workspace = { GetChildren = function() return { drop } end }
drop.Parent = workspace
local store = { Get = function() return { settings = { autoPickup = enabled } } end }
local fighter = {
    Entity = { Humanoid = { Health = 50, MaxHealth = 100 }, RootPart = {} },
}
local runtime = GunGameRuntime.new({
    clock = function() return now end,
    fireTouchInterest = function(part, target, toggle)
        table.insert(touches, { part = part, target = target, toggle = toggle })
    end,
    getFighter = function() return fighter end,
    isActive = function() return true end,
    isGunGame = function() return nativeGunGame end,
    isInCombat = function() return true end,
    spawn = function(callback) callback() end,
    store = store,
    wait = function() end,
    workspace = workspace,
})
runtime:update()
assert(#touches == 0, "disabled runtime must do zero pickup work")
enabled = true
nativeGunGame = false
runtime:update()
assert(#touches == 0, "non-Gun-Game native state must do zero pickup work")
nativeGunGame = true
runtime:update()
assert(#touches == 2 and touches[1].toggle == 1 and touches[2].toggle == 0)
runtime:update()
assert(#touches == 2, "pickup attempts must be throttled")
runtime:stop()
now += 1
runtime:update()
assert(#touches == 2, "stopped runtime must remain inert")

print("rivals-gun-game-runtime-contracts-ok")
