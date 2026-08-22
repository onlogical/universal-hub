local DynamicStyle = {}

local DEFLECT_WINDOW = 8

function DynamicStyle.new()
    return {
        mode = "offensive",
        deflectTimes = {},
        defensiveUntil = -math.huge,
        probeUntil = nil,
    }
end

local function copy(state)
    local nextState = {
        mode = state.mode,
        deflectTimes = {},
        defensiveUntil = state.defensiveUntil,
        probeUntil = state.probeUntil,
    }
    for _, time in ipairs(state.deflectTimes or {}) do
        table.insert(nextState.deflectTimes, time)
    end
    return nextState
end

function DynamicStyle.reset()
    return DynamicStyle.new()
end

function DynamicStyle.recordDeflect(state, now, isDynamic, lastAttackAt)
    local nextState = copy(state)
    if not isDynamic or now - lastAttackAt > 1.2 then
        return nextState
    end
    table.insert(nextState.deflectTimes, now)
    while nextState.deflectTimes[1]
        and now - nextState.deflectTimes[1] > DEFLECT_WINDOW
    do
        table.remove(nextState.deflectTimes, 1)
    end
    if #nextState.deflectTimes >= 3 or nextState.mode == "probing" then
        nextState.mode = "defensive"
        nextState.probeUntil = nil
        nextState.defensiveUntil = now + math.min(2.5 + #nextState.deflectTimes * 0.5, 5)
    end
    return nextState
end

function DynamicStyle.update(state, now, viablePunish)
    local nextState = copy(state)
    if nextState.mode == "probing" and nextState.probeUntil then
        if now >= nextState.probeUntil then
            return DynamicStyle.new(), "resume"
        end
        return nextState, "hold"
    end
    if nextState.mode == "defensive" then
        if now < nextState.defensiveUntil and not viablePunish then
            return nextState, "hold"
        end
        nextState.mode = "probing"
        nextState.probeUntil = nil
        return nextState, "probe"
    end
    return nextState, "attack"
end

function DynamicStyle.recordProbeAttack(state, attackAt)
    local nextState = copy(state)
    if nextState.mode == "probing" then
        nextState.probeUntil = attackAt + 1.25
    end
    return nextState
end

function DynamicStyle.preferences(state)
    local defensive = state and state.mode == "defensive"
    return {
        allowOffense = not defensive,
        counterAllowed = not defensive,
        movement = {
            orbitDistanceScale = defensive and 1.2 or 1,
        },
    }
end

return DynamicStyle
