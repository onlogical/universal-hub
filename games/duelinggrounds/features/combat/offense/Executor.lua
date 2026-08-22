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

local Attacks = importDependency("games/duelinggrounds/features/combat/Attacks", "../Attacks")
local Combos = importDependency("games/duelinggrounds/features/combat/Combos", "../Combos")
local JumpAttackPolicy =
    importDependency("games/duelinggrounds/features/combat/JumpAttackPolicy", "../JumpAttackPolicy")
local Skill = importDependency("games/duelinggrounds/features/combat/Skill", "../Skill")
local Styles = importDependency("games/duelinggrounds/features/combat/Styles", "../Styles")
local UltimatePolicy =
    importDependency("games/duelinggrounds/features/combat/UltimatePolicy", "../UltimatePolicy")

local Executor = {}
Executor.__index = Executor

local FIGHT_RETRY_INTERVAL = 0.05
local ULTIMATE_RETRY_INTERVAL = 0.2
local RECOVERY_MIN = 0.18
local RECOVERY_MAX = 0.65
local IMPACT_MARGIN = Vector3.new(1.5, 2.5, 0.75)

local function canReach(attacker, defender, attackInfo)
    if not attacker or not defender or not attackInfo then
        return false
    end
    local velocity = defender.AssemblyLinearVelocity or Vector3.zero
    local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontal.Magnitude > 18 then
        horizontal = horizontal.Unit * 18
    end
    for _, impact in ipairs(attackInfo.impacts or {}) do
        local impactTime = type(impact.markerTime) == "number" and impact.markerTime or 0
        local predicted = defender.Position + horizontal * math.clamp(impactTime, 0, 0.65)
        if Attacks.impactContainsPoint(attacker.CFrame, predicted, impact, IMPACT_MARGIN) then
            return true
        end
    end
    return false
end

function Executor.new(context)
    assert(context and context.characterController, "Offense Executor requires CharacterController")
    assert(context.targetLockController, "Offense Executor requires TargetLockController")
    return setmetatable({
        context = context,
        random = context.random or Random.new(),
        nextFightAt = 0,
        nextNeutralAttackAt = -math.huge,
        lastAttackAt = -math.huge,
        lastCriticalAt = -math.huge,
        lastUltimateAttemptAt = -math.huge,
        lastJumpAt = -math.huge,
        nextMixupAt = 0,
        pendingJumpUntil = nil,
        pendingCounterAt = nil,
        pendingCounterUntil = nil,
        pendingCounterAttack = "Light",
        comboLightCount = 0,
        stopped = false,
    }, Executor)
end

function Executor:setDodgeCounter(pendingAt, pendingUntil, attack)
    self.pendingCounterAt = pendingAt
    self.pendingCounterUntil = pendingUntil
    self.pendingCounterAttack = attack or "Light"
end

function Executor:_tryDodgeCounter(actionManager, targetRoot, disposition)
    if not self.pendingCounterUntil then
        return false
    end
    local now = os.clock()
    if now > self.pendingCounterUntil then
        self:_record("dodgeCounter", { result = "expired" })
        self.pendingCounterAt = nil
        self.pendingCounterUntil = nil
        return false
    end
    if now < (self.pendingCounterAt or 0) then
        return true
    end
    if disposition.incomingThreat then
        return true
    end
    if disposition.targetDodging or disposition.targetParrying then
        self:_record("dodgeCounter", { result = "targetInvulnerable" })
        return true
    end
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local root = handler and handler.Root
    local weapon = handler and handler:GetEquippedWeaponHandler()
    local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
    local attack = self.pendingCounterAttack
    local resolved = actionManager:_resolveAttackName(attack)
    local attackInfo = resolved and attackTypes and attackTypes[resolved]
    if not canReach(root, targetRoot, attackInfo) then
        self:_record("dodgeCounter", { result = "outOfRange", attack = resolved })
        return true
    end
    if actionManager:TryQueueBasicAttack(attack) then
        self:_record("dodgeCounter", {
            result = "queued",
            attack = resolved,
            variation = attack,
        })
        self.lastAttackAt = now
        self.pendingCounterAt = nil
        self.pendingCounterUntil = nil
    end
    return true
