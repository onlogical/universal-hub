local TaskPolicy = {}

local DEFAULT_GROUPS = { "Tasks", "BonusTasks", "EventTasks", "SpecialChallenges", "LimitedTasks" }
local GROUP_PRIORITY = {
    Tasks = 1,
    LimitedTasks = 2,
    SpecialChallenges = 3,
    EventTasks = 4,
    BonusTasks = 5,
}

local function read(controller, key)
    if type(controller) ~= "table" then
        return nil
    end
    if type(controller.Get) == "function" then
        local ok, result = pcall(controller.Get, controller, key)
        if ok then
            return result
        end
    end
    local data = controller.Data
    if type(data) == "table" then
        return data[key]
    end
    return controller[key]
end

local function copyRecord(record, fallbackName, group, info)
    if type(record) ~= "table" then
        return nil
    end
    local name = record.Name or record.Id or record.ID or fallbackName
    if type(name) ~= "string" then
        return nil
    end
    local metadata = type(info) == "table" and info[name] or nil
    local normalized = {
        name = name,
        id = name,
        group = group,
        title = record.Title or (metadata and metadata.Title) or name,
        progress = record.Progress,
        goal = record.Goal or (metadata and metadata.Goal),
        completed = record.Completed == true,
        locked = record.Locked == true or record.Unlocked == false or record.IsLocked == true,
        native = record,
    }
    -- Preserve the native values: a goal is metadata, not permission to invent progress.
    return normalized
end

function TaskPolicy.snapshot(taskLibrary, playerDataController)
    if
        type(playerDataController) == "table"
        and playerDataController.TASKS_DATA_NAMES
        and not (type(taskLibrary) == "table" and taskLibrary.TASKS_DATA_NAMES)
    then
        taskLibrary, playerDataController = playerDataController, taskLibrary
    end
    if type(taskLibrary) == "table" and taskLibrary.taskLibrary then
        playerDataController = taskLibrary.playerDataController
        taskLibrary = taskLibrary.taskLibrary
    end
    taskLibrary = taskLibrary or {}
    local groups = taskLibrary.TASKS_DATA_NAMES or DEFAULT_GROUPS
    local result = {}
    for _, group in ipairs(groups) do
        local records = read(playerDataController, group)
        if type(records) == "table" then
            local added = {}
            for index, record in ipairs(records) do
                local normalized = copyRecord(record, nil, group, taskLibrary.Info)
                if normalized then
                    table.insert(result, normalized)
                    added[index] = true
                end
            end
            local keys = {}
            for key, _ in pairs(records) do
                if not added[key] and type(key) ~= "number" then
                    table.insert(keys, key)
                end
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, key in ipairs(keys) do
                local normalized = copyRecord(records[key], key, group, taskLibrary.Info)
                if normalized then
                    table.insert(result, normalized)
                end
            end
        end
    end
    return result
end

local RANGE_FAMILY = {
    Beginner1 = "range",
    Beginner2 = "targets",
    Beginner3 = "slide",
    Beginner4 = "equip",
    Beginner5 = "dash",
    Beginner6 = "grenade",
}
local BEGINNER_PVP = { Beginner7 = "play", Beginner8 = "eliminations", Beginner9 = "wins" }

local function pvpFamily(name, title)
    local beginner = BEGINNER_PVP[name]
    if beginner then
        return beginner
    end
    local text = string.lower((name or "") .. " " .. (title or ""))
    if string.find(text, "eliminat", 1, true) or string.find(text, " kill", 1, true) then
        return "eliminations"
    end
    if string.find(text, "streak", 1, true) then
        return "streaks"
    end
    if string.find(text, "win", 1, true) then
        return "wins"
    end
    if string.find(text, "round", 1, true) then
        return "rounds"
    end
    if
        string.find(text, "duel", 1, true)
        or string.find(text, "match", 1, true)
        or string.find(text, "play", 1, true)
    then
        return "play"
    end
    return nil
end

function TaskPolicy.classify(task)
    if type(task) ~= "table" then
        return nil
    end
    local name = task.name or task.Name or task.id
    local title = task.title or task.Title
    local rangeFamily = RANGE_FAMILY[name]
    if rangeFamily then
        return {
            kind = "range",
            type = "range",
            family = rangeFamily,
            supported = true,
            requiresCombat = false,
        }
    end
    local family = pvpFamily(name, title)
    if family then
        local group = task.group or task.Group
        local lower = string.lower((name or "") .. " " .. (title or ""))
        local variant = string.find(lower, "event", 1, true) and "event"
            or string.find(lower, "limited", 1, true) and "limited"
            or (group == "EventTasks" and "event")
            or (group == "LimitedTasks" and "limited")
            or nil
        return {
            kind = "pvp",
            type = "pvp",
            family = family,
            variant = variant,
            scope = variant,
            supported = true,
            requiresCombat = true,
            event = variant == "event",
            limited = variant == "limited",
        }
    end
    return { kind = "unsupported", type = "unsupported", supported = false, requiresCombat = false }
end

local function sortKey(task)
    local beginner = tonumber(string.match(task.name or "", "^Beginner(%d+)$"))
    return GROUP_PRIORITY[task.group] or 99, beginner or math.huge, task.name or ""
end

function TaskPolicy.select(tasks)
    local candidates = {}
    for _, task in ipairs(tasks or {}) do
        local classification = TaskPolicy.classify(task)
        if
            task.completed ~= true
            and task.Completed ~= true
            and not task.locked
            and classification
            and classification.supported
        then
            task.classification = classification
            table.insert(candidates, task)
        end
    end
    table.sort(candidates, function(a, b)
        local ag, ai, an = sortKey(a)
        local bg, bi, bn = sortKey(b)
        if ag ~= bg then
            return ag < bg
        end
        if ai ~= bi then
            return ai < bi
        end
        return an < bn
    end)
    return candidates[1]
end

function TaskPolicy.requiresCombat(task)
    local classification = task and (task.classification or TaskPolicy.classify(task))
    return classification ~= nil and classification.kind == "pvp"
end

TaskPolicy.GROUP_PRIORITY = GROUP_PRIORITY
return TaskPolicy
