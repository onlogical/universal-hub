local TaskLoadout = {}
TaskLoadout.__index = TaskLoadout

local SLOT_NAMES = { "Primary", "Secondary", "Melee" }

local function restoreExecutorThread()
    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
end

local function weaponName(value)
    if type(value) == "string" then
        return value
    end
    if type(value) == "table" then
        local name = value.Name or value.name or value.Id or value.id
        return type(name) == "string" and name or nil
    end
    return nil
end

local function chosenTable(page)
    if type(page) ~= "table" then
        return nil
    end
    local chosen = page._chosen_weapons or page.ChosenWeapons or page.chosenWeapons
    return type(chosen) == "table" and chosen or nil
end

local function chosenAt(page, index)
    local chosen = chosenTable(page)
    if not chosen then
        return nil
    end
    return weaponName(chosen[index]) or weaponName(chosen[SLOT_NAMES[index]])
end

function TaskLoadout.new(options)
    options = options or {}
    return setmetatable({
        accepted = {},
        clock = options.clock or os.clock,
        constants = options.constants,
        finished = false,
        getOpponentFighter = options.getOpponentFighter,
        getStatus = options.getStatus,
        index = 1,
        nextAt = 0,
        page = options.page,
        plan = nil,
        taskCounterPolicy = options.taskCounterPolicy,
        taskDebug = options.taskDebug or {},
        taskPolicy = options.taskPolicy,
        wasOpen = false,
    }, TaskLoadout)
end

function TaskLoadout:armed()
    local status = type(self.getStatus) == "function" and self.getStatus()
    if type(status) ~= "table" then
        return false
    end
    return status.paused ~= true
        and status.task ~= nil
        and status.state ~= "idle"
        and status.state ~= "stopped"
        and status.state ~= "paused"
end

function TaskLoadout:stop()
    self.plan = nil
    self.index = 1
    self.nextAt = 0
    self.wasOpen = false
    self.finished = false
    table.clear(self.accepted)
end

function TaskLoadout:defaultPlan(secondary)
    local defaults = type(self.constants) == "table" and self.constants.DEFAULT_WEAPONS
    if type(defaults) ~= "table" then
        return nil
    end
    local plan = {}
    for index, name in ipairs(defaults) do
        if type(name) == "string" then
            plan[index] = name
        end
    end
    if #plan == 0 then
        for _, key in ipairs(SLOT_NAMES) do
            local name = defaults[key]
            if type(name) == "string" then
                table.insert(plan, name)
            end
        end
    end
    if type(secondary) == "string" then
        if #plan >= 2 then
            plan[2] = secondary
        elseif #plan == 1 then
            plan[2] = secondary
        end
    end
    return #plan > 0 and plan or nil
end

function TaskLoadout:_slotReady(index, desired)
    return self.accepted[index] == desired or chosenAt(self.page, index) == desired
end

function TaskLoadout:_planComplete()
    local plan = self.plan
    if type(plan) ~= "table" or #plan == 0 then
        return false
    end
    for index, desired in ipairs(plan) do
        if not self:_slotReady(index, desired) then
            return false
        end
    end
    return true
end

function TaskLoadout:_submit()
    local page = self.page
    if type(page.Finish) ~= "function" or self.finished then
        return
    end
    if not self:_planComplete() then
        self.taskDebug.loadoutStage = "waiting-slots"
        return
    end
    restoreExecutorThread()
    pcall(page.Finish, page)
    self.finished = true
    self.taskDebug.counterLoadout = tostring(self.plan[1]) .. " + " .. tostring(self.plan[2])
    self.taskDebug.loadoutStage = "submitted"
end

function TaskLoadout:poll()
    restoreExecutorThread()
    local page = self.page
    if not page or not page:IsOpen() then
        if self.wasOpen then
            self:stop()
        end
        return
    end
    if not self:armed() then
        if self.wasOpen or self.plan then
            self:stop()
        end
        self.taskDebug.loadoutStage = "player-pick"
        return
    end
    if not self.wasOpen then
        self.wasOpen = true
        self.plan = nil
        self.index = 1
        self.nextAt = 0
        self.finished = false
        table.clear(self.accepted)
        self.taskDebug.loadoutStage = "reading-opponent"
        self.taskDebug.loadoutError = nil
    end
    self.taskDebug.loadoutHeartbeat = self.clock()
    if not self.plan then
        local opponentFighter = self.getOpponentFighter and self.getOpponentFighter()
        local opponentItems = opponentFighter and opponentFighter.Items or {}
        local useCounter = self.taskCounterPolicy.shouldSelectSpray(opponentItems)
        self.plan = self:defaultPlan(useCounter and "Spray" or nil)
        if not self.plan then
            self.taskDebug.loadoutStage = "waiting-defaults"
            return
        end
        self.taskDebug.loadoutStage = useCounter and "selecting-counter" or "selecting-default"
    end
    while self.plan[self.index] and self:_slotReady(self.index, self.plan[self.index]) do
        self.index += 1
        self.nextAt = 0
    end
    if not self.plan[self.index] then
        self:_submit()
        return
    end
    if self.clock() < self.nextAt then
        return
    end
    if type(page.PickWeapon) ~= "function" then
        self.taskDebug.loadoutStage = "error"
        self.taskDebug.loadoutError = "PickWeapon unavailable"
        return
    end
    local desired = self.plan[self.index]
    self.taskDebug.loadoutStage = "picking-" .. desired
    restoreExecutorThread()
    local succeeded, loadoutError = pcall(page.PickWeapon, page, self.index, desired)
    if not succeeded then
        self.taskDebug.loadoutStage = "error"
        self.taskDebug.loadoutError = tostring(loadoutError)
        self.nextAt = self.clock() + 0.12
        return
    end
    self.accepted[self.index] = desired
    self.nextAt = self.clock() + 0.12
end

return TaskLoadout
