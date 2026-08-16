local PracticeTaskDriver = {}
PracticeTaskDriver.__index = PracticeTaskDriver

local PRACTICE_TASKS = {
    Beginner1 = "range",
    Beginner2 = "targets",
    Beginner3 = "slide",
    Beginner4 = "equip",
    Beginner5 = "dash",
    Beginner6 = "grenade",
}

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then connection:Disconnect() end
end

function PracticeTaskDriver.new(options)
    assert(options and type(options.getFighter) == "function", "Practice driver requires a fighter getter")
    assert(type(options.actions) == "table", "Practice driver requires normal action boundaries")
    local self = setmetatable({
        actions = options.actions,
        getFighter = options.getFighter,
        isInRange = options.isInRange,
        delay = options.delay or (task and task.delay or nil),
        cancelDelay = options.cancelDelay or (task and task.cancel or nil),
        retryDelay = options.retryDelay or 3,
        maxAttempts = options.maxAttempts or 3,
        onChanged = options.onChanged,
        task = nil,
        taskSignature = nil,
        state = "idle",
        attempts = 0,
        paused = false,
        stopped = false,
        retryHandle = nil,
        generation = 0,
        connections = {},
    }, PracticeTaskDriver)
    return self
end

function PracticeTaskDriver:_notify()
    if type(self.onChanged) == "function" then pcall(self.onChanged, self:status()) end
end

function PracticeTaskDriver:_release()
    if type(self.actions.releaseAll) == "function" then pcall(self.actions.releaseAll) end
end

function PracticeTaskDriver:_cancelRetry()
    local handle = self.retryHandle
    self.retryHandle = nil
    if handle == nil then return end
    if type(self.cancelDelay) == "function" then pcall(self.cancelDelay, handle)
    elseif type(handle) == "table" and type(handle.Cancel) == "function" then pcall(handle.Cancel, handle) end
end

function PracticeTaskDriver:_inRange()
    if type(self.isInRange) == "function" then return self.isInRange() == true end
    local fighter = self.getFighter()
    local data = fighter and fighter.Data
    return type(data) == "table" and data.IsInShootingRange == true
end

function PracticeTaskDriver:_equippedName()
    local fighter = self.getFighter()
    local item = fighter and fighter.EquippedItem
    return item and (item.Name or item.name) or nil
end

function PracticeTaskDriver:_schedule()
    if type(self.delay) ~= "function" or self.attempts >= self.maxAttempts then
        if self.attempts >= self.maxAttempts then self.state = "retry-exhausted"; self:_notify() end
        return
    end
    local generation = self.generation
    local handle
    handle = self.delay(self.retryDelay, function()
        if handle == self.retryHandle then self.retryHandle = nil end
        if self.stopped or self.paused or generation ~= self.generation then return end
        self:_reconcile()
    end)
    self.retryHandle = handle
end

function PracticeTaskDriver:_dispatch(name, ...)
    if self.attempts >= self.maxAttempts then self.state = "retry-exhausted"; self:_notify(); return end
    local action = self.actions[name]
    if type(action) ~= "function" then self.state = "unsupported-boundary"; self:_notify(); return end
    self.attempts += 1
    local ok, accepted = pcall(action, ...)
    if not ok or accepted == false then self.state = "action-rejected"; self:_schedule(); self:_notify(); return end
    self.state = "waiting-native"
    self:_schedule()
    self:_notify()
end

function PracticeTaskDriver:_reconcile()
    if self.stopped or self.paused then return end
    local taskRecord = self.task
    local kind = taskRecord and PRACTICE_TASKS[taskRecord.name]
    if not kind then self.state = "idle"; self:_notify(); return end
    if not self:_inRange() then self:_dispatch("enterRange"); return end
    if kind == "range" then self.state = "waiting-native"; self:_notify(); return end
    if kind == "targets" then self.state = "target-combat"; self:_notify(); return end
    if kind == "slide" then self:_dispatch("slide"); return end
    if kind == "equip" then
        if self:_equippedName() == "Scythe" then self.state = "waiting-native"; self:_notify()
        else self:_dispatch("equip", "Scythe") end
        return
    end
    if kind == "dash" then
        if self:_equippedName() ~= "Scythe" then self:_dispatch("equip", "Scythe")
        else self:_dispatch("secondary") end
        return
    end
    if kind == "grenade" then
        if self:_equippedName() ~= "Grenade" then self:_dispatch("equip", "Grenade")
        else self:_dispatch("primary") end
    end
end

function PracticeTaskDriver:setTask(taskRecord)
    if self.stopped then return end
    local signature = taskRecord and (tostring(taskRecord.name) .. ":" .. tostring(taskRecord.progress or 0)) or nil
    self:_cancelRetry()
    self.generation += 1
    self:_release()
    if signature ~= self.taskSignature then self.attempts = 0 end
    self.task = taskRecord
    self.taskSignature = signature
    self:_reconcile()
end

function PracticeTaskDriver:isCombatActive()
    return not self.stopped and not self.paused and self.task ~= nil
        and self.task.name == "Beginner2" and self:_inRange()
end

function PracticeTaskDriver:status()
    return { state = self.state, attempts = self.attempts, task = self.task }
end

function PracticeTaskDriver:setChanged(callback)
    self.onChanged = callback
end

function PracticeTaskDriver:pause()
    if self.stopped or self.paused then return end
    self.paused = true
    self:_cancelRetry(); self.generation += 1; self:_release(); self.state = "paused"; self:_notify()
end

function PracticeTaskDriver:resume()
    if self.stopped or not self.paused then return end
    self.paused = false
    self:_reconcile()
end

function PracticeTaskDriver:stop()
    if self.stopped then return end
    self.stopped = true
    self:_cancelRetry(); self.generation += 1; self:_release(); self.task = nil; self.state = "stopped"; self:_notify()
    for _, connection in ipairs(self.connections) do disconnect(connection) end
    table.clear(self.connections)
end

return PracticeTaskDriver
