local fs = require("@lune/fs")
local SourceInventory = require("../modules/SourceInventory")

local function definition(id, sources)
    return {
        id = id,
        sources = sources,
    }
end

local function expectError(fragment, callback)
    local succeeded, message = pcall(callback)
    assert(not succeeded, "Expected source inventory failure containing " .. fragment)
    assert(
        tostring(message):find(fragment, 1, true),
        ("Expected %q in %q"):format(fragment, tostring(message))
    )
end

local function duplicateOwners(first, second)
    expectError(
        "Source path owned by multiple game definitions: games/shared/Runtime (alpha, zeta)",
        function()
            SourceInventory.new({
                catalog = {
                    "games/" .. first .. "/Definition",
                    "games/" .. second .. "/Definition",
                },
                definitions = {
                    definition(first, { "games/shared/Runtime" }),
                    definition(second, { "games/shared/Runtime" }),
                },
            })
        end
    )
end
duplicateOwners("zeta", "alpha")
duplicateOwners("alpha", "zeta")

local shared = SourceInventory.new({
    catalog = {
        "games/alpha/Definition",
        "games/zeta/Definition",
    },
    core = {
        "games/shared/Runtime",
    },
    definitions = {
        definition("alpha", { "games/alpha/Adapter", "games/shared/Runtime" }),
        definition("zeta", { "games/zeta/Adapter", "games/shared/Runtime" }),
    },
})
assert(shared:Owner("games/shared/Runtime") == "core")
local sharedSources = shared:All()
local sharedCount = 0
for _, path in ipairs(sharedSources) do
    if path == "games/shared/Runtime" then
        sharedCount += 1
    end
end
assert(sharedCount == 1, "Explicit core sources must be fetched once")

local alphaAllowlist = shared:Allow("alpha")
assert(alphaAllowlist["games/shared/Runtime"])
assert(alphaAllowlist["games/alpha/Definition"])
assert(alphaAllowlist["games/zeta/Definition"])
assert(alphaAllowlist["games/alpha/Adapter"])
assert(
    not alphaAllowlist["games/zeta/Adapter"],
    "Selected runtime imports must exclude sources owned only by another definition"
)
assert(not alphaAllowlist["games/undeclared/Runtime"])
expectError("Unknown selected game definition: missing", function()
    shared:Allow("missing")
end)

local Catalog = require("../games/Catalog")
local definitions = {}
for _, path in ipairs(Catalog) do
    table.insert(definitions, require("../" .. path))
end
local inventory = SourceInventory.new({
    catalog = Catalog,
    definitions = definitions,
})
local declared = {}
for _, path in ipairs(inventory:All()) do
    assert(not declared[path], "Source inventory repeated " .. path)
    declared[path] = true
    assert(fs.isFile(path .. ".lua"), "Source inventory declares a missing file: " .. path)
end
for _, definitionValue in ipairs(definitions) do
    for _, source in ipairs(definitionValue.sources) do
        local sourceText = fs.readFile(source .. ".lua")
        for dependency in sourceText:gmatch('import%("([%w_/%-]+)"%)') do
            assert(
                declared[dependency],
                ("%s imports undeclared source %s"):format(source, dependency)
            )
        end
    end
end

print("source-inventory-contracts-ok")
