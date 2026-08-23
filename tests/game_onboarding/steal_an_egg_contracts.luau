local roblox = require("@lune/roblox")
Enum = roblox.Enum
Vector3 = roblox.Vector3

local Catalog = require("../../games/Catalog")
local Adapter = require("../../games/stealanegg/Adapter")
local AntiHit = require("../../games/stealanegg/features/AntiHit")
local AutoOpenEggs = require("../../games/stealanegg/features/AutoOpenEggs")
local Definition = require("../../games/stealanegg/Definition")
local HitAura = require("../../games/stealanegg/features/HitAura")
local InstantPrompts = require("../../games/stealanegg/features/InstantPrompts")
local Presentation = require("../../games/stealanegg/Presentation")

assert(type(Adapter.new) == "function")
assert(type(Presentation.mount) == "function")
assert(table.find(Catalog, "games/stealanegg/Definition"))
assert(Definition.id == "stealanegg")
assert(Definition.manifest.gameIds[1] == 10563114921)
assert(Definition.manifest.placeIds[1] == 107778070777162)
assert(Definition.defaults.antiHit == false)
assert(Definition.defaults.autoOpenEggs == false)
assert(Definition.defaults.hitAura == false)
assert(Definition.defaults.hitAuraIgnoreFriends == true)
assert(Definition.defaults.instantPrompts == false)
assert(table.find(Definition.features.capabilities, "antiHit"))
assert(table.find(Definition.features.capabilities, "autoOpenEggs"))
assert(table.find(Definition.features.capabilities, "hitAura"))
assert(table.find(Definition.features.capabilities, "hitAuraIgnoreFriends"))
assert(table.find(Definition.features.capabilities, "instantPrompts"))
assert(table.find(Definition.sources, "games/stealanegg/features/AntiHit"))
assert(table.find(Definition.sources, "games/stealanegg/features/AutoOpenEggs"))
assert(table.find(Definition.sources, "games/stealanegg/features/HitAura"))
assert(table.find(Definition.sources, "games/stealanegg/features/InstantPrompts"))

local presented = {}
Presentation.mount({
    section = function() end,
    option = function(_self, _section, _row, setting, _label, parent)
        presented[setting] = parent or true
    end,
})
assert(
    presented.antiHit
        and presented.autoOpenEggs
        and presented.hitAura
        and presented.hitAuraIgnoreFriends
        and presented.instantPrompts,
    "Presentation must expose every Steal An Egg tool"
)
assert(presented.hitAuraIgnoreFriends == "hitAura", "Ignore Friends must be a Hit Aura sub-toggle")

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

local auraHeartbeat = signal()
local auraNow = 10
local bat = {
    IsA = function(_self, className)
        return className == "Tool"
    end,
    GetAttribute = function(_self, name)
        return name == "IsBat" and true or nil
    end,
}
local function auraCharacter(position, tool)
    local root = { Position = position }
    local humanoid = { Health = 100 }
    return {
        GetChildren = function()
            return tool and { tool } or {}
        end,
        FindFirstChild = function(_self, name)
            return name == "HumanoidRootPart" and root or nil
        end,
        FindFirstChildOfClass = function(_self, className)
            return className == "Humanoid" and humanoid or nil
        end,
    }
