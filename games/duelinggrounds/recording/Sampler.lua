local Sampler = {}

local function attribute(model, name)
    if model and type(model.GetAttribute) == "function" then
        return model:GetAttribute(name)
    end
    return nil
end

local function humanoidHealth(model)
    if not model or type(model.FindFirstChildOfClass) ~= "function" then
        return nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health or nil
end

local function health(attributeModel, humanoidModel)
    local nativeHealth = attribute(attributeModel, "Health")
    if nativeHealth ~= nil then
        return nativeHealth
    end
    return humanoidHealth(humanoidModel or attributeModel)
end

local function action(handler)
    local manager = handler and handler.ActionManager
    return manager, manager and manager.CurrentAction
end

function Sampler.sample(frame, settings, elapsed)
    local localHandler = frame.localHandler
    local targetHandler = frame.targetHandler
    local localManager, localAction = action(localHandler)
    local targetManager, targetAction = action(targetHandler)
    local localModel = localHandler and (localHandler.OriginalModel or localHandler.Model)
        or frame.localModel
    local targetModel = frame.targetModel
    local localRoot = localHandler and localHandler.Root or frame.localRoot
    local targetRoot = targetHandler and targetHandler.Root or frame.targetRoot or frame.target
    local distance

    if localRoot and targetRoot then
        local offset = targetRoot.Position - localRoot.Position
        distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    end

    return {
        t = elapsed,
        distance = distance,
        style = settings.combatStyle,
        dynamicMode = settings.combatStyle == "dynamic" and frame.dynamicMode or nil,
        selfAction = localAction and localAction.ActionType or nil,
        selfCanCancel = localAction and localAction.CanCancel or nil,
        selfHealth = health(localModel, localHandler and localHandler.Model),
        selfPosture = attribute(localModel, "Posture"),
        selfBlocking = localHandler and localHandler.IsBlocking or false,
        selfParrying = localHandler and localHandler.IsParrying or false,
        selfDodging = localHandler and localHandler.IsDodging or false,
        selfCanUltimate = localHandler and localHandler:CanPerformUltimate() or false,
        targetAction = targetAction and targetAction.ActionType or nil,
        targetHealth = health(targetModel),
        targetPosture = attribute(targetModel, "Posture"),
        targetBlocking = targetHandler and targetHandler.IsBlocking or false,
        targetParrying = targetHandler and targetHandler.IsParrying or false,
        targetDodging = targetHandler and targetHandler.IsDodging or false,
        dodgeStamina = localManager and localManager._dodgeStamina or nil,
        blockStrength = localManager and localManager._blockStrength or nil,
        defense = frame.defense,
        critical = frame.critical == true,
    }
end

return Sampler
