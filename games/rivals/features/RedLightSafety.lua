local RedLightSafety = {}
RedLightSafety.__index = RedLightSafety

function RedLightSafety.new(options)
    assert(options, "RIVALS Red Light Safety requires options")
    assert(options.hookFunction, "RIVALS Red Light Safety requires hookfunction")
    assert(options.restoreFunction, "RIVALS Red Light Safety requires restorefunction")
    assert(options.releaseAll, "RIVALS Red Light Safety requires input release")
    assert(options.stopMovement, "RIVALS Red Light Safety requires movement stop")
    assert(options.setInputSink, "RIVALS Red Light Safety requires input sinking")

    local self = setmetatable({
        chickenGame = nil,
        enabled = options.enabled or function()
            return true
        end,
        hookFunction = options.hookFunction,
        paused = false,
        releaseAll = options.releaseAll,
        restoreFunction = options.restoreFunction,
        setInputSink = options.setInputSink,
        stopMovement = options.stopMovement,
        targets = {},
    }, RedLightSafety)

    if options.chickenGame then
        self:refresh(options.chickenGame)
    end
    return self
end

function RedLightSafety:refresh(chickenGame)
    if chickenGame == self.chickenGame and #self.targets > 0 then
        return
    end
    for _, target in ipairs(self.targets) do
        self.restoreFunction(target)
    end
    table.clear(self.targets)
    self.chickenGame = chickenGame
    if not chickenGame then
        self:setPaused(false)
        return
    end
    local redTarget = chickenGame.RedLight
    local greenTarget = chickenGame.GreenLight
    assert(
        type(redTarget) == "function" and type(greenTarget) == "function",
        "RIVALS Red Light Safety requires ChickenGame light methods"
    )

    local originalRed
    originalRed = self.hookFunction(redTarget, function(...)
        if self.enabled() then
            self:setPaused(true)
        end
        return originalRed(...)
    end)
    local originalGreen
    originalGreen = self.hookFunction(greenTarget, function(...)
        self:setPaused(false)
        return originalGreen(...)
    end)
    self.targets = { redTarget, greenTarget }
end

function RedLightSafety:setPaused(paused)
    paused = paused == true
    if self.paused == paused then
        return
    end
    self.paused = paused
    self.setInputSink(paused)
    if paused then
        self.releaseAll()
        self.stopMovement()
    end
end

function RedLightSafety:isPaused()
    return self.paused
end

function RedLightSafety:holdStill()
    if self.paused then
        self.stopMovement()
    end
end

function RedLightSafety:stop()
    self.paused = false
    self.setInputSink(false)
    for _, target in ipairs(self.targets) do
        self.restoreFunction(target)
    end
    table.clear(self.targets)
end

return RedLightSafety
