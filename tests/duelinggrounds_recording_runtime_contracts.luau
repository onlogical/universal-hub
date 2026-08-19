local Runtime = require("../games/duelinggrounds/recording/Runtime")

local now = 10
local wall = 1000
local saved = {}
local environment = {}
local runtime = Runtime.new({
    environment = environment,
    clock = function()
        return now
    end,
    wallClock = function()
        return wall
    end,
    sample = function(frame, settings, elapsed)
        return {
            t = elapsed,
            target = frame.targetModel.Name,
            style = settings.combatStyle,
        }
    end,
    persistence = {
        save = function(_, version, match)
            table.insert(saved, { version = version, match = match })
        end,
    },
})

assert(environment.__DuelingGroundsCombatTelemetry == runtime.telemetry)
assert(runtime.telemetry.version == 1)

local targetA = { Name = "Alpha" }
local targetB = { Name = "Beta" }
local settings = { autoFight = true, autoMovement = true, combatStyle = "dynamic" }
runtime:update({ targetModel = targetA, metadata = { target = targetA.Name } }, settings)
assert(runtime.telemetry.current.samples[1].t == 0, "The first pre-action frame must sample")
assert(runtime.telemetry.current.events[1].kind == "matchStarted")

now = 10.02
runtime:update({ targetModel = targetA }, settings)
assert(#runtime.telemetry.current.samples == 1, "Sampling must be capped at 20 Hz")
now = 10.05
runtime:update({ targetModel = targetA }, settings)
assert(#runtime.telemetry.current.samples == 2)

now = 10.08
local flashySettings = { autoFight = true, autoMovement = true, combatStyle = "flashy" }
runtime:update({ targetModel = targetA }, flashySettings)
local styleEvent = runtime.telemetry.current.events[2]
assert(styleEvent.kind == "styleChanged")
assert(styleEvent.from == "dynamic" and styleEvent.to == "flashy")
settings = flashySettings

now = 10.1
runtime:recordEvent("defenseSelected", { t = 999, winner = "parry" }, true)
local globalEvent = runtime.telemetry.events[1]
local matchEvent = runtime.telemetry.current.events[3]
assert(globalEvent.t == now, "Global compatibility events retain absolute clock timestamps")
assert(matchEvent.kind == "decision" and math.abs(matchEvent.t - 0.1) < 0.000001)
assert(matchEvent.winner == "parry")

now = 11
runtime:update({ targetModel = targetB, metadata = { target = targetB.Name } }, settings)
assert(saved[1].match.metadata.endReason == "targetChanged")
assert(runtime.telemetry.current.metadata.target == targetB.Name)
assert(runtime.telemetry.current.samples[1].t == 0)

now = 12
runtime:update({ targetModel = targetB, targetDead = true }, settings)
assert(saved[2].match.metadata.endReason == "targetDead")

runtime:update({ targetModel = targetA, metadata = { target = targetA.Name } }, settings)
now = 13
runtime:update({ targetModel = targetA, selfDead = true }, settings)
assert(saved[3].match.metadata.endReason == "selfDead")

runtime:update({ targetModel = targetA, metadata = { target = targetA.Name } }, settings)
now = 14
runtime:update({ targetModel = targetA }, { autoFight = false })
assert(saved[4].match.metadata.endReason == "autoFightOff")

runtime:update({ targetModel = targetA, metadata = { target = targetA.Name } }, settings)
now = 15
runtime:stop()
assert(saved[5].match.metadata.endReason == "sessionStopped")
assert(runtime.telemetry.current == nil)

local retained = { version = 1, events = {}, matches = {}, nextMatchId = 7 }
local compatibleEnvironment = { __DuelingGroundsCombatTelemetry = retained }
local compatible = Runtime.new({ environment = compatibleEnvironment })
assert(compatible.telemetry == retained and compatible.telemetry.nextMatchId == 7)

print("duelinggrounds-recording-runtime-contracts-ok")
