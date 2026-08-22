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

local Attacks = importDependency("games/duelinggrounds/features/combat/Attacks", "./combat/Attacks")
local DynamicStyle =
    importDependency("games/duelinggrounds/features/combat/DynamicStyle", "./combat/DynamicStyle")
local EnemyObserver =
    importDependency("games/duelinggrounds/features/combat/EnemyObserver", "./combat/EnemyObserver")
local Skill = importDependency("games/duelinggrounds/features/combat/Skill", "./combat/Skill")
local Planner = importDependency(
    "games/duelinggrounds/features/combat/defense/Planner",
    "./combat/defense/Planner"
)
local DefenseExecutor = importDependency(
    "games/duelinggrounds/features/combat/defense/Executor",
    "./combat/defense/Executor"
)
local OffenseExecutor = importDependency(
    "games/duelinggrounds/features/combat/offense/Executor",
    "./combat/offense/Executor"
)

local CombatRuntime = {}
CombatRuntime.__index = CombatRuntime

local function addAnimation(set, animation)
    if typeof(animation) == "Instance" and animation:IsA("Animation") then
        set[animation.AnimationId] = true
    end
end

local function collectAnimations(value, set, seen)
    if typeof(value) == "Instance" then
        addAnimation(set, value)
        return
    end
    if type(value) ~= "table" or seen[value] then
        return
    end
    seen[value] = true
    for _, child in pairs(value) do
        collectAnimations(child, set, seen)
    end
end

local function weaponInfo(handler)
    local weapon = handler and handler:GetEquippedWeaponHandler()
    return weapon and weapon.WeaponInfo
end

local function targetAnimationSets(handler)
    local sets = { block = {}, parry = {}, stagger = {} }
    local info = weaponInfo(handler)
    if not info then
        return sets
    end
    addAnimation(sets.block, info.BlockAnimation)
    addAnimation(sets.block, info.Animations and info.Animations.Block)
    local stagger = info.StaggerTypes or {}
    collectAnimations(stagger.Parry, sets.parry, {})
    collectAnimations(stagger.PostureBreak, sets.stagger, {})
    collectAnimations(stagger.PostureParry, sets.stagger, {})
    for _, attackInfo in pairs(info.BasicAttackTypes or {}) do
        collectAnimations(attackInfo.deflectStun, sets.stagger, {})
    end
    return sets
end

local function trackRemaining(track, fallback)
    local speed = math.max(math.abs(track.Speed), 0.05)
    return type(track.Length) == "number"
            and track.Length > 0
            and math.max((track.Length - track.TimePosition) / speed, 0.05)
        or fallback
end

function CombatRuntime.new(context)
    assert(
        context and context.players and context.players.LocalPlayer,
        "CombatRuntime requires Players"
    )
    assert(
        context.characterController and context.targetLockController,
        "CombatRuntime requires controllers"
    )
    local self = setmetatable({
        context = context,
        record = context.record or function() end,
        activeThreats = {},
        targetState = {
            blockTracks = {},
            dodgeUntil = -math.huge,
            parryUntil = -math.huge,
            staggerUntil = -math.huge,
        },
        dynamicState = DynamicStyle.new(),
        skillRandom = context.skillRandom or Random.new(),
        defenseIntent = nil,
        boundTarget = nil,
        animationSets = {},
        localHandler = nil,
        localWeapon = nil,
        localConnection = nil,
        localDeflectAnimations = {},
        lastCombatStyle = nil,
        stopped = false,
    }, CombatRuntime)
    self.defense = DefenseExecutor.new(context)
    self.offense = OffenseExecutor.new({
        characterController = context.characterController,
        targetLockController = context.targetLockController,
        random = context.offenseRandom,
        ping = context.ping,
        criticalStrike = context.criticalStrike,
        record = self.record,
        recordProbeAttack = function(at)
            self.dynamicState = DynamicStyle.recordProbeAttack(self.dynamicState, at)
        end,
    })
    self.enemies = EnemyObserver.new({
        players = context.players,
        localPlayer = context.players.LocalPlayer,
        characterController = context.characterController,
        observeTrack = function(handler, track, model)
            self:_observeTrack(handler, track, model)
        end,
        removeHandler = function(handler)
            for track, threat in pairs(self.activeThreats) do
                if threat.handler == handler then
                    self.activeThreats[track] = nil
                end
            end
        end,
    })
    return self
