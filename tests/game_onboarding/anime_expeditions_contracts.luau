local Compatibility = require("../../games/Compatibility")
local Registry = require("../../modules/Registry")

local definition = Compatibility.Compose(require("../../games/animeexpeditions/Definition"))
Registry.Validate(definition)

assert(definition.id == "animeexpeditions", "Anime Expeditions must use its stable catalog id")
assert(definition.label == "Anime Expeditions", "Anime Expeditions must use its public game name")
assert(
    table.find(definition.manifest.gameIds, 7613921865),
    "Anime Expeditions must match its Roblox universe"
)
assert(
    table.find(definition.manifest.placeIds, 84515722934860),
    "Anime Expeditions must match its current place"
)

local registry = Registry.new()
registry:Register(definition)
assert(
    registry:Resolve({ gameId = 7613921865, placeId = 84515722934860 }).id
        == "animeexpeditions",
    "Anime Expeditions must resolve from the live Roblox identifiers"
)

local adapter = require("../../games/AnimeExpeditions").new({
    store = {},
})
assert(type(adapter.stop) == "function", "Anime Expeditions must expose its cleanup seam")
adapter:stop()
assert(adapter:isStopped(), "Anime Expeditions cleanup must be observable")

print("anime-expeditions-contracts-ok")
