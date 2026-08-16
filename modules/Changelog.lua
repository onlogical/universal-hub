local Changelog = {}

local SECTION_ORDER = { "added", "changed", "fixed", "removed", "security" }
local SECTION_LABEL = {
    added = "Added",
    changed = "Changed",
    fixed = "Fixed",
    removed = "Removed",
    security = "Security",
}

local function copyList(source)
    local copy = {}
    for index, value in ipairs(source or {}) do
        copy[index] = value
    end
    return copy
end

local function isSemver(text)
    return type(text) == "string" and text:match("^%d+%.%d+%.%d+$") ~= nil
end

function Changelog.parseVersion(text)
    if text == nil or text == "" then
        return { 0, 0, 0 }
    end
    if not isSemver(text) then
        return nil
    end
    local major, minor, patch = text:match("^(%d+)%.(%d+)%.(%d+)$")
    return {
        tonumber(major),
        tonumber(minor),
        tonumber(patch),
    }
end

function Changelog.compare(left, right)
    local a = Changelog.parseVersion(left)
    local b = Changelog.parseVersion(right)
    if not a or not b then
        return nil
    end
    for index = 1, 3 do
        if a[index] < b[index] then
            return -1
        end
        if a[index] > b[index] then
            return 1
        end
    end
    return 0
end

function Changelog.isNewer(candidate, baseline)
    return Changelog.compare(candidate, baseline) == 1
end

function Changelog.sectionLabel(name)
    return SECTION_LABEL[name]
end

function Changelog.sectionOrder()
    return copyList(SECTION_ORDER)
end

function Changelog.channel(release)
    if type(release) == "table" and release.channel == "released" then
        return "released"
    end
    return "beta"
end

function Changelog.displayVersion(release)
    local version = type(release) == "table" and release.version or nil
    if type(version) ~= "string" or version == "" then
        return ""
    end
    if Changelog.channel(release) == "beta" then
        return version .. "-beta"
    end
    return version
end

function Changelog.entryText(entry)
    if type(entry) == "string" then
        return entry
    end
    if type(entry) ~= "table" then
        return ""
    end
    if type(entry.text) == "string" and entry.text ~= "" then
        return entry.text
    end
    local name = type(entry.name) == "string" and entry.name or ""
    local note = type(entry.note) == "string" and entry.note or ""
    local tab = type(entry.tab) == "string" and entry.tab or ""
    if name ~= "" and note ~= "" then
        return name .. " - " .. note
    end
    return name
end

local function entryList(value, field)
    if value == nil then
        return {}
    end
    assert(type(value) == "table", "Changelog " .. field .. " must be a list")
    local items = {}
    for _, item in ipairs(value) do
        if type(item) == "string" then
            assert(item ~= "", "Changelog " .. field .. " entries must be strings")
            table.insert(items, {
                tab = "",
                name = item,
                note = "",
                text = item,
            })
        else
            assert(type(item) == "table", "Changelog " .. field .. " entries must be strings or feature notes")
            local name = item.name or item.feature
            assert(type(name) == "string" and name ~= "", "Changelog " .. field .. " feature names must be strings")
            local tab = type(item.tab) == "string" and item.tab or ""
            local note = type(item.note) == "string" and item.note or ""
            local entry = {
                tab = tab,
                name = name,
                note = note,
            }
            entry.text = Changelog.entryText(entry)
            table.insert(items, entry)
        end
    end
    return items
end

