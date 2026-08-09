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

local world = read("modules/WorldRenderer.lua")
contains(world, 'settings.worldRenderer == "native"')
contains(world, "self.native:render(observations)")
contains(world, "self.limn:render(remainder or {}", "Native mode must preserve Limn-only observations")
contains(world, "self.native:destroy()")
contains(world, "self.limn:destroy()")

local overlay = read("modules/Overlay.lua")
contains(overlay, "observation.tone", "Classic ESP must consume the generic player-tone seam")
contains(overlay, "COLORS.team", "Classic ESP must render a distinct generic team tone")

local init = read("init.lua")
contains(init, 'import("modules/NativeWorldRenderer")')
contains(init, 'import("modules/WorldRenderer")')
contains(init, "worldOverlay:setPolicy(adapter.worldPolicy", "Adapters must configure the generic policy seam")
contains(init, "guiParent = uiParent", "Native instances must share the gethui parent")

local inventory = read("modules/SourceInventory.lua")
contains(inventory, '"modules/NativeWorldRenderer"')
contains(inventory, '"modules/WorldRenderer"')

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

local catalog = read("modules/presentation/Catalog.lua")
contains(catalog, 'type(option.visibility) == "table"')
contains(catalog, "option.visibility.whenParent")

local tactical = read("games/Counterblox.lua")
contains(tactical, "self.worldPolicy = {")
contains(tactical, "isPlayerEligible = isOpponent")
contains(tactical, "getPlayerTone = playerTone", "Shared tactical native ESP must expose team relationship, not game-specific colors")
contains(tactical, "getWeapon = function(player)")
contains(tactical, 'GetAttributeChangedSignal("CurrentEquipped")')

print("world-renderer-contracts-ok")
