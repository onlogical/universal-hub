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

local AutoMovement =
    importDependency("games/duelinggrounds/features/AutoMovement", "./features/AutoMovement")
local CombatPipeline =
    importDependency("games/duelinggrounds/features/CombatPipeline", "./features/CombatPipeline")
local CombatRuntime =
    importDependency("games/duelinggrounds/features/CombatRuntime", "./features/CombatRuntime")
local Noclip = importDependency("games/duelinggrounds/features/Noclip", "./features/Noclip")
local TeleportBehind =
    importDependency("games/duelinggrounds/features/TeleportBehind", "./features/TeleportBehind")
local WinTitles =
    importDependency("games/duelinggrounds/features/WinTitles", "./features/WinTitles")
local Persistence =
    importDependency("games/duelinggrounds/recording/Persistence", "./recording/Persistence")
local Recording = importDependency("games/duelinggrounds/recording/Runtime", "./recording/Runtime")
local Styles =
    importDependency("games/duelinggrounds/features/combat/Styles", "./features/combat/Styles")

local Adapter = {}

local DEFAULT_PROFILE = {
    approachDistance = 7.25,
    orbitDistance = 5.25,
    retreatDistance = 3.25,
}

local function weaponInfo(handler)
    local weapon = handler and handler:GetEquippedWeaponHandler()
    return weapon and weapon.WeaponInfo
end

