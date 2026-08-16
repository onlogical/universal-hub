local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local ItemPolicy = importDependency("games/rivals/libraries/ItemPolicy", "../libraries/ItemPolicy")
local TaskCounterPolicy = {}
TaskCounterPolicy.__index = TaskCounterPolicy

function TaskCounterPolicy.isDefensiveItem(item)
    return ItemPolicy.isDeflector(item) or ItemPolicy.isAbsorber(item)
end

function TaskCounterPolicy.hasShieldOrKatana(items)
    for key, value in pairs(items or {}) do
        local item = type(value) == "table" and value or type(key) == "table" and key or nil
        if TaskCounterPolicy.isDefensiveItem(item) then return true end
    end
    return false
end

function TaskCounterPolicy.shouldSelectSpray(items)
    return TaskCounterPolicy.hasShieldOrKatana(items)
end

function TaskCounterPolicy.shouldForceSpray(item, opponentEquippedItem)
    return ItemPolicy.isTrueDamage(item)
        and TaskCounterPolicy.isDefensiveItem(opponentEquippedItem)
end

function TaskCounterPolicy.new(options)
    return setmetatable({
        clock = options and options.clock or os.clock,
        candidate = false,
        candidateAt = 0,
        active = false,
    }, TaskCounterPolicy)
end

function TaskCounterPolicy:update(equippedItem)
    local now = self.clock()
    local candidate = TaskCounterPolicy.isDefensiveItem(equippedItem)
    if candidate ~= self.candidate then
        self.candidate = candidate
        self.candidateAt = now
    end
    local hold = candidate and 1.25 or 0.75
    if candidate ~= self.active and now - self.candidateAt >= hold then
        self.active = candidate
    end
    return self.active
end

return TaskCounterPolicy
