local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local TaskLocomotion = require("../games/rivals/tasks/TaskLocomotion")

local locomotion = TaskLocomotion.new()
local first = locomotion:plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(60, 0, 0),
    grounded = true,
    clear = true,
})
assert(first.intent == "push" and first.slide == true)

local retained = locomotion:plan({
    now = 0.2,
    position = Vector3.new(2, 0, 0),
    targetPosition = Vector3.new(60, 0, 0),
    grounded = true,
    clear = true,
})
assert(retained.strafeSign == first.strafeSign, "a progressing push must retain its route")

local replanned = locomotion:plan({
    now = 1,
    position = Vector3.new(2, 0, 0),
    targetPosition = Vector3.new(60, 0, 0),
    grounded = true,
    clear = false,
})
assert(replanned.strafeSign == -retained.strafeSign, "a stalled blocked push must replan")
assert(replanned.slide == false, "a blocked route must not slide")

print("rivals-task-locomotion-contracts-ok")
