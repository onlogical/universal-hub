local Ugc = {}

local DODGE_COOLDOWN = 0.35
local FIGHT_RETRY_INTERVAL = 0.05
local IMPACT_MARGIN = Vector3.new(2.5, 3, 2.5)
local PARRY_COOLDOWN = 0.05
local PARRY_HOLD_TIME = 0.12
local TARGET_BACKSTEP_DISTANCE = 4
local WALL_PHASE_COOLDOWN = 0.35

local function getAttackInfo(characterHandler, track)
    local weaponHandler = characterHandler and characterHandler:GetEquippedWeaponHandler()
    local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
    local animation = track and track.Animation
    if not attackTypes or not animation then
        return nil
    end
    for _, attackInfo in pairs(attackTypes) do
        if attackInfo.animation == animation
            or attackInfo.animation.AnimationId == animation.AnimationId
        then
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
            end
        end
    end
    return false
end

function Ugc.new(context)
    assert(type(context) == "table", "Ugc adapter requires context")
    assert(context.oh and context.oh.targeting, "Ugc requires Hydroxide Targeting")
    assert(context.players and context.players.LocalPlayer, "Ugc requires Players")
    assert(type(context.render) == "function", "Ugc requires a renderer")
    assert(context.store, "Ugc requires a reactive store")

    local localPlayer = context.players.LocalPlayer
    local GameManager = require(game:GetService("ReplicatedStorage").GameManager)
    local characterController = GameManager:GetController("CharacterController")
    local pingController = GameManager:GetController("PingController")
    local targetLockController = GameManager:GetController("TargetLockController")
    local stopped = false
    local lastDodgeAt = -math.huge
    local nextFightAt = 0
    local nextFightAttack = "Heavy"
    local pendingDodgeUntil = nil
    local lastParryAt = -math.huge
    local pendingParryUntil = nil
    local activeParryBlock = nil
    local lastWallPhaseAt = -math.huge
    local boundTarget = nil
    local targetAnimationConnection = nil
    local activeThreats = {}

    local function hasClearPath(fromRoot, fromModel, targetRoot, targetModel)
        if not fromRoot or not targetRoot then
            return false
        end
        local offset = targetRoot.Position - fromRoot.Position
        if offset.Magnitude <= 0.001 then
            return true
        end
        local parameters = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = fromModel and { fromModel } or {}
        parameters.IgnoreWater = true
        local hit = context.workspace:Raycast(fromRoot.Position, offset, parameters)
        return hit == nil or (targetModel and hit.Instance:IsDescendantOf(targetModel))
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
        local offset = target and localRoot and (localRoot.Position - target.Position) or Vector3.zero
        local direction = Vector3.new(offset.X, 0, offset.Z)
        if direction.Magnitude <= 0.001 then
            local camera = context.workspace.CurrentCamera
            local look = camera and camera.CFrame.LookVector or Vector3.zAxis
            direction = Vector3.new(-look.X, 0, -look.Z)
        end
        direction = direction.Magnitude > 0 and direction.Unit or Vector3.zAxis
        actionManager:_clearQueuedAction()
        actionManager:SwitchToAction("Dodge", {
            direction = direction,
            isReverse = true,
            dodgeStamina = actionManager._dodgeStamina,
        })
        pendingDodgeUntil = nil
        lastDodgeAt = os.clock()
    end

    local function queueDodge()
        pendingDodgeUntil = os.clock() + 0.3
        tryDodge()
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

    local function disconnectTargetAnimation()
        if targetAnimationConnection then
            targetAnimationConnection:Disconnect()
            targetAnimationConnection = nil
        end
        table.clear(activeThreats)
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
                    and hasClearPath(targetRoot, targetModel, localRoot, localHandler.OriginalModel)
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

    local function hasIncomingThreat()
        for track, threat in pairs(activeThreats) do
            if track.IsPlaying then
                local speed = math.max(math.abs(track.Speed), 0.05)
                for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                    if not threat.reacted[index] then
                        local timeUntilImpact = (impact.markerTime - track.TimePosition) / speed
                        if timeUntilImpact >= -0.08 then
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
            pendingParryUntil = nil
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
            targetAnimationConnection = animator.AnimationPlayed:Connect(function(track)
                observeThreatTrack(handler, track)
            end)
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                observeThreatTrack(handler, track)
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
        if targetHandler and (targetHandler.IsDodging or targetHandler.IsParrying) then
            return
        end
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager or not localHandler.EquippedWeapon then
            return
        end
        if pendingDodgeUntil or pendingParryUntil or localHandler.IsParrying or actionManager.BlockAction then
            return
        end
        if hasIncomingThreat() then
            return
        end

        local localRoot = localHandler.Root
        local weaponHandler = localHandler:GetEquippedWeaponHandler()
        local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
        if not localRoot or not targetRoot or not attackTypes
            or not hasClearPath(localRoot, localHandler.OriginalModel, targetRoot, targetModel)
        then
            return
        end

        local attack = nextFightAttack
        local resolvedName = actionManager:_resolveAttackName(attack)
        local attackInfo = resolvedName and attackTypes[resolvedName]
        local ultimateInfo = attackTypes.Ultimate
        if ultimateInfo
            and localHandler:CanPerformUltimate()
            and attackCanReach(localRoot, targetRoot, ultimateInfo, true)
        then
            attack = "Ultimate"
            attackInfo = ultimateInfo
        elseif targetHandler and targetHandler.IsBlocking then
            attack = "Heavy"
            attackInfo = attackTypes[actionManager:_resolveAttackName(attack)]
        end

        if not attackCanReach(localRoot, targetRoot, attackInfo, false) then
            local alternate = attack == "Heavy" and "Light" or "Heavy"
            local alternateInfo = attackTypes[actionManager:_resolveAttackName(alternate)]
            if attack == "Ultimate" or not attackCanReach(localRoot, targetRoot, alternateInfo, false) then
                return
            end
            attack = alternate
        end

        if actionManager:TryQueueBasicAttack(attack) and attack ~= "Ultimate" then
            nextFightAttack = attack == "Heavy" and "Light" or "Heavy"
        end
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