function Changelog.validate(catalog)
    assert(type(catalog) == "table", "Changelog catalog must be a table")
    assert(isSemver(catalog.current), "Changelog current version must be semver")
    assert(type(catalog.releases) == "table", "Changelog releases must be a list")
    assert(#catalog.releases > 0, "Changelog requires at least one release")

    local seen = {}
    local releases = {}
    for _, release in ipairs(catalog.releases) do
        assert(type(release) == "table", "Changelog release must be a table")
        assert(isSemver(release.version), "Changelog release version must be semver")
        assert(not seen[release.version], "Changelog contains a duplicate version: " .. release.version)
        assert(
            type(release.date) == "string" and release.date:match("^%d%d%d%d%-%d%d%-%d%d$"),
            "Changelog release date must be YYYY-MM-DD"
        )
        assert(type(release.title) == "string" and release.title ~= "", "Changelog release title is required")
        local channel = release.channel
        if channel == nil or channel == "" then
            channel = "beta"
        end
        assert(channel == "beta" or channel == "released", "Changelog channel must be beta or released")
        seen[release.version] = true
        local normalized = {
            version = release.version,
            date = release.date,
            title = release.title,
            channel = channel,
        }
        for _, section in ipairs(SECTION_ORDER) do
            normalized[section] = entryList(release[section], section)
        end
        table.insert(releases, normalized)
    end

    table.sort(releases, function(left, right)
        return Changelog.isNewer(left.version, right.version)
    end)
    assert(releases[1].version == catalog.current, "Changelog current version must match the newest release")

    return {
        current = catalog.current,
        releases = releases,
    }
end

function Changelog.decode(source, decode)
    assert(type(source) == "string" and source ~= "", "Changelog source must be JSON text")
    assert(type(decode) == "function", "Changelog.decode requires a JSON decoder")
    return Changelog.validate(decode(source))
end

function Changelog.entriesSince(catalog, lastUsedVersion)
    local validated = Changelog.validate(catalog)
    local baseline = lastUsedVersion
    if baseline == nil or baseline == "" then
        baseline = "0.0.0"
    end
    local entries = {}
    for _, release in ipairs(validated.releases) do
        if Changelog.isNewer(release.version, baseline) then
            table.insert(entries, release)
        end
    end
    return entries
end

function Changelog.notice(catalog, lastUsedVersion)
    local validated = Changelog.validate(catalog)
    local previous = lastUsedVersion
    if previous == nil or previous == "" then
        previous = "0.0.0"
    end
    local entries = Changelog.entriesSince(validated, previous)
    return {
        shouldShow = Changelog.isNewer(validated.current, previous) and #entries > 0,
        current = validated.current,
        previous = (type(lastUsedVersion) == "string" and lastUsedVersion ~= "") and lastUsedVersion or nil,
        lastUsed = lastUsedVersion or "",
        entries = entries,
        catalog = validated,
    }
end

function Changelog.load(options)
    options = options or {}
    local decode = options.decode
    assert(type(decode) == "function", "Changelog.load requires decode")

    if type(options.catalog) == "table" then
        return Changelog.validate(options.catalog)
    end
    if type(options.source) == "table" then
        return Changelog.validate(options.source)
    end
    if type(options.source) == "string" and options.source ~= "" then
        return Changelog.decode(options.source, decode)
    end

    local paths = {}
    if type(options.localPath) == "string" and options.localPath ~= "" then
        table.insert(paths, options.localPath)
    end
    for _, path in ipairs(options.localPaths or {}) do
        table.insert(paths, path)
    end
    if type(options.isFile) == "function" and type(options.readFile) == "function" then
        for _, path in ipairs(paths) do
            if type(path) == "string" and options.isFile(path) then
                local succeeded, catalog = pcall(function()
                    return Changelog.decode(options.readFile(path), decode)
                end)
                if succeeded then
                    return catalog
                end
            end
        end
    end

    if type(options.httpGet) == "function" then
        for _, url in ipairs(options.remoteUrls or {}) do
            if type(url) == "string" and url ~= "" then
                local succeeded, catalog = pcall(function()
                    return Changelog.decode(options.httpGet(url), decode)
                end)
                if succeeded then
                    return catalog
                end
            end
        end
    end

    return nil
end

function Changelog.releaseNotes(catalog, version)
    local validated = Changelog.validate(catalog)
    for _, release in ipairs(validated.releases) do
        if release.version == version then
            local lines = {
                "## " .. release.title,
                "",
            }
            for _, section in ipairs(SECTION_ORDER) do
                local items = release[section]
                if #items > 0 then
                    table.insert(lines, "### " .. SECTION_LABEL[section])
                    table.insert(lines, "")
                    local lastTab = nil
                    for _, item in ipairs(items) do
                        local tab = type(item) == "table" and item.tab or ""
                        if tab ~= "" and tab ~= lastTab then
                            table.insert(lines, "#### " .. tab)
                            table.insert(lines, "")
                            lastTab = tab
                        end
                        table.insert(lines, "- " .. Changelog.entryText(item))
                        table.insert(lines, "")
                    end
                    table.insert(lines, "")
                end
            end
            return table.concat(lines, "\n")
        end
    end
    return nil
end

function Changelog.markdown(catalog)
    local validated = Changelog.validate(catalog)
    local lines = {
        "# Changelog",
        "",
        "All notable changes to Universal Hub are documented in this file.",
        "",
        "The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),",
        "and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).",
        "",
        "## [Unreleased]",
        "",
    }
    for _, release in ipairs(validated.releases) do
        table.insert(lines, ("## [%s] - %s"):format(Changelog.displayVersion(release), release.date))
        table.insert(lines, "")
        for _, section in ipairs(SECTION_ORDER) do
            local items = release[section]
            if #items > 0 then
                table.insert(lines, "### " .. SECTION_LABEL[section])
                table.insert(lines, "")
                local lastTab = nil
                for _, item in ipairs(items) do
                    local tab = type(item) == "table" and item.tab or ""
                    if tab ~= "" and tab ~= lastTab then
                        table.insert(lines, "#### " .. tab)
                        table.insert(lines, "")
                        lastTab = tab
                    end
                    table.insert(lines, "- " .. Changelog.entryText(item))
                    table.insert(lines, "")
                end
            end
        end
    end
    local newest = validated.releases[1].version
    table.insert(lines, ("[Unreleased]: https://github.com/3xjn/universal-hub/compare/v%s...HEAD"):format(newest))
    for _, release in ipairs(validated.releases) do
        local displayed = Changelog.displayVersion(release)
        table.insert(
            lines,
            ("[%s]: https://github.com/3xjn/universal-hub/releases/tag/v%s"):format(displayed, release.version)
        )
    end
    table.insert(lines, "")
    return table.concat(lines, "\n")
end

return Changelog
