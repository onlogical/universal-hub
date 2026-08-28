return {
    buildId = [[32cfc07a]],
    id = [[animeexpeditions]],
    sources = {
        ["games/AnimeExpeditions.lua"] = [[local AnimeExpeditions = {}

local EconomyOverrides = require("games/animeexpeditions/features/EconomyOverrides")

function AnimeExpeditions.new(context)
    assert(type(context) == "table", "Anime Expeditions adapter requires context")
    assert(context.store, "Anime Expeditions requires a reactive store")

    local information = context.animeExpeditionsInformation
    if not information then
        local replicatedStorage = game:GetService("ReplicatedStorage")
        information = require(replicatedStorage.Shared.Information)
    end

    local overrides = EconomyOverrides.new(information)
    local unsubscribe = context.store:Subscribe(function(state)
        local settings = state.settings or {}
        overrides:setZeroCosts(settings.zeroUnitCosts)
        overrides:setUnlimitedPlacement(settings.unlimitedPlacement)
    end)

    local stopped = false
    local self = {
        capabilities = {
            "animeExpeditionsReady",
            "unlimitedPlacement",
            "zeroUnitCosts",
        },
    }

    function self:stop()
        if stopped then
            return
        end
        stopped = true
        unsubscribe()
        overrides:stop()
    end

    function self:isStopped()
        return stopped
    end

    return self
end

return AnimeExpeditions
]],
        ["games/animeexpeditions/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    host:section("Tools", "animeexpeditions", "ANIME EXPEDITIONS", 70)
    host:option("animeexpeditions", 1, "zeroUnitCosts", "Zero Unit Costs")
    host:option(
        "animeexpeditions",
        2,
        "unlimitedPlacement",
        "Unlimited Placement (Experimental)"
    )
    host:option("animeexpeditions", 3, "animeExpeditionsReady", "Hub Loaded")
end

return Presentation
]],
        ["games/animeexpeditions/features/EconomyOverrides.lua"] = [[local EconomyOverrides = {}
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
]],
    },
}
