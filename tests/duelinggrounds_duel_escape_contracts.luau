local DuelEscape = require("../games/duelinggrounds/features/DuelEscape")

local function input(key)
    return { KeyCode = key }
end

assert(DuelEscape.shouldTrigger(input("End"), false, {}, true, 10, 0))
assert(not DuelEscape.shouldTrigger(input("End"), true, {}, true, 10, 0))
assert(not DuelEscape.shouldTrigger(input("End"), false, {}, false, 10, 0))
assert(not DuelEscape.shouldTrigger(input("Q"), false, { duelEscapeKey = "End" }, true, 10, 0))
assert(DuelEscape.shouldTrigger(input("Q"), false, { duelEscapeKey = "Q" }, true, 10, 0))
assert(not DuelEscape.shouldTrigger(input("End"), false, {}, true, 1, 0))
assert(DuelEscape.shouldTrigger(input("End"), false, {}, true, 1.5, 0))

print("duelinggrounds-duel-escape-contracts-ok")
