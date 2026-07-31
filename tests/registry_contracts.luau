local Registry = require("../modules/Registry")

local function definition(id, options)
    options = options or {}
    return {
        composition = options.composition,
        defaults = options.defaults or {},
        factory = options.factory or function() end,
        features = options.features or {
            capabilities = {},
        },
        hydroxide = options.hydroxide or {},
        id = id,
        initialState = options.initialState or {},
        label = options.label or id,
        manifest = options.manifest or {
            gameIds = options.gameIds,
            placeIds = options.placeIds,
        },
        match = options.match,
        module = options.module,
        presentation = options.presentation,
        sources = options.sources or {},
    }
end

local function expectError(fragment, callback)
    local succeeded, message = pcall(callback)
    assert(not succeeded, "Expected registration failure containing " .. fragment)
    assert(
        tostring(message):find(fragment, 1, true),
        ("Expected %q in %q"):format(fragment, tostring(message))
    )
end

expectError("Game definition must be a table", function()
    Registry.Validate(false)
end)
expectError("non-empty id", function()
    Registry.Validate(definition(""))
end)
expectError("non-empty label", function()
    Registry.Validate(definition("missing-label", {
        label = "",
    }))
end)
expectError("requires a manifest", function()
    local candidate = definition("missing-manifest")
    candidate.manifest = nil
    Registry.Validate(candidate)
end)
expectError("numeric gameId or placeId", function()
    Registry.Validate(definition("empty-manifest"))
end)
expectError("positive integer", function()
    Registry.Validate(definition("bad-place", {
        placeIds = { "20" },
    }))
end)
expectError("exactly one module or factory", function()
    local candidate = definition("missing-constructor", {
        gameIds = { 10 },
    })
    candidate.factory = nil
    Registry.Validate(candidate)
end)
expectError("exactly one module or factory", function()
    Registry.Validate(definition("two-constructors", {
        gameIds = { 10 },
        module = "games/Two",
        sources = { "games/Two" },
    }))
end)
expectError("sources must be a table", function()
    local candidate = definition("missing-sources", {
        gameIds = { 10 },
    })
    candidate.sources = nil
    Registry.Validate(candidate)
end)
expectError("defaults must be a table", function()
    local candidate = definition("missing-defaults", {
        gameIds = { 10 },
    })
    candidate.defaults = nil
    Registry.Validate(candidate)
end)
expectError("initialState must be a table", function()
    local candidate = definition("missing-state", {
        gameIds = { 10 },
    })
    candidate.initialState = nil
    Registry.Validate(candidate)
end)
expectError("features must be a table", function()
    local candidate = definition("missing-features", {
        gameIds = { 10 },
    })
    candidate.features = nil
    Registry.Validate(candidate)
end)
expectError("capabilities must be a table", function()
    local candidate = definition("missing-capabilities", {
        gameIds = { 10 },
    })
    candidate.features.capabilities = nil
    Registry.Validate(candidate)
end)
expectError("Hydroxide requirements must be a table", function()
    local candidate = definition("missing-hydroxide", {
        gameIds = { 10 },
    })
    candidate.hydroxide = nil
    Registry.Validate(candidate)
end)
expectError("duplicate source", function()
    local candidate = definition("duplicate-source", {
        gameIds = { 10 },
    })
    candidate.sources = { "games/One", "games/One" }
    Registry.Validate(candidate)
end)
expectError("without .lua", function()
    local candidate = definition("source-extension", {
        gameIds = { 10 },
    })
    candidate.sources = { "games/One.lua" }
    Registry.Validate(candidate)
end)
expectError("must include its module", function()
    local candidate = definition("missing-module-source", {
        gameIds = { 10 },
    })
    candidate.factory = nil
    candidate.module = "games/One"
    candidate.presentation = "games/OnePresentation"
    candidate.sources = { "games/OneHelper", "games/OnePresentation" }
    Registry.Validate(candidate)
end)
expectError("presentation must be a valid source path", function()
    local candidate = definition("missing-presentation", {
        gameIds = { 10 },
    })
    candidate.factory = nil
    candidate.module = "games/One"
    candidate.sources = { "games/One" }
    Registry.Validate(candidate)
end)
expectError("must include its presentation", function()
    local candidate = definition("missing-presentation-source", {
        gameIds = { 10 },
    })
    candidate.factory = nil
    candidate.module = "games/One"
    candidate.presentation = "games/OnePresentation"
    candidate.sources = { "games/One" }
    Registry.Validate(candidate)
end)
expectError("composition must be a valid source path", function()
    local candidate = definition("invalid-composition", {
        composition = "../games/Composition",
        gameIds = { 10 },
    })
    candidate.factory = nil
    candidate.module = "games/One"
    candidate.presentation = "games/OnePresentation"
    candidate.sources = { "games/One", "games/OnePresentation" }
    Registry.Validate(candidate)
end)
expectError("must include its composition", function()
    local candidate = definition("missing-composition-source", {
        composition = "games/OneComposition",
        gameIds = { 10 },
    })
    candidate.factory = nil
    candidate.module = "games/One"
    candidate.presentation = "games/OnePresentation"
    candidate.sources = { "games/One", "games/OnePresentation" }
    Registry.Validate(candidate)
end)

local registry = Registry.new()
registry:Register(definition("universe", {
    gameIds = { 10 },
}))
registry:Register(definition("place", {
    placeIds = { 20 },
}))
expectError("Duplicate game definition id: place", function()
    registry:Register(definition("place", {
        placeIds = { 21 },
    }))
end)

local placeAdapter, placeScore = registry:Resolve({
    gameId = 10,
    placeId = 20,
})
assert(placeAdapter.id == "place" and placeScore == 200, "Place match must override universe match")

local universeAdapter, universeScore = registry:Resolve({
    gameId = 10,
    placeId = 99,
})
assert(universeAdapter.id == "universe" and universeScore == 100)

local missing, missingScore = registry:Resolve({
    gameId = 999,
    placeId = 999,
})
assert(missing == nil and missingScore == 0, "Unsupported games must not pick an adapter")

local listed = registry:List()
assert(listed[1].id == "place" and listed[2].id == "universe", "Adapter listing must be stable")

local customRegistry = Registry.new()
customRegistry:Register(definition("boolean", {
    gameIds = { 30 },
    match = function(context)
        return context.placeId == 31
    end,
}))
customRegistry:Register(definition("numeric", {
    gameIds = { 30 },
    match = function(context)
        return context.placeId == 32 and 7 or false
    end,
}))
local booleanMatch, booleanScore = customRegistry:Resolve({
    gameId = 0,
    placeId = 31,
})
assert(booleanMatch.id == "boolean" and booleanScore == 1)
local numericMatch, numericScore = customRegistry:Resolve({
    gameId = 0,
    placeId = 32,
})
assert(numericMatch.id == "numeric" and numericScore == 7)

local function ambiguous(first, second)
    local ambiguousRegistry = Registry.new()
    ambiguousRegistry:Register(definition(first, {
        gameIds = { 40 },
    }))
    ambiguousRegistry:Register(definition(second, {
        gameIds = { 40 },
    }))
    expectError("Ambiguous game definitions at score 100: alpha, zeta", function()
        ambiguousRegistry:Resolve({
            gameId = 40,
            placeId = 0,
        })
    end)
end
ambiguous("zeta", "alpha")
ambiguous("alpha", "zeta")

print("registry-contracts-ok")
