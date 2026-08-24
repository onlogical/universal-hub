local AutoCounterRuntime = {}
AutoCounterRuntime.__index = AutoCounterRuntime

local function horizontalMagnitude(vector)
    return Vector3.new(vector.X, 0, vector.Z).Magnitude
end

function AutoCounterRuntime.new(options)
    options = options or {}
    return setmetatable({
        clock = options.clock or os.clock,
        confirmedAt = nil,
        cooldownUntil = 0,
        epoch = nil,
        lastReason = "idle",
        lastSampleAt = nil,
        maximumHorizontalDisplacement = options.maximumHorizontalDisplacement or 5,
        maximumSampleGap = options.maximumSampleGap or 0.25,
        outboundMaximum = options.outboundMaximum or 1001,
        outboundMinimum = options.outboundMinimum or 999,
        outboundSign = nil,
        outboundAt = nil,
        previousPosition = nil,
        readyAt = nil,
        readyWindow = options.readyWindow or 0.75,
        returnMinimum = options.returnMinimum or 900,
        returnRadius = options.returnRadius or 1,
        signatureWindow = options.signatureWindow or 1.5,
        stableSamples = 0,
        stableSamplesRequired = options.stableSamplesRequired or 3,
        startPosition = nil,
        state = "idle",
        stopped = false,
    }, AutoCounterRuntime)
end

function AutoCounterRuntime:_reset(reason)
    self.confirmedAt = nil
    self.cooldownUntil = 0
    self.epoch = nil
    self.lastReason = reason or "reset"
    self.lastSampleAt = nil
    self.outboundSign = nil
    self.outboundAt = nil
    self.previousPosition = nil
    self.readyAt = nil
    self.stableSamples = 0
    self.startPosition = nil
    self.state = "idle"
end

function AutoCounterRuntime:_baseline(sample, now, reason)
    self.confirmedAt = nil
    self.cooldownUntil = 0
    self.epoch = sample.epoch
    self.lastReason = reason or "baseline"
    self.lastSampleAt = now
    self.outboundSign = nil
    self.outboundAt = nil
    self.previousPosition = sample.position
    self.readyAt = nil
    self.stableSamples = 0
    self.startPosition = nil
    self.state = "idle"
end

function AutoCounterRuntime:status()
    return {
        confirmedAt = self.confirmedAt,
        cooldownUntil = self.cooldownUntil,
        lastReason = self.lastReason,
        outboundAt = self.outboundAt,
        readyAt = self.readyAt,
        stableSamples = self.stableSamples,
        state = self.state,
    }
end

function AutoCounterRuntime:isReady()
    return not self.stopped and self.state == "ready"
end

function AutoCounterRuntime:update(sample)
    sample = sample or {}
    local now = sample.now or self.clock()
    if self.stopped then
        return self:status()
    end
    if sample.enabled ~= true then
        self:_reset("disabled")
        return self:status()
    end
    if
        sample.roundEligible ~= true
        or sample.alive ~= true
        or sample.epoch == nil
        or typeof(sample.position) ~= "Vector3"
    then
        self:_reset("ineligible")
        return self:status()
    end

    if self.state == "cooldown" then
        if now < self.cooldownUntil then
            self.epoch = sample.epoch
            self.lastSampleAt = now
            self.previousPosition = sample.position
            return self:status()
        end
        self:_baseline(sample, now, "cooldown-complete")
        return self:status()
    end

    if self.epoch ~= sample.epoch or self.previousPosition == nil then
        self:_baseline(sample, now, "epoch-baseline")
        return self:status()
    end

    local deltaTime = now - (self.lastSampleAt or now)
    if deltaTime <= 0 or deltaTime > self.maximumSampleGap then
        self:_baseline(sample, now, "sample-gap")
        return self:status()
    end

    local delta = sample.position - self.previousPosition
    if self.state == "idle" then
        local vertical = math.abs(delta.Y)
        if
            vertical >= self.outboundMinimum
            and vertical <= self.outboundMaximum
            and horizontalMagnitude(delta) <= self.maximumHorizontalDisplacement
        then
            self.lastReason = "outbound"
            self.outboundAt = now
            self.outboundSign = delta.Y >= 0 and 1 or -1
            self.startPosition = self.previousPosition
            self.state = "outbound"
        end
    elseif self.state == "outbound" then
        if now - self.outboundAt > self.signatureWindow then
            self:_baseline(sample, now, "return-timeout")
            return self:status()
        end
        local returned = delta.Y * self.outboundSign <= -self.returnMinimum
            and (sample.position - self.startPosition).Magnitude <= self.returnRadius
        if returned then
            self.confirmedAt = now
            self.lastReason = "returned"
            self.stableSamples = 0
            self.state = "confirmed"
        end
    elseif self.state == "confirmed" then
        if now - self.confirmedAt > self.readyWindow then
            self:_baseline(sample, now, "ready-timeout")
            return self:status()
        end
        local stable = sample.humanoidState == "Running"
            and (sample.position - self.startPosition).Magnitude <= self.returnRadius
            and delta.Magnitude <= self.returnRadius
        self.stableSamples = stable and self.stableSamples + 1 or 0
        if self.stableSamples >= self.stableSamplesRequired then
            self.lastReason = "ready"
            self.readyAt = now
            self.state = "ready"
        end
    elseif self.state == "ready" and now - self.confirmedAt > self.readyWindow then
        self:_baseline(sample, now, "action-timeout")
        return self:status()
    end

    self.lastSampleAt = now
    self.previousPosition = sample.position
    return self:status()
end

function AutoCounterRuntime:consume(now, cooldown)
    if not self:isReady() then
        return false
    end
    now = now or self.clock()
    self.cooldownUntil = now + math.max(0, cooldown or 0)
    self.lastReason = "consumed"
    self.state = "cooldown"
    self.confirmedAt = nil
    self.outboundAt = nil
    self.outboundSign = nil
    self.readyAt = nil
    self.stableSamples = 0
    self.startPosition = nil
    return true
end

function AutoCounterRuntime:disable(reason)
    if self.stopped then
        return
    end
    self:_reset(reason or "disabled")
end

function AutoCounterRuntime:stop()
    if self.stopped then
        return
    end
    self:_reset("stopped")
    self.stopped = true
end

return AutoCounterRuntime
