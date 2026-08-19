local NoScope = {}
NoScope.__index = NoScope

function NoScope.new()
    return setmetatable({ active = false }, NoScope)
end

function NoScope:update(enabled, firearm, profile)
    local shouldScope = enabled == true and profile and profile.scoped == true
    if shouldScope then
        firearm:setScoped(true)
        self.active = true
    elseif self.active then
        firearm:setScoped(false)
        self.active = false
    end
end

function NoScope:stop(firearm)
    if self.active then firearm:setScoped(false) end
    self.active = false
end

return NoScope
