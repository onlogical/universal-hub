local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local Definition = require("../games/rivals/Definition")
local ProjectileAim = require("../games/rivals/libraries/ProjectileAim")
local Session = require("../games/rivals/Session")
local SilentAim = require("../games/rivals/features/SilentAim")
local Targeting = require("../games/rivals/libraries/Targeting")

assert(table.find(Definition.sources, "games/rivals/Session"))
assert(table.find(Definition.sources, "games/rivals/features/SilentAim"))

local session = Session.new()
assert(session.aligned == nil and session.presented == nil)
assert(type(session.settings) == "table")

local updates = {}
local clears = 0
local presented = { id = "presented" }
local presentation = {
    clear = function()
        clears += 1
    end,
    update = function(_self, rotation, target)
        table.insert(updates, {
            rotation = rotation,
            target = target,
        })
    end,
    getPresentedTarget = function()
        return presented
    end,
}

local origin = Vector3.new(0, 2, 0)
local aligned = {
    position = Vector3.new(10, 2, -4),
    player = { Name = "target" },
}
local libs = {
    targeting = Targeting,
    maxDistance = ProjectileAim.MAX_DISTANCE,
}

session.settings = { shotAim = false }
session.aligned = aligned
session.cameraOrigin = origin
SilentAim.update(session, presentation, libs)
assert(clears == 1 and #updates == 0 and session.presented == nil, "Silent Aim must clear when shotAim is off")

session.settings = { shotAim = true }
session.aligned = nil
SilentAim.update(session, presentation, libs)
assert(clears == 2 and #updates == 0 and session.presented == nil, "Silent Aim must clear when aligned is missing")

session.aligned = aligned
session.cameraOrigin = nil
SilentAim.update(session, presentation, libs)
assert(clears == 3 and #updates == 0 and session.presented == nil, "Silent Aim must clear when the camera origin is unknown")

session.cameraOrigin = origin
SilentAim.update(session, presentation, libs)
assert(
    #updates == 1
        and updates[1].target == aligned
        and updates[1].rotation == Targeting.rotationToward(origin, aligned.position)
        and session.presented == presented,
    "Silent Aim must present the aligned target without selecting another"
)

local ricochetDirection = Vector3.new(0, 0, -1)
session.aligned = {
    position = aligned.position,
    ricochet = { direction = ricochetDirection },
}
SilentAim.update(session, presentation, libs)
local ricochetPoint = origin + ricochetDirection * ProjectileAim.MAX_DISTANCE
assert(
    #updates == 2
        and updates[2].target == session.aligned
        and updates[2].rotation == Targeting.rotationToward(origin, ricochetPoint),
    "Silent Aim must aim along a solved projectile direction"
)

print("rivals-silent-aim-contracts-ok")
