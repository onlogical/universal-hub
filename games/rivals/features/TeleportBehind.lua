local TeleportBehind = {}

-- Irregular barrage around the target. A sequential ring is readable.
TeleportBehind.DISTANCE = 56
TeleportBehind.DISTANCE_SPREAD = 24
TeleportBehind.HEIGHT = 64
TeleportBehind.HEIGHT_SPREAD = 20
TeleportBehind.CLOSE_DISTANCE = 10
TeleportBehind.CLOSE_HEIGHT = 4
TeleportBehind.KNIFE_DISTANCE = 4
TeleportBehind.KNIFE_HEIGHT = 1
TeleportBehind.AIM_TORSO = 1
TeleportBehind.HIGH_AIM = 12
TeleportBehind.CLEARANCE = 80
TeleportBehind.MARGIN = 40
TeleportBehind.BODY = 4
TeleportBehind.MIN_DISTANCE = 16
TeleportBehind.HOP_RATE = 16
TeleportBehind.MIN_YAW_DELTA = math.pi * 0.6
TeleportBehind.OOB_TAG = "OutOfBoundsPart"
TeleportBehind.OOB_SAFE_TAG = "OutOfBoundsSafePart"

local heldHumanoid

local function rootFrame(target)
    local character = target and target.character
    local root = target and target.root
        or character and (
            character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("RootPart")
        )
    local frame = root and root.CFrame
    if typeof(frame) ~= "CFrame" then
        return nil
    end
    return frame
end

function TeleportBehind.range()
    return TeleportBehind.DISTANCE, TeleportBehind.HEIGHT
end

function TeleportBehind.hopIndex(clock)
    clock = type(clock) == "number" and clock or 0
    return math.floor(clock * TeleportBehind.HOP_RATE)
end

function TeleportBehind.hash(index, salt)
    index = type(index) == "number" and index or 0
    salt = type(salt) == "number" and salt or 0
    local x = (index * 1103515245 + 12345 + salt * 7919) % 2147483648
    return x / 2147483648
end

local function yawDelta(a, b)
    return math.abs((a - b + math.pi) % (math.pi * 2) - math.pi)
end

function TeleportBehind.bearing(from, center)
    if typeof(from) ~= "Vector3" or typeof(center) ~= "Vector3" then
        return nil
    end
    local delta = from - center
    if math.abs(delta.X) + math.abs(delta.Z) < 1e-3 then
        return nil
    end
    return math.atan2(delta.Z, delta.X)
end

function TeleportBehind.pose(clock, lastYaw)
    local index = TeleportBehind.hopIndex(clock)
    local yaw = TeleportBehind.hash(index, 1) * math.pi * 2
    if type(lastYaw) == "number" and yawDelta(yaw, lastYaw) < TeleportBehind.MIN_YAW_DELTA then
        yaw = lastYaw + math.pi * (0.7 + TeleportBehind.hash(index, 2) * 0.6)
    end
    local distance = TeleportBehind.DISTANCE
        + (TeleportBehind.hash(index, 3) * 2 - 1) * TeleportBehind.DISTANCE_SPREAD
    local height = TeleportBehind.HEIGHT
        + (TeleportBehind.hash(index, 4) * 2 - 1) * TeleportBehind.HEIGHT_SPREAD
    return yaw, distance, height
end

function TeleportBehind.insidePart(part, position)
    if typeof(position) ~= "Vector3" then
        return false
    end
    local frame = part and part.CFrame
    local size = part and part.Size
    if typeof(frame) ~= "CFrame" or typeof(size) ~= "Vector3" then
        return false
    end
    local localPoint = frame:PointToObjectSpace(position)
    local half = size * 0.5
    return math.abs(localPoint.X) <= half.X
        and math.abs(localPoint.Y) <= half.Y
        and math.abs(localPoint.Z) <= half.Z
end

function TeleportBehind.isOutOfBounds(position, tagged)
    tagged = tagged or {}
    local insideKill = false
    for _, part in ipairs(tagged.kill or {}) do
        if TeleportBehind.insidePart(part, position) then
            insideKill = true
            break
        end
    end
    if not insideKill then
        return false
    end
    for _, part in ipairs(tagged.safe or {}) do
        if TeleportBehind.insidePart(part, position) then
            return false
        end
    end
    return true
end

