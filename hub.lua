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
local fetchSource = type(configuration.Fetch) == "function" and configuration.Fetch or function(url)
    return httpGame:HttpGet(url, true)
end

local menuSource = fetchSource(sourceBaseUrl .. "ui/dist/Menu.lua")
local previousSession = environment.UniversalHubSession
if type(previousSession) == "table" and type(previousSession.stop) == "function" then
    pcall(previousSession.stop, previousSession)
    if environment.UniversalHubSession == previousSession then
        environment.UniversalHubSession = nil
    end
end
local menuChunk, menuError = loadstring(menuSource, "ui/dist/Menu.lua")
local Menu = assert(menuChunk, menuError)()
assert(
    type(Menu) == "table" and type(Menu.mountUniversalHubMenu) == "function",
    "Universal Hub requires the compiled Prism menu"
)

local limnSource = fetchSource(sourceBaseUrl .. "vendor/Limn.lua")
local limnChunk, limnError = loadstring(limnSource, "vendor/Limn.lua")
local Limn = assert(limnChunk, limnError)()
assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")

local hydroxideCommit = "38778f8a78762d48fba916cade6eb93399e7c404"
local hydroxideSourceBaseUrl =
    ("https://raw.githubusercontent.com/3xjn/hydroxide/%s/"):format(hydroxideCommit)
local hydroxideSources = {}
for _, path in ipairs({
    "modules/Helpers.lua",
    "modules/Closure.lua",
    "modules/Lifecycle.lua",
    "modules/Targeting.lua",
}) do
    hydroxideSources[path] = fetchSource(hydroxideSourceBaseUrl .. path)
end
local helpersChunk, helpersError =
    loadstring(hydroxideSources["modules/Helpers.lua"], "hydroxide/modules/Helpers.lua")
local Helpers = assert(helpersChunk, helpersError)()
assert(
    type(Helpers) == "table" and type(Helpers.load) == "function",
    "Universal Hub requires Hydroxide Helpers.load"
)

local sources = {}
local function validModulePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:match("^[%w_/%-]+$") ~= nil
        and not path:find("//", 1, true)
end

local function fetch(path)
    if sources[path] == nil then
        sources[path] = fetchSource(sourceBaseUrl .. path)
    end
    return sources[path]
end

local function execute(path)
    local chunk, compileError = loadstring(fetch(path), path)
    return assert(chunk, compileError)()
end

local Registry = execute("modules/Registry.lua")
local Sources = execute("modules/Sources.lua")
local Compatibility = execute("games/Compatibility.lua")
local catalog = execute("games/Catalog.lua")
assert(type(catalog) == "table", "Universal Hub catalog must be a table")
local registry = Registry.new()
local definitions = {}
local seenDefinitions = {}
for _, definitionPath in ipairs(catalog) do
    assert(validModulePath(definitionPath), "Invalid game definition path")
    assert(not seenDefinitions[definitionPath], "Duplicate game definition path: " .. definitionPath)
    seenDefinitions[definitionPath] = true

    local definition = Compatibility.Compose(execute(definitionPath .. ".lua"))
    Registry.Validate(definition)
    registry:Register(definition)
    table.insert(definitions, definition)
end

local inventory = Sources.new({
    catalog = catalog,
    definitions = definitions,
})
local selectedDefinition = registry:Resolve({
    gameId = game.GameId,
    placeId = game.PlaceId,
})
assert(
    selectedDefinition,
    ("Universal Hub does not support game %s / place %s"):format(
        tostring(game.GameId),
        tostring(game.PlaceId)
    )
)
for _, modulePath in ipairs(inventory:All()) do
    fetch(modulePath .. ".lua")
end
environment.UniversalHubConfig = configuration
local importCache = {}
local allowedImports = inventory:Allow(selectedDefinition.id)
configuration.Import = function(path)
    assert(
        type(path) == "string"
            and path:match("^[%w_/%-]+$") ~= nil
            and not path:find("//", 1, true),
        "Invalid hub module path"
    )
    assert(
        allowedImports[path],
        "Hub module is outside selected game source scope: " .. tostring(path)
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
configuration.Menu = Menu
configuration.ChangelogSource = fetchSource(sourceBaseUrl .. "changelog.json")

local initSource = fetchSource(sourceBaseUrl .. "init.lua")
local initChunk, initError = loadstring(initSource, "init.lua")
return assert(initChunk, initError)()
