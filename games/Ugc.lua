local Ugc = {}

local DODGE_COOLDOWN = 0.35
local FIGHT_RETRY_INTERVAL = 0.05
local GUARANTEED_HIT_DISTANCE = 10
local PARRY_COOLDOWN = 0.35
local PARRY_HOLD_TIME = 0.12
local TARGET_BACKSTEP_DISTANCE = 4
local WALL_PHASE_COOLDOWN = 0.35

local function isCombatAnimation(track)
    local priority = track and track.Priority
    return priority == Enum.AnimationPriority.Action
        or priority == Enum.AnimationPriority.Action2
        or priority == Enum.AnimationPriority.Action3
        or priority == Enum.AnimationPriority.Action4
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
        if os.clock() - lastParryAt < PARRY_COOLDOWN then
            pendingParryUntil = nil
            queueDodge()
            return
        end
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager then
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

    local function onTargetAnimationPlayed(track)
        if not isCombatAnimation(track) then
            return
        end
        local settings = context.store:Get().settings
        if settings.autoDodge == true then
            queueDodge()
        elseif settings.autoParry == true then
            queueParry()
        end
    end

    local function disconnectTargetAnimation()
        if targetAnimationConnection then
            targetAnimationConnection:Disconnect()
            targetAnimationConnection = nil
        end
    end

    local function updateAutoDodge(settings)
        if settings.autoDodge ~= true and settings.autoParry ~= true then
            pendingDodgeUntil = nil
        else
            tryDodge()
        end
        if settings.autoParry ~= true then
            pendingParryUntil = nil
        else
            tryParry()
        end
        local target = targetLockController.Target
        if target ~= boundTarget then
            disconnectTargetAnimation()
            boundTarget = target
        end
        if not target or targetAnimationConnection then
            return
        end
        local model = target and target:FindFirstAncestorWhichIsA("Model")
        local handler = model and characterController:GetCharacterHandler(model)
        local animator = handler and handler.Animator
        if not animator then
            return
        end
        targetAnimationConnection = animator.AnimationPlayed:Connect(onTargetAnimationPlayed)
        if settings.autoDodge == true or settings.autoParry == true then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if isCombatAnimation(track) and track.TimePosition < 0.2 then
                    if settings.autoDodge == true then
                        queueDodge()
                    else
                        queueParry()
                    end
                    break
                end
            end
        end
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
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager or not localHandler.EquippedWeapon then
            return
        end

        local attack = nextFightAttack
        local localRoot = localHandler.Root
        local offset = localRoot and (target.Position - localRoot.Position) or Vector3.zero
        local distance = offset.Magnitude
        local facingTarget = distance > 0
            and localRoot.CFrame.LookVector:Dot(offset.Unit) >= 0.5
        local clearHit = false
        if distance > 0 and distance <= GUARANTEED_HIT_DISTANCE and facingTarget then
            local parameters = RaycastParams.new()
            parameters.FilterType = Enum.RaycastFilterType.Exclude
            local ignoredModels = {}
            if localHandler.Model then
                table.insert(ignoredModels, localHandler.Model)
            end
            if localHandler.OriginalModel then
                table.insert(ignoredModels, localHandler.OriginalModel)
            end
            parameters.FilterDescendantsInstances = ignoredModels
            parameters.IgnoreWater = true
            local hit = context.workspace:Raycast(localRoot.Position, offset, parameters)
            clearHit = hit ~= nil and hit.Instance:IsDescendantOf(targetModel)
        end
        if clearHit and localHandler:CanPerformUltimate() then
            attack = "Ultimate"
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
        updateAutoDodge(settings)
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
            "autoDodge",
            "autoParry",
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
