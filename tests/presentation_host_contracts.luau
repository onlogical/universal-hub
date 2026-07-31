local fs = require("@lune/fs")

local expectedPresentations = {
    counterblox = "games/counterblox/Presentation",
    rivals = "games/rivals/Presentation",
    town = "games/town/Presentation",
}

local function recorder(capabilities)
    local calls = {}
    local available = {}
    for _, capability in ipairs(capabilities) do
        available[capability] = true
    end
    local host = {}
    function host:supports(name)
        return available[name] == true
    end
    for _, method in ipairs({
        "aim",
        "cosmetics",
        "option",
        "plotCopy",
        "rate",
        "section",
    }) do
        host[method] = function(_, ...)
            local values = { method }
            for _, value in ipairs({ ... }) do
                if type(value) == "string" or type(value) == "number" then
                    table.insert(values, value)
                end
            end
            table.insert(calls, table.concat(values, ":"))
        end
    end
    return host, calls
end

local function mount(path, capabilities)
    local host, calls = recorder(capabilities)
    local presentation = require("../" .. path)
    assert(type(presentation) == "table" and type(presentation.mount) == "function")
    presentation.mount(host)
    return calls
end

local function assertSequence(actual, expected, label)
    assert(#actual == #expected, label .. " call count changed")
    for index, value in ipairs(expected) do
        assert(
            actual[index] == value,
            ("%s call %d changed: expected %q, got %q"):format(
                label,
                index,
                value,
                tostring(actual[index])
            )
        )
    end
end

local CounterbloxDefinition = require("../games/counterblox/Definition")
local RivalsDefinition = require("../games/rivals/Definition")
local TownDefinition = require("../games/town/Definition")
for id, definition in pairs({
    counterblox = CounterbloxDefinition,
    rivals = RivalsDefinition,
    town = TownDefinition,
}) do
    assert(definition.presentation == expectedPresentations[id])
    assert(table.find(definition.sources, definition.presentation))
    local presentationSource = fs.readFile(definition.presentation .. ".lua")
    for _, forbidden in ipairs({
        "Drawing",
        "DrawingImmediate",
        "Limn",
        "Canvas",
        "Element",
        "surface",
    }) do
        assert(
            not presentationSource:find(forbidden, 1, true),
            definition.presentation .. " must not access presentation runtime internals: " .. forbidden
        )
    end
end

assertSequence(
    mount(expectedPresentations.rivals, RivalsDefinition.features.capabilities),
    {
        "aim",
        "rate:aimSmoothness:Aim Smoothness",
        "rate:headshotRate:Headshot Rate",
        "rate:missRate:Miss Rate",
        "section:rage:AIM",
        "option:rage:1:silentAim:Camera Aim",
        "option:rage:1:shotAim:Silent Aim",
        "option:rage:2:humanAim:Human Aim:silentAim",
        "option:rage:3:triggerBot:Trigger Bot",
        "option:rage:3:alwaysScoped:Always Scoped",
        "section:movement:MOVEMENT",
        "option:movement:1:bhop:Bunny Hop",
        "section:world:WORLD",
        "option:world:1:autoPickup:Auto Pickup",
        "section:visuals:VISUALS",
        "option:visuals:1:boxes:Hitboxes",
        "option:visuals:1:chams:Chams",
        "option:visuals:2:names:Names",
        "option:visuals:2:health:Health",
        "option:visuals:3:weapon:Weapons",
        "option:visuals:3:noFlash:No Flash",
        "option:visuals:4:noSmoke:No Smoke",
        "option:visuals:5:utilityEsp:Utility ESP",
        "cosmetics",
    },
    "RIVALS presentation"
)

assertSequence(
    mount(expectedPresentations.counterblox, CounterbloxDefinition.features.capabilities),
    {
        "aim",
        "rate:headshotRate:Headshot Rate",
        "rate:missRate:Miss Rate",
        "section:rage:AIM",
        "option:rage:1:silentAim:Silent Aim",
        "option:rage:1:wallbang:Wallbang:silentAim",
        "option:rage:2:rapidFire:Rapid Fire",
        "option:rage:3:triggerBot:Trigger Bot",
        "option:rage:3:noSpread:No Spread",
        "option:rage:4:noRecoil:No Recoil",
        "option:rage:4:noWeaponSlow:No Weapon Slow",
        "section:melee:MELEE",
        "option:melee:1:knifeAura:Knife Aura",
        "option:melee:1:microStep:Micro Step:knifeAura",
        "section:movement:MOVEMENT",
        "option:movement:1:spinBot:Spin Bot",
        "option:movement:1:bhop:Bunny Hop",
        "section:visuals:VISUALS",
        "option:visuals:1:boxes:Hitboxes",
        "option:visuals:1:chams:Chams",
        "option:visuals:2:names:Names",
        "option:visuals:2:health:Health",
        "option:visuals:3:weapon:Weapons",
        "option:visuals:4:bombTimer:Bomb Timer",
        "option:visuals:5:utilityEsp:Utility ESP",
        "cosmetics",
    },
    "Counterblox presentation"
)

assertSequence(
    mount(expectedPresentations.town, TownDefinition.features.capabilities),
    {
        "aim",
        "plotCopy",
        "cosmetics",
    },
    "Town presentation"
)

local hostSource = fs.readFile("modules/PresentationHost.lua")
assert(not hostSource:find("Drawing", 1, true), "PresentationHost must not depend on raw Drawing")
assert(not hostSource:find("Limn", 1, true), "PresentationHost must not become another Limn abstraction")
local townPresentationSource = fs.readFile("games/town/Presentation.lua")
for _, action in ipairs({
    "cancelPlotCopy",
    "cleanupPlotCopyCheckpoint",
    "confirmPlotCopy",
    "copyPlot",
    "discardPlotCopy",
    "resumePlotCopy",
    "retryPlotCopyCleanup",
}) do
    assert(
        townPresentationSource:find(action, 1, true),
        "Town presentation must own its custom action: " .. action
    )
    assert(
        not hostSource:find('"' .. action .. '"', 1, true),
        "PresentationHost must not own Town action selection: " .. action
    )
end

local overlaySource = fs.readFile("modules/Overlay.lua")
for _, forbidden in ipairs({
    "OPTION_GROUPS",
    "OPTION_LABELS",
    "OPTION_PARENTS",
    "RATE_CONTROLS",
    "PLOT COPY",
    "Copy & Save",
    "COSMETICS",
    "Auto Pickup",
    "Always Scoped",
    "Knife Aura",
    "No Weapon Slow",
}) do
    assert(
        not overlaySource:find(forbidden, 1, true),
        "Overlay must not own game presentation content: " .. forbidden
    )
end

local initSource = fs.readFile("init.lua")
assert(
    initSource:find("import(adapterDefinition.presentation)", 1, true),
    "Init must import only the selected definition's presentation"
)
for _, path in pairs(expectedPresentations) do
    assert(
        not initSource:find('"' .. path .. '"', 1, true),
        "Init must not hand-maintain presentation imports"
    )
end

print("presentation-host-contracts-ok")