end

function CombatRuntime:_observeTrack(handler, track, model)
    local animation = track.Animation
    local target = self.context.targetLockController.Target
    local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
    self.record("animation", {
        side = model == targetModel and "target" or "enemy",
        id = animation and animation.AnimationId or "",
        name = animation and animation.Name or "",
    })
    local info = weaponInfo(handler)
    local attackInfo, attackName =
        Attacks.findByAnimation(info and info.BasicAttackTypes, animation)
    if attackInfo then
        if not self.activeThreats[track] then
            self.activeThreats[track] = {
                attackInfo = attackInfo,
                attackName = attackName,
                isHeavy = Attacks.isHeavy(attackName, attackInfo),
                handler = handler,
                reacted = {},
            }
            local localHandler = self.context.characterController:GetLocalCharacterHandler()
            local actions = localHandler and localHandler.ActionManager
            if actions then
                actions:_clearQueuedAction()
                local current = actions.CurrentAction
                if current and current.ActionType == "BasicAttack" and current.CanCancel then
                    actions:SwitchToAction(nil)
                end
            end
        end
        return
    end
    if model ~= targetModel then
        return
    end
    local sets = self.animationSets[model] or targetAnimationSets(handler)
    self.animationSets[model] = sets
    local id = animation and animation.AnimationId or ""
    local name = string.lower(animation and animation.Name or "")
    local now = os.clock()
    if sets.block[id] or name == "block" then
        self.targetState.blockTracks[track] = now
    elseif sets.parry[id] then
        self.targetState.parryUntil =
            math.max(self.targetState.parryUntil, now + trackRemaining(track, 0.45))
    elseif string.find(name, "dodge", 1, true) then
        self.targetState.dodgeUntil =
            math.max(self.targetState.dodgeUntil, now + trackRemaining(track, 0.65))
    elseif sets.stagger[id] or string.find(name, "posturebreak", 1, true) then
        self.targetState.staggerUntil =
            math.max(self.targetState.staggerUntil, now + trackRemaining(track, 0.5))
    end
end

function CombatRuntime:_observeLocal()
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local weapon = handler and handler:GetEquippedWeaponHandler()
    if handler == self.localHandler and weapon == self.localWeapon then
        return
    end
    if self.localConnection then
        self.localConnection:Disconnect()
        self.localConnection = nil
    end
    table.clear(self.localDeflectAnimations)
    self.localHandler, self.localWeapon = handler, weapon
    local animator = handler and handler.Animator
    local info = weapon and weapon.WeaponInfo
    if not animator or not info then
        return
    end
    for _, attackInfo in pairs(info.BasicAttackTypes or {}) do
        collectAnimations(attackInfo.deflectStun, self.localDeflectAnimations, {})
    end
    self.localConnection = animator.AnimationPlayed:Connect(function(track)
        local animation = track.Animation
        local id = animation and animation.AnimationId or ""
        local name = string.lower(animation and animation.Name or "")
        self.record("animation", {
            side = "self",
            id = id,
            name = animation and animation.Name or "",
        })
        if self.localDeflectAnimations[id] or string.find(name, "deflected", 1, true) then
            self.dynamicState = DynamicStyle.recordDeflect(
                self.dynamicState,
                os.clock(),
                self.lastCombatStyle == "dynamic",
                self.offense:disposition().lastAttackAt
            )
        end
        self.offense:recordAnimation(animation and animation.Name or "")
    end)
end

function CombatRuntime:_resetTarget(targetModel)
    if targetModel == self.boundTarget then
        return
    end
    self.boundTarget = targetModel
    table.clear(self.targetState.blockTracks)
    self.targetState.dodgeUntil = -math.huge
    self.targetState.parryUntil = -math.huge
    self.targetState.staggerUntil = -math.huge
end

function CombatRuntime:_targetBlocking()
    for track in pairs(self.targetState.blockTracks) do
        if not track.IsPlaying then
            self.targetState.blockTracks[track] = nil
        end
    end
    return next(self.targetState.blockTracks) ~= nil
