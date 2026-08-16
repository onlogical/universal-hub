local fs = require("@lune/fs")

local function read(path)
    return fs.readFile(path)
end

local function contains(source, needle, message)
    assert(string.find(source, needle, 1, true), message or ("missing: " .. needle))
end

local compatibility = read("games/Compatibility.lua")
contains(compatibility, 'worldRenderer = "limn"', "Limn must remain the default renderer")
contains(compatibility, "chamsExcludeAccessories = false")
contains(compatibility, "chamsPerPart = false")
contains(compatibility, "showTeammates = false", "Teammate ESP must remain opt-in")

local world = read("ui/esp/WorldRenderer.lua")
contains(world, 'settings.worldRenderer == "native"')
contains(world, "self.highlights:render(observations)")
contains(world, "self.drawing:render(remainder or {}", "Highlights mode must preserve Drawing-only observations")
contains(world, "self.highlights:destroy()")
contains(world, "self.drawing:destroy()")

local rivalsAdapter = read("games/rivals/Adapter.lua")
contains(rivalsAdapter, "or overlayVisualsEnabled", "Highlight ESP must still observe names, health, and weapons")
contains(rivalsAdapter, "context.render(visualObservations", "Native ESP must keep publishing visual observations")
assert(not string.find(rivalsAdapter, "renderObservations", 1, true),
    "Native ESP must not drop visual observations before render")

local overlay = read("ui/esp/DrawingRenderer.lua")
contains(overlay, "observation.tone", "Classic ESP must consume the generic player-tone seam")
contains(overlay, "COLORS.team", "Classic ESP must render a distinct generic team tone")

local init = read("init.lua")
contains(init, 'import("ui/esp/HighlightRenderer")')
contains(init, 'import("ui/esp/WorldRenderer")')
contains(init, "worldOverlay:setPolicy(adapter.worldPolicy", "Adapters must configure the generic policy seam")
contains(init, "guiParent = uiParent", "Highlight instances must share the gethui parent")

local inventory = read("modules/Sources.lua")
contains(inventory, '"ui/esp/HighlightRenderer"')
contains(inventory, '"ui/esp/WorldRenderer"')

for _, path in ipairs({
    "games/rivals/Definition.lua",
    "games/bloxstrike/Definition.lua",
}) do
    local definition = read(path)
    contains(definition, '"worldRenderer"', path .. " must expose renderer selection")
    contains(definition, '"showTeammates"', path .. " must expose opt-in teammate ESP")
    contains(definition, '"chamsExcludeAccessories"')
    contains(definition, '"chamsPerPart"')
end

for _, path in ipairs({
    "games/rivals/Presentation.lua",
    "games/bloxstrike/Presentation.lua",
}) do
    local presentation = read(path)
    contains(presentation, 'id = "worldRenderer"')
    contains(presentation, 'value = "limn"')
    contains(presentation, 'value = "native"')
    contains(presentation, '"chamsExcludeAccessories"')
    contains(presentation, '"chamsPerPart"')
    contains(presentation, 'setting = "worldRenderer", equals = "native"')
    contains(presentation, '"showTeammates"', path .. " must expose the compact Visuals toggle")
end

local catalog = read("ui/presentation/Catalog.lua")
contains(catalog, 'type(option.visibility) == "table"')
contains(catalog, "option.visibility.whenParent")

local tactical = read("games/Counterblox.lua")
contains(tactical, "self.worldPolicy = {")
contains(tactical, "isPlayerEligible = isOpponent")
contains(tactical, "getPlayerTone = playerTone", "Shared tactical native ESP must expose team relationship, not game-specific colors")
contains(tactical, "getWeapon = function(player)")
contains(tactical, 'GetAttributeChangedSignal("CurrentEquipped")')

print("world-renderer-contracts-ok")