end
local auraPlayer = {
    Character = auraCharacter(Vector3.zero, bat),
    UserId = 42,
    IsFriendsWith = function(_self, userId)
        return userId == 7
    end,
}
local friend = { Character = auraCharacter(Vector3.new(3, 0, 0)), UserId = 7 }
local enemy = { Character = auraCharacter(Vector3.new(5, 0, 0)), UserId = 8 }
local auraCalls = {}
local hitAura = HitAura.new({
    eggCmds = {
        GetAreaEggSnapshot = function()
            return {
                Records = {
                    { CarrierUserId = friend.UserId, State = "Carried" },
                    { CarrierUserId = enemy.UserId, State = "Carried" },
                },
            }
        end,
    },
    endpoint = "Bat:Activate",
    localPlayer = auraPlayer,
    network = {
        Fire = function(endpoint, target, traceId)
            table.insert(auraCalls, { endpoint = endpoint, target = target, traceId = traceId })
        end,
    },
    players = {
        GetPlayers = function()
            return { auraPlayer, friend, enemy }
        end,
    },
    runService = { Heartbeat = auraHeartbeat },
    workspace = {
        GetServerTimeNow = function()
            return auraNow
        end,
    },
})
hitAura:setEnabled(true)
auraHeartbeat:Fire()
assert(
    #auraCalls == 1 and auraCalls[1].target == enemy,
    "Hit Aura must skip a friend carrying an egg"
)
hitAura:setIgnoreFriends(false)
auraNow += 0.61
auraHeartbeat:Fire()
assert(
    #auraCalls == 2 and auraCalls[2].target == friend,
    "Hit Aura must target friends when allowed"
)
assert(auraCalls[2].endpoint == "Bat:Activate" and type(auraCalls[2].traceId) == "string")
hitAura:stop()
auraNow += 1
auraHeartbeat:Fire()
assert(#auraCalls == 2, "Disabled Hit Aura must stop native bat activations")

local autoOpenHeartbeat = signal()
local readyEggs = { ready = true }
local openedEggs = {}
local autoOpenEggs = AutoOpenEggs.new({
    eggCmds = {
        GetOwnerRuntimeRecords = function(userId)
            assert(userId == 42)
            return {
                inventory = {},
                later = { Placement = {} },
                ready = { Placement = {} },
            }
        end,
        IsLocalEggReady = function(uid)
            return readyEggs[uid] == true
        end,
    },
    localPlayer = { UserId = 42 },
    renderer = {
        ActivateLocalEgg = function(uid)
            table.insert(openedEggs, uid)
            return true
        end,
    },
    runService = { Heartbeat = autoOpenHeartbeat },
    spawn = function(callback)
        callback()
    end,
})
autoOpenEggs:setEnabled(true)
assert(#openedEggs == 1 and openedEggs[1] == "ready", "Ready placed eggs must open immediately")
readyEggs.later = true
autoOpenHeartbeat:Fire(0.25)
assert(
    #openedEggs == 2 and openedEggs[2] == "later",
    "Newly ready eggs must open without retrying active hatches"
)
autoOpenEggs:setEnabled(false)
autoOpenHeartbeat:Fire(1)
assert(#openedEggs == 2, "Disabled Auto Open Eggs must stop scanning")
autoOpenEggs:stop()

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
    MoveDirection = Vector3.new(1, 0, 0),
    PlatformStand = true,
    StateChanged = stateChanged,
    WalkSpeed = 16,
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
local dropRequestCount = 0
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
    RequestDropAreaEgg = function()
        dropRequestCount += 1
        return true
    end,
}
local nativeDropRequest = eggCmds.RequestDropAreaEgg
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
assert(
    rootPart.AssemblyLinearVelocity == Vector3.new(16, 0, 0),
    "Anti Hit must cancel knockback without stopping held-direction movement"
)
assert(rootPart.AssemblyAngularVelocity == Vector3.zero, "Anti Hit must cancel hit spin")
rootPart.AssemblyLinearVelocity = Vector3.new(9, 0, 0)
rootPart.AssemblyAngularVelocity = Vector3.new(0, 9, 0)
now += 0.1
postSimulation:Fire()
assert(
    rootPart.AssemblyLinearVelocity == Vector3.new(16, 0, 0),
    "Delayed knockback suppression must preserve held-direction movement"
)
assert(rootPart.AssemblyAngularVelocity == Vector3.zero, "Anti Hit must suppress delayed hit spin")
now += 0.4
rootPart.AssemblyLinearVelocity = Vector3.new(1, 0, 0)
postSimulation:Fire()
assert(
    rootPart.AssemblyLinearVelocity ~= Vector3.zero,
    "Normal movement must resume after recovery"
)
attributes.RagdollEndTime = now
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

table.clear(carryRequests)
record.State = "Carried"
record.CarrierUserId = player.UserId
carryChanged:Fire({ IsCarrying = true, Uid = record.Uid })
attributes.RagdollEndTime = now + 5
attributeChanged:Fire()
record.State = "Dropped"
record.CarrierUserId = nil
carryChanged:Fire({ IsCarrying = false, Uid = record.Uid })
assert(#carryRequests == 1, "Anti Hit must immediately reclaim eggs dropped during a hit")

table.clear(carryRequests)
assert(eggCmds.RequestDropAreaEgg("Manual") == true and dropRequestCount == 1)
record.State = "Dropped"
record.CarrierUserId = nil
carryChanged:Fire({ IsCarrying = false, Uid = record.Uid })
eggUpdated:Fire(record)
assert(#carryRequests == 0, "A user-requested drop must stop automatic pickup")
antiHit:setEnabled(false)
assert(eggCmds.RequestDropAreaEgg == nativeDropRequest, "Anti Hit must restore the native drop API")
attributeChanged:Fire()
assert(clearCount == 2, "Disabled Anti Hit must disconnect native state listeners")
antiHit:stop()

print("steal-an-egg-contracts-ok")
