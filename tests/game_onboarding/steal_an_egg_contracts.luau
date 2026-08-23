local roblox = require("@lune/roblox")
Enum = roblox.Enum
Vector3 = roblox.Vector3

local Catalog = require("../../games/Catalog")
local Adapter = require("../../games/stealanegg/Adapter")
local AntiHit = require("../../games/stealanegg/features/AntiHit")
local Definition = require("../../games/stealanegg/Definition")
local InstantPrompts = require("../../games/stealanegg/features/InstantPrompts")
local Presentation = require("../../games/stealanegg/Presentation")

assert(type(Adapter.new) == "function")
assert(type(Presentation.mount) == "function")
assert(table.find(Catalog, "games/stealanegg/Definition"))
assert(Definition.id == "stealanegg")
assert(Definition.manifest.gameIds[1] == 10563114921)
assert(Definition.manifest.placeIds[1] == 107778070777162)
assert(Definition.defaults.antiHit == false)
assert(Definition.defaults.instantPrompts == false)
assert(table.find(Definition.features.capabilities, "antiHit"))
assert(table.find(Definition.features.capabilities, "instantPrompts"))
assert(table.find(Definition.sources, "games/stealanegg/features/AntiHit"))
assert(table.find(Definition.sources, "games/stealanegg/features/InstantPrompts"))

local presented = {}
Presentation.mount({
    section = function() end,
    option = function(_self, _section, _row, setting)
        presented[setting] = true
    end,
})
assert(presented.antiHit and presented.instantPrompts, "Presentation must expose both game tools")

local function signal()
    local callbacks = {}
    return {
        Connect = function(_self, callback)
            callbacks[callback] = true
            return {
                Disconnect = function()
                    callbacks[callback] = nil
                end,
            }
        end,
        Fire = function(_self, ...)
            for callback in pairs(callbacks) do
                callback(...)
            end
        end,
    }
end

local changed = signal()
local prompt = {
    HoldDuration = 2,
    Parent = true,
}
function prompt:IsA(className)
    return className == "ProximityPrompt"
end
function prompt:GetPropertyChangedSignal(property)
    assert(property == "HoldDuration")
    return changed
end

local added = signal()
local removing = signal()
local root = {
    DescendantAdded = added,
    DescendantRemoving = removing,
}
function root:GetDescendants()
    return { prompt }
end

local feature = InstantPrompts.new(root)
feature:setEnabled(true)
assert(prompt.HoldDuration == 0, "Enabling Instant Prompts must remove the current hold")
prompt.HoldDuration = 4
changed:Fire()
assert(prompt.HoldDuration == 0, "Instant Prompts must reject game-side hold resets")
feature:setEnabled(false)
assert(prompt.HoldDuration == 4, "Disabling Instant Prompts must restore the latest native hold")
feature:stop()
assert(prompt.HoldDuration == 4, "Instant Prompts stop must be idempotent")

