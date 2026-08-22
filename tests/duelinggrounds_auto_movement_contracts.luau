local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local AutoMovement = require("../games/duelinggrounds/features/AutoMovement")
local profile = {
    approachDistance = 7.25,
    orbitDistance = 5.25,
    retreatDistance = 3.25,
}
local input = { MoveDirection = Vector3.zero }
local target = {}
local frame = {
    input = input,
    target = target,
    localPosition = Vector3.zero,
    targetPosition = Vector3.new(10, 0, 0),
    profile = profile,
    now = 0,
    orbitInterval = 2,
}
local movement = AutoMovement.new()

movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
assert(movement.mode == "approach" and input.MoveDirection.X > 0.99, "distant targets must be approached")

frame.targetPosition = Vector3.new(5.25, 0, 0)
movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
assert(movement.mode == "orbit" and math.abs(input.MoveDirection.Z) > 0.9, "approach must settle into a target-relative orbit")

frame.target = {}
frame.targetPosition = Vector3.new(2, 0, 0)
movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
assert(movement.mode == "retreat" and input.MoveDirection.X < -0.99, "close targets must be retreated from")

frame.target = {}
frame.targetPosition = Vector3.new(10, 0, 0)
frame.isObstacle = function()
    return true
end
movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
assert(movement.mode == "orbit" and input.MoveDirection.Z < -0.99, "obstacles must reverse and steer laterally")

frame.isObstacle = nil
frame.now = 1
frame.localPosition = Vector3.zero
movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
assert(movement.orbitDirection == 1, "stuck movement must reverse orbit direction")

movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = false })
assert(input.MoveDirection == Vector3.zero, "combat disposition must suspend owned movement")
input.MoveDirection = Vector3.new(0, 0, 1)
movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = false })
assert(input.MoveDirection == Vector3.new(0, 0, 1), "combat suspension must not seize movement owned by another system")

movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
input.MoveDirection = Vector3.new(0, 0, 1)
movement:update({ autoMovement = false }, frame, { canMove = true })
assert(input.MoveDirection == Vector3.new(0, 0, 1), "disable must not clear movement overwritten by another owner")

movement:update({ autoMovement = true, autoFight = true }, frame, { canMove = true })
movement:stop()
assert(input.MoveDirection == Vector3.zero, "stop must clear movement still owned by the feature")

local source = require("@lune/fs").readFile("games/duelinggrounds/features/AutoMovement.lua")
assert(not source:find("Dodge", 1, true), "movement must not duplicate dodge or approach-dash cooldown ownership")

print("duelinggrounds-auto-movement-contracts-ok")
