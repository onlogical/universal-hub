local roblox = require("@lune/roblox")
Enum = roblox.Enum
Color3 = roblox.Color3

local Catalog = require("../ui/presentation/Catalog")
local Presentation = require("../games/rivals/Presentation")

local settings = {
    aimSmoothness = 0,
    headshotRate = 100,
    missRate = 0,
    silentAim = false,
    shotAim = false,
    humanAim = false,
    triggerBot = false,
    alwaysScoped = false,
    fov = 58,
    minimumFov = 40,
    maximumFov = 500,
    fullScreenAim = false,
    boxes = true,
    chams = true,
    chamsExcludeAccessories = false,
    chamsPerPart = false,
    names = true,
    health = true,
    weapon = true,
    worldRenderer = "limn",
    espOutlineColor = "",
    espFillColor = "",
    espNameColor = "",
    espWeaponColor = "",
    espHealthLowColor = "",
    espHealthHighColor = "",
    espFillAlpha = -1,
}
local state = { menuVisible = true, settings = settings }
local writes = {}
local store = {}
function store:Get()
    return state
end
function store:Patch(patch)
    for key, value in pairs(patch) do
        state[key] = value
    end
end

local catalog = Catalog.new({
    store = store,
    capabilities = {
        "silentAim", "shotAim", "humanAim", "triggerBot", "alwaysScoped",
        "aimSmoothness", "headshotRate", "missRate", "boxes", "chams",
        "chamsExcludeAccessories", "chamsPerPart", "names", "health", "weapon", "worldRenderer",
    },
    setSetting = function(id, value)
        settings[id] = value
    end,
    setOption = function(id, value)
        settings[id] = value
        if id == "shotAim" and value then
            settings.silentAim = false
            settings.humanAim = false
        elseif id == "silentAim" and value then
            settings.shotAim = false
        end
        table.insert(writes, { id, value })
    end,
    setRate = function() end,
    setFov = function() end,
    getPreviewKey = function()
        return "preview-key"
    end,
    getPreviewSubject = function()
        return { marker = "preview-subject" }
    end,
})
Presentation.mount(catalog)
local model = catalog:model(state)
local combat = model.pages[1]
assert(combat.id == "Combat")
local expected = { "aimMode", "response", "targeting", "trigger" }
for index, id in ipairs(expected) do
    assert(combat.sections[index].id == id, "RIVALS Combat hierarchy changed at " .. index)
end
assert(combat.sections[1].controls[1].kind == "segmented")
assert(combat.sections[1].controls[1].value == "off")
assert(combat.sections[2].controls[1].emphasis == "row")
assert(combat.sections[4].label == "Trigger Bot")