end

function CombatRuntime:_punishWindow()
    local longest = 0
    for track, threat in pairs(self.activeThreats) do
        if track.IsPlaying then
            local lastImpact = Attacks.lastImpactTime(threat.attackInfo)
            local canCancel = Attacks.marker(threat.attackInfo, "canCancel")
            if lastImpact and canCancel and track.TimePosition >= lastImpact - 0.03 then
                longest = math.max(
                    longest,
                    (canCancel - track.TimePosition) / math.max(math.abs(track.Speed), 0.05)
                )
            end
        end
    end
    return math.max(longest, 0)
end

function CombatRuntime:_hasIncomingThreat(localRoot)
    for track, threat in pairs(self.activeThreats) do
        if track.IsPlaying then
            local speed = math.max(math.abs(track.Speed), 0.05)
            for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                if
                    not threat.reacted[index]
                    and (impact.markerTime - track.TimePosition) / speed >= -0.08
                    and Attacks.impactCanReach(
                        threat.handler and threat.handler.Root,
                        localRoot,
                        impact
                    )
                then
                    return true
                end
            end
        end
    end
    return false
end

function CombatRuntime:_executeDefense(settings, target)
    local intent = self.defenseIntent
    if not intent then
        return
    end
    local now = os.clock()
    if now > intent.expiresAt then
        self.record("defenseExpired", intent)
        self.defenseIntent = nil
        return
    end
    local succeeded, reason = self.defense:execute(intent, settings, target, self.dynamicState)
    if succeeded then
        self.record("defenseExecuted", intent)
        local pendingAt, pendingUntil, counterAttack = self.defense:consumeCounter()
        if pendingUntil then
            self.offense:setDodgeCounter(pendingAt, pendingUntil, counterAttack)
        end
        self.defenseIntent = nil
    elseif now >= intent.impactAt - 0.04 then
        local fallback = Planner.fallback(intent, self.defense:availability())
        if fallback then
            local replacement = table.clone(intent)
            replacement.kind = fallback
            if self.defense:execute(replacement, settings, target, self.dynamicState) then
                self.record("defenseFallback", replacement)
                local pendingAt, pendingUntil, counterAttack = self.defense:consumeCounter()
                if pendingUntil then
                    self.offense:setDodgeCounter(pendingAt, pendingUntil, counterAttack)
                end
                self.defenseIntent = nil
                return
            end
        end
        intent.lastFailure = reason
    end
end

function CombatRuntime:_updateThreats(settings, frame)
    local localHandler = frame.localHandler
        or self.context.characterController:GetLocalCharacterHandler()
    local localRoot = localHandler and localHandler.Root
    if not localRoot then
        return
    end
    local skill = Skill.profile(settings.botSkill)
    local lead = math.clamp(
        (self.context.ping() or 0) + 0.04 - Skill.reactionDelay(skill, self.skillRandom),
        0.01,
        0.16
    )
    for track, threat in pairs(self.activeThreats) do
        if not track.IsPlaying then
            self.activeThreats[track] = nil
            continue
        end
        local speed = math.max(math.abs(track.Speed), 0.05)
        local impactInputs = {}
        for index, impact in ipairs(threat.attackInfo.impacts or {}) do
            local untilImpact = (impact.markerTime - track.TimePosition) / speed
            impactInputs[index] = {
                parryable = Attacks.isParryable(impact),
                timeUntilImpact = untilImpact,
                source = impact,
            }
            if untilImpact < -0.08 then
                threat.reacted[index] = true
            end
        end
        local availability = self.defense:availability()
        local intent = Planner.plan({
            attackName = threat.attackName,
            isHeavy = threat.isHeavy,
            impacts = impactInputs,
            canDodge = availability.canDodge,
            canParry = availability.canParry,
            canReach = function(impact, index)
                local reactionLead = threat.isHeavy and math.max(lead, 0.2) or lead
                return not threat.reacted[index]
                    and impact.timeUntilImpact <= reactionLead
                    and Attacks.impactCanReach(
                        threat.handler and threat.handler.Root,
                        localRoot,
                        impact.source
                    )
            end,
        })
        if intent and Skill.shouldAct(skill, self.skillRandom) then
            local now = os.clock()
            intent.impactAt = now + intent.timeUntilImpact
            intent.expiresAt = intent.impactAt + 0.08
            if not self.defenseIntent or intent.impactAt < self.defenseIntent.impactAt then
                self.defenseIntent = intent
                threat.reacted[intent.impactIndex] = true
                self.record("defenseSelected", intent)
            end
        elseif intent then
            threat.reacted[intent.impactIndex] = true
            self.record("defenseMissed", {
                attack = intent.attackName,
                impactIndex = intent.impactIndex,
                skill = skill.level,
            })
        end
    end
