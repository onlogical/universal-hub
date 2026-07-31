local fs = require("@lune/fs")
local Compatibility = require("../../games/Compatibility")
local Registry = require("../../modules/Registry")
local SourceInventory = require("../../modules/SourceInventory")
local PresentationHost = require("../../modules/PresentationHost")

local Catalog = require("../fixtures/simplegame/Catalog")
assert(#Catalog == 1, "Simple game fixture must add exactly one catalog entry")

local definition = Compatibility.Compose(require("../fixtures/simplegame/Definition"))
Registry.Validate(definition)
assert(definition.composition == nil, "A simple game must not require a composition module")
assert(definition.defaults.triggerBot == true, "Sparse game defaults must override compatibility defaults")
assert(definition.defaults.boxes == true, "Shared compatibility defaults must be composed")
assert(definition.initialState.status == "Simple Game idle", "Sparse initial state must override compatibility state")
assert(definition.initialState.cosmetics.skin == "Stock", "Shared compatibility state must be composed")

local registry = Registry.new()
registry:Register(definition)
assert(registry:Resolve({
    gameId = 987654321,
    placeId = 0,
}).id == "simplegame", "Simple game catalog entry must resolve through Registry")

local inventory = SourceInventory.new({
    catalog = Catalog,
    definitions = { definition },
})
local allowed = inventory:Allow("simplegame")
assert(allowed["tests/fixtures/simplegame/Definition"], "Selected scope must include its catalog definition")
assert(allowed["tests/fixtures/simplegame/Adapter"], "Selected scope must include its adapter")
assert(allowed["tests/fixtures/simplegame/Presentation"], "Selected scope must include its presentation")

local adapter = require("../fixtures/simplegame/Adapter").new({})
assert(type(adapter.stop) == "function", "Simple adapter must satisfy the cleanup seam")

local mounted = false
local facade = {
    action = function() end,
    patch = function() end,
    read = function() end,
    register = function()
        mounted = true
    end,
}
PresentationHost.mount(facade, require("../fixtures/simplegame/Presentation"))
assert(not mounted, "A simple game may mount without optional panels")

for _, productionPath in ipairs({
    "hub.lua",
    "init.lua",
    "modules/PresentationHost.lua",
    "games/Catalog.lua",
    "tests/catalog_contracts.luau",
    "tests/presentation_host_contracts.luau",
}) do
    assert(
        not fs.readFile(productionPath):find("simplegame", 1, true),
        productionPath .. " must not need a simple-game compatibility edit"
    )
end
local checkSource = fs.readFile("scripts/check.sh")
assert(
    checkSource:find("tests/game_onboarding/*.luau", 1, true),
    "New game onboarding tests must be discovered without check-runner edits"
)
assert(
    not checkSource:find("simplegame", 1, true),
    "The check runner must not name individual onboarded games"
)

print("simple-game-contracts-ok")
