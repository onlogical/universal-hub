local UltimatePolicy = {}

function UltimatePolicy.shouldUseNeutral(state)
    state = state or {}
    if state.targetDodging or state.targetParrying then
        return false, "targetInvulnerable"
    end
    if
        state.targetHealth
        and state.ultimateDamage
        and state.ultimateDamage >= state.targetHealth
    then
        return true, "lethal"
    end
    if
        (state.punishWindow or 0)
        >= (state.impactTime or math.huge) + (state.networkMargin or 0)
    then
        return true, "confirmedPunish"
    end
    return false, "reserveForCritical"
end

return UltimatePolicy
