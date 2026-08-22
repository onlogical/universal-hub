local EnemyPolicy = {}

local function isValidCharacter(character)
    if character == nil then
        return false
    end
    local isDead = character.isDead
    if type(character.GetAttribute) == "function" then
        isDead = character:GetAttribute("IsDead")
    end
    return isDead ~= true
end

local function teamGroup(character)
    if type(character.GetAttribute) == "function" then
        return character:GetAttribute("TeamGroup")
    end
    return character.teamGroup
end

function EnemyPolicy.isEnemy(localPlayer, candidate, lockedTarget)
    if
        candidate == nil
        or candidate == localPlayer
        or candidate.player ~= nil and candidate.player == localPlayer.player
        or not isValidCharacter(candidate.character)
    then
        return false
    end
    if candidate == lockedTarget or candidate.character == lockedTarget then
        return true
    end

    local localCharacter = localPlayer and localPlayer.character
    local localTeamGroup = localCharacter and teamGroup(localCharacter)
    local candidateTeamGroup = teamGroup(candidate.character)
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
