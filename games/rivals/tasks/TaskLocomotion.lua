local TaskLocomotion = {}
TaskLocomotion.__index = TaskLocomotion

function TaskLocomotion.new()
    return setmetatable({
        lastDistance = math.huge,
        lastProgressAt = 0,
        nextSlideAt = 0,
        strafeSign = 1,
        target = nil,
    }, TaskLocomotion)
end

function TaskLocomotion:plan(state)
    local offset = state.targetPosition - state.position
    local distance = offset.Magnitude
    local targetChanged = self.target ~= state.targetPosition
    if targetChanged then
        self.target = state.targetPosition
        self.lastDistance = distance
        self.lastProgressAt = state.now
    elseif distance < self.lastDistance - 0.75 then
        self.lastDistance = distance
        self.lastProgressAt = state.now
    elseif state.clear == false and state.now - self.lastProgressAt >= 0.65 then
        self.strafeSign = -self.strafeSign
        self.lastDistance = distance
        self.lastProgressAt = state.now
    end

    local toward = distance > 0.01 and offset.Unit or Vector3.zero
    local strafe = Vector3.new(-toward.Z, 0, toward.X) * self.strafeSign
    local direction = distance > 8 and (toward * 0.9 + strafe * 0.2).Unit
        or (strafe - toward * 0.5).Unit
    local slide = state.clear ~= false
        and state.grounded == true
        and distance > 24
        and state.now >= self.nextSlideAt
    if slide then
        self.nextSlideAt = state.now + 2.8
    end
    return {
        direction = direction,
        intent = "push",
        slide = slide,
        strafeSign = self.strafeSign,
    }
end

return TaskLocomotion
