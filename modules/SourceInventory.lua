local SourceInventory = {}
SourceInventory.__index = SourceInventory

local CORE = {
    "modules/Store",
    "modules/Config",
    "modules/InputCapture",
    "modules/MenuToggle",
    "modules/Registry",
    "modules/Session",
    "modules/Overlay",
    "modules/PresentationHost",
    "modules/presentation/Runtime",
    "modules/presentation/StandardPanels",
    "modules/presentation/CosmeticsPanel",
    "modules/SourceInventory",
    "games/Compatibility",
    "games/Catalog",
}

local function copyList(source)
    local copy = {}
    for index, value in ipairs(source) do
        copy[index] = value
    end
    return copy
end

local function validPath(path)
    return type(path) == "string"
        and path ~= ""
        and path:match("^[%w_/%-]+$") ~= nil
        and not path:find("//", 1, true)
end

local function appendUnique(ordered, seen, path)
    if not seen[path] then
        seen[path] = true
        table.insert(ordered, path)
    end
end

function SourceInventory.Core()
    return copyList(CORE)
end

function SourceInventory.new(options)
    assert(type(options) == "table", "Source inventory options must be a table")
    assert(type(options.catalog) == "table", "Source inventory catalog must be a table")
    assert(type(options.definitions) == "table", "Source inventory definitions must be a table")
    assert(
        #options.catalog == #options.definitions,
        "Source inventory requires one definition per catalog entry"
    )

    local core = options.core or CORE
    assert(type(core) == "table", "Source inventory core must be a table")
    local ordered = {}
    local seen = {}
    local ownerByPath = {}
    for _, path in ipairs(core) do
        assert(validPath(path), "Invalid core source path: " .. tostring(path))
        assert(not ownerByPath[path], "Duplicate core source path: " .. path)
        ownerByPath[path] = "core"
        appendUnique(ordered, seen, path)
    end
    for _, path in ipairs(options.catalog) do
        assert(validPath(path), "Invalid catalog definition path: " .. tostring(path))
        if ownerByPath[path] and ownerByPath[path] ~= "core" then
            error("Catalog definition path conflicts with game source owner: " .. path, 2)
        end
        ownerByPath[path] = "core"
        appendUnique(ordered, seen, path)
    end

    local definitionById = {}
    local claims = {}
    for _, definition in ipairs(options.definitions) do
        assert(type(definition) == "table", "Source inventory definition must be a table")
        assert(
            type(definition.id) == "string" and definition.id ~= "",
            "Source inventory definition requires an id"
        )
        assert(
            not definitionById[definition.id],
            "Duplicate source inventory definition id: " .. definition.id
        )
        assert(
            type(definition.sources) == "table",
            "Source inventory definition sources must be a table"
        )
        definitionById[definition.id] = definition
        for _, path in ipairs(definition.sources) do
            assert(validPath(path), "Invalid game source path: " .. tostring(path))
            claims[path] = claims[path] or {}
            claims[path][definition.id] = true
            appendUnique(ordered, seen, path)
        end
    end

    for path, owners in pairs(claims) do
        if ownerByPath[path] ~= "core" then
            local ids = {}
            for id in pairs(owners) do
                table.insert(ids, id)
            end
            table.sort(ids)
            if #ids > 1 then
                error(
                    ("Source path owned by multiple game definitions: %s (%s)"):format(
                        path,
                        table.concat(ids, ", ")
                    ),
                    2
                )
            end
            ownerByPath[path] = ids[1]
        end
    end

    return setmetatable({
        catalog = copyList(options.catalog),
        definitionById = definitionById,
        ordered = ordered,
        ownerByPath = ownerByPath,
    }, SourceInventory)
end

function SourceInventory:All()
    return copyList(self.ordered)
end

function SourceInventory:Allow(selectedId)
    local selected = self.definitionById[selectedId]
    assert(selected, "Unknown selected game definition: " .. tostring(selectedId))
    local allowed = {}
    for path, owner in pairs(self.ownerByPath) do
        if owner == "core" or owner == selectedId then
            allowed[path] = true
        end
    end
    return allowed
end

function SourceInventory:Owner(path)
    return self.ownerByPath[path]
end

return SourceInventory
