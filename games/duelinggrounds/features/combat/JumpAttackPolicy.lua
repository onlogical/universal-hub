local JumpAttackPolicy = {}

function JumpAttackPolicy.shouldJump(state)
    state = state or {}
    if
        not state.available
        or not state.jumpReady
        or not state.cooldownReady
        or not state.canQueue
    then
        return false
    end
    local postureBreak = state.targetBlocking
        and state.postureDamage > 0
        and type(state.targetPosture) == "number"
        and state.targetPosture <= state.postureDamage
    local staggerPunish = state.targetStaggered
        and state.healthDamage > 0
        and state.healthDamage >= state.heavyHealthDamage
        and state.staggerRemaining >= 0.9
    return (postureBreak or staggerPunish) and (state.inRange or state.canLunge),
        postureBreak and "postureBreak" or "staggerPunish"
end

return JumpAttackPolicy
