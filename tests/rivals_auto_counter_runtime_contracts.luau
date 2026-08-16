local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local AutoCounterRuntime = require("../games/rivals/features/AutoCounterRuntime")

local epoch = {}
local function sample(runtime, now, position, overrides)
    overrides = overrides or {}
    return runtime:update({
        alive = overrides.alive ~= false,
        enabled = overrides.enabled ~= false,
        epoch = overrides.epoch or epoch,
        humanoidState = overrides.humanoidState or "Running",
        now = now,
        position = position,
        roundEligible = overrides.roundEligible ~= false,
    })
end

local origin = Vector3.new(10, 4000, -20)
local function confirmedRuntime()
    local runtime = AutoCounterRuntime.new()
    sample(runtime, 0, origin)
    assert(sample(runtime, 0.1, origin + Vector3.new(0, 1000, 0)).state == "outbound")
    sample(runtime, 0.2, origin + Vector3.new(0, 1000, 0), { humanoidState = "Freefall" })
    assert(sample(runtime, 0.3, origin).state == "confirmed")
    assert(sample(runtime, 0.4, origin).stableSamples == 1)
    assert(sample(runtime, 0.5, origin).stableSamples == 2)
    assert(sample(runtime, 0.6, origin).state == "ready")
    return runtime
end

local confirmed = confirmedRuntime()
assert(confirmed:isReady(), "The bracketed 1000-stud trace must confirm after three stable samples")
assert(confirmed:consume(0.6, 0.13), "A ready signature must permit one action")
assert(not confirmed:consume(0.6, 0.13), "A consumed signature must never permit a second action")
assert(confirmed:status().state == "cooldown")

local observer = AutoCounterRuntime.new()
sample(observer, 0, origin)
for index = 1, 12 do
    sample(observer, index * 0.1, origin + Vector3.new(0, index * 0.0004, 0))
end
assert(not observer:isReady(), "Observer-side sub-stud motion must never confirm")

local outboundOnly = AutoCounterRuntime.new()
sample(outboundOnly, 0, origin)
sample(outboundOnly, 0.1, origin + Vector3.new(0, 1000, 0))
for index = 2, 18 do
    sample(outboundOnly, index * 0.1, origin + Vector3.new(0, 1000, 0), {
        humanoidState = "Freefall",
    })
end
assert(not outboundOnly:isReady(), "An outward transition without a return must expire")

local nativeMovement = AutoCounterRuntime.new()
sample(nativeMovement, 0, origin)
for index = 1, 20 do
    local jump = math.sin(index / 20 * math.pi) * 4.7
    sample(nativeMovement, index * 0.05, origin + Vector3.new(index * 1.5, jump, 0))
end
assert(not nativeMovement:isReady(), "Native jump and slide-sized movement must remain clean")

local wrongRound = AutoCounterRuntime.new()
sample(wrongRound, 0, origin)
sample(wrongRound, 0.1, origin + Vector3.new(0, 1000, 0))
sample(wrongRound, 0.2, origin, { roundEligible = false })
for index = 3, 8 do
    sample(wrongRound, index * 0.1, origin)
end
assert(not wrongRound:isReady(), "Round loss between transitions must clear the signature")

local wrongState = AutoCounterRuntime.new()
sample(wrongState, 0, origin)
sample(wrongState, 0.1, origin + Vector3.new(0, 1000, 0))
sample(wrongState, 0.2, origin)
for index = 3, 6 do
    sample(wrongState, index * 0.1, origin, { humanoidState = "Freefall" })
end
assert(not wrongState:isReady(), "Non-running return samples must not satisfy stabilization")

local disabled = confirmedRuntime()
sample(disabled, 0.7, origin, { enabled = false })
assert(not disabled:isReady() and disabled:status().lastReason == "disabled")

local expired = confirmedRuntime()
sample(expired, 0.75, origin)
sample(expired, 0.9, origin)
sample(expired, 1.05, origin)
sample(expired, 1.06, origin)
assert(
    not expired:isReady() and expired:status().lastReason == "action-timeout",
    "A confirmed signature must expire without a delayed action"
)

local changedEpoch = AutoCounterRuntime.new()
sample(changedEpoch, 0, origin)
sample(changedEpoch, 0.1, origin + Vector3.new(0, 1000, 0))
sample(changedEpoch, 0.2, origin, { epoch = {} })
for index = 3, 6 do
    sample(changedEpoch, index * 0.1, origin, { epoch = {} })
end
assert(not changedEpoch:isReady(), "A character epoch change must clear outbound evidence")

print("rivals-auto-counter-runtime-contracts-ok")
