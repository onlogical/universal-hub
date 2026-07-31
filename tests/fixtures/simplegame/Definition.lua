return {
    id = "simplegame",
    label = "Simple Game",
    manifest = {
        gameIds = { 987654321 },
        placeIds = {},
    },
    module = "tests/fixtures/simplegame/Adapter",
    presentation = "tests/fixtures/simplegame/Presentation",
    sources = {
        "tests/fixtures/simplegame/Adapter",
        "tests/fixtures/simplegame/Presentation",
    },
    defaults = {
        triggerBot = true,
    },
    initialState = {
        simpleGame = {
            mode = "idle",
        },
        status = "Simple Game idle",
    },
    features = {
        capabilities = {},
        cosmetics = false,
    },
    hydroxide = {},
}