local attributeChanged = signal()
local characterAdded = signal()
local stateChanged = signal()
local carryChanged = signal()
local eggUpdated = signal()
local postSimulation = signal()
local now = 100
local attributes = {}
local changedState
local humanoid = {
    PlatformStand = true,
    StateChanged = stateChanged,
    ChangeState = function(_self, state)
        changedState = state
    end,
}
local rootPart = {
    AssemblyAngularVelocity = Vector3.new(1, 2, 3),
    AssemblyLinearVelocity = Vector3.new(4, 5, 6),
}
local character = {
    FindFirstChild = function(_self, name)
        return name == "HumanoidRootPart" and rootPart or nil
    end,
    FindFirstChildOfClass = function(_self, className)
        return className == "Humanoid" and humanoid or nil
    end,
}
local player = {
    Character = character,
    CharacterAdded = characterAdded,
    UserId = 42,
    GetAttribute = function(_self, name)
        return attributes[name]
    end,
    GetAttributeChangedSignal = function(_self, name)
        assert(name == "RagdollEndTime")
        return attributeChanged
    end,
}
local record = {
    AreaId = "Forest",
    CarrierUserId = player.UserId,
    NestId = "Slot_002",
    State = "Carried",
    Uid = "egg-42",
}
local carryRequests = {}
local eggCmds = {
    AreaEggCarryStateChanged = carryChanged,
    AreaEggUpdated = eggUpdated,
    GetAreaEggRecord = function(uid)
        return uid == record.Uid and record or nil
    end,
    GetAreaEggSnapshot = function()
        return { Records = { record } }
    end,
    RequestCarryAreaEgg = function(uid, slotKey)
        table.insert(carryRequests, { slotKey = slotKey, uid = uid })
        record.State = "Carried"
        record.CarrierUserId = player.UserId
        return true
    end,
}
local clearCount = 0
local spawned = {}
local antiHit = AntiHit.new({
    eggCmds = eggCmds,
    localPlayer = player,
    ragdoll = {
        ClearClientRagdoll = function(receivedCharacter)
            assert(receivedCharacter == character)
            clearCount += 1
        end,
    },
    runService = {
        PostSimulation = postSimulation,
    },
    slotIdentity = {
        BuildSlotKey = function(areaId, nestId)
            return areaId .. ":" .. nestId
        end,
        IsFirstAreaUid = function()
            return true
        end,
    },
    spawn = function(callback)
        table.insert(spawned, callback)
    end,
    wait = function()
        now += 0.1
    end,
    workspace = {
        GetServerTimeNow = function()
            return now
        end,
    },
})
antiHit:setEnabled(true)
attributes.RagdollEndTime = now + 5
attributeChanged:Fire()
assert(clearCount == 1, "Anti Hit must clear the native client ragdoll immediately")
assert(humanoid.PlatformStand == false and changedState == Enum.HumanoidStateType.GettingUp)
assert(rootPart.AssemblyLinearVelocity == Vector3.zero, "Anti Hit must cancel hit knockback")
assert(rootPart.AssemblyAngularVelocity == Vector3.zero, "Anti Hit must cancel hit spin")
rootPart.AssemblyLinearVelocity = Vector3.new(9, 0, 0)
rootPart.AssemblyAngularVelocity = Vector3.new(0, 9, 0)
now += 0.1
postSimulation:Fire()
assert(rootPart.AssemblyLinearVelocity == Vector3.zero, "Anti Hit must suppress delayed knockback")
assert(rootPart.AssemblyAngularVelocity == Vector3.zero, "Anti Hit must suppress delayed hit spin")
now += 0.4
rootPart.AssemblyLinearVelocity = Vector3.new(1, 0, 0)
postSimulation:Fire()
assert(
    rootPart.AssemblyLinearVelocity ~= Vector3.zero,
    "Normal movement must resume after recovery"
)
record.State = "Dropped"
record.CarrierUserId = nil
carryChanged:Fire({ IsCarrying = false })
assert(#carryRequests == 1, "Anti Hit must request the dropped egg after a hit")
assert(carryRequests[1].uid == record.Uid)
assert(carryRequests[1].slotKey == "Forest:Slot_002")

table.clear(carryRequests)
record.State = "Carried"
record.CarrierUserId = player.UserId
carryChanged:Fire({ IsCarrying = true, Uid = record.Uid })
carryChanged:Fire({ IsCarrying = false, Uid = record.Uid })
assert(#carryRequests == 0, "Anti Hit must wait until the server marks the egg dropped")
record.State = "Dropped"
record.CarrierUserId = nil
eggUpdated:Fire(record)
assert(
    #carryRequests == 1 and carryRequests[1].uid == record.Uid,
    "Anti Hit must beat non-ragdoll animal and boss pickups to a dropped egg"
)
antiHit:setEnabled(false)
attributeChanged:Fire()
assert(clearCount == 1, "Disabled Anti Hit must disconnect native state listeners")
antiHit:stop()

print("steal-an-egg-contracts-ok")
