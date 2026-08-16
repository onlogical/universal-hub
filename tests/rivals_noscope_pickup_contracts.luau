local Definition = require("../games/rivals/Definition")
local NoScope = require("../games/rivals/features/NoScope")
local Pickup = require("../games/rivals/features/Pickup")
local Session = require("../games/rivals/Session")

assert(table.find(Definition.sources, "games/rivals/features/NoScope"))
assert(table.find(Definition.sources, "games/rivals/features/Pickup"))

assert(NoScope.enabled({ alwaysScoped = true }) == true)
assert(NoScope.enabled({ alwaysScoped = false }) == false)
assert(NoScope.shouldRefresh({ alwaysScoped = true, shotAim = false }) == true)
assert(NoScope.shouldRefresh({ alwaysScoped = false, shotAim = true }) == true)
assert(NoScope.shouldRefresh({ alwaysScoped = false, shotAim = false }) == false)

local updates = 0
local session = Session.new()
session.settings = { autoPickup = false }
assert(Pickup.update(session, {
    update = function()
        updates += 1
    end,
}) == false and updates == 0)

session.settings.autoPickup = true
assert(Pickup.update(session, {
    update = function()
        updates += 1
    end,
}) == true and updates == 1)

print("rivals-noscope-pickup-contracts-ok")
