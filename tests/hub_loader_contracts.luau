local fs = require("@lune/fs")
local source = fs.readFile("hub.lua")
local hydroxideCommit = "8e2d4a84ddb4b7ef901af170966a43b3b35fbaa7"
local sourceBaseUrl = "https://raw.githubusercontent.com/3xjn/universal-hub/main/"
local Catalog = require("../games/Catalog")
local expectedHubPaths = {
    "modules/Store.lua",
    "modules/Config.lua",
    "modules/InputCapture.lua",
    "modules/MenuToggle.lua",
    "modules/Registry.lua",
    "modules/Session.lua",
    "modules/Overlay.lua",
    "modules/PresentationHost.lua",
    "games/Catalog.lua",
    "init.lua",
}
local firstDeclaredSource
for _, definitionPath in ipairs(Catalog) do
    table.insert(expectedHubPaths, definitionPath .. ".lua")
    local definition = require("../" .. definitionPath)
    for _, modulePath in ipairs(definition.sources) do
        local file = modulePath .. ".lua"
        firstDeclaredSource = firstDeclaredSource or file
        table.insert(expectedHubPaths, file)
        assert(
            not source:find('"' .. file .. '"', 1, true),
            "Packaged game sources must come from definitions, not hub.lua: " .. file
        )
    end
end
assert(
    source:find("Registry.Validate", 1, true),
    "Packaged bootstrap must validate definitions before fetching their declared sources"
)
assert(
    source:find("vendor/Limn.lua", 1, true)
        and source:find(hydroxideCommit, 1, true)
        and source:find("modules/Helpers.lua", 1, true)
        and source:find("modules/Closure.lua", 1, true)
        and source:find("modules/Lifecycle.lua", 1, true)
        and source:find("modules/Targeting.lua", 1, true),
    "Packaged bootstrap must pin Limn and the stable Hydroxide helper source set"
)
assert(
    not source:find("/hydroxide/dev/init.lua", 1, true)
        and not source:find("environment.HydroxideConfig", 1, true),
    "Packaged bootstrap must not execute or configure the Hydroxide application"
)
local environment = {
    oh = {
        unrelated = true,
    },
}
environment.OriginalOh = environment.oh
local requested = {}
local invalidDefinitionPath

function getgenv()
    return environment
end

