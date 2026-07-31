local fs = require("@lune/fs")
local Registry = require("../modules/Registry")

local expectedCatalog = {
    "games/counterblox/Definition",
    "games/rivals/Definition",
    "games/town/Definition",
}

local expectedDefaults = {
    aimSmoothness = 0,
    autoPickup = false,
    bhop = false,
    boxes = true,
    bombTimer = true,
    chams = true,
    fov = 180,
    fovCircle = true,
    fullScreenAim = false,
    gloveColorOverride = false,
    gloveOverride = false,
    headshotRate = 0,
    health = true,
    humanAim = false,
    knifeAura = false,
    maximumFov = 500,
    microStep = false,
    minimumFov = 40,
    missRate = 0,
    names = true,
    noFlash = false,
    noRecoil = false,
    noSmoke = false,
    noSpread = false,
    noWeaponSlow = false,
    rapidFire = false,
    alwaysScoped = false,
    shotAim = false,
    silentAim = false,
    skinOverrides = {},
    spinBot = false,
    triggerBot = false,
    utilityEsp = true,
    wallbang = false,
    weapon = true,
}

local expectedInitialState = {
    activeWeapon = nil,
    activeWeaponKind = nil,
    cosmeticWeapon = nil,
    cosmetics = {
        maximumWear = 1,
        minimumWear = 0,
        skin = "Stock",
        skinCount = 1,
        skinIndex = 1,
        statTrak = false,
        supportsStatTrak = false,
        wear = 0,
        weapon = nil,
    },
    cosmeticMode = "weapon",
    cosmeticsOpen = false,
    error = nil,
    menuVisible = true,
    observations = {},
    plotCopy = {
        active = false,
        confirmedProgress = 0,
        context = "",
        phase = "Ready",
        state = "idle",
    },
    bombObservation = {
        visible = false,
    },
    utilityObservations = {},
    gloves = {
        maximumWear = 1,
        minimumWear = 0,
        skin = "Game equipped",
        skinCount = 1,
        skinIndex = 0,
        wear = 0,
        weapon = "Gloves",
    },
}

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function assertDataOnly(value, path, seen)
    local valueType = type(value)
    assert(
        valueType == "nil"
            or valueType == "boolean"
            or valueType == "number"
            or valueType == "string"
            or valueType == "table",
        path .. " must contain only data"
    )
    if valueType ~= "table" then
        return
    end

    seen = seen or {}
    assert(not seen[value], path .. " must not contain cycles")
    seen[value] = true
    for key, child in pairs(value) do
        assertDataOnly(key, path .. " key", seen)
        assertDataOnly(child, path .. "." .. tostring(key), seen)
    end
    seen[value] = nil
end

local Catalog = require("../games/Catalog")
assert(deepEqual(Catalog, expectedCatalog), "Catalog order and definition paths must remain explicit")

local definitions = {}
for _, path in ipairs(Catalog) do
    local definition = require("../" .. path)
    assertDataOnly(definition, path)
    Registry.Validate(definition)
    assert(definition.factory == nil and definition.match == nil, path .. " must not contain runtime callbacks")
    assert(deepEqual(definition.defaults, expectedDefaults), path .. " must own the existing config defaults")
    assert(
        deepEqual(definition.initialState, expectedInitialState),
        path .. " must preserve the selected-game initial state shape"
    )
    assert(fs.isFile(path .. ".lua"), path .. " must resolve to a definition source")
    assert(fs.isFile(definition.module .. ".lua"), path .. " must resolve to its behavior module")
    for _, source in ipairs(definition.sources) do
        assert(fs.isFile(source .. ".lua"), path .. " declares a missing source: " .. source)
    end
    definitions[definition.id] = definition
end

assert(#Catalog == 3, "Universal Hub must expose exactly the current three games")
assert(definitions.counterblox.label == "Counterblox")
assert(definitions.counterblox.module == "games/Counterblox")
assert(deepEqual(definitions.counterblox.hydroxide, { "targeting" }))
assert(definitions.counterblox.features.cosmetics == nil)
assert(table.find(definitions.counterblox.features.capabilities, "wallbang"))

assert(definitions.rivals.label == "RIVALS")
assert(definitions.rivals.module == "games/rivals/Adapter")
assert(deepEqual(definitions.rivals.hydroxide, { "targeting" }))
assert(definitions.rivals.features.cosmetics == false)
assert(definitions.rivals.features.optionLabels.silentAim == "Camera Aim")
assert(deepEqual(definitions.rivals.features.exclusiveOptions.shotAim, { "silentAim", "humanAim" }))
assert(not table.find(definitions.rivals.features.capabilities, "wallbang"))

assert(definitions.town.label == "Town")
assert(definitions.town.module == "games/Town")
assert(deepEqual(definitions.town.hydroxide, {}))
assert(definitions.town.features.cosmetics == false)
assert(deepEqual(definitions.town.features.capabilities, { "plotCopy" }))

local registry = Registry.new()
for _, path in ipairs(Catalog) do
    registry:Register(require("../" .. path))
end
assert(registry:Resolve({ gameId = 7633926880, placeId = 114234929420007 }).id == "counterblox")
assert(registry:Resolve({ gameId = 6035872082, placeId = 17625359962 }).id == "rivals")
assert(registry:Resolve({ gameId = 6035872082, placeId = 133215910299950 }).id == "rivals")
assert(registry:Resolve({ gameId = 1718755273, placeId = 4991214437 }).id == "town")

for _, path in ipairs({
    "games/Counterblox.lua",
    "games/rivals/Adapter.lua",
    "games/Town.lua",
}) do
    local source = fs.readFile(path)
    assert(not source:find(".factory =", 1, true), path .. " must not expose registration metadata")
    assert(not source:find(".sources =", 1, true), path .. " must not expose source inventory metadata")
end

print("catalog-contracts-ok")
