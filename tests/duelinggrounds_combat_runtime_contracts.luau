local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local CombatRuntime = require("../games/duelinggrounds/features/CombatRuntime")

local disconnected = 0
local stopped = 0
local runtime = setmetatable({
    stopped = false,
    enemies = {
        stop = function()
            stopped += 1
        end,
    },
    defense = {
        stop = function()
            stopped += 1
        end,
    },
    offense = {
        stop = function()
            stopped += 1
        end,
    },
    localConnection = {
        Disconnect = function()
            disconnected += 1
        end,
    },
    activeThreats = { threat = true },
    targetState = { blockTracks = { track = true } },
    animationSets = { target = true },
    localDeflectAnimations = { animation = true },
    defenseIntent = {},
    localHandler = {},
    localWeapon = {},
}, CombatRuntime)

runtime:stop()
assert(stopped == 3)
assert(disconnected == 1)
assert(next(runtime.activeThreats) == nil)
assert(next(runtime.targetState.blockTracks) == nil)
assert(runtime.defenseIntent == nil)
runtime:stop()
assert(stopped == 3 and disconnected == 1, "CombatRuntime stop must be idempotent")

print("duelinggrounds-combat-runtime-contracts-ok")
