local Replay = {}

local HIT_WINDOW = 1.35
local PUNISH_THRESHOLD = 0.12

local function isAttackName(name)
    name = tostring(name or "")
    return name == "Ultimate"
        or name == "DashLight"
        or name == "JumpAttack"
        or string.find(name, "Light", 1, true) ~= nil
        or string.find(name, "Heavy", 1, true) ~= nil
        or string.find(name, "Attack", 1, true) ~= nil
end

local function rounded(value)
    return math.floor((value or 0) * 10 + 0.5) / 10
end

local function add(entries, time, kind, title, detail)
    table.insert(entries, {
        t = math.max(time or 0, 0),
        kind = kind,
        title = title,
        detail = detail,
    })
end

local function findPriorAttack(attacks, side, time)
    for index = #attacks, 1, -1 do
        local attack = attacks[index]
        if attack.side == side and attack.t <= time then
            if time - attack.t <= HIT_WINDOW then
                return attack
            end
            return nil
        end
    end
    return nil
end

local function victimState(samples, side, startTime, endTime)
    local dodging = false
    local blocking = false
    local parrying = false
    for _, sample in ipairs(samples) do
        if sample.t >= startTime and sample.t <= endTime then
            if side == "self" then
                dodging = dodging or sample.selfDodging == true
                blocking = blocking or sample.selfBlocking == true
                parrying = parrying or sample.selfParrying == true
            else
                dodging = dodging or sample.targetDodging == true
                blocking = blocking or sample.targetBlocking == true
                parrying = parrying or sample.targetParrying == true
            end
        end
    end
    return dodging, blocking, parrying
end

function Replay.build(match)
    if type(match) ~= "table" then
        return nil
    end
    local samples = match.samples or {}
    local events = match.events or {}
    local entries = {}
    local attacks = {}
    local deflections = {}
    for _, event in ipairs(events) do
        if event.kind == "animation" then
            local name = tostring(event.attack or event.name or "Attack")
            if isAttackName(name) then
                table.insert(attacks, {
                    t = event.t or 0,
                    side = event.side or "target",
                    name = name,
                    matched = false,
                })
            end
            if string.find(string.lower(tostring(event.name or "")), "deflected", 1, true) then
                table.insert(deflections, event)
            end
        elseif event.kind == "decision" and event.decisionKind == "defenseExecuted" then
            local winner = tostring(event.winner or "defense")
            add(
                entries,
                event.t,
                winner,
                string.upper(winner),
                ("Reacted to %s%s"):format(
                    tostring(event.attack or "attack"),
                    event.reason and (" — " .. tostring(event.reason)) or ""
                )
            )
        end
    end
    table.sort(attacks, function(left, right)
        return left.t < right.t
    end)

    local previous = samples[1]
    for index = 2, #samples do
        local sample = samples[index]
        local selfHealthDamage = type(previous.selfHealth) == "number"
                and type(sample.selfHealth) == "number"
                and math.max(previous.selfHealth - sample.selfHealth, 0)
            or 0
        local targetHealthDamage = type(previous.targetHealth) == "number"
                and type(sample.targetHealth) == "number"
                and math.max(previous.targetHealth - sample.targetHealth, 0)
            or 0
        local selfPostureDamage = type(previous.selfPosture) == "number"
                and type(sample.selfPosture) == "number"
                and math.max(previous.selfPosture - sample.selfPosture, 0)
            or 0
        local targetPostureDamage = type(previous.targetPosture) == "number"
                and type(sample.targetPosture) == "number"
                and math.max(previous.targetPosture - sample.targetPosture, 0)
            or 0
        for _, outcome in ipairs({
            { side = "self", victim = "target", health = targetHealthDamage, posture = targetPostureDamage },
            { side = "target", victim = "self", health = selfHealthDamage, posture = selfPostureDamage },
        }) do
            if outcome.health > 0 or outcome.posture > 0 then
                local attack = findPriorAttack(attacks, outcome.side, sample.t)
                if attack then
                    attack.matched = true
                end
                local damage = outcome.health > 0 and (rounded(outcome.health) .. " HP")
                    or (rounded(outcome.posture) .. " posture")
                add(
                    entries,
                    sample.t,
                    "hit",
                    "HIT",
                    ("%s %s dealt %s at %.1f studs"):format(
                        outcome.side,
                        attack and attack.name or "attack",
                        damage,
                        rounded(sample.distance)
                    )
                )
            end
        end
        previous = sample
    end

    for _, attack in ipairs(attacks) do
        if not attack.matched then
            local victim = attack.side == "self" and "target" or "self"
            local wasParried = false
            for _, deflection in ipairs(deflections) do
                if deflection.side == attack.side
                    and deflection.t >= attack.t
                    and deflection.t - attack.t <= HIT_WINDOW
                then
                    wasParried = true
                    break
                end
            end
            local dodging, blocking, parrying = victimState(
                samples,
                victim,
                attack.t,
                attack.t + HIT_WINDOW
            )
            local reason = wasParried and "parried"
                or dodging and "dodged"
                or parrying and "parried"
                or blocking and "blocked"
                or "missed the hurtbox"
            add(
                entries,
                attack.t,
                wasParried and "parry" or dodging and "dodge" or "miss",
                wasParried and "PARRY" or dodging and "DODGE" or "MISS",
                ("%s %s was %s"):format(attack.side, attack.name, reason)
            )
        end
    end

    local openingStart
    local openingEnd
    local function closeOpening()
        if not openingStart then
            return
        end
        local attacked = false
        for _, attack in ipairs(attacks) do
            if attack.side == "self"
                and attack.t >= openingStart
                and attack.t <= openingEnd + 0.15
            then
                attacked = true
                break
            end
        end
        if not attacked then
            add(
                entries,
                openingStart,
                "missedPunish",
                "MISSED PUNISH",
                ("%.0fms opening expired without an attack"):format(
                    math.max(openingEnd - openingStart, 0) * 1000
                )
            )
        end
        openingStart = nil
        openingEnd = nil
    end
    for _, sample in ipairs(samples) do
        local open = sample.critical == true
            or (type(sample.punishWindow) == "number" and sample.punishWindow >= PUNISH_THRESHOLD)
        if open then
            openingStart = openingStart or sample.t
            openingEnd = sample.t
        elseif openingStart then
            closeOpening()
        end
    end
    closeOpening()

    table.sort(entries, function(left, right)
        if left.t == right.t then
            return left.kind < right.kind
        end
        return left.t < right.t
    end)
    local counts = {}
    for _, entry in ipairs(entries) do
        counts[entry.kind] = (counts[entry.kind] or 0) + 1
    end
    return {
        id = match.metadata and match.metadata.id or 0,
        target = match.metadata and match.metadata.target or "Opponent",
        duration = match.metadata and match.metadata.duration or 0,
        entries = entries,
        counts = counts,
    }
end

return Replay
