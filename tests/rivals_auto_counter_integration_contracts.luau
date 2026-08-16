local fs = require("@lune/fs")

local adapter = fs.readFile("games/rivals/Adapter.lua")
local definition = fs.readFile("games/rivals/Definition.lua")
local init = fs.readFile("init.lua")
local localLoader = fs.readFile("local.lua")
local presentation = fs.readFile("games/rivals/Presentation.lua")
local simulator = fs.readFile("games/rivals/features/AutoCounterTestSimulator.lua")

local function contains(source, needle, message)
    assert(string.find(source, needle, 1, true), message or ("missing: " .. needle))
end

contains(definition, '"autoCounter"', "RIVALS must declare the Auto Counter capability")
contains(definition, "autoCounter = false", "RIVALS must keep Auto Counter default off")
contains(definition, '"games/rivals/features/AutoCounterRuntime"')
contains(definition, '"games/rivals/features/AutoCounterTestSimulator"')
assert(
    not string.find(presentation, 'host:option("trigger", 3, "autoCounter", "Auto Counter")', 1, true),
    "Auto Counter must stay off the Combat page until it ships"
)
contains(presentation, 'host:option("rage", 1, "teleportBehind", "Warp")')
assert(not string.find(presentation, "teleportOneShot", 1, true))
assert(not string.find(simulator, "Teleport Behind", 1, true), "The private simulator must have no UI")
assert(not string.find(simulator, 'teleportBehind", "Warp"', 1, true), "The private simulator must have no UI")
contains(init, "rivalsAutoCounterTest = configuration.RivalsAutoCounterTest")
contains(localLoader, "enabled = false", "local loads must keep the Auto Counter hop off")
assert(not string.find(localLoader, "UniversalHubCounterCandidate", 1, true))
assert(not string.find(init, "UniversalHubCounterCandidate", 1, true))
assert(not string.find(adapter, "UniversalHubCounterCandidate", 1, true))

contains(adapter, 'importDependency("games/rivals/features/AutoCounterRuntime"')
contains(adapter, '"games/rivals/features/AutoCounterTestSimulator"')
contains(adapter, "CombatState.isRoundEligible")
contains(adapter, "settings.autoCounter == true")
contains(adapter, "or settings.autoCounter == true")
contains(adapter, "AutoCounter.fire(")
contains(adapter, "autoCounterTestSimulator:update(false, false)")

local action = fs.readFile("games/rivals/features/AutoCounter.lua")
assert(not string.find(action, "FireServer", 1, true))
assert(not string.find(action, "InvokeServer", 1, true))
assert(not string.find(action, "PivotTo", 1, true))
assert(not string.find(action, ".CFrame =", 1, true), "Production Auto Counter must never move either fighter")
contains(action, "ctx.targeting.visibleBodyPoint")
contains(action, "ctx.runtime:consume(")
contains(action, "pcall(ctx.click)")

contains(simulator, "configuration.enabled == true")
contains(simulator, "root.CFrame = root.CFrame + self.offset")
contains(simulator, "self:_restore()")
assert(not string.find(simulator, "JobId", 1, true), "The local simulator must not carry stale job gates")
assert(not string.find(simulator, "UserId", 1, true), "The local simulator must not carry stale account gates")
assert(not string.find(simulator, "FireServer", 1, true))
assert(not string.find(simulator, "InvokeServer", 1, true))

print("rivals-auto-counter-integration-contracts-ok")
