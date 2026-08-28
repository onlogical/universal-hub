return {
    defaults = {
        animeExpeditionsReady = true,
        unlimitedPlacement = false,
        zeroUnitCosts = false,
    },
    features = {
        capabilities = {
            "animeExpeditionsReady",
            "unlimitedPlacement",
            "zeroUnitCosts",
        },
        cosmetics = false,
    },
    hydroxide = {},
    id = "animeexpeditions",
    initialState = {},
    label = "Anime Expeditions",
    manifest = {
        gameIds = { 7613921865 },
        placeIds = { 84515722934860 },
    },
    module = "games/AnimeExpeditions",
    presentation = "games/animeexpeditions/Presentation",
    sources = {
        "games/AnimeExpeditions",
        "games/animeexpeditions/Presentation",
        "games/animeexpeditions/features/EconomyOverrides",
    },
}
