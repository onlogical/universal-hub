local AnimeExpeditions = {}

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
