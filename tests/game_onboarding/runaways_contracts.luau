local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
Enum = roblox.Enum

local Catalog = require("../../games/Catalog")
local Definition = require("../../games/runaways/Definition")
local Registry = require("../../modules/Registry")
local Targeting = require("../../games/runaways/Targeting")
local Movement = require("../../games/runaways/features/Movement")

assert(table.find(Catalog, "games/runaways/Definition"))
assert(Definition.id == "runaways" and Definition.label == "RUNAWAYS")
assert(Definition.manifest.gameIds[1] == 7585140258)
assert(table.find(Definition.manifest.placeIds, 118418618261207))
assert(table.find(Definition.manifest.placeIds, 117311404196294))
assert(table.find(Definition.features.capabilities, "boxes"))
assert(table.find(Definition.features.capabilities, "fly"))
assert(table.find(Definition.sources, "games/runaways/features/Movement"))

local registry = Registry.new()
registry:Register(Definition)
assert(registry:Resolve({ gameId = 7585140258, placeId = 117311404196294 }).id == "runaways")

local livingCharacter = {
    FindFirstChildOfClass = function()
        return { Health = 100 }
    end,
}
local localPlayer = { Character = livingCharacter }
local otherPlayer = { Character = livingCharacter }
assert(Targeting.isOpponent(localPlayer, otherPlayer))
assert(not Targeting.isOpponent(localPlayer, localPlayer))

local humanoid = { Parent = true, PlatformStand = false, WalkSpeed = 16 }
local root = { AssemblyLinearVelocity = Vector3.zero }
local character = {
    FindFirstChildOfClass = function(_self, name)
        return name == "Humanoid" and humanoid or nil
    end,
    FindFirstChild = function(_self, name)
        return name == "HumanoidRootPart" and root or nil
    end,
}
local pressed = { [Enum.KeyCode.W] = true, [Enum.KeyCode.Space] = true }
local movement = Movement.new()
movement:update({ fly = true, flySpeed = 80, speed = true, walkSpeed = 48 }, character, {
    CFrame = roblox.CFrame.new(),
}, {
    IsKeyDown = function(_self, key)
        return pressed[key] == true
    end,
})
assert(humanoid.PlatformStand == true and humanoid.WalkSpeed == 48)
assert(math.abs(root.AssemblyLinearVelocity.Magnitude - 80) < 0.001)
movement:stop()
assert(humanoid.PlatformStand == false and humanoid.WalkSpeed == 16)

print("runaways-contracts-ok")
