local Ugc = {}

local AUTO_MOVE_DASH_EXTRA_REACH = 6
local AUTO_MOVE_DASH_COOLDOWN = 0.75
local DODGE_COOLDOWN = 0.35
local FIGHT_RETRY_INTERVAL = 0.05
local IMPACT_MARGIN = Vector3.new(2.5, 3, 2.5)
local OFFENSIVE_IMPACT_MARGIN = Vector3.new(1.5, 2.5, 0.75)
local PARRY_COOLDOWN = 0.05
local PARRY_HOLD_TIME = 0.12
local TARGET_BACKSTEP_DISTANCE = 4
local UNKNOWN_ATTACK_REACH = 12
local WALL_PHASE_COOLDOWN = 0.35

local DEFAULT_COMBAT_PROFILE = {
    approachDistance = 7.25,
    orbitDistance = 5.25,
    retreatDistance = 3.25,
    neutralAttack = "Light",
    neutralCadence = 0.12,
    safeRangeBuffer = 0.5,
}

local COMBAT_PROFILES = {
    Kusarigama = {
        approachDistance = 13.25,
        orbitDistance = 12.5,
        retreatDistance = 11.75,
        neutralAttack = "Light",
        neutralCadence = 0.22,
        safeRangeBuffer = 0.85,
    },
}

local function sameAnimation(left, right)
    return left ~= nil
        and right ~= nil
        and (left == right or left.AnimationId == right.AnimationId)
end

local function getWeaponInfo(characterHandler)
    local weaponHandler = characterHandler and characterHandler:GetEquippedWeaponHandler()
    return weaponHandler and weaponHandler.WeaponInfo
end

local function getCombatProfile(characterHandler)
    local weaponInfo = getWeaponInfo(characterHandler)
    local weaponName = weaponInfo and weaponInfo.WeaponName
    return COMBAT_PROFILES[weaponName] or DEFAULT_COMBAT_PROFILE
end

local function getFirstImpactTime(attackInfo)
    local first = math.huge
    for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
        if type(impact.markerTime) == "number" then
            first = math.min(first, impact.markerTime)
        end
    end
    return first < math.huge and first or nil
end

local function getLastImpactTime(attackInfo)
    local last = 0
    for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
        if type(impact.markerTime) == "number" then
            last = math.max(last, impact.markerTime)
        end
    end
    return last > 0 and last or nil
end

local function getAttackMarker(attackInfo, marker)
    local timeMarkers = attackInfo and attackInfo.timeMarkers
    return timeMarkers and timeMarkers[marker] or nil
end

local function getImpactResultValue(attackInfo, resultName, valueName)
    local impact = attackInfo and attackInfo.impacts and attackInfo.impacts[1]
    local impactInfo = impact and impact.impactInfo
    local results = impactInfo and impactInfo.impactResults
    local result = results and results[resultName]
    return result and result[valueName] or 0
end

local function getAttackInfo(characterHandler, track)
    local weaponHandler = characterHandler and characterHandler:GetEquippedWeaponHandler()
    local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
    local animation = track and track.Animation
    if not attackTypes or not animation then
        return nil
    end
    for _, attackInfo in pairs(attackTypes) do
        if sameAnimation(attackInfo.animation, animation) then
            return attackInfo
        end
    end
    return nil
end

local function impactContainsPoint(attackerRoot, point, impact, margin)
    local impactInfo = impact and impact.impactInfo
    local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
    local hitboxSize = impactInfo and impactInfo.hitboxSize
    if typeof(hitboxCFrame) ~= "CFrame" or typeof(hitboxSize) ~= "Vector3" then
        return false
    end
    local localPoint = (attackerRoot.CFrame * hitboxCFrame):PointToObjectSpace(point)
    local allowance = hitboxSize / 2 + (margin or Vector3.zero)
    return math.abs(localPoint.X) <= allowance.X
        and math.abs(localPoint.Y) <= allowance.Y
        and math.abs(localPoint.Z) <= allowance.Z
end

local function attackCanReach(attackerRoot, defenderRoot, attackInfo, strict)
    if not attackerRoot or not defenderRoot or not attackInfo then
        return false
    end
    for _, impact in ipairs(attackInfo.impacts or {}) do
        if impactContainsPoint(attackerRoot, defenderRoot.Position, impact, IMPACT_MARGIN) then
            return true
        end
        if not strict then
            local hitbox = impact.impactInfo
            local hitboxCFrame = hitbox and hitbox.hitboxCFrame
            local hitboxSize = hitbox and hitbox.hitboxSize
            if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
                local offset = defenderRoot.Position - attackerRoot.Position
                local flatOffset = Vector3.new(offset.X, 0, offset.Z)
                local maximumReach = math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2 + 4
                if flatOffset.Magnitude <= maximumReach
                    and flatOffset.Magnitude > 0
                    and attackerRoot.CFrame.LookVector:Dot(flatOffset.Unit) >= 0.15
                then
                    return true
                end
            else
                local offset = defenderRoot.Position - attackerRoot.Position
                local flatOffset = Vector3.new(offset.X, 0, offset.Z)
                if flatOffset.Magnitude <= UNKNOWN_ATTACK_REACH
                    and flatOffset.Magnitude > 0
                    and attackerRoot.CFrame.LookVector:Dot(flatOffset.Unit) >= 0
                then
                    return true
                end
            end
        end
    end
    return false
