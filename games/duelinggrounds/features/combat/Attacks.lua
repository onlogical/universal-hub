local Attacks = {}

local UNKNOWN_ATTACK_REACH = 12

local function impacts(attackInfo)
    return attackInfo and attackInfo.impacts or {}
end

function Attacks.sameAnimation(left, right)
    return left ~= nil
        and right ~= nil
        and (left == right or left.AnimationId == right.AnimationId)
end

function Attacks.findByAnimation(attackTypes, animation)
    if not attackTypes or not animation then
        return nil
    end
    for attackName, attackInfo in pairs(attackTypes) do
        if Attacks.sameAnimation(attackInfo.animation, animation) then
            return attackInfo, attackName
        end
    end
    return nil
end

function Attacks.firstImpactTime(attackInfo)
    local first = math.huge
    for _, impact in ipairs(impacts(attackInfo)) do
        if type(impact.markerTime) == "number" then
            first = math.min(first, impact.markerTime)
        end
    end
    return first < math.huge and first or nil
end

function Attacks.lastImpactTime(attackInfo)
    local last = -math.huge
    for _, impact in ipairs(impacts(attackInfo)) do
        if type(impact.markerTime) == "number" then
            last = math.max(last, impact.markerTime)
        end
    end
    return last > -math.huge and last or nil
end

function Attacks.marker(attackInfo, markerName)
    local timeMarkers = attackInfo and attackInfo.timeMarkers
    return timeMarkers and timeMarkers[markerName] or nil
end

function Attacks.impactResultValue(attackInfo, resultName, valueName)
    local impact = impacts(attackInfo)[1]
    local results = impact and impact.impactInfo and impact.impactInfo.impactResults
    local result = results and results[resultName]
    return result and result[valueName] or 0
end

function Attacks.triggersUltimateDamage(attackInfo)
    for _, impact in ipairs(impacts(attackInfo)) do
        local results = impact.impactInfo
            and impact.impactInfo.impactResults
        if results and results.GetHit and results.GetHit.triggerUltimate == true then
            return true
        end
    end
    return false
end

function Attacks.isHeavy(attackName, attackInfo)
    if string.find(string.lower(attackName or ""), "heavy", 1, true) then
        return true
    end
    return Attacks.impactResultValue(attackInfo, "GetHit", "healthDamage") >= 50
        or Attacks.impactResultValue(attackInfo, "Block", "postureDamage") >= 30
end

function Attacks.isParryable(impact)
    local results = impact and impact.impactInfo and impact.impactInfo.impactResults
    return results ~= nil and results.Parry ~= nil
end

function Attacks.isMultiHit(attackInfo)
    return #impacts(attackInfo) > 1
end

function Attacks.impactContainsPoint(attackerCFrame, point, impact, margin)
    local impactInfo = impact and impact.impactInfo
    local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
    local hitboxSize = impactInfo and impactInfo.hitboxSize
    if typeof(hitboxCFrame) ~= "CFrame" or typeof(hitboxSize) ~= "Vector3" then
        return false
    end
    local localPoint = (attackerCFrame * hitboxCFrame):PointToObjectSpace(point)
    local allowance = hitboxSize / 2 + (margin or Vector3.zero)
    return math.abs(localPoint.X) <= allowance.X
        and math.abs(localPoint.Y) <= allowance.Y
        and math.abs(localPoint.Z) <= allowance.Z
end

function Attacks.impactCanReach(attacker, defender, impact, options)
    if not attacker or not defender or not impact then
        return false
    end
    options = options or {}
    if Attacks.impactContainsPoint(attacker.CFrame, defender.Position, impact, options.margin) then
        return true
    end
    if options.strict then
        return false
    end

    local offset = defender.Position - attacker.Position
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    if flatOffset.Magnitude <= 0 then
        return false
    end
    local impactInfo = impact.impactInfo
    local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
    local hitboxSize = impactInfo and impactInfo.hitboxSize
    local maximumReach = options.unknownReach or UNKNOWN_ATTACK_REACH
    local minimumFacing = 0
    if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
        maximumReach = math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2
            + (options.reachAllowance or 4)
        minimumFacing = options.minimumFacing or 0.15
    end
    return flatOffset.Magnitude <= maximumReach
        and attacker.CFrame.LookVector:Dot(flatOffset.Unit) >= minimumFacing
end

function Attacks.canReach(attacker, defender, attackInfo, options)
    for _, impact in ipairs(impacts(attackInfo)) do
        if Attacks.impactCanReach(attacker, defender, impact, options) then
            return true
        end
    end
    return false
end

function Attacks.geometricReach(attackInfo, allowance)
    local maximumReach = 0
    for _, impact in ipairs(impacts(attackInfo)) do
        local impactInfo = impact.impactInfo
        local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
        local hitboxSize = impactInfo and impactInfo.hitboxSize
        if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
            maximumReach = math.max(
                maximumReach,
                math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2 + (allowance or 0)
            )
        end
    end
    return maximumReach
end

return Attacks
