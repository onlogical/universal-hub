local Session = {}

function Session.new()
    return {
        clock = 0,
        settings = {},
        localFighter = nil,
        item = nil,
        active = false,
        inCombat = false,
        inRound = false,
        inputCaptured = false,
        taskCombat = false,
        mouse = nil,
        cameraOrigin = nil,
        observations = {},
        utilities = {},
        aligned = nil,
        presented = nil,
    }
end

return Session
