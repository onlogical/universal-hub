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

local unit = {
    PlacementLimit = 3,
    UpgradeInfo = {
        [0] = { Cost = 900 },
        [1] = { Cost = 1300 },
    },
}
local listener
local unsubscribed = false
local adapter = require("../../games/AnimeExpeditions").new({
    animeExpeditionsInformation = {
        Units = { TestUnit = unit },
    },
    store = {
        Subscribe = function(_, callback)
            listener = callback
            callback({ settings = {} })
            return function()
                unsubscribed = true
            end
        end,
    },
})
assert(type(adapter.stop) == "function", "Anime Expeditions must expose its cleanup seam")

listener({ settings = { unlimitedPlacement = true, zeroUnitCosts = true } })
assert(unit.PlacementLimit == math.huge, "Unlimited Placement must remove the client cap")
assert(unit.UpgradeInfo[0].Cost == 0, "Zero Unit Costs must clear placement costs")
assert(unit.UpgradeInfo[1].Cost == 0, "Zero Unit Costs must clear upgrade costs")

listener({ settings = { unlimitedPlacement = false, zeroUnitCosts = false } })
assert(unit.PlacementLimit == 3, "Unlimited Placement must restore the original cap")
assert(unit.UpgradeInfo[0].Cost == 900, "Zero Unit Costs must restore placement costs")
assert(unit.UpgradeInfo[1].Cost == 1300, "Zero Unit Costs must restore upgrade costs")

adapter:stop()
assert(adapter:isStopped(), "Anime Expeditions cleanup must be observable")
assert(unsubscribed, "Anime Expeditions cleanup must unsubscribe from settings")

print("anime-expeditions-contracts-ok")
