local fs = require("@lune/fs")

local source = fs.readFile("games/DuelingGrounds.lua")
local observer = assert(source:find("local function observeThreatTrack", 1, true))
local incoming = assert(source:find("local function getTrackRemaining", observer, true))
local observerSource = source:sub(observer, incoming - 1)

assert(
    observerSource:find("track.Looped", 1, true),
    "Looping weapon-ready and draw stances must not become attack threats"
)
assert(
    not observerSource:find("_clearQueuedAction", 1, true)
        and not observerSource:find("SwitchToAction", 1, true),
    "Observing an animation must not interrupt offense before reach and timing are confirmed"
)
assert(
    source:find("queueDefenseIntent", incoming, true),
    "Confirmed reachable impacts must still route through the defense planner"
)

print("duelinggrounds-threat-gating-contracts-ok")
