local fs = require("@lune/fs")

local adapterSource = fs.readFile("games/DuelingGrounds.lua")
local definitionSource = fs.readFile("games/duelinggrounds/Definition.lua")
local presentationSource = fs.readFile("games/duelinggrounds/Presentation.lua")
local multiJumpSource = fs.readFile("games/duelinggrounds/features/MultiJump.lua")

assert(adapterSource:find('"games/duelinggrounds/features/MultiJump"', 1, true))
assert(adapterSource:find('"multiJump"', 1, true))
assert(adapterSource:find("multiJump:stop()", 1, true))
assert(definitionSource:find("multiJump = false", 1, true))
assert(definitionSource:find('"games/duelinggrounds/features/MultiJump"', 1, true))
assert(presentationSource:find('"multiJump", "Multi Jump"', 1, true))
assert(multiJumpSource:find("inputService.JumpRequest:Connect", 1, true))
assert(multiJumpSource:find("humanoid:ChangeState(Enum.HumanoidStateType.Jumping)", 1, true))

print("duelinggrounds-multi-jump-contracts-ok")