end

local function offensiveAttackCanReach(attackerRoot, defenderRoot, attackInfo)
    if not attackerRoot or not defenderRoot or not attackInfo then
        return false
    end
    local impactTime = getFirstImpactTime(attackInfo) or 0
    local velocity = defenderRoot.AssemblyLinearVelocity or Vector3.zero
    local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontalVelocity.Magnitude > 18 then
        horizontalVelocity = horizontalVelocity.Unit * 18
    end
    local predictedPoint = defenderRoot.Position
        + horizontalVelocity * math.clamp(impactTime, 0, 0.2)
    for _, impact in ipairs(attackInfo.impacts or {}) do
        if impactContainsPoint(
            attackerRoot,
            predictedPoint,
            impact,
            OFFENSIVE_IMPACT_MARGIN
        ) then
            return true
        end
    end
    return false
end

local function getAttackGeometricReach(attackInfo)
    local maximumReach = 0
    for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
        local impactInfo = impact.impactInfo
        local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
        local hitboxSize = impactInfo and impactInfo.hitboxSize
        if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
            maximumReach = math.max(
                maximumReach,
                math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2
            )
        end
    end
    return maximumReach
end

local function getAttackMaximumReach(attackInfo)
    local maximumReach = 0
    for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
        local impactInfo = impact.impactInfo
        local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
        local hitboxSize = impactInfo and impactInfo.hitboxSize
        if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
            maximumReach = math.max(
                maximumReach,
                math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2 + 4
            )
        end
    end
    return maximumReach
end

