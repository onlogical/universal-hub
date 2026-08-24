local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local AutoCounterTestSimulator = require("../games/rivals/features/AutoCounterTestSimulator")

local now = 0
local root = { CFrame = CFrame.new(0, 10, 0) }
local simulator = AutoCounterTestSimulator.new({
    clock = function()
        return now
    end,
    configuration = {
        enabled = true,
        holdDuration = 0.45,
        startDelay = 0,
        verticalOffset = 1000,
    },
    getRoot = function()
        return root
    end,
})
simulator:update(true, true)
simulator:update(true, true)
assert(simulator:update(true, true) == "armed")
assert(simulator:update(true, true) == "outbound")
assert(
    root.CFrame.Position.Y == 1010,
    "The private test simulator must reproduce the local 1000-stud transition"
)
now = 0.46
assert(simulator:update(true, true) == "complete")
assert(
    root.CFrame.Position.Y == 10,
    "The private test simulator must restore the exact saved frame"
)
assert(simulator:status().spent == true, "The private test simulator must be one-shot")
simulator:update(true, true)
assert(root.CFrame.Position.Y == 10, "A spent simulator must never replay")

local disabledRoot = { CFrame = CFrame.new(0, 20, 0) }
local disabled = AutoCounterTestSimulator.new({
    clock = function()
        return now
    end,
    configuration = { enabled = true, startDelay = 0 },
    getRoot = function()
        return disabledRoot
    end,
})
disabled:update(true, true)
disabled:update(true, true)
disabled:update(true, true)
disabled:update(true, true)
assert(disabledRoot.CFrame.Position.Y == 1020)
disabled:update(false, false)
assert(
    disabledRoot.CFrame.Position.Y == 20,
    "Toggle-off must restore an outbound simulator immediately"
)

local inertRoot = { CFrame = CFrame.new(0, 30, 0) }
local inert = AutoCounterTestSimulator.new({
    clock = function()
        return now
    end,
    configuration = { enabled = false, startDelay = 0 },
    getRoot = function()
        return inertRoot
    end,
})
for _ = 1, 10 do
    inert:update(true, true)
end
assert(inertRoot.CFrame.Position.Y == 30, "Missing test injection must make the simulator inert")

print("rivals-auto-counter-test-simulator-contracts-ok")
