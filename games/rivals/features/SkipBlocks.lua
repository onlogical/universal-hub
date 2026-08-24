local SkipBlocks = {}
SkipBlocks.__index = SkipBlocks

function SkipBlocks.shouldBlock(item, target, ctx)
    if not target or type(ctx) ~= "table" or type(ctx.isDeflecting) ~= "function" then
        return false
    end
    local targetFighter = target.player
        and type(ctx.fighterFor) == "function"
        and ctx.fighterFor(target.player)
    local counter = ctx.taskCounterPolicy
    local sprayCounter = targetFighter
        and type(counter) == "table"
        and type(counter.shouldForceSpray) == "function"
        and counter.shouldForceSpray(item, targetFighter.EquippedItem)
    return ctx.isDeflecting(target.player) == true and sprayCounter ~= true
end

function SkipBlocks.isFiring(item)
    if type(item) ~= "table" then
        return false
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "IsShooting")
        if succeeded and type(value) == "boolean" then
            return value
        end
    end
    local data = item.Data
    return type(data) == "table" and data.IsShooting == true
end

function SkipBlocks.new(options)
    assert(options and options.getFighter, "RIVALS Katana Stop requires a fighter getter")
    assert(options.hookFunction, "RIVALS Katana Stop requires hookfunction")
    assert(options.isEnabled, "RIVALS Katana Stop requires an enabled predicate")
    assert(options.restoreFunction, "RIVALS Katana Stop requires restorefunction")
    assert(options.shouldBlock, "RIVALS Katana Stop requires a block predicate")

    return setmetatable({
        getFighter = options.getFighter,
        hookFunction = options.hookFunction,
        hookTarget = nil,
        isEnabled = options.isEnabled,
        restoreFunction = options.restoreFunction,
        shouldBlock = options.shouldBlock,
        stopped = false,
    }, SkipBlocks)
end

function SkipBlocks:_restoreHook()
    if not self.hookTarget then
        return
    end
    self.restoreFunction(self.hookTarget)
    self.hookTarget = nil
end

function SkipBlocks:refreshHook()
    if self.stopped then
        return
    end
    if not self.isEnabled() then
        self:_restoreHook()
        return
    end

    local fighter = self.getFighter()
    local target = type(fighter) == "table" and type(fighter.Input) == "function" and fighter.Input
        or nil
    if target == self.hookTarget then
        return
    end

    self:_restoreHook()
    if not target then
        return
    end

    self.hookTarget = target
    local original
    original = self.hookFunction(target, function(fighterSelf, action, ...)
        local currentFighter = self.getFighter()
        if
            not self.stopped
            and self.isEnabled()
            and fighterSelf == currentFighter
            and action == "StartShooting"
            and self.shouldBlock(currentFighter.EquippedItem)
        then
            return
        end
        return original(fighterSelf, action, ...)
    end)
end

function SkipBlocks.update(item, target, ctx)
    if not SkipBlocks.shouldBlock(item, target, ctx) then
        return false
    end
    if
        type(ctx.releaseFire) == "function" and (SkipBlocks.isFiring(item) or ctx.fireHeld == true)
    then
        ctx.releaseFire()
    end
    return true
end

function SkipBlocks:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_restoreHook()
end

return SkipBlocks
