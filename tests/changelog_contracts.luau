local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Changelog = require("../modules/Changelog")

local function decode(source)
    return serde.decode("json", source)
end

assert(Changelog.compare("0.1.0", "0.0.9") == 1)
assert(Changelog.compare("1.0.0", "1.0.0") == 0)
assert(Changelog.compare("1.2.0", "1.10.0") == -1)
assert(Changelog.isNewer("0.2.0", "0.1.9"))
assert(Changelog.parseVersion("")[1] == 0)
assert(Changelog.parseVersion(nil)[3] == 0)
assert(Changelog.parseVersion("1.2") == nil)

local catalog = Changelog.decode(fs.readFile("changelog.json"), decode)
assert(catalog.current == "0.3.0")
assert(catalog.releases[1].version == "0.3.0")
assert(catalog.releases[1].title == "Warp")
assert(catalog.releases[1].added[1].tab == "Rage")
assert(catalog.releases[1].added[1].name == "Warp")
assert(catalog.releases[1].added[1].note:find("hops around your opponent", 1, true))
assert(not catalog.releases[1].added[1].note:find("orbit", 1, true))
assert(catalog.releases[1].added[2] == nil)
assert(not Changelog.entryText(catalog.releases[1].added[1]):find("Auto Counter", 1, true))
assert(catalog.releases[1].fixed[1].tab == "Combat")
assert(catalog.releases[1].fixed[1].name == "Trigger Bot")
assert(catalog.releases[1].fixed[1].note:find("uses line of sight, not just who's on screen", 1, true))
assert(catalog.releases[1].fixed[2].tab == "Movement")
assert(catalog.releases[1].fixed[2].name == "Wall Noclip")
assert(catalog.releases[1].fixed[2].note:find("stays put when the menu opens", 1, true))
assert(catalog.releases[1].fixed[3] == nil)
assert(not Changelog.entryText(catalog.releases[1].fixed[2]):find("Auto Counter", 1, true))
assert(not catalog.releases[1].added[1].note:find("One Shot", 1, true))
assert(not Changelog.entryText(catalog.releases[1].added[1]):find("toggle", 1, true))
assert(not Changelog.entryText(catalog.releases[1].added[1]):find("close pocket", 1, true))
assert(not Changelog.entryText(catalog.releases[1].added[1]):find("→", 1, true))
assert(not Changelog.entryText(catalog.releases[1].added[1]):find(" / ", 1, true))
assert(not Changelog.entryText(catalog.releases[1].added[1]):find(">", 1, true))
assert(#catalog.releases == 2, "Changelog tracks main→beta then beta→local")
assert(catalog.releases[2].version == "0.2.0")
assert(catalog.releases[1].channel == "beta")
assert(catalog.releases[2].channel == "beta")
assert(catalog.releases[2].title == "New menu")
assert(Changelog.displayVersion(catalog.releases[1]) == "0.3.0-beta")
assert(catalog.releases[2].added[1].name == "New menu")
assert(catalog.releases[2].added[2].tab == "Settings")
assert(catalog.releases[2].added[2].name == "Task farming")
assert(not Changelog.entryText(catalog.releases[2].added[1]):find("Prism", 1, true))
local betaNotes = table.concat({
    Changelog.entryText(catalog.releases[2].added[1]),
    Changelog.entryText(catalog.releases[2].added[2]),
    Changelog.entryText(catalog.releases[2].added[3]),
    Changelog.entryText(catalog.releases[2].added[4]),
    Changelog.entryText(catalog.releases[2].added[5]),
}, "\n")
assert(not betaNotes:find("Camera Aim", 1, true))
assert(not betaNotes:find("Trigger Bot", 1, true))
assert(not betaNotes:find("Always Scoped", 1, true))
assert(not betaNotes:find("Gun Game", 1, true))
assert(not table.concat(catalog.releases[2].changed, "\n"):find("Private match", 1, true))

local generated = Changelog.markdown(catalog)
local committed = fs.readFile("CHANGELOG.md"):gsub("\r\n", "\n")
assert(committed == generated, "Committed CHANGELOG.md must match changelog.json")
assert(generated:find("## [0.3.0-beta]", 1, true), "Beta builds must stay marked until they reach production")
assert(generated:find("#### Rage", 1, true))
assert(generated:find("- Warp - hops around your opponent", 1, true))
assert(generated:find("- Wall Noclip - stays put when the menu opens", 1, true))
assert(not generated:find(" / ", 1, true), "Changelog must not join tab and feature with a slash")

local fixture = Changelog.validate({
    current = "0.3.0",
    releases = {
        {
            version = "0.2.0",
            channel = "released",
            date = "2026-07-30",
            title = "Native Prism menu",
            added = { "Prism native menu" },
        },
        {
            version = "0.3.0",
            date = "2026-08-15",
            title = "What's New",
            added = { "Upgrade popup" },
            fixed = { "Changelog fetch path" },
        },
        {
            version = "0.2.1",
            date = "2026-08-08",
            title = "Task farming",
            changed = { "Pause matchmaking on demand" },
        },
    },
})
assert(fixture.releases[1].version == "0.3.0", "Releases must sort newest first")
assert(fixture.releases[1].channel == "beta", "Builds stay beta until they are marked released")
assert(fixture.releases[2].version == "0.2.1")
assert(fixture.releases[3].version == "0.2.0")
assert(fixture.releases[3].channel == "released")
assert(Changelog.displayVersion(fixture.releases[3]) == "0.2.0")

local since = Changelog.entriesSince(fixture, "0.2.0")
assert(#since == 2)
assert(since[1].version == "0.3.0" and since[2].version == "0.2.1")
assert(#Changelog.entriesSince(fixture, "0.3.0") == 0)

local firstLoad = Changelog.notice(fixture, "")
assert(firstLoad.shouldShow == true)
assert(firstLoad.previous == nil)
assert(#firstLoad.entries == 3)

local current = Changelog.notice(fixture, "0.3.0")
assert(current.shouldShow == false)
assert(#current.entries == 0)

local upgrade = Changelog.notice(fixture, "0.2.0")
assert(upgrade.shouldShow == true)
assert(upgrade.previous == "0.2.0")
assert(#upgrade.entries == 2)

local notes = Changelog.releaseNotes(fixture, "0.3.0")
assert(notes:find("### Added", 1, true) and notes:find("Upgrade popup", 1, true))
assert(notes:find("### Fixed", 1, true))

local loaded = Changelog.load({
    decode = decode,
    localPath = "missing.json",
    isFile = fs.isFile,
    readFile = fs.readFile,
    remoteUrls = { "https://example.invalid/changelog.json" },
    httpGet = function()
        error("should not fetch when a local catalog is provided")
    end,
    source = fs.readFile("changelog.json"),
})
assert(loaded.current == "0.3.0")

local fromFile = Changelog.load({
    decode = decode,
    localPath = "changelog.json",
    isFile = fs.isFile,
    readFile = fs.readFile,
})
assert(fromFile.current == catalog.current)

local remoteOnly = Changelog.load({
    decode = decode,
    isFile = function()
        return false
    end,
    readFile = function()
        error("local read should not run")
    end,
    remoteUrls = {
        "https://3xjn.github.io/universal-hub/changelog.json",
    },
    httpGet = function(url)
        assert(url == "https://3xjn.github.io/universal-hub/changelog.json")
        return fs.readFile("changelog.json")
    end,
})
assert(remoteOnly.current == "0.3.0")

assert(Changelog.load({
    decode = decode,
    isFile = function()
        return false
    end,
    readFile = function()
        return ""
    end,
}) == nil)

local initSource = fs.readFile("init.lua")
assert(initSource:find('import("modules/Changelog")', 1, true))
assert(initSource:find('forget("modules/Changelog")', 1, true))
assert(initSource:find('import("ui/WhatsNew")', 1, true))
assert(initSource:find("WhatsNew.snapshot", 1, true))
assert(initSource:find("replaceWhatsNew", 1, true), "Changelog reloads must replace What's New instead of merging leftover notes")
assert(initSource:find("configuration.HotReload == true and nil", 1, true), "Local hot reload must reread changelog.json instead of a cached source")
assert(not initSource:find("WhatsNew.mount", 1, true), "What's New must mount through the Prism menu model")
assert(initSource:find("last-used-version.json", 1, true) or initSource:find("WhatsNew.DEFAULT_PATH", 1, true))
assert(initSource:find("configuration.ChangelogSource", 1, true))
local hubSource = fs.readFile("hub.lua")
assert(
    hubSource:find('sourceBaseUrl .. "changelog.json"', 1, true)
        and hubSource:find("configuration.ChangelogSource", 1, true),
    "Packaged beta must prefetch changelog.json so What's New can show on execute"
)
local inventorySource = fs.readFile("modules/Sources.lua")
assert(inventorySource:find('"modules/Changelog"', 1, true))
assert(inventorySource:find('"ui/WhatsNew"', 1, true))

local failed = pcall(function()
    Changelog.validate({
        current = "0.2.0",
        releases = {
            {
                version = "0.1.0",
                date = "2026-08-15",
                title = "Older",
            },
        },
    })
end)
assert(not failed, "Current version must match the newest release")

print("changelog-contracts-ok")
