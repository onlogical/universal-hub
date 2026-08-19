local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local Sampler = require("../games/duelinggrounds/recording/Sampler")

local function model(attributes, humanoidHealth)
    return {
        GetAttribute = function(_, name)
            return attributes[name]
        end,
        FindFirstChildOfClass = function(_, className)
            if className == "Humanoid" and humanoidHealth ~= nil then
                return { Health = humanoidHealth }
            end
            return nil
        end,
    }
end

local localModel = model({ Health = 0, Posture = 0 }, 88)
local targetModel = model({ Posture = 12 }, 76)
local sample = Sampler.sample({
    localHandler = {
        Model = localModel,
        Root = { Position = Vector3.new(0, 5, 0) },
        ActionManager = {
            CurrentAction = { ActionType = "Attack", CanCancel = false },
            _dodgeStamina = 3,
            _blockStrength = 4,
        },
        IsBlocking = true,
        IsParrying = false,
        IsDodging = false,
        CanPerformUltimate = function()
            return true
        end,
    },
    targetHandler = {
        Root = { Position = Vector3.new(3, 100, 4) },
        ActionManager = { CurrentAction = { ActionType = "Block" } },
        IsBlocking = false,
        IsParrying = true,
        IsDodging = true,
    },
    targetModel = targetModel,
    dynamicMode = "defensive",
    defense = "parry",
    critical = true,
    punishWindow = 0.3,
    selfFrameData = { attack = "Light01", startup = 0.1, recovery = 0.5, comboGap = 0.2 },
    targetFrameData = { attack = "Heavy01", startup = 0.4, recovery = 0.8, comboGap = 0.3 },
}, { combatStyle = "dynamic" }, 0.25)

assert(sample.t == 0.25 and sample.distance == 5, "Distance must ignore vertical offset")
assert(sample.selfHealth == 0, "A native zero Health attribute must not fall through")
assert(sample.selfPosture == 0, "A native zero Posture attribute must be preserved")
assert(sample.targetHealth == 76, "Humanoid health must be used when native Health is absent")
assert(sample.targetPosture == 12)
assert(sample.dynamicMode == "defensive" and sample.defense == "parry")
assert(sample.selfCanUltimate and sample.critical)
assert(sample.punishWindow == 0.3)
assert(sample.selfAttack == "Light01" and sample.selfStartup == 0.1 and sample.selfRecovery == 0.5)
assert(sample.targetAttack == "Heavy01" and sample.targetStartup == 0.4 and sample.targetRecovery == 0.8)

print("duelinggrounds-recording-sampler-contracts-ok")
