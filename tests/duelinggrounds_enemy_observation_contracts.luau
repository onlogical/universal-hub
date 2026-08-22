local EnemyPolicy = require("../games/duelinggrounds/features/combat/EnemyPolicy")

local localPlayer = {
    character = {
        teamGroup = "Blue",
    },
}
local lockedWithoutTeam = {
    character = {},
    id = "locked",
}
local oppositeTeam = {
    character = {
        teamGroup = "Red",
    },
    id = "opposite",
}
local sameTeam = {
    character = {
        teamGroup = "Blue",
    },
    id = "same",
}
local deadOpponent = {
    character = {
        isDead = true,
        teamGroup = "Red",
    },
    id = "dead",
}

assert(
    EnemyPolicy.isEnemy(localPlayer, lockedWithoutTeam, lockedWithoutTeam),
    "The locked target must be observed even when it has no TeamGroup"
)
assert(
    EnemyPolicy.isEnemy(localPlayer, oppositeTeam, lockedWithoutTeam),
    "Opposite-TeamGroup players must be observed in addition to the locked target"
)
assert(
    not EnemyPolicy.isEnemy(localPlayer, sameTeam, lockedWithoutTeam),
    "Players in the local TeamGroup must not be observed as enemies"
)
assert(
    not EnemyPolicy.isEnemy(localPlayer, deadOpponent, lockedWithoutTeam),
    "Dead players must not be observed as enemies"
)

local enemies = EnemyPolicy.filter(localPlayer, {
    sameTeam,
    oppositeTeam,
    lockedWithoutTeam,
    deadOpponent,
}, lockedWithoutTeam)
assert(
    #enemies == 2
        and enemies[1] == oppositeTeam
        and enemies[2] == lockedWithoutTeam,
    "Enemy filtering must retain the locked target plus additional opponents, in player order"
)

local lockedCharacter = {
    teamGroup = nil,
}
local lockedPlayer = {
    character = lockedCharacter,
}
assert(
    EnemyPolicy.isEnemy(localPlayer, lockedPlayer, lockedCharacter),
    "Enemy filtering must accept a locked character as well as its player wrapper"
)

print("duelinggrounds-enemy-observation-contracts-ok")
