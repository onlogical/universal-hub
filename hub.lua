local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local sourceBaseUrl = assert(
    configuration.SourceBaseUrl,
    "Set UniversalHubConfig.SourceBaseUrl to the raw universal-hub source root"
)
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string, noCache: boolean?) -> string,
}
local httpGame = game :: HttpGame

local limnSource = httpGame:HttpGet(sourceBaseUrl .. "vendor/Limn.lua", true)
local limnChunk, limnError = loadstring(limnSource, "vendor/Limn.lua")
local Limn = assert(limnChunk, limnError)()
assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")

local hydroxideCommit = "8e2d4a84ddb4b7ef901af170966a43b3b35fbaa7"
local hydroxideSourceBaseUrl =
    ("https://raw.githubusercontent.com/3xjn/hydroxide/%s/"):format(hydroxideCommit)
local hydroxideSources = {}
for _, path in ipairs({
    "modules/Helpers.lua",
    "modules/Closure.lua",
    "modules/Lifecycle.lua",
    "modules/Targeting.lua",
}) do
    hydroxideSources[path] = httpGame:HttpGet(hydroxideSourceBaseUrl .. path, true)
end
local helpersChunk, helpersError =
    loadstring(hydroxideSources["modules/Helpers.lua"], "hydroxide/modules/Helpers.lua")
local Helpers = assert(helpersChunk, helpersError)()
assert(
    type(Helpers) == "table" and type(Helpers.load) == "function",
    "Universal Hub requires Hydroxide Helpers.load"
)

local sources = {}
for _, path in ipairs({
    "modules/Store.lua",
    "modules/Config.lua",
    "modules/InputCapture.lua",
    "modules/MenuToggle.lua",
    "modules/Registry.lua",
    "modules/Session.lua",
    "modules/Overlay.lua",
    "games/Catalog.lua",
    "games/counterblox/Definition.lua",
    "games/rivals/Definition.lua",
    "games/town/Definition.lua",
    "games/town/Canonical.lua",
    "games/town/CheckpointStore.lua",
    "games/town/CopyEngine.lua",
    "games/town/CopyPlan.lua",
    "games/town/ExecutionPlan.lua",
    "games/Counterblox.lua",
    "games/Town.lua",
    "games/rivals/Adapter.lua",
    "games/rivals/Targeting.lua",
    "games/rivals/ProjectileAim.lua",
    "games/rivals/ShotPresentation.lua",
    "games/rivals/ScopedAccuracy.lua",
    "games/rivals/WeaponPolicy.lua",
    "games/rivals/Effects.lua",
    "games/rivals/Movement.lua",
    "games/rivals/CombatState.lua",
}) do
    sources[path] = httpGame:HttpGet(sourceBaseUrl .. path, true)
end
environment.UniversalHubConfig = configuration
local importCache = {}
configuration.Import = function(path)
    assert(
        type(path) == "string"
            and path:match("^[%w_/%-]+$") ~= nil
            and not path:find("//", 1, true),
        "Invalid hub module path"
    )
    if importCache[path] ~= nil then
        return importCache[path]
    end
    local file = path .. ".lua"
    local chunk, compileError = loadstring(assert(sources[file], "Unknown hub module: " .. path), file)
    local result = assert(chunk, compileError)()
    importCache[path] = result
    return result
end
local hydroxideCache = {}
configuration.HydroxideImport = function(path)
    assert(
        path == "modules/Closure" or path == "modules/Lifecycle" or path == "modules/Targeting",
        "Unknown Hydroxide helper module: " .. tostring(path)
    )
    if hydroxideCache[path] ~= nil then
        return hydroxideCache[path]
    end
    local file = path .. ".lua"
    local chunk, compileError =
        loadstring(assert(hydroxideSources[file], "Unknown Hydroxide source: " .. path), "hydroxide/" .. file)
    local result = assert(chunk, compileError)()
    hydroxideCache[path] = assert(result, "Hydroxide helper module returned nil: " .. path)
    return hydroxideCache[path]
end
configuration.HydroxideHelpers = Helpers
configuration.Limn = Limn

local initSource = httpGame:HttpGet(sourceBaseUrl .. "init.lua", true)
local initChunk, initError = loadstring(initSource, "init.lua")
return assert(initChunk, initError)()