game = {}
function game:HttpGet(url, noCache)
    assert(noCache == true, "Hub loader must bypass the executor HTTP cache")
    table.insert(requested, url)

    if url == sourceBaseUrl .. "vendor/Limn.lua" then
        return [[return { new = function() end }]]
    end

    local hydroxideRoot =
        "https://raw.githubusercontent.com/3xjn/hydroxide/"
        .. hydroxideCommit
        .. "/"
    if url == hydroxideRoot .. "modules/Helpers.lua" then
        return [[
return {
    load = function(options)
        local files = {
            closure = "modules/Closure",
            lifecycle = "modules/Lifecycle",
            targeting = "modules/Targeting",
        }
        local namespace = {}
        for _, name in ipairs(options.modules or {}) do
            namespace[name] = options.import(files[name])
        end
        return namespace
    end,
}
]]
    end
    if url == hydroxideRoot .. "modules/Targeting.lua" then
        return [[return { nearestPlayer = function() end }]]
    end
    if url == hydroxideRoot .. "modules/Closure.lua"
        or url == hydroxideRoot .. "modules/Lifecycle.lua"
    then
        return [[return {}]]
    end

    if url == sourceBaseUrl .. "modules/Registry.lua"
        or url == sourceBaseUrl .. "games/Catalog.lua"
        or url == sourceBaseUrl .. "games/counterblox/Definition.lua"
        or url == sourceBaseUrl .. "games/rivals/Definition.lua"
        or url == sourceBaseUrl .. "games/town/Definition.lua"
    then
        local path = url:sub(#sourceBaseUrl + 1)
        if path == invalidDefinitionPath then
            return [[return {}]]
        end
        return fs.readFile(path)
    end

    if url == sourceBaseUrl .. "init.lua" then
        return [[
local configuration = getgenv().UniversalHubConfig
assert(type(configuration.Limn.new) == "function", "Hub loader must stage vendored Limn")
assert(type(configuration.Import) == "function", "Hub loader must install its own importer")
local first = configuration.Import("modules/Store")
local second = configuration.Import("modules/Store")
assert(first == second, "Hub importer must cache Universal Hub modules")
assert(not pcall(configuration.Import, "../modules/Store"), "Hub importer must validate paths")
local helpers = configuration.HydroxideHelpers.load({
    import = configuration.HydroxideImport,
    modules = { "targeting" },
})
assert(type(helpers.targeting.nearestPlayer) == "function")
assert(
    not pcall(configuration.HydroxideImport, "modules/Store"),
    "Hydroxide importer must not resolve Universal Hub modules"
)
assert(getgenv().oh == getgenv().OriginalOh, "Hub loader must not replace environment.oh")
return "hub-loader-ok"
]]
    end

    if url == sourceBaseUrl .. "modules/Store.lua" then
        return [[
local environment = getgenv()
environment.StoreExecutions = (environment.StoreExecutions or 0) + 1
return {}
]]
    end

    return [[return {}]]
end

environment.UniversalHubConfig = {
    SourceBaseUrl = sourceBaseUrl,
}

local chunk, compileError = loadstring(source, "hub.lua")
local result = assert(chunk, compileError)()
assert(result == "hub-loader-ok")
assert(environment.StoreExecutions == 1, "Hub importer must execute a fetched module once")
local expectedUrls = {
    [sourceBaseUrl .. "vendor/Limn.lua"] = true,
}
local hydroxideRoot =
    "https://raw.githubusercontent.com/3xjn/hydroxide/"
    .. hydroxideCommit
    .. "/"
for _, path in ipairs({
    "modules/Helpers.lua",
    "modules/Closure.lua",
    "modules/Lifecycle.lua",
    "modules/Targeting.lua",
}) do
    expectedUrls[hydroxideRoot .. path] = true
end
for _, path in ipairs(expectedHubPaths) do
    expectedUrls[sourceBaseUrl .. path] = true
end

local seen = {}
local requestedAt = {}
for index, url in ipairs(requested) do
    assert(not seen[url], "Hub loader must fetch each pinned source exactly once: " .. url)
    assert(expectedUrls[url], "Hub loader fetched an undeclared source: " .. url)
    seen[url] = true
    requestedAt[url] = index
    assert(not url:find("/hydroxide/dev/init.lua", 1, true))
    assert(not url:find("/modules/Drawing", 1, true))
    assert(not url:find("/modules/DrawingControls", 1, true))
    assert(not url:find("/modules/Remote.lua", 1, true))
end
for url in pairs(expectedUrls) do
    assert(seen[url], "Hub loader did not fetch declared source: " .. url)
end
local lastDefinitionAt = 0
for _, path in ipairs(Catalog) do
    lastDefinitionAt = math.max(lastDefinitionAt, assert(requestedAt[sourceBaseUrl .. path .. ".lua"]))
end
assert(
    lastDefinitionAt < assert(requestedAt[sourceBaseUrl .. firstDeclaredSource]),
    "Catalog definitions must be fetched before their declared game sources"
)

invalidDefinitionPath = "games/rivals/Definition.lua"
requested = {}
environment.UniversalHubConfig = {
    SourceBaseUrl = sourceBaseUrl,
}
local invalidSucceeded, invalidMessage = pcall(function()
    local invalidChunk, invalidCompileError = loadstring(source, "hub-invalid-definition.lua")
    assert(invalidChunk, invalidCompileError)()
end)
assert(
    not invalidSucceeded and tostring(invalidMessage):find("non-empty id", 1, true),
    "Packaged bootstrap must reject an invalid catalog definition"
)
for _, url in ipairs(requested) do
    for _, definitionPath in ipairs(Catalog) do
        local definition = require("../" .. definitionPath)
        for _, modulePath in ipairs(definition.sources) do
            assert(
                url ~= sourceBaseUrl .. modulePath .. ".lua",
                "Packaged bootstrap must validate every definition before fetching game sources"
            )
        end
    end
end
print("hub-loader-contracts-ok")
