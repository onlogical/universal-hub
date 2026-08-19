local Planner = {}

local function selectImpact(impacts, canReach)
    local reachable = {}
    for index, impact in ipairs(impacts or {}) do
        if canReach(impact, index) then
            table.insert(reachable, { impact = impact, index = index })
        end
    end
    if #reachable == 0 then
        return nil
    end
    if #reachable > 1 then
        for _, entry in ipairs(reachable) do
            if entry.impact.parryable then
                return entry, #reachable
            end
        end
    end
    return reachable[1], #reachable
end

function Planner.plan(input)
    local selected, reachableCount = selectImpact(
        input.impacts,
        input.canReach or function()
            return true
        end
    )
    if not selected then
        return nil
    end

    local impact = selected.impact
    local canParry = input.canParry == true and impact.parryable == true
    local canDodge = input.canDodge == true
    local kind
    local reason
    if reachableCount > 1 and canParry then
        kind = "parry"
        reason = "interrupt multi-hit chain"
    elseif input.isHeavy and canDodge then
        kind = "dodge"
        reason = "heavy counter"
    elseif canParry then
        kind = "parry"
        reason = input.isHeavy and "dodge unavailable" or "parryable impact"
    elseif canDodge then
        kind = "dodge"
        reason = impact.parryable and "parry unavailable" or "unparryable impact"
    else
        return nil
    end

    return {
        kind = kind,
        mode = input.isHeavy and "heavy" or nil,
        attackName = input.attackName,
        impactIndex = selected.index,
        impactCount = #(input.impacts or {}),
        reachableImpactCount = reachableCount,
        parryable = impact.parryable == true,
        timeUntilImpact = impact.timeUntilImpact,
        reason = reason,
    }
end

function Planner.fallback(intent, availability)
    if intent.kind == "dodge"
        and intent.parryable
        and availability.canParry == true
    then
        return "parry"
    end
    if intent.kind == "parry" and availability.canDodge == true then
        return "dodge"
    end
    return nil
end

return Planner
