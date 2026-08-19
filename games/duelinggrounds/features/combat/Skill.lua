local Skill = {}

local function clampLevel(level)
    return math.clamp(type(level) == "number" and level or 85, 0, 100)
end

function Skill.profile(level)
    local normalized = clampLevel(level) / 100
    return {
        level = clampLevel(level),
        reactionDelay = 0.02 + (1 - normalized) * 0.28,
        reactionJitter = (1 - normalized) * 0.12,
        defenseAccuracy = 0.55 + normalized * 0.45,
        punishAccuracy = 0.45 + normalized * 0.55,
        movementPrecision = 0.5 + normalized * 0.5,
    }
end

function Skill.shouldAct(profile, random)
    return random:NextNumber() <= profile.defenseAccuracy
end

function Skill.reactionDelay(profile, random)
    return profile.reactionDelay
        + random:NextNumber(-profile.reactionJitter, profile.reactionJitter)
end

function Skill.shouldPunish(profile, random)
    return random:NextNumber() <= profile.punishAccuracy
end

return Skill
