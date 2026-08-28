local Presentation = {}

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
