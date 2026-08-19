local Persistence = require("../games/duelinggrounds/recording/Persistence")

local folders = {}
local path
local payload
local encoded
local persistence = Persistence.new({
    makefolder = function(folder)
        table.insert(folders, folder)
    end,
    isfolder = function()
        return false
    end,
    writefile = function(filePath, contents)
        path = filePath
        encoded = contents
    end,
    jsonEncode = function(value)
        payload = value
        return "encoded-json"
    end,
})

local match = {
    metadata = {
        id = 7,
        startedAt = 1234,
        target = "Bad/Name: Here!",
    },
    events = { { kind = "matchStarted", t = 0 } },
    samples = { { t = 0 } },
}
assert(persistence:save(1, match))
assert(folders[1] == "universal-hub/beta/logs")
assert(folders[2] == "universal-hub/beta/logs/duelinggrounds_1v1s")
assert(path == "universal-hub/beta/logs/duelinggrounds_1v1s/match_1234_0007_Bad_Name__Here_.json")
assert(match.metadata.file == path)
assert(encoded == "encoded-json")
assert(payload.version == 1 and payload.metadata == match.metadata)
assert(payload.events == match.events and payload.samples == match.samples)

assert(not Persistence.new():save(1, match), "Missing filesystem/JSON dependencies must be inert")

print("duelinggrounds-recording-persistence-contracts-ok")
