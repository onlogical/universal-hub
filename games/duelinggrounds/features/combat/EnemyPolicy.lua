local EnemyPolicy = {}

local function isValidCharacter(character)
    return character ~= nil and character.isDead ~= true
end

function EnemyPolicy.isEnemy(localPlayer, candidate, lockedTarget)
    if candidate == nil
        or candidate == localPlayer
        or not isValidCharacter(candidate.character)
    then
        return false
    end
    if candidate == lockedTarget or candidate.character == lockedTarget then
        return true
    end

    local localCharacter = localPlayer and localPlayer.character
    local localTeamGroup = localCharacter and localCharacter.teamGroup
    local candidateTeamGroup = candidate.character.teamGroup
    return localTeamGroup ~= nil
        and candidateTeamGroup ~= nil
        and candidateTeamGroup ~= localTeamGroup
end

function EnemyPolicy.filter(localPlayer, candidates, lockedTarget)
    local enemies = {}
    for _, candidate in ipairs(candidates or {}) do
        if EnemyPolicy.isEnemy(localPlayer, candidate, lockedTarget) then
            table.insert(enemies, candidate)
        end
    end
    return enemies
end

return EnemyPolicy
