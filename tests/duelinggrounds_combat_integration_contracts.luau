local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local DefenseExecutor = require("../games/duelinggrounds/features/combat/defense/Executor")
local OffenseExecutor = require("../games/duelinggrounds/features/combat/offense/Executor")

local queued
local actionManager = {
    CurrentAction = { ActionType = "Dodge" },
    _dodgeStamina = 1,
    _blockStrength = 1,
    _clearQueuedAction = function() end,
    _resolveAttackName = function(_, attack)
        return attack == "Heavy" and "DashHeavy" or "DashLight"
    end,
    CanStartDodge = function()
        return true
    end,
    CanStartBlock = function()
        return true
    end,
    TryQueueBasicAttack = function(_, attack)
        queued = attack
        return true
    end,
}
local attackInfo = {
    impacts = {
        {
            markerTime = 0.1,
            impactInfo = {
                hitboxCFrame = CFrame.new(0, 0, -2),
                hitboxSize = Vector3.new(6, 6, 6),
            },
        },
    },
}
local localRoot = {
    Position = Vector3.zero,
    CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1)),
    AssemblyLinearVelocity = Vector3.zero,
}
local targetPosition = (localRoot.CFrame * CFrame.new(0, 0, -2)).Position
local targetRoot = {
    Position = targetPosition,
    CFrame = CFrame.new(targetPosition),
    AssemblyLinearVelocity = Vector3.zero,
}
local handler = {
    ActionManager = actionManager,
    Root = localRoot,
    GetEquippedWeaponHandler = function()
        return {
            WeaponInfo = {
                BasicAttackTypes = {
                    DashHeavy = attackInfo,
                    DashLight = attackInfo,
                },
            },
        }
    end,
}
local controller = {
    GetLocalCharacterHandler = function()
        return handler
    end,
}
local defense = DefenseExecutor.new({
    characterController = controller,
    workspace = { CurrentCamera = nil },
})
defense.pendingCounterAt = 0
defense.pendingCounterUntil = os.clock() + 1
defense.pendingCounterAttack = "Heavy"

local pendingAt, pendingUntil, attack = defense:consumeCounter()
assert(pendingAt == 0 and pendingUntil and attack == "Heavy")

local offense = OffenseExecutor.new({
    characterController = controller,
    targetLockController = {},
    ping = function()
        return 0
    end,
    random = {
        NextNumber = function(_, minimum, maximum)
            return minimum and (minimum + maximum) / 2 or 0.5
        end,
    },
})
offense:setDodgeCounter(0, os.clock() + 1, attack)
assert(offense:_tryDodgeCounter(actionManager, targetRoot, {
    incomingThreat = false,
    targetDodging = false,
    targetParrying = false,
}))
assert(queued == "Heavy", "Flashy heavy dodges must request the native DashHeavy variation")

print("duelinggrounds-combat-integration-contracts-ok")