model.onValueChange("aimMode", "camera", true)
assert(#writes == 2 and writes[1][1] == "shotAim" and writes[1][2] == false)
assert(writes[2][1] == "silentAim" and writes[2][2] == true)
model = catalog:model(state)
assert(model.pages[1].sections[1].controls[1].value == "camera")
assert(#model.pages[1].sections[1].controls == 2)
assert(model.pages[1].sections[1].controls[2].id == "humanAim")
assert(model.pages[1].sections[4].id == "trigger")

model.onValueChange("humanAim", true, true)
assert(settings.humanAim == true)
model.onValueChange("aimMode", "silent", true)
assert(writes[4][1] == "silentAim" and writes[4][2] == false)
assert(writes[5][1] == "shotAim" and writes[5][2] == true)
assert(settings.humanAim == false)
model = catalog:model(state)
assert(model.pages[1].sections[1].controls[1].value == "silent")
assert(#model.pages[1].sections == 4)
assert(#model.pages[1].sections[1].controls == 1)
assert(model.pages[1].sections[4].id == "trigger")

model.onValueChange("aimMode", "camera", true)
assert(writes[8][1] == "humanAim" and writes[8][2] == true)
assert(settings.humanAim == true)
model = catalog:model(state)
assert(model.pages[1].sections[1].controls[1].value == "camera")
assert(model.pages[1].sections[1].controls[2].id == "humanAim")
assert(model.pages[1].sections[1].controls[2].value == true)

local visuals
for _, page in ipairs(model.pages) do
    if page.id == "Visuals" then
        visuals = page
        break
    end
end
assert(visuals and visuals.layout == "toggle-grid")
assert(visuals.preview.kind == "character" and visuals.preview.key == "preview-key")
assert(visuals.preview.resolve().marker == "preview-subject")
assert(visuals.preview.worldRenderer == "limn" and visuals.preview.chams == true)
assert(#visuals.preview.palette.relationships == 2)
local enemyPalette = visuals.preview.palette.relationships[1]
local teammatePalette = visuals.preview.palette.relationships[2]
assert(enemyPalette.id == "enemy" and teammatePalette.id == "teammate")
assert(#enemyPalette.targets == 6 and enemyPalette.fillAlpha == 0.18)
model.onValueChange("espColor:enemy:outline", "#123456", true)
model.onValueChange("espAlpha:enemy", 0.73, true)
assert(settings.espEnemyOutlineColor == "#123456" and settings.espEnemyFillAlpha == 0.73)
model = catalog:model(state)
for _, page in ipairs(model.pages) do
    if page.id == "Visuals" then visuals = page break end
end
enemyPalette = visuals.preview.palette.relationships[1]
assert(enemyPalette.targets[1].color == Color3.fromRGB(18, 52, 86))
assert(enemyPalette.fillAlpha == 0.73)
local rendererSection
local visualSection
for _, section in ipairs(visuals.sections) do
    if section.id == "worldRenderer" then
        rendererSection = section
    elseif section.id == "visuals" then
        visualSection = section
    end
end
assert(rendererSection and rendererSection.label == "ESP")
assert(rendererSection.controls[1].label == "Style" and rendererSection.controls[1].value == "limn")
assert(visualSection and #visualSection.controls == 5, "Native-only Chams options must stay hidden in Classic mode")
model.onValueChange("worldRenderer", "native", true)
assert(settings.worldRenderer == "native", "Renderer selection must preserve its string setting")
model = catalog:model(state)
for _, page in ipairs(model.pages) do
    if page.id == "Visuals" then
        visuals = page
        break
    end
end
for _, section in ipairs(visuals.sections) do
    if section.id == "visuals" then
        visualSection = section
        break
    end
end
assert(visuals.preview.worldRenderer == "native")
assert(#visualSection.controls == 7, "Native Chams sub-options must appear only in Native mode")

local cosmeticState = {
    menuVisible = true,
    settings = { boxes = false, menuKey = "RightShift" },
    cosmetics = {
        minimumWear = 0,
        maximumWear = 1,
        skin = "Fade",
        skinLabel = "Fade",
        wear = 0.2,
        weapon = "Karambit",
        statTrak = true,
        supportsStatTrak = true,
    },
    gloves = {
        minimumWear = 0,
        maximumWear = 1,
        skin = "Vice",
        wear = 0.1,
        weapon = "Sports Gloves",
    },
}
local cosmeticStore = {}
function cosmeticStore:Get()
    return cosmeticState
end
function cosmeticStore:Patch() end
local cosmeticCatalog = Catalog.new({
    store = cosmeticStore,
    capabilities = { "boxes" },
    setOption = function() end,
    setRate = function() end,
    setFov = function() end,
    getWeaponPreviewKey = function()
        return "weapon-preview-key"
    end,
    getWeaponPreviewSubject = function()
        return { marker = "weapon-preview" }
    end,
})
cosmeticCatalog:page("Visuals", { layout = "toggle-grid" })
cosmeticCatalog:section("Visuals", "visuals", "VISUALS", 70)
cosmeticCatalog:option("visuals", 1, "boxes", "Hitboxes")
cosmeticCatalog:cosmetics()
local cosmeticModel = cosmeticCatalog:model(cosmeticState)
local cosmeticVisuals
for _, page in ipairs(cosmeticModel.pages) do
    assert(page.id ~= "Tools", "Cosmetics must not create a Tools tab")
    if page.id == "Visuals" then
        cosmeticVisuals = page
    end
end
assert(cosmeticVisuals and cosmeticVisuals.sections[2].id == "skin-changer")
assert(cosmeticVisuals.sections[3].id == "glove-changer")
local viewer = cosmeticVisuals.sections[2].controls[1]
assert(viewer.kind == "model-viewer" and viewer.key == "weapon-preview-key")
assert(viewer.resolve().marker == "weapon-preview")

print("native-catalog-contracts-ok")