function Adapter.new(context)
    assert(context and context.store and context.players and context.render)
    local Players = context.players
    local LocalPlayer = Players.LocalPlayer
    local Workspace = context.workspace or workspace
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local GameManager = require(ReplicatedStorage.GameManager)
    local characterController = GameManager:GetController("CharacterController")
    local targetLockController = GameManager:GetController("TargetLockController")
    local playerInputController = GameManager:GetController("PlayerInputController")
    local pingController = GameManager:GetController("PingController")
    local environment = type(getgenv) == "function" and getgenv() or _G
    local recording
    recording = Recording.new({
        environment = environment,
        persistence = Persistence.new({
            writefile = type(writefile) == "function" and writefile or nil,
            makefolder = type(makefolder) == "function" and makefolder or nil,
            isfolder = type(isfolder) == "function" and isfolder or nil,
            jsonEncode = function(value)
                return game:GetService("HttpService"):JSONEncode(value)
            end,
        }),
    })
    local combat = CombatRuntime.new({
        players = Players,
        workspace = Workspace,
        characterController = characterController,
        targetLockController = targetLockController,
        ping = function()
            return pingController:GetPing()
        end,
        criticalStrike = function(model)
            ReplicatedStorage.Remotes.PlayerCharacter.Request.CriticalStrike:FireServer(model)
        end,
        record = function(kind, data)
            if string.find(kind, "defense", 1, true) then
                recording:recordDecision(kind, data)
            else
                recording:recordEvent(kind, data)
            end
        end,
    })
    local movement = AutoMovement.new()
    local noclip = Noclip.new()
    local winTitles = WinTitles.new()
    local stopped = false

    local function frame(settings)
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        local localHandler = characterController:GetLocalCharacterHandler()
        local targetHandler = targetModel and characterController:GetCharacterHandler(targetModel)
        local localModel = localHandler and (localHandler.OriginalModel or localHandler.Model)
        local targetRoot = targetHandler and targetHandler.Root or target
        local localRoot = localHandler and localHandler.Root
        local localWeapon = weaponInfo(localHandler)
        local targetWeapon = weaponInfo(targetHandler)
        local targetPlayer = targetModel and Players:GetPlayerFromCharacter(targetModel)
        local localState = {
            health = localModel and localModel:GetAttribute("Health"),
            maximumHealth = localModel and localModel:GetAttribute("MaxHealth"),
            posture = localModel and localModel:GetAttribute("Posture"),
            maximumPosture = localModel and localModel:GetAttribute("MaxPosture"),
        }
        return {
            settings = settings,
            target = target,
            targetModel = targetModel,
            targetHandler = targetHandler,
            targetRoot = targetRoot,
            localHandler = localHandler,
            localRoot = localRoot,
            localModel = localModel,
            localState = localState,
            targetDead = targetModel and targetModel:GetAttribute("IsDead") == true,
            selfDead = localModel and localModel:GetAttribute("IsDead") == true,
            metadata = {
                gameId = game.GameId,
                placeId = game.PlaceId,
                jobId = game.JobId,
                localPlayer = LocalPlayer.Name,
                localUserId = LocalPlayer.UserId,
                target = targetPlayer and targetPlayer.Name or targetModel and targetModel.Name,
                targetUserId = targetPlayer and targetPlayer.UserId,
                selfWeapon = localWeapon and localWeapon.WeaponName,
                targetWeapon = targetWeapon and targetWeapon.WeaponName,
            },
        }
    end

    local function render(settings)
        local observations = settings.showEnemies == false and {}
            or context.oh.targeting.observePlayers({
                isEligible = function(player)
                    return player ~= LocalPlayer
                end,
                screenOrigin = Vector2.zero,
            })
        for _, observation in ipairs(observations) do
            local humanoid = observation.character
                and observation.character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health
            observation.maxHealth = humanoid and humanoid.MaxHealth
            observation.tone = "enemy"
        end
        context.render(observations, Vector2.zero, {})
        context.store:Patch({
            observations = observations,
            status = ("%d players visible"):format(#observations),
        })
    end

    local connection = RunService.RenderStepped:Connect(function()
        if stopped then
            return
        end
        local settings = context.store:Get().settings or {}
        local current = frame(settings)
        CombatPipeline.run({
            record = function()
                local disposition = combat:disposition()
                current.dynamicMode = disposition.dynamicState.mode
                current.defense = disposition.defenseIntent and disposition.defenseIntent.kind
                current.critical = targetLockController.CriticalStrikeTarget ~= nil
                recording:update(current, settings)
            end,
            defend = function()
                combat:observeAndDefend(settings, current)
            end,
            relocate = function()
                TeleportBehind.update(settings, {
                    targetDead = current.targetDead,
                    localRoot = current.localRoot,
                    targetRoot = current.targetRoot,
                    distance = 4,
                })
            end,
            attack = function()
                combat:attack(settings, current)
            end,
            move = function()
                local disposition = combat:disposition()
                local actions = current.localHandler and current.localHandler.ActionManager
                local style = Styles.preferences(
                    settings.combatStyle,
                    current.localState,
                    disposition.dynamicState
                )
                movement:update(settings, {
                    input = playerInputController.CurrentInput,
                    target = current.target,
                    localPosition = current.localRoot and current.localRoot.Position,
                    targetPosition = current.targetRoot and current.targetRoot.Position,
                    profile = {
                        approachDistance = DEFAULT_PROFILE.approachDistance,
                        orbitDistance = DEFAULT_PROFILE.orbitDistance
                            * ((style.movement and style.movement.orbitDistanceScale) or 1),
                        retreatDistance = DEFAULT_PROFILE.retreatDistance,
                    },
                    movement = style.movement,
                    now = os.clock(),
                }, {
                    canMove = not disposition.defenseIntent
                        and not disposition.incomingThreat
                        and actions ~= nil
                        and not actions._queuedActionType
                        and not actions.BlockAction
                        and not current.localHandler.IsDodging
                        and not current.localHandler.IsParrying,
                })
            end,
            effects = function()
                noclip:update(settings.noclip == true, LocalPlayer.Character)
                winTitles:update(settings.showWins == true, Players)
            end,
            render = function()
                render(settings)
            end,
        }, current)
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
            "showWins",
            "autoFight",
            "autoMovement",
            "botSkill",
            "combatStyle",
            "teleportBehind",
            "noclip",
        },
        isOpponent = function(player)
            return player ~= nil and player ~= LocalPlayer
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            connection:Disconnect()
            combat:stop()
            movement:stop()
            recording:stop("sessionStopped")
            noclip:stop()
            winTitles:stop()
        end,
    }
end

return Adapter
