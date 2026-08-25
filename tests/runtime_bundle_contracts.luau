local fs = require("@lune/fs")

local Sources = require("../modules/Sources")
local catalog = require("../games/Catalog")

local hydroxideCommit = "38778f8a78762d48fba916cade6eb93399e7c404"
assert(fs.readFile("hub.lua"):find(hydroxideCommit, 1, true))
assert(fs.readFile("scripts/build_runtime_bundles.luau"):find(hydroxideCommit, 1, true))
assert(fs.readFile(".github/workflows/runtime-bundles.yml"):find(hydroxideCommit, 1, true))

local runtimePath = "dist/runtime.lua"
assert(fs.isFile(runtimePath), "Shared runtime bundle is missing")
local runtimeSource = fs.readFile(runtimePath)
assert(#runtimeSource < 1000000, "Shared runtime bundle must not embed the compiled menu")
assert(
    not runtimeSource:find("C:/git", 1, true),
    "Runtime bundle must not contain a machine-local path"
)
local runtimeChunk, runtimeError = loadstring(runtimeSource, runtimePath)
local runtime = assert(runtimeChunk, runtimeError)()
assert(type(runtime.buildId) == "string" and runtime.buildId ~= "")
assert(type(runtime.run) == "function")

local definitions = {}
for _, path in ipairs(catalog) do
    table.insert(definitions, require("../" .. path))
end
local inventory = Sources.new({ catalog = catalog, definitions = definitions })

for _, definition in ipairs(definitions) do
    local path = "dist/games/" .. definition.id .. ".lua"
    assert(fs.isFile(path), "Missing game bundle: " .. definition.id)
    local chunk, compileError = loadstring(fs.readFile(path), path)
    local bundle = assert(chunk, compileError)()
    assert(bundle.id == definition.id)
    assert(bundle.buildId == runtime.buildId, "Runtime/game bundle build IDs must match")

    local expected = {}
    for _, sourcePath in ipairs(inventory:All()) do
        if inventory:Owner(sourcePath) == definition.id then
            expected[sourcePath .. ".lua"] = true
        end
    end
    for sourcePath, source in pairs(bundle.sources) do
        assert(
            expected[sourcePath],
            definition.id .. " bundle contains unowned source " .. sourcePath
        )
        assert(type(source) == "string" and source ~= "")
        expected[sourcePath] = nil
    end
    assert(next(expected) == nil, definition.id .. " bundle is missing an owned source")

    for _, id in ipairs(definition.manifest.gameIds or {}) do
        assert(runtime.gameIds[tostring(id)] == definition.id)
    end
    for _, id in ipairs(definition.manifest.placeIds or {}) do
        assert(runtime.placeIds[tostring(id)] == definition.id)
    end
end

local mismatchOk, mismatchError = pcall(runtime.run, {
    id = definitions[1].id,
    buildId = "stale-build",
    sources = {},
})
assert(not mismatchOk and tostring(mismatchError):find("builds do not match", 1, true))

local loaderSource = fs.readFile("loader.lua")
assert(
    loaderSource:find("runtime.placeIds[tostring(game.PlaceId)]", 1, true)
        and loaderSource:find("or runtime.gameIds[tostring(game.GameId)]", 1, true),
    "Bundled loader must preserve Registry place-ID priority"
)

print("runtime-bundle-contracts-ok")
