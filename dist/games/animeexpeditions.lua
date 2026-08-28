return {
    buildId = [[64f70c03]],
    id = [[animeexpeditions]],
    sources = {
        ["games/AnimeExpeditions.lua"] = [[local AnimeExpeditions = {}

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
]],
        ["games/animeexpeditions/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    host:section("Tools", "animeexpeditions", "ANIME EXPEDITIONS", 70)
    host:option("animeexpeditions", 1, "animeExpeditionsReady", "Hub Loaded")
end

return Presentation
]],
    },
}