function TeleportBehind.cageBounds(parts)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local found = false
    for _, part in ipairs(parts or {}) do
        local frame = part and part.CFrame
        local size = part and part.Size
        if typeof(frame) == "CFrame" and typeof(size) == "Vector3" then
            local half = size * 0.5
            for _, sx in ipairs({ -1, 1 }) do
                for _, sy in ipairs({ -1, 1 }) do
                    for _, sz in ipairs({ -1, 1 }) do
                        local world = frame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
                        minX = math.min(minX, world.X)
                        minY = math.min(minY, world.Y)
                        minZ = math.min(minZ, world.Z)
                        maxX = math.max(maxX, world.X)
                        maxY = math.max(maxY, world.Y)
                        maxZ = math.max(maxZ, world.Z)
                        found = true
                    end
                end
            end
        end
    end
    if not found then
        return nil
    end
    return {
        min = Vector3.new(minX, minY, minZ),
        max = Vector3.new(maxX, maxY, maxZ),
    }
end

function TeleportBehind.cageTop(parts)
    local bounds = TeleportBehind.cageBounds(parts)
    return bounds and bounds.max.Y or nil
end

function TeleportBehind.outsideHeight(targetY, parts)
    if type(targetY) ~= "number" then
        return TeleportBehind.HEIGHT
    end
    local top = TeleportBehind.cageTop(parts)
    if type(top) ~= "number" then
        return TeleportBehind.HEIGHT
    end
    return math.max(TeleportBehind.HEIGHT, (top + TeleportBehind.CLEARANCE) - targetY)
end

function TeleportBehind.outsideRadius(focus, bounds)
    if typeof(focus) ~= "Vector3" or type(bounds) ~= "table" then
        return TeleportBehind.DISTANCE
    end
    local min, max = bounds.min, bounds.max
    if typeof(min) ~= "Vector3" or typeof(max) ~= "Vector3" then
        return TeleportBehind.DISTANCE
    end
    local farthest = 0
    for _, x in ipairs({ min.X, max.X }) do
        for _, z in ipairs({ min.Z, max.Z }) do
            local dx = x - focus.X
            local dz = z - focus.Z
            local mag = math.sqrt(dx * dx + dz * dz)
            if mag > farthest then
                farthest = mag
            end
        end
    end
    return math.max(TeleportBehind.DISTANCE, farthest + TeleportBehind.MARGIN)
end

function TeleportBehind.focusY(session, targetY)
    if type(targetY) ~= "number" then
        return targetY
    end
    if type(session.teleportFocusY) ~= "number" or targetY <= session.teleportFocusY + 8 then
        session.teleportFocusY = targetY
    end
    return session.teleportFocusY
end

function TeleportBehind.clear(position, isOutOfBounds)
    if typeof(position) ~= "Vector3" then
        return false
    end
    if type(isOutOfBounds) ~= "function" then
        return true
    end
    if isOutOfBounds(position) == true then
        return false
    end
    local margin = TeleportBehind.BODY
    for _, offset in ipairs({
        Vector3.new(margin, 0, 0),
        Vector3.new(-margin, 0, 0),
        Vector3.new(0, margin, 0),
        Vector3.new(0, -margin, 0),
        Vector3.new(0, 0, margin),
        Vector3.new(0, 0, -margin),
    }) do
        if isOutOfBounds(position + offset) == true then
            return false
        end
    end
    return true
end

function TeleportBehind.hasForceField(character)
    return type(character) == "table"
        and type(character.FindFirstChildOfClass) == "function"
        and character:FindFirstChildOfClass("ForceField") ~= nil
end

function TeleportBehind.lookPoint(target)
    if typeof(target and target.position) == "Vector3" then
        return target.position
    end
    local character = target and target.character
    local head = character and character.FindFirstChild and character:FindFirstChild("Head")
    if head and typeof(head.Position) == "Vector3" then
        return head.Position
    end
    local frame = rootFrame(target)
    if not frame then
        return nil
    end
    return frame.Position + Vector3.new(0, 2, 0)
end

function TeleportBehind.aimPoint(from, target)
    local lookAt = TeleportBehind.lookPoint(target)
    local frame = rootFrame(target)
    local root = frame and frame.Position
    if typeof(from) ~= "Vector3" then
        return lookAt
    end
    local focus = typeof(root) == "Vector3" and root or lookAt
    if typeof(focus) ~= "Vector3" then
        return lookAt
    end
    if from.Y - focus.Y < TeleportBehind.HIGH_AIM then
        return lookAt
    end
    return Vector3.new(focus.X, focus.Y + TeleportBehind.AIM_TORSO, focus.Z)
end

function TeleportBehind.canSee(from, lookAt, raycast)
    if typeof(from) ~= "Vector3" or typeof(lookAt) ~= "Vector3" then
        return false
    end
    if type(raycast) ~= "function" then
        return true
    end
    local delta = lookAt - from
    if delta.Magnitude < 1e-3 then
        return true
    end
    return raycast(from, delta) == nil
end