end

function CombatRuntime:observeAndDefend(settings, frame)
    if self.stopped then
        return
    end
    frame = frame or {}
    if settings.combatStyle ~= self.lastCombatStyle then
        self.dynamicState = DynamicStyle.reset()
        self.lastCombatStyle = settings.combatStyle
    end
    self:_observeLocal()
    if settings.autoFight ~= true then
        self.defenseIntent = nil
        self.enemies:clear()
        return
    end
    local target = frame.target or self.context.targetLockController.Target
    local targetModel = frame.targetModel or target and target:FindFirstAncestorWhichIsA("Model")
    self:_resetTarget(targetModel)
    self.enemies:refresh(target)
    self:_executeDefense(settings, target)
    self:_updateThreats(settings, frame)
    self:_executeDefense(settings, target)
end

function CombatRuntime:attack(settings, frame)
    if self.stopped then
        return
    end
    frame = frame or {}
    local target = frame.target or self.context.targetLockController.Target
    local targetModel = frame.targetModel or target and target:FindFirstAncestorWhichIsA("Model")
    local targetHandler = frame.targetHandler
        or targetModel and self.context.characterController:GetCharacterHandler(targetModel)
    local localHandler = frame.localHandler
        or self.context.characterController:GetLocalCharacterHandler()
    local disposition = self:disposition()
    local viablePunish = disposition.targetStaggered or disposition.punishWindow >= 0.35
    local behavior
    self.dynamicState, behavior = DynamicStyle.update(self.dynamicState, os.clock(), viablePunish)
    disposition.dynamicState = self.dynamicState
    if settings.combatStyle == "dynamic" and behavior == "hold" then
        return
    end
    frame.target = target
    frame.targetModel = targetModel
    frame.targetHandler = targetHandler
    frame.targetRoot = frame.targetRoot or targetHandler and targetHandler.Root or target
    frame.localHandler = localHandler
    self.offense:attack(settings, frame, disposition)
end

function CombatRuntime:disposition()
    local now = os.clock()
    local localHandler = self.context.characterController:GetLocalCharacterHandler()
    local target = self.context.targetLockController.Target
    local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
    local targetHandler = targetModel
        and self.context.characterController:GetCharacterHandler(targetModel)
    return {
        defenseIntent = self.defenseIntent,
        incomingThreat = self:_hasIncomingThreat(localHandler and localHandler.Root),
        targetBlocking = self:_targetBlocking()
            or targetHandler and targetHandler.IsBlocking
            or false,
        targetDodging = now <= self.targetState.dodgeUntil
            or targetHandler and targetHandler.IsDodging
            or false,
        targetParrying = now <= self.targetState.parryUntil
            or targetHandler and targetHandler.IsParrying
            or false,
        targetStaggered = now <= self.targetState.staggerUntil,
        targetStaggerRemaining = math.max(self.targetState.staggerUntil - now, 0),
        punishWindow = self:_punishWindow(),
        dynamicState = self.dynamicState,
        defense = self.defense:disposition(),
        offense = self.offense:disposition(),
    }
end

function CombatRuntime:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self.enemies:stop()
    self.defense:stop()
    self.offense:stop()
    if self.localConnection then
        self.localConnection:Disconnect()
        self.localConnection = nil
    end
    table.clear(self.activeThreats)
    table.clear(self.targetState.blockTracks)
    table.clear(self.animationSets)
    table.clear(self.localDeflectAnimations)
    self.defenseIntent = nil
    self.localHandler = nil
    self.localWeapon = nil
end

return CombatRuntime
