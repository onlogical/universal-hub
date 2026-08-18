local Ugc = {}

local DODGE_COOLDOWN = 0.35
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
    assert(type(context.fireSignal) == "function", "Ugc Auto Dodge requires firesignal")

    local localPlayer = context.players.LocalPlayer
    local GameManager = require(game:GetService("ReplicatedStorage").GameManager)
    local characterController = GameManager:GetController("CharacterController")
    local targetLockController = GameManager:GetController("TargetLockController")
    local playerInputController = GameManager:GetController("PlayerInputController")
    local dodgeAction = playerInputController.InputActions.CharacterGameplayContext.DodgeAction
    local stopped = false
    local lastDodgeAt = -math.huge
    local lastWallPhaseAt = -math.huge
    local boundTarget = nil
    local targetAnimationConnection = nil

    local function dodge()
        if os.clock() - lastDodgeAt < DODGE_COOLDOWN then
            return
        end
        lastDodgeAt = os.clock()
        context.fireSignal(dodgeAction.Pressed)
    end

    local function onTargetAnimationPlayed(track)
        if context.store:Get().settings.autoDodge ~= true or not isCombatAnimation(track) then
            return
        end
        dodge()
    end

    local function disconnectTargetAnimation()
        if targetAnimationConnection then
            targetAnimationConnection:Disconnect()
            targetAnimationConnection = nil
        end
    end

    local function updateAutoDodge(settings)
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
        if settings.autoDodge == true then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if isCombatAnimation(track) and track.TimePosition < 0.2 then
                    dodge()
                    break
                end
            end
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

    local connection = game:GetService("RunService").RenderStepped:Connect(function()
        if stopped then
            return
        end

        local settings = context.store:Get().settings or {}
        updateAutoDodge(settings)
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
            "autoDodge",
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
            connection:Disconnect()
        end,
    }
end

return Ugc
