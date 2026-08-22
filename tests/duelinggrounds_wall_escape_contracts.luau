local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local WallEscape = require("../games/duelinggrounds/features/combat/WallEscape")

local toward = Vector3.new(1, 0, 0)
local direction, side = WallEscape.choose(toward, function(candidate)
    if candidate.Z > 0 then
        return { Distance = 1 }
    end
    return { Distance = 5 }
end, 6, 1)
assert(side == -1 and direction.Z < -0.99, "Baby must escape toward the clearer side")

direction, side = WallEscape.choose(toward, function()
    return nil
end, 6, -1)
assert(side == -1 and direction.Z < -0.99, "Equal clearance must preserve the chosen side")

direction, side = WallEscape.choose(toward, function(candidate)
    if candidate.Z > 0 then
        return nil
    end
    return { Distance = 2 }
end, 6, -1)
assert(side == 1 and direction.Z > 0.99, "An open side must beat a partially blocked side")

print("duelinggrounds-wall-escape-contracts-ok")
