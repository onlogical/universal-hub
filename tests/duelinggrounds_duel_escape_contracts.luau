local DuelEscape = require("../games/duelinggrounds/features/DuelEscape")

local function input(key)
    return { KeyCode = key }
end

local function mouseInput(inputType)
    return { KeyCode = "Unknown", UserInputType = inputType }
end

assert(DuelEscape.shouldTrigger(input("End"), false, {}, true, 10, 0))
assert(not DuelEscape.shouldTrigger(input("End"), true, {}, true, 10, 0))
assert(not DuelEscape.shouldTrigger(input("End"), false, {}, false, 10, 0))
assert(not DuelEscape.shouldTrigger(input("Q"), false, { duelEscapeKey = "End" }, true, 10, 0))
assert(DuelEscape.shouldTrigger(input("Q"), false, { duelEscapeKey = "Q" }, true, 10, 0))
assert(DuelEscape.shouldTrigger(mouseInput("MouseButton3"), false, { duelEscapeKey = "MouseButton3" }, true, 10, 0))
assert(not DuelEscape.shouldTrigger(input("End"), false, {}, true, 1, 0))
assert(DuelEscape.shouldTrigger(input("End"), false, {}, true, 1.5, 0))

local fs = require("@lune/fs")
local adapterSource = fs.readFile("games/DuelingGrounds.lua")
local escapeSource = fs.readFile("games/duelinggrounds/features/DuelEscape.lua")
assert(
    adapterSource:find("characterController:GetLocalCharacterHandler()", 1, true),
    "Duel Escape must resolve the live workspace character handler"
)
assert(escapeSource:find("ESCAPE_HEIGHT = 50", 1, true))
assert(escapeSource:find("root.CFrame + Vector3.new(0, ESCAPE_HEIGHT, 0)", 1, true))
assert(escapeSource:find('RunService").Heartbeat', 1, true))
assert(not escapeSource:find('FindFirstChild("LobbySpawner")', 1, true))

print("duelinggrounds-duel-escape-contracts-ok")
