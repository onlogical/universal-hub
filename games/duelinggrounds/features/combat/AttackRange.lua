local AttackRange = {}

local VALID_MODES = {
    close = true,
    medium = true,
    far = true,
}

function AttackRange.normalize(mode)
    return VALID_MODES[mode] and mode or "medium"
end

function AttackRange.choose(random, defenseReady)
    if defenseReady == false then
        return "far"
    end
    local roll = random:NextNumber()
    if roll < 0.15 then
        return "close"
    end
    if roll < 0.6 then
        return "medium"
    end
    return "far"
end

function AttackRange.apply(profile, mode, geometricReach)
    mode = AttackRange.normalize(mode)
    local maximumRange = profile.maximumNeutralAttackDistance
    if type(geometricReach) == "number" and geometricReach > 0 then
        maximumRange = maximumRange and math.min(maximumRange, geometricReach)
            or geometricReach
    end
    maximumRange = maximumRange or profile.approachDistance
    maximumRange = math.max(maximumRange, 1.5)

    local attackDistance
    if mode == "close" then
        attackDistance = maximumRange * 0.52
    elseif mode == "far" then
        attackDistance = maximumRange
    else
        attackDistance = maximumRange * 0.76
    end
    attackDistance = math.clamp(attackDistance, 1.5, maximumRange)

    local ranged = {}
    for key, value in pairs(profile) do
        ranged[key] = value
    end
    ranged.rangeMode = mode
    ranged.maximumNeutralAttackDistance = attackDistance
    ranged.approachDistance = attackDistance
    ranged.orbitDistance = math.max(attackDistance - 0.25, 1.25)
    ranged.retreatDistance = math.max(ranged.orbitDistance - 0.75, 0.75)
    return ranged
end

return AttackRange
