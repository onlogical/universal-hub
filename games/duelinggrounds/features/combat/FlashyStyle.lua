local FlashyStyle = {}

function FlashyStyle.preferences(state)
    state = state or {}
    local health = state.health or math.huge
    local maximumHealth = math.max(state.maximumHealth or health, 1)
    local posture = state.posture or math.huge
    local maximumPosture = math.max(state.maximumPosture or posture, 1)
    local pressured = health / maximumHealth < 0.35
        or posture / maximumPosture < 0.3
        or state.defenseReady == false

    return {
        allowOffense = true,
        aggressiveCombos = true,
        counterAllowed = not pressured,
        proactiveDashCounter = not pressured,
        punishOnly = true,
        suppressTraversalDodge = true,
        movement = {
            orbitInterval = pressured and 1.1 or 0.65,
            orbitDistanceScale = pressured and 1.2 or 0.9,
        },
    }
end

return FlashyStyle