function TeleportBehind.isImmune(session, libs)
    libs = libs or {}
    if type(libs.isImmune) == "function" and libs.isImmune() == true then
        return true
    end
    local character = type(libs.getCharacter) == "function" and libs.getCharacter()
    if TeleportBehind.hasForceField(character) then
        return true
    end
    local target = session and (session.presented or session.aligned)
    return TeleportBehind.hasForceField(target and target.character)
end

function TeleportBehind.pullIn(center, position, isOutOfBounds)
    if typeof(center) ~= "Vector3" or typeof(position) ~= "Vector3" then
        return nil
    end
    if TeleportBehind.clear(position, isOutOfBounds) then
        return position
    end
    for step = 9, 2, -1 do
        local pulled = center:Lerp(position, step / 10)
        local planar = Vector3.new(pulled.X - center.X, 0, pulled.Z - center.Z)
        if planar.Magnitude >= TeleportBehind.MIN_DISTANCE
            and TeleportBehind.clear(pulled, isOutOfBounds)
        then
            return pulled
        end
    end
    return nil
end

local function slotCFrame(center, lookAt, yaw, distance, height)
    local position = center + Vector3.new(
        math.cos(yaw) * distance,
        height,
        math.sin(yaw) * distance
    )
    return CFrame.lookAt(position, lookAt)
end

function TeleportBehind.destination(target, clock, distance, height, isOutOfBounds, yaw, focusY, raycast, closeOnly)
    local frame = rootFrame(target)
    if not frame then
        return nil
    end
    if type(yaw) ~= "number" then
        yaw, distance, height = TeleportBehind.pose(clock)
    elseif type(distance) ~= "number" or type(height) ~= "number" then
        local _, sampledDistance, sampledHeight = TeleportBehind.pose(clock, yaw)
        if type(distance) ~= "number" then
            distance = sampledDistance
        end
        if type(height) ~= "number" then
            height = sampledHeight
        end
    end
    local center = frame.Position
    if type(focusY) == "number" then
        center = Vector3.new(center.X, focusY, center.Z)
    end
    local lookAt = TeleportBehind.lookPoint(target) or frame.Position
    local attempts = {
        { 0, 1, 0 },
        { math.pi * 0.85, 1, 0 },
        { math.pi * 1.2, 1, 0 },
        { math.pi * 0.5, 0.85, 0 },
        { math.pi * 1.5, 0.85, 0 },
        { math.pi, 0.7, 0 },
        { 0, 0.55, 12 },
    }
    for _, attempt in ipairs(attempts) do
        local destination = slotCFrame(
            center,
            lookAt,
            yaw + attempt[1],
            distance * attempt[2],
            height + attempt[3]
        )
        local pulled = TeleportBehind.pullIn(center, destination.Position, isOutOfBounds)
        if pulled and TeleportBehind.canSee(pulled, lookAt, raycast) then
            return CFrame.lookAt(pulled, lookAt)
        end
    end
    if closeOnly ~= true
        and (
            distance > TeleportBehind.CLOSE_DISTANCE + 1
            or height > TeleportBehind.CLOSE_HEIGHT + 1
        )
    then
        return TeleportBehind.destination(
            target,
            clock,
            TeleportBehind.CLOSE_DISTANCE,
            TeleportBehind.CLOSE_HEIGHT,
            isOutOfBounds,
            yaw,
            focusY,
            raycast,
            true
        )
    end
    return nil
end

function TeleportBehind.knifeDestination(target, isOutOfBounds, raycast, focusY)
    local frame = rootFrame(target)
    if not frame then
        return nil
    end
    local look = frame.LookVector
    local planar = Vector3.new(look.X, 0, look.Z)
    if planar.Magnitude < 1e-3 then
        planar = Vector3.new(0, 0, 1)
    else
        planar = planar.Unit
    end
    local center = frame.Position
    if type(focusY) == "number" then
        center = Vector3.new(center.X, focusY, center.Z)
    end
    local lookAt = TeleportBehind.lookPoint(target) or frame.Position
    local behind = center
        - planar * TeleportBehind.KNIFE_DISTANCE
        + Vector3.new(0, TeleportBehind.KNIFE_HEIGHT, 0)
    local pulled = TeleportBehind.pullIn(center, behind, isOutOfBounds)
    if pulled and TeleportBehind.canSee(pulled, lookAt, raycast) then
        return CFrame.lookAt(pulled, lookAt)
    end
    return TeleportBehind.destination(
        target,
        0,
        TeleportBehind.KNIFE_DISTANCE,
        TeleportBehind.KNIFE_HEIGHT,
        isOutOfBounds,
        TeleportBehind.bearing(behind, center) or 0,
        focusY,
        raycast,
        true
    )
end

function TeleportBehind.slotOpen(destination, target, isOutOfBounds, raycast)
    if typeof(destination) ~= "CFrame" then
        return false
    end
    local lookAt = TeleportBehind.lookPoint(target)
    return lookAt ~= nil
        and TeleportBehind.clear(destination.Position, isOutOfBounds)
        and TeleportBehind.canSee(destination.Position, lookAt, raycast)
