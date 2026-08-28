local AnimeExpeditions = {}

function AnimeExpeditions.new(context)
    assert(type(context) == "table", "Anime Expeditions adapter requires context")
    assert(context.store, "Anime Expeditions requires a reactive store")

    local stopped = false
    local self = {
        capabilities = { "animeExpeditionsReady" },
    }

    function self:stop()
        stopped = true
    end

    function self:isStopped()
        return stopped
    end

    return self
end

return AnimeExpeditions
