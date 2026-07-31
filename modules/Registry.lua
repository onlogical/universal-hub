local Registry = {}
Registry.__index = Registry

local function validSourcePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:match("^[%w_/%-]+$") ~= nil
        and not path:find("//", 1, true)
end

local function validateManifestIds(manifest, field)
    local values = manifest[field]
    if values == nil then
        return 0
    end
    assert(type(values) == "table", "Game definition manifest " .. field .. " must be a table")

    local seen = {}
    for _, value in ipairs(values) do
        assert(
            type(value) == "number" and value > 0 and value % 1 == 0,
            "Game definition manifest ids must be positive integers"
        )
        assert(not seen[value], "Game definition manifest contains duplicate id: " .. tostring(value))
        seen[value] = true
    end
    return #values
end

local function validateData(value, path, seen)
    local valueType = type(value)
    assert(
        valueType == "nil"
            or valueType == "boolean"
            or valueType == "number"
            or valueType == "string"
            or valueType == "table",
        path .. " must contain only data"
    )
    if valueType ~= "table" then
        return
    end

    seen = seen or {}
    assert(not seen[value], path .. " must not contain cycles")
    seen[value] = true
    for key, child in pairs(value) do
        validateData(key, path .. " key", seen)
        validateData(child, path .. "." .. tostring(key), seen)
    end
    seen[value] = nil
end

local function validateStringList(values, path, allowed)
    assert(type(values) == "table", path .. " must be a table")
    local seen = {}
    for _, value in ipairs(values) do
        assert(type(value) == "string" and value ~= "", path .. " entries must be non-empty strings")
        assert(not seen[value], path .. " contains duplicate entry: " .. value)
        assert(not allowed or allowed[value], path .. " contains unsupported entry: " .. value)
        seen[value] = true
    end
end

function Registry.Validate(definition)
    assert(type(definition) == "table", "Game definition must be a table")
    assert(
        type(definition.id) == "string" and definition.id:match("%S") ~= nil,
        "Game definition requires a non-empty id"
    )
    assert(
        type(definition.label) == "string" and definition.label:match("%S") ~= nil,
        "Game definition requires a non-empty label"
    )
    assert(type(definition.manifest) == "table", "Game definition requires a manifest")

    local gameIdCount = validateManifestIds(definition.manifest, "gameIds")
    local placeIdCount = validateManifestIds(definition.manifest, "placeIds")
    assert(
        gameIdCount + placeIdCount > 0,
        "Game definition manifest requires a numeric gameId or placeId"
    )

    local hasModule = definition.module ~= nil
    local hasFactory = definition.factory ~= nil
    assert(hasModule ~= hasFactory, "Game definition requires exactly one module or factory")
    if hasModule then
        assert(validSourcePath(definition.module), "Game definition module must be a valid source path")
        assert(definition.match == nil, "Module game definitions must not contain runtime callbacks")
    else
        assert(type(definition.factory) == "function", "Game definition factory must be a function")
    end

    assert(type(definition.sources) == "table", "Game definition sources must be a table")
    local seenSources = {}
    for _, source in ipairs(definition.sources) do
        assert(
            type(source) ~= "string" or not source:match("%.lua$"),
            "Game definition sources use module paths without .lua"
        )
        assert(validSourcePath(source), "Game definition source must be a valid module path")
        assert(not seenSources[source], "Game definition contains duplicate source: " .. source)
        seenSources[source] = true
    end
    if hasModule then
        assert(seenSources[definition.module], "Game definition sources must include its module")
    end

    assert(type(definition.defaults) == "table", "Game definition defaults must be a table")
    assert(type(definition.initialState) == "table", "Game definition initialState must be a table")
    assert(type(definition.features) == "table", "Game definition features must be a table")
    validateStringList(definition.features.capabilities, "Game definition capabilities")
    assert(
        definition.features.cosmetics == nil or type(definition.features.cosmetics) == "boolean",
        "Game definition cosmetics must be a boolean when declared"
    )
    if definition.features.optionLabels ~= nil then
        assert(type(definition.features.optionLabels) == "table", "Game definition optionLabels must be a table")
    end
    if definition.features.exclusiveOptions ~= nil then
        assert(
            type(definition.features.exclusiveOptions) == "table",
            "Game definition exclusiveOptions must be a table"
        )
        for option, exclusions in pairs(definition.features.exclusiveOptions) do
            assert(type(option) == "string" and option ~= "", "Game definition exclusion keys must be strings")
            validateStringList(exclusions, "Game definition exclusion " .. option)
        end
    end
    validateStringList(definition.hydroxide, "Hydroxide requirements", {
        closure = true,
        lifecycle = true,
        targeting = true,
    })
    validateData(definition.defaults, "Game definition defaults")
    validateData(definition.initialState, "Game definition initialState")
    validateData(definition.features, "Game definition features")

    return definition
end

local function matchManifest(manifest, context)
    local score = 0

    for _, placeId in ipairs(manifest.placeIds or {}) do
        if placeId == context.placeId then
            score = math.max(score, 200)
        end
    end

    for _, gameId in ipairs(manifest.gameIds or {}) do
        if gameId == context.gameId then
            score = math.max(score, 100)
        end
    end

    return score
end

function Registry.new()
    return setmetatable({
        adapters = {},
        order = {},
    }, Registry)
end

function Registry:Register(definition)
    Registry.Validate(definition)
    assert(self.adapters[definition.id] == nil, "Duplicate game definition id: " .. definition.id)

    self.adapters[definition.id] = definition
    table.insert(self.order, definition)
    return definition
end

function Registry:Resolve(context)
    local selected = {}
    local selectedScore = 0

    for _, adapter in ipairs(self.order) do
        local score
        if type(adapter.match) == "function" then
            score = adapter.match(context)
            if score == true then
                score = 1
            elseif score == false or score == nil then
                score = 0
            end
        else
            score = matchManifest(adapter.manifest or {}, context)
        end

        if type(score) == "number" and score > selectedScore then
            selected = { adapter }
            selectedScore = score
        elseif type(score) == "number" and score > 0 and score == selectedScore then
            table.insert(selected, adapter)
        end
    end

    if #selected > 1 then
        local ids = {}
        for _, definition in ipairs(selected) do
            table.insert(ids, definition.id)
        end
        table.sort(ids)
        error(
            ("Ambiguous game definitions at score %s: %s"):format(
                tostring(selectedScore),
                table.concat(ids, ", ")
            ),
            2
        )
    end

    return selected[1], selectedScore
end

function Registry:List()
    local adapters = {}
    for _, adapter in ipairs(self.order) do
        table.insert(adapters, adapter)
    end
    table.sort(adapters, function(left, right)
        return left.id < right.id
    end)
    return adapters
end

return Registry
