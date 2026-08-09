local TaskCounterPolicy = {}
TaskCounterPolicy.__index = TaskCounterPolicy

local function itemName(item)
    local info = type(item) == "table" and item.Info
    return type(info) == "table" and info.Name or type(item) == "table" and item.Name or nil
end

function TaskCounterPolicy.hasShieldOrKatana(items)
    for key, value in pairs(items or {}) do
        local item = type(value) == "table" and value or type(key) == "table" and key or nil
        local name = itemName(item)
        if name == "Riot Shield" or name == "Katana" then return true end
    end
    return false
end

function TaskCounterPolicy.shouldForceSpray(item, opponentItems)
    return type(item) == "table"
        and item.Name == "Spray"
        and TaskCounterPolicy.hasShieldOrKatana(opponentItems)
end

function TaskCounterPolicy.new(options)
    return setmetatable({clock=options and options.clock or os.clock,candidate=false,candidateAt=0,active=false},TaskCounterPolicy)
end

function TaskCounterPolicy:update(items)
    local now=self.clock() local candidate=TaskCounterPolicy.hasShieldOrKatana(items)
    if candidate~=self.candidate then self.candidate=candidate self.candidateAt=now end
    local hold=candidate and 0.5 or 1.25
    if candidate~=self.active and now-self.candidateAt>=hold then self.active=candidate end
    return self.active
end

return TaskCounterPolicy
