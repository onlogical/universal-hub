local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Changelog = importDependency("modules/Changelog", "../modules/Changelog")

local WhatsNew = {}
WhatsNew.DEFAULT_PATH = "universal-hub/last-used-version.json"
WhatsNew.PAGES_CHANGELOG_URL = "https://3xjn.github.io/universal-hub/changelog.json"

local function copyLastUsed(value)
    return {
        version = type(value) == "table" and type(value.version) == "string" and value.version or "",
        suppressPopups = type(value) == "table" and value.suppressPopups == true,
    }
end

function WhatsNew.defaults()
    return {
        version = "",
        suppressPopups = false,
    }
end

local function readLocalCatalog()
    if type(getgenv) ~= "function" or type(readfile) ~= "function" then
        return nil
    end
    local environment = getgenv()
    local configuration = environment and environment.UniversalHubConfig
    local root = type(configuration) == "table" and configuration.LocalRoot or "universal-hub/local"
    local path = root .. "/changelog.json"
    if type(isfile) == "function" and not isfile(path) then
        return nil
    end
    local ok, catalog = pcall(function()
        return Changelog.decode(readfile(path), function(source)
            return game:GetService("HttpService"):JSONDecode(source)
        end)
    end)
    if ok then
        return catalog
    end
    return nil
end

function WhatsNew.evaluate(options)
    options = options or {}
    local catalog = options.catalog
    if type(catalog) ~= "table" or type(catalog.releases) ~= "table" then
        catalog = readLocalCatalog()
    end
    if type(catalog) ~= "table" then
        return {
            shouldShow = false,
        }
    end
    local lastUsed = copyLastUsed(options.lastUsed)
    local notice = Changelog.notice(catalog, lastUsed.version)
    notice.suppressPopups = lastUsed.suppressPopups
    if lastUsed.suppressPopups then
        notice.shouldShow = false
    end
    return notice
end

function WhatsNew.acknowledge(current, suppressPopups)
    assert(type(current) == "string" and current ~= "", "WhatsNew.acknowledge requires the current version")
    return {
        version = current,
        suppressPopups = suppressPopups == true,
    }
end

local SECTION_LABEL = {
    added = "New features",
    changed = "Changes",
    fixed = "Bugfixes",
    removed = "Removed",
    security = "Security",
}

function WhatsNew.sectionLabel(name)
    return SECTION_LABEL[name] or Changelog.sectionLabel(name)
end

local function featureEntry(item)
    if type(item) == "table" then
        return {
            tab = type(item.tab) == "string" and item.tab or "",
            name = item.name or item.text or "",
            note = type(item.note) == "string" and item.note or "",
            text = item.text or (Changelog.entryText and Changelog.entryText(item)) or item.name or "",
        }
    end
    local text = tostring(item or "")
    return {
        tab = "",
        name = text,
        note = "",
        text = text,
    }
end

function WhatsNew.releaseSections(release)
    local sections = {}
    for _, name in ipairs(Changelog.sectionOrder()) do
        local items = release and release[name]
        if items and #items > 0 then
            local copy = {}
            local groups = {}
            local current
            for index, item in ipairs(items) do
                local entry = featureEntry(item)
                copy[index] = entry.text
                if not current or current.tab ~= entry.tab then
                    current = {
                        tab = entry.tab,
                        items = {},
                    }
                    table.insert(groups, current)
                end
                table.insert(current.items, entry)
            end
            table.insert(sections, {
                id = name,
                label = WhatsNew.sectionLabel(name),
                items = copy,
                groups = groups,
            })
        end
    end
    return sections
end

function WhatsNew.releaseBody(release)
    local lines = {}
    for _, section in ipairs(WhatsNew.releaseSections(release)) do
        table.insert(lines, section.label)
        for _, group in ipairs(section.groups or {}) do
            if group.tab ~= "" then
                table.insert(lines, group.tab)
            end
            for _, item in ipairs(group.items or {}) do
                table.insert(lines, item.name)
                if item.note ~= "" then
                    table.insert(lines, item.note)
                end
            end
        end
    end
    return table.concat(lines, "\n")
end

local function copyReleases(source)
    local releases = {}
    for index, release in ipairs(type(source) == "table" and source or {}) do
        releases[index] = release
    end
    return releases
end

function WhatsNew.snapshot(notice)
    notice = notice or {}
    local catalog = notice.catalog
    local board = copyReleases(catalog and catalog.releases)
    return {
        visible = notice.shouldShow == true,
        current = notice.current,
        previous = notice.previous,
        showingAll = false,
        entries = notice.entries or {},
        catalog = catalog,
        history = board,
        timeline = board,
        lanes = board,
        board = board,
        outline = board,
        guide = board,
        pack = board,
    }
end

local function publishedReleases(state)
    if type(state) ~= "table" then
        return {}
    end
    if type(state.pack) == "table" and #state.pack > 0 then
        return state.pack
    end
    if type(state.guide) == "table" and #state.guide > 0 then
        return state.guide
    end
    if type(state.outline) == "table" and #state.outline > 0 then
        return state.outline
    end
    if type(state.board) == "table" and #state.board > 0 then
        return state.board
    end
    if type(state.lanes) == "table" and #state.lanes > 0 then
        return state.lanes
    end
    if type(state.timeline) == "table" and #state.timeline > 0 then
        return state.timeline
    end
    if type(state.history) == "table" and #state.history > 0 then
        return state.history
    end
    if type(state.catalog) == "table" and type(state.catalog.releases) == "table" then
        return state.catalog.releases
    end
    return state.entries or {}
end

function WhatsNew.releases(state)
    if type(state) ~= "table" then
        return {}
    end
    if state.showingAll == true then
        return publishedReleases(state)
    end
    return state.entries or {}
end

local function releaseChannel(release)
    if Changelog.channel then
        return Changelog.channel(release)
    end
    if type(release) == "table" and release.channel == "released" then
        return "released"
    end
    return "beta"
end

local function displayVersion(release)
    if Changelog.displayVersion then
        return Changelog.displayVersion(release)
    end
    local version = type(release) == "table" and release.version or ""
    if releaseChannel(release) == "beta" then
        return version .. "-beta"
    end
    return version
end

local function mapRelease(release)
    return {
        version = release.version,
        displayVersion = displayVersion(release),
        channel = releaseChannel(release),
        date = release.date,
        title = release.title,
        body = WhatsNew.releaseBody(release),
        sections = WhatsNew.releaseSections(release),
    }
end

function WhatsNew.model(state)
    local entries = {}
    for _, release in ipairs(WhatsNew.releases(state)) do
        table.insert(entries, mapRelease(release))
    end
    local releases = {}
    for _, release in ipairs(publishedReleases(state)) do
        table.insert(releases, mapRelease(release))
    end
    local fresh = {}
    for _, release in ipairs(type(state) == "table" and state.entries or {}) do
        if type(release.version) == "string" then
            fresh[release.version] = true
        end
    end
    return {
        visible = type(state) == "table" and state.visible == true,
        current = type(state) == "table" and state.current or "",
        previous = type(state) == "table" and state.previous or nil,
        showingAll = type(state) == "table" and state.showingAll == true,
        entries = entries,
        releases = releases,
        fresh = fresh,
    }
end

return WhatsNew
