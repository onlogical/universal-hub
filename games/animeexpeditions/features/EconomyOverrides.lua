local EconomyOverrides = {}
EconomyOverrides.__index = EconomyOverrides

local function unitsOf(information)
    return information and information.Units or {}
end

function EconomyOverrides.new(information)
    assert(type(information) == "table", "Economy Overrides requires Information")
    return setmetatable({
        information = information,
        originalCosts = {},
        originalLimits = {},
        unlimitedPlacement = false,
        zeroCosts = false,
    }, EconomyOverrides)
end

function EconomyOverrides:_applyCosts()
    for _, unit in pairs(unitsOf(self.information)) do
        for _, upgrade in pairs(unit.UpgradeInfo or {}) do
            if type(upgrade) == "table" and type(upgrade.Cost) == "number" then
                if self.originalCosts[upgrade] == nil then
                    self.originalCosts[upgrade] = upgrade.Cost
                end
                upgrade.Cost = 0
            end
        end
    end
end

function EconomyOverrides:_restoreCosts()
    for upgrade, cost in pairs(self.originalCosts) do
        upgrade.Cost = cost
    end
    table.clear(self.originalCosts)
end

function EconomyOverrides:_applyLimits()
    for _, unit in pairs(unitsOf(self.information)) do
        if type(unit) == "table" and type(unit.PlacementLimit) == "number" then
            if self.originalLimits[unit] == nil then
                self.originalLimits[unit] = unit.PlacementLimit
            end
            unit.PlacementLimit = math.huge
        end
    end
end

function EconomyOverrides:_restoreLimits()
    for unit, limit in pairs(self.originalLimits) do
        unit.PlacementLimit = limit
    end
    table.clear(self.originalLimits)
end

function EconomyOverrides:setZeroCosts(enabled)
    enabled = enabled == true
    self.zeroCosts = enabled
    if enabled then
        self:_applyCosts()
    else
        self:_restoreCosts()
    end
end

function EconomyOverrides:setUnlimitedPlacement(enabled)
    enabled = enabled == true
    self.unlimitedPlacement = enabled
    if enabled then
        self:_applyLimits()
    else
        self:_restoreLimits()
    end
end

function EconomyOverrides:stop()
    self.zeroCosts = false
    self.unlimitedPlacement = false
    self:_restoreCosts()
    self:_restoreLimits()
end

return EconomyOverrides
