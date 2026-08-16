local fs = require("@lune/fs")
local Definition = require("../games/rivals/Definition")
local ItemInput = require("../games/rivals/libraries/ItemInput")

assert(table.find(Definition.sources, "games/rivals/libraries/ItemInput"))

assert(ItemInput.START_SHOOTING == "StartShooting")
assert(ItemInput.FINISH_SHOOTING == "FinishShooting")
assert(ItemInput.START_AIMING == "StartAiming")
assert(ItemInput.FINISH_AIMING == "FinishAiming")
assert(ItemInput.EQUIP_PRIMARY == "EquipPrimary")
assert(ItemInput.EQUIP_SECONDARY == "EquipSecondary")

assert(ItemInput.dispatch(nil, ItemInput.START_SHOOTING) == false)
assert(ItemInput.dispatch({}, ItemInput.START_SHOOTING) == false)
assert(ItemInput.dispatch({ Input = true }, ItemInput.START_SHOOTING) == false)
assert(ItemInput.dispatch({
    Input = function()
        return true
    end,
}, "") == false)

local actions = {}
local fighter = {}
function fighter.Input(_self, action)
    table.insert(actions, action)
    return true
end
assert(ItemInput.dispatch(fighter, ItemInput.START_SHOOTING) == true)
assert(ItemInput.dispatch(fighter, ItemInput.START_AIMING) == true)
assert(ItemInput.dispatch(fighter, ItemInput.FINISH_AIMING) == true)
assert(ItemInput.dispatch(fighter, ItemInput.FINISH_SHOOTING) == true)
assert(actions[1] == "StartShooting")
assert(actions[2] == "StartAiming")
assert(actions[3] == "FinishAiming")
assert(actions[4] == "FinishShooting")

assert(ItemInput.dispatch({
    Input = function()
        error("blocked")
    end,
}, ItemInput.START_SHOOTING) == false)
assert(ItemInput.dispatch({
    Input = function()
        return false
    end,
}, ItemInput.START_SHOOTING) == false)

assert(ItemInput.equipAction({ Info = { Class = "Primary" } }) == "EquipPrimary")
assert(ItemInput.equipAction({ Info = { Class = "Secondary" } }) == "EquipSecondary")
assert(ItemInput.equipAction({ Info = { Class = "Melee" } }) == nil)
assert(ItemInput.equipAction({}) == nil)

local adapter = fs.readFile("games/rivals/Adapter.lua")
assert(adapter:find("ItemInput.dispatch", 1, true), "Adapter must dispatch through ItemInput")
assert(not adapter:find("context.click", 1, true), "Adapter must not fire through simulated primary click")
assert(not adapter:find("context.aimClick", 1, true), "Adapter must not fire through simulated secondary click")
assert(not adapter:find("context.keyPress", 1, true), "Adapter must not equip through simulated keypress")
assert(not adapter:find("mouse1click", 1, true))
assert(not adapter:find("mouse2click", 1, true))

print("rivals-item-input-contracts-ok")
