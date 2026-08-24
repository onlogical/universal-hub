local fs = require("@lune/fs")
local source = fs.readFile("local.lua")
local function contains(value, message)
    assert(string.find(source, value, 1, true), message or ("missing loader contract: " .. value))
end
contains(
    "UniversalHubTeleportBootstrap = true",
    "queued teleports must identify the early bootstrap path"
)
contains("waitForNativeGameReady()", "queued RIVALS loads must gate the entire hub")
contains("game.GameId ~= 6035872082", "the native gate must remain game-scoped")
contains('playerGui:FindFirstChild("LoadingScreen")')
contains("while loadingScreen == nil", "the gate must not race a not-yet-created LoadingScreen")
contains("while loadingScreen.Parent ~= nil and loadingScreen.Enabled == true")
contains("staleMenu:Destroy()", "stale gethui UI must not stay interactive across teleport")
local gate = assert(string.find(source, "waitForNativeGameReady()", 1, true))
local load = assert(string.find(source, "return loadHub()", gate, true))
assert(gate < load, "native readiness must precede all menu and hub module evaluation")
print("rivals-loader-readiness-contracts-ok")