function Ugc.new(context)
    assert(type(context) == "table", "Ugc adapter requires context")
    assert(context.oh and context.oh.targeting, "Ugc requires Hydroxide Targeting")
    assert(context.players and context.players.LocalPlayer, "Ugc requires Players")
    assert(type(context.render) == "function", "Ugc requires a renderer")
    assert(context.store, "Ugc requires a reactive store")

    local localPlayer = context.players.LocalPlayer
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local GameManager = require(replicatedStorage.GameManager)
    local characterController = GameManager:GetController("CharacterController")
    local pingController = GameManager:GetController("PingController")
    local playerInputController = GameManager:GetController("PlayerInputController")
    local targetLockController = GameManager:GetController("TargetLockController")
    local stopped = false
    local lastDodgeAt = -math.huge
    local lastApproachDashAt = -math.huge
    local lastJumpAttackAt = -math.huge
    local lastCriticalStrikeAt = -math.huge
    local nextFightAt = 0
    local lastFightAttackAt = -math.huge
    local pendingDodgeCounterAt = nil
    local pendingDodgeCounterUntil = nil
    local pendingJumpAttackUntil = nil
    local pendingDodgeUntil = nil
    local lastParryAt = -math.huge
    local pendingParryUntil = nil
    local activeParryBlock = nil
    local lastWallPhaseAt = -math.huge
    local boundTarget = nil
    local targetAnimationConnection = nil
    local activeThreats = {}
    local targetCombatState = {
        blockTracks = {},
        dodgeUntil = -math.huge,
        parryUntil = -math.huge,
        staggerUntil = -math.huge,
    }
    local autoMoveMode = nil
    local autoMoveTarget = nil
    local orbitDirection = 1
    local lastMovementCheckAt = 0
    local lastMovementCheckPosition = nil
    local dodgeCounterDirection = 1

    local function getInstances(value)
        if typeof(value) == "Instance" then
            return { value }
        end
        local instances = {}
        if type(value) == "table" then
            for _, candidate in pairs(value) do
                if typeof(candidate) == "Instance" then
                    table.insert(instances, candidate)
                end
            end
        end
        return instances
    end

    local function hasClearPath(fromRoot, fromModels, targetRoot, targetModels)
        if not fromRoot or not targetRoot then
            return false
        end
        local offset = targetRoot.Position - fromRoot.Position
        if offset.Magnitude <= 0.001 then
            return true
        end
        local parameters = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = getInstances(fromModels)
        parameters.IgnoreWater = true
        local hit = context.workspace:Raycast(fromRoot.Position, offset, parameters)
        if hit == nil then
            return true
        end
        for _, targetModel in ipairs(getInstances(targetModels)) do
            if hit.Instance:IsDescendantOf(targetModel) then
                return true
            end
        end
        return false
    end

    local targetAnimationSets = {
        block = {},
        parry = {},
        stagger = {},
    }

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

    local function rebuildTargetAnimationSets(handler)
        targetAnimationSets = {
            block = {},
            parry = {},
            stagger = {},
        }
        local weaponInfo = getWeaponInfo(handler)
        if not weaponInfo then
            return
        end
        addAnimation(targetAnimationSets.block, weaponInfo.BlockAnimation)
        local animations = weaponInfo.Animations
        addAnimation(targetAnimationSets.block, animations and animations.Block)
        local staggerTypes = weaponInfo.StaggerTypes or {}
        collectAnimations(staggerTypes.Parry, targetAnimationSets.parry, {})
        collectAnimations(staggerTypes.PostureBreak, targetAnimationSets.stagger, {})
        collectAnimations(staggerTypes.PostureParry, targetAnimationSets.stagger, {})
        for _, attackInfo in pairs(weaponInfo.BasicAttackTypes or {}) do
            collectAnimations(attackInfo.deflectStun, targetAnimationSets.stagger, {})
        end
    end

    local function clearStoppedBlockTracks()
        for track in pairs(targetCombatState.blockTracks) do
            if not track.IsPlaying then
                targetCombatState.blockTracks[track] = nil
            end
        end
    end

    local function targetIsBlocking()
        clearStoppedBlockTracks()
        return next(targetCombatState.blockTracks) ~= nil
    end

    local function getTargetBlockHeldTime()
        clearStoppedBlockTracks()
        local earliest = math.huge
        for _, startedAt in pairs(targetCombatState.blockTracks) do
            earliest = math.min(earliest, startedAt)
        end
        return earliest < math.huge and os.clock() - earliest or 0
    end

    local function targetIsParrying()
        return os.clock() <= targetCombatState.parryUntil
    end

    local function targetIsDodging()
        return os.clock() <= targetCombatState.dodgeUntil
    end

    local function targetIsStaggered()
        return os.clock() <= targetCombatState.staggerUntil
    end

    local function getTargetStaggerRemaining()
        return math.max(targetCombatState.staggerUntil - os.clock(), 0)
    end

    local function getTargetPunishWindow()
        local longest = 0
        for track, threat in pairs(activeThreats) do
            if track.IsPlaying then
                local speed = math.max(math.abs(track.Speed), 0.05)
                local lastImpact = getLastImpactTime(threat.attackInfo)
                local canCancel = getAttackMarker(threat.attackInfo, "canCancel")
                if lastImpact and canCancel and track.TimePosition >= lastImpact - 0.03 then
                    longest = math.max(longest, (canCancel - track.TimePosition) / speed)
                end
            end
        end
        return math.max(longest, 0)
    end

    local function getTargetGeometricReach(handler)
        local weaponInfo = getWeaponInfo(handler)
        local maximumReach = 0
        for name, attackInfo in pairs(weaponInfo and weaponInfo.BasicAttackTypes or {}) do
            if string.match(name, "^Light") or string.match(name, "^Heavy") then
                maximumReach = math.max(maximumReach, getAttackGeometricReach(attackInfo))
            end
        end
        return maximumReach
    end

    local function tryDodge()
        if not pendingDodgeUntil or os.clock() > pendingDodgeUntil then
            pendingDodgeUntil = nil
            return
        end
        if os.clock() - lastDodgeAt < DODGE_COOLDOWN then
            return
        end
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager or not actionManager:CanStartDodge() then
            return
        end
        local target = targetLockController.Target
        local localRoot = localHandler.Root
        local offset = target and localRoot and (target.Position - localRoot.Position) or Vector3.zero
        local direction = Vector3.new(offset.X, 0, offset.Z)
        local settings = context.store:Get().settings or {}
        local offensiveStyle = settings.combatStyle ~= "defensive"
        if direction.Magnitude <= 0.001 then
            local camera = context.workspace.CurrentCamera
            local look = camera and camera.CFrame.LookVector or Vector3.zAxis
            direction = Vector3.new(look.X, 0, look.Z)
        end
        direction = direction.Magnitude > 0 and direction.Unit or Vector3.zAxis
        local isReverse = true
        if offensiveStyle and target and localRoot then
            local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
            if distance <= 8 then
                direction = Vector3.new(-direction.Z, 0, direction.X) * dodgeCounterDirection
                dodgeCounterDirection = -dodgeCounterDirection
            end
            isReverse = false
        else
            direction = -direction
        end
        actionManager:_clearQueuedAction()
        actionManager:SwitchToAction("Dodge", {
            direction = direction,
            isReverse = isReverse,
            dodgeStamina = actionManager._dodgeStamina,
        })
        pendingDodgeUntil = nil
        lastDodgeAt = os.clock()
        if offensiveStyle then
            pendingDodgeCounterAt = lastDodgeAt + 0.16
            pendingDodgeCounterUntil = lastDodgeAt + 0.32
        else
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
        end
    end

    local function queueDodge()
        pendingDodgeUntil = os.clock() + 0.3
        tryDodge()
    end

    local function tryDodgeCounter(localHandler, actionManager, targetHandler, targetRoot)
        if not pendingDodgeCounterUntil then
            return false
        end
        local now = os.clock()
        if now > pendingDodgeCounterUntil then
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
            return false
        end
        if now < (pendingDodgeCounterAt or 0) then
            return true
        end
        local currentAction = actionManager.CurrentAction
        if not currentAction or currentAction.ActionType ~= "Dodge" then
            return true
        end
        if targetIsDodging()
            or targetIsParrying()
            or (targetHandler and (targetHandler.IsDodging or targetHandler.IsParrying))
        then
            return true
        end
        local localRoot = localHandler.Root
        local weaponHandler = localHandler:GetEquippedWeaponHandler()
        local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
        local attackName = actionManager:_resolveAttackName("Light")
        local attackInfo = attackName and attackTypes and attackTypes[attackName]
        local reach = getAttackGeometricReach(attackInfo) + 1
        if not localRoot or not targetRoot or reach <= 1 then
            return true
        end
        for track, threat in pairs(activeThreats) do
            if track.IsPlaying then
                local speed = math.max(math.abs(track.Speed), 0.05)
                for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                    local timeUntilImpact = (impact.markerTime - track.TimePosition) / speed
                    local threatRoot = threat.handler and threat.handler.Root
                    if not threat.reacted[index]
                        and timeUntilImpact >= -0.03
                        and timeUntilImpact <= 0.6
                        and attackCanReach(
                            threatRoot,
                            localRoot,
                            { impacts = { impact } },
                            false
                        )
                    then
                        return true
                    end
                end
            end
        end
        local offset = targetRoot.Position - localRoot.Position
        local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
        if distance > reach
            or not hasClearPath(
                localRoot,
                { localHandler.Model, localHandler.OriginalModel },
                targetRoot,
                { targetHandler and targetHandler.Model }
            )
        then
            return true
        end
        if actionManager:TryQueueBasicAttack("Light") then
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
            lastFightAttackAt = now
        end
        return true
    end

    local function tryParry()
        if not pendingParryUntil or os.clock() > pendingParryUntil then
            pendingParryUntil = nil
            return
        end
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager then
            return
        end
        if actionManager.BlockAction then
            pendingParryUntil = nil
            if not localHandler.IsParrying then
                queueDodge()
            end
            return
        end
        if os.clock() - lastParryAt < PARRY_COOLDOWN then
            return
        end
        if (actionManager._blockStrength or 0) <= 0.01 then
            pendingParryUntil = nil
            queueDodge()
            return
        end
        local canStart, replaceCurrent = actionManager:CanStartBlock()
        if not canStart then
            local currentAction = actionManager.CurrentAction
            if currentAction and currentAction.ActionType == "Dodge" then
                return
            end
            pendingParryUntil = nil
            queueDodge()
            return
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
        activeParryBlock = block
        pendingParryUntil = nil
        lastParryAt = os.clock()
        task.delay(PARRY_HOLD_TIME, function()
            if activeParryBlock == block then
                block._wantsToRelease = true
                activeParryBlock = nil
            end
        end)
    end

    local function queueParry()
        pendingParryUntil = os.clock() + 0.2
        tryParry()
    end

    local function observeThreatTrack(handler, track)
        if activeThreats[track] then
            return
        end
        local attackInfo = getAttackInfo(handler, track)
        if not attackInfo then
            return
        end
        activeThreats[track] = {
            attackInfo = attackInfo,
            handler = handler,
            reacted = {},
        }
        local settings = context.store:Get().settings or {}
        if settings.autoFight == true then
            local localHandler = characterController:GetLocalCharacterHandler()
            local actionManager = localHandler and localHandler.ActionManager
            if actionManager then
                actionManager:_clearQueuedAction()
                local currentAction = actionManager.CurrentAction
                if currentAction
                    and currentAction.ActionType == "BasicAttack"
                    and currentAction.CanCancel
                then
                    actionManager:SwitchToAction(nil)
                end
            end
        end
    end

    local function getTrackRemaining(track, fallback)
        local speed = math.max(math.abs(track.Speed), 0.05)
        local length = track.Length
        if type(length) ~= "number" or length <= 0 then
            return fallback
        end
        return math.max((length - track.TimePosition) / speed, 0.05)
    end

    local function observeTargetTrack(handler, track)
        local attackInfo = getAttackInfo(handler, track)
        if attackInfo then
            observeThreatTrack(handler, track)
            return
        end
        local animation = track.Animation
        local animationId = animation and animation.AnimationId or ""
        local animationName = string.lower(animation and animation.Name or "")
        local now = os.clock()
        if targetAnimationSets.block[animationId] or animationName == "block" then
            targetCombatState.blockTracks[track] = now
        elseif targetAnimationSets.parry[animationId] then
            targetCombatState.parryUntil = math.max(
                targetCombatState.parryUntil,
                now + getTrackRemaining(track, 0.45)
            )
        elseif string.find(animationName, "dodge", 1, true) then
            targetCombatState.dodgeUntil = math.max(
                targetCombatState.dodgeUntil,
                now + getTrackRemaining(track, 0.65)
            )
        elseif targetAnimationSets.stagger[animationId]
            or string.find(animationName, "posturebreak", 1, true)
        then
            targetCombatState.staggerUntil = math.max(
                targetCombatState.staggerUntil,
                now + getTrackRemaining(track, 0.5)
            )
        end
    end

    local function disconnectTargetAnimation()
        if targetAnimationConnection then
            targetAnimationConnection:Disconnect()
            targetAnimationConnection = nil
        end
        table.clear(activeThreats)
        table.clear(targetCombatState.blockTracks)
        targetCombatState.dodgeUntil = -math.huge
        targetCombatState.parryUntil = -math.huge
        targetCombatState.staggerUntil = -math.huge
    end

    local function updateIncomingThreats()
        local localHandler = characterController:GetLocalCharacterHandler()
        local localRoot = localHandler and localHandler.Root
        if not localRoot then
            return
        end
        local leadTime = math.clamp((pingController:GetPing() or 0) + 0.04, 0.08, 0.16)
        for track, threat in pairs(activeThreats) do
            if not track.IsPlaying then
                activeThreats[track] = nil
                continue
            end
            local targetHandler = threat.handler
            local targetRoot = targetHandler and targetHandler.Root
            local targetModel = targetHandler and targetHandler.OriginalModel
            local speed = math.max(math.abs(track.Speed), 0.05)
            for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                if threat.reacted[index] then
                    continue
                end
                local timeUntilImpact = (impact.markerTime - track.TimePosition) / speed
                if timeUntilImpact < -0.08 then
                    threat.reacted[index] = true
                elseif timeUntilImpact <= leadTime
                    and attackCanReach(targetRoot, localRoot, { impacts = { impact } }, false)
                    and hasClearPath(
                        targetRoot,
                        { targetHandler.Model, targetModel },
                        localRoot,
                        { localHandler.Model, localHandler.OriginalModel }
                    )
                then
                    threat.reacted[index] = true
                    local impactResults = impact.impactInfo and impact.impactInfo.impactResults
                    if impactResults and impactResults.Parry == nil then
                        queueDodge()
                    else
                        queueParry()
                    end
                end
            end
        end
    end

    local function hasIncomingThreat(reachableOnly)
        local localHandler = characterController:GetLocalCharacterHandler()
        local localRoot = localHandler and localHandler.Root
        for track, threat in pairs(activeThreats) do
            if track.IsPlaying then
                local speed = math.max(math.abs(track.Speed), 0.05)
                for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                    if not threat.reacted[index] then
                        local timeUntilImpact = (impact.markerTime - track.TimePosition) / speed
                        local targetRoot = threat.handler and threat.handler.Root
                        if timeUntilImpact >= -0.08
                            and (not reachableOnly
                                or attackCanReach(
                                    targetRoot,
                                    localRoot,
                                    { impacts = { impact } },
                                    false
                                ))
                        then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local function updateAutoDefense(settings)
        if settings.autoFight ~= true then
            pendingDodgeUntil = nil
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
            pendingParryUntil = nil
            pendingJumpAttackUntil = nil
            boundTarget = nil
            disconnectTargetAnimation()
            return
        end
        tryDodge()
        tryParry()
        local target = targetLockController.Target
        if target ~= boundTarget then
            disconnectTargetAnimation()
            boundTarget = target
        end
        if not target then
            return
        end
        if not targetAnimationConnection then
            local model = target:FindFirstAncestorWhichIsA("Model")
            local handler = model and characterController:GetCharacterHandler(model)
            local animator = handler and handler.Animator
            if not animator then
                return
            end
            rebuildTargetAnimationSets(handler)
            targetAnimationConnection = animator.AnimationPlayed:Connect(function(track)
                observeTargetTrack(handler, track)
            end)
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                observeTargetTrack(handler, track)
            end
        end
        updateIncomingThreats()
    end

    local function updateAutoFight(settings)
        if settings.autoFight ~= true or os.clock() < nextFightAt then
            return
        end
        nextFightAt = os.clock() + FIGHT_RETRY_INTERVAL
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        if not targetModel or targetModel:GetAttribute("IsDead") == true then
            return
        end
        local targetHandler = characterController:GetCharacterHandler(targetModel)
        local targetRoot = targetHandler and targetHandler.Root or target
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager or not localHandler.EquippedWeapon then
            return
        end
        local criticalTarget = targetLockController.CriticalStrikeTarget
        local criticalModel = criticalTarget and criticalTarget.Parent
        if criticalModel
            and os.clock() - lastCriticalStrikeAt >= 0.25
        then
            replicatedStorage.Remotes.PlayerCharacter.Request.CriticalStrike:FireServer(criticalModel)
            lastCriticalStrikeAt = os.clock()
            lastFightAttackAt = lastCriticalStrikeAt
            return
        end
        if settings.combatStyle == "defensive" then
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
            pendingJumpAttackUntil = nil
            if actionManager._queuedActionType == "Jump"
                or actionManager._queuedActionType == "BasicAttack"
            then
                actionManager:_clearQueuedAction()
            end
            local currentAction = actionManager.CurrentAction
            if currentAction
                and currentAction.ActionType == "BasicAttack"
                and currentAction.CanCancel
            then
                actionManager:SwitchToAction(nil)
            end
            return
        end
        if tryDodgeCounter(localHandler, actionManager, targetHandler, targetRoot) then
            return
        end
        if targetIsDodging()
            or targetIsParrying()
            or (targetHandler and (targetHandler.IsDodging or targetHandler.IsParrying))
        then
            pendingJumpAttackUntil = nil
            if actionManager._queuedActionType == "Jump" then
                actionManager:_clearQueuedAction()
            end
            return
        end
        if pendingDodgeUntil or pendingParryUntil or localHandler.IsParrying or actionManager.BlockAction then
            return
        end
        if hasIncomingThreat(true) then
            pendingJumpAttackUntil = nil
            return
        end
        if pendingJumpAttackUntil then
            if os.clock() > pendingJumpAttackUntil then
                pendingJumpAttackUntil = nil
            elseif actionManager.CurrentAction
                and actionManager.CurrentAction.ActionType == "Jump"
            then
                if actionManager.CurrentAction.CanQueueBasicAttacks
                    and actionManager:TryQueueBasicAttack("JumpAttack")
                then
                    pendingJumpAttackUntil = nil
                    lastFightAttackAt = os.clock()
                end
                return
            elseif actionManager._queuedActionType == "Jump" then
                return
            else
                pendingJumpAttackUntil = nil
            end
        end
        if actionManager.CurrentAction or actionManager._queuedActionType then
            return
        end

        local localRoot = localHandler.Root
        local weaponHandler = localHandler:GetEquippedWeaponHandler()
        local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
        if not localRoot or not targetRoot or not attackTypes
            or not hasClearPath(
                localRoot,
                { localHandler.Model, localHandler.OriginalModel },
                targetRoot,
                { targetHandler and targetHandler.Model, targetModel }
            )
        then
            return
        end

        local profile = getCombatProfile(localHandler)
        local distance = (Vector3.new(targetRoot.Position.X, 0, targetRoot.Position.Z)
            - Vector3.new(localRoot.Position.X, 0, localRoot.Position.Z)).Magnitude
        local targetReach = getTargetGeometricReach(targetHandler)
        local safelyOutsideCounterRange = targetReach <= 0
            or distance >= targetReach + profile.safeRangeBuffer
        local targetBlocking = targetIsBlocking()
            or (targetHandler and targetHandler.IsBlocking)
        local targetStaggered = targetIsStaggered()
        local punishWindow = getTargetPunishWindow()

        if os.clock() - lastFightAttackAt < profile.neutralCadence then
            return
        end

        local lightInfo = attackTypes[actionManager:_resolveAttackName("Light")]
        local heavyInfo = attackTypes[actionManager:_resolveAttackName("Heavy")]
        local lightCanHit = offensiveAttackCanReach(localRoot, targetRoot, lightInfo)
        local heavyCanHit = offensiveAttackCanReach(localRoot, targetRoot, heavyInfo)
        local attack
        if targetBlocking or targetStaggered then
            attack = "Heavy"
        elseif lightCanHit then
            attack = "Light"
        elseif heavyCanHit and safelyOutsideCounterRange then
            attack = "Heavy"
        else
            return
        end
        local resolvedName = actionManager:_resolveAttackName(attack)
        local attackInfo = resolvedName and attackTypes[resolvedName]
        local attackImpactTime = getFirstImpactTime(attackInfo) or math.huge
        local networkMargin = math.clamp((pingController:GetPing() or 0) + 0.05, 0.08, 0.18)

        if punishWindow > 0
            and not targetStaggered
            and attackImpactTime + networkMargin >= punishWindow
        then
            return
        end

        local ultimateInfo = attackTypes.Ultimate
        local ultimateImpactTime = getFirstImpactTime(ultimateInfo) or math.huge
        local confirmedUltimateOpening = getTargetStaggerRemaining()
            >= math.max(ultimateImpactTime - 0.2, 0.35)
            or punishWindow >= ultimateImpactTime + networkMargin
            or (targetBlocking and getTargetBlockHeldTime() >= 0.18)
        if ultimateInfo
            and localHandler:CanPerformUltimate()
            and confirmedUltimateOpening
            and offensiveAttackCanReach(localRoot, targetRoot, ultimateInfo)
        then
            attack = "Ultimate"
            attackInfo = ultimateInfo
        end

        local jumpInfo = attackTypes.JumpAttack
        local jumpHealthDamage = getImpactResultValue(jumpInfo, "GetHit", "healthDamage")
        local heavyHealthDamage = getImpactResultValue(heavyInfo, "GetHit", "healthDamage")
        local jumpDominatesHit = targetStaggered
            and jumpHealthDamage > 0
            and jumpHealthDamage >= heavyHealthDamage
        local shouldJumpAttack = attack ~= "Ultimate"
            and jumpInfo ~= nil
            and getFirstImpactTime(jumpInfo) ~= nil
            and getFirstImpactTime(jumpInfo) <= 0.15
            and (actionManager._jumpStamina or 0) >= 0.9
            and os.clock() - lastJumpAttackAt >= 2.5
            and jumpDominatesHit
            and getTargetStaggerRemaining() >= 0.9
            and attackCanReach(localRoot, targetRoot, jumpInfo, true)
            and actionManager:CanQueueJump()
        if shouldJumpAttack then
            local offset = targetRoot.Position - localRoot.Position
            local direction = Vector3.new(offset.X, 0, offset.Z)
            direction = direction.Magnitude > 0 and direction.Unit or Vector3.zero
            if actionManager:TryQueueJump(direction) then
                pendingJumpAttackUntil = os.clock() + 0.65
                lastJumpAttackAt = os.clock()
                lastFightAttackAt = lastJumpAttackAt
            end
            return
        end

        if not offensiveAttackCanReach(localRoot, targetRoot, attackInfo) then
            local alternate = "Light"
            local alternateInfo = attackTypes[actionManager:_resolveAttackName(alternate)]
            if attack == "Ultimate"
                or targetBlocking
                or not offensiveAttackCanReach(localRoot, targetRoot, alternateInfo)
            then
                return
            end
            attack = alternate
        end

        if actionManager:TryQueueBasicAttack(attack) then
            lastFightAttackAt = os.clock()
        end
    end

    local function updateAutoMovement(settings)
        if settings.autoMovement ~= true or settings.autoFight ~= true then
            autoMoveMode = nil
            autoMoveTarget = nil
            lastMovementCheckPosition = nil
            return
        end
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        if not targetModel or targetModel:GetAttribute("IsDead") == true then
            autoMoveMode = nil
            autoMoveTarget = nil
            lastMovementCheckPosition = nil
            return
        end
        local targetHandler = characterController:GetCharacterHandler(targetModel)
        local targetRoot = targetHandler and targetHandler.Root or target
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        local localRoot = localHandler and localHandler.Root
        if not actionManager or not localRoot or not targetRoot then
            return
        end
        local profile = getCombatProfile(localHandler)

        local currentAction = actionManager.CurrentAction
        if pendingDodgeUntil
            or pendingParryUntil
            or hasIncomingThreat(true)
            or actionManager._queuedActionType
            or actionManager.BlockAction
            or currentAction
            or localHandler.IsDodging
            or localHandler.IsParrying
        then
            playerInputController.CurrentInput.MoveDirection = Vector3.zero
            return
        end

        if target ~= autoMoveTarget then
            autoMoveTarget = target
            autoMoveMode = nil
            orbitDirection = 1
            lastMovementCheckPosition = localRoot.Position
            lastMovementCheckAt = os.clock()
        end

        local offset = targetRoot.Position - localRoot.Position
        local flatOffset = Vector3.new(offset.X, 0, offset.Z)
        local distance = flatOffset.Magnitude
        if distance <= 0.001 then
            playerInputController.CurrentInput.MoveDirection = Vector3.zero
            return
        end
        local toward = flatOffset.Unit

        local weaponHandler = localHandler:GetEquippedWeaponHandler()
        local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
        local attackName = actionManager:_resolveAttackName(profile.neutralAttack)
        local attackInfo = attackName and attackTypes and attackTypes[attackName]
        local attackReach = getAttackMaximumReach(attackInfo)
        if attackReach > 0
            and distance > attackReach + 0.25
            and distance <= attackReach + AUTO_MOVE_DASH_EXTRA_REACH
            and os.clock() - lastApproachDashAt >= AUTO_MOVE_DASH_COOLDOWN
            and (actionManager._blockStrength or 0) >= 0.99
            and actionManager:CanStartDodge()
            and hasClearPath(
                localRoot,
                { localHandler.Model, localHandler.OriginalModel },
                targetRoot,
                { targetHandler and targetHandler.Model, targetModel }
            )
        then
            actionManager:_clearQueuedAction()
            actionManager:SwitchToAction("Dodge", {
                direction = toward,
                isReverse = false,
                dodgeStamina = actionManager._dodgeStamina,
            })
            pendingDodgeUntil = nil
            lastDodgeAt = os.clock()
            lastApproachDashAt = lastDodgeAt
            playerInputController.CurrentInput.MoveDirection = Vector3.zero
            return
        end

        if autoMoveMode == "approach" then
            if distance <= profile.orbitDistance + 0.5 then
                autoMoveMode = "orbit"
            end
        elseif autoMoveMode == "retreat" then
            if distance >= profile.orbitDistance - 0.5 then
                autoMoveMode = "orbit"
            end
        elseif distance > profile.approachDistance then
            autoMoveMode = "approach"
        elseif distance < profile.retreatDistance then
            autoMoveMode = "retreat"
        else
            autoMoveMode = "orbit"
        end

        local direction
        if autoMoveMode == "approach" then
            direction = toward
        elseif autoMoveMode == "retreat" then
            direction = -toward
        else
            local tangent = Vector3.new(-toward.Z, 0, toward.X) * orbitDirection
            local radialCorrection = math.clamp(
                (distance - profile.orbitDistance) / 2,
                -0.6,
                0.6
            )
            direction = tangent + toward * radialCorrection
            direction = direction.Magnitude > 0 and direction.Unit or tangent
        end

        local parameters = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = getInstances({
            localHandler.Model,
            localHandler.OriginalModel,
            targetHandler and targetHandler.Model,
            targetModel,
        })
        parameters.IgnoreWater = true
        local obstacle = context.workspace:Raycast(
            localRoot.Position + Vector3.new(0, 0.5, 0),
            direction * 3,
            parameters
        )
        if obstacle and obstacle.Instance.CanCollide then
            orbitDirection = -orbitDirection
            direction = Vector3.new(-toward.Z, 0, toward.X) * orbitDirection
            autoMoveMode = "orbit"
        end

        local now = os.clock()
        if now - lastMovementCheckAt >= 0.75 then
            if lastMovementCheckPosition
                and (localRoot.Position - lastMovementCheckPosition).Magnitude < 0.6
            then
                orbitDirection = -orbitDirection
            end
            lastMovementCheckPosition = localRoot.Position
            lastMovementCheckAt = now
        end
        playerInputController.CurrentInput.MoveDirection = direction
    end

    local function updateWallPhase(settings)
        if settings.wallPhase ~= true or os.clock() - lastWallPhaseAt < WALL_PHASE_COOLDOWN then
            return
        end
        local character = localPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local direction = type(context.movementDirection) == "function" and context.movementDirection() or nil
        if not root or typeof(direction) ~= "Vector3" or direction.Magnitude < 0.1 then
            return
        end
        direction = direction.Unit

        local exclude = RaycastParams.new()
        exclude.FilterType = Enum.RaycastFilterType.Exclude
        exclude.FilterDescendantsInstances = { character }
        exclude.IgnoreWater = true
        local front = context.workspace:Raycast(root.Position + Vector3.new(0, 0.5, 0), direction * 3.5, exclude)
        if not front
            or not front.Instance:IsA("BasePart")
            or front.Instance.CanCollide ~= true
            or math.abs(front.Normal.Y) > 0.45
        then
            return
        end

        local include = RaycastParams.new()
        include.FilterType = Enum.RaycastFilterType.Include
        include.FilterDescendantsInstances = { front.Instance }
        include.IgnoreWater = true
        local back = context.workspace:Raycast(front.Position + direction * 12, -direction * 12.2, include)
        if not back then
            return
        end
        local thickness = (back.Position - front.Position):Dot(direction)
        if thickness < 0.05 or thickness > 10 then
            return
        end
        character:PivotTo(character:GetPivot() + direction * (thickness + 2.25))
        lastWallPhaseAt = os.clock()
    end

    local function updateTeleportBehind(settings)
        if settings.teleportBehind ~= true then
            return
        end
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        if not targetModel or targetModel:GetAttribute("IsDead") == true then
            return
        end
        local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") or target
        local localHandler = characterController:GetLocalCharacterHandler()
        local localRoot = localHandler and localHandler.Root
        if not targetRoot or not targetRoot:IsA("BasePart") or not localRoot then
            return
        end

        local targetLook = targetRoot.CFrame.LookVector
        local flatLook = Vector3.new(targetLook.X, 0, targetLook.Z)
        if flatLook.Magnitude <= 0.001 then
            return
        end
        flatLook = flatLook.Unit
        local destination = targetRoot.Position - flatLook * TARGET_BACKSTEP_DISTANCE
        localRoot.CFrame = CFrame.lookAt(
            destination,
            Vector3.new(targetRoot.Position.X, destination.Y, targetRoot.Position.Z)
        )
    end

    local connection = game:GetService("RunService").RenderStepped:Connect(function()
        if stopped then
            return
        end

        local settings = context.store:Get().settings or {}
        updateAutoDefense(settings)
        updateTeleportBehind(settings)
        updateAutoFight(settings)
        updateAutoMovement(settings)
        updateWallPhase(settings)
        local observations = {}
        if settings.showEnemies ~= false then
            observations = context.oh.targeting.observePlayers({
                isEligible = function(player, character)
                    return player ~= localPlayer
                        and typeof(character) == "Instance"
                        and character:IsA("Model")
                end,
                screenOrigin = Vector2.new(0, 0),
            })
        end
        for _, observation in ipairs(observations) do
            local humanoid = observation.character and observation.character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health or nil
            observation.maxHealth = humanoid and humanoid.MaxHealth or nil
            observation.tone = "enemy"
        end
        context.render(observations, Vector2.new(0, 0), {})
        context.store:Patch({
            observations = observations,
            status = ("%d players visible"):format(#observations),
        })
    end)

    return {
        capabilities = {
            "boxes",
            "chams",
            "chamsExcludeAccessories",
            "chamsPerPart",
            "showEnemies",
            "worldRenderer",
            "names",
            "health",
            "autoFight",
            "autoMovement",
            "combatStyle",
            "teleportBehind",
            "wallPhase",
        },
        isOpponent = function(player)
            return player ~= nil and player ~= localPlayer
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            disconnectTargetAnimation()
            if activeParryBlock then
                activeParryBlock._wantsToRelease = true
                activeParryBlock = nil
            end
            connection:Disconnect()
        end,
    }
end

return Ugc
