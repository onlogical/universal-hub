return {
    defaults = {
        antiHit = false,
        autoOpenEggs = false,
        instantPrompts = false,
    },
    features = {
        capabilities = {
            "antiHit",
            "autoOpenEggs",
            "instantPrompts",
        },
        cosmetics = false,
    },
    hydroxide = {},
    id = "stealanegg",
    initialState = {},
    label = "Steal An Egg",
    manifest = {
        gameIds = { 10563114921 },
        placeIds = { 107778070777162 },
    },
    module = "games/stealanegg/Adapter",
    presentation = "games/stealanegg/Presentation",
    sources = {
        "games/stealanegg/Adapter",
        "games/stealanegg/Presentation",
        "games/stealanegg/features/AntiHit",
        "games/stealanegg/features/AutoOpenEggs",
        "games/stealanegg/features/InstantPrompts",
    },
}
