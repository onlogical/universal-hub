local DynamicStyle = require("../games/duelinggrounds/features/combat/DynamicStyle")

local initial = DynamicStyle.new()
local ignored = DynamicStyle.recordDeflect(initial, 2, false, 1)
assert(initial.mode == "offensive" and #initial.deflectTimes == 0)
assert(ignored.mode == "offensive" and #ignored.deflectTimes == 0)

local state = DynamicStyle.recordDeflect(initial, 1, true, 0.5)
state = DynamicStyle.recordDeflect(state, 2, true, 1.5)
state = DynamicStyle.recordDeflect(state, 3, true, 2.5)
assert(state.mode == "defensive")
assert(state.defensiveUntil == 7)
assert(initial.mode == "offensive", "transitions must not mutate the source state")

local holding, action = DynamicStyle.update(state, 4, false)
assert(holding.mode == "defensive" and action == "hold")
local probing
probing, action = DynamicStyle.update(state, 4, true)
assert(probing.mode == "probing" and action == "probe")
local waiting = DynamicStyle.recordProbeAttack(probing, 4)
assert(waiting.probeUntil == 5.25)
local resumed
resumed, action = DynamicStyle.update(waiting, 5.25, false)
assert(resumed.mode == "offensive" and action == "resume")

print("duelinggrounds-dynamic-style-contracts-ok")
