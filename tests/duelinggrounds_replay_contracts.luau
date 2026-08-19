local Replay = require("../games/duelinggrounds/recording/Replay")

local replay = Replay.build({
    metadata = { id = 4, target = "Opponent", duration = 3 },
    events = {
        { kind = "animation", side = "self", name = "Light01", attack = "Light01", t = 0.1 },
        { kind = "animation", side = "self", name = "Heavy01", attack = "Heavy01", t = 1 },
        {
            kind = "decision",
            decisionKind = "defenseExecuted",
            winner = "parry",
            attack = "Light02",
            reason = "parryable impact",
            t = 1.5,
        },
    },
    samples = {
        { t = 0, selfHealth = 100, targetHealth = 100, distance = 5 },
        { t = 0.35, selfHealth = 100, targetHealth = 75, distance = 5 },
        { t = 1.2, selfHealth = 100, targetHealth = 75, targetDodging = true, distance = 6 },
        { t = 2, selfHealth = 100, targetHealth = 75, critical = true, distance = 4 },
        { t = 2.2, selfHealth = 100, targetHealth = 75, punishWindow = 0.2, distance = 4 },
        { t = 2.4, selfHealth = 100, targetHealth = 75, distance = 4 },
    },
})

assert(replay.id == 4 and replay.target == "Opponent")
assert(replay.counts.hit == 1, "Health loss must create a hit timeline entry")
assert(replay.counts.dodge == 1, "An attack into dodge frames must explain the miss as a dodge")
assert(replay.counts.parry == 1, "Executed parries must appear in the timeline")
assert(replay.counts.missedPunish == 1, "Unused critical windows must be marked as missed punishes")

print("duelinggrounds-replay-contracts-ok")
