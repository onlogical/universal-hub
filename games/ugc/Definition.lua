return {
    defaults = {
        autoParry = false,
        autoParryDelay = 0.05,
        autoParryRange = 25,
    },
    features = {
        capabilities = {
            "boxes",
            "chams",
            "chamsExcludeAccessories",
            "chamsPerPart",
            "showEnemies",
            "worldRenderer",
            "names",
            "health",
            "autoParry",
            "autoParryRange",
            "autoParryDelay",
        },
        cosmetics = false,
    },
    hydroxide = { "targeting" },
    id = "ugc",
    initialState = {},
    label = "Ugc",
    manifest = {
        gameIds = { 9051406594 },
        placeIds = { 94217045453265 },
    },
    module = "games/Ugc",
    presentation = "games/ugc/Presentation",
    sources = {
        "games/Ugc",
        "games/ugc/Presentation",
    },
}
