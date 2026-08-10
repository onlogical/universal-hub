local fs = require("@lune/fs")
local source = fs.readFile("games/rivals/Adapter.lua")

assert(source:find('local TaskPolicy = importDependency("games/rivals/TaskPolicy", "./TaskPolicy")', 1, true), "loadout picker must import the combat-task policy it calls")
assert(source:find('PickWeaponsPage.OpenChanged:Connect', 1, true), "loadout picker must wake from the native open signal")
assert(source:find('PageFrame:GetPropertyChangedSignal("Visible")', 1, true), "loadout picker must wake from native page visibility")
assert(source:find('local useCounter = rawCounter or counterActive', 1, true), "pre-round loadout selection must not wait through counter hysteresis")
assert(source:find('PickWeaponsPage._chosen_weapons[loadoutIndex] == desired', 1, true), "loadout selection must use native chosen state as acknowledgement")
assert(source:find('pcall(context.fireSignal, button.MouseButton1Click)', 1, true), "loadout selection must use the visible native button signal")
assert(not source:find('PickWeaponsPage:PickWeapon', 1, true), "loadout selection must not invoke PickWeapon directly")
assert(not source:find('PickWeaponsPage:Finish', 1, true), "loadout selection must not invoke Finish directly")
assert(not source:find('elseif loadoutIndex == #loadoutPlan', 1, true), "loadout picker must not report submission before native acknowledgement")

print("rivals-loadout-picker-contracts-ok")
