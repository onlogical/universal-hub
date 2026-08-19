local FrameData = {}

local function sortedImpacts(attackInfo)
    local impacts = {}
    for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
        if type(impact.markerTime) == "number" then
            table.insert(impacts, impact.markerTime)
        end
    end
    table.sort(impacts)
    return impacts
end

local function marker(attackInfo, name)
    local markers = attackInfo and attackInfo.timeMarkers
    return markers and type(markers[name]) == "number" and markers[name] or nil
end

function FrameData.describe(track, attackInfo, attackName)
    if not track or not attackInfo then
        return nil
    end
    local speed = math.max(math.abs(track.Speed or 1), 0.05)
    local elapsed = math.max(track.TimePosition or 0, 0)
    local impacts = sortedImpacts(attackInfo)
    local firstImpact = impacts[1]
    local lastImpact = impacts[#impacts]
    local recoveryEnd = marker(attackInfo, "canCancel")
        or (type(track.Length) == "number" and track.Length > 0 and track.Length)
        or lastImpact
        or elapsed
    local nextImpact
    local previousImpact
    for _, impactTime in ipairs(impacts) do
        if impactTime > elapsed then
            nextImpact = impactTime
            break
        end
        previousImpact = impactTime
    end
    local comboGap
    if nextImpact and previousImpact then
        comboGap = (nextImpact - previousImpact) / speed
    elseif #impacts > 1 then
        comboGap = (impacts[2] - impacts[1]) / speed
    end
    local startupRemaining = firstImpact and math.max((firstImpact - elapsed) / speed, 0) or nil
    local recoveryRemaining = math.max((recoveryEnd - elapsed) / speed, 0)
    local punishWindow = lastImpact and elapsed >= lastImpact
        and recoveryRemaining
        or 0
    local phase = "recovery"
    if firstImpact and elapsed < firstImpact then
        phase = "startup"
    elseif nextImpact then
        phase = previousImpact and "combo" or "startup"
    elseif recoveryRemaining <= 0 then
        phase = "complete"
    end
    return {
        attack = attackName or "Attack",
        phase = phase,
        elapsed = elapsed,
        startup = startupRemaining,
        recovery = recoveryRemaining,
        punish = punishWindow,
        comboGap = comboGap,
        nextImpact = nextImpact and math.max((nextImpact - elapsed) / speed, 0) or nil,
    }
end

return FrameData
