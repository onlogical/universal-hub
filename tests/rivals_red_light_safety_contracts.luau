local RedLightSafety = require("../games/rivals/features/RedLightSafety")

local red
local green
local hooked = {}
local restored = {}
local chickenGame = {
    RedLight = function() end,
    GreenLight = function() end,
}
local releases = 0
local stops = 0
local sinks = {}
local safety = RedLightSafety.new({
    chickenGame = chickenGame,
    hookFunction = function(target, replacement)
        hooked[target] = replacement
        return target
    end,
    restoreFunction = function(target)
        restored[target] = true
    end,
    releaseAll = function()
        releases += 1
    end,
    stopMovement = function()
        stops += 1
    end,
    setInputSink = function(enabled)
        table.insert(sinks, enabled)
    end,
})

red = hooked[chickenGame.RedLight]
green = hooked[chickenGame.GreenLight]
assert(type(red) == "function" and type(green) == "function")
assert(safety:isPaused() == false)

red()
assert(safety:isPaused() == true)
assert(releases == 1 and stops == 1 and sinks[1] == true)
safety:holdStill()
assert(stops == 2)

green()
assert(safety:isPaused() == false)
assert(sinks[2] == false)
assert(releases == 1, "green must not replay or synthesize held input")

safety:stop()
assert(restored[chickenGame.RedLight] and restored[chickenGame.GreenLight])
assert(sinks[#sinks] == false)

print("rivals-red-light-safety-contracts-ok")
