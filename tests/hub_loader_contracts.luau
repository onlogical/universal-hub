local fs = require("@lune/fs")
local source = fs.readFile("hub.lua")
local hydroxideCommit = "8e2d4a84ddb4b7ef901af170966a43b3b35fbaa7"
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

function getgenv()
    return environment
end

game = {}
function game:HttpGet(url, noCache)
    assert(noCache == true, "Hub loader must bypass the executor HTTP cache")
    table.insert(requested, url)

    if url == "https://raw.githubusercontent.com/3xjn/universal-hub/main/vendor/Limn.lua" then
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

    if url == "https://raw.githubusercontent.com/3xjn/universal-hub/main/init.lua" then
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

    if url == "https://raw.githubusercontent.com/3xjn/universal-hub/main/modules/Store.lua" then
        return [[
local environment = getgenv()
environment.StoreExecutions = (environment.StoreExecutions or 0) + 1
return {}
]]
    end

    return [[return {}]]
end

environment.UniversalHubConfig = {
    SourceBaseUrl = "https://raw.githubusercontent.com/3xjn/universal-hub/main/",
}

local chunk, compileError = loadstring(source, "hub.lua")
local result = assert(chunk, compileError)()
assert(result == "hub-loader-ok")
assert(environment.StoreExecutions == 1, "Hub importer must execute a fetched module once")
assert(
    #requested == 33,
    "Hub loader must fetch vendored Limn, pinned Helpers and leaves, init.lua, and twenty-seven modules"
)
local seen = {}
for _, url in ipairs(requested) do
    assert(not seen[url], "Hub loader must fetch each pinned source exactly once: " .. url)
    seen[url] = true
    assert(not url:find("/hydroxide/dev/init.lua", 1, true))
    assert(not url:find("/modules/Drawing", 1, true))
    assert(not url:find("/modules/DrawingControls", 1, true))
    assert(not url:find("/modules/Remote.lua", 1, true))
end
print("hub-loader-contracts-ok")
