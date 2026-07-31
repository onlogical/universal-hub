return {
    composition = "games/town/Composition",
    defaults = {},
    features = {
        capabilities = {
            "plotCopy",
        },
        cosmetics = false,
    },
    hydroxide = {},
    id = "town",
    initialState = {},
    label = "Town",
    manifest = {
        gameIds = { 1718755273 },
        placeIds = { 4991214437 },
    },
    module = "games/Town",
    presentation = "games/town/Presentation",
    sources = {
        "games/Town",
        "games/town/Canonical",
        "games/town/CheckpointStore",
        "games/town/Composition",
        "games/town/CopyEngine",
        "games/town/CopyPlan",
        "games/town/ExecutionPlan",
        "games/town/Presentation",
    },
}
