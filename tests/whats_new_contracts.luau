local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
Color3 = roblox.Color3
Enum = roblox.Enum
UDim = roblox.UDim
UDim2 = roblox.UDim2
Vector2 = roblox.Vector2
typeof = function(value)
    if type(value) == "userdata" or type(value) == "table" then
        local ok, className = pcall(function()
            return value.ClassName
        end)
        if ok and type(className) == "string" then
            return "Instance"
        end
    end
    return type(value)
end

local Changelog = require("../modules/Changelog")
local WhatsNew = require("../ui/WhatsNew")
local Catalog = require("../ui/presentation/Catalog")
local Store = require("../modules/Store")

local whatsNewSource = fs.readFile("ui/WhatsNew.lua")
assert(not whatsNewSource:find("ScreenGui", 1, true), "What's New must not own a sibling ScreenGui")
assert(not whatsNewSource:find("WhatsNew.mount", 1, true), "What's New must not mount a custom overlay")

local menuSource = fs.readFile("ui/src/UniversalHubMenu.tsx")
assert(menuSource:find("WhatsNewModal", 1, true), "Shell must mount the extracted What's New modal")

local modalSource = fs.readFile("ui/src/components/WhatsNewModal.tsx")
assert(modalSource:find("from \"@prism\"", 1, true) or modalSource:find("from '@prism'", 1, true))
assert(modalSource:find("Modal", 1, true), "What's New must use the Prism Modal")
assert(modalSource:find("whatsNewDismiss", 1, true))
assert(modalSource:find("whatsNewDontShowAgain", 1, true))
assert(modalSource:find("whatsNewViewAll", 1, true))
assert(modalSource:find("whatsNewAcknowledge", 1, true))
assert(modalSource:find("closeOnBackdropClick", 1, true), "Backdrop dismiss must follow Prism Modal conventions")
assert(modalSource:find('label="Got it"', 1, true))
assert(modalSource:find("Don't show again", 1, true))
assert(modalSource:find("View all", 1, true))

local contracts = fs.readFile("ui/src/contracts.ts")
assert(contracts:find("export interface WhatsNewModel", 1, true))
assert(contracts:find("readonly whatsNew?: WhatsNewModel", 1, true))
assert(contracts:find("readonly displayVersion?: string", 1, true))
assert(contracts:find('readonly channel?: "beta" | "released"', 1, true))

local overlaySource = fs.readFile("ui/Menu.lua")
assert(overlaySource:find("displayVersion", 1, true))
assert(overlaySource:find(" · Beta", 1, true))
assert(overlaySource:find('Name = "Bullet"', 1, true), "What's New items must render as bullets")
assert(overlaySource:find('Name = "Tab"', 1, true), "What's New must group features by menu tab")
assert(overlaySource:find(' .. " - " .. feature.note', 1, true), "What's New feature notes stay on the same bullet")
assert(not overlaySource:find("→", 1, true), "What's New must not use unicode arrows")
assert(not overlaySource:find("›", 1, true), "What's New must not use unicode arrows")
assert(not overlaySource:find(" / ", 1, true), "What's New must not join tab and feature with a slash")

assert(WhatsNew.DEFAULT_PATH == "universal-hub/last-used-version.json")
assert(WhatsNew.PAGES_CHANGELOG_URL == "https://3xjn.github.io/universal-hub/changelog.json")

local catalog = Changelog.validate({
    current = "0.3.0",
    releases = {
        {
            version = "0.3.0",
            date = "2026-08-15",
            title = "What's New",
            added = { "Upgrade popup" },
        },
        {
            version = "0.2.0",
            date = "2026-07-30",
            title = "Native Prism menu",
            added = { "Prism native menu" },
        },
    },
})

