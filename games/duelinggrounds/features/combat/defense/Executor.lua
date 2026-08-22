local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Styles = importDependency("games/duelinggrounds/features/combat/Styles", "../Styles")

local Executor = {}
Executor.__index = Executor

local DODGE_COOLDOWN = 0.35
local PARRY_COOLDOWN = 0.05
local PARRY_HOLD_TIME = 0.12

function Executor.new(context)
    assert(context and context.characterController, "Defense Executor requires CharacterController")
    return setmetatable({
        context = context,
        lastDodgeAt = -math.huge,
        lastParryAt = -math.huge,
        activeParryBlock = nil,
        dodgeCounterDirection = 1,
        pendingCounterAt = nil,
        pendingCounterUntil = nil,
        pendingCounterAttack = "Light",
        stopped = false,
    }, Executor)
end

function Executor:_parry()
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager then
        return false, "action manager unavailable"
    end
    if actionManager.BlockAction then
        return false, "block action active"
    end
    local now = os.clock()
    if now - self.lastParryAt < PARRY_COOLDOWN then
        return false, "parry cooldown"
    end
    if (actionManager._blockStrength or 0) <= 0.01 then
        return false, "block strength depleted"
    end
    local canStart, replaceCurrent = actionManager:CanStartBlock()
    if not canStart then
        return false, actionManager.CurrentAction and "current action locked" or "parry unavailable"
    end
    local currentAction = actionManager.CurrentAction
    actionManager:_clearQueuedAction()
    local block = actionManager:SwitchBlock(true, {
        blockStrength = actionManager._blockStrength or 1,
    })
    if replaceCurrent and currentAction then
        actionManager:_replaceActionWith(currentAction, block)
        actionManager.CurrentAction = nil
    end
    self.activeParryBlock = block
    self.lastParryAt = now
    task.delay(PARRY_HOLD_TIME, function()
        if self.activeParryBlock == block then
            block._wantsToRelease = true
            self.activeParryBlock = nil
        end
    end)
    return true
end

function Executor:_dodge(intent, settings, target, dynamicState)
    local now = os.clock()
    if now - self.lastDodgeAt < DODGE_COOLDOWN then
        return false, "dodge cooldown"
    end
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager then
        return false, "action manager unavailable"
    end
    if not actionManager:CanStartDodge() then
        return false, actionManager.CurrentAction and "current action locked" or "dodge unavailable"
    end
    local root = handler.Root
    local offset = target and root and target.Position - root.Position or Vector3.zero
    local direction = Vector3.new(offset.X, 0, offset.Z)
    if direction.Magnitude <= 0.001 then
        local camera = self.context.workspace.CurrentCamera
        local look = camera and camera.CFrame.LookVector or Vector3.zAxis
        direction = Vector3.new(look.X, 0, look.Z)
    end
    direction = direction.Magnitude > 0 and direction.Unit or Vector3.zAxis
    local model = handler.OriginalModel or handler.Model
    local preferences = Styles.preferences(settings.combatStyle, {
        health = model and model:GetAttribute("Health"),
        maximumHealth = model and model:GetAttribute("MaxHealth"),
        posture = model and model:GetAttribute("Posture"),
        maximumPosture = model and model:GetAttribute("MaxPosture"),
        defenseReady = (actionManager._dodgeStamina or 0) >= 0.99
            and (actionManager._blockStrength or 0) > 0.01,
    }, dynamicState)
    local counterAllowed = preferences.counterAllowed
    local reverse = true
    if intent.mode == "heavy" and target and root then
        local lateral = Vector3.new(-direction.Z, 0, direction.X) * self.dodgeCounterDirection
        local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
        direction = distance > 9 and (lateral * 0.8 + direction * 0.6).Unit or lateral
        self.dodgeCounterDirection = -self.dodgeCounterDirection
        reverse = false
    elseif counterAllowed and target and root then
        if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 8 then
            direction = Vector3.new(-direction.Z, 0, direction.X) * self.dodgeCounterDirection
            self.dodgeCounterDirection = -self.dodgeCounterDirection
        end
        reverse = false
    else
        direction = -direction
    end
    actionManager:_clearQueuedAction()
    actionManager:SwitchToAction("Dodge", {
        direction = direction,
        isReverse = reverse,
        dodgeStamina = actionManager._dodgeStamina,
    })
    self.lastDodgeAt = now
    if counterAllowed then
        self.pendingCounterAt = intent.mode == "heavy" and now or now + 0.16
        self.pendingCounterUntil = now + 0.32
        self.pendingCounterAttack = intent.mode == "heavy"
                and settings.combatStyle == "flashy"
                and "Heavy"
            or "Light"
    else
        self.pendingCounterAt = nil
        self.pendingCounterUntil = nil
    end
    return true
end

function Executor:availability()
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager then
        return { canDodge = false, canParry = false, dodgeStamina = 0 }
    end
    local now = os.clock()
    local dodgeStamina = actionManager._dodgeStamina or 0
    local canDodge = dodgeStamina >= 0.99
        and now - self.lastDodgeAt >= DODGE_COOLDOWN
        and actionManager:CanStartDodge()
    local canParry = false
    if
        not actionManager.BlockAction
        and (actionManager._blockStrength or 0) > 0.01
        and now - self.lastParryAt >= PARRY_COOLDOWN
    then
        canParry = actionManager:CanStartBlock()
    end
    return {
        canDodge = canDodge == true,
        canParry = canParry == true,
        dodgeStamina = dodgeStamina,
        currentAction = actionManager.CurrentAction,
    }
end

function Executor:execute(intent, settings, target, dynamicState)
    if self.stopped then
        return false, "stopped"
    end
    if intent.kind == "dodge" then
        return self:_dodge(intent, settings, target, dynamicState)
    end
    return self:_parry()
end

function Executor:disposition()
    return {
        lastDodgeAt = self.lastDodgeAt,
        lastParryAt = self.lastParryAt,
        pendingCounterAt = self.pendingCounterAt,
        pendingCounterUntil = self.pendingCounterUntil,
        activeParry = self.activeParryBlock ~= nil,
    }
end

function Executor:consumeCounter()
    local pendingAt, pendingUntil, attack =
        self.pendingCounterAt, self.pendingCounterUntil, self.pendingCounterAttack
    self.pendingCounterAt = nil
    self.pendingCounterUntil = nil
    self.pendingCounterAttack = "Light"
    return pendingAt, pendingUntil, attack
end

function Executor:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self.pendingCounterAt = nil
    self.pendingCounterUntil = nil
    if self.activeParryBlock then
        self.activeParryBlock._wantsToRelease = true
        self.activeParryBlock = nil
    end
end

return Executor
