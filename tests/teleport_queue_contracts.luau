local fs = require("@lune/fs")

local init = fs.readFile("init.lua")
local localLoader = fs.readFile("local.lua")
local remoteLoader = fs.readFile("loader.lua")

assert(
    init:find("configDefaults.autoExecuteOnTeleport = false", 1, true),
    "Teleport auto execution must default off as a generic hub setting"
)
assert(
    init:find('"autoExecuteOnTeleport",', 1, true)
        and init:find('"Auto Execute on Teleport"', 1, true),
    "Every game presentation must expose the generic teleport option"
)
assert(
    init:find("UniversalHubTeleportQueueOwned", 1, true)
        and init:find("clearteleportqueue", 1, true),
    "The hub must own and cancel only the teleport queue it enabled"
)
assert(
    localLoader:find("configuration.TeleportBootstrapSource", 1, true)
        and remoteLoader:find("configuration.TeleportBootstrapSource", 1, true),
    "Both loaders must provide their bootstrap without enabling it implicitly"
)
assert(
    not localLoader:find("pcall(queue", 1, true)
        and not remoteLoader:find("queueNextPlace", 1, true),
    "Loaders must not bypass the saved hub option"
)

print("teleport-queue-contracts-ok")
