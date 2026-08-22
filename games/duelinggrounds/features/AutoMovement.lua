local AutoMovement = {}
AutoMovement.__index = AutoMovement

local ZERO = Vector3.zero
local DEFAULT_RANDOM = {
    NextNumber = function(_, minimum, maximum)
        local value = math.random()
        if minimum ~= nil and maximum ~= nil then
            return minimum + (maximum - minimum) * value
        end
        return value
    end,
}

function AutoMovement.new(options)
    options = options or {}
    return setmetatable({
        input = nil,
        lastDirection = nil,
        mode = nil,
        target = nil,
        orbitDirection = 1,
        nextOrbitSwitchAt = 0,
        lastMovementCheckAt = 0,
        lastMovementCheckPosition = nil,
        owned = false,
        random = options.random or (Random and Random.new and Random.new()) or DEFAULT_RANDOM,
        feintUntil = -math.huge,
        radiusScale = 1,
        stopped = false,
    }, AutoMovement)
end

function AutoMovement:_release()
    if self.owned and self.input and self.input.MoveDirection == self.lastDirection then
        self.input.MoveDirection = ZERO
    end
    self.input = nil
    self.lastDirection = nil
    self.owned = false
end

function AutoMovement:_reset()
    self:_release()
    self.mode = nil
    self.target = nil
    self.lastMovementCheckPosition = nil
end

function AutoMovement:_move(input, direction)
    if self.input and self.input ~= input then
        self:_release()
    end
    self.input = input
    self.lastDirection = direction
    self.owned = true
    input.MoveDirection = direction
end

function AutoMovement:update(settings, frame, combatDisposition)
    if self.stopped then
        return
    end
    if
        settings.autoMovement ~= true
        or settings.autoFight ~= true
        or not frame
        or not frame.input
        or not frame.target
        or not frame.localPosition
        or not frame.targetPosition
        or not frame.profile
    then
        self:_reset()
        return
    end

    if combatDisposition and combatDisposition.canMove == false then
        self:_release()
        return
    end

    local now = frame.now or os.clock()
    if frame.target ~= self.target then
        self.target = frame.target
        self.mode = nil
        self.orbitDirection = 1
        self.lastMovementCheckPosition = frame.localPosition
        self.lastMovementCheckAt = now
        self.nextOrbitSwitchAt = now + (frame.orbitInterval or 1.9)
        self.feintUntil = -math.huge
        self.radiusScale = 1
    end

    local offset = frame.targetPosition - frame.localPosition
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    local distance = flatOffset.Magnitude
    if distance <= 0.001 then
        self:_move(frame.input, ZERO)
        return
    end

    local profile = frame.profile
    local movement = frame.movement or {}
    local toward = flatOffset.Unit
    if self.mode == "approach" then
        if distance <= profile.orbitDistance + 0.5 then
            self.mode = "orbit"
        end
    elseif self.mode == "retreat" then
        if distance >= profile.orbitDistance - 0.5 then
            self.mode = "orbit"
        end
    elseif distance > profile.approachDistance then
        self.mode = "approach"
    elseif distance < profile.retreatDistance then
        self.mode = "retreat"
    else
        self.mode = "orbit"
    end

    local direction
    if self.mode == "approach" then
        direction = toward
    elseif self.mode == "retreat" then
        direction = -toward
    else
        if now >= self.nextOrbitSwitchAt then
            self.orbitDirection = self.random:NextNumber() < 0.5 and -1 or 1
            self.nextOrbitSwitchAt = now + (movement.orbitInterval or frame.orbitInterval or 1.9)
            self.radiusScale = 1
                + self.random:NextNumber(
                    -(movement.radiusVariance or 0),
                    movement.radiusVariance or 0
                )
            if self.random:NextNumber() < (movement.feintChance or 0) then
                self.feintUntil = now + (movement.feintDuration or 0)
            end
        end
        local tangent = Vector3.new(-toward.Z, 0, toward.X) * self.orbitDirection
        local desiredOrbitDistance = profile.orbitDistance * self.radiusScale
        local radialCorrection = math.clamp((distance - desiredOrbitDistance) / 2, -0.6, 0.6)
        direction = tangent + toward * radialCorrection
        direction = direction.Magnitude > 0 and direction.Unit or tangent
    end

    local tangent = Vector3.new(-toward.Z, 0, toward.X) * self.orbitDirection
    if now < self.feintUntil then
        direction = (-toward * 0.65 + tangent * 0.75).Unit
    elseif self.mode == "approach" and (movement.angularApproach or 0) > 0 then
        direction = (toward + tangent * movement.angularApproach).Unit
    elseif self.mode == "retreat" and (movement.angularApproach or 0) > 0 then
        direction = (-toward + tangent * movement.angularApproach * 0.5).Unit
    end

    if frame.isObstacle and frame.isObstacle(direction) then
        self.orbitDirection = -self.orbitDirection
        direction = Vector3.new(-toward.Z, 0, toward.X) * self.orbitDirection
        self.mode = "orbit"
    end

    if now - self.lastMovementCheckAt >= 0.75 then
        if
            self.lastMovementCheckPosition
            and (frame.localPosition - self.lastMovementCheckPosition).Magnitude < 0.6
        then
            self.orbitDirection = -self.orbitDirection
        end
        self.lastMovementCheckPosition = frame.localPosition
        self.lastMovementCheckAt = now
    end

    self:_move(frame.input, direction)
end

function AutoMovement:stop()
    if self.stopped then
        return
    end
    self:_reset()
    self.stopped = true
end

return AutoMovement
