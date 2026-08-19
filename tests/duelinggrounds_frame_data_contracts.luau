local FrameData = require("../games/duelinggrounds/features/combat/FrameData")

local attack = {
    impacts = {
        { markerTime = 0.3 },
        { markerTime = 0.6 },
    },
    timeMarkers = { canCancel = 0.9 },
}
local startup = FrameData.describe({ TimePosition = 0.1, Speed = 1, Length = 1 }, attack, "Light01")
assert(startup.attack == "Light01" and startup.phase == "startup")
assert(math.abs(startup.startup - 0.2) < 0.0001)
assert(math.abs(startup.recovery - 0.8) < 0.0001)
assert(math.abs(startup.comboGap - 0.3) < 0.0001)

local combo = FrameData.describe({ TimePosition = 0.45, Speed = 1, Length = 1 }, attack, "Light01")
assert(combo.phase == "combo" and math.abs(combo.nextImpact - 0.15) < 0.0001)

local recovery = FrameData.describe({ TimePosition = 0.7, Speed = 1, Length = 1 }, attack, "Light01")
assert(recovery.phase == "recovery")
assert(math.abs(recovery.punish - 0.2) < 0.0001)

local faster = FrameData.describe({ TimePosition = 0.1, Speed = 2, Length = 1 }, attack, "Light01")
assert(math.abs(faster.startup - 0.1) < 0.0001, "Playback speed must scale frame times")

print("duelinggrounds-frame-data-contracts-ok")
