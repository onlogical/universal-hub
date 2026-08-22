local WallEscape = {}

local function clearance(result, maximumDistance)
    if not result then
        return maximumDistance
    end
    return math.clamp(tonumber(result.Distance) or 0, 0, maximumDistance)
end

function WallEscape.choose(toward, cast, maximumDistance, preferredSide)
    assert(typeof(toward) == "Vector3", "Wall escape requires a target direction")
    assert(type(cast) == "function", "Wall escape requires a clearance probe")
    maximumDistance = math.max(tonumber(maximumDistance) or 0, 0)

    local left = Vector3.new(-toward.Z, 0, toward.X)
    if left.Magnitude <= 0.001 then
        return Vector3.zero, 0
    end
    left = left.Unit
    local right = -left
    local leftClearance = clearance(cast(left, maximumDistance), maximumDistance)
    local rightClearance = clearance(cast(right, maximumDistance), maximumDistance)

    if math.abs(leftClearance - rightClearance) <= 0.05 then
        local side = preferredSide == -1 and -1 or 1
        return side == 1 and left or right, side, leftClearance, rightClearance
    end
    if leftClearance > rightClearance then
        return left, 1, leftClearance, rightClearance
    end
    return right, -1, leftClearance, rightClearance
end

return WallEscape
