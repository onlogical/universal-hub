local AutoCounterTestSimulator = {}
AutoCounterTestSimulator.__index = AutoCounterTestSimulator

function AutoCounterTestSimulator.new(options)
    assert(options and options.getRoot, "RIVALS Auto Counter test simulator requires a root getter")
    local configuration = options.configuration or {}
    return setmetatable({
        armedAt = nil,
        baselineSamples = 0,
        clock = options.clock or os.clock,
        configured = configuration.enabled == true,
        getRoot = options.getRoot,
        holdDuration = configuration.holdDuration or 0.45,
        offset = Vector3.new(0, configuration.verticalOffset or 1000, 0),
        outboundAt = nil,
        originalFrame = nil,
        phase = "idle",
        spent = false,
        startDelay = configuration.startDelay or 0.25,
        stopped = false,
    }, AutoCounterTestSimulator)
end

function AutoCounterTestSimulator:_restore()
    local root = self.getRoot()
    if root and self.originalFrame then
        root.CFrame = self.originalFrame
    end
    self.originalFrame = nil
    if self.phase == "outbound" then
        self.phase = "complete"
        self.spent = true
    end
end

function AutoCounterTestSimulator:update(active, roundEligible)
    if self.stopped or not self.configured then
        return self.phase
    end
    if active ~= true or roundEligible ~= true then
        self:_restore()
        if not self.spent then
            self.armedAt = nil
            self.baselineSamples = 0
            self.phase = "idle"
        end
        return self.phase
    end
    if self.spent then
        return self.phase
    end

    local now = self.clock()
    local root = self.getRoot()
    if not root or typeof(root.CFrame) ~= "CFrame" then
        return self.phase
    end
    if self.phase == "idle" then
        self.baselineSamples += 1
        if self.baselineSamples >= 3 then
            self.armedAt = now
            self.phase = "armed"
        end
    elseif self.phase == "armed" and now - self.armedAt >= self.startDelay then
        self.originalFrame = root.CFrame
        root.CFrame = root.CFrame + self.offset
        self.outboundAt = now
        self.phase = "outbound"
    elseif self.phase == "outbound" and now - self.outboundAt >= self.holdDuration then
        self:_restore()
    end
    return self.phase
end

function AutoCounterTestSimulator:status()
    return {
        configured = self.configured,
        phase = self.phase,
        spent = self.spent,
    }
end

function AutoCounterTestSimulator:stop()
    if self.stopped then
        return
    end
    self:_restore()
    self.stopped = true
end

return AutoCounterTestSimulator
