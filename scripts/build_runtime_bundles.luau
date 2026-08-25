local fs = require("@lune/fs")
local process = require("@lune/process")

local Sources = require("../modules/Sources")
local catalog = require("../games/Catalog")

local HYDROXIDE_COMMIT = "38778f8a78762d48fba916cade6eb93399e7c404"
local hydroxideRoot =
    assert(process.env.HYDROXIDE_ROOT, "HYDROXIDE_ROOT must point to the pinned Hydroxide checkout")

local function normalize(source)
    return source:gsub("\r\n?", "\n")
end

local function quote(source)
    source = normalize(source)
    for depth = 0, 16 do
        local equals = string.rep("=", depth)
        local close = "]" .. equals .. "]"
        if not source:find(close, 1, true) then
            return "[" .. equals .. "[" .. source .. close
        end
    end
    error("Source requires an unsupported long-string delimiter", 2)
end

local function read(path)
    assert(fs.isFile(path), "Missing bundle source: " .. path)
    return fs.readFile(path)
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

local function sourceTable(values, indent)
    indent = indent or ""
    local lines = { "{" }
    for _, path in ipairs(sortedKeys(values)) do
        table.insert(
            lines,
            indent .. "    [" .. string.format("%q", path) .. "] = " .. quote(values[path]) .. ","
        )
    end
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

local definitions = {}
for _, path in ipairs(catalog) do
    table.insert(definitions, require("../" .. path))
end
local inventory = Sources.new({
    catalog = catalog,
    definitions = definitions,
})

local shared = {
    ["hub.lua"] = read("hub.lua"),
    ["init.lua"] = read("init.lua"),
    ["vendor/Limn.lua"] = read("vendor/Limn.lua"),
    ["changelog.json"] = read("changelog.json"),
}
local byGame = {}
for _, definition in ipairs(definitions) do
    byGame[definition.id] = {}
end
for _, path in ipairs(inventory:All()) do
    local source = read(path .. ".lua")
    local owner = inventory:Owner(path)
    if owner == "core" then
        shared[path .. ".lua"] = source
    else
        assert(byGame[owner], "Unknown bundle owner: " .. tostring(owner))
        byGame[owner][path .. ".lua"] = source
    end
end

local hydroxideBase = "https://raw.githubusercontent.com/3xjn/hydroxide/" .. HYDROXIDE_COMMIT .. "/"
local external = {}
for _, path in ipairs({
    "modules/Helpers.lua",
    "modules/Closure.lua",
    "modules/Lifecycle.lua",
    "modules/Targeting.lua",
}) do
    external[hydroxideBase .. path] = read(hydroxideRoot .. "/" .. path)
end

local gameIds = {}
local placeIds = {}
for _, definition in ipairs(definitions) do
    for _, id in ipairs(definition.manifest.gameIds or {}) do
        local key = tostring(id)
        assert(not gameIds[key], "Duplicate bundled game id: " .. key)
        gameIds[key] = definition.id
    end
    for _, id in ipairs(definition.manifest.placeIds or {}) do
        local key = tostring(id)
        assert(not placeIds[key], "Duplicate bundled place id: " .. key)
        placeIds[key] = definition.id
    end
end

local hash = 5381
local function hashValues(values)
    for _, key in ipairs(sortedKeys(values)) do
        local value = key .. "\0" .. values[key]
        for index = 1, #value do
            hash = (hash * 33 + value:byte(index)) % 2147483647
        end
    end
end
hashValues(shared)
hashValues(external)
for _, definition in ipairs(definitions) do
    hashValues(byGame[definition.id])
end
local buildId = ("%08x"):format(hash)

local runtime = table.concat({
    "local buildId = " .. quote(buildId),
    "local shared = " .. sourceTable(shared),
    "local external = " .. sourceTable(external),
    "local gameIds = " .. sourceTable(gameIds),
    "local placeIds = " .. sourceTable(placeIds),
    [[
local function run(bundle)
    assert(type(bundle) == "table" and type(bundle.id) == "string", "Invalid game bundle")
    assert(bundle.buildId == buildId, "Runtime and game bundle builds do not match")
    assert(type(bundle.sources) == "table", "Game bundle sources are missing")
    local expected = placeIds[tostring(game.PlaceId)] or gameIds[tostring(game.GameId)]
    assert(expected == bundle.id, "Wrong game bundle: " .. tostring(bundle.id))

    local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
    local configuration = environment.UniversalHubConfig or {}
    local sourceRoot = assert(configuration.SourceBaseUrl, "Bundled loader source root is missing")
    local timing = configuration.BootTiming or { startedAt = os.clock() }
    timing.mode = "bundle"
    timing.bundle = bundle.id
    timing.bundleSourceCount = 0
    for _ in pairs(shared) do
        timing.bundleSourceCount += 1
    end
    for path, source in pairs(bundle.sources) do
        assert(type(path) == "string" and type(source) == "string", "Invalid bundled source")
        assert(shared[path] == nil, "Game bundle replaces shared source: " .. path)
        timing.bundleSourceCount += 1
    end
    configuration.BootTiming = timing
    configuration.Fetch = function(url)
        local source = external[url]
        if source == nil and url:sub(1, #sourceRoot) == sourceRoot then
            local path = url:sub(#sourceRoot + 1)
            source = bundle.sources[path] or shared[path]
        end
        return assert(source, "Source is absent from runtime bundle: " .. tostring(url))
    end
    environment.UniversalHubConfig = configuration

    local chunk, compileError = loadstring(shared["hub.lua"], "universal-hub/hub.lua")
    return assert(chunk, compileError)()
end

return {
    buildId = buildId,
    gameIds = gameIds,
    placeIds = placeIds,
    run = run,
}
]],
}, "\n")

fs.writeDir("dist")
fs.writeDir("dist/games")
for _, name in ipairs(fs.readDir("dist/games")) do
    if name:sub(-4) == ".lua" then
        fs.removeFile("dist/games/" .. name)
    end
end
fs.writeFile("dist/runtime.lua", normalize(runtime))
for _, definition in ipairs(definitions) do
    local artifact = "return {\n    buildId = "
        .. quote(buildId)
        .. ",\n    id = "
        .. quote(definition.id)
        .. ",\n    sources = "
        .. sourceTable(byGame[definition.id], "    ")
        .. ",\n}\n"
    fs.writeFile("dist/games/" .. definition.id .. ".lua", normalize(artifact))
end

print(("runtime-bundles-ok shared=%d games=%d"):format(#sortedKeys(shared), #definitions))