local first = WhatsNew.evaluate({
    catalog = catalog,
    lastUsed = WhatsNew.defaults(),
})
assert(first.shouldShow == true)
assert(first.current == "0.3.0")
assert(#first.entries == 2)

local current = WhatsNew.evaluate({
    catalog = catalog,
    lastUsed = { version = "0.3.0", suppressPopups = false },
})
assert(current.shouldShow == false)

local upgrade = WhatsNew.evaluate({
    catalog = catalog,
    lastUsed = { version = "0.2.0" },
})
assert(upgrade.shouldShow == true)
assert(upgrade.previous == "0.2.0")
assert(#upgrade.entries == 1)
assert(upgrade.entries[1].version == "0.3.0")

local suppressed = WhatsNew.evaluate({
    catalog = catalog,
    lastUsed = { version = "0.2.0", suppressPopups = true },
})
assert(suppressed.shouldShow == false)
assert(suppressed.suppressPopups == true)

assert(WhatsNew.evaluate({}).shouldShow == false)

local acknowledged = WhatsNew.acknowledge("0.3.0")
assert(acknowledged.version == "0.3.0" and acknowledged.suppressPopups == false)
local muted = WhatsNew.acknowledge("0.3.0", true)
assert(muted.suppressPopups == true)

local snapshot = WhatsNew.snapshot(upgrade)
assert(snapshot.visible == true)
assert(snapshot.current == "0.3.0")
assert(snapshot.showingAll == false)
assert(#snapshot.entries == 1)
assert(#snapshot.history == 2)
assert(#snapshot.timeline == 2)
assert(#snapshot.lanes == 2)
assert(#snapshot.board == 2)
assert(#snapshot.outline == 2)
assert(#snapshot.guide == 2)
assert(#snapshot.pack == 2)
assert(snapshot.pack[1].version == "0.3.0")

local model = WhatsNew.model(snapshot)
assert(model.visible == true)
assert(model.current == "0.3.0")
assert(model.previous == "0.2.0")
assert(#model.entries == 1)
assert(model.entries[1].title == "What's New")
assert(model.entries[1].body:find("Upgrade popup", 1, true))
assert(model.entries[1].sections[1].id == "added")
assert(model.entries[1].sections[1].label == "New features")
assert(#model.releases == 2)
assert(model.releases[1].displayVersion == "0.3.0-beta")
assert(model.releases[1].channel == "beta")
assert(model.fresh["0.3.0"] == true)

local liveCatalog = Changelog.decode(fs.readFile("changelog.json"), function(source)
    return serde.decode("json", source)
end)
local liveNotice = WhatsNew.evaluate({
    catalog = liveCatalog,
    lastUsed = WhatsNew.defaults(),
})
local liveModel = WhatsNew.model(WhatsNew.snapshot(liveNotice))
assert(liveModel.releases[1].displayVersion == "0.3.0-beta")
assert(liveModel.releases[1].channel == "beta")
assert(liveModel.releases[2].displayVersion == "0.2.0-beta")
assert(liveModel.releases[1].sections[1].groups[1].tab == "Rage")
assert(liveModel.releases[1].sections[1].groups[1].items[1].name == "Warp")
assert(liveModel.releases[1].sections[1].groups[1].items[1].note:find("hops around", 1, true))
assert(liveModel.releases[1].sections[1].groups[2] == nil)
assert(not liveModel.releases[1].body:find("Auto Counter", 1, true))
assert(liveModel.releases[1].body:find("Rage", 1, true))
assert(not liveModel.releases[1].body:find("→", 1, true))

local staleMerged = WhatsNew.model({
    visible = true,
    current = "0.3.0",
    previous = "0.2.0",
    showingAll = false,
    entries = snapshot.entries,
    catalog = {
        current = "0.3.0",
        releases = {
            {
                version = "0.3.0",
                date = "2026-08-15",
                title = "Warp",
                added = { "Warp" },
                changed = { "Private matches leave the loadout to you" },
            },
        },
    },
    history = {
        snapshot.history[1],
        snapshot.history[2],
        {
            version = "0.1.0",
            date = "2026-08-15",
            title = "What's New",
            added = { "What's New on execute" },
        },
    },
    timeline = snapshot.timeline,
    lanes = snapshot.lanes,
    board = snapshot.board,
    outline = snapshot.outline,
    guide = snapshot.guide,
    pack = snapshot.pack,
})
assert(#staleMerged.releases == 2)
assert(staleMerged.releases[1].title == "What's New")
assert(staleMerged.releases[2].title == "Native Prism menu")
assert(not staleMerged.releases[1].body:find("Private matches", 1, true), "What's New must prefer a fresh timeline over a merged catalog")

local expanded = WhatsNew.model({
    visible = true,
    current = "0.3.0",
    previous = "0.2.0",
    showingAll = true,
    entries = snapshot.entries,
    catalog = catalog,
})
assert(#expanded.entries == 2)
assert(expanded.showingAll == true)

local store = Store.new({
    settings = {
        menuKey = "RightShift",
        fov = 180,
        minimumFov = 40,
        maximumFov = 400,
    },
    menuVisible = true,
    whatsNew = snapshot,
})
local host = Catalog.new({
    store = store,
    capabilities = {},
    whatsNewDismiss = function() end,
    whatsNewDontShowAgain = function() end,
    whatsNewViewAll = function() end,
    whatsNewAcknowledge = function() end,
})
local menuModel = host:model(store:Get())
assert(menuModel.whatsNew.visible == true)
assert(menuModel.whatsNew.current == "0.3.0")
assert(#menuModel.whatsNew.entries == 1)
assert(type(menuModel.onAction) == "function")

print("whats-new-contracts-ok")
