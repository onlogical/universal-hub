local fs = require("@lune/fs")

local init = fs.readFile("init.lua")
local localLoader = fs.readFile("local.lua")
local remoteLoader = fs.readFile("loader.lua")

assert(
    not init:find("autoExecuteOnTeleport", 1, true)
        and not init:find("UniversalHubTeleportQueueOwned", 1, true)
        and not init:find("clearteleportqueue", 1, true),
    "Teleport persistence must be loader infrastructure, not a hub setting"
)
assert(
    localLoader:find("local queue =", 1, true)
        and localLoader:find("pcall(queue", 1, true)
        and localLoader:find("UniversalHubTeleportBootstrap = true", 1, true),
    "The local loader must automatically queue its local bootstrap"
)
assert(
    remoteLoader:find("local function queueNextPlace()", 1, true)
        and remoteLoader:find("pcall(queue", 1, true)
        and remoteLoader:find("UniversalHubConfig.SourceBaseUrl", 1, true),
    "The remote loader must automatically queue its matching remote bootstrap"
)
assert(
    remoteLoader:find("if sourceRoot ~= officialSourceRoot then", 1, true),
    "A custom remote source must provide its own safe teleport bootstrap"
)

print("teleport-queue-contracts-ok")
