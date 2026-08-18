return {
    defaults = {
        autoDodge = false,
        autoFight = false,
        autoParry = false,
        wallPhase = false,
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
            "autoFight",
            "autoDodge",
            "autoParry",
            "wallPhase",
        },
        exclusiveOptions = {
            autoDodge = { "autoParry" },
            autoParry = { "autoDodge" },
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
