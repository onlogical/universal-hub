local Combos = {}

local COMBOS = {
    BoStaff = { finisherAfter = 2 },
    CurvedBlades = { finisherAfter = 2 },
    Daggers = { finisherAfter = 1 },
    Gauntlets = { finisherAfter = 2 },
    Katana = { finisherAfter = 3 },
    Kusarigama = { finisherAfter = 2 },
    Naginata = { finisherAfter = 2 },
    ["War Hammer"] = { finisherAfter = 1 },
}

function Combos.profile(weaponName)
    return COMBOS[weaponName] or { finisherAfter = 2 }
end

function Combos.nextAttack(state)
    state = state or {}
    local lightCount = state.lightCount or 0
    local profile = Combos.profile(state.weaponName)
    local finisherAfter = profile.finisherAfter
    local canHeavy = state.hasHeavy == true
    local flashy = state.style == "flashy"

    if state.recentDeflects and state.recentDeflects >= 2 then
        return nil, "disengageAfterDeflects"
    end
    if state.targetBlocking and canHeavy then
        return "Heavy", "guardPressure"
    end
    if canHeavy and lightCount >= finisherAfter then
        return "Heavy", "comboFinisher"
    end
    if flashy and state.canDashHeavy and state.afterDodge then
        return "Heavy", "dodgeHeavyVariation"
    end
    return "Light", lightCount == 0 and "comboStarter" or "comboContinue"
end

return Combos
