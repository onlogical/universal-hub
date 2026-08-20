local TeleStyle = {}

function TeleStyle.preferences()
    return {
        allowOffense = true,
        counterAllowed = false,
        teleAttack = true,
    }
end

function TeleStyle.timeUntilImpact(trackPosition, trackSpeed, markerTime)
    local speed = math.max(math.abs(trackSpeed or 1), 0.05)
    return ((markerTime or 0) - (trackPosition or 0)) / speed
end

function TeleStyle.shouldWarpIn(trackPosition, trackSpeed, firstImpact, leadTime)
    return TeleStyle.timeUntilImpact(trackPosition, trackSpeed, firstImpact)
        <= (leadTime or 0.08)
end

function TeleStyle.shouldWarpAway(trackPosition, trackSpeed, lastImpact, graceTime)
    return TeleStyle.timeUntilImpact(trackPosition, trackSpeed, lastImpact)
        <= -(graceTime or 0.04)
end

return TeleStyle