end

function Executor:recordAnimation(name)
    if string.match(name or "", "^Light%d+$") then
        self.comboLightCount += 1
    elseif
        string.match(name or "", "^Heavy%d+$")
        or name == "DashHeavy"
        or name == "JumpAttack"
    then
        self.comboLightCount = 0
    end
end

function Executor:_record(kind, data)
    if self.context.record then
        self.context.record(kind, data)
    end
end

function Executor:_queue(actionManager, attack, attackInfo, settings, disposition)
    local queued = actionManager:TryQueueBasicAttack(attack)
    local now = os.clock()
    if attack == "Ultimate" then
        self.lastUltimateAttemptAt = now
        self:_record("ultimateAttempt", { result = queued and "queueAccepted" or "rejected" })
    end
    if queued then
        self.lastAttackAt = now
        local recovery = disposition.targetBlocking
            or disposition.targetStaggered
            or disposition.punishWindow > 0 and RECOVERY_MIN
            or self.random:NextNumber(RECOVERY_MIN, RECOVERY_MAX)
        self.nextNeutralAttackAt = now
            + (Attacks.marker(attackInfo, "canCancel") or Attacks.firstImpactTime(attackInfo) or 0.5)
            + recovery
        if self.context.recordProbeAttack and settings.combatStyle == "dynamic" then
            self.context.recordProbeAttack(now)
        end
    end
    return queued
end

