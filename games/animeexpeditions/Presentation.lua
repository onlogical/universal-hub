local Presentation = {}

function Presentation.mount(host)
    host:section("Tools", "animeexpeditions", "ANIME EXPEDITIONS", 70)
    host:option("animeexpeditions", 1, "animeExpeditionsReady", "Hub Loaded")
end

return Presentation