end

function TeleportBehind.oneShotMode(_session, libs)
    libs = libs or {}
    local mode = type(libs.weaponMode) == "function" and libs.weaponMode()
    if mode == "knife" or mode == "sniper" then
        return mode
    end
    return nil
end

local function stopFall(root)
    if typeof(root.AssemblyLinearVelocity) == "Vector3" then
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
    if typeof(root.AssemblyAngularVelocity) == "Vector3" then
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end

local function apply(root, destination, humanoid)
    root.CFrame = destination
    stopFall(root)
    if humanoid and humanoid.PlatformStand ~= nil then
        humanoid.PlatformStand = true
        heldHumanoid = humanoid
    end
end

function TeleportBehind.release(session, libs)
    libs = libs or {}
    if session then
        session.teleportEngaged = false
        session.teleportSafe = nil
        session.teleportHop = nil
        session.teleportYaw = nil
        session.teleportDistance = nil
        session.teleportHeight = nil
        session.teleportFocusY = nil
    end
    if heldHumanoid and heldHumanoid.PlatformStand == true then
        heldHumanoid.PlatformStand = false
    end
    heldHumanoid = nil
end

function TeleportBehind.hold(session, libs)
    libs = libs or {}
    local settings = session and session.settings or {}
    if settings.teleportBehind ~= true then
        return false
    end
    local destination = session and session.teleportSafe
    local root = type(libs.getRoot) == "function" and libs.getRoot()
    if not root or typeof(destination) ~= "CFrame" then
        return false
    end
    apply(
        root,
        destination,
        type(libs.getHumanoid) == "function" and libs.getHumanoid()
    )
    return true
end

function TeleportBehind.update(session, libs)
    libs = libs or {}
    local settings = session and session.settings or {}
    if settings.teleportBehind ~= true then
        TeleportBehind.release(session, libs)
        return false
    end
    if TeleportBehind.isImmune(session, libs) then
        if session.teleportEngaged == true and typeof(session.teleportSafe) == "CFrame" then
            return TeleportBehind.hold(session, libs)
        end
        return false
    end
    if session.teleportEngaged ~= true then
        if session.active ~= true or session.inCombat ~= true then
            return false
        end
        session.teleportEngaged = true
    end
    local target = session.presented or session.aligned
    if not target and type(libs.selectTarget) == "function" then
        target = libs.selectTarget()
    end
    local root = type(libs.getRoot) == "function" and libs.getRoot()
    if not root then
        TeleportBehind.release(session, libs)
        return false
    end
    local clock = type(libs.clock) == "function" and libs.clock() or session.clock
    local distance, height = TeleportBehind.range()
    if type(libs.distance) == "number" then
        distance = libs.distance
    end
    if type(libs.height) == "number" then
        height = libs.height
    end
    if type(clock) ~= "number" then
        clock = 0
    end
    local frame = rootFrame(target)
    local focusY = frame and TeleportBehind.focusY(session, frame.Position.Y)
    local oneShot = TeleportBehind.oneShotMode(session, libs)
    local destination
    if oneShot == "knife" then
        destination = TeleportBehind.knifeDestination(
            target,
            libs.isOutOfBounds,
            libs.raycast,
            focusY
        )
    elseif oneShot == "sniper"
        and TeleportBehind.slotOpen(
            session.teleportSafe,
            target,
            libs.isOutOfBounds,
            libs.raycast
        )
    then
        local lookAt = TeleportBehind.lookPoint(target)
        destination = CFrame.lookAt(session.teleportSafe.Position, lookAt)
    else
        local hop = TeleportBehind.hopIndex(clock)
        if session.teleportHop ~= hop or type(session.teleportYaw) ~= "number" then
            local around = frame and TeleportBehind.bearing(root.Position, frame.Position)
            local yaw, hopDistance, hopHeight = TeleportBehind.pose(
                clock,
                around or session.teleportYaw
            )
            session.teleportHop = hop
            session.teleportYaw = yaw
            session.teleportDistance = hopDistance
            session.teleportHeight = hopHeight
        end
        destination = TeleportBehind.destination(
            target,
            clock,
            session.teleportDistance or distance,
            session.teleportHeight or height,
            libs.isOutOfBounds,
            session.teleportYaw,
            focusY,
            libs.raycast
        )
    end
    if destination then
        session.teleportSafe = destination
    end
    if typeof(session.teleportSafe) ~= "CFrame" then
        return false
    end
    apply(
        root,
        session.teleportSafe,
        type(libs.getHumanoid) == "function" and libs.getHumanoid()
    )
    return true
end

return TeleportBehind