function Executor:attack(settings, frame, disposition)
    if self.stopped or settings.autoFight ~= true then
        return
    end
    local now = os.clock()
    if now < self.nextFightAt then
        return
    end
    self.nextFightAt = now + FIGHT_RETRY_INTERVAL

    local target = frame.target or self.context.targetLockController.Target
    local targetModel = frame.targetModel or target and target:FindFirstAncestorWhichIsA("Model")
    if not targetModel or targetModel:GetAttribute("IsDead") == true then
        return
    end
    local targetHandler = frame.targetHandler
        or self.context.characterController:GetCharacterHandler(targetModel)
    local targetRoot = frame.targetRoot or targetHandler and targetHandler.Root or target
    local handler = frame.localHandler
        or self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager or not handler.EquippedWeapon then
        return
    end
    local localModel = handler.OriginalModel or handler.Model
    local localPosture = localModel and localModel:GetAttribute("Posture")
    local maximumPosture = localModel and localModel:GetAttribute("MaxPosture")
    if
        type(localPosture) == "number"
        and type(maximumPosture) == "number"
        and maximumPosture > 0
        and localPosture / maximumPosture <= 0.25
    then
        if actionManager._queuedActionType then
            actionManager:_clearQueuedAction()
        end
        local current = actionManager.CurrentAction
        if current and current.ActionType == "BasicAttack" and current.CanCancel then
            actionManager:SwitchToAction(nil)
        end
        return
    end

    if settings.combatStyle == "defensive" then
        self.pendingJumpUntil = nil
        if
            actionManager._queuedActionType == "Jump"
            or actionManager._queuedActionType == "BasicAttack"
        then
            actionManager:_clearQueuedAction()
        end
        local current = actionManager.CurrentAction
        if current and current.ActionType == "BasicAttack" and current.CanCancel then
            actionManager:SwitchToAction(nil)
        end
        return
    end

    local criticalTarget = self.context.targetLockController.CriticalStrikeTarget
    local criticalModel = criticalTarget and criticalTarget.Parent
    if criticalModel and now - self.lastCriticalAt >= 0.25 then
        local criticalHandler = self.context.characterController:GetCharacterHandler(criticalModel)
        local criticalRoot = criticalHandler and criticalHandler.Root or criticalModel.PrimaryPart
        local weapon = handler:GetEquippedWeaponHandler()
        local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
        local ultimate = attackTypes and attackTypes.Ultimate
        if actionManager._queuedActionType then
            actionManager:_clearQueuedAction()
        end
        local current = actionManager.CurrentAction
        if current and current.ActionType == "BasicAttack" and current.CanCancel then
            actionManager:SwitchToAction(nil)
            current = nil
        end
        if
            ultimate
            and handler:CanPerformUltimate()
            and not current
            and not actionManager._queuedActionType
        then
            if self:_queue(actionManager, "Ultimate", ultimate, settings, disposition) then
                self:_record("criticalDecision", {
                    choice = "ultimate",
                    ultimateResult = "queued",
                    reason = "nativeCriticalTarget",
                })
                return
            end
        end
        self.context.criticalStrike(criticalModel)
        self.lastCriticalAt = now
        self.lastAttackAt = now
        return
    end

    if disposition.defenseIntent or disposition.incomingThreat then
        self.pendingJumpUntil = nil
        return
    end
    if self:_tryDodgeCounter(actionManager, targetRoot, disposition) then
        return
    end
    if disposition.targetDodging or disposition.targetParrying then
        self.pendingJumpUntil = nil
        return
    end
    if handler.IsParrying or actionManager.BlockAction then
        return
    end

    local current = actionManager.CurrentAction
    if
        current
        and current.ActionType == "BasicAttack"
        and current.CanQueueBasicAttacks
        and not actionManager._queuedActionType
    then
        local skill = Skill.profile(settings.botSkill)
        local preferences = Styles.preferences(settings.combatStyle, nil, disposition.dynamicState)
        local weapon = handler:GetEquippedWeaponHandler()
        local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
        local nextAttack, reason = Combos.nextAttack({
            weaponName = weapon and weapon.WeaponInfo.WeaponName,
            lightCount = self.comboLightCount,
            hasHeavy = attackTypes
                and attackTypes[actionManager:_resolveAttackName("Heavy")] ~= nil,
            targetBlocking = disposition.targetBlocking,
            style = settings.combatStyle,
            recentDeflects = #(disposition.dynamicState.deflectTimes or {}),
        })
        if
            nextAttack
            and (preferences.aggressiveCombos or Skill.shouldPunish(skill, self.random))
            and actionManager:TryQueueBasicAttack(nextAttack)
        then
            self.lastAttackAt = now
            self:_record("comboAttack", {
                result = "queued",
                attack = actionManager:_resolveAttackName(nextAttack),
                reason = reason,
                lightCount = self.comboLightCount,
                skill = skill.level,
            })
        elseif reason == "disengageAfterDeflects" then
            self.nextNeutralAttackAt = now + self.random:NextNumber(0.35, 0.7)
        end
        return
    end
    if current or actionManager._queuedActionType or now < self.nextNeutralAttackAt then
        return
    end

    local root = handler.Root
    local weapon = handler:GetEquippedWeaponHandler()
    local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
    if not root or not targetRoot or not attackTypes then
        return
    end
    local light = attackTypes[actionManager:_resolveAttackName("Light")]
    local heavy = attackTypes[actionManager:_resolveAttackName("Heavy")]
    local ultimate = attackTypes.Ultimate
    local skill = Skill.profile(settings.botSkill)
    local preferences =
        Styles.preferences(settings.combatStyle, frame.localState, disposition.dynamicState)
    local ultimateImpact = Attacks.firstImpactTime(ultimate) or math.huge
    local networkMargin = math.clamp((self.context.ping() or 0) + 0.05, 0.08, 0.18)
    local ultimateAllowed, ultimateReason = UltimatePolicy.shouldUseNeutral({
        targetDodging = disposition.targetDodging,
        targetParrying = disposition.targetParrying,
        targetHealth = targetModel:GetAttribute("Health"),
        ultimateDamage = Attacks.impactResultValue(ultimate, "GetHit", "healthDamage"),
        punishWindow = math.max(
            disposition.punishWindow,
            disposition.targetStaggered and disposition.targetStaggerRemaining or 0
        ),
        impactTime = ultimateImpact,
        networkMargin = networkMargin,
    })
    local attack
    if
        ultimate
        and handler:CanPerformUltimate()
        and now - self.lastUltimateAttemptAt >= ULTIMATE_RETRY_INTERVAL
        and canReach(root, targetRoot, ultimate)
        and ultimateAllowed
    then
        if not Skill.shouldPunish(skill, self.random) then
            return
        end
        attack = "Ultimate"
    elseif disposition.targetBlocking or disposition.targetStaggered then
        if not Skill.shouldPunish(skill, self.random) then
            return
        end
        attack = "Heavy"
    elseif preferences.allowOffense ~= false and canReach(root, targetRoot, light) then
        local canMixHeavy = heavy ~= nil
            and canReach(root, targetRoot, heavy)
            and now >= self.nextMixupAt
        if settings.combatStyle == "flashy" and canMixHeavy and self.random:NextNumber() < 0.28 then
            attack = "Heavy"
            self.nextMixupAt = now + self.random:NextNumber(1.2, 2.4)
            self:_record("offenseMixup", { kind = "neutralHeavy" })
        else
            attack = "Light"
        end
    elseif canReach(root, targetRoot, heavy) then
        attack = "Heavy"
    else
        return
    end
    if attack == "Ultimate" then
        self:_record("ultimateDecision", { reason = ultimateReason })
    end
    local jump = attackTypes.JumpAttack
    local jumpPostureDamage = Attacks.impactResultValue(jump, "Block", "postureDamage")
    local jumpReach = Attacks.geometricReach(jump, 4)
    local distance = (Vector3.new(targetRoot.Position.X, 0, targetRoot.Position.Z) - Vector3.new(
        root.Position.X,
        0,
        root.Position.Z
    )).Magnitude
    local shouldJump, jumpReason = JumpAttackPolicy.shouldJump({
        available = attack ~= "Ultimate" and jump ~= nil and Attacks.firstImpactTime(jump) ~= nil,
        jumpReady = (actionManager._jumpStamina or 0) >= 0.9,
        cooldownReady = now - self.lastJumpAt >= 2.5,
        canQueue = actionManager:CanQueueJump(),
        targetBlocking = disposition.targetBlocking,
        targetPosture = targetModel:GetAttribute("Posture"),
        postureDamage = jumpPostureDamage,
        targetStaggered = disposition.targetStaggered,
        staggerRemaining = disposition.targetStaggerRemaining,
        healthDamage = Attacks.impactResultValue(jump, "GetHit", "healthDamage"),
        heavyHealthDamage = Attacks.impactResultValue(heavy, "GetHit", "healthDamage"),
        inRange = canReach(root, targetRoot, jump),
        canLunge = jumpReach > 0 and distance <= jumpReach + 6,
    })
    if shouldJump then
        local offset = targetRoot.Position - root.Position
        local direction = Vector3.new(offset.X, 0, offset.Z)
        direction = direction.Magnitude > 0 and direction.Unit or Vector3.zero
        if actionManager:TryQueueJump(direction) then
            self.pendingJumpUntil = now + 0.65
            self.lastJumpAt = now
            self.lastAttackAt = now
            self:_record("jumpAttack", {
                result = "jumpQueued",
                reason = jumpReason,
                targetPosture = targetModel:GetAttribute("Posture"),
                postureDamage = jumpPostureDamage,
                distance = distance,
            })
        end
        return
    end
    local resolved = actionManager:_resolveAttackName(attack)
    local attackInfo = attackTypes[resolved]
    if
        attack ~= "Ultimate"
        and disposition.punishWindow > 0
        and not disposition.targetStaggered
        and (Attacks.firstImpactTime(attackInfo) or math.huge)
                + math.clamp((self.context.ping() or 0) + 0.05, 0.08, 0.18)
            >= disposition.punishWindow
    then
        return
    end
    if canReach(root, targetRoot, attackInfo) then
        self:_queue(actionManager, attack, attackInfo, settings, disposition)
    end
end

function Executor:disposition()
    return {
        lastAttackAt = self.lastAttackAt,
        nextNeutralAttackAt = self.nextNeutralAttackAt,
        lastUltimateAttemptAt = self.lastUltimateAttemptAt,
        pendingJumpUntil = self.pendingJumpUntil,
    }
end

function Executor:stop()
    self.stopped = true
    self.pendingJumpUntil = nil
end

return Executor
