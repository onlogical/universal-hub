local EnemyPolicy = require("../games/duelinggrounds/features/combat/EnemyPolicy")

local localPlayer = { character = {} }
local lockedNoTeam = { character = {} }
assert(EnemyPolicy.isEnemy(localPlayer, lockedNoTeam, lockedNoTeam))
assert(EnemyPolicy.isEnemy(localPlayer, lockedNoTeam, lockedNoTeam.character))

localPlayer.character.teamGroup = "blue"
local enemy = { character = { teamGroup = "red" } }
local ally = { character = { teamGroup = "blue" } }
local unassigned = { character = {} }
assert(EnemyPolicy.isEnemy(localPlayer, enemy))
assert(not EnemyPolicy.isEnemy(localPlayer, ally))
assert(not EnemyPolicy.isEnemy(localPlayer, unassigned))
assert(not EnemyPolicy.isEnemy(localPlayer, localPlayer))
assert(not EnemyPolicy.isEnemy(localPlayer, { character = { teamGroup = "red", isDead = true } }))
assert(not EnemyPolicy.isEnemy(localPlayer, { character = nil }))

localPlayer.character.teamGroup = nil
assert(not EnemyPolicy.isEnemy(localPlayer, enemy))
assert(EnemyPolicy.isEnemy(localPlayer, lockedNoTeam, lockedNoTeam))

local filtered = EnemyPolicy.filter(localPlayer, { enemy, lockedNoTeam }, lockedNoTeam)
assert(#filtered == 1 and filtered[1] == lockedNoTeam)

print("duelinggrounds-enemy-policy-contracts-ok")
