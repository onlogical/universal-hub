return {
    buildId = [[275d1097]],
    id = [[rivals]],
    sources = {
        ["games/rivals/Adapter.lua"] = [[local Targeting = require("./libraries/Targeting")
local ProjectileAim = require("./libraries/ProjectileAim")
local Session = require("./Session")
local CameraAim = require("./features/CameraAim")
local SilentAim = require("./features/SilentAim")
local TeleportBehind = require("./features/TeleportBehind")
local TriggerBot = require("./features/TriggerBot")
local RapidFire = require("./features/RapidFire")
local SkipBlocks = require("./features/SkipBlocks")
local AutoDeflect = require("./features/AutoDeflect")
local AutoCounter = require("./features/AutoCounter")
local NoScope = require("./features/NoScope")
local Pickup = require("./features/Pickup")
local RedLightSafety = require("./features/RedLightSafety")
local TaskLoadout = require("./tasks/TaskLoadout")
local HookRuntime = require("./libraries/HookRuntime")
local WeaponPolicy = require("./libraries/WeaponPolicy")
local ItemInput = require("./libraries/ItemInput")
local Effects = require("./world/Effects")
local Movement = require("./libraries/Movement")
local TaskCamera = require("./tasks/TaskCamera")
local TaskLocomotion = require("./tasks/TaskLocomotion")
local TaskWeaponSwap = require("./tasks/TaskWeaponSwap")
local TaskSkillRuntime = require("./tasks/TaskSkillRuntime")
local TaskCounterPolicy = require("./tasks/TaskCounterPolicy")
local TaskPolicy = require("./tasks/TaskPolicy")
local CombatState = require("./libraries/CombatState")
local ModePolicy = require("./libraries/ModePolicy")
local GunGameRuntime = require("./features/GunGameRuntime")
local ObservationRuntime = require("./world/ObservationRuntime")
local AutoCounterRuntime = require("./features/AutoCounterRuntime")
local WorldPolicy = require("./world/WorldPolicy")
local TaskFarmRuntime = require("./tasks/TaskFarmRuntime")
local PracticeTaskDriver = require("./tasks/PracticeTaskDriver")

local Rivals = {}

local TRIGGER_INTERVAL = TriggerBot.INTERVAL
local TRIGGER_RADIUS = TriggerBot.RADIUS

function Rivals.playerTone(localPlayer, player, character)
    if player == localPlayer or not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return nil
    end

    if localPlayer:GetAttribute("EnvironmentID") ~= player:GetAttribute("EnvironmentID") then
        return nil
    end

    local localTeam = localPlayer:GetAttribute("TeamID")
    local playerTeam = player:GetAttribute("TeamID")
    return localTeam ~= nil and playerTeam ~= nil and localTeam == playerTeam and "team" or "enemy"
end

function Rivals.isOpponent(localPlayer, player, character)
    return Rivals.playerTone(localPlayer, player, character) == "enemy"
end

function Rivals.capabilityContext(context)
    context = context or {}
    local duelController = context.duelController
    local player = context.player
    -- Capability discovery runs before Adapter.new and therefore before the
    -- native loading-screen readiness gate. The live path must never require a
    -- controller here; injected test/composition loaders are already isolated.
    if not duelController and type(context.requireModule) == "function" then
        local gameObject = context.game or game
        local players = gameObject:GetService("Players")
        player = player or players.LocalPlayer
        local controllers = player.PlayerScripts:WaitForChild("Controllers")
        duelController = context.requireModule(controllers:WaitForChild("DuelController"))
    end
    return {
        isGunGame = duelController ~= nil
                and ModePolicy.controllerIsGunGame(duelController, player)
            or false,
    }
end

function Rivals.capabilitiesFor(context, declaredCapabilities)
    context = context or {}
    -- Gun Game is joined after execute. Do not snapshot IsGunGame here or the
    -- Tools tab disappears for the rest of the session.
    local autoPickupAvailable = context.fireTouchInterestAvailable == true
    local hookFeaturesAvailable = context.hookFunctionAvailable == true
        and context.restoreFunctionAvailable == true
    local capabilities = {}
    for _, capability in ipairs(declaredCapabilities or {}) do
        local available = capability ~= "autoPickup" or autoPickupAvailable
        if
            capability == "shotAim"
            or capability == "alwaysScoped"
            or capability == "skipDeflect"
            or capability == "redLightSafety"
        then
            available = available and hookFeaturesAvailable
        end
        if available then
            table.insert(capabilities, capability)
        end
    end
    return capabilities
end

function Rivals.entityIsInvincible(entity)
    if type(entity) ~= "table" then
        return false
    end

    if type(entity.Get) == "function" then
        local succeeded, value = pcall(entity.Get, entity, "IsInvincible")
        if succeeded and value ~= nil then
            return value == true
        end
    end

    local data = entity.Data
    return type(data) == "table" and data.IsInvincible == true
end

function Rivals.lowestHealthObservation(observations, validate, nearest)
    local lowestHealth = math.huge
    local lowest = {}
    for _, observation in ipairs(observations or {}) do
        local accepted = validate(observation)
        local health = accepted and accepted.health
        if type(health) == "number" and health > 0 then
            if health < lowestHealth then
                lowestHealth = health
                lowest = { accepted }
            elseif health == lowestHealth then
                table.insert(lowest, accepted)
            end
        end
    end
    if #lowest == 0 then
        return nil
    end
    return nearest(lowest)
end

Rivals.pickupType = GunGameRuntime.pickupType
Rivals.shouldCollectPickup = GunGameRuntime.shouldCollect

function Rivals.isTargetable(localPlayer, player, character, fighter, isGunGame)
    if
        not Rivals.isOpponent(localPlayer, player, character)
        or character:FindFirstChildOfClass("ForceField") ~= nil
    then
        return false
    end

    return isGunGame ~= true or not Rivals.entityIsInvincible(fighter and fighter.Entity)
end

function Rivals.new(context)
    assert(context and context.oh, "RIVALS adapter requires Hydroxide")
    assert(context.store, "RIVALS adapter requires a reactive store")

    local clock = context.clock or os.clock
    local itemClock = context.itemClock or tick
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ContextActionService = context.contextActionService
        or game:GetService("ContextActionService")
    local Workspace = game:GetService("Workspace")
    local Lighting = context.lighting or game:GetService("Lighting")
    local CollectionService = context.collectionService or game:GetService("CollectionService")
    local LocalPlayer = Players.LocalPlayer
    local loadModule: (any) -> any = context.requireModule or require
    local controllers = LocalPlayer.PlayerScripts:WaitForChild("Controllers")
    local cameraControllerModule = controllers:WaitForChild("CameraController")
    local duelControllerModule = controllers:WaitForChild("DuelController")
    local fighterControllerModule = controllers:WaitForChild("FighterController")
    local controlsControllerModule = controllers:WaitForChild("ControlsController")
    local mechanicsControllerModule = controllers:WaitForChild("MechanicsController")
    local playerDataControllerModule
    local matchmakingControllerModule
    local shootingRangeControllerModule
    if context.taskFarmRuntime == nil then
        playerDataControllerModule = controllers:WaitForChild("PlayerDataController")
        matchmakingControllerModule = controllers:WaitForChild("MatchmakingController")
        shootingRangeControllerModule = controllers:WaitForChild("ShootingRangeController")
    end
    if context.requireModule == nil then
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        if character and not character:FindFirstChild("HumanoidRootPart") then
            character:WaitForChild("HumanoidRootPart", 15)
        end
        -- game:IsLoaded() and character readiness both precede RIVALS' own
        -- controller bootstrap. Requiring Camera/Fighter/Mechanics while its
        -- native LoadingScreen is enabled permanently poisons those modules.
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")
        local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
        local loadingDeadline = os.clock() + 3
        while loadingScreen == nil and os.clock() < loadingDeadline do
            RunService.Heartbeat:Wait()
            loadingScreen = playerGui:FindFirstChild("LoadingScreen")
        end
        while loadingScreen and loadingScreen.Parent ~= nil and loadingScreen.Enabled == true do
            RunService.Heartbeat:Wait()
        end
        RunService.Heartbeat:Wait()
    end
    local CameraController = loadModule(cameraControllerModule)
    local DuelController = loadModule(duelControllerModule)
    local FighterController = loadModule(fighterControllerModule)
    local ControlsController = loadModule(controlsControllerModule)
    local MechanicsController = loadModule(mechanicsControllerModule)
    local PlayerDataController
    local MatchmakingController
    local ShootingRangeController
    local TaskLibrary
    local RivalsConstants
    if context.taskFarmRuntime == nil then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local modules = ReplicatedStorage:WaitForChild("Modules")
        PlayerDataController = context.playerDataController
            or loadModule(playerDataControllerModule)
        MatchmakingController = context.matchmakingController
            or loadModule(matchmakingControllerModule)
        ShootingRangeController = context.shootingRangeController
            or loadModule(shootingRangeControllerModule)
        TaskLibrary = context.taskLibrary or loadModule(modules:WaitForChild("TaskLibrary"))
        RivalsConstants = context.rivalsConstants or loadModule(modules:WaitForChild("CONSTANTS"))
    end
    local function isGunGame()
        return ModePolicy.controllerIsGunGame(DuelController, LocalPlayer)
    end
    local PickWeaponsPage = context.pickWeaponsPage
        or loadModule(
            LocalPlayer.PlayerScripts
                :WaitForChild("Modules")
                :WaitForChild("Pages")
                :WaitForChild("PickWeapons")
        )
    assert(
        PickWeaponsPage and type(PickWeaponsPage.IsOpen) == "function",
        "RIVALS adapter requires the live Pick Weapons page"
    )
    local spawn = context.spawn or task.spawn
    local targeting = context.oh.targeting
    local store = context.store
    if context.teleportBootstrap ~= true and store:Get().settings.taskAutomationPaused ~= true then
        local state = store:Get()
        local settings = table.clone(state.settings)
        settings.taskAutomationPaused = true
        store:Patch({ settings = settings })
        if context.settingsChanged then
            context.settingsChanged(settings)
        end
    end
    local lastTaskPauseSetting = store:Get().settings.taskAutomationPaused == true
    local session = Session.new()
    local stopped = false
    local trigger = {
        fireAmmo = nil,
        fireAmmoAt = 0,
        fireHeld = false,
        fireItem = nil,
        gunblade = nil,
        held = false,
        heldAt = 0,
        heldItem = nil,
        nextAt = 0,
    }
    local aimPlan
    local aimTargetKey
    local aimTargetWeapon
    local humanAimCharacter
    local humanAimState
    local renderDelta = 1 / 60
    local observations = {}
    local visualObservations = observations
    local taskFarmRuntime
    local taskEmergencyConnection
    local autoCounterInFlight = false
    local self = { autoCounterDebug = {}, taskDebug = {} }
    local getNetworkPing = context.getNetworkPing
        or function()
            return LocalPlayer:GetNetworkPing()
        end
    local random = context.random or math.random
    local effects = Effects.new({
        clock = clock,
        collectionService = CollectionService,
        lighting = Lighting,
        limn = context.limn,
        localPlayer = LocalPlayer,
        playerGui = context.playerGui,
        projectileAim = ProjectileAim,
        workspace = Workspace,
    })
    local observeThrowables = context.observeThrowables
        or function(camera, environmentID)
            return effects:observeThrowables(camera, environmentID)
        end

    local combatInput = ItemInput.new(function()
        return FighterController.LocalFighter
    end)
    local rapidFire = RapidFire.new(WeaponPolicy)
    local function startShooting()
        return combatInput:fire()
    end
    local function finishShooting()
        return combatInput:releaseFire()
    end
    local function startAiming()
        return combatInput:aim()
    end
    local function finishAiming()
        return combatInput:releaseAim()
    end

    local function releaseFire()
        if not trigger.fireHeld then
            return
        end
        combatInput:releaseFire()
        trigger.fireHeld = false
        trigger.fireItem = nil
        trigger.fireAmmo = nil
        trigger.fireAmmoAt = 0
    end

    local taskWeaponSwap = TaskWeaponSwap.new({
        clock = clock,
        equip = function(fighter, item)
            if type(fighter.EquipItem) == "function" then
                local succeeded, result = pcall(fighter.EquipItem, fighter, item)
                if succeeded and result ~= false then
                    return true
                end
            end
            return ItemInput.dispatch(fighter, ItemInput.equipAction(item))
        end,
        weaponPolicy = WeaponPolicy,
        release = function()
            releaseFire()
            if trigger.held then
                finishAiming()
                trigger.held = false
                trigger.heldItem = nil
            end
        end,
    })

    local taskSkillRuntime = TaskSkillRuntime.new({ localPlayer = LocalPlayer })
    local taskCounterPolicy = TaskCounterPolicy.new({ clock = clock })
    local taskSkillWasActive = false
    local nextCounterEquipAt = 0
    local function fighterFor(player)
        if player == LocalPlayer then
            return FighterController.LocalFighter
        end
        if type(FighterController.GetFighter) == "function" then
            local succeeded, fighter =
                pcall(FighterController.GetFighter, FighterController, player)
            if succeeded and fighter ~= nil then
                return fighter
            end
        end
        local fighters = FighterController._player_to_fighter
        return type(fighters) == "table" and fighters[player] or nil
    end

    local function equippedWeapon(player)
        local fighter = fighterFor(player)
        return fighter and WeaponPolicy.itemLabel(fighter.EquippedItem) or nil
    end

    local function isDeflecting(player)
        local fighter = fighterFor(player)
        return WeaponPolicy.isActivelyDeflecting(fighter and fighter.EquippedItem)
    end

    local function currentCameraSubject()
        if type(CameraController.GetCurrentSubject) == "function" then
            local succeeded, subject = pcall(CameraController.GetCurrentSubject, CameraController)
            if succeeded then
                return subject
            end
        end
        return CameraController._current_subject
    end

    local function localFighterIsActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return fighter ~= nil
            and currentCameraSubject() == fighter
            and humanoid ~= nil
            and humanoid.Health > 0
    end

    local function localFighterIsTaskActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return humanoid ~= nil and humanoid.Health > 0 and not PickWeaponsPage:IsOpen()
    end

    local function localFighterIsInCombat()
        local fighter = FighterController.LocalFighter
        return CombatState.isCombatEligible(
            fighter,
            DuelController:GetDuel(LocalPlayer),
            PickWeaponsPage:IsOpen()
        )
    end

    local function localFighterIsInRound()
        local fighter = FighterController.LocalFighter
        return CombatState.isRoundEligible(
            fighter,
            DuelController:GetDuel(LocalPlayer),
            PickWeaponsPage:IsOpen()
        )
    end

    local function localFighterRoot()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        return entity and (entity.RootPart or entity.HumanoidRootPart)
    end
    local function localFighterHumanoid()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        return entity and entity.Humanoid
    end
    local gameplayUtility
    local teleportPhysics
    local function localFighterCharacter()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        return entity and entity.Character or LocalPlayer.Character
    end
    local function ricochetRaycast()
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = true

        local excluded = {}
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        for _, observation in ipairs(observations) do
            if observation.character then
                table.insert(excluded, observation.character)
            end
        end
        raycastParams.FilterDescendantsInstances = excluded

        return function(origin, displacement)
            return Workspace:Raycast(origin, displacement, raycastParams)
        end
    end
    local environmentRaycast = context.environmentRaycast or ricochetRaycast
    local function teleportLibs()
        return {
            clock = clock,
            getRoot = localFighterRoot,
            getHumanoid = localFighterHumanoid,
            getCharacter = localFighterCharacter,
            isImmune = function()
                local fighter = FighterController.LocalFighter
                local entity = fighter and fighter.Entity
                return TeleportBehind.hasForceField(localFighterCharacter())
                    or Rivals.entityIsInvincible(entity)
            end,
            raycast = function(origin, displacement)
                if type(environmentRaycast) ~= "function" then
                    return nil
                end
                local cast = environmentRaycast()
                if type(cast) ~= "function" then
                    return nil
                end
                return cast(origin, displacement)
            end,
            weaponMode = function()
                local fighter = FighterController.LocalFighter
                local item = fighter and fighter.EquippedItem
                if WeaponPolicy.isBackstabKnife(item) then
                    return "knife"
                end
                if WeaponPolicy.isScoped(item) then
                    return "sniper"
                end
                return "barrage"
            end,
            killParts = function()
                return CollectionService:GetTagged(TeleportBehind.OOB_TAG)
            end,
            isOutOfBounds = function(position)
                if gameplayUtility == nil then
                    local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
                    local moduleScript = modules and modules:FindFirstChild("GameplayUtility")
                    if moduleScript then
                        local ok, result = pcall(loadModule, moduleScript)
                        gameplayUtility = ok and result or false
                    else
                        gameplayUtility = false
                    end
                end
                if
                    type(gameplayUtility) == "table"
                    and type(gameplayUtility.IsWithinOOBPart) == "function"
                then
                    return gameplayUtility:IsWithinOOBPart(position) ~= nil
                end
                return TeleportBehind.isOutOfBounds(position, {
                    kill = CollectionService:GetTagged(TeleportBehind.OOB_TAG),
                    safe = CollectionService:GetTagged(TeleportBehind.OOB_SAFE_TAG),
                })
            end,
        }
    end
    local function stopTeleportPhysics()
        if teleportPhysics then
            for _, connection in ipairs(teleportPhysics) do
                connection:Disconnect()
            end
            teleportPhysics = nil
        end
        TeleportBehind.release(session, {
            getRoot = localFighterRoot,
            getHumanoid = localFighterHumanoid,
        })
    end
    local function startTeleportPhysics()
        if teleportPhysics then
            return
        end
        local function holdAfterPhysics()
            if stopped then
                return
            end
            TeleportBehind.hold(session, {
                getRoot = localFighterRoot,
                getHumanoid = localFighterHumanoid,
            })
        end
        teleportPhysics = {
            RunService.Stepped:Connect(holdAfterPhysics),
            RunService.Heartbeat:Connect(holdAfterPhysics),
        }
    end

    local autoCounterRuntime = AutoCounterRuntime.new({ clock = clock })

    local function localFighterIsCrouching(fighter)
        local isCrouching = fighter and fighter.IsCrouching
        if type(isCrouching) == "function" then
            local succeeded, crouching = pcall(isCrouching, fighter)
            if succeeded then
                return crouching == true
            end
        end
        local data = fighter and fighter.Data
        return type(data) == "table" and data.IsCrouching == true
    end

    local suppressBhopJump = false
    local movement = Movement.new({
        clock = clock,
        controlsController = ControlsController,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        getSettings = function()
            return store:Get().settings
        end,
        isActive = localFighterIsActive,
        isTaskActive = localFighterIsTaskActive,
        isInCombat = localFighterIsInCombat,
        isInputCaptured = context.isInputCaptured,
        isTaskInputCaptured = function()
            return context.isInputCaptured() and store:Get().menuVisible ~= true
        end,
        mechanicsController = MechanicsController,
        movementDirection = context.movementDirection,
        taskObstacleProbe = function(origin, direction)
            if
                not Workspace.Raycast
                or typeof(origin) ~= "Vector3"
                or typeof(direction) ~= "Vector3"
            then
                return false
            end
            local params
            if RaycastParams and type(RaycastParams.new) == "function" then
                params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = LocalPlayer.Character
                        and { LocalPlayer.Character }
                    or {}
                params.IgnoreWater = true
            end
            local result =
                Workspace:Raycast(origin + Vector3.new(0, 2, 0), direction.Unit * 6, params)
            return result ~= nil
        end,
        taskParkourProbe = function(origin, direction)
            if
                not Workspace.Raycast
                or typeof(origin) ~= "Vector3"
                or typeof(direction) ~= "Vector3"
            then
                return nil
            end
            local params
            if RaycastParams and type(RaycastParams.new) == "function" then
                params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = LocalPlayer.Character
                        and { LocalPlayer.Character }
                    or {}
                params.IgnoreWater = true
            end
            local unit = direction.Magnitude > 0.01 and direction.Unit or Vector3.zero
            local function blocked(height, length)
                return Workspace:Raycast(origin + Vector3.new(0, height, 0), unit * length, params)
                    ~= nil
            end
            local function groundAt(distance)
                local castOrigin = origin + unit * distance + Vector3.new(0, 5, 0)
                local result = Workspace:Raycast(castOrigin, Vector3.new(0, -13, 0), params)
                return result and result.Normal.Y >= 0.55 and result or nil
            end
            local currentGround = groundAt(0)
            local nearGround = groundAt(3)
            local landing = groundAt(7)
            local result = {
                low = blocked(0.75, 4.5),
                middle = blocked(2.5, 4.5),
                high = blocked(4.5, 4.5),
                landing = landing ~= nil,
            }
            -- Baritone's MovementParkour evaluates bounded jump distances from
            -- shortest to longest, requiring body clearance, a walkable landing,
            -- and overshoot safety before it creates a movement.
            if currentGround and not nearGround then
                local rootHeight = math.clamp(origin.Y - currentGround.Position.Y, 2, 4)
                local fighter = FighterController.LocalFighter
                local humanoid = fighter and fighter.Entity and fighter.Entity.Humanoid
                local walkSpeed = humanoid and humanoid.WalkSpeed or 20
                local jumpPower = humanoid and humanoid.JumpPower or 50
                local gravity = Workspace.Gravity > 0 and Workspace.Gravity or 196.2
                local maxReach = math.clamp(walkSpeed * (2 * jumpPower / gravity) * 0.82, 6, 11)
                local lateral = Vector3.new(-unit.Z, 0, unit.X)
                local function landingPatch(distance, center)
                    if not center then
                        return false
                    end
                    for _, offset in ipairs({
                        lateral * 1.1,
                        lateral * -1.1,
                        unit * 0.9,
                        unit * -0.9,
                    }) do
                        local castOrigin = origin + unit * distance + offset + Vector3.new(0, 5, 0)
                        local patch = Workspace:Raycast(castOrigin, Vector3.new(0, -13, 0), params)
                        if
                            not patch
                            or patch.Normal.Y < 0.55
                            or math.abs(patch.Position.Y - center.Position.Y) > 0.75
                        then
                            return false
                        end
                    end
                    return true
                end
                for _, distance in ipairs({ 6, 8, 10 }) do
                    if distance > maxReach then
                        break
                    end
                    local candidate = groundAt(distance)
                    local overshoot = groundAt(distance + 2)
                    local verticalDelta = candidate
                        and candidate.Position.Y - currentGround.Position.Y
                    local clearTrajectory = not blocked(2.5, distance - 1)
                        and not blocked(4.5, distance - 1)
                    if Workspace.Blockcast and clearTrajectory then
                        local castFrame = CFrame.new(origin + Vector3.new(0, 1.2, 0))
                        clearTrajectory = Workspace:Blockcast(
                            castFrame,
                            Vector3.new(2.4, 4.6, 2.4),
                            unit * math.max(0, distance - 2),
                            params
                        ) == nil
                    end
                    local headClear = candidate
                        and Workspace:Raycast(
                                candidate.Position + Vector3.new(0, 0.35, 0),
                                Vector3.new(0, 5.5, 0),
                                params
                            )
                            == nil
                    if
                        candidate
                        and overshoot
                        and clearTrajectory
                        and headClear
                        and landingPatch(distance, candidate)
                        and verticalDelta >= -2.5
                        and verticalDelta <= 2
                    then
                        result.jumpLanding = candidate.Position + Vector3.new(0, rootHeight, 0)
                        result.jumpDistance = distance
                        result.jumpConfidence = 1
                        result.landing = true
                        break
                    end
                end
            end
            return result
        end,

        taskLineOfSightBlocked = function(origin, targetPosition)
            if
                not Workspace.Raycast
                or typeof(origin) ~= "Vector3"
                or typeof(targetPosition) ~= "Vector3"
            then
                return false
            end
            local displacement = targetPosition - (origin + Vector3.new(0, 2, 0))
            if displacement.Magnitude <= 4 then
                return false
            end
            local params
            if RaycastParams and type(RaycastParams.new) == "function" then
                params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = LocalPlayer.Character
                        and { LocalPlayer.Character }
                    or {}
                params.IgnoreWater = true
            end
            return Workspace:Raycast(
                origin + Vector3.new(0, 2, 0),
                displacement.Unit * (displacement.Magnitude - 3),
                params
            ) ~= nil
        end,
        shouldSuppressJump = function()
            return suppressBhopJump
        end,
        spawn = spawn,
        userInputService = UserInputService,
    })
    local taskLocomotion = TaskLocomotion.new()
    local redLightSafety
    if table.find(context.capabilities or {}, "redLightSafety") then
        local actionName = "UniversalHubRivalsRedLightSafety"
        redLightSafety = RedLightSafety.new({
            enabled = function()
                return not stopped and store:Get().settings.redLightSafety == true
            end,
            hookFunction = context.hookFunction,
            releaseAll = function()
                combatInput:releaseAll()
                trigger.fireHeld = false
                trigger.fireItem = nil
                trigger.held = false
                trigger.heldItem = nil
            end,
            restoreFunction = context.restoreFunction,
            setInputSink = function(enabled)
                if enabled then
                    ContextActionService:BindActionAtPriority(
                        actionName,
                        function()
                            return Enum.ContextActionResult.Sink
                        end,
                        false,
                        Enum.ContextActionPriority.High.Value + 200,
                        Enum.UserInputType.MouseButton1,
                        Enum.UserInputType.MouseButton2,
                        Enum.KeyCode.W,
                        Enum.KeyCode.A,
                        Enum.KeyCode.S,
                        Enum.KeyCode.D,
                        Enum.KeyCode.Space,
                        Enum.KeyCode.LeftShift,
                        Enum.KeyCode.C
                    )
                else
                    ContextActionService:UnbindAction(actionName)
                end
            end,
            stopMovement = function()
                movement:stopTaskCombat()
                movement:stop()
                local humanoid = localFighterHumanoid()
                if humanoid and type(humanoid.Move) == "function" then
                    humanoid:Move(Vector3.zero, false)
                end
            end,
        })
    end

    local function playerTone(player, character)
        return Rivals.playerTone(LocalPlayer, player, character)
    end

    local function isOpponent(player, character)
        return playerTone(player, character) == "enemy"
    end

    local function isTargetable(player, character)
        return Rivals.isTargetable(LocalPlayer, player, character, fighterFor(player), isGunGame())
    end

    local function taskOpponentFighter()
        local localEnvironment = LocalPlayer:GetAttribute("EnvironmentID")
        for _, player in ipairs(Players:GetPlayers()) do
            if
                player ~= LocalPlayer
                and player:GetAttribute("EnvironmentID") == localEnvironment
            then
                local fighter = fighterFor(player)
                if fighter then
                    return fighter, player
                end
            end
        end
        return nil, nil
    end

    local function counterLoadoutReady(fighter)
        local items = fighter and fighter.Items
        if type(items) ~= "table" or next(items) == nil then
            return false
        end
        if type(fighter.Get) == "function" then
            local succeeded, canPick = pcall(fighter.Get, fighter, "CanPickWeapons")
            if succeeded and canPick == true then
                return false
            end
        end
        return true
    end

    local gunGameRuntime = GunGameRuntime.new({
        clock = clock,
        fireTouchInterest = context.fireTouchInterest,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        isActive = localFighterIsActive,
        isGunGame = isGunGame,
        isInCombat = localFighterIsInCombat,
        spawn = spawn,
        store = store,
        wait = context.wait,
        workspace = Workspace,
    })

    local function taskNavigationObservation()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local localRoot = entity and (entity.RootPart or entity.HumanoidRootPart)
        if not localRoot then
            return nil
        end
        local nearest
        local nearestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and root and isTargetable(player, character) then
                local distance = (root.Position - localRoot.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearest = {
                        character = character,
                        player = player,
                        part = root,
                        position = root.Position,
                        screenDistance = math.huge,
                        visible = false,
                    }
                end
            end
        end
        return nearest
    end

    local function selectTarget(maxScreenDistance, includeBlocked, ignoreAimFov, preferVisible)
        local settings = store:Get().settings
        local options = {
            includeBlocked = includeBlocked,
            isEligible = isTargetable,
            screenOrigin = UserInputService:GetMouseLocation(),
        }
        if maxScreenDistance then
            options.maxScreenDistance = maxScreenDistance
        elseif not ignoreAimFov then
            local shotOnly = settings.shotAim == true
            local fullScreenAim = shotOnly
                    and (settings.shotFullScreenAim == nil and settings.fullScreenAim or settings.shotFullScreenAim)
                or not shotOnly
                    and (settings.cameraFullScreenAim == nil and settings.fullScreenAim or settings.cameraFullScreenAim)
            if not fullScreenAim then
                options.maxScreenDistance = shotOnly and (settings.shotFov or settings.fov)
                    or (settings.cameraFov or settings.fov)
            end
        end
        local preferredVisible = false
        if preferVisible then
            for _, observation in ipairs(observations) do
                local screenDistance = observation.screenDistance
                if
                    observation.visible == true
                    and (options.maxScreenDistance == nil or type(screenDistance) == "number" and screenDistance <= options.maxScreenDistance)
                    and (
                        observation.player == observation.character
                        or isTargetable(observation.player, observation.character)
                    )
                then
                    preferredVisible = true
                    break
                end
            end
        end
        local function nearest(values)
            local eligible = {}
            for _, observation in ipairs(values) do
                if
                    (not preferredVisible or observation.visible == true)
                    and (
                        observation.player == observation.character
                        or isTargetable(observation.player, observation.character)
                    )
                then
                    table.insert(eligible, observation)
                end
            end
            if settings.humanAim then
                local camera = Workspace.CurrentCamera
                local cameraFrame = camera
                    and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
                return Targeting.closestObservation(
                    eligible,
                    cameraFrame and cameraFrame.Position,
                    options
                )
            end
            return targeting.nearestObservation(eligible, options)
        end
        local selected
        if isGunGame() then
            local fighter = FighterController.LocalFighter
            local item = fighter and fighter.EquippedItem
            local camera = Workspace.CurrentCamera
            local cameraFrame = camera
                and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
            local origin = cameraFrame and cameraFrame.Position
            local function accepted(observation)
                if not includeBlocked and observation.visible ~= true then
                    return nil
                end
                return nearest({ observation })
            end
            local function finishable(observation)
                local candidate = accepted(observation)
                local distance = candidate
                    and origin
                    and candidate.position
                    and (candidate.position - origin).Magnitude
                local damage = candidate and WeaponPolicy.finishingDamage(item, candidate, distance)
                return type(damage) == "number"
                        and type(candidate.health) == "number"
                        and damage >= candidate.health
                        and candidate
                    or nil
            end
            selected = Rivals.lowestHealthObservation(observations, finishable, nearest)
                or Rivals.lowestHealthObservation(observations, accepted, nearest)
                or nearest(observations)
            aimTargetKey = selected and (selected.character or selected.player or selected.part)
                or nil
        else
            selected, aimTargetKey =
                Targeting.selectObservation(observations, aimTargetKey, nearest)
        end
        return selected
    end

    local function selectCrosshairTarget()
        if type(context.selectCrosshairTarget) == "function" then
            return context.selectCrosshairTarget(observations)
        end
        local mouse = LocalPlayer:GetMouse()
        local hit = mouse and mouse.Target
        if not hit then
            return nil
        end
        for _, observation in ipairs(observations) do
            local character = observation.character
            if
                (observation.part == hit or character and hit:IsDescendantOf(character))
                and (observation.player == character or isTargetable(observation.player, character))
            then
                return observation
            end
        end
        return nil
    end

    local function selectBackstabTarget(localPosition, info, acquisitionDistance)
        local nearest
        local nearestDistance = math.huge
        local lowestHealth = math.huge
        for _, observation in ipairs(observations) do
            local character = observation.character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local plan =
                WeaponPolicy.backstabPlan(localPosition, observation, info, acquisitionDistance)
            if
                observation.visible
                and isTargetable(observation.player, character)
                and root
                and plan
            then
                local distance = (localPosition - root.Position).Magnitude
                local health = type(observation.health) == "number" and observation.health
                    or math.huge
                local preferred = isGunGame()
                        and (health < lowestHealth or health == lowestHealth and distance < nearestDistance)
                    or not isGunGame() and distance < nearestDistance
                if preferred then
                    nearest = table.clone(observation)
                    nearest.backstabPlan = plan
                    nearestDistance = distance
                    lowestHealth = health
                end
            end
        end
        return nearest
    end

    local function targetRootPosition(target)
        local character = target and target.character
        local root = character
            and character.FindFirstChild
            and character:FindFirstChild("HumanoidRootPart")
        return root and root.Position or target and target.position
    end

    local function selectDualModeBladeTarget(fighter, item)
        local entity = fighter and fighter.Entity
        local localRoot = entity and entity.RootPart
        local comboRange = WeaponPolicy.gunbladeDashRange(item)
        if not localRoot or type(comboRange) ~= "number" then
            return nil
        end

        local candidates = table.clone(observations)
        local gunbladeRaycast = context.gunbladeRaycast
        if not gunbladeRaycast and RaycastParams and type(RaycastParams.new) == "function" then
            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.IgnoreWater = true
            local excluded = effects:smokeRaycastIgnore()
            if LocalPlayer.Character then
                table.insert(excluded, LocalPlayer.Character)
            end
            raycastParams.FilterDescendantsInstances = excluded
            gunbladeRaycast = function(raycastOrigin, displacement)
                return Workspace:Raycast(raycastOrigin, displacement, raycastParams)
            end
        end
        if type(Players.GetPlayers) == "function" then
            for _, player in ipairs(Players:GetPlayers()) do
                local character = player.Character
                local position = targetRootPosition({ character = character })
                local result = position
                    and gunbladeRaycast
                    and gunbladeRaycast(localRoot.Position, position - localRoot.Position)
                local instance = result and result.Instance
                local clear = not instance
                    or instance.IsDescendantOf and instance:IsDescendantOf(character)
                if position and clear and isTargetable(player, character) then
                    table.insert(candidates, {
                        character = character,
                        player = player,
                        position = position,
                        visible = true,
                    })
                end
            end
        end
        return Targeting.closestObservation(candidates, localRoot.Position, {
            isEligible = isTargetable,
            maxDistance = comboRange,
            resolvePosition = targetRootPosition,
        })
    end

    local function headAimOptions()
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local origin = cameraFrame and cameraFrame.Position
        if not origin then
            return nil
        end
        if context.headRaycast then
            return {
                origin = origin,
                raycast = context.headRaycast,
            }
        end
        if not RaycastParams or type(RaycastParams.new) ~= "function" then
            return { origin = origin }
        end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = true
        local excluded = effects:smokeRaycastIgnore()
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        raycastParams.FilterDescendantsInstances = excluded
        return {
            origin = origin,
            raycast = function(raycastOrigin, displacement)
                return Workspace:Raycast(raycastOrigin, displacement, raycastParams)
            end,
        }
    end

    local function updatePreferredHead(target, result, options)
        result.preferHead = true
        local position, head = Targeting.visibleHeadPoint(
            target,
            options and options.origin,
            options and options.raycast
        )
        if position then
            result.part = head
            result.position = position
        else
            result.part = target.part
            result.position = target.position
        end
        return result
    end

    local function plannedAimTarget(target, item, rateOverrides)
        local now = clock()
        local settings = store:Get().settings
        local headshotRate = rateOverrides and rateOverrides.headshotRate or settings.headshotRate
        local missRate = rateOverrides and rateOverrides.missRate or settings.missRate
        local options = headAimOptions()
        if
            aimPlan
            and aimPlan.character == target.character
            and aimPlan.headshotRate == headshotRate
            and aimPlan.humanAim == settings.humanAim
            and aimPlan.item == item
            and aimPlan.missRate == missRate
            and now < aimPlan.expiresAt
        then
            local refreshed = table.clone(target)
            refreshed.intentionalMiss = aimPlan.target.intentionalMiss
            refreshed.part = aimPlan.target.part
            refreshed.preferHead = aimPlan.target.preferHead
            if refreshed.intentionalMiss then
                local character = target.character
                local root = character
                    and character.FindFirstChild
                    and character:FindFirstChild("HumanoidRootPart")
                if root then
                    local width = root.Size and root.Size.X or 2
                    refreshed.part = root
                    refreshed.position = target.position
                        + root.CFrame.RightVector * (width * 0.5 + 2.5)
                end
            elseif refreshed.preferHead then
                updatePreferredHead(target, refreshed, options)
            else
                local bodyPosition, bodyPart = Targeting.visibleBodyPoint(
                    target,
                    options and options.origin,
                    options and options.raycast
                )
                if bodyPosition and bodyPart then
                    refreshed.part = bodyPart
                    refreshed.position = bodyPosition
                elseif refreshed.part and refreshed.part.Position then
                    refreshed.position = refreshed.part.Position
                end
            end
            return refreshed
        end

        local info = item and item.Info
        local cooldown = type(info) == "table"
                and (info.ShootCooldown or info.AttackCooldown or info.ChargeReleaseCooldown)
            or TRIGGER_INTERVAL
        local aimSettings = settings
        if rateOverrides then
            aimSettings = table.clone(settings)
            aimSettings.headshotRate = headshotRate
            aimSettings.missRate = missRate
        end
        local planned = Targeting.applyAimRates(target, aimSettings, random, options)
        aimPlan = {
            character = target.character,
            expiresAt = now + math.max(TRIGGER_INTERVAL, cooldown or TRIGGER_INTERVAL),
            headshotRate = headshotRate,
            humanAim = settings.humanAim,
            item = item,
            missRate = missRate,
            target = planned,
        }
        return planned
    end

    local solveRicochet = context.solveRicochet or ProjectileAim.solveRicochet
    local solveSplashAim = context.solveSplashAim or ProjectileAim.solveSplashAim
    local solveBouncingProjectile = context.solveBouncingProjectile
        or ProjectileAim.solveBouncingProjectile

    local observationRuntime = ObservationRuntime.new({
        effects = effects,
        equippedWeapon = equippedWeapon,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        getPlayerTone = playerTone,
        isOpponent = isOpponent,
        targeting = targeting,
        workspace = Workspace,
    })

    local function setAimRotation(rotation, instant, character, maximumHumanSmoothness)
        local applied = rotation
        local function commitCameraFrame(committedRotation)
            local camera = Workspace.CurrentCamera
            if not camera then
                return
            end

            -- SetRotation can be ignored while the native subject is frozen (for
            -- example while a modal menu is open).  This adapter owns the final
            -- task-combat render step, so also commit the requested orientation
            -- directly while preserving the native camera position.
            TaskCamera.commit(camera, committedRotation)
        end
        if instant then
            CameraController:SetRotation(rotation)
            commitCameraFrame(rotation)
            return true
        end
        local settings = store:Get().settings
        local smoothness = settings.aimSmoothness
        if settings.humanAim then
            smoothness = math.max(smoothness, 55)
            if maximumHumanSmoothness then
                smoothness = math.min(smoothness, maximumHumanSmoothness)
            end
            if humanAimCharacter ~= character then
                humanAimCharacter = character
                humanAimState = {
                    curveSign = random() < 0.5 and -1 or 1,
                }
            end
            applied = Targeting.humanRotation(
                CameraController.Rotation,
                rotation,
                smoothness,
                renderDelta,
                humanAimState
            )
        else
            humanAimCharacter = nil
            humanAimState = nil
            applied = Targeting.smoothRotation(
                CameraController.Rotation,
                rotation,
                smoothness,
                renderDelta
            )
        end
        CameraController:SetRotation(applied)
        commitCameraFrame(applied)
        local pitchError = math.abs(rotation.X - applied.X)
        local yawError = math.abs((rotation.Y - applied.Y + math.pi) % (math.pi * 2) - math.pi)
        return math.max(pitchError, yawError) <= math.rad(0.5)
    end

    local function publishAutoCounterDebug(extra)
        local status = autoCounterRuntime:status()
        for key, value in pairs(extra or {}) do
            status[key] = value
        end
        self.autoCounterDebug = status
    end

    local function humanoidStateName(humanoid)
        if not humanoid or type(humanoid.GetState) ~= "function" then
            return nil
        end
        local succeeded, state = pcall(humanoid.GetState, humanoid)
        if not succeeded or state == nil then
            return nil
        end
        local nameSucceeded, name = pcall(function()
            return state.Name
        end)
        if nameSucceeded and type(name) == "string" then
            return name
        end
        return tostring(state):match("([^%.]+)$")
    end

    local function updateAutoCounterDetector(settings)
        local roundEligible = localFighterIsInRound()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local root = entity and (entity.RootPart or entity.HumanoidRootPart)
        local humanoid = entity and entity.Humanoid
        autoCounterRuntime:update({
            alive = humanoid ~= nil and humanoid.Health > 0,
            enabled = settings.autoCounter == true,
            epoch = entity,
            humanoidState = humanoidStateName(humanoid),
            now = clock(),
            position = root and root.Position,
            roundEligible = roundEligible,
        })
        publishAutoCounterDebug()
    end

    local function runAutoCounter(settings)
        return AutoCounter.fire(settings, {
            runtime = autoCounterRuntime,
            inFlight = autoCounterInFlight,
            inputCaptured = context.isInputCaptured(),
            fighterActive = localFighterIsActive(),
            inRound = localFighterIsInRound(),
            getFighter = function()
                return FighterController.LocalFighter
            end,
            selectTarget = selectTarget,
            camera = Workspace.CurrentCamera,
            headAimOptions = headAimOptions,
            isTargetable = isTargetable,
            targeting = Targeting,
            weaponPolicy = WeaponPolicy,
            itemClock = itemClock,
            isDeflecting = isDeflecting,
            localFighterIsCrouching = localFighterIsCrouching,
            cameraController = CameraController,
            releaseTrigger = function()
                releaseFire()
                if trigger.held then
                    finishAiming()
                    trigger.held = false
                    trigger.heldItem = nil
                end
            end,
            clearAimPlan = function()
                aimPlan = nil
            end,
            setInFlight = function(value)
                autoCounterInFlight = value
            end,
            setAimRotation = setAimRotation,
            interval = TRIGGER_INTERVAL,
            clock = clock,
            click = startShooting,
            commitCamera = TaskCamera.commit,
            publishDebug = publishAutoCounterDebug,
        })
    end

    local function stopAutoCounter(reason)
        autoCounterRuntime:disable(reason or "disabled")
        autoCounterInFlight = false
        publishAutoCounterDebug()
    end

    local cameraAim = CameraAim.new({
        targeting = Targeting,
        projectileAim = ProjectileAim,
        weaponPolicy = WeaponPolicy,
    })
    local function alignCamera(shotOnly, taskCombatActive)
        return cameraAim:align({
            shotOnly = shotOnly,
            taskCombatActive = taskCombatActive,
            settings = store:Get().settings,
            inputCaptured = context.isInputCaptured(),
            fighterActive = taskCombatActive == true and localFighterIsTaskActive()
                or localFighterIsActive(),
            inCombat = localFighterIsInCombat(),
            fighter = FighterController.LocalFighter,
            camera = Workspace.CurrentCamera,
            clock = clock,
            renderDelta = renderDelta,
            gravity = Workspace.Gravity,
            getNetworkPing = getNetworkPing,
            environmentRaycast = environmentRaycast,
            solveBouncingProjectile = solveBouncingProjectile,
            solveSplashAim = solveSplashAim,
            solveRicochet = solveRicochet,
            setAimRotation = setAimRotation,
            selectTarget = selectTarget,
            selectBackstabTarget = selectBackstabTarget,
            taskNavigationObservation = taskNavigationObservation,
            plannedAimTarget = plannedAimTarget,
            taskSkillRuntime = taskSkillRuntime,
            taskDebug = self.taskDebug,
            clearRetention = function(clearPlan)
                aimTargetKey = nil
                aimTargetWeapon = nil
                if clearPlan then
                    aimPlan = nil
                end
            end,
            rememberWeapon = function(item)
                if aimTargetWeapon ~= item then
                    aimTargetKey = nil
                    aimTargetWeapon = item
                end
            end,
            rememberTarget = function(target)
                aimTargetKey = target.character or target.player or target.part
            end,
            clearTargetKey = function()
                aimTargetKey = nil
            end,
        })
    end

    local hookRuntime = HookRuntime.new({
        capabilities = context.capabilities,
        hookFunction = context.hookFunction,
        restoreFunction = context.restoreFunction,
        skipBlocks = {
            getFighter = function()
                return FighterController.LocalFighter
            end,
            hookFunction = context.hookFunction,
            isEnabled = function()
                return not stopped and store:Get().settings.skipDeflect == true
            end,
            restoreFunction = context.restoreFunction,
            shouldBlock = function(item)
                local settings = store:Get().settings
                local target = settings.shotAim == true and session.presented or session.aligned
                if not target and settings.shotAim ~= true then
                    target = selectTarget(nil, true, true)
                end
                return SkipBlocks.shouldBlock(item, target, {
                    isDeflecting = isDeflecting,
                    fighterFor = fighterFor,
                    taskCounterPolicy = TaskCounterPolicy,
                })
            end,
        },
        scopedAccuracy = {
            getFighter = function()
                return FighterController.LocalFighter
            end,
            hookFunction = context.hookFunction,
            isEnabled = function()
                return not stopped and store:Get().settings.alwaysScoped == true
            end,
            restoreFunction = context.restoreFunction,
        },
        shotPresentation = {
            cameraController = CameraController,
            getFighter = function()
                return FighterController.LocalFighter
            end,
            hookFunction = context.hookFunction,
            isEnabled = function()
                return not stopped and store:Get().settings.shotAim == true
            end,
            isInputCaptured = context.isInputCaptured,
            restoreFunction = context.restoreFunction,
            runService = RunService,
            workspace = Workspace,
        },
    })
    local shotPresentation = hookRuntime.presentation

    local function refreshHooks()
        hookRuntime:refresh()
    end

    local function triggerContext(alignedTarget, taskCombatActive)
        return {
            alignedTarget = alignedTarget,
            taskCombatActive = taskCombatActive,
            inputCaptured = context.isInputCaptured(),
            fighterActive = taskCombatActive == true and localFighterIsTaskActive()
                or localFighterIsActive(),
            inCombat = localFighterIsInCombat(),
            state = trigger,
            taskDebug = self.taskDebug,
            weaponPolicy = WeaponPolicy,
            projectileAim = ProjectileAim,
            targeting = Targeting,
            taskCounterPolicy = TaskCounterPolicy,
            interval = TRIGGER_INTERVAL,
            radius = TRIGGER_RADIUS,
            clock = clock,
            itemClock = itemClock,
            getFighter = function()
                return FighterController.LocalFighter
            end,
            selectDualModeBladeTarget = selectDualModeBladeTarget,
            selectTarget = selectTarget,
            selectCrosshairTarget = selectCrosshairTarget,
            isDeflecting = isDeflecting,
            isGunGame = isGunGame,
            localFighterIsCrouching = localFighterIsCrouching,
            fighterFor = fighterFor,
            targetRootPosition = targetRootPosition,
            releaseFire = releaseFire,
            clearAimPlan = function()
                aimPlan = nil
            end,
            camera = Workspace.CurrentCamera,
            cameraController = CameraController,
            gravity = Workspace.Gravity,
            raycast = type(environmentRaycast) == "function" and environmentRaycast() or nil,
            click = startShooting,
            aimClick = startAiming,
            aimPress = function()
                return combatInput:pressAim()
            end,
            aimRelease = finishAiming,
            press = function()
                return combatInput:pressFire()
            end,
        }
    end
    local function runTriggerBot(alignedTarget, taskCombatActive)
        TriggerBot.update(session, triggerContext(alignedTarget, taskCombatActive))
    end

    local function taskMovementPosition(alignedTarget)
        local position = targetRootPosition(alignedTarget)
        if typeof(position) == "Vector3" then
            return position
        end
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local localRoot = entity and (entity.RootPart or entity.HumanoidRootPart)
        if not localRoot then
            return nil
        end
        local nearestPosition
        local nearestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and isTargetable(player, character) then
                local distance = (root.Position - localRoot.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestPosition = root.Position
                end
            end
        end
        return nearestPosition
    end

    local renderConnection
    local renderBindingName = "UniversalHubRivalsFrame"
    local settingsSubscription
    local ensureTaskLoadoutPoll
    local function updateFrame(deltaTime)
        if stopped then
            return
        end
        local settings = store:Get().settings
        if redLightSafety then
            local duel = DuelController:GetDuel(LocalPlayer)
            redLightSafety:refresh(duel and duel.ChickenGame)
            if settings.redLightSafety ~= true then
                redLightSafety:setPaused(false)
            elseif redLightSafety:isPaused() then
                redLightSafety:holdStill()
                return
            end
        end
        if ensureTaskLoadoutPoll then
            ensureTaskLoadoutPoll()
        end
        local taskCombatActive = taskFarmRuntime and taskFarmRuntime:isCombatActive() == true
        if taskCombatActive ~= taskSkillWasActive then
            taskSkillRuntime:reset()
            taskSkillWasActive = taskCombatActive
        end
        if NoScope.shouldRefresh(settings) or settings.skipDeflect == true then
            refreshHooks()
        end
        if type(deltaTime) == "number" and deltaTime > 0 then
            renderDelta = deltaTime
        end

        updateAutoCounterDetector(settings)

        Pickup.update({ settings = settings }, gunGameRuntime)
        local overlayVisualsEnabled = settings.names == true
            or settings.health == true
            or settings.weapon == true
        local limnVisualsEnabled = settings.worldRenderer ~= "native"
            and (settings.boxes == true or settings.chams == true or overlayVisualsEnabled)
        local observationsEnabled = settings.silentAim == true
            or settings.shotAim == true
            or settings.triggerBot == true
            or settings.autoCounter == true
            or settings.teleportBehind == true
            or taskCombatActive
            or limnVisualsEnabled
            or overlayVisualsEnabled
        if observationsEnabled then
            observations, visualObservations = observationRuntime:update(
                UserInputService:GetMouseLocation(),
                settings.showTeammates == true,
                settings.showEnemies ~= false
            )
        elseif #observations > 0 or #visualObservations > 0 then
            observations = {}
            visualObservations = observations
        end
        local utilityObservations = {}
        local taskHazards = utilityObservations
        local fighter = FighterController.LocalFighter
        rapidFire:update(
            settings,
            fighter and fighter.EquippedItem,
            localFighterIsActive() and localFighterIsInCombat() and not context.isInputCaptured(),
            type(context.isFireHeld) == "function" and context.isFireHeld()
                or type(UserInputService.IsMouseButtonPressed) == "function"
                    and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1),
            startShooting
        )
        if
            (settings.utilityEsp == true or taskCombatActive)
            and localFighterIsInCombat()
            and Workspace.CurrentCamera
        then
            local data = fighter and fighter.Data
            local environmentID = type(data) == "table" and data.EnvironmentID
                or LocalPlayer:GetAttribute("EnvironmentID")
            taskHazards = observeThrowables(Workspace.CurrentCamera, environmentID)
            if settings.utilityEsp == true then
                utilityObservations = taskHazards
            end
        end
        if not settingsSubscription then
            effects:update(settings)
        end

        local autoCounterActed = runAutoCounter(settings)
        local alignedTarget
        local aimEnabled = not autoCounterActed
            and (settings.silentAim == true or settings.shotAim == true or taskCombatActive)
        if aimEnabled then
            alignedTarget = alignCamera(false, taskCombatActive)
            if not alignedTarget and settings.shotAim then
                alignedTarget = alignCamera(true, taskCombatActive)
            end
        end
        local taskWeaponDistance
        local taskRoot = fighter
            and fighter.Entity
            and (fighter.Entity.RootPart or fighter.Entity.HumanoidRootPart)
        local taskTargetPosition = alignedTarget and targetRootPosition(alignedTarget)
        if taskRoot and taskTargetPosition then
            taskWeaponDistance = (taskTargetPosition - taskRoot.Position).Magnitude
        end
        movement:updateInfiniteJump(settings)
        movement:updateWallNoclip(settings)
        local taskTactical
        if taskCombatActive and alignedTarget and alignedTarget.player then
            local opponentFighter = fighterFor(alignedTarget.player)
            local opponentItem = opponentFighter and opponentFighter.EquippedItem
            taskTactical = {
                pushSniper = WeaponPolicy.isScoped(opponentItem),
                avoidSniperPeek = WeaponPolicy.isScoped(opponentItem)
                    and WeaponPolicy.isAiming(opponentItem),
            }
        end
        local counterSwitching = false
        if taskCombatActive and alignedTarget and alignedTarget.player then
            local opponentFighter = fighterFor(alignedTarget.player)
            local counterActive = counterLoadoutReady(opponentFighter)
                    and taskCounterPolicy:update(opponentFighter.EquippedItem)
                or false
            if
                counterActive
                and fighter
                and fighter.EquippedItem
                and not WeaponPolicy.isTrueDamage(fighter.EquippedItem)
                and clock() >= nextCounterEquipAt
            then
                local spray
                for key, value in pairs(fighter.Items or {}) do
                    local item = type(value) == "table" and value
                        or type(key) == "table" and key
                        or nil
                    if
                        item
                        and WeaponPolicy.isTrueDamage(item)
                        and (WeaponPolicy.ammo(item) or 0) > 0
                    then
                        spray = item
                        break
                    end
                end
                if spray then
                    releaseFire()
                    if taskWeaponSwap.equip(fighter, spray) then
                        nextCounterEquipAt = clock() + 0.75
                        counterSwitching = true
                        self.taskDebug.counterWeapon = WeaponPolicy.itemName(spray) or "Spray"
                    end
                end
            end
        end
        local taskWeaponSwapping = counterSwitching
            or taskWeaponSwap:update(taskCombatActive, fighter, alignedTarget, taskWeaponDistance)
        if taskWeaponSwapping then
            alignedTarget = nil
        end
        session.settings = settings
        session.aligned = alignedTarget
        session.active = taskCombatActive == true and localFighterIsTaskActive()
            or localFighterIsActive()
        session.inCombat = localFighterIsInCombat()
        session.inRound = localFighterIsInRound()
        session.inputCaptured = context.isInputCaptured()
        session.taskCombat = taskCombatActive == true
        if settings.teleportBehind == true then
            local libs = teleportLibs()
            libs.selectTarget = function()
                return selectTarget(nil, true, true)
            end
            TeleportBehind.update(session, libs)
            startTeleportPhysics()
            local lookTarget = session.presented or alignedTarget
            local movedRoot = localFighterRoot()
            local lookPoint = movedRoot and TeleportBehind.aimPoint(movedRoot.Position, lookTarget)
            if movedRoot and typeof(lookPoint) == "Vector3" then
                setAimRotation(
                    Targeting.rotationToward(movedRoot.Position, lookPoint),
                    true,
                    lookTarget and lookTarget.character
                )
                session.cameraOrigin = movedRoot.Position
                if alignedTarget then
                    alignedTarget.position = lookPoint
                    alignedTarget.aimSettled = true
                    session.aligned = alignedTarget
                end
            end
        elseif settingsSubscription then
            stopTeleportPhysics()
        end
        if alignedTarget and limnVisualsEnabled then
            local _, refreshedVisuals = observationRuntime:update(
                UserInputService:GetMouseLocation(),
                settings.showTeammates == true,
                settings.showEnemies ~= false
            )
            visualObservations = refreshedVisuals
        end
        context.render(visualObservations, UserInputService:GetMouseLocation(), utilityObservations)
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local movedRoot = localFighterRoot()
        session.cameraOrigin = cameraFrame and cameraFrame.Position
            or movedRoot and movedRoot.Position
            or nil
        if session.teleportEngaged == true and movedRoot then
            session.cameraOrigin = movedRoot.Position
        end
        if settings.shotAim == true or not settingsSubscription then
            SilentAim.update(session, shotPresentation, {
                targeting = Targeting,
                maxDistance = ProjectileAim.MAX_DISTANCE,
            })
        end
        local triggerTarget = alignedTarget
        if settings.shotAim == true then
            triggerTarget = session.presented
        end
        if taskCombatActive then
            local movementTarget = taskMovementPosition(alignedTarget)
            local locomotionPlan
            if taskRoot and typeof(movementTarget) == "Vector3" then
                local routeClear = true
                if type(environmentRaycast) == "function" then
                    local cast = environmentRaycast()
                    local offset = movementTarget - taskRoot.Position
                    if type(cast) == "function" and offset.Magnitude > 1 then
                        routeClear = cast(
                            taskRoot.Position,
                            offset.Unit * math.min(offset.Magnitude, 6)
                        ) == nil
                    end
                end
                locomotionPlan = taskLocomotion:plan({
                    clear = routeClear,
                    grounded = localFighterIsTaskActive(),
                    now = clock(),
                    position = taskRoot.Position,
                    targetPosition = movementTarget,
                })
            end
            movement:updateTaskCombat(movementTarget, taskHazards, taskTactical, locomotionPlan)
            self.taskDebug.parkour = movement.taskParkourCommit and "committed" or "grounded-route"
        else
            movement:stopTaskCombat()
        end
        if settings.bhop == true then
            suppressBhopJump = WeaponPolicy.isBackstabKnife(fighter and fighter.EquippedItem)
                and alignedTarget ~= nil
                and alignedTarget.knifePath ~= nil
            movement:update(settings)
        elseif not settingsSubscription then
            suppressBhopJump = false
            movement:stop()
        end
        if aimEnabled then
            local trajectory = alignedTarget
                and (
                    (alignedTarget.ricochet and alignedTarget.ricochet.path)
                    or (alignedTarget.slingshot and alignedTarget.slingshot.path)
                    or alignedTarget.knifePath
                )
            effects:renderTrajectory(trajectory)
        elseif not settingsSubscription then
            effects:renderTrajectory(nil)
        end
        local targetDeflecting = settings.skipDeflect == true
                and triggerTarget
                and triggerTarget.player
                and isDeflecting(triggerTarget.player)
            or false
        combatInput:setDeflecting(targetDeflecting)
        if settings.skipDeflect == true then
            local equipped = fighter and fighter.EquippedItem
            SkipBlocks.update(equipped, triggerTarget, {
                isDeflecting = isDeflecting,
                fighterFor = fighterFor,
                taskCounterPolicy = TaskCounterPolicy,
                fireHeld = trigger.fireHeld,
                releaseFire = function()
                    finishShooting()
                    trigger.fireHeld = false
                    trigger.fireItem = nil
                end,
            })
        end
        local autoDeflectActed = false
        if settings.autoDeflect == true then
            local entity = fighter and fighter.Entity
            local humanoid = entity and entity.Humanoid
            local ours = entity and entity.Character or LocalPlayer.Character
            local opponents = {}
            local map = FighterController._player_to_fighter
            if type(map) == "table" then
                for player, opponentFighter in pairs(map) do
                    local character = player and player.Character
                    if
                        player ~= LocalPlayer
                        and opponentFighter
                        and character
                        and isTargetable(player, character)
                    then
                        opponents[#opponents + 1] = {
                            player = player,
                            character = character,
                            EquippedItem = opponentFighter.EquippedItem,
                        }
                    end
                end
            end
            autoDeflectActed = AutoDeflect.update(settings, {
                inputCaptured = context.isInputCaptured(),
                fighterActive = localFighterIsActive(),
                inCombat = localFighterIsInCombat(),
                getFighter = function()
                    return FighterController.LocalFighter
                end,
                weaponPolicy = WeaponPolicy,
                itemClock = itemClock,
                health = humanoid and humanoid.Health,
                character = ours,
                opponents = opponents,
                hasLine = function(origin, point, opponentCharacter)
                    local cast = type(environmentRaycast) == "function" and environmentRaycast()
                    if
                        type(cast) ~= "function"
                        or typeof(origin) ~= "Vector3"
                        or typeof(point) ~= "Vector3"
                    then
                        return true
                    end
                    local delta = point - origin
                    local distance = delta.Magnitude
                    if distance < 1 then
                        return true
                    end
                    local result = cast(origin, delta.Unit, distance)
                    if not result or not result.Instance then
                        return true
                    end
                    if ours and result.Instance:IsDescendantOf(ours) then
                        return true
                    end
                    if opponentCharacter and result.Instance:IsDescendantOf(opponentCharacter) then
                        return true
                    end
                    return false
                end,
                aimClick = startAiming,
                taskDebug = self.taskDebug,
            })
        end
        if
            not autoCounterActed
            and not autoDeflectActed
            and (
                settings.triggerBot == true
                or taskCombatActive
                or trigger.held
                or trigger.fireHeld
                or not settingsSubscription
            )
        then
            runTriggerBot(triggerTarget, taskCombatActive)
        end
    end

    local reconcileFrameLifecycle
    local reconcileTaskEmergency
    local function taskStatusChanged(status)
        if reconcileTaskEmergency then
            reconcileTaskEmergency(status)
        end
    end
    local function taskActivityChanged(_, status)
        taskStatusChanged(status)
        if reconcileFrameLifecycle then
            reconcileFrameLifecycle(store:Get())
        end
    end
    local practiceTaskDriver = context.practiceTaskDriver
    if practiceTaskDriver == nil and context.taskFarmRuntime == nil then
        practiceTaskDriver = PracticeTaskDriver.new({
            getFighter = function()
                return FighterController.LocalFighter
            end,
            actions = {
                enterRange = function()
                    local result = ShootingRangeController:Enter()
                    return result ~= false
                end,
                slide = function()
                    local fighter = FighterController.LocalFighter
                    if
                        not fighter
                        or type(fighter.CanSlide) ~= "function"
                        or fighter:CanSlide() ~= true
                    then
                        return false
                    end
                    MechanicsController:Slide()
                    return true
                end,
                equip = function(name)
                    local fighter = FighterController.LocalFighter
                    if
                        not fighter
                        or type(fighter.GetItem) ~= "function"
                        or type(fighter.EquipItem) ~= "function"
                    then
                        return false
                    end
                    local item = fighter:GetItem(name)
                    if not item then
                        return false
                    end
                    local result = fighter:EquipItem(item)
                    return result ~= false
                end,
                secondary = function()
                    startAiming()
                    return true
                end,
                primary = function()
                    startShooting()
                    return true
                end,
                releaseAll = function()
                    if trigger.held then
                        finishAiming()
                        trigger.held = false
                    end
                    releaseFire()
                end,
            },
        })
    end
    taskFarmRuntime = context.taskFarmRuntime
        or TaskFarmRuntime.new({
            constants = RivalsConstants,
            duelController = DuelController,
            fighterController = FighterController,
            localPlayer = LocalPlayer,
            matchmakingController = MatchmakingController,
            playerDataController = PlayerDataController,
            practiceDriver = practiceTaskDriver,
            taskLibrary = TaskLibrary,
            paused = store:Get().settings.taskAutomationPaused == true,
            onActivityChanged = taskActivityChanged,
            onStatusChanged = taskStatusChanged,
            onManualDuel = function()
                local state = store:Get()
                if state.settings.taskAutomationPaused == true then
                    return
                end
                local settings = table.clone(state.settings)
                settings.taskAutomationPaused = true
                store:Patch({ settings = settings })
                if type(context.settingsChanged) == "function" then
                    context.settingsChanged(settings)
                end
            end,
        })
    if type(taskFarmRuntime.setActivityChanged) == "function" then
        taskFarmRuntime:setActivityChanged(taskActivityChanged)
    end
    if type(taskFarmRuntime.setStatusChanged) == "function" then
        taskFarmRuntime:setStatusChanged(taskStatusChanged)
    end
    local function currentTaskStatus()
        if type(taskFarmRuntime.status) == "function" then
            return taskFarmRuntime:status()
        end
        return { state = "idle", paused = false, task = nil }
    end
    taskStatusChanged(currentTaskStatus())
    self.taskFarmRuntime = taskFarmRuntime

    local loadoutOpenConnection
    local loadoutVisibleConnection
    local taskLoadout = TaskLoadout.new({
        clock = clock,
        constants = RivalsConstants,
        getOpponentFighter = taskOpponentFighter,
        getStatus = currentTaskStatus,
        page = PickWeaponsPage,
        taskCounterPolicy = TaskCounterPolicy,
        taskDebug = self.taskDebug,
        taskPolicy = TaskPolicy,
    })
    local function stopLoadoutPoll()
        taskLoadout:stop()
    end
    ensureTaskLoadoutPoll = function()
        taskLoadout:poll()
    end

    reconcileTaskEmergency = function(status)
        status = status or currentTaskStatus()
        local armed = status.task ~= nil
            and status.paused ~= true
            and status.state ~= "idle"
            and status.state ~= "stopped"
        if not armed then
            if taskEmergencyConnection then
                taskEmergencyConnection:Disconnect()
                taskEmergencyConnection = nil
            end
            return
        end
        if taskEmergencyConnection then
            return
        end
        taskEmergencyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then
                return
            end
            local keyCode = input and input.KeyCode
            local pressedName = keyCode and keyCode.Name
            local currentState = store:Get()
            local settings = currentState.settings or {}
            if pressedName ~= (settings.taskAutomationEmergencyKey or "End") then
                return
            end
            local updated = table.clone(settings)
            updated.taskAutomationPaused = true
            store:Patch({ settings = updated })
            if type(context.settingsChanged) == "function" then
                context.settingsChanged(updated)
            end
        end)
    end
    reconcileTaskEmergency(currentTaskStatus())

    local function frameWorkEnabled(state)
        local settings = state.settings or {}
        local playerVisuals = settings.boxes == true
            or settings.chams == true
            or settings.names == true
            or settings.health == true
            or settings.weapon == true
        local playerFrame = playerVisuals
            and (settings.worldRenderer ~= "native" or state.menuVisible ~= false)
        return taskFarmRuntime:isCombatActive() == true
            or PickWeaponsPage:IsOpen()
            or settings.silentAim == true
            or settings.shotAim == true
            or settings.triggerBot == true
            or settings.autoCounter == true
            or settings.alwaysScoped == true
            or settings.bhop == true
            or settings.infiniteJump == true
            or settings.wallNoclip == true
            or settings.teleportBehind == true
            or settings.autoPickup == true
            or settings.utilityEsp == true
            or settings.fovCircle == true
            or playerFrame
    end

    local function connectFrame()
        if renderConnection then
            return
        end
        if
            context.requireModule == nil
            and type(RunService.BindToRenderStep) == "function"
            and type(RunService.UnbindFromRenderStep) == "function"
        then
            local priority = Enum.RenderPriority.Last.Value
            RunService:BindToRenderStep(renderBindingName, priority, updateFrame)
            renderConnection = {
                Disconnect = function()
                    RunService:UnbindFromRenderStep(renderBindingName)
                end,
            }
        else
            renderConnection = RunService.RenderStepped:Connect(updateFrame)
        end
    end

    local function disconnectFrame()
        if renderConnection then
            renderConnection:Disconnect()
            renderConnection = nil
        end
    end

    reconcileFrameLifecycle = function(state)
        if stopped then
            return
        end
        local settings = state.settings or {}
        local pausedSetting = settings.taskAutomationPaused == true
        if pausedSetting ~= lastTaskPauseSetting then
            local wasPaused = lastTaskPauseSetting
            lastTaskPauseSetting = pausedSetting
            if type(context.settingsChanged) == "function" then
                context.settingsChanged(settings)
            end
            -- Starting the farm closes the hub once. Subsequent manual menu
            -- opens are respected while farming remains active.
            if wasPaused and not pausedSetting and state.menuVisible ~= false then
                store:Patch({ menuVisible = false })
                return
            end
        end
        if type(taskFarmRuntime.status) == "function" then
            local taskStatus = taskFarmRuntime:status()
            if settings.taskAutomationPaused == true and not taskStatus.paused then
                taskFarmRuntime:pause("user")
            elseif settings.taskAutomationPaused ~= true and taskStatus.paused then
                taskFarmRuntime:resume()
            end
        end
        effects:update(settings)
        refreshHooks()
        if settings.autoCounter ~= true then
            stopAutoCounter("disabled")
        end
        if frameWorkEnabled(state) then
            connectFrame()
            return
        end
        disconnectFrame()
        stopTeleportPhysics()
        context.render({}, UserInputService:GetMouseLocation(), {})
        movement:stop()
        movement:stopWallNoclip()
        effects:renderTrajectory(nil)
        shotPresentation:clear()
        runTriggerBot(nil, false)
    end

    local function loadoutVisibilityChanged()
        if stopped then
            return
        end
        if PickWeaponsPage:IsOpen() then
            if ensureTaskLoadoutPoll then
                ensureTaskLoadoutPoll()
            end
        elseif taskLoadout.wasOpen then
            stopLoadoutPoll()
            self.taskDebug.loadoutStage = "closed"
        end
        reconcileFrameLifecycle(store:Get())
    end
    if PickWeaponsPage.OpenChanged and type(PickWeaponsPage.OpenChanged.Connect) == "function" then
        loadoutOpenConnection = PickWeaponsPage.OpenChanged:Connect(loadoutVisibilityChanged)
    end
    if
        PickWeaponsPage.PageFrame
        and type(PickWeaponsPage.PageFrame.GetPropertyChangedSignal) == "function"
    then
        loadoutVisibleConnection = PickWeaponsPage.PageFrame
            :GetPropertyChangedSignal("Visible")
            :Connect(loadoutVisibilityChanged)
    end

    if type(store.Subscribe) == "function" then
        settingsSubscription = store:Subscribe(reconcileFrameLifecycle)
        reconcileFrameLifecycle(store:Get())
    else
        connectFrame()
    end

    function self.stop()
        if stopped then
            return
        end
        stopped = true
        if redLightSafety then
            redLightSafety:stop()
        end
        if taskEmergencyConnection then
            taskEmergencyConnection:Disconnect()
            taskEmergencyConnection = nil
        end
        stopLoadoutPoll()
        if loadoutOpenConnection then
            loadoutOpenConnection:Disconnect()
            loadoutOpenConnection = nil
        end
        if loadoutVisibleConnection then
            loadoutVisibleConnection:Disconnect()
            loadoutVisibleConnection = nil
        end
        taskFarmRuntime:stop()
        gunGameRuntime:stop()
        hookRuntime:stop()
        autoCounterRuntime:stop()
        if trigger.held then
            finishAiming()
            trigger.held = false
        end
        releaseFire()
        rapidFire:stop()
        movement:stop()
        movement:stopWallNoclip()
        effects:stop()
        if settingsSubscription then
            settingsSubscription()
            settingsSubscription = nil
        end
        stopTeleportPhysics()
        disconnectFrame()
    end

    self.capabilities = context.capabilities or {}
    self.autoCounterRuntime = autoCounterRuntime
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget
    self.worldPolicy = WorldPolicy.new({
        getLocalFighter = function()
            return FighterController.LocalFighter
        end,
        getWeapon = equippedWeapon,
        getFighter = fighterFor,
        isOpponent = isOpponent,
        getPlayerTone = playerTone,
        localPlayer = LocalPlayer,
        workspace = Workspace,
    })

    return self
end

return Rivals
]],
        ["games/rivals/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            views = {
                { id = "preview", label = "Preview" },
                { id = "colors", label = "ESP Colors" },
            },
            preview = { kind = "character" },
        })
    end
    host:aim()
    host:rate("aimSmoothness", "Aim Smoothness")
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:segmented("Visuals", {
        id = "worldRenderer",
        sectionLabel = "ESP",
        label = "Style",
        treatment = "style",
        options = {
            {
                label = "Classic",
                value = "limn",
                when = { worldRenderer = "limn" },
                patch = { { "worldRenderer", "limn" } },
            },
            {
                label = "Highlights",
                value = "native",
                when = { worldRenderer = "native" },
                patch = { { "worldRenderer", "native" } },
            },
        },
    })

    host:segmented("Combat", {
        id = "aimMode",
        label = "Aim Type",
        emphasis = "prominent",
        related = {
            { id = "humanAim", kind = "toggle", label = "Human Aim", when = "camera" },
        },
        options = {
            {
                label = "Off",
                value = "off",
                when = { silentAim = false, shotAim = false },
                patch = { { "silentAim", false }, { "shotAim", false } },
            },
            {
                label = "Camera",
                value = "camera",
                when = { silentAim = true, shotAim = false },
                patch = { { "shotAim", false }, { "silentAim", true } },
            },
            {
                label = "Silent",
                value = "silent",
                when = { shotAim = true },
                patch = { { "silentAim", false }, { "shotAim", true } },
            },
        },
    })

    host:section("Combat", "trigger", "Trigger Bot", 64)
    host:option("trigger", 1, "triggerBot", "Trigger Bot")
    if type(host.slider) == "function" then
        host:slider("trigger", "triggerDelay", "Delay", {
            min = 0,
            max = 250,
            step = 1,
            unit = "ms",
            parent = "triggerBot",
        })
    end
    host:option("trigger", 2, "rapidFire", "Rapid Fire")
    if type(host.slider) == "function" then
        host:slider("trigger", "fireRate", "Fire Rate", {
            min = 100,
            max = 300,
            step = 5,
            unit = "%",
            parent = "rapidFire",
        })
    end
    host:option("trigger", 3, "skipDeflect", "Katana Stop")
    host:option("trigger", 3, "autoDeflect", "Auto Katana")
    host:option("trigger", 4, "alwaysScoped", "Always Scoped")

    host:section("Rage", "rage", "RAGE", 70)
    host:option("rage", 1, "teleportBehind", "Warp")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "bhop", "Bunny Hop")
    host:option("movement", 2, "infiniteJump", "Infinite Jump")
    host:option("movement", 3, "wallNoclip", "Wall Noclip")
    host:option("movement", 4, "redLightSafety", "Red Light Safety")

    host:section("Settings", "taskFarming", "TASK FARMING", 70)
    host:option("taskFarming", 1, "taskAutomationPaused", "Pause Task Farming")
    if type(host.keybind) == "function" then
        host:keybind("taskFarming", "taskAutomationEmergencyKey", "Emergency stop", "End")
    end

    host:section("Tools", "world", "WORLD", 70)
    host:option("world", 1, "autoPickup", "Auto Pickup")

    host:section("Visuals", "visuals", "VISUALS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "chamsExcludeAccessories", "Ignore Accessories", "chams", {
        setting = "worldRenderer",
        equals = "native",
    })
    host:option("visuals", 2, "chamsPerPart", "Part Highlights", "chams", {
        setting = "worldRenderer",
        equals = "native",
    })
    host:option("visuals", 3, "names", "Names")
    host:option("visuals", 3, "health", "Health")
    host:option("visuals", 4, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
    host:option("visuals", 4, "noFlash", "No Flash")
    host:option("visuals", 5, "noSmoke", "No Smoke")
    host:option("visuals", 6, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
]],
        ["games/rivals/Session.lua"] = [[local Session = {}

function Session.new()
    return {
        clock = 0,
        settings = {},
        localFighter = nil,
        item = nil,
        active = false,
        inCombat = false,
        inRound = false,
        inputCaptured = false,
        taskCombat = false,
        mouse = nil,
        cameraOrigin = nil,
        observations = {},
        utilities = {},
        aligned = nil,
        presented = nil,
    }
end

return Session
]],
        ["games/rivals/features/AutoCounter.lua"] = [[local AutoCounter = {}

function AutoCounter.weaponReady(item, target, distance, ctx)
    local info = item and item.Info
    local data = item and item.Data
    local now = ctx.itemClock()
    local WeaponPolicy = ctx.weaponPolicy
    return type(item) == "table"
        and type(info) == "table"
        and type(info.ShootDamage) == "number"
        and WeaponPolicy.automationPolicy(item).triggerBot == true
        and (WeaponPolicy.ammo(item) or 0) > 0
        and item.IsEquipping ~= true
        and not (type(data) == "table" and (data.IsReloading == true or data.Reloading == true))
        and not (type(item._shoot_cooldown) == "number" and now < item._shoot_cooldown)
        and not ctx.isDeflecting(target.player)
        and WeaponPolicy.triggerDamageReady(item, target, distance)
        and WeaponPolicy.sniperTriggerReady(
            ctx.cameraController,
            item,
            target,
            distance,
            ctx.localFighterIsCrouching(ctx.getFighter()),
            false
        )
end

function AutoCounter.fire(settings, ctx)
    if
        settings.autoCounter ~= true
        or not ctx.runtime:isReady()
        or ctx.inFlight
        or ctx.inputCaptured
        or not ctx.fighterActive
        or not ctx.inRound
    then
        return false
    end

    local fighter = ctx.getFighter()
    local item = fighter and fighter.EquippedItem
    local target = ctx.selectTarget(nil, false, true)
    local camera = ctx.camera
    local aimOptions = camera and ctx.headAimOptions() or nil
    if
        not target
        or target.visible ~= true
        or not ctx.isTargetable(target.player, target.character)
        or not camera
        or not aimOptions
    then
        return false
    end

    local bodyPosition, bodyPart =
        ctx.targeting.visibleBodyPoint(target, aimOptions.origin, aimOptions.raycast)
    if not bodyPosition or not bodyPart then
        return false
    end
    local bodyTarget = table.clone(target)
    bodyTarget.part = bodyPart
    bodyTarget.position = bodyPosition
    local distance = (bodyPosition - aimOptions.origin).Magnitude
    if not AutoCounter.weaponReady(item, bodyTarget, distance, ctx) then
        return false
    end

    ctx.releaseTrigger()
    ctx.clearAimPlan()
    ctx.setInFlight(true)
    local originalRotation = ctx.cameraController.Rotation
    local rotation = ctx.targeting.rotationToward(aimOptions.origin, bodyPosition)
    ctx.setAimRotation(rotation, true, target.character)
    local info = item.Info
    local cooldown =
        math.max(ctx.interval, info.ShootCooldown or info.AttackCooldown or ctx.interval)
    ctx.runtime:consume(ctx.clock(), cooldown)
    local succeeded, actionError = pcall(ctx.click)
    if typeof(originalRotation) == "Vector2" then
        ctx.cameraController:SetRotation(originalRotation)
        ctx.commitCamera(camera, originalRotation)
    end
    ctx.setInFlight(false)
    ctx.publishDebug({
        actionAt = ctx.clock(),
        actionError = succeeded and nil or tostring(actionError),
        targetUserId = target.player and target.player.UserId or nil,
    })
    return true
end

return AutoCounter
]],
        ["games/rivals/features/AutoCounterRuntime.lua"] = [[local AutoCounterRuntime = {}
AutoCounterRuntime.__index = AutoCounterRuntime

local function horizontalMagnitude(vector)
    return Vector3.new(vector.X, 0, vector.Z).Magnitude
end

function AutoCounterRuntime.new(options)
    options = options or {}
    return setmetatable({
        clock = options.clock or os.clock,
        confirmedAt = nil,
        cooldownUntil = 0,
        epoch = nil,
        lastReason = "idle",
        lastSampleAt = nil,
        maximumHorizontalDisplacement = options.maximumHorizontalDisplacement or 5,
        maximumSampleGap = options.maximumSampleGap or 0.25,
        outboundMaximum = options.outboundMaximum or 1001,
        outboundMinimum = options.outboundMinimum or 999,
        outboundSign = nil,
        outboundAt = nil,
        previousPosition = nil,
        readyAt = nil,
        readyWindow = options.readyWindow or 0.75,
        returnMinimum = options.returnMinimum or 900,
        returnRadius = options.returnRadius or 1,
        signatureWindow = options.signatureWindow or 1.5,
        stableSamples = 0,
        stableSamplesRequired = options.stableSamplesRequired or 3,
        startPosition = nil,
        state = "idle",
        stopped = false,
    }, AutoCounterRuntime)
end

function AutoCounterRuntime:_reset(reason)
    self.confirmedAt = nil
    self.cooldownUntil = 0
    self.epoch = nil
    self.lastReason = reason or "reset"
    self.lastSampleAt = nil
    self.outboundSign = nil
    self.outboundAt = nil
    self.previousPosition = nil
    self.readyAt = nil
    self.stableSamples = 0
    self.startPosition = nil
    self.state = "idle"
end

function AutoCounterRuntime:_baseline(sample, now, reason)
    self.confirmedAt = nil
    self.cooldownUntil = 0
    self.epoch = sample.epoch
    self.lastReason = reason or "baseline"
    self.lastSampleAt = now
    self.outboundSign = nil
    self.outboundAt = nil
    self.previousPosition = sample.position
    self.readyAt = nil
    self.stableSamples = 0
    self.startPosition = nil
    self.state = "idle"
end

function AutoCounterRuntime:status()
    return {
        confirmedAt = self.confirmedAt,
        cooldownUntil = self.cooldownUntil,
        lastReason = self.lastReason,
        outboundAt = self.outboundAt,
        readyAt = self.readyAt,
        stableSamples = self.stableSamples,
        state = self.state,
    }
end

function AutoCounterRuntime:isReady()
    return not self.stopped and self.state == "ready"
end

function AutoCounterRuntime:update(sample)
    sample = sample or {}
    local now = sample.now or self.clock()
    if self.stopped then
        return self:status()
    end
    if sample.enabled ~= true then
        self:_reset("disabled")
        return self:status()
    end
    if
        sample.roundEligible ~= true
        or sample.alive ~= true
        or sample.epoch == nil
        or typeof(sample.position) ~= "Vector3"
    then
        self:_reset("ineligible")
        return self:status()
    end

    if self.state == "cooldown" then
        if now < self.cooldownUntil then
            self.epoch = sample.epoch
            self.lastSampleAt = now
            self.previousPosition = sample.position
            return self:status()
        end
        self:_baseline(sample, now, "cooldown-complete")
        return self:status()
    end

    if self.epoch ~= sample.epoch or self.previousPosition == nil then
        self:_baseline(sample, now, "epoch-baseline")
        return self:status()
    end

    local deltaTime = now - (self.lastSampleAt or now)
    if deltaTime <= 0 or deltaTime > self.maximumSampleGap then
        self:_baseline(sample, now, "sample-gap")
        return self:status()
    end

    local delta = sample.position - self.previousPosition
    if self.state == "idle" then
        local vertical = math.abs(delta.Y)
        if
            vertical >= self.outboundMinimum
            and vertical <= self.outboundMaximum
            and horizontalMagnitude(delta) <= self.maximumHorizontalDisplacement
        then
            self.lastReason = "outbound"
            self.outboundAt = now
            self.outboundSign = delta.Y >= 0 and 1 or -1
            self.startPosition = self.previousPosition
            self.state = "outbound"
        end
    elseif self.state == "outbound" then
        if now - self.outboundAt > self.signatureWindow then
            self:_baseline(sample, now, "return-timeout")
            return self:status()
        end
        local returned = delta.Y * self.outboundSign <= -self.returnMinimum
            and (sample.position - self.startPosition).Magnitude <= self.returnRadius
        if returned then
            self.confirmedAt = now
            self.lastReason = "returned"
            self.stableSamples = 0
            self.state = "confirmed"
        end
    elseif self.state == "confirmed" then
        if now - self.confirmedAt > self.readyWindow then
            self:_baseline(sample, now, "ready-timeout")
            return self:status()
        end
        local stable = sample.humanoidState == "Running"
            and (sample.position - self.startPosition).Magnitude <= self.returnRadius
            and delta.Magnitude <= self.returnRadius
        self.stableSamples = stable and self.stableSamples + 1 or 0
        if self.stableSamples >= self.stableSamplesRequired then
            self.lastReason = "ready"
            self.readyAt = now
            self.state = "ready"
        end
    elseif self.state == "ready" and now - self.confirmedAt > self.readyWindow then
        self:_baseline(sample, now, "action-timeout")
        return self:status()
    end

    self.lastSampleAt = now
    self.previousPosition = sample.position
    return self:status()
end

function AutoCounterRuntime:consume(now, cooldown)
    if not self:isReady() then
        return false
    end
    now = now or self.clock()
    self.cooldownUntil = now + math.max(0, cooldown or 0)
    self.lastReason = "consumed"
    self.state = "cooldown"
    self.confirmedAt = nil
    self.outboundAt = nil
    self.outboundSign = nil
    self.readyAt = nil
    self.stableSamples = 0
    self.startPosition = nil
    return true
end

function AutoCounterRuntime:disable(reason)
    if self.stopped then
        return
    end
    self:_reset(reason or "disabled")
end

function AutoCounterRuntime:stop()
    if self.stopped then
        return
    end
    self:_reset("stopped")
    self.stopped = true
end

return AutoCounterRuntime
]],
        ["games/rivals/features/AutoDeflect.lua"] = [[local AutoDeflect = {}

AutoDeflect.LOOK_COSINE = math.cos(math.rad(16))

function AutoDeflect.lookFrom(character)
    local head = character and character.Head
    if not head and character and type(character.FindFirstChild) == "function" then
        head = character:FindFirstChild("Head")
    end
    local frame = head and head.CFrame
    local position = frame and frame.Position
    local look = frame and frame.LookVector
    if position == nil or look == nil then
        return nil
    end
    return position, look
end

function AutoDeflect.bodyPoint(character)
    local root = character
        and (character.HumanoidRootPart or character.RootPart or character.PrimaryPart)
    if not root and character and type(character.FindFirstChild) == "function" then
        root = character:FindFirstChild("HumanoidRootPart")
    end
    return root and root.Position or nil
end

function AutoDeflect.looksAt(origin, look, point, cosine)
    if typeof(origin) ~= "Vector3" or typeof(look) ~= "Vector3" or typeof(point) ~= "Vector3" then
        return false
    end
    local delta = point - origin
    if delta.Magnitude < 1 then
        return true
    end
    return look.Unit:Dot(delta.Unit) >= (cosine or AutoDeflect.LOOK_COSINE)
end

function AutoDeflect.lethalShot(item, health, distance, weaponPolicy)
    if type(health) ~= "number" or health <= 0 or type(weaponPolicy) ~= "table" then
        return false
    end
    local observation = {
        part = { Name = "HitboxHead" },
        health = health,
    }
    local damage = type(weaponPolicy.finishingDamage) == "function"
        and weaponPolicy.finishingDamage(item, observation, distance)
    if type(damage) ~= "number" and type(weaponPolicy.damageAtDistance) == "function" then
        damage = weaponPolicy.damageAtDistance(item, observation, distance)
    end
    return type(damage) == "number" and damage >= health
end

function AutoDeflect.ready(item, itemNow)
    if type(item) ~= "table" then
        return false
    end
    if
        type(itemNow) == "number"
        and type(item._deflect_cooldown) == "number"
        and itemNow < item._deflect_cooldown
    then
        return false
    end
    return true
end

function AutoDeflect.shouldBlock(localFighter, opponent, ctx)
    ctx = ctx or {}
    local WeaponPolicy = ctx.weaponPolicy
    local item = localFighter and localFighter.EquippedItem
    if
        type(WeaponPolicy) ~= "table"
        or type(WeaponPolicy.isDeflector) ~= "function"
        or WeaponPolicy.isDeflector(item) ~= true
        or (type(WeaponPolicy.isActivelyDeflecting) == "function" and WeaponPolicy.isActivelyDeflecting(
            item
        ))
        or not AutoDeflect.ready(item, ctx.itemClock and ctx.itemClock())
    then
        return false
    end

    local theirItem = opponent and opponent.EquippedItem
    local ourHealth = ctx.health
    local origin, look = AutoDeflect.lookFrom(opponent and opponent.character)
    local point = AutoDeflect.bodyPoint(ctx.character)
    local distance = ctx.distance
    if type(distance) ~= "number" and origin and point then
        distance = (point - origin).Magnitude
    end
    if
        not AutoDeflect.lethalShot(theirItem, ourHealth, distance, WeaponPolicy)
        or not AutoDeflect.looksAt(origin, look, point, ctx.lookCosine)
    then
        return false
    end
    if type(ctx.hasLine) == "function" then
        return ctx.hasLine(origin, point, opponent.character) == true
    end
    return true
end

function AutoDeflect.update(settings, ctx)
    if
        settings.autoDeflect ~= true
        or ctx.inputCaptured
        or not ctx.fighterActive
        or not ctx.inCombat
    then
        return false
    end
    local fighter = ctx.getFighter and ctx.getFighter()
    if not fighter then
        return false
    end
    for _, opponent in ipairs(ctx.opponents or {}) do
        if AutoDeflect.shouldBlock(fighter, opponent, ctx) then
            if type(ctx.aimClick) == "function" then
                ctx.aimClick()
            end
            if ctx.taskDebug then
                ctx.taskDebug.autoDeflectStage = "blocked"
            end
            return true
        end
    end
    return false
end

return AutoDeflect
]],
        ["games/rivals/features/CameraAim.lua"] = [[local RICOCHET_CACHE_INTERVAL = 0.15
local SPLASH_CACHE_INTERVAL = 0.1
local SLINGSHOT_CACHE_INTERVAL = 0.2
local SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS = 65

local CameraAim = {}
CameraAim.__index = CameraAim

function CameraAim.enabled(settings, shotOnly, taskCombatActive)
    settings = settings or {}
    local cameraAimEnabled = settings.silentAim == true or taskCombatActive == true
    return shotOnly and settings.shotAim == true or (cameraAimEnabled and settings.shotAim ~= true)
end

function CameraAim.shouldClearRetention(
    settings,
    taskCombatActive,
    inputCaptured,
    fighterActive,
    inCombat
)
    settings = settings or {}
    local cameraAimEnabled = settings.silentAim == true or taskCombatActive == true
    return not cameraAimEnabled and settings.shotAim ~= true
        or (inputCaptured and taskCombatActive ~= true)
        or not fighterActive
        or not inCombat
end

function CameraAim.new(libs)
    libs = libs or {}
    return setmetatable({
        targeting = libs.targeting,
        projectileAim = libs.projectileAim,
        weaponPolicy = libs.weaponPolicy,
        ricochetCache = nil,
        splashCache = nil,
        slingshotCache = nil,
    }, CameraAim)
end

function CameraAim:align(ctx)
    local Targeting = self.targeting
    local ProjectileAim = self.projectileAim
    local WeaponPolicy = self.weaponPolicy
    local settings = ctx.settings or {}
    local shotOnly = ctx.shotOnly
    local taskCombatActive = ctx.taskCombatActive
    local enabled = CameraAim.enabled(settings, shotOnly, taskCombatActive)
    local fighterActive = ctx.fighterActive
    local inCombat = ctx.inCombat
    if
        not enabled
        or (ctx.inputCaptured and taskCombatActive ~= true)
        or not fighterActive
        or not inCombat
    then
        if
            CameraAim.shouldClearRetention(
                settings,
                taskCombatActive,
                ctx.inputCaptured,
                fighterActive,
                inCombat
            )
        then
            ctx.clearRetention()
        end
        return nil
    end
    local function settleAim(rotation, instant, character, maximumSmoothness)
        if shotOnly then
            return true
        end
        return ctx.setAimRotation(rotation, instant, character, maximumSmoothness)
    end

    local fighter = ctx.fighter
    local item = fighter and fighter.EquippedItem
    local automationPolicy = WeaponPolicy.automationPolicy(item)
    local aimMode = shotOnly and "silentAim" or "cameraAim"
    if automationPolicy[aimMode] ~= true then
        ctx.clearRetention(true)
        return nil
    end
    local energyRifle = WeaponPolicy.isRicochetWeapon(item)
    local knife = WeaponPolicy.isBackstabKnife(item)
    local slingshot = WeaponPolicy.isBouncingProjectile(item)
    local splashProjectile = ProjectileAim.isSplashProjectile(item)
    local entity = fighter and fighter.Entity
    local localRoot = entity and entity.RootPart
    local target
    if knife then
        ctx.clearRetention()
        target = localRoot and ctx.selectBackstabTarget(localRoot.Position, item.Info)
    else
        ctx.rememberWeapon(item)
        local cameraAim = shotOnly ~= true
        if cameraAim and taskCombatActive ~= true then
            target = ctx.selectTarget(nil, true, false, true)
        else
            target = ctx.selectTarget(
                nil,
                energyRifle or slingshot or splashProjectile or taskCombatActive == true,
                taskCombatActive == true
            )
        end
        if not target and taskCombatActive == true then
            target = ctx.taskNavigationObservation()
        end
    end
    local camera = ctx.camera
    local taskDebug = ctx.taskDebug
    if not target or not camera then
        if taskDebug then
            taskDebug.aimStage = not camera and "no-camera" or "no-target"
        end
        if not target then
            ctx.clearTargetKey()
        end
        return nil
    end
    if taskDebug then
        taskDebug.aimStage = "target-selected"
        taskDebug.targetVisible = target.visible == true
        taskDebug.targetHealth = target.health
        taskDebug.targetDistance = target.distance
    end
    if not knife then
        ctx.rememberTarget(target)
    end

    local cameraFrame = camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
    local origin = cameraFrame.Position
    local now = ctx.clock()
    if
        not shotOnly
        and not knife
        and target.visible ~= true
        and typeof(target.position) == "Vector3"
    then
        local aligned = table.clone(target)
        aligned.aimSettled = settleAim(
            Targeting.rotationToward(origin, target.position),
            taskCombatActive == true,
            target.character
        )
        aligned.navigationOnly = taskCombatActive == true
        if taskDebug then
            taskDebug.aimStage = taskCombatActive == true and "navigation-only" or "off-screen"
            taskDebug.aimSettled = aligned.aimSettled
        end
        return aligned
    end
    if knife then
        local plan = target.backstabPlan
        local aimSettled =
            settleAim(Targeting.rotationToward(origin, plan.aimPosition), true, target.character)
        local aligned = {}
        for key, value in pairs(target) do
            aligned[key] = value
        end
        aligned.position = plan.aimPosition
        aligned.aimSettled = aimSettled
        aligned.backstab = plan.ready
        aligned.knifePath = plan.path
        return aligned
    end
    local taskRates
    if taskCombatActive == true then
        local observedRates =
            ctx.taskSkillRuntime:update(entity and entity.Humanoid, target, ctx.renderDelta)
        if taskDebug then
            taskDebug.adaptiveRates = observedRates
        end
        if observedRates.ready == true then
            taskRates = observedRates
        end
    end
    target = ctx.plannedAimTarget(target, item, taskRates)
    if taskDebug then
        taskDebug.aimStage = "planned"
        taskDebug.intentionalMiss = target.intentionalMiss == true
    end

    if slingshot and target.position then
        local cacheValid = self.slingshotCache
            and self.slingshotCache.target == target.character
            and now < self.slingshotCache.expiresAt
            and (self.slingshotCache.origin - origin).Magnitude <= 0.5
            and (self.slingshotCache.targetPosition - target.position).Magnitude <= 0.5
        if not cacheValid then
            self.slingshotCache = {
                expiresAt = now + SLINGSHOT_CACHE_INTERVAL,
                origin = origin,
                solution = ctx.solveBouncingProjectile(
                    origin,
                    target,
                    item.Info,
                    ctx.environmentRaycast(),
                    ctx.gravity,
                    ctx.getNetworkPing()
                ),
                target = target.character,
                targetPosition = target.position,
            }
        end

        if self.slingshotCache.solution then
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, origin + self.slingshotCache.solution.direction),
                false,
                target.character,
                SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS
            )
            local aligned = {}
            for key, value in pairs(target) do
                aligned[key] = value
            end
            aligned.aimSettled = aimSettled
            aligned.slingshot = self.slingshotCache.solution
            aligned.visible = true
            return aligned
        end
    else
        self.slingshotCache = nil
    end

    if splashProjectile and target.position then
        local raycast = ctx.environmentRaycast()
        local cacheValid = self.splashCache
            and self.splashCache.target == target.character
            and self.splashCache.item == item
            and now < self.splashCache.expiresAt
            and (self.splashCache.origin - origin).Magnitude <= 0.5
            and (self.splashCache.targetPosition - target.position).Magnitude <= 0.5
            and (
                not self.splashCache.solution
                or ProjectileAim.isSplashSolutionCurrent(
                    origin,
                    self.splashCache.solution,
                    item.Info,
                    raycast,
                    ctx.gravity
                )
            )
        if not cacheValid then
            self.splashCache = {
                expiresAt = now + SPLASH_CACHE_INTERVAL,
                item = item,
                origin = origin,
                solution = ctx.solveSplashAim(origin, target, item.Info, raycast, ctx.gravity),
                target = target.character,
                targetPosition = target.position,
            }
        end

        if self.splashCache.solution then
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, origin + self.splashCache.solution.direction),
                false,
                target.character
            )
            local aligned = {}
            for key, value in pairs(target) do
                aligned[key] = value
            end
            aligned.aimSettled = aimSettled
            aligned.splashImpact = self.splashCache.solution
            aligned.visible = true
            return aligned
        end
    else
        self.splashCache = nil
    end
    if splashProjectile then
        return nil
    end

    if target.visible and ProjectileAim.isDirectProjectile(item) then
        local solution = ProjectileAim.solveProjectileAim(
            origin,
            target,
            item.Info,
            ctx.gravity,
            shotOnly and ctx.renderDelta or 0
        )
        if solution then
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, origin + solution.direction),
                false,
                target.character
            )
            local aligned = {}
            for key, value in pairs(target) do
                aligned[key] = value
            end
            aligned.aimSettled = aimSettled
            aligned.projectileAim = solution
            aligned.visible = true
            return aligned
        end
    end

    if target.visible then
        local aimSettled =
            settleAim(Targeting.rotationToward(origin, target.position), false, target.character)
        self.ricochetCache = nil
        local aligned = table.clone(target)
        aligned.aimSettled = aimSettled
        return aligned
    end
    if not energyRifle or not target.position then
        return nil
    end

    local cacheValid = self.ricochetCache
        and self.ricochetCache.target == target.character
        and now < self.ricochetCache.expiresAt
        and (self.ricochetCache.origin - origin).Magnitude <= 0.5
        and (self.ricochetCache.targetPosition - target.position).Magnitude <= 0.5
    if not cacheValid then
        self.ricochetCache = {
            direction = ctx.solveRicochet(origin, target.position, ctx.environmentRaycast()),
            expiresAt = now + RICOCHET_CACHE_INTERVAL,
            origin = origin,
            target = target.character,
            targetPosition = target.position,
        }
    end

    local solution = self.ricochetCache.direction
    if not solution then
        return nil
    end

    local aimSettled = settleAim(
        Targeting.rotationToward(origin, origin + solution.direction),
        false,
        target.character
    )
    local aligned = {}
    for key, value in pairs(target) do
        aligned[key] = value
    end
    aligned.aimSettled = aimSettled
    aligned.ricochet = solution
    aligned.visible = true
    return aligned
end

return CameraAim
]],
        ["games/rivals/features/GunGameRuntime.lua"] = [[local GunGameRuntime = {}
GunGameRuntime.__index = GunGameRuntime

local SCAN_INTERVAL = 0.1
local RETRY_INTERVAL = 0.5

function GunGameRuntime.pickupType(instance)
    if
        not instance
        or instance.Name ~= "_drop"
        or type(instance.IsA) ~= "function"
        or not instance:IsA("BasePart")
        or type(instance.FindFirstChild) ~= "function"
    then
        return nil
    end
    if instance:FindFirstChild("Health") then
        return "Health"
    end
    if instance:FindFirstChild("AmmoBalanced") then
        return "AmmoBalanced"
    end
    return nil
end

function GunGameRuntime.shouldCollect(kind, fighter)
    if kind == "Health" then
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return humanoid ~= nil
            and type(humanoid.Health) == "number"
            and type(humanoid.MaxHealth) == "number"
            and humanoid.Health > 0
            and humanoid.Health < humanoid.MaxHealth
    end
    if kind ~= "AmmoBalanced" then
        return false
    end
    local item = fighter and fighter.EquippedItem
    local data = item and item.Data
    local info = item and item.Info
    if type(data) ~= "table" or type(info) ~= "table" then
        return item ~= nil
    end
    local knownCapacity = false
    if type(data.Ammo) == "number" and type(info.MaxAmmo) == "number" then
        knownCapacity = true
        if data.Ammo < info.MaxAmmo then
            return true
        end
    end
    if type(data.AmmoReserve) == "number" and type(info.MaxAmmoReserve) == "number" then
        knownCapacity = true
        if data.AmmoReserve < info.MaxAmmoReserve then
            return true
        end
    end
    return not knownCapacity
end

function GunGameRuntime.new(options)
    assert(options and options.store, "Gun Game runtime requires Store")
    assert(options.workspace, "Gun Game runtime requires Workspace")
    assert(options.getFighter, "Gun Game runtime requires a fighter getter")
    assert(options.isGunGame, "Gun Game runtime requires native mode state")

    local self = setmetatable({
        attemptedAt = setmetatable({}, { __mode = "k" }),
        candidates = {},
        clock = options.clock or os.clock,
        connections = {},
        fireTouchInterest = options.fireTouchInterest,
        getFighter = options.getFighter,
        isActive = options.isActive,
        isGunGame = options.isGunGame,
        isInCombat = options.isInCombat,
        nextScanAt = 0,
        spawn = options.spawn or task.spawn,
        stopped = false,
        store = options.store,
        wait = options.wait or task.wait,
        workspace = options.workspace,
    }, GunGameRuntime)

    local function addCandidate(candidate)
        if self.stopped then
            return
        end
        local kind = GunGameRuntime.pickupType(candidate)
        if kind then
            self.candidates[candidate] = kind
        end
    end
    local function removeCandidate(candidate)
        self.candidates[candidate] = nil
        self.attemptedAt[candidate] = nil
    end

    if type(options.workspace.GetChildren) == "function" then
        for _, candidate in ipairs(options.workspace:GetChildren()) do
            addCandidate(candidate)
        end
    end
    if
        options.workspace.ChildAdded
        and type(options.workspace.ChildAdded.Connect) == "function"
    then
        table.insert(self.connections, options.workspace.ChildAdded:Connect(addCandidate))
    end
    if
        options.workspace.ChildRemoved
        and type(options.workspace.ChildRemoved.Connect) == "function"
    then
        table.insert(self.connections, options.workspace.ChildRemoved:Connect(removeCandidate))
    end

    return self
end

function GunGameRuntime:update()
    if self.stopped then
        return
    end
    local settings = self.store:Get().settings
    if
        settings.autoPickup ~= true
        or not self.isGunGame()
        or type(self.fireTouchInterest) ~= "function"
        or self.isActive and not self.isActive()
        or self.isInCombat and not self.isInCombat()
    then
        return
    end
    local now = self.clock()
    if now < self.nextScanAt then
        return
    end
    self.nextScanAt = now + SCAN_INTERVAL
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local touchPart = entity and entity.RootPart
    if not touchPart then
        return
    end
    for candidate, kind in pairs(self.candidates) do
        local lastAttemptAt = self.attemptedAt[candidate]
        if
            kind
            and candidate.Parent == self.workspace
            and GunGameRuntime.shouldCollect(kind, fighter)
            and (lastAttemptAt == nil or now - lastAttemptAt >= RETRY_INTERVAL)
        then
            self.attemptedAt[candidate] = now
            self.spawn(function()
                if self.stopped or candidate.Parent ~= self.workspace then
                    return
                end
                local touched = pcall(self.fireTouchInterest, touchPart, candidate, 1)
                if touched then
                    self.wait()
                    pcall(self.fireTouchInterest, touchPart, candidate, 0)
                end
            end)
        end
    end
end

function GunGameRuntime:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    for _, connection in ipairs(self.connections) do
        if connection and type(connection.Disconnect) == "function" then
            connection:Disconnect()
        end
    end
    table.clear(self.connections)
    table.clear(self.candidates)
    table.clear(self.attemptedAt)
end

return GunGameRuntime
]],
        ["games/rivals/features/NoScope.lua"] = [[local NoScope = {}

function NoScope.enabled(settings)
    return settings and settings.alwaysScoped == true
end

function NoScope.shouldRefresh(settings)
    return NoScope.enabled(settings) or settings and settings.shotAim == true
end

return NoScope
]],
        ["games/rivals/features/Pickup.lua"] = [[local Pickup = {}

function Pickup.update(session, runtime)
    local settings = session and session.settings or {}
    if settings.autoPickup ~= true or not runtime then
        return false
    end
    runtime:update()
    return true
end

return Pickup
]],
        ["games/rivals/features/RapidFire.lua"] = [[local RapidFire = {}
RapidFire.__index = RapidFire

function RapidFire.new(weaponPolicy)
    return setmetatable({
        item = nil,
        cooldownKey = nil,
        originalCooldown = nil,
        weaponPolicy = weaponPolicy,
    }, RapidFire)
end

function RapidFire:restore()
    if self.item and self.cooldownKey and self.originalCooldown then
        self.item.Info[self.cooldownKey] = self.originalCooldown
    end
    self.item = nil
    self.cooldownKey = nil
    self.originalCooldown = nil
end

function RapidFire:update(settings, item, canFire, fireHeld, fire)
    local info = item and item.Info
    local cooldownKey = type(info) == "table"
            and type(info.ShootCooldown) == "number"
            and "ShootCooldown"
        or type(info) == "table" and type(info.AttackCooldown) == "number" and "AttackCooldown"
        or nil
    local cooldown = cooldownKey and info[cooldownKey]
    if settings.rapidFire ~= true or type(cooldown) ~= "number" or cooldown <= 0 then
        self:restore()
        return
    end

    if self.item ~= item then
        self:restore()
        self.item = item
        self.cooldownKey = cooldownKey
        self.originalCooldown = cooldown
    end

    local rate =
        math.clamp(type(settings.fireRate) == "number" and settings.fireRate or 200, 100, 300)
    info[self.cooldownKey] = self.originalCooldown * 100 / rate

    if
        canFire
        and fireHeld
        and not self.weaponPolicy.holdToFire(item)
        and type(fire) == "function"
    then
        fire()
    end
end

function RapidFire:stop()
    self:restore()
end

return RapidFire
]],
        ["games/rivals/features/RedLightSafety.lua"] = [[local RedLightSafety = {}
RedLightSafety.__index = RedLightSafety

function RedLightSafety.new(options)
    assert(options, "RIVALS Red Light Safety requires options")
    assert(options.hookFunction, "RIVALS Red Light Safety requires hookfunction")
    assert(options.restoreFunction, "RIVALS Red Light Safety requires restorefunction")
    assert(options.releaseAll, "RIVALS Red Light Safety requires input release")
    assert(options.stopMovement, "RIVALS Red Light Safety requires movement stop")
    assert(options.setInputSink, "RIVALS Red Light Safety requires input sinking")

    local self = setmetatable({
        chickenGame = nil,
        enabled = options.enabled or function()
            return true
        end,
        hookFunction = options.hookFunction,
        paused = false,
        releaseAll = options.releaseAll,
        restoreFunction = options.restoreFunction,
        setInputSink = options.setInputSink,
        stopMovement = options.stopMovement,
        targets = {},
    }, RedLightSafety)

    if options.chickenGame then
        self:refresh(options.chickenGame)
    end
    return self
end

function RedLightSafety:refresh(chickenGame)
    if chickenGame == self.chickenGame and #self.targets > 0 then
        return
    end
    for _, target in ipairs(self.targets) do
        self.restoreFunction(target)
    end
    table.clear(self.targets)
    self.chickenGame = chickenGame
    if not chickenGame then
        self:setPaused(false)
        return
    end
    local redTarget = chickenGame.RedLight
    local greenTarget = chickenGame.GreenLight
    assert(
        type(redTarget) == "function" and type(greenTarget) == "function",
        "RIVALS Red Light Safety requires ChickenGame light methods"
    )

    local originalRed
    originalRed = self.hookFunction(redTarget, function(...)
        if self.enabled() then
            self:setPaused(true)
        end
        return originalRed(...)
    end)
    local originalGreen
    originalGreen = self.hookFunction(greenTarget, function(...)
        self:setPaused(false)
        return originalGreen(...)
    end)
    self.targets = { redTarget, greenTarget }
end

function RedLightSafety:setPaused(paused)
    paused = paused == true
    if self.paused == paused then
        return
    end
    self.paused = paused
    self.setInputSink(paused)
    if paused then
        self.releaseAll()
        self.stopMovement()
    end
end

function RedLightSafety:isPaused()
    return self.paused
end

function RedLightSafety:holdStill()
    if self.paused then
        self.stopMovement()
    end
end

function RedLightSafety:stop()
    self.paused = false
    self.setInputSink(false)
    for _, target in ipairs(self.targets) do
        self.restoreFunction(target)
    end
    table.clear(self.targets)
end

return RedLightSafety
]],
        ["games/rivals/features/ScopedAccuracy.lua"] = [[local ScopedAccuracy = {}
ScopedAccuracy.__index = ScopedAccuracy

local function eligibleItem(item)
    local info = item and item.Info
    return type(info) == "table"
        and type(info.AimScopePercent) == "number"
        and info.AimScopePercent > 0
        and type(item.IsFullyAiming) == "function"
end

function ScopedAccuracy.new(options)
    assert(options and options.getFighter, "RIVALS Always Scoped requires a fighter getter")
    assert(options.hookFunction, "RIVALS Always Scoped requires hookfunction")
    assert(options.isEnabled, "RIVALS Always Scoped requires an enabled predicate")
    assert(options.restoreFunction, "RIVALS Always Scoped requires restorefunction")

    return setmetatable({
        getFighter = options.getFighter,
        hookFunction = options.hookFunction,
        hookTarget = nil,
        isEnabled = options.isEnabled,
        restoreFunction = options.restoreFunction,
        stopped = false,
    }, ScopedAccuracy)
end

function ScopedAccuracy:_restoreHook()
    if not self.hookTarget then
        return
    end
    self.restoreFunction(self.hookTarget)
    self.hookTarget = nil
end

function ScopedAccuracy:refreshHook()
    if self.stopped then
        return
    end
    if not self.isEnabled() then
        self:_restoreHook()
        return
    end

    local fighter = self.getFighter()
    local item = fighter and fighter.EquippedItem
    local target = eligibleItem(item) and item.IsFullyAiming or nil
    if target == self.hookTarget then
        return
    end

    self:_restoreHook()
    if not target then
        return
    end

    self.hookTarget = target
    local original
    original = self.hookFunction(target, function(itemSelf, ...)
        local currentFighter = self.getFighter()
        if
            not self.stopped
            and self.isEnabled()
            and currentFighter
            and itemSelf == currentFighter.EquippedItem
            and eligibleItem(itemSelf)
        then
            return true
        end
        return original(itemSelf, ...)
    end)
end

function ScopedAccuracy:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_restoreHook()
end

return ScopedAccuracy
]],
        ["games/rivals/features/ShotPresentation.lua"] = [[local ShotPresentation = {}
ShotPresentation.__index = ShotPresentation

local function maskedFrame(targetFrame, visibleFrame)
    return CFrame.new(targetFrame.Position) * visibleFrame.Rotation
end

function ShotPresentation.new(options)
    assert(options and options.cameraController, "RIVALS Shot Aim requires CameraController")
    assert(options.runService, "RIVALS Shot Aim requires RunService")
    assert(options.workspace, "RIVALS Shot Aim requires Workspace")
    assert(options.getFighter, "RIVALS Shot Aim requires a fighter getter")
    assert(options.hookFunction, "RIVALS Shot Aim requires hookfunction")
    assert(options.restoreFunction, "RIVALS Shot Aim requires restorefunction")

    local self = setmetatable({
        cameraController = options.cameraController,
        cameraDataOriginal = nil,
        cameraDataTarget = nil,
        frameRotation = nil,
        getFighter = options.getFighter,
        hookFunction = options.hookFunction,
        isEnabled = options.isEnabled or function()
            return false
        end,
        isInputCaptured = options.isInputCaptured or function()
            return false
        end,
        logicalTarget = nil,
        logicalRotation = nil,
        maskedFrame = nil,
        pendingTarget = nil,
        pendingRotation = nil,
        presentedTarget = nil,
        restoreFunction = options.restoreFunction,
        runService = options.runService,
        stopped = false,
        targetFrame = nil,
        visibleCamera = nil,
        visibleFrame = nil,
        visibleRotation = nil,
        workspace = options.workspace,
    }, ShotPresentation)
    local bindingSuffix = tostring(self):gsub("[^%w]", "")
    self.postBinding = "UniversalHubShotPresentationPost" .. bindingSuffix
    self.preBinding = "UniversalHubShotPresentationPre" .. bindingSuffix

    self.cameraPriority = options.cameraPriority or Enum.RenderPriority.Camera.Value
    return self
end

function ShotPresentation:_startRuntime()
    if self.runtimeActive or self.stopped then
        return
    end
    self.runtimeActive = true
    local rotationDeltaSignal = self.cameraController.RotationDeltaApplied
    if rotationDeltaSignal and type(rotationDeltaSignal.Connect) == "function" then
        self.rotationDeltaConnection = rotationDeltaSignal:Connect(function(delta)
            self:_applyVisibleRotationDelta(delta)
        end)
    end
    self.runService:BindToRenderStep(self.preBinding, self.cameraPriority - 1, function()
        self:_prepareFrame()
    end)
    self.runService:BindToRenderStep(self.postBinding, self.cameraPriority + 1, function()
        self:_maskFrame()
    end)
end

function ShotPresentation:_stopRuntime()
    if not self.runtimeActive then
        return
    end
    self.runtimeActive = false
    if self.rotationDeltaConnection then
        self.rotationDeltaConnection:Disconnect()
        self.rotationDeltaConnection = nil
    end
    self.runService:UnbindFromRenderStep(self.preBinding)
    self.runService:UnbindFromRenderStep(self.postBinding)
    self:clear()
end

function ShotPresentation:_reset()
    self.frameRotation = nil
    self.logicalTarget = nil
    self.logicalRotation = nil
    self.maskedFrame = nil
    self.pendingTarget = nil
    self.pendingRotation = nil
    self.presentedTarget = nil
    self.targetFrame = nil
    self.visibleCamera = nil
    self.visibleFrame = nil
    self.visibleRotation = nil
end

function ShotPresentation:clear()
    if self.visibleRotation then
        self.cameraController:SetRotation(self.visibleRotation)
    end
    local camera = self.workspace.CurrentCamera
    if camera and camera == self.visibleCamera and self.maskedFrame then
        camera.CFrame = self.maskedFrame
    end
    self:_reset()
end

function ShotPresentation:update(rotation, target)
    if self.stopped or typeof(rotation) ~= "Vector2" then
        self:clear()
        return false
    end

    local camera = self.workspace.CurrentCamera
    if not camera then
        self:clear()
        return false
    end
    if self.visibleCamera and self.visibleCamera ~= camera then
        self:clear()
    end
    if not self.visibleFrame then
        self.visibleCamera = camera
        self.visibleFrame = camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
        self.visibleRotation = self.cameraController.Rotation
    end
    self.pendingTarget = target
    self.pendingRotation = rotation
    return true
end

function ShotPresentation:getPresentedTarget()
    return self.targetFrame and self.frameRotation and self.presentedTarget or nil
end

function ShotPresentation:_prepareFrame()
    if self.stopped or not self.pendingRotation then
        return
    end
    self.logicalTarget = self.pendingTarget
    self.logicalRotation = self.pendingRotation
    self.cameraController:SetRotation(self.logicalRotation)
end

function ShotPresentation:_maskFrame()
    if
        self.stopped
        or not self.logicalRotation
        or not self.visibleFrame
        or not self.visibleRotation
    then
        return
    end
    local camera = self.workspace.CurrentCamera
    if not camera or camera ~= self.visibleCamera then
        self:clear()
        return
    end
    self.targetFrame = camera.CFrame
    self.frameRotation = self.logicalRotation
    self.presentedTarget = self.logicalTarget
    self.maskedFrame = maskedFrame(self.targetFrame, self.visibleFrame)
    camera.CFrame = self.maskedFrame
    self.cameraController:SetRotation(self.logicalRotation)
end

function ShotPresentation:_applyVisibleRotationDelta(delta)
    if
        self.stopped
        or not self.visibleFrame
        or not self.visibleRotation
        or typeof(delta) ~= "Vector2"
    then
        return
    end

    local previousRotation = self.visibleRotation
    local visible = previousRotation + delta
    local nextRotation =
        Vector2.new(math.clamp(visible.X, -1.5690509975429023, 1.5690509975429023), visible.Y)
    local previousBase = CFrame.Angles(0, previousRotation.Y, 0)
        * CFrame.Angles(previousRotation.X, 0, 0)
    local nextBase = CFrame.Angles(0, nextRotation.Y, 0) * CFrame.Angles(nextRotation.X, 0, 0)
    self.visibleFrame = CFrame.new(self.visibleFrame.Position)
        * nextBase
        * previousBase:ToObjectSpace(self.visibleFrame.Rotation)
    self.visibleRotation = nextRotation
    if self.logicalRotation then
        self.cameraController:SetRotation(self.logicalRotation)
    end
end

function ShotPresentation:refreshHook()
    if self.stopped then
        return
    end
    if not self.isEnabled() then
        if self.cameraDataTarget then
            self.restoreFunction(self.cameraDataTarget)
            self.cameraDataOriginal = nil
            self.cameraDataTarget = nil
        end
        self:_stopRuntime()
        return
    end
    self:_startRuntime()
    local fighter = self.getFighter()
    local target = fighter and fighter.GetCameraData
    if target == self.cameraDataTarget then
        return
    end
    if self.cameraDataTarget then
        self.restoreFunction(self.cameraDataTarget)
    end
    self.cameraDataOriginal = nil
    self.cameraDataTarget = nil
    if type(target) ~= "function" then
        return
    end

    self.cameraDataTarget = target
    local original
    original = self.hookFunction(target, function(fighterSelf, ...)
        if
            self.stopped
            or not self.isEnabled()
            or fighterSelf ~= self.getFighter()
            or self.isInputCaptured()
        then
            return original(fighterSelf, ...)
        end

        local camera = self.workspace.CurrentCamera
        if
            not camera
            or camera ~= self.visibleCamera
            or not self.targetFrame
            or not self.frameRotation
        then
            return original(fighterSelf, ...)
        end

        local localMaskedFrame = camera.CFrame
        camera.CFrame = self.targetFrame
        self.cameraController:SetRotation(self.frameRotation)
        local returned = table.pack(original(fighterSelf, ...))
        camera.CFrame = localMaskedFrame
        self.cameraController:SetRotation(self.frameRotation)
        return table.unpack(returned, 1, returned.n)
    end)
    self.cameraDataOriginal = original
end

function ShotPresentation:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_stopRuntime()
    self:clear()
    if self.cameraDataTarget then
        self.restoreFunction(self.cameraDataTarget)
        self.cameraDataTarget = nil
        self.cameraDataOriginal = nil
    end
end

return ShotPresentation
]],
        ["games/rivals/features/SilentAim.lua"] = [[local SilentAim = {}

function SilentAim.point(aligned, origin, distance)
    local solution = aligned
        and (aligned.slingshot or aligned.splashImpact or aligned.projectileAim or aligned.ricochet)
    if solution and typeof(solution.direction) == "Vector3" then
        return origin + solution.direction.Unit * distance
    end
    return aligned and aligned.position
end

function SilentAim.clear(session, presentation)
    if presentation and type(presentation.clear) == "function" then
        presentation:clear()
    end
    if session then
        session.presented = nil
    end
end

function SilentAim.update(session, presentation, libs)
    libs = libs or {}
    local settings = session and session.settings or {}
    if settings.shotAim ~= true then
        SilentAim.clear(session, presentation)
        return
    end
    local origin = session.cameraOrigin
    local point = origin and SilentAim.point(session.aligned, origin, libs.maxDistance)
    if not point or not presentation then
        SilentAim.clear(session, presentation)
        return
    end
    presentation:update(libs.targeting.rotationToward(origin, point), session.aligned)
    session.presented = presentation:getPresentedTarget()
end

return SilentAim
]],
        ["games/rivals/features/SkipBlocks.lua"] = [[local SkipBlocks = {}
SkipBlocks.__index = SkipBlocks

function SkipBlocks.shouldBlock(item, target, ctx)
    if not target or type(ctx) ~= "table" or type(ctx.isDeflecting) ~= "function" then
        return false
    end
    local targetFighter = target.player
        and type(ctx.fighterFor) == "function"
        and ctx.fighterFor(target.player)
    local counter = ctx.taskCounterPolicy
    local sprayCounter = targetFighter
        and type(counter) == "table"
        and type(counter.shouldForceSpray) == "function"
        and counter.shouldForceSpray(item, targetFighter.EquippedItem)
    return ctx.isDeflecting(target.player) == true and sprayCounter ~= true
end

function SkipBlocks.isFiring(item)
    if type(item) ~= "table" then
        return false
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "IsShooting")
        if succeeded and type(value) == "boolean" then
            return value
        end
    end
    local data = item.Data
    return type(data) == "table" and data.IsShooting == true
end

function SkipBlocks.new(options)
    assert(options and options.getFighter, "RIVALS Katana Stop requires a fighter getter")
    assert(options.hookFunction, "RIVALS Katana Stop requires hookfunction")
    assert(options.isEnabled, "RIVALS Katana Stop requires an enabled predicate")
    assert(options.restoreFunction, "RIVALS Katana Stop requires restorefunction")
    assert(options.shouldBlock, "RIVALS Katana Stop requires a block predicate")

    return setmetatable({
        getFighter = options.getFighter,
        hookFunction = options.hookFunction,
        hookTarget = nil,
        isEnabled = options.isEnabled,
        restoreFunction = options.restoreFunction,
        shouldBlock = options.shouldBlock,
        stopped = false,
    }, SkipBlocks)
end

function SkipBlocks:_restoreHook()
    if not self.hookTarget then
        return
    end
    self.restoreFunction(self.hookTarget)
    self.hookTarget = nil
end

function SkipBlocks:refreshHook()
    if self.stopped then
        return
    end
    if not self.isEnabled() then
        self:_restoreHook()
        return
    end

    local fighter = self.getFighter()
    local target = type(fighter) == "table" and type(fighter.Input) == "function" and fighter.Input
        or nil
    if target == self.hookTarget then
        return
    end

    self:_restoreHook()
    if not target then
        return
    end

    self.hookTarget = target
    local original
    original = self.hookFunction(target, function(fighterSelf, action, ...)
        local currentFighter = self.getFighter()
        if
            not self.stopped
            and self.isEnabled()
            and fighterSelf == currentFighter
            and action == "StartShooting"
            and self.shouldBlock(currentFighter.EquippedItem)
        then
            return
        end
        return original(fighterSelf, action, ...)
    end)
end

function SkipBlocks.update(item, target, ctx)
    if not SkipBlocks.shouldBlock(item, target, ctx) then
        return false
    end
    if
        type(ctx.releaseFire) == "function" and (SkipBlocks.isFiring(item) or ctx.fireHeld == true)
    then
        ctx.releaseFire()
    end
    return true
end

function SkipBlocks:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_restoreHook()
end

return SkipBlocks
]],
        ["games/rivals/features/TeleportBehind.lua"] = [[local TeleportBehind = {}

-- Irregular barrage around the target. A sequential ring is readable.
TeleportBehind.DISTANCE = 56
TeleportBehind.DISTANCE_SPREAD = 24
TeleportBehind.HEIGHT = 64
TeleportBehind.HEIGHT_SPREAD = 20
TeleportBehind.CLOSE_DISTANCE = 10
TeleportBehind.CLOSE_HEIGHT = 4
TeleportBehind.KNIFE_DISTANCE = 4
TeleportBehind.KNIFE_HEIGHT = 1
TeleportBehind.AIM_TORSO = 1
TeleportBehind.HIGH_AIM = 12
TeleportBehind.CLEARANCE = 80
TeleportBehind.MARGIN = 40
TeleportBehind.BODY = 4
TeleportBehind.MIN_DISTANCE = 16
TeleportBehind.HOP_RATE = 16
TeleportBehind.MIN_YAW_DELTA = math.pi * 0.6
TeleportBehind.OOB_TAG = "OutOfBoundsPart"
TeleportBehind.OOB_SAFE_TAG = "OutOfBoundsSafePart"

local heldHumanoid

local function rootFrame(target)
    local character = target and target.character
    local root = target and target.root
        or character
            and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild(
                "RootPart"
            ))
    local frame = root and root.CFrame
    if typeof(frame) ~= "CFrame" then
        return nil
    end
    return frame
end

function TeleportBehind.range()
    return TeleportBehind.DISTANCE, TeleportBehind.HEIGHT
end

function TeleportBehind.hopIndex(clock)
    clock = type(clock) == "number" and clock or 0
    return math.floor(clock * TeleportBehind.HOP_RATE)
end

function TeleportBehind.hash(index, salt)
    index = type(index) == "number" and index or 0
    salt = type(salt) == "number" and salt or 0
    local x = (index * 1103515245 + 12345 + salt * 7919) % 2147483648
    return x / 2147483648
end

local function yawDelta(a, b)
    return math.abs((a - b + math.pi) % (math.pi * 2) - math.pi)
end

function TeleportBehind.bearing(from, center)
    if typeof(from) ~= "Vector3" or typeof(center) ~= "Vector3" then
        return nil
    end
    local delta = from - center
    if math.abs(delta.X) + math.abs(delta.Z) < 1e-3 then
        return nil
    end
    return math.atan2(delta.Z, delta.X)
end

function TeleportBehind.pose(clock, lastYaw)
    local index = TeleportBehind.hopIndex(clock)
    local yaw = TeleportBehind.hash(index, 1) * math.pi * 2
    if type(lastYaw) == "number" and yawDelta(yaw, lastYaw) < TeleportBehind.MIN_YAW_DELTA then
        yaw = lastYaw + math.pi * (0.7 + TeleportBehind.hash(index, 2) * 0.6)
    end
    local distance = TeleportBehind.DISTANCE
        + (TeleportBehind.hash(index, 3) * 2 - 1) * TeleportBehind.DISTANCE_SPREAD
    local height = TeleportBehind.HEIGHT
        + (TeleportBehind.hash(index, 4) * 2 - 1) * TeleportBehind.HEIGHT_SPREAD
    return yaw, distance, height
end

function TeleportBehind.insidePart(part, position)
    if typeof(position) ~= "Vector3" then
        return false
    end
    local frame = part and part.CFrame
    local size = part and part.Size
    if typeof(frame) ~= "CFrame" or typeof(size) ~= "Vector3" then
        return false
    end
    local localPoint = frame:PointToObjectSpace(position)
    local half = size * 0.5
    return math.abs(localPoint.X) <= half.X
        and math.abs(localPoint.Y) <= half.Y
        and math.abs(localPoint.Z) <= half.Z
end

function TeleportBehind.isOutOfBounds(position, tagged)
    tagged = tagged or {}
    local insideKill = false
    for _, part in ipairs(tagged.kill or {}) do
        if TeleportBehind.insidePart(part, position) then
            insideKill = true
            break
        end
    end
    if not insideKill then
        return false
    end
    for _, part in ipairs(tagged.safe or {}) do
        if TeleportBehind.insidePart(part, position) then
            return false
        end
    end
    return true
end

function TeleportBehind.cageBounds(parts)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local found = false
    for _, part in ipairs(parts or {}) do
        local frame = part and part.CFrame
        local size = part and part.Size
        if typeof(frame) == "CFrame" and typeof(size) == "Vector3" then
            local half = size * 0.5
            for _, sx in ipairs({ -1, 1 }) do
                for _, sy in ipairs({ -1, 1 }) do
                    for _, sz in ipairs({ -1, 1 }) do
                        local world = frame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
                        minX = math.min(minX, world.X)
                        minY = math.min(minY, world.Y)
                        minZ = math.min(minZ, world.Z)
                        maxX = math.max(maxX, world.X)
                        maxY = math.max(maxY, world.Y)
                        maxZ = math.max(maxZ, world.Z)
                        found = true
                    end
                end
            end
        end
    end
    if not found then
        return nil
    end
    return {
        min = Vector3.new(minX, minY, minZ),
        max = Vector3.new(maxX, maxY, maxZ),
    }
end

function TeleportBehind.cageTop(parts)
    local bounds = TeleportBehind.cageBounds(parts)
    return bounds and bounds.max.Y or nil
end

function TeleportBehind.outsideHeight(targetY, parts)
    if type(targetY) ~= "number" then
        return TeleportBehind.HEIGHT
    end
    local top = TeleportBehind.cageTop(parts)
    if type(top) ~= "number" then
        return TeleportBehind.HEIGHT
    end
    return math.max(TeleportBehind.HEIGHT, (top + TeleportBehind.CLEARANCE) - targetY)
end

function TeleportBehind.outsideRadius(focus, bounds)
    if typeof(focus) ~= "Vector3" or type(bounds) ~= "table" then
        return TeleportBehind.DISTANCE
    end
    local min, max = bounds.min, bounds.max
    if typeof(min) ~= "Vector3" or typeof(max) ~= "Vector3" then
        return TeleportBehind.DISTANCE
    end
    local farthest = 0
    for _, x in ipairs({ min.X, max.X }) do
        for _, z in ipairs({ min.Z, max.Z }) do
            local dx = x - focus.X
            local dz = z - focus.Z
            local mag = math.sqrt(dx * dx + dz * dz)
            if mag > farthest then
                farthest = mag
            end
        end
    end
    return math.max(TeleportBehind.DISTANCE, farthest + TeleportBehind.MARGIN)
end

function TeleportBehind.focusY(session, targetY)
    if type(targetY) ~= "number" then
        return targetY
    end
    if type(session.teleportFocusY) ~= "number" or targetY <= session.teleportFocusY + 8 then
        session.teleportFocusY = targetY
    end
    return session.teleportFocusY
end

function TeleportBehind.clear(position, isOutOfBounds)
    if typeof(position) ~= "Vector3" then
        return false
    end
    if type(isOutOfBounds) ~= "function" then
        return true
    end
    if isOutOfBounds(position) == true then
        return false
    end
    local margin = TeleportBehind.BODY
    for _, offset in ipairs({
        Vector3.new(margin, 0, 0),
        Vector3.new(-margin, 0, 0),
        Vector3.new(0, margin, 0),
        Vector3.new(0, -margin, 0),
        Vector3.new(0, 0, margin),
        Vector3.new(0, 0, -margin),
    }) do
        if isOutOfBounds(position + offset) == true then
            return false
        end
    end
    return true
end

function TeleportBehind.hasForceField(character)
    return type(character) == "table"
        and type(character.FindFirstChildOfClass) == "function"
        and character:FindFirstChildOfClass("ForceField") ~= nil
end

function TeleportBehind.lookPoint(target)
    if typeof(target and target.position) == "Vector3" then
        return target.position
    end
    local character = target and target.character
    local head = character and character.FindFirstChild and character:FindFirstChild("Head")
    if head and typeof(head.Position) == "Vector3" then
        return head.Position
    end
    local frame = rootFrame(target)
    if not frame then
        return nil
    end
    return frame.Position + Vector3.new(0, 2, 0)
end

function TeleportBehind.aimPoint(from, target)
    local lookAt = TeleportBehind.lookPoint(target)
    local frame = rootFrame(target)
    local root = frame and frame.Position
    if typeof(from) ~= "Vector3" then
        return lookAt
    end
    local focus = typeof(root) == "Vector3" and root or lookAt
    if typeof(focus) ~= "Vector3" then
        return lookAt
    end
    if from.Y - focus.Y < TeleportBehind.HIGH_AIM then
        return lookAt
    end
    return Vector3.new(focus.X, focus.Y + TeleportBehind.AIM_TORSO, focus.Z)
end

function TeleportBehind.canSee(from, lookAt, raycast)
    if typeof(from) ~= "Vector3" or typeof(lookAt) ~= "Vector3" then
        return false
    end
    if type(raycast) ~= "function" then
        return true
    end
    local delta = lookAt - from
    if delta.Magnitude < 1e-3 then
        return true
    end
    return raycast(from, delta) == nil
end

function TeleportBehind.isImmune(session, libs)
    libs = libs or {}
    if type(libs.isImmune) == "function" and libs.isImmune() == true then
        return true
    end
    local character = type(libs.getCharacter) == "function" and libs.getCharacter()
    if TeleportBehind.hasForceField(character) then
        return true
    end
    local target = session and (session.presented or session.aligned)
    return TeleportBehind.hasForceField(target and target.character)
end

function TeleportBehind.pullIn(center, position, isOutOfBounds)
    if typeof(center) ~= "Vector3" or typeof(position) ~= "Vector3" then
        return nil
    end
    if TeleportBehind.clear(position, isOutOfBounds) then
        return position
    end
    for step = 9, 2, -1 do
        local pulled = center:Lerp(position, step / 10)
        local planar = Vector3.new(pulled.X - center.X, 0, pulled.Z - center.Z)
        if
            planar.Magnitude >= TeleportBehind.MIN_DISTANCE
            and TeleportBehind.clear(pulled, isOutOfBounds)
        then
            return pulled
        end
    end
    return nil
end

local function slotCFrame(center, lookAt, yaw, distance, height)
    local position = center
        + Vector3.new(math.cos(yaw) * distance, height, math.sin(yaw) * distance)
    return CFrame.lookAt(position, lookAt)
end

function TeleportBehind.destination(
    target,
    clock,
    distance,
    height,
    isOutOfBounds,
    yaw,
    focusY,
    raycast,
    closeOnly
)
    local frame = rootFrame(target)
    if not frame then
        return nil
    end
    if type(yaw) ~= "number" then
        yaw, distance, height = TeleportBehind.pose(clock)
    elseif type(distance) ~= "number" or type(height) ~= "number" then
        local _, sampledDistance, sampledHeight = TeleportBehind.pose(clock, yaw)
        if type(distance) ~= "number" then
            distance = sampledDistance
        end
        if type(height) ~= "number" then
            height = sampledHeight
        end
    end
    local center = frame.Position
    if type(focusY) == "number" then
        center = Vector3.new(center.X, focusY, center.Z)
    end
    local lookAt = TeleportBehind.lookPoint(target) or frame.Position
    local attempts = {
        { 0, 1, 0 },
        { math.pi * 0.85, 1, 0 },
        { math.pi * 1.2, 1, 0 },
        { math.pi * 0.5, 0.85, 0 },
        { math.pi * 1.5, 0.85, 0 },
        { math.pi, 0.7, 0 },
        { 0, 0.55, 12 },
    }
    for _, attempt in ipairs(attempts) do
        local destination =
            slotCFrame(center, lookAt, yaw + attempt[1], distance * attempt[2], height + attempt[3])
        local pulled = TeleportBehind.pullIn(center, destination.Position, isOutOfBounds)
        if pulled and TeleportBehind.canSee(pulled, lookAt, raycast) then
            return CFrame.lookAt(pulled, lookAt)
        end
    end
    if
        closeOnly ~= true
        and (
            distance > TeleportBehind.CLOSE_DISTANCE + 1
            or height > TeleportBehind.CLOSE_HEIGHT + 1
        )
    then
        return TeleportBehind.destination(
            target,
            clock,
            TeleportBehind.CLOSE_DISTANCE,
            TeleportBehind.CLOSE_HEIGHT,
            isOutOfBounds,
            yaw,
            focusY,
            raycast,
            true
        )
    end
    return nil
end

function TeleportBehind.knifeDestination(target, isOutOfBounds, raycast, focusY)
    local frame = rootFrame(target)
    if not frame then
        return nil
    end
    local look = frame.LookVector
    local planar = Vector3.new(look.X, 0, look.Z)
    if planar.Magnitude < 1e-3 then
        planar = Vector3.new(0, 0, 1)
    else
        planar = planar.Unit
    end
    local center = frame.Position
    if type(focusY) == "number" then
        center = Vector3.new(center.X, focusY, center.Z)
    end
    local lookAt = TeleportBehind.lookPoint(target) or frame.Position
    local behind = center
        - planar * TeleportBehind.KNIFE_DISTANCE
        + Vector3.new(0, TeleportBehind.KNIFE_HEIGHT, 0)
    local pulled = TeleportBehind.pullIn(center, behind, isOutOfBounds)
    if pulled and TeleportBehind.canSee(pulled, lookAt, raycast) then
        return CFrame.lookAt(pulled, lookAt)
    end
    return TeleportBehind.destination(
        target,
        0,
        TeleportBehind.KNIFE_DISTANCE,
        TeleportBehind.KNIFE_HEIGHT,
        isOutOfBounds,
        TeleportBehind.bearing(behind, center) or 0,
        focusY,
        raycast,
        true
    )
end

function TeleportBehind.slotOpen(destination, target, isOutOfBounds, raycast)
    if typeof(destination) ~= "CFrame" then
        return false
    end
    local lookAt = TeleportBehind.lookPoint(target)
    return lookAt ~= nil
        and TeleportBehind.clear(destination.Position, isOutOfBounds)
        and TeleportBehind.canSee(destination.Position, lookAt, raycast)
end

function TeleportBehind.oneShotMode(_session, libs)
    libs = libs or {}
    local mode = type(libs.weaponMode) == "function" and libs.weaponMode()
    if mode == "knife" or mode == "sniper" then
        return mode
    end
    return nil
end

local function stopFall(root)
    if typeof(root.AssemblyLinearVelocity) == "Vector3" then
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
    if typeof(root.AssemblyAngularVelocity) == "Vector3" then
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end

local function apply(root, destination, humanoid)
    root.CFrame = destination
    stopFall(root)
    if humanoid and humanoid.PlatformStand ~= nil then
        humanoid.PlatformStand = true
        heldHumanoid = humanoid
    end
end

function TeleportBehind.release(session, libs)
    libs = libs or {}
    if session then
        session.teleportEngaged = false
        session.teleportSafe = nil
        session.teleportHop = nil
        session.teleportYaw = nil
        session.teleportDistance = nil
        session.teleportHeight = nil
        session.teleportFocusY = nil
    end
    if heldHumanoid and heldHumanoid.PlatformStand == true then
        heldHumanoid.PlatformStand = false
    end
    heldHumanoid = nil
end

function TeleportBehind.hold(session, libs)
    libs = libs or {}
    local settings = session and session.settings or {}
    if settings.teleportBehind ~= true then
        return false
    end
    local destination = session and session.teleportSafe
    local root = type(libs.getRoot) == "function" and libs.getRoot()
    if not root or typeof(destination) ~= "CFrame" then
        return false
    end
    apply(root, destination, type(libs.getHumanoid) == "function" and libs.getHumanoid())
    return true
end

function TeleportBehind.update(session, libs)
    libs = libs or {}
    local settings = session and session.settings or {}
    if settings.teleportBehind ~= true then
        TeleportBehind.release(session, libs)
        return false
    end
    if TeleportBehind.isImmune(session, libs) then
        if session.teleportEngaged == true and typeof(session.teleportSafe) == "CFrame" then
            return TeleportBehind.hold(session, libs)
        end
        return false
    end
    if session.teleportEngaged ~= true then
        if session.active ~= true or session.inCombat ~= true then
            return false
        end
        session.teleportEngaged = true
    end
    local target = session.presented or session.aligned
    if not target and type(libs.selectTarget) == "function" then
        target = libs.selectTarget()
    end
    local root = type(libs.getRoot) == "function" and libs.getRoot()
    if not root then
        TeleportBehind.release(session, libs)
        return false
    end
    local clock = type(libs.clock) == "function" and libs.clock() or session.clock
    local distance, height = TeleportBehind.range()
    if type(libs.distance) == "number" then
        distance = libs.distance
    end
    if type(libs.height) == "number" then
        height = libs.height
    end
    if type(clock) ~= "number" then
        clock = 0
    end
    local frame = rootFrame(target)
    local focusY = frame and TeleportBehind.focusY(session, frame.Position.Y)
    local oneShot = TeleportBehind.oneShotMode(session, libs)
    local destination
    if oneShot == "knife" then
        destination =
            TeleportBehind.knifeDestination(target, libs.isOutOfBounds, libs.raycast, focusY)
    elseif
        oneShot == "sniper"
        and TeleportBehind.slotOpen(session.teleportSafe, target, libs.isOutOfBounds, libs.raycast)
    then
        local lookAt = TeleportBehind.lookPoint(target)
        destination = CFrame.lookAt(session.teleportSafe.Position, lookAt)
    else
        local hop = TeleportBehind.hopIndex(clock)
        if session.teleportHop ~= hop or type(session.teleportYaw) ~= "number" then
            local around = frame and TeleportBehind.bearing(root.Position, frame.Position)
            local yaw, hopDistance, hopHeight =
                TeleportBehind.pose(clock, around or session.teleportYaw)
            session.teleportHop = hop
            session.teleportYaw = yaw
            session.teleportDistance = hopDistance
            session.teleportHeight = hopHeight
        end
        destination = TeleportBehind.destination(
            target,
            clock,
            session.teleportDistance or distance,
            session.teleportHeight or height,
            libs.isOutOfBounds,
            session.teleportYaw,
            focusY,
            libs.raycast
        )
    end
    if destination then
        session.teleportSafe = destination
    end
    if typeof(session.teleportSafe) ~= "CFrame" then
        return false
    end
    apply(root, session.teleportSafe, type(libs.getHumanoid) == "function" and libs.getHumanoid())
    return true
end

return TeleportBehind
]],
        ["games/rivals/features/TriggerBot.lua"] = [[local TriggerBot = {}

-- Fallback only. Live fire uses the equipped weapon's native cooldown.
TriggerBot.INTERVAL = 0
TriggerBot.RADIUS = 8

function TriggerBot.weaponReady(item, now)
    if type(now) ~= "number" then
        return true
    end
    if type(item) == "table" and type(item._shoot_cooldown) == "number" then
        return now >= item._shoot_cooldown
    end
    return true
end

function TriggerBot.fireDelay(item, fallback)
    local info = item and item.Info
    if type(info) == "table" then
        if type(info.ShootCooldown) == "number" then
            return info.ShootCooldown
        end
        if type(info.InternalUseCooldown) == "number" then
            return info.InternalUseCooldown
        end
    end
    if type(fallback) == "number" then
        return fallback
    end
    return TriggerBot.INTERVAL
end

function TriggerBot.hubReady(state, now)
    local nextAt = state and state.nextAt
    if type(nextAt) ~= "number" or type(now) ~= "number" or now >= nextAt then
        return true
    end
    -- A previous click stored tick() in nextAt. os.clock() can never catch that.
    if nextAt - now > 60 then
        state.nextAt = 0
        return true
    end
    return false
end

TriggerBot.MAX_DELAY_MS = 250
TriggerBot.TARGET_GRACE_SECONDS = 0.1

function TriggerBot.delaySeconds(settings)
    local ms = settings and settings.triggerDelay
    if type(ms) ~= "number" or ms <= 0 then
        return 0
    end
    return math.clamp(ms, 0, TriggerBot.MAX_DELAY_MS) / 1000
end

function TriggerBot.delayReady(state, now, delay, targetKey)
    if type(delay) ~= "number" or delay <= 0 then
        if state then
            state.armedAt = nil
            state.armedDelay = nil
            state.armedKey = nil
        end
        return true
    end
    if type(now) ~= "number" then
        return true
    end
    if
        state.armedKey ~= targetKey
        or state.armedDelay ~= delay
        or type(state.armedAt) ~= "number"
        or type(state.lostAt) == "number"
            and now - state.lostAt > TriggerBot.TARGET_GRACE_SECONDS
    then
        state.armedAt = now
        state.armedDelay = delay
        state.armedKey = targetKey
    end
    state.lostAt = nil
    return now >= state.armedAt + delay
end

function TriggerBot.delayLost(state, now)
    if
        type(state) == "table"
        and type(state.armedAt) == "number"
        and type(state.lostAt) ~= "number"
    then
        state.lostAt = now
    end
end

function TriggerBot.holdDropped(item, now, fallback)
    if type(now) ~= "number" or not TriggerBot.weaponReady(item, now) then
        return false
    end
    local delay = TriggerBot.fireDelay(item, fallback)
    if type(delay) ~= "number" or delay <= 0 then
        return false
    end
    local readyAt = item and item._shoot_cooldown
    if type(readyAt) ~= "number" or readyAt <= 0 then
        return false
    end
    return now - readyAt > delay
end

function TriggerBot.target(session, alignedTarget)
    local settings = session and session.settings or {}
    if settings.shotAim == true then
        return session and session.presented or nil
    end
    return alignedTarget
end

function TriggerBot.solvedPath(target)
    return target ~= nil
        and (
            target.projectileAim ~= nil
            or target.ricochet ~= nil
            or target.slingshot ~= nil
            or target.splashImpact ~= nil
        )
end

local function policyFlag(weaponPolicy, name, item)
    local query = weaponPolicy and weaponPolicy[name]
    return type(query) == "function" and query(item) == true
end

local function cameraOrigin(ctx)
    local camera = ctx and ctx.camera
    local frame = camera and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    return frame and frame.Position or nil
end

function TriggerBot.hitscanReady(target, origin, raycast, targeting)
    if typeof(origin) ~= "Vector3" or type(raycast) ~= "function" then
        return target and target.visible == true
    end
    targeting = targeting or {}
    if type(targeting.visibleHeadPoint) == "function" then
        local point = targeting.visibleHeadPoint(target, origin, raycast)
        if point then
            return true
        end
    end
    if type(targeting.visibleBodyPoint) == "function" then
        local point = targeting.visibleBodyPoint(target, origin, raycast)
        if point then
            return true
        end
    end
    return false
end

function TriggerBot.pathReady(target, item, ctx)
    ctx = ctx or {}
    if not target then
        return false
    end
    local WeaponPolicy = ctx.weaponPolicy or {}
    local ProjectileAim = ctx.projectileAim or {}
    if
        policyFlag(WeaponPolicy, "isBackstabKnife", item)
        or policyFlag(WeaponPolicy, "isDualModeBlade", item)
    then
        return true
    end
    if TriggerBot.solvedPath(target) then
        return true
    end
    local usesArc = (
        type(ProjectileAim.isSplashProjectile) == "function"
        and ProjectileAim.isSplashProjectile(item)
    )
        or (type(ProjectileAim.isDirectProjectile) == "function" and ProjectileAim.isDirectProjectile(
            item
        ))
        or policyFlag(WeaponPolicy, "isRicochetWeapon", item)
        or policyFlag(WeaponPolicy, "isBouncingProjectile", item)
    if usesArc then
        if
            type(ProjectileAim.isDirectProjectile) == "function"
            and ProjectileAim.isDirectProjectile(item)
            and type(ProjectileAim.solveProjectileAim) == "function"
        then
            local origin = cameraOrigin(ctx)
            local solution = origin
                and ProjectileAim.solveProjectileAim(
                    origin,
                    target,
                    item and item.Info,
                    ctx.gravity
                )
            if solution then
                target.projectileAim = solution
                return true
            end
        end
        return false
    end
    return TriggerBot.hitscanReady(target, cameraOrigin(ctx), ctx.raycast, ctx.targeting)
end

function TriggerBot.shouldHoldForDeflect(target, item, ctx)
    if not target or type(ctx) ~= "table" or type(ctx.isDeflecting) ~= "function" then
        return false
    end
    local targetFighter = target.player
        and type(ctx.fighterFor) == "function"
        and ctx.fighterFor(target.player)
    local counter = ctx.taskCounterPolicy
    local sprayCounter = targetFighter
        and type(counter) == "table"
        and type(counter.shouldForceSpray) == "function"
        and counter.shouldForceSpray(item, targetFighter.EquippedItem)
    return ctx.isDeflecting(target.player) == true and sprayCounter ~= true
end

function TriggerBot.update(session, ctx)
    local settings = session and session.settings or {}
    local alignedTarget = TriggerBot.target(session, ctx.alignedTarget)
    local taskCombatActive = ctx.taskCombatActive
    local taskDebug = ctx.taskDebug
    local state = ctx.state
    local WeaponPolicy = ctx.weaponPolicy
    local ProjectileAim = ctx.projectileAim
    local interval = ctx.interval or TriggerBot.INTERVAL
    local radius = ctx.radius or TriggerBot.RADIUS
    if taskDebug then
        taskDebug.triggerStage = "entered"
        taskDebug.triggerAt = ctx.clock()
    end
    if
        settings.triggerBot ~= true and taskCombatActive ~= true
        or (ctx.inputCaptured and taskCombatActive ~= true)
        or not ctx.fighterActive
        or not ctx.inCombat
    then
        if taskDebug then
            taskDebug.triggerStage = "inactive"
        end
        state.gunblade = nil
        state.armedAt = nil
        state.armedDelay = nil
        state.armedKey = nil
        state.lostAt = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    local fighter = ctx.getFighter()
    local item = fighter and fighter.EquippedItem
    if WeaponPolicy.automationPolicy(item).triggerBot ~= true then
        if taskDebug then
            taskDebug.triggerStage = "unsupported-weapon"
        end
        state.gunblade = nil
        ctx.clearAimPlan()
        state.armedAt = nil
        state.armedDelay = nil
        state.armedKey = nil
        state.lostAt = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    local itemData = item.Data
    local ammo = WeaponPolicy.ammo(item)
    if ammo == 0 or type(itemData) == "table" and itemData.IsReloading == true then
        if taskDebug then
            taskDebug.triggerStage = ammo == 0 and "empty" or "reloading"
        end
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    local gunblade = WeaponPolicy.isDualModeBlade(item)
    if not gunblade and alignedTarget and alignedTarget.aimSettled == false then
        local humanReticleReady = settings.humanAim
            and (alignedTarget.screenDistance or math.huge) <= radius
            and not alignedTarget.ricochet
            and not alignedTarget.slingshot
            and not alignedTarget.splashImpact
            and not alignedTarget.projectileAim
        if not humanReticleReady then
            if taskDebug then
                taskDebug.triggerStage = "aim-settling"
            end
            if state.fireHeld then
                return
            end
            TriggerBot.delayLost(state, ctx.clock())
            ctx.releaseFire()
            return
        end
    end

    local target
    if gunblade then
        if settings.shotAim then
            target = alignedTarget
        else
            target = ctx.selectDualModeBladeTarget(fighter, item)
        end
    else
        target = alignedTarget
        if not target and not settings.shotAim then
            target = ctx.selectCrosshairTarget()
        end
    end
    if TriggerBot.shouldHoldForDeflect(target, item, ctx) then
        if taskDebug then
            taskDebug.triggerStage = "target-deflecting"
        end
        state.gunblade = nil
        state.armedAt = nil
        state.armedDelay = nil
        state.armedKey = nil
        state.lostAt = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        return
    end
    if not target or not TriggerBot.pathReady(target, item, ctx) then
        if taskDebug then
            taskDebug.triggerStage = not target and "no-target" or "path-blocked"
        end
        local now = ctx.clock()
        TriggerBot.delayLost(state, now)
        if state.fireHeld then
            state.fireLostAt = state.fireLostAt or now
            if now - state.fireLostAt <= TriggerBot.TARGET_GRACE_SECONDS then
                return
            end
        end
        state.fireLostAt = nil
        state.gunblade = nil
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
            state.nextAt = ctx.clock() + TriggerBot.fireDelay(item, interval)
        end
        return
    end
    state.fireLostAt = nil

    if gunblade then
        ctx.releaseFire()
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end

        local entity = fighter and fighter.Entity
        local localRoot = entity and entity.RootPart
        local localPosition = localRoot and localRoot.Position
        local targetPosition = ctx.targetRootPosition(target)
        local targetDistance = localPosition
            and targetPosition
            and (targetPosition - localPosition).Magnitude
        local action
        state.gunblade, action = WeaponPolicy.gunbladeTriggerAction(
            state.gunblade,
            item,
            target.character or target.player or target,
            targetDistance,
            ctx.clock()
        )
        if not action then
            return
        end

        local camera = ctx.camera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local cameraPosition = cameraFrame and cameraFrame.Position
        local cameraOffset = cameraPosition and targetPosition and targetPosition - cameraPosition
        local visibleFrame = camera and camera.CFrame
        local visibleRotation = ctx.cameraController.Rotation
        if cameraOffset and cameraOffset.Magnitude > 1e-3 then
            ctx.cameraController:SetRotation(
                ctx.targeting.rotationToward(cameraPosition, targetPosition)
            )
            camera.CFrame = CFrame.lookAt(cameraPosition, targetPosition)
        end
        if action.kind == "dash" then
            ctx.aimClick()
        else
            ctx.click()
        end
        if visibleFrame then
            camera.CFrame = visibleFrame
        end
        if visibleRotation then
            ctx.cameraController:SetRotation(visibleRotation)
        end
        ctx.clearAimPlan()
        return
    end
    state.gunblade = nil
    if
        ProjectileAim.isSplashProjectile(item)
        and not (alignedTarget and alignedTarget.splashImpact)
    then
        ctx.releaseFire()
        return
    end
    if WeaponPolicy.isBackstabKnife(item) then
        ctx.releaseFire()
        if not WeaponPolicy.backstabTriggerReady(fighter, item, alignedTarget, ctx.isGunGame()) then
            return
        end
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        if not TriggerBot.hubReady(state, ctx.clock()) then
            return
        end
        state.nextAt = ctx.clock() + (item.Info.HeavyAttackCooldown or interval)
        ctx.aimClick()
        return
    end
    local targetFighter = target.player and ctx.fighterFor(target.player)
    local sprayCounter = targetFighter
        and ctx.taskCounterPolicy.shouldForceSpray(item, targetFighter.EquippedItem)
    local camera = ctx.camera
    local cameraFrame = camera
        and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    local targetDistance = cameraFrame
        and target.position
        and (target.position - cameraFrame.Position).Magnitude
    if
        targetDistance
        and not sprayCounter
        and not WeaponPolicy.triggerDamageReady(item, target, targetDistance)
    then
        if taskDebug then
            taskDebug.triggerStage = "damage-gate"
        end
        ctx.releaseFire()
        return
    end
    local sniperCrouching = WeaponPolicy.isScoped(item) and ctx.localFighterIsCrouching(fighter)
    if
        not WeaponPolicy.sniperTriggerReady(
            ctx.cameraController,
            item,
            target,
            targetDistance,
            sniperCrouching,
            settings.alwaysScoped == true
        )
    then
        if taskDebug then
            taskDebug.triggerStage = "precision-gate"
        end
        ctx.releaseFire()
        return
    end
    if taskDebug then
        taskDebug.triggerStage = "ready"
        taskDebug.triggerDistance = targetDistance
    end
    local targetKey = target.character or target.player or target
    local previousKey = state.armedKey
    if
        not TriggerBot.delayReady(state, ctx.clock(), TriggerBot.delaySeconds(settings), targetKey)
    then
        if taskDebug then
            taskDebug.triggerStage = "delay"
        end
        if previousKey ~= targetKey then
            ctx.releaseFire()
        end
        return
    end
    if WeaponPolicy.isFanFirearm(item) then
        ctx.releaseFire()
        local action =
            WeaponPolicy.revolverTriggerAction(item, target, targetDistance, ctx.itemClock())
        if state.held then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
        end
        if not action or not TriggerBot.hubReady(state, ctx.clock()) then
            return
        end
        state.nextAt = ctx.clock() + action.cooldown
        if action.kind == "fan" then
            ctx.aimClick()
        else
            ctx.click()
        end
        ctx.clearAimPlan()
        return
    end
    if WeaponPolicy.isChargedBow(item) then
        ctx.releaseFire()
        if not state.held then
            if not TriggerBot.hubReady(state, ctx.clock()) then
                return
            end
            if WeaponPolicy.bowQuickShotLethal(item, target) then
                state.nextAt = ctx.clock() + (item.Info.ShootCooldown or interval)
                ctx.click()
                ctx.clearAimPlan()
                return
            end
            state.held = true
            state.heldAt = ctx.clock()
            state.heldItem = item
            ctx.aimPress()
            return
        end
        if state.heldItem ~= item then
            ctx.aimRelease()
            state.held = false
            state.heldItem = nil
            state.nextAt = ctx.clock() + interval
            return
        end
        if ctx.clock() - state.heldAt + 1e-3 < WeaponPolicy.bowChargeTime(item, target) then
            return
        end

        ctx.aimRelease()
        state.held = false
        state.heldItem = nil
        state.nextAt = ctx.clock() + (item.Info.ChargeReleaseCooldown or interval)
        ctx.clearAimPlan()
        return
    end

    if state.held then
        ctx.aimRelease()
        state.held = false
        state.heldItem = nil
    end
    if WeaponPolicy.holdToFire(item) then
        if not WeaponPolicy.adsSettled(ctx.cameraController, item) then
            if taskDebug then
                taskDebug.triggerStage = "ads-gate"
            end
            ctx.releaseFire()
            return
        end
        if state.fireHeld and state.fireItem == item then
            if WeaponPolicy.repeatShootingInput(item) then
                ctx.press()
            else
                local fireClock = type(ctx.itemClock) == "function" and ctx.itemClock()
                    or ctx.clock()
                if TriggerBot.holdDropped(item, fireClock, 0) then
                    ctx.releaseFire()
                    state.fireHeld = true
                    state.fireItem = item
                    ctx.press()
                end
            end
            if taskDebug then
                taskDebug.triggerStage = "holding-fire"
            end
            return
        end
        if not TriggerBot.hubReady(state, ctx.clock()) then
            return
        end
        state.fireHeld = true
        state.fireItem = item
        ctx.press()
        if taskDebug then
            taskDebug.triggerStage = "pressed-fire"
        end
        ctx.clearAimPlan()
        return
    end

    ctx.releaseFire()
    local fireClock = type(ctx.itemClock) == "function" and ctx.itemClock() or ctx.clock()
    if
        not TriggerBot.weaponReady(item, fireClock) or not TriggerBot.hubReady(state, ctx.clock())
    then
        return
    end
    if not WeaponPolicy.adsSettled(ctx.cameraController, item) then
        return
    end

    ctx.click()
    -- nextAt is os.clock(); item._shoot_cooldown is tick(). Never copy that
    -- stamp across clocks or a pistol waits ~1.7e9 seconds for the next shot.
    state.nextAt = sprayCounter and ctx.clock() + TriggerBot.fireDelay(item, interval) or 0
    if taskDebug then
        taskDebug.triggerStage = "clicked-fire"
    end
    ctx.clearAimPlan()
end

return TriggerBot
]],
        ["games/rivals/libraries/CombatState.lua"] = [[local CombatState = {}

local function value(replica, key)
    if type(replica) ~= "table" then
        return nil
    end

    if type(replica.Get) == "function" then
        return replica:Get(key)
    end

    local data = replica.Data
    return type(data) == "table" and data[key] or nil
end

function CombatState.isRoundEligible(fighter, duel, loadoutOpen)
    if loadoutOpen == true then
        return false
    end

    return value(fighter, "IsInDuel") == true and value(duel, "Status") == "RoundStarted"
end

function CombatState.isCombatEligible(fighter, duel, loadoutOpen)
    if loadoutOpen == true then
        return false
    end

    if value(fighter, "IsInShootingRange") == true then
        return true
    end

    return CombatState.isRoundEligible(fighter, duel, false)
end

return CombatState
]],
        ["games/rivals/libraries/HookRuntime.lua"] = [[local ScopedAccuracy = require("../features/ScopedAccuracy")
local ShotPresentation = require("../features/ShotPresentation")
local SkipBlocks = require("../features/SkipBlocks")
local HookRuntime = {}
HookRuntime.__index = HookRuntime

local function supports(capabilities, capability)
    return table.find(capabilities or {}, capability) ~= nil
end

local NullPresentation = {}
function NullPresentation:refreshHook() end
function NullPresentation:clear() end
function NullPresentation:update()
    return false
end
function NullPresentation:getPresentedTarget()
    return nil
end
function NullPresentation:stop() end

local NullScoped = {}
function NullScoped:refreshHook() end
function NullScoped:stop() end

local NullSkip = {}
function NullSkip:refreshHook() end
function NullSkip:stop() end

function HookRuntime.new(options)
    local wantsShotAim = supports(options.capabilities, "shotAim")
    local wantsScoped = supports(options.capabilities, "alwaysScoped")
    local wantsSkip = supports(options.capabilities, "skipDeflect")
    if wantsShotAim or wantsScoped or wantsSkip then
        assert(options.hookFunction, "enabled RIVALS hook features require hookfunction")
        assert(options.restoreFunction, "enabled RIVALS hook features require restorefunction")
    end
    local presentation = NullPresentation
    if wantsShotAim then
        presentation = ShotPresentation.new(options.shotPresentation)
    end
    local scoped = NullScoped
    if wantsScoped then
        scoped = ScopedAccuracy.new(options.scopedAccuracy)
    end
    local skip = NullSkip
    if wantsSkip then
        skip = SkipBlocks.new(options.skipBlocks)
    end
    return setmetatable({ presentation = presentation, scoped = scoped, skip = skip }, HookRuntime)
end

function HookRuntime:refresh()
    self.presentation:refreshHook()
    self.scoped:refreshHook()
    self.skip:refreshHook()
end

function HookRuntime:stop()
    self.presentation:stop()
    self.scoped:stop()
    self.skip:stop()
end

return HookRuntime
]],
        ["games/rivals/libraries/ItemInput.lua"] = [[local ItemPolicy = require("./ItemPolicy")
local ItemInput = {}
ItemInput.__index = ItemInput

ItemInput.START_SHOOTING = "StartShooting"
ItemInput.FINISH_SHOOTING = "FinishShooting"
ItemInput.START_AIMING = "StartAiming"
ItemInput.FINISH_AIMING = "FinishAiming"
ItemInput.EQUIP_PRIMARY = "EquipPrimary"
ItemInput.EQUIP_SECONDARY = "EquipSecondary"

function ItemInput.equipAction(item)
    local info = item and item.Info
    if type(info) ~= "table" then
        return nil
    end
    if info.Class == "Secondary" then
        return ItemInput.EQUIP_SECONDARY
    end
    if info.Class == "Primary" then
        return ItemInput.EQUIP_PRIMARY
    end
    return nil
end

function ItemInput.dispatch(fighter, action)
    if
        type(fighter) ~= "table"
        or type(fighter.Input) ~= "function"
        or type(action) ~= "string"
        or action == ""
    then
        return false
    end
    local succeeded, result = pcall(fighter.Input, fighter, action)
    return succeeded and result ~= false
end

function ItemInput.new(getFighter)
    assert(type(getFighter) == "function", "RIVALS item input requires a fighter getter")
    return setmetatable({
        deflecting = false,
        fireHeld = false,
        aimHeld = false,
        getFighter = getFighter,
    }, ItemInput)
end

function ItemInput:_dispatch(action)
    return ItemInput.dispatch(self.getFighter(), action)
end

function ItemInput:canFire(item)
    return not self.deflecting or ItemPolicy.capabilities(item).bypassesDeflection
end

function ItemInput:fire()
    local fighter = self.getFighter()
    local item = fighter and fighter.EquippedItem
    if not fighter or not self:canFire(item) then
        self:releaseFire()
        return false
    end
    return self:_dispatch(ItemInput.START_SHOOTING)
end

function ItemInput:pressFire()
    if not self:fire() then
        return false
    end
    self.fireHeld = true
    return true
end

function ItemInput:releaseFire()
    if not self.fireHeld then
        return false
    end
    self:_dispatch(ItemInput.FINISH_SHOOTING)
    self.fireHeld = false
    return true
end

function ItemInput:pressAim()
    if not self:_dispatch(ItemInput.START_AIMING) then
        return false
    end
    self.aimHeld = true
    return true
end

function ItemInput:aim()
    return self:_dispatch(ItemInput.START_AIMING)
end

function ItemInput:releaseAim()
    if not self.aimHeld then
        return false
    end
    self:_dispatch(ItemInput.FINISH_AIMING)
    self.aimHeld = false
    return true
end

function ItemInput:releaseAll()
    self:releaseAim()
    self:releaseFire()
end

function ItemInput:setDeflecting(deflecting)
    self.deflecting = deflecting == true
    if self.deflecting then
        local fighter = self.getFighter()
        if not self:canFire(fighter and fighter.EquippedItem) then
            self:releaseFire()
        end
    end
end

function ItemInput:isFireHeld()
    return self.fireHeld
end

function ItemInput:isAimHeld()
    return self.aimHeld
end

return ItemInput
]],
        ["games/rivals/libraries/ItemPolicy.lua"] = [[local ItemPolicy = {}

local ENABLED = {
    cameraAim = true,
    silentAim = true,
    triggerBot = true,
}
local DISABLED = {
    cameraAim = false,
    silentAim = false,
    triggerBot = false,
}

local function info(item)
    return type(item) == "table" and type(item.Info) == "table" and item.Info or nil
end

local function positive(value)
    return type(value) == "number" and value > 0
end

function ItemPolicy.isThrowable(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and positive(itemInfo.ThrowMaxChargeTime)
        and positive(itemInfo.ThrowForceMax)
        and type(item.StartShooting) == "function"
        and type(item.FinishShooting) == "function"
end

function ItemPolicy.isBackstab(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and type(item._backstab_hash) == "number"
        and positive(itemInfo.CriticalDamage)
        and positive(itemInfo.HeavyAttackReach)
        and positive(itemInfo.HeavyAttackCooldown)
end

function ItemPolicy.isDualModeBlade(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and type(item.GetMobileInputSettings) == "function"
        and type(itemInfo.BladeModeMobileInputSettings) == "table"
        and type(itemInfo.MobileInputSettings) == "table"
        and positive(itemInfo.BladeReach)
        and positive(itemInfo.DashSpeed)
        and positive(itemInfo.DashDuration)
end

function ItemPolicy.isScoped(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and positive(itemInfo.AimScopePercent)
end

function ItemPolicy.isBurst(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and type(itemInfo.BurstCount) == "number" and itemInfo.BurstCount > 1
end

function ItemPolicy.hasDeflectCapability(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and positive(itemInfo.DeflectDuration)
        and positive(itemInfo.DeflectCooldown)
end

function ItemPolicy.isDeflector(item)
    return ItemPolicy.hasDeflectCapability(item) and type(item._deflect_hash) == "number"
end

function ItemPolicy.isActivelyDeflecting(item)
    if not ItemPolicy.hasDeflectCapability(item) then
        return false
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "FOVOffset")
        if succeeded and value == 5 then
            return true
        end
    end
    local data = item.Data
    return type(data) == "table" and data.FOVOffset == 5
end

function ItemPolicy.isRicochetWeapon(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and type(itemInfo.RaycastBounceCount) == "number"
        and itemInfo.RaycastBounceCount > 0
end

function ItemPolicy.isBouncingProjectile(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and itemInfo.IsProjectile == true
        and positive(itemInfo.ProjectileSpeed)
        and type(itemInfo.ProjectileMaxHits) == "number"
        and itemInfo.ProjectileMaxHits > 1
end

function ItemPolicy.isFanFirearm(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and positive(itemInfo.QuickShotCooldown)
        and positive(itemInfo.QuickShotSpread)
        and positive(itemInfo.ShootCooldown)
end

function ItemPolicy.isChargedBow(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and itemInfo.IsProjectile == true
        and positive(itemInfo.ChargeReleaseCooldown)
        and type(itemInfo.ChargeLevelTimestamps) == "table"
        and type(itemInfo.ChargeLevelDamageMultipliers) == "table"
end

function ItemPolicy.isTrueDamage(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and itemInfo.DealsTrueDamage == true
end

function ItemPolicy.capabilities(item)
    local itemInfo = info(item)
    if not itemInfo then
        return {
            attack = nil,
            bypassesDeflection = false,
            maxDoubleJumps = 0,
            targetedDamage = false,
        }
    end

    local maxDoubleJumps = type(itemInfo.MaxDoubleJumps) == "number"
            and math.max(0, itemInfo.MaxDoubleJumps)
        or 0
    local unarmedMobilityMelee = itemInfo.Type == "Melee"
        and itemInfo.Class == "Melee"
        and positive(itemInfo.AttackDamage)
        and type(item._attack_hash) == "number"
        and maxDoubleJumps > 0
    return {
        attack = itemInfo.Type == "Gun" and "gun" or itemInfo.Type == "Melee" and "melee" or nil,
        bypassesDeflection = itemInfo.DealsTrueDamage == true or unarmedMobilityMelee,
        maxDoubleJumps = maxDoubleJumps,
        targetedDamage = positive(itemInfo.ShootDamage)
            or positive(itemInfo.AttackDamage)
            or positive(itemInfo.CriticalDamage),
    }
end

function ItemPolicy.isAbsorber(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and positive(itemInfo.MaxAbsorption)
end

function ItemPolicy.isRevolver(item)
    return ItemPolicy.isFanFirearm(item)
end

function ItemPolicy.isChargedProjectile(item)
    return ItemPolicy.isChargedBow(item)
end

function ItemPolicy.isTrueDamageBurst(item)
    return ItemPolicy.isTrueDamage(item) and ItemPolicy.isBurst(item)
end

function ItemPolicy.isContinuous(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and positive(itemInfo.InternalUseCooldown)
end

function ItemPolicy.hasTargetedDamage(item)
    local itemInfo = info(item)
    if not itemInfo or ItemPolicy.isThrowable(item) then
        return false
    end
    return positive(itemInfo.ShootDamage)
        or positive(itemInfo.AttackDamage)
        or positive(itemInfo.CriticalDamage)
        or ItemPolicy.isDualModeBlade(item)
        or ItemPolicy.isContinuous(item)
end

function ItemPolicy.automationPolicy(item)
    return ItemPolicy.hasTargetedDamage(item) and ENABLED or DISABLED
end

return ItemPolicy
]],
        ["games/rivals/libraries/ModePolicy.lua"] = [[local ModePolicy = {}

local function replicatedValue(replica, key)
    if type(replica) ~= "table" then
        return nil
    end
    if type(replica.Get) == "function" then
        local succeeded, value = pcall(replica.Get, replica, key)
        if succeeded and value ~= nil then
            return value
        end
    end
    local data = replica.Data
    if type(data) == "table" then
        return data[key]
    end
    return nil
end

function ModePolicy.resolve(clientDuel)
    local isGunGame = replicatedValue(clientDuel, "IsGunGame")
    if isGunGame == true then
        return "gun-game"
    end
    if isGunGame == false then
        return "standard"
    end
    return nil
end

function ModePolicy.fromController(duelController, player)
    if type(duelController) ~= "table" or type(duelController.GetDuel) ~= "function" then
        return nil
    end
    local succeeded, clientDuel = pcall(duelController.GetDuel, duelController, player)
    if not succeeded then
        return nil
    end
    return ModePolicy.resolve(clientDuel)
end

function ModePolicy.isGunGame(clientDuel)
    return ModePolicy.resolve(clientDuel) == "gun-game"
end

function ModePolicy.controllerIsGunGame(duelController, player)
    return ModePolicy.fromController(duelController, player) == "gun-game"
end

return ModePolicy
]],
        ["games/rivals/libraries/Movement.lua"] = [[local Movement = {}
Movement.__index = Movement

function Movement.new(options)
    assert(options and options.controlsController, "RIVALS movement requires ControlsController")
    assert(options.mechanicsController, "RIVALS movement requires MechanicsController")
    assert(options.getFighter, "RIVALS movement requires a fighter getter")
    assert(options.getSettings, "RIVALS movement requires a settings getter")
    assert(options.isActive, "RIVALS movement requires an active-state predicate")
    assert(options.isInCombat, "RIVALS movement requires a combat-state predicate")
    assert(options.isInputCaptured, "RIVALS movement requires an input-capture predicate")
    assert(options.userInputService, "RIVALS movement requires UserInputService")

    return setmetatable({
        clock = options.clock or os.clock,
        controlsController = options.controlsController,
        getFighter = options.getFighter,
        getSettings = options.getSettings,
        isActive = options.isActive,
        isTaskActive = options.isTaskActive or options.isActive,
        isTaskInputCaptured = options.isTaskInputCaptured or options.isInputCaptured,
        isInCombat = options.isInCombat,
        isInputCaptured = options.isInputCaptured,
        infiniteJumpHeld = false,
        mechanicsController = options.mechanicsController,
        movement = nil,
        movementDirection = options.movementDirection,
        taskObstacleProbe = options.taskObstacleProbe,
        taskParkourProbe = options.taskParkourProbe,
        taskLineOfSightBlocked = options.taskLineOfSightBlocked,
        wallNoclipModel = nil,
        wallNoclipConnection = nil,
        wallNoclipParts = {},
        taskHumanoid = nil,
        taskCrouching = false,
        taskCrouchAt = 0,
        taskMobilityAt = 0,
        taskMobilityPhase = nil,
        taskParkourAt = 0,
        taskParkourCommit = nil,
        taskProgressAt = 0,
        taskProgressPosition = nil,
        taskOwnsSlide = false,
        taskStrafeSign = 1,
        taskStrafeUntil = 0,
        shouldSuppressJump = options.shouldSuppressJump,
        spawn = options.spawn or task.spawn,
        syntheticInputs = {},
        userInputService = options.userInputService,
    }, Movement)
end

function Movement:_toggleInput(input, enabled)
    local inputKey = typeof(input) == "EnumItem" and input.Name or tostring(input)
    local owned = self.syntheticInputs[inputKey]
    if enabled == true then
        if not owned then
            local previous = false
            if type(self.controlsController.IsToggled) == "function" then
                previous = self.controlsController:IsToggled(input) == true
            elseif type(self.controlsController._toggled_inputs) == "table" then
                previous = self.controlsController._toggled_inputs[input] == true
            end
            owned = {
                input = input,
                previous = previous,
            }
            self.syntheticInputs[inputKey] = owned
        end
        self.controlsController:ToggleInput(input, true)
    elseif owned then
        self.controlsController:ToggleInput(owned.input, owned.previous)
        self.syntheticInputs[inputKey] = nil
    end
end

function Movement:_clearInputs()
    local inputs = {}
    for _, owned in pairs(self.syntheticInputs) do
        table.insert(inputs, owned)
    end
    table.clear(self.syntheticInputs)
    for _, owned in ipairs(inputs) do
        self.controlsController:ToggleInput(owned.input, owned.previous)
    end
    if
        self.movement
        and self.movement.ownsSlide
        and self.mechanicsController.IsSliding
        and type(self.mechanicsController.StopSliding) == "function"
    then
        self.mechanicsController:StopSliding()
    end
end

function Movement:_advance(fighter)
    local movement = self.movement
    local function readState(name, fallback)
        local value = fighter[name]
        if type(value) == "function" then
            return value(fighter)
        end
        if type(value) == "boolean" then
            return value
        end
        return fallback
    end

    self:_toggleInput(Enum.KeyCode.LeftShift, true)
    if movement.phase == "jump" then
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, false)
        movement.phase = "airborne"
    elseif movement.phase == "airborne" then
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, false)
        if readState("IsGrounded", false) then
            movement.phase = "waitingSlide"
        end
    elseif movement.phase == "sliding" then
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, true)
        if self.mechanicsController.IsSliding == true or readState("IsSlidingLocally", false) then
            movement.slideWaitFrames = 0
            movement.slideFrames += 1
            if movement.slideFrames >= 2 then
                if self.shouldSuppressJump and self.shouldSuppressJump() then
                    self:_toggleInput(Enum.KeyCode.Space, false)
                    return
                end
                self:_toggleInput(Enum.KeyCode.Space, true)
                movement.ownsSlide = false
                self.mechanicsController:HighJump()
                movement.phase = "jump"
            end
        else
            movement.slideWaitFrames += 1
            if movement.slideWaitFrames >= 3 then
                movement.ownsSlide = false
                movement.phase = "waitingSlide"
            end
        end
    else
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, false)
        local grounded = readState("IsGrounded", true)
        local canSlide = readState("CanSlide", true)
        if grounded and canSlide then
            self:_toggleInput(Enum.KeyCode.C, true)
            movement.phase = "sliding"
            movement.slideFrames = 0
            movement.slideWaitFrames = 0
            movement.ownsSlide = true
            self.spawn(function()
                self.mechanicsController:Slide()
            end)
        end
    end
end

local function taskHazardRepulsion(position, hazards)
    local repulsion = Vector3.zero
    local nearby = false
    for _, hazard in ipairs(hazards or {}) do
        local hazardPosition = hazard.worldPosition
        local hazardous = hazard.tone == "danger"
            or hazard.label == "GRENADE"
            or hazard.label == "THROWABLE"
            or hazard.label == "FIRE"
        if hazardous and typeof(hazardPosition) == "Vector3" then
            local away =
                Vector3.new(position.X - hazardPosition.X, 0, position.Z - hazardPosition.Z)
            local hazardDistance = away.Magnitude
            local avoidanceRadius = hazard.label == "GRENADE" and 38
                or hazard.label == "THROWABLE" and 34
                or hazard.label == "FIRE" and 30
                or 28
            if hazardDistance > 0.01 and hazardDistance < avoidanceRadius then
                nearby = true
                repulsion += away.Unit * ((avoidanceRadius - hazardDistance) / avoidanceRadius) * 4
            end
        end
    end
    return repulsion, nearby
end

function Movement:stopTaskCombat()
    local humanoid = self.taskHumanoid
    self.taskHumanoid = nil
    if self.taskCrouching and type(self.mechanicsController.SetCrouching) == "function" then
        pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
    end
    self.taskCrouching = false
    self.taskCrouchAt = 0
    if self.taskOwnsSlide and type(self.mechanicsController.StopSliding) == "function" then
        pcall(self.mechanicsController.StopSliding, self.mechanicsController)
    end
    self.taskOwnsSlide = false
    self.taskMobilityPhase = nil
    self.taskMobilityAt = 0
    self.taskParkourAt = 0
    self.taskParkourCommit = nil
    self.taskProgressAt = 0
    self.taskProgressPosition = nil
    if humanoid and type(humanoid.Move) == "function" then
        pcall(humanoid.Move, humanoid, Vector3.zero, false)
    end
end

function Movement:updateTaskCombat(targetPosition, hazards, tactical, locomotionPlan)
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local humanoid = entity and entity.Humanoid
    local root = entity and (entity.RootPart or entity.HumanoidRootPart)
    if
        self.isTaskInputCaptured()
        or not self.isTaskActive()
        or not self.isInCombat()
        or not humanoid
        or type(humanoid.Move) ~= "function"
        or not root
        or typeof(root.Position) ~= "Vector3"
    then
        self:stopTaskCombat()
        return
    end
    if self.taskHumanoid and self.taskHumanoid ~= humanoid then
        self:stopTaskCombat()
    end
    self.taskHumanoid = humanoid
    local repulsion, hazardNearby = taskHazardRepulsion(root.Position, hazards)
    if typeof(targetPosition) ~= "Vector3" then
        if self.taskCrouching and type(self.mechanicsController.SetCrouching) == "function" then
            pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
            self.taskCrouching = false
        end
        humanoid:Move(repulsion.Magnitude > 0.01 and repulsion.Unit or Vector3.zero, false)
        return
    end
    local offset =
        Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
    local distance = offset.Magnitude
    if distance < 0.01 then
        humanoid:Move(Vector3.zero, false)
        return
    end
    local toward = offset.Unit
    local now = self.clock()
    local grounded = false
    if type(fighter.IsGrounded) == "function" then
        local succeeded, result = pcall(fighter.IsGrounded, fighter)
        grounded = succeeded and result == true
    elseif type(humanoid.FloorMaterial) == "EnumItem" then
        grounded = humanoid.FloorMaterial ~= Enum.Material.Air
    end
    local pushSniper = type(tactical) == "table" and tactical.pushSniper == true
    if now >= self.taskStrafeUntil then
        self.taskStrafeSign = -self.taskStrafeSign
        self.taskStrafeUntil = now + (pushSniper and 0.48 or 1.25)
    end
    local strafe = Vector3.new(-toward.Z, 0, toward.X) * self.taskStrafeSign
    local item = fighter and fighter.EquippedItem
    local info = item and item.Info
    local sustainedRifle = type(info) == "table"
        and info.Type == "Gun"
        and info.IsRaycast == true
        and type(info.ShootCooldown) == "number"
        and info.ShootCooldown <= 0.15
        and type(info.MaxAmmo) == "number"
        and info.MaxAmmo >= 15
    local lineBlocked = type(self.taskLineOfSightBlocked) == "function"
        and self.taskLineOfSightBlocked(root.Position, targetPosition, fighter) == true
    local avoidSniperPeek = type(tactical) == "table" and tactical.avoidSniperPeek == true
    local direction
    if pushSniper and distance < 7 then
        direction = (-toward * 0.75 + strafe * 0.65).Unit
    elseif avoidSniperPeek and not lineBlocked then
        -- Close through a hard lateral angle while the sniper is holding scope.
        direction = (toward * 0.12 + strafe).Unit
    elseif pushSniper and lineBlocked then
        -- Geometry is safety: use it to collapse distance rather than staying tucked.
        direction = (toward * 0.9 + strafe * 0.3).Unit
    elseif pushSniper then
        direction = (toward * 0.88 + strafe * 0.48).Unit
    elseif lineBlocked then
        -- Commit to one side of cover long enough to round the corner instead
        -- of oscillating against it, while retaining a little forward pressure.
        direction = (toward * 0.25 + strafe).Unit
    elseif sustainedRifle and distance > 52 then
        direction = (toward * 0.72 + strafe * 0.7).Unit
    elseif sustainedRifle and distance < 28 then
        direction = (-toward * 0.82 + strafe * 0.58).Unit
    elseif sustainedRifle then
        -- Assault rifles are strongest when holding the falloff edge and
        -- slicing the angle, rather than collapsing into melee distance.
        direction = (-toward * 0.12 + strafe).Unit
    elseif distance > 20 then
        direction = (toward * 0.82 + strafe * 0.58).Unit
    elseif distance < 8 then
        direction = (-toward * 0.8 + strafe * 0.6).Unit
    else
        direction = (toward * 0.35 + strafe).Unit
    end
    if repulsion.Magnitude > 0.01 then
        direction = (direction + repulsion).Unit
    end
    if type(locomotionPlan) == "table" and typeof(locomotionPlan.direction) == "Vector3" then
        direction = locomotionPlan.direction
        if repulsion.Magnitude > 0.01 then
            direction = (direction + repulsion).Unit
        end
    end
    local parkour
    if type(self.taskParkourProbe) == "function" then
        parkour = self.taskParkourProbe(root.Position, direction, fighter)
    end
    local obstacleBlocked = type(self.taskObstacleProbe) == "function"
        and self.taskObstacleProbe(root.Position, direction, fighter)
    local performedParkour = false
    local commit = self.taskParkourCommit
    if commit then
        local landingOffset =
            Vector3.new(commit.landing.X - root.Position.X, 0, commit.landing.Z - root.Position.Z)
        local landingDistance = landingOffset.Magnitude
        local elapsed = now - commit.startedAt
        if grounded and elapsed > 0.18 and landingDistance <= 3 then
            self.taskParkourCommit = nil
            commit = nil
            self.taskParkourAt = now + 0.35
        elseif grounded and elapsed > 0.8 and landingDistance > commit.startDistance - 0.5 then
            -- Takeoff failed; cancel only while grounded, matching Baritone's
            -- safe-to-cancel-before-running rule.
            self.taskParkourCommit = nil
            commit = nil
            direction = -toward
            self.taskParkourAt = now + 0.5
        else
            if landingDistance > 0.05 then
                direction = landingOffset.Unit
            end
            performedParkour = true
            local velocity = root.AssemblyLinearVelocity
            local descending = typeof(velocity) == "Vector3" and velocity.Y < -1
            local info = fighter.EquippedItem and fighter.EquippedItem.Info
            if
                not grounded
                and descending
                and not commit.usedDoubleJump
                and type(info) == "table"
                and type(info.MaxDoubleJumps) == "number"
                and info.MaxDoubleJumps > 0
                and type(self.mechanicsController.DoubleJumpRequest) == "function"
            then
                pcall(self.mechanicsController.DoubleJumpRequest, self.mechanicsController)
                commit.usedDoubleJump = true
            end
        end
    end
    if not commit and now >= self.taskParkourAt and type(parkour) == "table" then
        if
            grounded
            and typeof(parkour.jumpLanding) == "Vector3"
            and parkour.jumpConfidence == 1
        then
            local jumpMethod = type(self.mechanicsController.JumpRequest) == "function"
                    and self.mechanicsController.JumpRequest
                or self.mechanicsController.Jump
            if type(jumpMethod) == "function" then
                local landingOffset = Vector3.new(
                    parkour.jumpLanding.X - root.Position.X,
                    0,
                    parkour.jumpLanding.Z - root.Position.Z
                )
                self.taskParkourCommit = {
                    landing = parkour.jumpLanding,
                    startedAt = now,
                    startDistance = landingOffset.Magnitude,
                    usedDoubleJump = false,
                }
                if landingOffset.Magnitude > 0.05 then
                    direction = landingOffset.Unit
                end
                pcall(jumpMethod, self.mechanicsController)
                performedParkour = true
                commit = self.taskParkourCommit
                self.taskParkourAt = now + 0.2
            end
        elseif grounded and parkour.low and not parkour.middle then
            if type(self.mechanicsController.Jump) == "function" then
                pcall(self.mechanicsController.Jump, self.mechanicsController)
                performedParkour = true
                self.taskParkourAt = now + 0.42
            end
        elseif grounded and parkour.middle and not parkour.high and parkour.landing then
            if type(self.mechanicsController.HighJump) == "function" then
                pcall(self.mechanicsController.HighJump, self.mechanicsController)
                performedParkour = true
                self.taskParkourAt = now + 0.7
            end
        elseif not parkour.landing then
            obstacleBlocked = true
        end
    end
    if not commit and type(parkour) == "table" and not parkour.landing then
        -- Baritone-style edge recovery: probe both lateral routes for ground and
        -- retreat if neither side has a verified landing.
        local left = strafe.Unit
        local right = -left
        local leftProfile = self.taskParkourProbe(root.Position, left, fighter)
        local rightProfile = self.taskParkourProbe(root.Position, right, fighter)
        if type(leftProfile) == "table" and leftProfile.landing then
            direction = left
        elseif type(rightProfile) == "table" and rightProfile.landing then
            direction = right
        else
            direction = -toward
        end
        obstacleBlocked = false
    elseif obstacleBlocked and not performedParkour then
        local side = strafe.Unit
        if self.taskObstacleProbe(root.Position, side, fighter) then
            side = -side
        end
        direction = side
    end
    if self.taskProgressAt == 0 then
        self.taskProgressAt = now
        self.taskProgressPosition = root.Position
    elseif now - self.taskProgressAt >= 0.65 then
        local progressed = self.taskProgressPosition
            and (root.Position - self.taskProgressPosition).Magnitude >= 0.75
        if
            not commit
            and grounded
            and not progressed
            and distance > 10
            and now >= self.taskParkourAt
            and not (type(parkour) == "table" and not parkour.landing)
        then
            local recover = type(self.mechanicsController.JumpRequest) == "function"
                    and self.mechanicsController.JumpRequest
                or self.mechanicsController.Jump
            if type(recover) == "function" then
                pcall(recover, self.mechanicsController)
                performedParkour = true
                self.taskParkourAt = now + 0.8
                self.taskStrafeSign = -self.taskStrafeSign
            end
        end
        self.taskProgressAt = now
        self.taskProgressPosition = root.Position
    end
    local shouldUseMobility = (locomotionPlan == nil or locomotionPlan.slide == true)
        and not performedParkour
        and not (type(parkour) == "table" and not parkour.landing)
        and not avoidSniperPeek
        and not lineBlocked
        and not hazardNearby
        and distance > 24
    if self.taskMobilityPhase == "sliding" and now >= self.taskMobilityAt then
        if type(self.mechanicsController.HighJump) == "function" then
            pcall(self.mechanicsController.HighJump, self.mechanicsController)
        end
        self.taskOwnsSlide = false
        self.taskMobilityPhase = nil
        self.taskMobilityAt = now + 2.8
    elseif not self.taskMobilityPhase and shouldUseMobility and now >= self.taskMobilityAt then
        local canSlide = true
        if type(fighter.CanSlide) == "function" then
            local succeeded, result = pcall(fighter.CanSlide, fighter)
            canSlide = succeeded and result == true
        end
        if canSlide and type(self.mechanicsController.Slide) == "function" then
            if self.taskCrouching and type(self.mechanicsController.SetCrouching) == "function" then
                pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
                self.taskCrouching = false
            end
            pcall(self.mechanicsController.Slide, self.mechanicsController)
            self.taskOwnsSlide = true
            self.taskMobilityPhase = "sliding"
            self.taskMobilityAt = now + 0.16
        else
            self.taskMobilityAt = now + 0.5
        end
    end

    local shouldCrouchSpam = sustainedRifle
        and not avoidSniperPeek
        and self.taskMobilityPhase == nil
        and not lineBlocked
        and not hazardNearby
        and distance >= 18
        and distance <= 75
        and type(self.mechanicsController.SetCrouching) == "function"
    if shouldCrouchSpam and now >= self.taskCrouchAt then
        self.taskCrouching = not self.taskCrouching
        pcall(self.mechanicsController.SetCrouching, self.mechanicsController, self.taskCrouching)
        self.taskCrouchAt = now + (self.taskCrouching and 0.22 or 0.38)
    elseif not shouldCrouchSpam and self.taskCrouching then
        pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
        self.taskCrouching = false
        self.taskCrouchAt = now + 0.25
    end
    humanoid:Move(direction, false)
end

function Movement:stopWallNoclip()
    if self.wallNoclipConnection then
        self.wallNoclipConnection:Disconnect()
        self.wallNoclipConnection = nil
    end
    for part, original in pairs(self.wallNoclipParts) do
        if typeof(part) == "Instance" and part.Parent then
            part.CanCollide = original
        end
    end
    table.clear(self.wallNoclipParts)
    self.wallNoclipModel = nil
end

function Movement:updateWallNoclip(settings)
    settings = settings or self.getSettings()
    if settings.wallNoclip ~= true then
        self:stopWallNoclip()
        return
    end
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local model = entity and entity.Model
    if typeof(model) ~= "Instance" then
        self:stopWallNoclip()
        return
    end
    if model ~= self.wallNoclipModel then
        self:stopWallNoclip()
        self.wallNoclipModel = model
        local function track(descendant)
            if descendant:IsA("BasePart") and self.wallNoclipParts[descendant] == nil then
                self.wallNoclipParts[descendant] = descendant.CanCollide
                descendant.CanCollide = false
            end
        end
        for _, descendant in ipairs(model:GetDescendants()) do
            track(descendant)
        end
        self.wallNoclipConnection = model.DescendantAdded:Connect(track)
    end
    -- RIVALS may restore character collision during its own physics update.
    -- Reassert only cached character parts; no descendant traversal occurs here.
    for part in pairs(self.wallNoclipParts) do
        if part.Parent and part.CanCollide then
            part.CanCollide = false
        end
    end
end

function Movement:updateInfiniteJump(settings)
    settings = settings or self.getSettings()
    local held = self.userInputService:IsKeyDown(Enum.KeyCode.Space) == true
    if
        settings.infiniteJump == true
        and held
        and not self.infiniteJumpHeld
        and not self.isInputCaptured()
        and type(self.mechanicsController.DoubleJump) == "function"
    then
        pcall(self.mechanicsController.DoubleJump, self.mechanicsController)
    end
    self.infiniteJumpHeld = settings.infiniteJump == true and held
end

function Movement:stop()
    self:stopTaskCombat()
    if self.movement then
        self:_clearInputs()
        self.movement = nil
    end
end

function Movement:update(settings)
    settings = settings or self.getSettings()
    if settings.bhop ~= true then
        self:stop()
        return
    end

    local fighter = self.getFighter()
    local direction = self.movementDirection and self.movementDirection()
    local isMoving = typeof(direction) == "Vector3" and direction.Magnitude > 0.01
    if direction == nil then
        isMoving = self.userInputService:IsKeyDown(Enum.KeyCode.W)
            or self.userInputService:IsKeyDown(Enum.KeyCode.A)
            or self.userInputService:IsKeyDown(Enum.KeyCode.S)
            or self.userInputService:IsKeyDown(Enum.KeyCode.D)
    end
    if not isMoving or self.isInputCaptured() or not self.isActive() or not self.isInCombat() then
        self:stop()
        return
    end

    if not self.movement or self.movement.fighter ~= fighter then
        self:stop()
        self.movement = {
            fighter = fighter,
            phase = "waitingSlide",
            slideFrames = 0,
            slideWaitFrames = 0,
        }
    end
    self:_advance(fighter)
end

return Movement
]],
        ["games/rivals/libraries/ProjectileAim.lua"] = [[local ItemPolicy = require("./ItemPolicy")
local ProjectileAim = {}

local RICOCHET_BOUNCES = 2
local RICOCHET_MAX_DISTANCE = 2048
local RICOCHET_REDIRECT_ANGLE = math.rad(7.5)
local RICOCHET_REDIRECT_RADIUS = 128
local RICOCHET_SURFACE_OFFSET = 0.05
local SPLASH_TRACE_STEPS = 12
local SLINGSHOT_STEP = 1 / 20
local SLINGSHOT_TARGET_RADIUS = 2.5

function ProjectileAim.reflectDirection(direction, normal)
    return (direction - normal * (2 * direction:Dot(normal))).Unit
end

function ProjectileAim.reflectPoint(point, planePosition, planeNormal)
    return point - planeNormal * (2 * (point - planePosition):Dot(planeNormal))
end

local function withinRedirectAngle(direction, targetDirection, maxAngle)
    return direction:Dot(targetDirection) >= math.cos(maxAngle)
end

local function clearToTarget(origin, target, raycast)
    local displacement = target - origin
    if displacement.Magnitude <= RICOCHET_SURFACE_OFFSET then
        return true
    end

    local result = raycast(origin, displacement)
    return result == nil
        or (result.Position - origin).Magnitude
            >= displacement.Magnitude - RICOCHET_SURFACE_OFFSET
end

function ProjectileAim.traceRicochet(
    origin,
    direction,
    target,
    raycast,
    maxBounces,
    redirectAngle,
    maxDistance
)
    local position = origin
    local rayDirection = direction.Unit
    local path = { origin }
    maxBounces = maxBounces or RICOCHET_BOUNCES
    redirectAngle = redirectAngle or RICOCHET_REDIRECT_ANGLE
    maxDistance = maxDistance or RICOCHET_MAX_DISTANCE

    for bounce = 1, maxBounces do
        local result = raycast(position, rayDirection * maxDistance)
        if not result or not result.Normal or not result.Position then
            return nil
        end

        table.insert(path, result.Position)
        rayDirection = ProjectileAim.reflectDirection(rayDirection, result.Normal)
        position = result.Position + rayDirection * RICOCHET_SURFACE_OFFSET

        local targetOffset = target - position
        if targetOffset.Magnitude > RICOCHET_SURFACE_OFFSET then
            local targetDirection = targetOffset.Unit
            local exactPath = rayDirection:Dot(targetDirection) >= math.cos(math.rad(0.25))
            local redirectable = targetOffset.Magnitude <= RICOCHET_REDIRECT_RADIUS
                and withinRedirectAngle(rayDirection, targetDirection, redirectAngle)
            if (exactPath or redirectable) and clearToTarget(position, target, raycast) then
                table.insert(path, target)
                return {
                    bounces = bounce,
                    direction = direction.Unit,
                    path = path,
                }
            end
        end
    end

    return nil
end

local function ricochetProbeDirections(forward)
    local reference = math.abs(forward:Dot(Vector3.yAxis)) < 0.95 and Vector3.yAxis or Vector3.xAxis
    local right = forward:Cross(reference).Unit
    local up = right:Cross(forward).Unit
    local directions = { forward }

    for _, angle in ipairs({ math.rad(30), math.rad(60) }) do
        for step = 0, 7 do
            local azimuth = 2 * math.pi * step / 8
            local radial = right * math.cos(azimuth) + up * math.sin(azimuth)
            table.insert(directions, (forward * math.cos(angle) + radial * math.sin(angle)).Unit)
        end
    end
    return directions
end

function ProjectileAim.solveRicochet(origin, target, raycast, maxDistance)
    maxDistance = maxDistance or RICOCHET_MAX_DISTANCE
    local forward = (target - origin).Unit

    for _, probeDirection in ipairs(ricochetProbeDirections(forward)) do
        local sampledSurface = raycast(origin, probeDirection * maxDistance)
        if sampledSurface and sampledSurface.Normal and sampledSurface.Position then
            local image =
                ProjectileAim.reflectPoint(target, sampledSurface.Position, sampledSurface.Normal)
            local oneBounceDirection = (image - origin).Unit
            local oneBounce = ProjectileAim.traceRicochet(
                origin,
                oneBounceDirection,
                target,
                raycast,
                RICOCHET_BOUNCES,
                RICOCHET_REDIRECT_ANGLE,
                maxDistance
            )
            if oneBounce then
                return oneBounce
            end

            local firstSurface = raycast(origin, oneBounceDirection * maxDistance)
            if firstSurface and firstSurface.Normal and firstSurface.Position then
                local firstReflection =
                    ProjectileAim.reflectDirection(oneBounceDirection, firstSurface.Normal)
                local secondOrigin = firstSurface.Position
                    + firstReflection * RICOCHET_SURFACE_OFFSET
                local secondSurface = raycast(secondOrigin, firstReflection * maxDistance)
                if secondSurface and secondSurface.Normal and secondSurface.Position then
                    local secondImage = ProjectileAim.reflectPoint(
                        target,
                        secondSurface.Position,
                        secondSurface.Normal
                    )
                    local firstImage = ProjectileAim.reflectPoint(
                        secondImage,
                        firstSurface.Position,
                        firstSurface.Normal
                    )
                    local twoBounce = ProjectileAim.traceRicochet(
                        origin,
                        (firstImage - origin).Unit,
                        target,
                        raycast,
                        RICOCHET_BOUNCES,
                        RICOCHET_REDIRECT_ANGLE,
                        maxDistance
                    )
                    if twoBounce and twoBounce.bounces == RICOCHET_BOUNCES then
                        return twoBounce
                    end
                end
            end
        end
    end

    return nil
end

function ProjectileAim.isSplashProjectile(item)
    local info = item and item.Info
    return type(info) == "table"
        and info.DamageType == "Splash"
        and info.IsProjectile == true
        and type(info.ProjectileSpeed) == "number"
        and info.ProjectileSpeed > 0
        and type(info.ShootExplosionRadius) == "number"
        and info.ShootExplosionRadius > 0
end

function ProjectileAim.isDirectProjectile(item)
    local info = item and item.Info
    return type(info) == "table"
        and info.IsProjectile == true
        and info.IsRaycast ~= true
        and info.DamageType ~= "Splash"
        and (info.ProjectileMaxHits or 1) <= 1
        and (info.RaycastBounceCount or 0) == 0
        and not ItemPolicy.isBouncingProjectile(item)
end

local function ballisticDirection(origin, target, speed, gravity)
    local offset = target - origin
    local horizontal = Vector3.new(offset.X, 0, offset.Z)
    local horizontalDistance = horizontal.Magnitude
    if gravity <= 1e-6 or horizontalDistance <= 1e-6 then
        return offset.Unit, offset.Magnitude / speed
    end

    local speedSquared = speed * speed
    local discriminant = speedSquared * speedSquared
        - gravity
            * (gravity * horizontalDistance * horizontalDistance + 2 * offset.Y * speedSquared)
    if discriminant < 0 then
        return nil
    end

    local angle =
        math.atan((speedSquared - math.sqrt(discriminant)) / (gravity * horizontalDistance))
    local cosine = math.cos(angle)
    if cosine <= 1e-6 then
        return nil
    end

    local direction = (horizontal.Unit * cosine + Vector3.yAxis * math.sin(angle)).Unit
    return direction, horizontalDistance / (speed * cosine)
end

local function traceProjectile(origin, direction, speed, acceleration, flightTime, raycast)
    local previous = origin
    local previousTime = 0
    for step = 1, SPLASH_TRACE_STEPS do
        local time = flightTime * step / SPLASH_TRACE_STEPS
        local position = origin + direction * (speed * time) + acceleration * (0.5 * time * time)
        local result = raycast(previous, position - previous)
        if result and result.Position then
            local segmentLength = (position - previous).Magnitude
            local impactAlpha = segmentLength > 1e-6
                    and math.clamp((result.Position - previous).Magnitude / segmentLength, 0, 1)
                or 0
            return result.Position, previousTime + (time - previousTime) * impactAlpha
        end
        previous = position
        previousTime = time
    end
    return nil
end

local function clearBlastToTarget(impact, target, raycast)
    local displacement = target - impact
    if displacement.Magnitude <= RICOCHET_SURFACE_OFFSET then
        return true
    end
    return clearToTarget(impact + displacement.Unit * RICOCHET_SURFACE_OFFSET, target, raycast)
end

local function observationVelocity(observation)
    local part = observation and observation.part
    local velocity = part and (part.AssemblyLinearVelocity or part.Velocity)
    if velocity then
        return velocity
    end

    local character = observation and observation.character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and (root.AssemblyLinearVelocity or root.Velocity) or Vector3.zero
end

local function directionFrame(origin, direction)
    local reference = math.abs(direction:Dot(Vector3.yAxis)) < 0.999 and Vector3.yAxis
        or Vector3.xAxis
    local right = direction:Cross(reference).Unit
    local up = right:Cross(direction).Unit

    return CFrame.fromMatrix(origin, right, up, -direction)
end

local function projectileLaunchOrigin(cameraOrigin, direction, info)
    local spawnOffset = info and info.ProjectileSpawnOffset
    if typeof(spawnOffset) ~= "CFrame" or direction.Magnitude <= 1e-6 then
        return cameraOrigin
    end

    return (directionFrame(cameraOrigin, direction) * spawnOffset).Position
end

local function projectileCameraDirection(projectileDirection, info)
    local spawnOffset = info and info.ProjectileSpawnOffset
    if
        typeof(spawnOffset) ~= "CFrame"
        or spawnOffset.Rotation == CFrame.identity
        or projectileDirection.Magnitude <= 1e-6
    then
        return projectileDirection
    end

    return (directionFrame(Vector3.zero, projectileDirection) * spawnOffset.Rotation:Inverse()).LookVector
end

function ProjectileAim.solveProjectileAim(origin, observation, info, worldGravity, launchDelay)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    if not targetPosition or type(speed) ~= "number" or speed <= 0 then
        return nil
    end

    local targetVelocity = observationVelocity(observation)
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local lifetime = type(info.ProjectileLifetime) == "number" and info.ProjectileLifetime
        or math.huge
    local delay = math.clamp(type(launchDelay) == "number" and launchDelay or 0, 0, 0.25)
    local predictedPosition = targetPosition + targetVelocity * delay
    local launchOrigin = origin
    local direction
    local flightTime

    for _ = 1, 6 do
        local projectileDirection
        projectileDirection, flightTime =
            ballisticDirection(launchOrigin, predictedPosition, speed, gravity)
        if not projectileDirection or not flightTime or flightTime > lifetime then
            return nil
        end
        predictedPosition = targetPosition + targetVelocity * (delay + flightTime)
        direction = projectileCameraDirection(projectileDirection, info)
        launchOrigin = projectileLaunchOrigin(origin, direction, info)
    end

    local projectileDirection
    projectileDirection, flightTime =
        ballisticDirection(launchOrigin, predictedPosition, speed, gravity)
    if not projectileDirection or not flightTime or flightTime > lifetime then
        return nil
    end
    direction = projectileCameraDirection(projectileDirection, info)
    launchOrigin = projectileLaunchOrigin(origin, direction, info)
    return {
        direction = direction,
        flightTime = flightTime,
        launchOrigin = launchOrigin,
        predictedPosition = predictedPosition,
        projectileDirection = projectileDirection,
    }
end

function ProjectileAim.solveSplashAim(
    origin,
    observation,
    info,
    raycast,
    worldGravity,
    networkLatency
)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    local radius = info and info.ShootExplosionRadius
    if
        not targetPosition
        or type(speed) ~= "number"
        or speed <= 0
        or type(radius) ~= "number"
        or radius <= 0
        or type(raycast) ~= "function"
    then
        return nil
    end

    local velocity = observationVelocity(observation)
    local lifetime = type(info.ProjectileLifetime) == "number" and info.ProjectileLifetime
        or math.huge
    local latency = math.clamp(type(networkLatency) == "number" and networkLatency or 0, 0, 0.25)
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local predictedPosition = targetPosition
    for _ = 1, 4 do
        local _, travelTime = ballisticDirection(origin, predictedPosition, speed, gravity)
        if not travelTime or travelTime > lifetime then
            return nil
        end
        local updatedPosition = targetPosition + velocity * (travelTime + latency)
        if (updatedPosition - predictedPosition).Magnitude <= 0.25 then
            predictedPosition = updatedPosition
            break
        end
        predictedPosition = updatedPosition
    end

    local directions = {}
    local function addDirection(direction)
        if direction.Magnitude <= 1e-6 then
            return
        end
        direction = direction.Unit
        for _, existing in ipairs(directions) do
            if existing:Dot(direction) > 0.99 then
                return
            end
        end
        table.insert(directions, direction)
    end

    local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontalVelocity.Magnitude > 1 then
        local forward = horizontalVelocity.Unit
        addDirection(forward)
        addDirection(-forward)
        addDirection(forward:Cross(Vector3.yAxis))
        addDirection(-forward:Cross(Vector3.yAxis))
    end
    addDirection(Vector3.new(0, -1, 0))
    addDirection((predictedPosition - origin).Unit)
    addDirection(-(predictedPosition - origin).Unit)

    local candidates = {}
    local searchDistance = math.max(radius - (info.ProjectileRaycastRadius or 0), 0.5)
    for _, direction in ipairs(directions) do
        local result = raycast(predictedPosition, direction * searchDistance)
        if result and result.Position then
            table.insert(candidates, {
                distance = (result.Position - predictedPosition).Magnitude,
                position = result.Position,
            })
        end
    end
    table.sort(candidates, function(left, right)
        return left.distance < right.distance
    end)

    local acceleration = Vector3.new(0, -gravity, 0)
    for _, candidate in ipairs(candidates) do
        local direction, flightTime = ballisticDirection(origin, candidate.position, speed, gravity)
        if direction and flightTime and flightTime <= lifetime then
            local impact, impactTime =
                traceProjectile(origin, direction, speed, acceleration, flightTime + 1e-3, raycast)
            local targetAtImpact = impactTime and targetPosition + velocity * (impactTime + latency)
            if
                impact
                and targetAtImpact
                and (impact - targetAtImpact).Magnitude <= radius
                and clearBlastToTarget(impact, targetAtImpact, raycast)
            then
                return {
                    direction = direction,
                    flightTime = impactTime,
                    impact = impact,
                    predictedPosition = targetAtImpact,
                }
            end
        end
    end

    return nil
end

function ProjectileAim.isSplashSolutionCurrent(origin, solution, info, raycast, worldGravity)
    local speed = info and info.ProjectileSpeed
    local impact = solution and solution.impact
    local flightTime = solution and solution.flightTime
    if
        not impact
        or not solution.direction
        or not solution.predictedPosition
        or type(speed) ~= "number"
        or speed <= 0
        or type(flightTime) ~= "number"
        or flightTime <= 0
    then
        return false
    end

    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local currentImpact = traceProjectile(
        origin,
        solution.direction,
        speed,
        Vector3.new(0, -gravity, 0),
        flightTime + 1e-3,
        raycast
    )
    return currentImpact
            and (currentImpact - impact).Magnitude <= RICOCHET_SURFACE_OFFSET
            and clearBlastToTarget(currentImpact, solution.predictedPosition, raycast)
        or false
end

local function distanceToSegment(point, segmentStart, segmentEnd)
    local segment = segmentEnd - segmentStart
    local lengthSquared = segment:Dot(segment)
    if lengthSquared <= 1e-6 then
        return (point - segmentStart).Magnitude
    end
    local alpha = math.clamp((point - segmentStart):Dot(segment) / lengthSquared, 0, 1)
    return (point - (segmentStart + segment * alpha)).Magnitude
end

function ProjectileAim.simulateBouncingProjectile(
    origin,
    direction,
    target,
    info,
    raycast,
    worldGravity
)
    local speed = info.ProjectileSpeed
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local lifetime = info.ProjectileLifetime or 5
    local maximumBounces = math.max((info.ProjectileMaxHits or 1) - 1, 0)
    local restitution = info.ProjectileBounceRestitution or 0.5
    local velocity = direction.Unit * speed
    local acceleration = Vector3.new(0, -gravity, 0)
    local position = origin
    local elapsed = 0
    local bounces = 0
    local path = { origin }

    while elapsed < lifetime do
        local step = math.min(SLINGSHOT_STEP, lifetime - elapsed)
        local nextPosition = position + velocity * step + acceleration * (0.5 * step * step)
        local result = raycast(position, nextPosition - position)
        local segmentEnd = result and result.Position or nextPosition
        if
            bounces > 0
            and distanceToSegment(target, position, segmentEnd) <= SLINGSHOT_TARGET_RADIUS
        then
            table.insert(path, target)
            return {
                bounces = bounces,
                direction = direction.Unit,
                path = path,
            }
        end

        if result and result.Position and result.Normal then
            bounces += 1
            table.insert(path, result.Position)
            if bounces > maximumBounces then
                return nil
            end

            local impactVelocity = velocity + acceleration * step
            local normalVelocity = result.Normal * impactVelocity:Dot(result.Normal)
            local tangentVelocity = impactVelocity - normalVelocity
            velocity = tangentVelocity - normalVelocity * restitution
            if velocity.Magnitude <= 1e-3 then
                return nil
            end
            position = result.Position + velocity.Unit * RICOCHET_SURFACE_OFFSET
        else
            position = nextPosition
            velocity += acceleration * step
            table.insert(path, position)
        end
        elapsed += step
    end

    return nil
end

function ProjectileAim.solveBouncingProjectile(origin, observation, info, raycast, worldGravity)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    if not targetPosition or type(speed) ~= "number" or speed <= 0 then
        return nil
    end

    local velocity = observationVelocity(observation)
    local travelTime = (targetPosition - origin).Magnitude / speed
    local predictedTarget = targetPosition + velocity * travelTime
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local baseDirection = ballisticDirection(origin, predictedTarget, speed, gravity)
    if not baseDirection then
        return nil
    end

    local candidates = { baseDirection }
    local straightRicochet = ProjectileAim.solveRicochet(origin, predictedTarget, raycast)
    if straightRicochet then
        table.insert(candidates, straightRicochet.direction)
    end

    local reference = math.abs(baseDirection:Dot(Vector3.yAxis)) < 0.95 and Vector3.yAxis
        or Vector3.xAxis
    local right = baseDirection:Cross(reference).Unit
    local up = right:Cross(baseDirection).Unit
    local searchAngle = math.rad(12)
    for step = 0, 7 do
        local azimuth = 2 * math.pi * step / 8
        local radial = right * math.cos(azimuth) + up * math.sin(azimuth)
        table.insert(
            candidates,
            (baseDirection * math.cos(searchAngle) + radial * math.sin(searchAngle)).Unit
        )
    end

    for _, candidate in ipairs(candidates) do
        local solution = ProjectileAim.simulateBouncingProjectile(
            origin,
            candidate,
            predictedTarget,
            info,
            raycast,
            worldGravity
        )
        if solution then
            solution.predictedPosition = predictedTarget
            return solution
        end
    end
    return nil
end

function ProjectileAim.projectTrajectory(camera, path)
    local segments = {}
    for index = 1, #path - 1 do
        local fromPoint, fromVisible = camera:WorldToViewportPoint(path[index])
        local toPoint, toVisible = camera:WorldToViewportPoint(path[index + 1])
        if fromVisible and toVisible and fromPoint.Z > 0 and toPoint.Z > 0 then
            table.insert(segments, {
                from = Vector2.new(fromPoint.X, fromPoint.Y),
                to = Vector2.new(toPoint.X, toPoint.Y),
            })
        end
    end
    return segments
end

ProjectileAim.MAX_DISTANCE = RICOCHET_MAX_DISTANCE

return ProjectileAim
]],
        ["games/rivals/libraries/Targeting.lua"] = [[local Targeting = {}

local BODY_PART_NAMES = { "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart" }
local HEAD_CROWN_FRACTIONS = { 0.45, 0.35, 0.25 }
local HEAD_HITBOX_NAMES = { "HitboxHead", "HitboxHeadSmall" }
local HEAD_RAY_HIT_NAMES = {
    Head = true,
    HitboxHead = true,
    HitboxHeadSmall = true,
    PhysicalHitboxHead = true,
}

local function observationKey(observation)
    return observation and (observation.character or observation.player or observation.part) or nil
end

function Targeting.closestObservation(observations, origin, options)
    if not origin then
        return nil
    end

    options = options or {}
    local nearest
    local nearestDistance = math.huge
    for _, observation in ipairs(observations or {}) do
        local position = type(options.resolvePosition) == "function"
                and options.resolvePosition(observation)
            or observation.position
        local screenDistance = observation.screenDistance
        local insideFov = options.maxScreenDistance == nil
            or type(screenDistance) == "number" and screenDistance <= options.maxScreenDistance
        local eligible = options.isEligible == nil
            or options.isEligible(observation.player, observation.character)
        if
            position
            and insideFov
            and eligible
            and (options.includeBlocked or observation.visible)
        then
            local distance = (position - origin).Magnitude
            if
                (options.maxDistance == nil or distance <= options.maxDistance)
                and distance < nearestDistance
            then
                nearest = observation
                nearestDistance = distance
            end
        end
    end
    return nearest
end

function Targeting.selectObservation(observations, currentKey, nearest)
    if currentKey then
        for _, observation in ipairs(observations or {}) do
            if observationKey(observation) == currentKey then
                local retained = nearest({ observation })
                if retained then
                    return retained, currentKey
                end
                break
            end
        end
    end

    local selected = nearest(observations or {})
    return selected, observationKey(selected)
end

function Targeting.visibleHeadPoint(observation, origin, raycast)
    local character = observation and observation.character
    local visualHead = character and character.FindFirstChild and character:FindFirstChild("Head")
    local head
    if character and character.FindFirstChild then
        for _, name in ipairs(HEAD_HITBOX_NAMES) do
            local candidate = character:FindFirstChild(name, true)
            if
                candidate
                and candidate.GetAttribute
                and candidate:GetAttribute("IsCritical") == true
            then
                head = candidate
                break
            end
        end
    end
    head = head or visualHead
    if not head then
        return nil, nil
    end
    if not origin or type(raycast) ~= "function" or not head.CFrame or not head.Size then
        return head.Position, head
    end

    local function exposed(point)
        local result = raycast(origin, point - origin)
        local instance = result and result.Instance
        if not instance or instance == head then
            return true
        end
        return instance.IsDescendantOf
            and instance:IsDescendantOf(character)
            and (
                HEAD_RAY_HIT_NAMES[instance.Name] == true
                or instance.GetAttribute and instance:GetAttribute("IsCritical") == true
            )
    end

    if exposed(head.Position) then
        return head.Position, head
    end
    for _, fraction in ipairs(HEAD_CROWN_FRACTIONS) do
        local point = head.CFrame:PointToWorldSpace(Vector3.new(0, head.Size.Y * fraction, 0))
        if exposed(point) then
            return point, head
        end
    end
    return nil, head
end

function Targeting.visibleBodyPoint(observation, origin, raycast)
    local character = observation and observation.character
    if not character or not character.FindFirstChild then
        return nil, nil
    end

    for _, partName in ipairs(BODY_PART_NAMES) do
        local part = character:FindFirstChild(partName)
        local position = part and part.Position
        if position then
            if not origin or type(raycast) ~= "function" then
                return position, part
            end

            local result = raycast(origin, position - origin)
            local instance = result and result.Instance
            local critical = instance
                and (
                    instance.Name == "Head"
                    or instance.GetAttribute and instance:GetAttribute("IsCritical") == true
                )
            if
                not instance
                or instance == part
                or not critical
                    and instance.IsDescendantOf
                    and instance:IsDescendantOf(character)
            then
                return position, part
            end
        end
    end
    return nil, nil
end

function Targeting.applyAimRates(observation, settings, random, options)
    if not observation or not observation.position then
        return observation
    end

    random = random or math.random
    local missRate = math.clamp(settings.missRate or 0, 0, 100)
    if missRate > 0 and random() * 100 < missRate then
        local character = observation.character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return observation
        end

        local result = table.clone(observation)
        local width = root.Size and root.Size.X or 2
        result.intentionalMiss = true
        result.part = root
        result.position = observation.position + root.CFrame.RightVector * (width * 0.5 + 2.5)
        return result
    end

    local character = observation.character
    local head = character and character.FindFirstChild and character:FindFirstChild("Head")
    local headshotRate = math.clamp(settings.headshotRate or 0, 0, 100)
    local preferHead = head and headshotRate > 0 and random() * 100 < headshotRate
    if preferHead then
        local result = table.clone(observation)
        result.intentionalMiss = false
        result.preferHead = true
        local position, targetHead = Targeting.visibleHeadPoint(
            observation,
            options and options.origin,
            options and options.raycast
        )
        if position then
            result.part = targetHead
            result.position = position
            return result
        end
    end

    local bodyPosition, bodyPart = Targeting.visibleBodyPoint(
        observation,
        options and options.origin,
        options and options.raycast
    )
    if bodyPosition and bodyPart then
        if observation.part == bodyPart and observation.position == bodyPosition then
            return observation
        end

        local result = table.clone(observation)
        result.intentionalMiss = false
        result.preferHead = preferHead == true
        result.part = bodyPart
        result.position = bodyPosition
        return result
    end

    return observation
end

function Targeting.rotationToward(origin, target)
    local direction = (target - origin).Unit
    return Vector2.new(math.asin(direction.Y), math.atan2(-direction.X, -direction.Z))
end

function Targeting.smoothRotation(current, target, smoothness, deltaTime)
    smoothness = math.clamp(smoothness or 0, 0, 100)
    if smoothness <= 0 or not current then
        return target
    end

    local speed = math.max(1.5, 30 * (1 - smoothness / 100))
    local alpha = 1 - math.exp(-speed * math.max(deltaTime or 1 / 60, 0))
    local yawDelta = (target.Y - current.Y + math.pi) % (math.pi * 2) - math.pi
    return Vector2.new(current.X + (target.X - current.X) * alpha, current.Y + yawDelta * alpha)
end

function Targeting.humanRotation(current, target, smoothness, deltaTime, state)
    if not current then
        return target
    end

    state = state or {}
    local stepTime = math.max(deltaTime or 1 / 60, 1 / 240)
    local smooth = math.clamp(smoothness or 0, 0, 100)
    local yawError = (target.Y - current.Y + math.pi) % (math.pi * 2) - math.pi
    local error = Vector2.new(target.X - current.X, yawError)
    local targetMotion = Vector2.zero
    if state.lastTarget then
        targetMotion = Vector2.new(
            target.X - state.lastTarget.X,
            (target.Y - state.lastTarget.Y + math.pi) % (math.pi * 2) - math.pi
        )
    end
    state.lastTarget = target

    local targetSpeed = targetMotion.Magnitude / stepTime
    local baseSpeed = math.max(1.5, 30 * (1 - smooth / 100))
    local trackingSpeed = baseSpeed + math.min(targetSpeed * 0.8, 24)
    local alpha = 1 - math.exp(-trackingSpeed * stepTime)
    local curve = Vector2.zero
    if error.Magnitude > 1e-6 then
        local curveMagnitude = math.min(error.Magnitude * 0.08, math.rad(0.35))
        local curveSign = state.curveSign or 1
        curve = Vector2.new(-error.Y, error.X).Unit * curveMagnitude * curveSign
    end

    local step = error * alpha + targetMotion * 0.55 + curve * alpha
    local maximumStep = error.Magnitude * 0.85
    if step.Magnitude > maximumStep and maximumStep > 0 then
        step = step.Unit * maximumStep
    end
    return current + step
end

return Targeting
]],
        ["games/rivals/libraries/WeaponPolicy.lua"] = [[local ItemPolicy = require("./ItemPolicy")
local WeaponPolicy = {}

local AUTOMATIC_SHOOT_COOLDOWN = 0.15
local CROUCH_SPREAD_MULTIPLIER = 0.75
local SNIPER_NOSCOPE_MIN_HIT_CHANCE = 0.4
local TRIGGER_DAMAGE_RETENTION = 0.9
local TRIGGER_INTERVAL = 0.1
local NATIVE_HEAD_PROXY_NAMES = {
    Head = true,
    HitboxHead = true,
    HitboxHeadSmall = true,
    PhysicalHitboxHead = true,
}
function WeaponPolicy.itemName(item)
    if not item then
        return nil
    end

    local info = item.Info
    if type(info) == "table" then
        return info.DisplayName or info.Name or info.ItemName or item.Name
    end
    return item.Name
end

function WeaponPolicy.isBackstabKnife(item)
    return ItemPolicy.isBackstab(item)
end

function WeaponPolicy.automationPolicy(item)
    return ItemPolicy.automationPolicy(item)
end

function WeaponPolicy.isScoped(item)
    return ItemPolicy.isScoped(item)
end

function WeaponPolicy.isAiming(item)
    if not item then
        return false
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "IsAiming")
        if succeeded and type(value) == "boolean" then
            return value
        end
    end
    local data = item.Data
    return type(data) == "table" and data.IsAiming == true
end

function WeaponPolicy.isDualModeBlade(item)
    return ItemPolicy.isDualModeBlade(item)
end

function WeaponPolicy.isDeflector(item)
    return ItemPolicy.isDeflector(item)
end

function WeaponPolicy.isActivelyDeflecting(item)
    return ItemPolicy.isActivelyDeflecting(item)
end

function WeaponPolicy.isRevolver(item)
    return ItemPolicy.isRevolver(item)
end

function WeaponPolicy.isChargedProjectile(item)
    return ItemPolicy.isChargedProjectile(item)
end

function WeaponPolicy.isTrueDamageBurst(item)
    return ItemPolicy.isTrueDamageBurst(item)
end

function WeaponPolicy.isAbsorber(item)
    return ItemPolicy.isAbsorber(item)
end

function WeaponPolicy.isRicochetWeapon(item)
    return ItemPolicy.isRicochetWeapon(item)
end

function WeaponPolicy.isBouncingProjectile(item)
    return ItemPolicy.isBouncingProjectile(item)
end

function WeaponPolicy.isFanFirearm(item)
    return ItemPolicy.isFanFirearm(item)
end

function WeaponPolicy.isChargedBow(item)
    return ItemPolicy.isChargedBow(item)
end

function WeaponPolicy.isTrueDamage(item)
    return ItemPolicy.isTrueDamage(item)
end

function WeaponPolicy.ammo(item)
    if not item then
        return nil
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "Ammo")
        if succeeded and type(value) == "number" then
            return value
        end
    end
    local data = item.Data
    return type(data) == "table" and type(data.Ammo) == "number" and data.Ammo or nil
end

function WeaponPolicy.itemLabel(item)
    local name = WeaponPolicy.itemName(item)
    local info = item and item.Info
    local maximum = type(info) == "table" and info.MaxAbsorption or nil
    if not name or type(maximum) ~= "number" then
        return name
    end

    local current
    if type(item.Get) == "function" then
        local ok, value = pcall(item.Get, item, "Ammo")
        current = ok and value or nil
    end
    if type(current) ~= "number" and type(item.Data) == "table" then
        current = item.Data.Ammo
    end
    if type(current) ~= "number" then
        return name
    end

    return ("%s (%s/%s)"):format(
        name,
        tostring(math.floor(math.max(0, current))),
        tostring(maximum)
    )
end

function WeaponPolicy.isCriticalPart(part)
    if not part then
        return false
    end

    if NATIVE_HEAD_PROXY_NAMES[part.Name] == true then
        return true
    end

    local getAttribute = part.GetAttribute
    if type(getAttribute) ~= "function" then
        return false
    end

    local succeeded, isCritical = pcall(getAttribute, part, "IsCritical")
    return succeeded and isCritical == true
end

function WeaponPolicy.backstabPlan(localPosition, observation, info, acquisitionDistance)
    local health = observation and observation.health
    local character = observation and observation.character
    local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
    if
        type(health) ~= "number"
        or type(info) ~= "table"
        or type(info.CriticalDamage) ~= "number"
        or health > info.CriticalDamage
        or not targetRoot
        or not targetRoot.CFrame
    then
        return nil
    end

    local offset = localPosition - targetRoot.Position
    local reach = info.HeavyAttackReach or info.AttackReach
    if type(reach) ~= "number" or offset.Magnitude <= 1e-3 then
        return nil
    end

    local rearDirection = offset.Unit
    local rearDot = targetRoot.CFrame.LookVector:Dot(rearDirection)
    local ready = offset.Magnitude <= reach and rearDot <= 0.1
    local acquisitionReach = math.min(24, math.max(16, reach * 2.5))
    if type(acquisitionDistance) == "number" then
        acquisitionReach = math.max(acquisitionReach, acquisitionDistance)
    end
    if not ready and offset.Magnitude > acquisitionReach then
        return nil
    end

    local approachDistance = math.clamp(reach * 0.65, 3.5, 5)
    local approachPosition = targetRoot.Position - targetRoot.CFrame.LookVector * approachDistance
    return {
        aimPosition = ready and observation.position or approachPosition,
        approachPosition = approachPosition,
        movePosition = approachPosition,
        path = {
            localPosition,
            approachPosition,
            targetRoot.Position,
        },
        ready = ready,
        rearDot = rearDot,
    }
end

function WeaponPolicy.backstabReady(localPosition, observation, info)
    local plan = WeaponPolicy.backstabPlan(localPosition, observation, info)
    return plan ~= nil and plan.ready == true
end

function WeaponPolicy.backstabTriggerReady(fighter, item, target, allowAirborne)
    local entity = fighter and fighter.Entity
    local localRoot = entity and entity.RootPart
    local isGrounded = fighter and fighter.IsGrounded
    local grounded
    if type(isGrounded) == "function" then
        local succeeded, value = pcall(isGrounded, fighter)
        grounded = succeeded and value == true
    elseif type(isGrounded) == "boolean" then
        grounded = isGrounded
    end
    if
        not localRoot
        or typeof(localRoot.Position) ~= "Vector3"
        or allowAirborne ~= true and grounded ~= true
        or type(item) ~= "table"
        or type(item.Info) ~= "table"
        or not target
        or target.aimSettled ~= true
    then
        return false
    end

    return WeaponPolicy.backstabReady(localRoot.Position, target, item.Info)
end

function WeaponPolicy.adsSettled(cameraController, item)
    local info = item and item.Info
    local data = item and item.Data
    if
        type(info) ~= "table"
        or info.AimScopePercent == nil
        or type(data) ~= "table"
        or data.IsAiming ~= true
    then
        return true
    end

    if type(item.IsFullyAiming) == "function" then
        local succeeded, fullyAiming = pcall(item.IsFullyAiming, item)
        if succeeded then
            return fullyAiming == true
        end
    end

    local spring = cameraController._fov_weapons_spring
    return spring ~= nil
        and type(spring.Value) == "number"
        and type(spring.Target) == "number"
        and math.abs(spring.Value - spring.Target) <= 0.5
end

function WeaponPolicy.sniperTriggerReady(
    cameraController,
    item,
    observation,
    distance,
    crouching,
    forceScoped
)
    if not ItemPolicy.isScoped(item) then
        return true
    end

    local info = item and item.Info
    local data = item and item.Data
    if type(info) ~= "table" or type(data) ~= "table" then
        return false
    end
    if forceScoped == true then
        return type(info.AimScopePercent) == "number" and info.AimScopePercent > 0
    end
    if data.IsAiming == true then
        return WeaponPolicy.adsSettled(cameraController, item)
    end

    local part = observation and observation.part
    local size = part and part.Size
    local spread = info.ShootSpread
    if
        type(distance) ~= "number"
        or distance <= 0
        or typeof(size) ~= "Vector3"
        or type(spread) ~= "number"
        or spread <= 0
    then
        return false
    end

    local targetRadius = math.min(size.X, size.Y) * 0.5
    if targetRadius <= 0 then
        return false
    end

    local maximumSpread = math.rad(spread) * (crouching and CROUCH_SPREAD_MULTIPLIER or 1)
    local targetAngularRadius = math.atan(targetRadius / distance)
    return targetAngularRadius / maximumSpread >= SNIPER_NOSCOPE_MIN_HIT_CHANCE
end

function WeaponPolicy.holdToFire(item)
    local info = item and item.Info
    local inputSpamming = type(info) == "table" and info.InputSpammingEnabled
    if
        type(inputSpamming) ~= "table"
        or type(inputSpamming.StartShooting) ~= "number"
        or info.IsProjectile == true
    then
        return false
    end

    return type(info.InternalUseCooldown) == "number"
        or type(info.ShootCooldown) == "number"
            and info.ShootCooldown <= AUTOMATIC_SHOOT_COOLDOWN
end

function WeaponPolicy.repeatShootingInput(item)
    local info = item and item.Info
    return WeaponPolicy.holdToFire(item)
        and type(info) == "table"
        and type(info.ShootCooldown) == "number"
        and type(info.InternalUseCooldown) ~= "number"
end

function WeaponPolicy.gunbladeMode(item)
    if not ItemPolicy.isDualModeBlade(item) then
        return nil
    end

    local info = item and item.Info
    local getMobileInputSettings = item and item.GetMobileInputSettings
    local bladeSettings = type(info) == "table" and info.BladeModeMobileInputSettings
    local gunSettings = type(info) == "table" and info.MobileInputSettings
    if
        type(getMobileInputSettings) ~= "function"
        or type(bladeSettings) ~= "table"
        or type(gunSettings) ~= "table"
    then
        return nil
    end

    local succeeded, currentSettings = pcall(getMobileInputSettings, item)
    if not succeeded or type(currentSettings) ~= "table" then
        return nil
    end
    if currentSettings == bladeSettings then
        return "blade"
    end
    if currentSettings == gunSettings then
        return "gun"
    end

    if bladeSettings.Aim ~= gunSettings.Aim then
        if currentSettings.Aim == bladeSettings.Aim then
            return "blade"
        end
        if currentSettings.Aim == gunSettings.Aim then
            return "gun"
        end
    end
    return nil
end

function WeaponPolicy.gunbladeDashRange(item)
    if not ItemPolicy.isDualModeBlade(item) then
        return nil
    end

    local info = item and item.Info
    local reach = info and info.BladeReach
    local dashSpeed = info and info.DashSpeed
    local dashDuration = info and info.DashDuration
    if type(reach) ~= "number" or type(dashSpeed) ~= "number" or type(dashDuration) ~= "number" then
        return nil
    end
    return reach + dashSpeed * dashDuration
end

local function gunbladeState(item, target, phase, readyAt, dashReadyAt)
    return {
        dashReadyAt = dashReadyAt or 0,
        item = item,
        phase = phase,
        readyAt = readyAt,
        target = target,
    }
end

local function gunbladeQuickAttackReady(item)
    local canQuickAttack = item and item.CanQuickAttack
    if type(canQuickAttack) ~= "function" then
        return true
    end
    local succeeded, ready = pcall(canQuickAttack, item)
    return succeeded and ready == true
end

function WeaponPolicy.gunbladeTriggerAction(state, item, target, distance, now)
    local mode = WeaponPolicy.gunbladeMode(item)
    local dashRange = WeaponPolicy.gunbladeDashRange(item)
    local info = item and item.Info
    local bladeReach = info and info.BladeReach
    if
        not mode
        or not target
        or type(distance) ~= "number"
        or type(now) ~= "number"
        or type(dashRange) ~= "number"
        or distance > dashRange
        or type(bladeReach) ~= "number"
    then
        return nil, nil
    end

    if type(state) ~= "table" or state.item ~= item or state.target ~= target then
        state = nil
    end
    local phase = state and state.phase
    local readyAt = state and state.readyAt or 0
    local dashReadyAt = state and state.dashReadyAt or 0
    local transitionCooldown = type(info.TransitionCooldown) == "number" and info.TransitionCooldown
        or 0

    if mode == "gun" then
        if phase == "awaitBlade" or (phase == "awaitGun" and now < readyAt) then
            return state, nil
        end

        local shootCooldown = type(info.ShootCooldown) == "number" and info.ShootCooldown
            or TRIGGER_INTERVAL
        return gunbladeState(
            item,
            target,
            "awaitBlade",
            now + math.max(shootCooldown, transitionCooldown),
            dashReadyAt
        ),
            {
                cooldown = shootCooldown,
                kind = "shoot",
            }
    end

    if phase == "strike" then
        if now < readyAt or distance > bladeReach or not gunbladeQuickAttackReady(item) then
            return state, nil
        end
    elseif phase == "awaitGun" then
        return state, nil
    else
        if now < dashReadyAt or (phase == "awaitBlade" and now < readyAt) then
            return state, nil
        end

        local dashCooldown = type(info.DashCooldown) == "number" and info.DashCooldown
            or TRIGGER_INTERVAL
        return gunbladeState(item, target, "strike", now, now + dashCooldown),
            {
                cooldown = dashCooldown,
                kind = "dash",
            }
    end

    local bladeCooldown = type(info.BladeCooldown) == "number" and info.BladeCooldown
        or TRIGGER_INTERVAL
    return gunbladeState(
        item,
        target,
        "awaitGun",
        now + math.max(bladeCooldown, transitionCooldown),
        dashReadyAt
    ),
        {
            cooldown = bladeCooldown,
            kind = "strike",
        }
end

function WeaponPolicy.damageAtDistance(item, observation, distance)
    local info = item and item.Info
    local startDistance = info
        and (info.DamageFallOffStartDist or info.RaycastDamageDropoffStartDistance)
    local endDistance = info and (info.DamageFallOffEndDist or info.RaycastDamageDropoffEndDistance)
    local minimumMultiplier = info
        and (info.DamageFallOffMultiplier or info.RaycastDamageDropoffMultiplier)
    local part = observation and observation.part
    local baseDamage = WeaponPolicy.isCriticalPart(part) and info and info.CriticalDamage
        or info and info.ShootDamage
    if type(baseDamage) ~= "number" then
        return nil
    end
    if
        type(startDistance) ~= "number"
        or type(endDistance) ~= "number"
        or endDistance <= startDistance
        or type(minimumMultiplier) ~= "number"
        or type(distance) ~= "number"
    then
        return baseDamage
    end

    local alpha = math.clamp((distance - startDistance) / (endDistance - startDistance), 0, 1)
    return baseDamage * (1 + (minimumMultiplier - 1) * alpha)
end

function WeaponPolicy.finishingDamage(item, observation, distance)
    local damage = WeaponPolicy.damageAtDistance(item, observation, distance)
    local info = item and item.Info
    if type(damage) ~= "number" or type(info) ~= "table" then
        return nil
    end

    if ItemPolicy.isBurst(item) and type(info.BurstCount) == "number" then
        damage *= math.max(1, info.BurstCount)
    end

    local multipliers = info.ChargeLevelDamageMultipliers
    if type(multipliers) == "table" then
        local maximum = 1
        for _, multiplier in ipairs(multipliers) do
            if type(multiplier) == "number" then
                maximum = math.max(maximum, multiplier)
            end
        end
        damage *= maximum
    end
    return damage
end

function WeaponPolicy.triggerDamageReady(item, observation, distance)
    if ItemPolicy.isBurst(item) then
        return true
    end

    local info = item and item.Info
    local sustainedRifle = type(info) == "table"
        and info.Type == "Gun"
        and info.IsRaycast == true
        and type(info.ShootCooldown) == "number"
        and info.ShootCooldown <= 0.15
        and type(info.MaxAmmo) == "number"
        and info.MaxAmmo >= 15
    if sustainedRifle then
        -- Automatic rifles gain more from sustained pressure than from waiting
        -- for near-full per-shot damage at the edge of falloff.
        return true
    end
    local startDistance = info
        and (info.DamageFallOffStartDist or info.RaycastDamageDropoffStartDistance)
    local endDistance = info and (info.DamageFallOffEndDist or info.RaycastDamageDropoffEndDistance)
    local minimumMultiplier = info
        and (info.DamageFallOffMultiplier or info.RaycastDamageDropoffMultiplier)
    if
        type(info) ~= "table"
        or type(startDistance) ~= "number"
        or type(endDistance) ~= "number"
        or type(minimumMultiplier) ~= "number"
    then
        return true
    end

    local part = observation and observation.part
    local baseDamage = WeaponPolicy.isCriticalPart(part) and info.CriticalDamage or info.ShootDamage
    local damage = WeaponPolicy.damageAtDistance(item, observation, distance)
    local health = observation and observation.health
    return type(baseDamage) == "number"
        and type(damage) == "number"
        and (
            damage >= baseDamage * TRIGGER_DAMAGE_RETENTION
            or type(health) == "number" and damage >= health
        )
end

function WeaponPolicy.bowChargeTime(item, observation)
    local info = item and item.Info
    local timestamps = info and info.ChargeLevelTimestamps
    local multipliers = info and info.ChargeLevelDamageMultipliers
    if type(timestamps) ~= "table" or type(multipliers) ~= "table" then
        return 0
    end

    local part = observation and observation.part
    local baseDamage = WeaponPolicy.isCriticalPart(part) and info.CriticalDamage or info.ShootDamage
    local health = observation and observation.health
    if type(baseDamage) ~= "number" or type(health) ~= "number" then
        return timestamps[#timestamps] or 0
    end

    for level, timestamp in ipairs(timestamps) do
        local multiplier = multipliers[level]
        if
            type(timestamp) == "number"
            and type(multiplier) == "number"
            and baseDamage * multiplier >= health
        then
            return timestamp
        end
    end
    return timestamps[#timestamps] or 0
end

function WeaponPolicy.bowQuickShotLethal(item, observation)
    local info = item and item.Info
    if type(info) ~= "table" then
        return false
    end

    local part = observation and observation.part
    local damage = WeaponPolicy.isCriticalPart(part) and info.CriticalDamage or info.ShootDamage
    local health = observation and observation.health
    if type(damage) ~= "number" or type(health) ~= "number" or damage < health then
        return false
    end

    local shootCooldown = info.ShootCooldown
    local releaseCooldown = info.ChargeReleaseCooldown
    return type(shootCooldown) == "number"
        and type(releaseCooldown) == "number"
        and shootCooldown + TRIGGER_INTERVAL < releaseCooldown
end

local function revolverCanShoot(item, now)
    local data = item and item.Data
    local ammo = type(data) == "table" and data.Ammo
    if type(now) ~= "number" or type(ammo) ~= "number" or ammo <= 0 then
        return false
    end

    if item.IsEquipping == true then
        return false
    end
    if type(item._shoot_cooldown) == "number" and now < item._shoot_cooldown then
        return false
    end

    local reloadCooldown = item._reload_cooldown
    if type(reloadCooldown) ~= "number" or now >= reloadCooldown then
        return true
    end

    local cancelCooldown = item._reload_cancel_cooldown
    local cancelExpiration = item._reload_cancel_expiration
    return type(cancelCooldown) == "number"
        and now >= cancelCooldown
        and type(cancelExpiration) == "number"
        and now < cancelExpiration
end

local function targetFitsRevolverSpread(observation, distance, spread)
    if type(spread) ~= "number" or type(distance) ~= "number" then
        return false
    end

    local part = observation and observation.part
    local size = part and part.Size
    local targetRadius = 1
    if size and type(size.X) == "number" and type(size.Y) == "number" then
        targetRadius = math.min(size.X, size.Y) * 0.5
    end
    return math.tan(math.rad(spread)) * distance <= targetRadius
end

function WeaponPolicy.revolverTriggerAction(item, observation, distance, now)
    local info = item and item.Info
    if
        not item
        or not ItemPolicy.isRevolver(item)
        or type(info) ~= "table"
        or not revolverCanShoot(item, now)
    then
        return nil
    end

    local quickCooldown = info.QuickShotCooldown
    local preciseCooldown = info.ShootCooldown
    if type(quickCooldown) ~= "number" or type(preciseCooldown) ~= "number" then
        return nil
    end

    local preciseLockedUntil = item._is_revolver_quick_shooting
    local preciseReady = type(preciseLockedUntil) ~= "number" or now >= preciseLockedUntil
    local preciseFits = targetFitsRevolverSpread(observation, distance, info.ShootSpread)
    local preciseDamage = WeaponPolicy.damageAtDistance(item, observation, distance)
    local health = observation and observation.health
    if
        preciseReady
        and preciseFits
        and type(preciseDamage) == "number"
        and type(health) == "number"
        and preciseDamage >= health
    then
        return {
            cooldown = preciseCooldown,
            kind = "precise",
        }
    end

    if targetFitsRevolverSpread(observation, distance, info.QuickShotSpread) then
        return {
            cooldown = quickCooldown,
            kind = "fan",
        }
    end
    if preciseReady and preciseFits then
        return {
            cooldown = preciseCooldown,
            kind = "precise",
        }
    end
    return nil
end

return WeaponPolicy
]],
        ["games/rivals/tasks/PracticeTaskDriver.lua"] = [[local PracticeTaskDriver = {}
PracticeTaskDriver.__index = PracticeTaskDriver

local PRACTICE_TASKS = {
    Beginner1 = "range",
    Beginner2 = "targets",
    Beginner3 = "slide",
    Beginner4 = "equip",
    Beginner5 = "dash",
    Beginner6 = "grenade",
}

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        connection:Disconnect()
    end
end

function PracticeTaskDriver.new(options)
    assert(
        options and type(options.getFighter) == "function",
        "Practice driver requires a fighter getter"
    )
    assert(type(options.actions) == "table", "Practice driver requires normal action boundaries")
    local self = setmetatable({
        actions = options.actions,
        getFighter = options.getFighter,
        isInRange = options.isInRange,
        delay = options.delay or (task and task.delay or nil),
        cancelDelay = options.cancelDelay or (task and task.cancel or nil),
        retryDelay = options.retryDelay or 3,
        maxAttempts = options.maxAttempts or 3,
        onChanged = options.onChanged,
        task = nil,
        taskSignature = nil,
        state = "idle",
        attempts = 0,
        paused = false,
        stopped = false,
        retryHandle = nil,
        generation = 0,
        connections = {},
    }, PracticeTaskDriver)
    return self
end

function PracticeTaskDriver:_notify()
    if type(self.onChanged) == "function" then
        pcall(self.onChanged, self:status())
    end
end

function PracticeTaskDriver:_release()
    if type(self.actions.releaseAll) == "function" then
        pcall(self.actions.releaseAll)
    end
end

function PracticeTaskDriver:_cancelRetry()
    local handle = self.retryHandle
    self.retryHandle = nil
    if handle == nil then
        return
    end
    if type(self.cancelDelay) == "function" then
        pcall(self.cancelDelay, handle)
    elseif type(handle) == "table" and type(handle.Cancel) == "function" then
        pcall(handle.Cancel, handle)
    end
end

function PracticeTaskDriver:_inRange()
    if type(self.isInRange) == "function" then
        return self.isInRange() == true
    end
    local fighter = self.getFighter()
    local data = fighter and fighter.Data
    return type(data) == "table" and data.IsInShootingRange == true
end

function PracticeTaskDriver:_equippedName()
    local fighter = self.getFighter()
    local item = fighter and fighter.EquippedItem
    return item and (item.Name or item.name) or nil
end

function PracticeTaskDriver:_schedule()
    if type(self.delay) ~= "function" or self.attempts >= self.maxAttempts then
        if self.attempts >= self.maxAttempts then
            self.state = "retry-exhausted"
            self:_notify()
        end
        return
    end
    local generation = self.generation
    local handle
    handle = self.delay(self.retryDelay, function()
        if handle == self.retryHandle then
            self.retryHandle = nil
        end
        if self.stopped or self.paused or generation ~= self.generation then
            return
        end
        self:_reconcile()
    end)
    self.retryHandle = handle
end

function PracticeTaskDriver:_dispatch(name, ...)
    if self.attempts >= self.maxAttempts then
        self.state = "retry-exhausted"
        self:_notify()
        return
    end
    local action = self.actions[name]
    if type(action) ~= "function" then
        self.state = "unsupported-boundary"
        self:_notify()
        return
    end
    self.attempts += 1
    local ok, accepted = pcall(action, ...)
    if not ok or accepted == false then
        self.state = "action-rejected"
        self:_schedule()
        self:_notify()
        return
    end
    self.state = "waiting-native"
    self:_schedule()
    self:_notify()
end

function PracticeTaskDriver:_reconcile()
    if self.stopped or self.paused then
        return
    end
    local taskRecord = self.task
    local kind = taskRecord and PRACTICE_TASKS[taskRecord.name]
    if not kind then
        self.state = "idle"
        self:_notify()
        return
    end
    if not self:_inRange() then
        self:_dispatch("enterRange")
        return
    end
    if kind == "range" then
        self.state = "waiting-native"
        self:_notify()
        return
    end
    if kind == "targets" then
        self.state = "target-combat"
        self:_notify()
        return
    end
    if kind == "slide" then
        self:_dispatch("slide")
        return
    end
    if kind == "equip" then
        if self:_equippedName() == "Scythe" then
            self.state = "waiting-native"
            self:_notify()
        else
            self:_dispatch("equip", "Scythe")
        end
        return
    end
    if kind == "dash" then
        if self:_equippedName() ~= "Scythe" then
            self:_dispatch("equip", "Scythe")
        else
            self:_dispatch("secondary")
        end
        return
    end
    if kind == "grenade" then
        if self:_equippedName() ~= "Grenade" then
            self:_dispatch("equip", "Grenade")
        else
            self:_dispatch("primary")
        end
    end
end

function PracticeTaskDriver:setTask(taskRecord)
    if self.stopped then
        return
    end
    local signature = taskRecord
            and (tostring(taskRecord.name) .. ":" .. tostring(taskRecord.progress or 0))
        or nil
    self:_cancelRetry()
    self.generation += 1
    self:_release()
    if signature ~= self.taskSignature then
        self.attempts = 0
    end
    self.task = taskRecord
    self.taskSignature = signature
    self:_reconcile()
end

function PracticeTaskDriver:isCombatActive()
    return not self.stopped
        and not self.paused
        and self.task ~= nil
        and self.task.name == "Beginner2"
        and self:_inRange()
end

function PracticeTaskDriver:status()
    return { state = self.state, attempts = self.attempts, task = self.task }
end

function PracticeTaskDriver:setChanged(callback)
    self.onChanged = callback
end

function PracticeTaskDriver:pause()
    if self.stopped or self.paused then
        return
    end
    self.paused = true
    self:_cancelRetry()
    self.generation += 1
    self:_release()
    self.state = "paused"
    self:_notify()
end

function PracticeTaskDriver:resume()
    if self.stopped or not self.paused then
        return
    end
    self.paused = false
    self:_reconcile()
end

function PracticeTaskDriver:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_cancelRetry()
    self.generation += 1
    self:_release()
    self.task = nil
    self.state = "stopped"
    self:_notify()
    for _, connection in ipairs(self.connections) do
        disconnect(connection)
    end
    table.clear(self.connections)
end

return PracticeTaskDriver
]],
        ["games/rivals/tasks/TaskCamera.lua"] = [[local TaskCamera = {}

function TaskCamera.commit(camera, rotation)
    if not camera or typeof(rotation) ~= "Vector2" then
        return false
    end
    local frame = camera.CFrame
    if typeof(frame) ~= "CFrame" then
        return false
    end
    camera.CFrame = CFrame.new(frame.Position)
        * CFrame.Angles(0, rotation.Y, 0)
        * CFrame.Angles(rotation.X, 0, 0)
    return true
end

return TaskCamera
]],
        ["games/rivals/tasks/TaskCounterPolicy.lua"] = [[local ItemPolicy = require("../libraries/ItemPolicy")
local TaskCounterPolicy = {}
TaskCounterPolicy.__index = TaskCounterPolicy

function TaskCounterPolicy.isDefensiveItem(item)
    return ItemPolicy.isDeflector(item) or ItemPolicy.isAbsorber(item)
end

function TaskCounterPolicy.hasShieldOrKatana(items)
    for key, value in pairs(items or {}) do
        local item = type(value) == "table" and value or type(key) == "table" and key or nil
        if TaskCounterPolicy.isDefensiveItem(item) then
            return true
        end
    end
    return false
end

function TaskCounterPolicy.shouldSelectSpray(items)
    return TaskCounterPolicy.hasShieldOrKatana(items)
end

function TaskCounterPolicy.shouldForceSpray(item, opponentEquippedItem)
    return ItemPolicy.capabilities(item).bypassesDeflection
        and TaskCounterPolicy.isDefensiveItem(opponentEquippedItem)
end

function TaskCounterPolicy.new(options)
    return setmetatable({
        clock = options and options.clock or os.clock,
        candidate = false,
        candidateAt = 0,
        active = false,
    }, TaskCounterPolicy)
end

function TaskCounterPolicy:update(equippedItem)
    local now = self.clock()
    local candidate = TaskCounterPolicy.isDefensiveItem(equippedItem)
    if candidate ~= self.candidate then
        self.candidate = candidate
        self.candidateAt = now
    end
    local hold = candidate and 1.25 or 0.75
    if candidate ~= self.active and now - self.candidateAt >= hold then
        self.active = candidate
    end
    return self.active
end

return TaskCounterPolicy
]],
        ["games/rivals/tasks/TaskFarmRuntime.lua"] = [[local TaskPolicy = require("./TaskPolicy")

local TaskFarmRuntime = {}
TaskFarmRuntime.__index = TaskFarmRuntime

local function read(replica, key)
    if type(replica) ~= "table" then
        return nil
    end
    if type(replica.Get) == "function" then
        local ok, result = pcall(replica.Get, replica, key)
        if ok then
            return result
        end
    end
    if type(replica.Data) == "table" then
        return replica.Data[key]
    end
    return replica[key]
end

local function connect(connections, signal, callback)
    if signal and type(signal.Connect) == "function" then
        local ok, connection = pcall(signal.Connect, signal, callback)
        if ok and connection then
            table.insert(connections, connection)
            return connection
        end
    end
    return nil
end

local function changedSignal(replica, key)
    if type(replica) ~= "table" then
        return nil
    end
    for _, method in ipairs({
        "GetDataChangedSignal",
        "GetChangedSignal",
        "GetPropertyChangedSignal",
    }) do
        if type(replica[method]) == "function" then
            local ok, result = pcall(replica[method], replica, key)
            if ok and result then
                return result
            end
        end
    end
    return replica.Changed
end

function TaskFarmRuntime.new(options)
    assert(options and options.taskLibrary, "Task farm requires TaskLibrary")
    assert(options.playerDataController, "Task farm requires PlayerDataController")
    assert(options.matchmakingController, "Task farm requires MatchmakingController")
    local defaultDelay = task and task.delay or nil
    local self = setmetatable({
        taskLibrary = options.taskLibrary,
        playerDataController = options.playerDataController,
        matchmakingController = options.matchmakingController,
        duelController = options.duelController,
        fighterController = options.fighterController,
        localPlayer = options.localPlayer,
        constants = options.constants or options.CONSTANTS or {},
        context = options.context or {},
        delay = options.delay or options.schedule or defaultDelay,
        cancelDelay = options.cancelDelay or (task and task.cancel or nil),
        retryHandles = {},
        retryDelay = options.retryDelay or options.retrySeconds or 10,
        maxQueueAttempts = options.maxQueueAttempts or options.maxQueueRetries or 3,
        onActivityChanged = options.onActivityChanged,
        onStatusChanged = options.onStatusChanged,
        onManualDuel = options.onManualDuel,
        practiceDriver = options.practiceDriver,
        lastCombatActive = false,
        queueAccepted = false,
        queuedTaskName = nil,
        wasInDuel = false,
        connections = {},
        contextConnections = {},
        generation = 0,
        attempts = 0,
        stopped = false,
        paused = options.paused == true,
        pauseReason = options.paused == true and "user" or nil,
        currentTask = nil,
        state = "idle",
    }, TaskFarmRuntime)

    if self.practiceDriver and type(self.practiceDriver.setChanged) == "function" then
        self.practiceDriver:setChanged(function()
            self:_notifyActivity()
        end)
    end
    local function onNativeChange()
        self:_reconcile(false)
    end
    local groups = options.taskLibrary.TASKS_DATA_NAMES
        or {
            "Tasks",
            "BonusTasks",
            "EventTasks",
            "SpecialChallenges",
            "LimitedTasks",
        }
    for _, group in ipairs(groups) do
        if type(options.playerDataController.GetDataChangedSignal) == "function" then
            local ok, signal = pcall(
                options.playerDataController.GetDataChangedSignal,
                options.playerDataController,
                group
            )
            if ok then
                connect(self.connections, signal, onNativeChange)
            end
        end
    end
    if type(options.playerDataController.GetDataChangedSignal) == "function" then
        local ok, signal = pcall(
            options.playerDataController.GetDataChangedSignal,
            options.playerDataController,
            "BeginnerTasksCompleted"
        )
        if ok then
            connect(self.connections, signal, onNativeChange)
        end
    end
    local fighter = self:_fighter()
    connect(self.connections, changedSignal(fighter, "IsInDuel"), onNativeChange)
    connect(self.connections, changedSignal(fighter, "IsInShootingRange"), onNativeChange)
    if options.fighterController then
        connect(self.connections, options.fighterController.LocalFighterChanged, onNativeChange)
    end
    self:_bindDuel()
    self:_reconcile(false)
    return self
end

function TaskFarmRuntime:_fighter()
    if type(self.context.getFighter) == "function" then
        return self.context.getFighter()
    end
    return self.fighterController and self.fighterController.LocalFighter or nil
end

function TaskFarmRuntime:_duel()
    if type(self.context.getDuel) == "function" then
        return self.context.getDuel()
    end
    if self.duelController and type(self.duelController.GetDuel) == "function" then
        local ok, duel = pcall(self.duelController.GetDuel, self.duelController, self.localPlayer)
        if ok then
            return duel
        end
    end
    return nil
end

function TaskFarmRuntime:_bindDuel()
    for _, connection in ipairs(self.contextConnections) do
        if connection and type(connection.Disconnect) == "function" then
            connection:Disconnect()
        end
    end
    self.contextConnections = {}
    local duel = self:_duel()
    connect(self.contextConnections, changedSignal(duel, "Status"), function()
        self:_reconcile(false)
    end)
end

function TaskFarmRuntime:_inDuel()
    if type(self.context.isInDuel) == "function" then
        return self.context.isInDuel() == true
    end
    return read(self:_fighter(), "IsInDuel") == true
end

function TaskFarmRuntime:_inRange()
    if type(self.context.isInRange) == "function" then
        return self.context.isInRange() == true
    end
    return read(self:_fighter(), "IsInShootingRange") == true
end

function TaskFarmRuntime:_isMatchmadeDuel()
    if type(self.context.isMatchmadeDuel) == "function" then
        return self.context.isMatchmadeDuel(self:_duel()) == true
    end
    if self.queueAccepted or self:_isQueued() then
        return true
    end
    local controller = self.matchmakingController
    if type(controller.Get) == "function" then
        for _, key in ipairs({ "MatchmadeStatus", "MatchmadeGameOver", "MatchmadeConnectedPlayers" }) do
            local ok, value = pcall(controller.Get, controller, key)
            if ok and value ~= nil then
                return true
            end
        end
    end
    if type(controller.IsMatchmadeDuelOver) == "function" then
        local ok, value = pcall(controller.IsMatchmadeDuelOver, controller)
        if ok and value == true then
            return true
        end
    end
    return read(controller, "MatchmadeStatus") ~= nil
        or read(controller, "MatchmadeGameOver") ~= nil
        or read(controller, "MatchmadeConnectedPlayers") ~= nil
end

function TaskFarmRuntime:_isQueued()
    if type(self.context.isQueued) == "function" then
        return self.context.isQueued() == true
    end
    if type(self.context.getQueueName) == "function" then
        return self.context.getQueueName() ~= nil
    end
    local controller = self.matchmakingController
    return read(controller, "IsQueued") == true
        or read(controller, "IsInQueue") == true
        or read(controller, "QueueName") ~= nil
        or read(controller, "QueuedFor") ~= nil
end

function TaskFarmRuntime:_wins()
    if type(self.context.getWins) == "function" then
        return self.context.getWins() or 0
    end
    if type(self.playerDataController.GetStatistic) == "function" then
        local ok, value = pcall(
            self.playerDataController.GetStatistic,
            self.playerDataController,
            "StatisticDuelsWon"
        )
        if ok and type(value) == "number" then
            return value
        end
    end
    for _, key in ipairs({ "Wins", "DuelWins", "TotalWins" }) do
        local value = read(self.playerDataController, key)
        if type(value) == "number" then
            return value
        end
    end
    for _, containerKey in ipairs({ "Stats", "Statistics", "PlayerStats" }) do
        local container = read(self.playerDataController, containerKey)
        if type(container) == "table" then
            for _, key in ipairs({ "Wins", "DuelWins", "TotalWins" }) do
                if type(container[key]) == "number" then
                    return container[key]
                end
            end
        end
    end
    return 0
end

function TaskFarmRuntime:_queueName()
    local cap = self.constants.BEGINNER_QUEUE_WINS
    local beginner = self.constants.BEGINNER_QUEUE_NAME
    if beginner and type(cap) == "number" and self:_wins() < cap then
        return beginner
    end
    return "1v1"
end

function TaskFarmRuntime:_cancelRetries()
    for handle, _ in pairs(self.retryHandles) do
        if type(self.cancelDelay) == "function" then
            pcall(self.cancelDelay, handle)
        elseif type(handle) == "table" and type(handle.Cancel) == "function" then
            pcall(handle.Cancel, handle)
        end
        self.retryHandles[handle] = nil
    end
end

function TaskFarmRuntime:_scheduleRetry(generation)
    if type(self.delay) ~= "function" or self.attempts >= self.maxQueueAttempts then
        return
    end
    local token = { active = true }
    local handle
    local function retry()
        token.active = false
        if handle ~= nil then
            self.retryHandles[handle] = nil
        end
        if self.stopped or self.paused or generation ~= self.generation then
            return
        end
        self:_reconcile(true)
    end
    handle = self.delay(self.retryDelay, retry)
    if token.active and handle ~= nil then
        self.retryHandles[handle] = true
    end
end

function TaskFarmRuntime:_tryLeaveQueue()
    local leaveQueue = self.context.leaveQueue or self.matchmakingController.TryLeaveQueue
    if type(leaveQueue) == "function" then
        pcall(leaveQueue, self.matchmakingController)
    end
end

function TaskFarmRuntime:_cancelOwnedQueue()
    if not self.queueAccepted then
        return
    end
    self.queueAccepted = false
    self.queuedTaskName = nil
    self:_tryLeaveQueue()
end

function TaskFarmRuntime:_requestQueue(generation)
    if self.stopped or self.paused or generation ~= self.generation then
        return
    end
    if self.attempts >= self.maxQueueAttempts then
        self.state = "retry-exhausted"
        return
    end
    self.attempts += 1
    self.state = "queueing"
    -- This is deliberately the sole state-changing boundary in the runtime.
    local ok, result =
        pcall(self.matchmakingController.QueueInto, self.matchmakingController, self:_queueName())
    local accepted = ok and (result == true or result == "Success")
    if self.stopped or self.paused or generation ~= self.generation then
        if accepted then
            self:_tryLeaveQueue()
        end
        return
    end
    if accepted then
        self.queueAccepted = true
        self.queuedTaskName = self.currentTask and self.currentTask.name or nil
        self.state = "queued"
        return
    end
    self:_scheduleRetry(generation)
end

function TaskFarmRuntime:_notifyActivity()
    local status = self:status()
    if type(self.onStatusChanged) == "function" then
        pcall(self.onStatusChanged, status)
    end
    local active = self:isCombatActive() == true
    if active == self.lastCombatActive then
        return
    end
    self.lastCombatActive = active
    if type(self.onActivityChanged) == "function" then
        pcall(self.onActivityChanged, active, status)
    end
end

function TaskFarmRuntime:_reconcile(isRetry)
    if self.stopped then
        return
    end
    if not isRetry then
        self:_cancelRetries()
        self.generation += 1
        self.attempts = 0
        self:_bindDuel()
    end
    local generation = self.generation
    local previousTaskName = self.currentTask and self.currentTask.name or nil
    local tasks = TaskPolicy.snapshot(self.taskLibrary, self.playerDataController)
    self.currentTask = TaskPolicy.select(tasks)
    local currentTaskName = self.currentTask and self.currentTask.name or nil
    if currentTaskName ~= previousTaskName then
        self.queueAccepted = false
        self.queuedTaskName = nil
    end
    if self.practiceDriver and type(self.practiceDriver.setTask) == "function" then
        local practiceTask = self.currentTask
        if practiceTask and TaskPolicy.requiresCombat(practiceTask) then
            practiceTask = nil
        end
        self.practiceDriver:setTask(practiceTask)
        if self.paused and type(self.practiceDriver.pause) == "function" then
            self.practiceDriver:pause()
        elseif not self.paused and type(self.practiceDriver.resume) == "function" then
            self.practiceDriver:resume()
        end
    end
    local inDuel = self:_inDuel()
    -- Auto-pause only when entering a private/lobby duel. A later user resume,
    -- round-status change, or Adapter pause/resume sync must not re-pause.
    if inDuel and not self:_isMatchmadeDuel() and not self.wasInDuel then
        self.wasInDuel = true
        self:pause("manual-duel")
        if type(self.onManualDuel) == "function" then
            pcall(self.onManualDuel)
        end
        return
    end
    if self.wasInDuel and not inDuel then
        self.queueAccepted = false
        self.queuedTaskName = nil
    end
    self.wasInDuel = inDuel
    local function finish(state)
        self.state = state
        self:_notifyActivity()
    end
    if self.paused then
        finish("paused")
        return
    end
    if not self.currentTask then
        finish("idle")
        return
    end
    if not TaskPolicy.requiresCombat(self.currentTask) then
        local practiceStatus = self.practiceDriver and self.practiceDriver:status() or nil
        finish(practiceStatus and practiceStatus.state or "practice-pending")
        return
    end
    local duelStatus = read(self:_duel(), "Status")
    if inDuel and duelStatus == "GameOver" and self:_isMatchmadeDuel() then
        if self:_isQueued() or (self.queueAccepted and self.queuedTaskName == currentTaskName) then
            finish("queued")
            return
        end
        self:_requestQueue(generation)
        self:_notifyActivity()
        return
    end
    if inDuel then
        finish(self:isCombatActive() and "combat" or "duel-waiting")
        return
    end
    if self:_inRange() then
        finish("range-waiting")
        return
    end
    if self:_isQueued() or (self.queueAccepted and self.queuedTaskName == currentTaskName) then
        finish("queued")
        return
    end
    self:_requestQueue(generation)
    self:_notifyActivity()
end

function TaskFarmRuntime:isCombatActive()
    if self.stopped or self.paused then
        return false
    end
    if
        self.practiceDriver
        and type(self.practiceDriver.isCombatActive) == "function"
        and self.practiceDriver:isCombatActive()
    then
        return true
    end
    if not TaskPolicy.requiresCombat(self.currentTask) or not self:_inDuel() then
        return false
    end
    if type(self.context.isRoundStarted) == "function" then
        return self.context.isRoundStarted(self:_duel()) == true
    end
    return read(self:_duel(), "Status") == "RoundStarted"
end

function TaskFarmRuntime:status()
    return {
        state = self.state,
        task = self.currentTask,
        paused = self.paused,
        reason = self.pauseReason,
        attempts = self.attempts,
        practice = self.practiceDriver and self.practiceDriver:status() or nil,
    }
end

function TaskFarmRuntime:setActivityChanged(callback)
    self.onActivityChanged = callback
end

function TaskFarmRuntime:setStatusChanged(callback)
    self.onStatusChanged = callback
end

function TaskFarmRuntime:pause(reason)
    if self.stopped then
        return
    end
    self:_cancelRetries()
    self.generation += 1
    self.paused = true
    self.pauseReason = reason or "paused"
    self.state = "paused"
    self:_cancelOwnedQueue()
    if self.practiceDriver and type(self.practiceDriver.pause) == "function" then
        self.practiceDriver:pause()
    end
    self:_notifyActivity()
end

function TaskFarmRuntime:resume()
    if self.stopped or not self.paused then
        return
    end
    self.paused = false
    self.pauseReason = nil
    self:_reconcile(false)
end

function TaskFarmRuntime:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_cancelRetries()
    self.generation += 1
    self.state = "stopped"
    self.currentTask = nil
    if self.practiceDriver and type(self.practiceDriver.stop) == "function" then
        self.practiceDriver:stop()
    end
    self:_notifyActivity()
    for _, list in ipairs({ self.connections, self.contextConnections }) do
        for _, connection in ipairs(list) do
            if connection and type(connection.Disconnect) == "function" then
                connection:Disconnect()
            end
        end
        table.clear(list)
    end
end

return TaskFarmRuntime
]],
        ["games/rivals/tasks/TaskLoadout.lua"] = [=[local TaskLoadout = {}
TaskLoadout.__index = TaskLoadout

local SLOT_NAMES = { "Primary", "Secondary", "Melee" }

local function restoreExecutorThread()
    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
end

local function weaponName(value)
    if type(value) == "string" then
        return value
    end
    if type(value) == "table" then
        local name = value.Name or value.name or value.Id or value.id
        return type(name) == "string" and name or nil
    end
    return nil
end

local function chosenTable(page)
    if type(page) ~= "table" then
        return nil
    end
    local chosen = page._chosen_weapons or page.ChosenWeapons or page.chosenWeapons
    return type(chosen) == "table" and chosen or nil
end

local function chosenAt(page, index)
    local chosen = chosenTable(page)
    if not chosen then
        return nil
    end
    return weaponName(chosen[index]) or weaponName(chosen[SLOT_NAMES[index]])
end

function TaskLoadout.new(options)
    options = options or {}
    return setmetatable({
        accepted = {},
        clock = options.clock or os.clock,
        constants = options.constants,
        finished = false,
        getOpponentFighter = options.getOpponentFighter,
        getStatus = options.getStatus,
        index = 1,
        nextAt = 0,
        page = options.page,
        plan = nil,
        taskCounterPolicy = options.taskCounterPolicy,
        taskDebug = options.taskDebug or {},
        taskPolicy = options.taskPolicy,
        wasOpen = false,
    }, TaskLoadout)
end

function TaskLoadout:armed()
    local status = type(self.getStatus) == "function" and self.getStatus()
    if type(status) ~= "table" then
        return false
    end
    return status.paused ~= true
        and status.task ~= nil
        and status.state ~= "idle"
        and status.state ~= "stopped"
        and status.state ~= "paused"
end

function TaskLoadout:stop()
    self.plan = nil
    self.index = 1
    self.nextAt = 0
    self.wasOpen = false
    self.finished = false
    table.clear(self.accepted)
end

function TaskLoadout:defaultPlan(secondary)
    local defaults = type(self.constants) == "table" and self.constants.DEFAULT_WEAPONS
    if type(defaults) ~= "table" then
        return nil
    end
    local plan = {}
    for index, name in ipairs(defaults) do
        if type(name) == "string" then
            plan[index] = name
        end
    end
    if #plan == 0 then
        for _, key in ipairs(SLOT_NAMES) do
            local name = defaults[key]
            if type(name) == "string" then
                table.insert(plan, name)
            end
        end
    end
    if type(secondary) == "string" then
        if #plan >= 2 then
            plan[2] = secondary
        elseif #plan == 1 then
            plan[2] = secondary
        end
    end
    return #plan > 0 and plan or nil
end

function TaskLoadout:_slotReady(index, desired)
    return self.accepted[index] == desired or chosenAt(self.page, index) == desired
end

function TaskLoadout:_planComplete()
    local plan = self.plan
    if type(plan) ~= "table" or #plan == 0 then
        return false
    end
    for index, desired in ipairs(plan) do
        if not self:_slotReady(index, desired) then
            return false
        end
    end
    return true
end

function TaskLoadout:_submit()
    local page = self.page
    if type(page.Finish) ~= "function" or self.finished then
        return
    end
    if not self:_planComplete() then
        self.taskDebug.loadoutStage = "waiting-slots"
        return
    end
    restoreExecutorThread()
    pcall(page.Finish, page)
    self.finished = true
    self.taskDebug.counterLoadout = tostring(self.plan[1]) .. " + " .. tostring(self.plan[2])
    self.taskDebug.loadoutStage = "submitted"
end

function TaskLoadout:poll()
    restoreExecutorThread()
    local page = self.page
    if not page or not page:IsOpen() then
        if self.wasOpen then
            self:stop()
        end
        return
    end
    if not self:armed() then
        if self.wasOpen or self.plan then
            self:stop()
        end
        self.taskDebug.loadoutStage = "player-pick"
        return
    end
    if not self.wasOpen then
        self.wasOpen = true
        self.plan = nil
        self.index = 1
        self.nextAt = 0
        self.finished = false
        table.clear(self.accepted)
        self.taskDebug.loadoutStage = "reading-opponent"
        self.taskDebug.loadoutError = nil
    end
    self.taskDebug.loadoutHeartbeat = self.clock()
    if not self.plan then
        local opponentFighter = self.getOpponentFighter and self.getOpponentFighter()
        local opponentItems = opponentFighter and opponentFighter.Items or {}
        local useCounter = self.taskCounterPolicy.shouldSelectSpray(opponentItems)
        self.plan = self:defaultPlan(useCounter and "Spray" or nil)
        if not self.plan then
            self.taskDebug.loadoutStage = "waiting-defaults"
            return
        end
        self.taskDebug.loadoutStage = useCounter and "selecting-counter" or "selecting-default"
    end
    while self.plan[self.index] and self:_slotReady(self.index, self.plan[self.index]) do
        self.index += 1
        self.nextAt = 0
    end
    if not self.plan[self.index] then
        self:_submit()
        return
    end
    if self.clock() < self.nextAt then
        return
    end
    if type(page.PickWeapon) ~= "function" then
        self.taskDebug.loadoutStage = "error"
        self.taskDebug.loadoutError = "PickWeapon unavailable"
        return
    end
    local desired = self.plan[self.index]
    self.taskDebug.loadoutStage = "picking-" .. desired
    restoreExecutorThread()
    local succeeded, loadoutError = pcall(page.PickWeapon, page, self.index, desired)
    if not succeeded then
        self.taskDebug.loadoutStage = "error"
        self.taskDebug.loadoutError = tostring(loadoutError)
        self.nextAt = self.clock() + 0.12
        return
    end
    self.accepted[self.index] = desired
    self.nextAt = self.clock() + 0.12
end

return TaskLoadout
]=],
        ["games/rivals/tasks/TaskLocomotion.lua"] = [[local TaskLocomotion = {}
TaskLocomotion.__index = TaskLocomotion

function TaskLocomotion.new()
    return setmetatable({
        lastDistance = math.huge,
        lastProgressAt = 0,
        nextSlideAt = 0,
        strafeSign = 1,
        target = nil,
    }, TaskLocomotion)
end

function TaskLocomotion:plan(state)
    local offset = state.targetPosition - state.position
    local distance = offset.Magnitude
    local targetChanged = self.target ~= state.targetPosition
    if targetChanged then
        self.target = state.targetPosition
        self.lastDistance = distance
        self.lastProgressAt = state.now
    elseif distance < self.lastDistance - 0.75 then
        self.lastDistance = distance
        self.lastProgressAt = state.now
    elseif state.clear == false and state.now - self.lastProgressAt >= 0.65 then
        self.strafeSign = -self.strafeSign
        self.lastDistance = distance
        self.lastProgressAt = state.now
    end

    local toward = distance > 0.01 and offset.Unit or Vector3.zero
    local strafe = Vector3.new(-toward.Z, 0, toward.X) * self.strafeSign
    local direction = distance > 8 and (toward * 0.9 + strafe * 0.2).Unit
        or (strafe - toward * 0.5).Unit
    local slide = state.clear ~= false
        and state.grounded == true
        and distance > 24
        and state.now >= self.nextSlideAt
    if slide then
        self.nextSlideAt = state.now + 2.8
    end
    return {
        direction = direction,
        intent = "push",
        slide = slide,
        strafeSign = self.strafeSign,
    }
end

return TaskLocomotion
]],
        ["games/rivals/tasks/TaskPolicy.lua"] = [[local TaskPolicy = {}

local DEFAULT_GROUPS = { "Tasks", "BonusTasks", "EventTasks", "SpecialChallenges", "LimitedTasks" }
local GROUP_PRIORITY = {
    Tasks = 1,
    LimitedTasks = 2,
    SpecialChallenges = 3,
    EventTasks = 4,
    BonusTasks = 5,
}

local function read(controller, key)
    if type(controller) ~= "table" then
        return nil
    end
    if type(controller.Get) == "function" then
        local ok, result = pcall(controller.Get, controller, key)
        if ok then
            return result
        end
    end
    local data = controller.Data
    if type(data) == "table" then
        return data[key]
    end
    return controller[key]
end

local function copyRecord(record, fallbackName, group, info)
    if type(record) ~= "table" then
        return nil
    end
    local name = record.Name or record.Id or record.ID or fallbackName
    if type(name) ~= "string" then
        return nil
    end
    local metadata = type(info) == "table" and info[name] or nil
    local normalized = {
        name = name,
        id = name,
        group = group,
        title = record.Title or (metadata and metadata.Title) or name,
        progress = record.Progress,
        goal = record.Goal or (metadata and metadata.Goal),
        completed = record.Completed == true,
        locked = record.Locked == true or record.Unlocked == false or record.IsLocked == true,
        native = record,
    }
    -- Preserve the native values: a goal is metadata, not permission to invent progress.
    return normalized
end

function TaskPolicy.snapshot(taskLibrary, playerDataController)
    if
        type(playerDataController) == "table"
        and playerDataController.TASKS_DATA_NAMES
        and not (type(taskLibrary) == "table" and taskLibrary.TASKS_DATA_NAMES)
    then
        taskLibrary, playerDataController = playerDataController, taskLibrary
    end
    if type(taskLibrary) == "table" and taskLibrary.taskLibrary then
        playerDataController = taskLibrary.playerDataController
        taskLibrary = taskLibrary.taskLibrary
    end
    taskLibrary = taskLibrary or {}
    local groups = taskLibrary.TASKS_DATA_NAMES or DEFAULT_GROUPS
    local result = {}
    for _, group in ipairs(groups) do
        local records = read(playerDataController, group)
        if type(records) == "table" then
            local added = {}
            for index, record in ipairs(records) do
                local normalized = copyRecord(record, nil, group, taskLibrary.Info)
                if normalized then
                    table.insert(result, normalized)
                    added[index] = true
                end
            end
            local keys = {}
            for key, _ in pairs(records) do
                if not added[key] and type(key) ~= "number" then
                    table.insert(keys, key)
                end
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, key in ipairs(keys) do
                local normalized = copyRecord(records[key], key, group, taskLibrary.Info)
                if normalized then
                    table.insert(result, normalized)
                end
            end
        end
    end
    return result
end

local RANGE_FAMILY = {
    Beginner1 = "range",
    Beginner2 = "targets",
    Beginner3 = "slide",
    Beginner4 = "equip",
    Beginner5 = "dash",
    Beginner6 = "grenade",
}
local BEGINNER_PVP = { Beginner7 = "play", Beginner8 = "eliminations", Beginner9 = "wins" }

local function pvpFamily(name, title)
    local beginner = BEGINNER_PVP[name]
    if beginner then
        return beginner
    end
    local text = string.lower((name or "") .. " " .. (title or ""))
    if string.find(text, "eliminat", 1, true) or string.find(text, " kill", 1, true) then
        return "eliminations"
    end
    if string.find(text, "streak", 1, true) then
        return "streaks"
    end
    if string.find(text, "win", 1, true) then
        return "wins"
    end
    if string.find(text, "round", 1, true) then
        return "rounds"
    end
    if
        string.find(text, "duel", 1, true)
        or string.find(text, "match", 1, true)
        or string.find(text, "play", 1, true)
    then
        return "play"
    end
    return nil
end

function TaskPolicy.classify(task)
    if type(task) ~= "table" then
        return nil
    end
    local name = task.name or task.Name or task.id
    local title = task.title or task.Title
    local rangeFamily = RANGE_FAMILY[name]
    if rangeFamily then
        return {
            kind = "range",
            type = "range",
            family = rangeFamily,
            supported = true,
            requiresCombat = false,
        }
    end
    local family = pvpFamily(name, title)
    if family then
        local group = task.group or task.Group
        local lower = string.lower((name or "") .. " " .. (title or ""))
        local variant = string.find(lower, "event", 1, true) and "event"
            or string.find(lower, "limited", 1, true) and "limited"
            or (group == "EventTasks" and "event")
            or (group == "LimitedTasks" and "limited")
            or nil
        return {
            kind = "pvp",
            type = "pvp",
            family = family,
            variant = variant,
            scope = variant,
            supported = true,
            requiresCombat = true,
            event = variant == "event",
            limited = variant == "limited",
        }
    end
    return { kind = "unsupported", type = "unsupported", supported = false, requiresCombat = false }
end

local function sortKey(task)
    local beginner = tonumber(string.match(task.name or "", "^Beginner(%d+)$"))
    return GROUP_PRIORITY[task.group] or 99, beginner or math.huge, task.name or ""
end

function TaskPolicy.select(tasks)
    local candidates = {}
    for _, task in ipairs(tasks or {}) do
        local classification = TaskPolicy.classify(task)
        if
            task.completed ~= true
            and task.Completed ~= true
            and not task.locked
            and classification
            and classification.supported
        then
            task.classification = classification
            table.insert(candidates, task)
        end
    end
    table.sort(candidates, function(a, b)
        local ag, ai, an = sortKey(a)
        local bg, bi, bn = sortKey(b)
        if ag ~= bg then
            return ag < bg
        end
        if ai ~= bi then
            return ai < bi
        end
        return an < bn
    end)
    return candidates[1]
end

function TaskPolicy.requiresCombat(task)
    local classification = task and (task.classification or TaskPolicy.classify(task))
    return classification ~= nil and classification.kind == "pvp"
end

TaskPolicy.GROUP_PRIORITY = GROUP_PRIORITY
return TaskPolicy
]],
        ["games/rivals/tasks/TaskSkillRuntime.lua"] = [[local TaskSkillRuntime = {}
TaskSkillRuntime.__index = TaskSkillRuntime

local function healthOf(subject)
    if not subject then
        return nil, nil
    end
    local humanoid = subject
    if typeof(subject) == "Instance" then
        if not subject:IsA("Humanoid") then
            humanoid = subject:FindFirstChildOfClass("Humanoid")
        end
    elseif type(subject) == "table" then
        humanoid = subject.Humanoid or subject
    end
    local health = humanoid and humanoid.Health
    local maximum = humanoid and humanoid.MaxHealth
    if type(health) ~= "number" then
        return nil, nil
    end
    if type(maximum) ~= "number" or maximum <= 0 then
        return health, nil
    end
    return health, maximum
end

local function attribute(player, name)
    if not player or type(player.GetAttribute) ~= "function" then
        return nil
    end
    local succeeded, value = pcall(player.GetAttribute, player, name)
    return succeeded and value or nil
end

local function playerStatThreat(localPlayer, opponent)
    local player = opponent and opponent.player
    if not player then
        return nil, nil
    end
    local elo = attribute(player, "DisplayELO")
    local level = attribute(player, "Level")
    local streak = attribute(player, "StatisticDuelsWinStreak")
    local localElo = attribute(localPlayer, "DisplayELO")
    local localLevel = attribute(localPlayer, "Level")
    local localStreak = attribute(localPlayer, "StatisticDuelsWinStreak")
    if type(elo) ~= "number" and type(level) ~= "number" and type(streak) ~= "number" then
        return nil, nil
    end
    local values = {}
    if type(elo) == "number" then
        values[#values + 1] = type(localElo) == "number"
                and math.clamp(0.5 + (elo - localElo) / 1600, 0, 1)
            or math.clamp((elo - 600) / 2000, 0, 1)
    end
    if type(level) == "number" then
        values[#values + 1] = type(localLevel) == "number"
                and math.clamp(0.5 + (level - localLevel) / 300, 0, 1)
            or math.clamp(level / 250, 0, 1)
    end
    if type(streak) == "number" then
        values[#values + 1] = type(localStreak) == "number"
                and math.clamp(0.5 + (streak - localStreak) / 20, 0, 1)
            or math.clamp(streak / 12, 0, 1)
    end
    local total = 0
    for _, value in ipairs(values) do
        total += value
    end
    return total / #values, { elo = elo, level = level, streak = streak }
end

function TaskSkillRuntime.new(options)
    options = options or {}
    return setmetatable({
        localPlayer = options.localPlayer,
        threat = 0.5,
        statsReady = false,
        opponentStats = nil,
        lastLocalHealth = nil,
        lastOpponentHealth = nil,
        lastOpponent = nil,
        samples = 0,
    }, TaskSkillRuntime)
end

function TaskSkillRuntime:reset()
    self.threat = 0.5
    self.statsReady = false
    self.opponentStats = nil
    self.lastLocalHealth = nil
    self.lastOpponentHealth = nil
    self.lastOpponent = nil
    self.samples = 0
end

function TaskSkillRuntime:update(localHumanoid, opponent, deltaTime)
    local localHealth, localMaximum = healthOf(localHumanoid)
    local opponentHumanoid = opponent
        and opponent.character
        and opponent.character.FindFirstChildOfClass
        and opponent.character:FindFirstChildOfClass("Humanoid")
    local opponentHealth, opponentMaximum = healthOf(opponentHumanoid)
    if type(opponent and opponent.health) == "number" then
        opponentHealth = opponent.health
    end
    if type(opponent and opponent.maxHealth) == "number" then
        opponentMaximum = opponent.maxHealth
    end
    if
        type(opponentHealth) == "number"
        and (type(opponentMaximum) ~= "number" or opponentMaximum <= 0)
    then
        opponentMaximum = nil
    end
    local opponentKey = opponent and (opponent.character or opponent.player or opponent.part)
    local statThreat, opponentStats = playerStatThreat(self.localPlayer, opponent)
    if opponentKey ~= self.lastOpponent then
        self.lastOpponent = opponentKey
        self.lastOpponentHealth = opponentHealth
        self.samples = 0
        if type(statThreat) == "number" then
            self.threat = statThreat
        end
    end
    self.statsReady = type(statThreat) == "number"
    self.opponentStats = opponentStats
    if not localHealth or not opponentHealth or not localMaximum or not opponentMaximum then
        self.lastLocalHealth = localHealth
        self.lastOpponentHealth = opponentHealth
        return self:rates()
    end
    local dt = math.max(type(deltaTime) == "number" and deltaTime or 1 / 60, 1 / 120)
    local incoming = math.max(0, (self.lastLocalHealth or localHealth) - localHealth) / dt
    local outgoing = math.max(0, (self.lastOpponentHealth or opponentHealth) - opponentHealth) / dt
    if incoming > 0 or outgoing > 0 then
        self.samples += 1
    end
    local healthPressure =
        math.clamp((opponentHealth / opponentMaximum - localHealth / localMaximum + 1) * 0.5, 0, 1)
    local exchangePressure = (incoming + outgoing) > 0 and incoming / (incoming + outgoing)
        or self.threat
    local observed = self.statsReady
            and statThreat * 0.5 + healthPressure * 0.35 + exchangePressure * 0.15
        or healthPressure * 0.65 + exchangePressure * 0.35
    self.threat += (observed - self.threat) * math.min(1, dt * 2.5)
    self.lastLocalHealth = localHealth
    self.lastOpponentHealth = opponentHealth
    return self:rates()
end

function TaskSkillRuntime:rates()
    return {
        headshotRate = math.floor(28 + self.threat * 22 + 0.5),
        missRate = math.floor(32 - self.threat * 12 + 0.5),
        ready = self.statsReady or self.samples >= 3,
        samples = self.samples,
        stats = self.opponentStats,
        statsReady = self.statsReady,
        threat = self.threat,
    }
end

return TaskSkillRuntime
]],
        ["games/rivals/tasks/TaskWeaponSwap.lua"] = [[local TaskWeaponSwap = {}
TaskWeaponSwap.__index = TaskWeaponSwap

local function ammo(item)
    if type(item) ~= "table" then
        return nil
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "Ammo")
        if succeeded and type(value) == "number" then
            return value
        end
    end
    local data = item.Data
    return type(data) == "table" and type(data.Ammo) == "number" and data.Ammo or nil
end

function TaskWeaponSwap.new(options)
    return setmetatable({
        clock = options.clock or os.clock,
        equip = options.equip or function(fighter, item)
            return fighter:EquipItem(item)
        end,
        nextAt = 0,
        pendingItem = nil,
        pendingAttempts = 0,
        pendingAt = 0,
        release = options.release or function() end,
        weaponPolicy = assert(options.weaponPolicy),
    }, TaskWeaponSwap)
end

function TaskWeaponSwap:update(active, fighter, target, distance)
    local now = self.clock()
    local current = fighter and fighter.EquippedItem
    if self.pendingItem then
        if current == self.pendingItem then
            self.pendingItem = nil
            self.pendingAttempts = 0
        elseif active == true and fighter and now >= self.pendingAt then
            self.release()
            self.pendingAttempts += 1
            pcall(self.equip, fighter, self.pendingItem)
            self.pendingAt = now + 0.12
            self.nextAt = self.pendingAt
            if self.pendingAttempts >= 6 then
                self.pendingItem = nil
                self.pendingAttempts = 0
            end
            return true
        else
            return active == true
        end
    end
    local currentAmmo = ammo(current)
    if
        active ~= true
        or now < self.nextAt
        or not fighter
        or type(fighter.EquipItem) ~= "function"
    then
        return false
    end
    local targetHealth = target and target.health
    local currentInfo = current and current.Info
    local empty = currentAmmo == 0
    local maximumAmmo = type(currentInfo) == "table" and currentInfo.MaxAmmo or nil
    local lowMagazine = type(currentAmmo) == "number"
        and type(maximumAmmo) == "number"
        and currentAmmo <= math.max(2, math.floor(maximumAmmo * 0.3))
    local tacticalSecondary = not empty
        and lowMagazine
        and type(targetHealth) == "number"
        and type(currentInfo) == "table"
        and currentInfo.Class == "Primary"
    if not empty and not tacticalSecondary then
        return false
    end
    local candidates = fighter.Items
    if type(candidates) ~= "table" and type(fighter.GetEquippedItems) == "function" then
        local succeeded, equipped = pcall(fighter.GetEquippedItems, fighter)
        if succeeded and type(equipped) == "table" then
            candidates = equipped
        end
    end
    if type(candidates) ~= "table" then
        return false
    end
    for key, candidate in pairs(candidates) do
        if type(candidate) ~= "table" then
            if type(key) == "table" then
                candidate = key
            elseif type(fighter.GetItem) == "function" then
                local identifier = candidate ~= true and candidate or key
                local succeeded, item = pcall(fighter.GetItem, fighter, identifier)
                if succeeded then
                    candidate = item
                end
            end
        end
        local candidateInfo = type(candidate) == "table" and candidate.Info or nil
        local candidateAmmo = ammo(candidate)
        local candidateDamage = type(candidateInfo) == "table" and candidateInfo.ShootDamage or nil
        if type(candidateDamage) ~= "number" and type(candidate) == "table" then
            candidateDamage = self.weaponPolicy.damageAtDistance(candidate, target, distance)
        end
        local canFinishClip = empty
            or type(targetHealth) == "number"
                and type(candidateDamage) == "number"
                and type(candidateAmmo) == "number"
                and candidateDamage * candidateAmmo >= targetHealth
        local desiredClass = type(currentInfo) == "table"
                and currentInfo.Class == "Secondary"
                and "Primary"
            or "Secondary"
        local eligibleSlot = type(candidateInfo) == "table" and candidateInfo.Class == desiredClass
        if
            type(candidate) == "table"
            and candidate ~= current
            and eligibleSlot
            and canFinishClip
            and self.weaponPolicy.automationPolicy(candidate).cameraAim == true
            and candidateAmmo ~= nil
            and candidateAmmo > 0
        then
            self.release()
            self.pendingItem = candidate
            self.pendingAttempts = 1
            self.pendingAt = now + 0.12
            self.nextAt = self.pendingAt
            pcall(self.equip, fighter, candidate)
            if fighter.EquippedItem == candidate then
                self.pendingItem = nil
                self.pendingAttempts = 0
            end
            return true
        end
    end
    self.nextAt = now + 0.25
    return false
end

return TaskWeaponSwap
]],
        ["games/rivals/world/Effects.lua"] = [[local UtilityPolicy = require("./UtilityPolicy")
local VisualSuppression = require("./VisualSuppression")
local TrajectoryRenderer = require("./TrajectoryRenderer")
local Effects = {}
Effects.__index = Effects

local THROWABLE_MAX_DISTANCE = 2000
local WIREFRAME_CUBE_OFFSETS = {
    Vector3.new(-0.5, -0.5, -0.5),
    Vector3.new(0.5, -0.5, -0.5),
    Vector3.new(0.5, 0.5, -0.5),
    Vector3.new(-0.5, 0.5, -0.5),
    Vector3.new(-0.5, -0.5, 0.5),
    Vector3.new(0.5, -0.5, 0.5),
    Vector3.new(0.5, 0.5, 0.5),
    Vector3.new(-0.5, 0.5, 0.5),
}
local function connectSignal(signal, callback)
    if not signal or type(signal.Connect) ~= "function" then
        return nil
    end
    local succeeded, connection = pcall(signal.Connect, signal, callback)
    return succeeded and connection or nil
end

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        pcall(connection.Disconnect, connection)
    end
end

local function hierarchyAttribute(instance, name)
    local current = instance
    for _depth = 1, 32 do
        if not current then
            break
        end
        if current.GetAttribute then
            local succeeded, value = pcall(current.GetAttribute, current, name)
            if succeeded and value ~= nil then
                return value
            end
        end
        current = current.Parent
    end
    return nil
end

local function isWorldUtility(root, camera, worldRoot, localPlayer)
    local current = root
    local reachedWorld = worldRoot == nil
    local localCharacter = localPlayer and localPlayer.Character
    for _depth = 1, 32 do
        if not current then
            break
        end
        if current == worldRoot then
            reachedWorld = true
        end
        if current == camera or current == localCharacter then
            return false
        end
        if current.IsA then
            local succeeded, isCamera = pcall(current.IsA, current, "Camera")
            if succeeded and isCamera then
                return false
            end
        end
        current = current.Parent
    end
    return reachedWorld
end

local function projectWireframeCube(camera, boundsFrame, boundsSize)
    if not boundsFrame or not boundsSize then
        return nil
    end

    local corners = {}
    local minimumX = math.huge
    local minimumY = math.huge
    local maximumX = -math.huge
    local anyOnScreen = false
    for _, offset in ipairs(WIREFRAME_CUBE_OFFSETS) do
        local worldPosition = boundsFrame:PointToWorldSpace(
            Vector3.new(offset.X * boundsSize.X, offset.Y * boundsSize.Y, offset.Z * boundsSize.Z)
        )
        local point, onScreen = camera:WorldToViewportPoint(worldPosition)
        if point.Z <= 0 then
            return nil
        end
        local corner = Vector2.new(point.X, point.Y)
        table.insert(corners, corner)
        minimumX = math.min(minimumX, corner.X)
        minimumY = math.min(minimumY, corner.Y)
        maximumX = math.max(maximumX, corner.X)
        anyOnScreen = anyOnScreen or onScreen == true
    end
    return corners, Vector2.new((minimumX + maximumX) * 0.5, minimumY - 16), anyOnScreen
end

Effects.updateVisualSuppressions = VisualSuppression.update

function Effects.throwableObservation(camera, candidate, environmentID, worldRoot, localPlayer)
    local descriptor, root = UtilityPolicy.descriptor(candidate)
    if not descriptor or not camera or not root then
        return nil
    end
    if root.Parent == nil and candidate.Parent == nil then
        return nil
    end
    if not isWorldUtility(root, camera, worldRoot, localPlayer) then
        return nil
    end

    local finished = hierarchyAttribute(root, "SimulationFinished") == true
        or hierarchyAttribute(root, "Exploded") == true
        or hierarchyAttribute(root, "Detonated") == true
    if finished then
        return nil
    end
    local observedEnvironment = hierarchyAttribute(root, "EnvironmentID")
    if
        environmentID ~= nil
        and observedEnvironment ~= nil
        and observedEnvironment ~= environmentID
    then
        return nil
    end

    local part
    if candidate.IsA and candidate:IsA("BasePart") then
        part = candidate
    elseif root.IsA and root:IsA("BasePart") then
        part = root
    else
        part = root.PrimaryPart
            or (root.FindFirstChildWhichIsA and root:FindFirstChildWhichIsA("BasePart", true))
    end
    if not part or not part.Position then
        return nil
    end

    local cameraPosition = camera.CFrame and camera.CFrame.Position
    if cameraPosition and (part.Position - cameraPosition).Magnitude > THROWABLE_MAX_DISTANCE then
        return nil
    end
    local point, onScreen = camera:WorldToViewportPoint(part.Position)
    local markerStyle
    local wireframeCorners
    local labelPosition
    local wireframeOnScreen = false
    if descriptor.markerStyle == "wireframeCube" then
        local boundsFrame
        local boundsSize
        if root.GetBoundingBox then
            local succeeded
            succeeded, boundsFrame, boundsSize = pcall(root.GetBoundingBox, root)
            if not succeeded then
                boundsFrame = nil
                boundsSize = nil
            end
        end
        boundsFrame = boundsFrame or part.CFrame
        boundsSize = boundsSize or part.Size
        wireframeCorners, labelPosition, wireframeOnScreen =
            projectWireframeCube(camera, boundsFrame, boundsSize)
        if wireframeCorners then
            markerStyle = descriptor.markerStyle
        end
    end
    return {
        key = root,
        label = descriptor.label,
        labelPosition = labelPosition,
        markerStyle = markerStyle,
        onScreen = point.Z > 0 and (onScreen == true or wireframeOnScreen),
        polygons = {},
        screenPosition = Vector2.new(point.X, point.Y),
        tone = descriptor.tone,
        wireframeCorners = wireframeCorners,
        worldPosition = part.Position,
    }
end

function Effects.new(options)
    assert(options and options.workspace, "RIVALS effects require Workspace")
    assert(options.localPlayer, "RIVALS effects require LocalPlayer")
    assert(options.projectileAim, "RIVALS effects require projectile aim")

    local self = setmetatable({
        clock = options.clock or os.clock,
        collectionService = options.collectionService,
        lighting = options.lighting,
        localPlayer = options.localPlayer,
        playerGui = options.playerGui,
        suppressedVisuals = setmetatable({}, { __mode = "k" }),
        throwableCandidates = {},
        throwableCandidateSet = setmetatable({}, { __mode = "k" }),
        throwableTagCounts = setmetatable({}, { __mode = "k" }),
        taggedCandidates = {},
        smokeCandidates = setmetatable({}, { __mode = "k" }),
        tagConnections = {},
        visualConnections = {},
        visualLifecycleConnections = {},
        visualRoots = {},
        smokeVisualConnections = setmetatable({}, { __mode = "k" }),
        visualNoFlash = false,
        visualNoSmoke = false,
        trajectoryRenderer = TrajectoryRenderer.new(options),
        workspace = options.workspace,
    }, Effects)
    self:_startThrowableRegistry()
    return self
end

function Effects:_addTaggedCandidate(tag, candidate)
    if not candidate then
        return
    end
    local tagged = self.taggedCandidates[tag]
    if tagged[candidate] then
        return
    end
    tagged[candidate] = true
    local count = (self.throwableTagCounts[candidate] or 0) + 1
    self.throwableTagCounts[candidate] = count
    if count == 1 then
        self.throwableCandidateSet[candidate] = true
        table.insert(self.throwableCandidates, candidate)
    end
    if tag == "SmokeCloud" then
        self.smokeCandidates[candidate] = true
        if self.visualNoSmoke then
            self:_attachSmokeVisual(candidate)
        end
    end
end

function Effects:_removeTaggedCandidate(tag, candidate)
    local tagged = self.taggedCandidates[tag]
    if not tagged or not tagged[candidate] then
        return
    end
    tagged[candidate] = nil
    if tag == "SmokeCloud" then
        self.smokeCandidates[candidate] = nil
        self:_detachSmokeVisual(candidate)
    end
    local count = (self.throwableTagCounts[candidate] or 1) - 1
    if count > 0 then
        self.throwableTagCounts[candidate] = count
        return
    end
    self.throwableTagCounts[candidate] = nil
    self.throwableCandidateSet[candidate] = nil
    for index, value in ipairs(self.throwableCandidates) do
        if value == candidate then
            table.remove(self.throwableCandidates, index)
            break
        end
    end
end

function Effects:_startThrowableRegistry()
    local service = self.collectionService
    if not service then
        return
    end
    for _, tag in ipairs(UtilityPolicy.TAGS) do
        self.taggedCandidates[tag] = setmetatable({}, { __mode = "k" })
        if service.GetInstanceAddedSignal then
            local succeeded, signal = pcall(service.GetInstanceAddedSignal, service, tag)
            if succeeded then
                local connection = connectSignal(signal, function(candidate)
                    self:_addTaggedCandidate(tag, candidate)
                end)
                if connection then
                    table.insert(self.tagConnections, connection)
                end
            end
        end
        if service.GetInstanceRemovedSignal then
            local succeeded, signal = pcall(service.GetInstanceRemovedSignal, service, tag)
            if succeeded then
                local connection = connectSignal(signal, function(candidate)
                    self:_removeTaggedCandidate(tag, candidate)
                end)
                if connection then
                    table.insert(self.tagConnections, connection)
                end
            end
        end
        if service.GetTagged then
            local succeeded, candidates = pcall(service.GetTagged, service, tag)
            if succeeded then
                for _, candidate in ipairs(candidates or {}) do
                    self:_addTaggedCandidate(tag, candidate)
                end
            end
        end
    end
end

-- Kept for callers/tests that use the old helper. Discovery itself is now event-driven.
function Effects:_collectThrowables()
    local candidates = {}
    for _, candidate in ipairs(self.throwableCandidates) do
        table.insert(candidates, candidate)
    end
    return candidates
end

function Effects:smokeRaycastIgnore()
    local smokeClouds = {}
    for candidate in pairs(self.smokeCandidates) do
        table.insert(smokeClouds, candidate)
    end
    return smokeClouds
end

function Effects:observeThrowables(camera, environmentID)
    local utilities = {}
    for _, candidate in ipairs(self.throwableCandidates) do
        local observation = Effects.throwableObservation(
            camera,
            candidate,
            environmentID,
            self.workspace,
            self.localPlayer
        )
        if observation then
            table.insert(utilities, observation)
        end
    end
    return utilities
end

function Effects:_disconnectVisualRoots()
    for _, connection in ipairs(self.visualConnections) do
        disconnect(connection)
    end
    for _, connection in ipairs(self.visualLifecycleConnections) do
        disconnect(connection)
    end
    self.visualConnections = {}
    self.visualLifecycleConnections = {}
    self.visualRoots = {}
end

function Effects:_globalVisualRoots()
    local playerGui = self.playerGui
    if not playerGui and self.localPlayer.FindFirstChildOfClass then
        playerGui = self.localPlayer:FindFirstChildOfClass("PlayerGui")
    end
    local roots = {}
    if self.lighting then
        table.insert(roots, self.lighting)
    end
    if self.workspace.CurrentCamera then
        table.insert(roots, self.workspace.CurrentCamera)
    end
    if playerGui then
        table.insert(roots, playerGui)
    end
    return roots
end

function Effects:_startFlashVisuals()
    self:_disconnectVisualRoots()
    self.visualRoots = self:_globalVisualRoots()
    for _, root in ipairs(self.visualRoots) do
        local added = connectSignal(root.DescendantAdded, function(instance)
            VisualSuppression.apply({ noFlash = true }, { instance }, self.suppressedVisuals)
        end)
        local removing = connectSignal(root.DescendantRemoving, function(instance)
            VisualSuppression.restoreRoots({ instance }, self.suppressedVisuals)
        end)
        if added then
            table.insert(self.visualConnections, added)
        end
        if removing then
            table.insert(self.visualConnections, removing)
        end
    end

    -- Camera replacement is rare, but must also remain event-driven.
    if self.workspace.GetPropertyChangedSignal then
        local succeeded, signal =
            pcall(self.workspace.GetPropertyChangedSignal, self.workspace, "CurrentCamera")
        if succeeded then
            local connection = connectSignal(signal, function()
                if self.visualNoFlash then
                    for _, root in ipairs(self.visualRoots) do
                        VisualSuppression.restoreRoots({ root }, self.suppressedVisuals)
                    end
                    self:_startFlashVisuals()
                end
            end)
            if connection then
                table.insert(self.visualLifecycleConnections, connection)
            end
        end
    end
    VisualSuppression.apply({ noFlash = true }, self.visualRoots, self.suppressedVisuals)
end

function Effects:_stopFlashVisuals()
    for _, root in ipairs(self.visualRoots) do
        VisualSuppression.restoreRoots({ root }, self.suppressedVisuals)
    end
    self:_disconnectVisualRoots()
end

function Effects:_attachSmokeVisual(candidate)
    if not candidate or self.smokeVisualConnections[candidate] then
        return
    end
    local descriptor, root = UtilityPolicy.descriptor(candidate)
    if not descriptor or descriptor.tone ~= "smoke" or not root then
        return
    end

    local connections = { root = root }
    local added = connectSignal(root.DescendantAdded, function(instance)
        VisualSuppression.apply({ noSmoke = true }, {
            { instance = instance, kind = "smoke" },
        }, self.suppressedVisuals)
    end)
    local removing = connectSignal(root.DescendantRemoving, function(instance)
        VisualSuppression.restoreRoots({ instance }, self.suppressedVisuals)
    end)
    if added then
        table.insert(connections, added)
    end
    if removing then
        table.insert(connections, removing)
    end
    self.smokeVisualConnections[candidate] = connections
    VisualSuppression.apply({ noSmoke = true }, {
        { instance = root, kind = "smoke" },
    }, self.suppressedVisuals)
end

function Effects:_detachSmokeVisual(candidate)
    local connections = self.smokeVisualConnections[candidate]
    if not connections then
        return
    end
    for _, connection in ipairs(connections) do
        disconnect(connection)
    end
    VisualSuppression.restoreRoots({ connections.root }, self.suppressedVisuals)
    self.smokeVisualConnections[candidate] = nil
end

function Effects:_stopSmokeVisuals()
    local candidates = {}
    for candidate in pairs(self.smokeVisualConnections) do
        table.insert(candidates, candidate)
    end
    for _, candidate in ipairs(candidates) do
        self:_detachSmokeVisual(candidate)
    end
end

function Effects:update(settings)
    local noFlash = settings.noFlash == true
    local noSmoke = settings.noSmoke == true
    if noFlash == self.visualNoFlash and noSmoke == self.visualNoSmoke then
        return
    end

    if noFlash ~= self.visualNoFlash then
        self.visualNoFlash = noFlash
        if noFlash then
            self:_startFlashVisuals()
        else
            self:_stopFlashVisuals()
        end
    end
    if noSmoke ~= self.visualNoSmoke then
        self.visualNoSmoke = noSmoke
        if noSmoke then
            for candidate in pairs(self.smokeCandidates) do
                self:_attachSmokeVisual(candidate)
            end
        else
            self:_stopSmokeVisuals()
        end
    end
end

function Effects:renderTrajectory(path)
    self.trajectoryRenderer:render(path)
end

function Effects:stop()
    self:_stopSmokeVisuals()
    Effects.updateVisualSuppressions({}, {}, self.suppressedVisuals)
    self:_disconnectVisualRoots()
    for _, connection in ipairs(self.tagConnections) do
        disconnect(connection)
    end
    self.tagConnections = {}
    self.trajectoryRenderer:stop()
end

return Effects
]],
        ["games/rivals/world/ObservationRuntime.lua"] = [[local ObservationRuntime = {}
ObservationRuntime.__index = ObservationRuntime

function ObservationRuntime.rangeHealth(humanoid)
    local health = humanoid.Health
    local maximum = humanoid.MaxHealth
    if health == math.huge or maximum == math.huge then
        return 150, 150
    end
    return health, maximum
end

function ObservationRuntime.new(options)
    assert(options and options.targeting, "RIVALS observations require Hydroxide Targeting")
    assert(options.workspace, "RIVALS observations require Workspace")
    assert(options.getFighter, "RIVALS observations require a fighter getter")
    return setmetatable({
        effects = options.effects,
        equippedWeapon = options.equippedWeapon,
        getFighter = options.getFighter,
        getPlayerTone = options.getPlayerTone,
        isOpponent = options.isOpponent,
        maximumDistance = options.maximumDistance or 2000,
        targeting = options.targeting,
        workspace = options.workspace,
    }, ObservationRuntime)
end

function ObservationRuntime:update(screenOrigin, includeTeammates, includeEnemies)
    local raycastIgnore = self.effects and self.effects:smokeRaycastIgnore() or {}
    local eligibility = self.isOpponent
    if includeTeammates and self.getPlayerTone then
        eligibility = function(player, character)
            return self.getPlayerTone(player, character) ~= nil
        end
    end
    local observations = self.targeting.observePlayers({
        isEligible = eligibility,
        raycastIgnore = raycastIgnore,
        screenOrigin = screenOrigin,
    })
    local fighter = self.getFighter()
    local data = fighter and fighter.Data
    local camera = self.workspace.CurrentCamera
    local rangeEntities = self.workspace:FindFirstChild("ShootingRangeEntities")
    if type(data) == "table" and data.IsInShootingRange and camera and rangeEntities then
        local containers = { rangeEntities }
        local hurtEffect = self.workspace:FindFirstChild("HurtEffect")
        if hurtEffect then
            table.insert(containers, hurtEffect)
        end
        for _, container in ipairs(containers) do
            for _, entity in ipairs(container:GetChildren()) do
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local environmentID = entity:GetAttribute("EnvironmentID")
                if
                    entity:IsA("Model")
                    and humanoid
                    and humanoid.Health > 0
                    and (data.EnvironmentID == nil or environmentID == data.EnvironmentID)
                then
                    local observation = self.targeting.observeCharacter(entity, {
                        screenOrigin = screenOrigin,
                    })
                    if observation then
                        observation.player = entity
                        observation.health, observation.maxHealth =
                            ObservationRuntime.rangeHealth(humanoid)
                        table.insert(observations, observation)
                    end
                end
            end
        end
    end
    local cameraFrame = camera
        and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    local cameraPosition = cameraFrame and cameraFrame.Position
    local nearby = {}
    if cameraPosition then
        for _, observation in ipairs(observations) do
            if
                observation.position
                and (observation.position - cameraPosition).Magnitude <= self.maximumDistance
            then
                table.insert(nearby, observation)
            end
        end
    end
    for _, observation in ipairs(nearby) do
        if observation.player ~= observation.character then
            local character = observation.character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health or nil
            observation.maxHealth = humanoid and humanoid.MaxHealth or nil
            observation.weapon = self.equippedWeapon and self.equippedWeapon(observation.player)
                or nil
            observation.tone = self.getPlayerTone
                    and self.getPlayerTone(observation.player, character)
                or "enemy"
        end
    end
    local opponents = {}
    local allies = {}
    for _, observation in ipairs(nearby) do
        if observation.player ~= observation.character and observation.tone == "team" then
            table.insert(allies, observation)
        else
            table.insert(opponents, observation)
        end
    end
    if includeTeammates and includeEnemies ~= false then
        local visual = {}
        for _, observation in ipairs(opponents) do
            table.insert(visual, observation)
        end
        for _, observation in ipairs(allies) do
            table.insert(visual, observation)
        end
        return opponents, visual
    end
    if includeTeammates then
        return opponents, allies
    end
    if includeEnemies == false then
        return opponents, {}
    end
    return opponents, opponents
end

return ObservationRuntime
]],
        ["games/rivals/world/TrajectoryRenderer.lua"] = [[local TrajectoryRenderer = {}
TrajectoryRenderer.__index = TrajectoryRenderer

function TrajectoryRenderer.new(options)
    local canvas
    if options.limn and options.limn:supportsPrimitive("Line") then
        canvas = options.limn:createCanvas()
    end
    return setmetatable({
        canvas = canvas,
        lines = {},
        projectileAim = options.projectileAim,
        workspace = options.workspace,
    }, TrajectoryRenderer)
end

function TrajectoryRenderer:render(path)
    if not self.canvas or path == nil and #self.lines == 0 then
        return
    end
    local camera = self.workspace.CurrentCamera
    local segments = camera and path and self.projectileAim.projectTrajectory(camera, path) or {}
    for index, segment in ipairs(segments) do
        local line = self.lines[index]
        if not line then
            line = self.canvas:create("Line")
            self.lines[index] = line
        end
        line:patch({
            Color = Color3.fromRGB(92, 214, 255),
            From = segment.from,
            Thickness = 2,
            To = segment.to,
            Transparency = 0.9,
            Visible = true,
            ZIndex = 20,
        })
    end
    for index = #segments + 1, #self.lines do
        self.lines[index]:patch({ Visible = false })
    end
end

function TrajectoryRenderer:stop()
    if self.canvas then
        self.canvas:destroy()
        self.canvas = nil
    end
    table.clear(self.lines)
end

return TrajectoryRenderer
]],
        ["games/rivals/world/UtilityPolicy.lua"] = [[local UtilityPolicy = {}

local TAG_DESCRIPTORS = {
    FireHitbox = { label = "FIRE", tone = "danger" },
    JumpPadHitbox = { label = "JUMP PAD", tone = "accent" },
    SmokeCloud = { label = "SMOKE", tone = "smoke" },
    SubspaceTripmine = {
        label = "TRIPMINE",
        markerStyle = "wireframeCube",
        tone = "danger",
    },
}

UtilityPolicy.TAGS = {
    "FireHitbox",
    "JumpPadHitbox",
    "SmokeCloud",
    "SubspaceTripmine",
}

local function method(instance, name)
    if not instance then
        return nil
    end
    local succeeded, value = pcall(function()
        return instance[name]
    end)
    return succeeded and type(value) == "function" and value or nil
end

local function hasTag(instance, tag)
    local hasTagMethod = method(instance, "HasTag")
    if hasTagMethod then
        local succeeded, tagged = pcall(hasTagMethod, instance, tag)
        return succeeded and tagged == true
    end
    local getTags = method(instance, "GetTags")
    if getTags then
        local succeeded, tags = pcall(getTags, instance)
        return succeeded and type(tags) == "table" and table.find(tags, tag) ~= nil
    end
    return false
end

local function attribute(instance, name)
    local getAttribute = method(instance, "GetAttribute")
    if not getAttribute then
        return nil
    end
    local succeeded, value = pcall(getAttribute, instance, name)
    return succeeded and value or nil
end

function UtilityPolicy.descriptor(instance)
    local current = instance
    for _depth = 1, 3 do
        if not current then
            break
        end
        for tag, descriptor in pairs(TAG_DESCRIPTORS) do
            if hasTag(current, tag) then
                return descriptor, current
            end
        end
        if attribute(current, "ThrowableOrientation") ~= nil then
            return { label = "THROWABLE", tone = "accent" }, current
        end
        current = current.Parent
    end
    return nil
end

function UtilityPolicy.effectKind(instance)
    if hasTag(instance, "SmokeCloud") then
        return "smoke"
    end
    if instance and (instance.Name == "Flashbang" or instance.Name == "FlashbangGui") then
        return "flash"
    end
    return nil
end

return UtilityPolicy
]],
        ["games/rivals/world/VisualSuppression.lua"] = [[local UtilityPolicy = require("./UtilityPolicy")
local VisualSuppression = {}

local VISUAL_EFFECT_CLASSES = {
    Beam = true,
    BlurEffect = true,
    ColorCorrectionEffect = true,
    DepthOfFieldEffect = true,
    Frame = true,
    ImageLabel = true,
    ParticleEmitter = true,
    Smoke = true,
}

local function effectStateProperty(instance)
    local supported = false
    if instance.IsA then
        for className in pairs(VISUAL_EFFECT_CLASSES) do
            if instance:IsA(className) then
                supported = true
                break
            end
        end
    end
    if not supported then
        return nil
    end
    local enabledOk, enabled = pcall(function()
        return instance.Enabled
    end)
    if enabledOk and type(enabled) == "boolean" then
        return "Enabled", enabled
    end
    local visibleOk, visible = pcall(function()
        return instance.Visible
    end)
    if visibleOk and type(visible) == "boolean" then
        return "Visible", visible
    end
    return nil
end

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        pcall(connection.Disconnect, connection)
    end
end

local function restore(instance, state, suppressed)
    disconnect(state.connection)
    local succeeded, current = pcall(function()
        return instance[state.property]
    end)
    if not succeeded or current ~= state.value then
        pcall(function()
            instance[state.property] = state.value
        end)
    end
    suppressed[instance] = nil
end

local function suppress(instance, kind, suppressed)
    local property, value = effectStateProperty(instance)
    if not property then
        return false
    end

    local state = suppressed[instance]
    if not state then
        state = {
            kind = kind,
            property = property,
            value = value,
        }
        suppressed[instance] = state
        local methodOk, getPropertyChangedSignal = pcall(function()
            return instance.GetPropertyChangedSignal
        end)
        if methodOk and type(getPropertyChangedSignal) == "function" then
            local signalOk, signal = pcall(getPropertyChangedSignal, instance, property)
            if signalOk and signal and type(signal.Connect) == "function" then
                local connectionOk, connection = pcall(signal.Connect, signal, function()
                    local readOk, current = pcall(function()
                        return instance[property]
                    end)
                    if readOk and current == true then
                        pcall(function()
                            instance[property] = false
                        end)
                    end
                end)
                if connectionOk then
                    state.connection = connection
                end
            end
        end
    end

    local readOk, current = pcall(function()
        return instance[property]
    end)
    if readOk and current ~= false then
        pcall(function()
            instance[property] = false
        end)
    end
    return true
end

local function visit(settings, roots, suppressed, active)
    for _, entry in ipairs(roots or {}) do
        local root = entry
        local inheritedKind
        if type(entry) == "table" and entry.instance then
            root = entry.instance
            inheritedKind = entry.kind
        end
        local instances = { root }
        if root and root.GetDescendants then
            local succeeded, descendants = pcall(root.GetDescendants, root)
            if succeeded then
                for _, descendant in ipairs(descendants or {}) do
                    table.insert(instances, descendant)
                end
            end
        end
        for _, instance in ipairs(instances) do
            local kind = UtilityPolicy.effectKind(instance) or inheritedKind
            local shouldSuppress = kind == "flash" and settings.noFlash == true
                or kind == "smoke" and settings.noSmoke == true
            if shouldSuppress and suppress(instance, kind, suppressed) and active then
                active[instance] = true
            end
        end
    end
end

-- Applies only the supplied roots and retains all existing registrations. This is
-- used by event callbacks so a single added effect never forces a broad rescan.
function VisualSuppression.apply(settings, roots, suppressed)
    visit(settings, roots, suppressed)
end

function VisualSuppression.restoreRoots(roots, suppressed)
    local selected = {}
    for _, entry in ipairs(roots or {}) do
        local root = entry
        if type(entry) == "table" and entry.instance then
            root = entry.instance
        end
        selected[root] = true
    end
    for instance, state in pairs(suppressed) do
        local current = instance
        local matches = false
        for _depth = 1, 64 do
            if not current then
                break
            end
            if selected[current] then
                matches = true
                break
            end
            current = current.Parent
        end
        if matches then
            restore(instance, state, suppressed)
        end
    end
end

function VisualSuppression.update(settings, roots, suppressed)
    local active = {}
    visit(settings, roots, suppressed, active)
    for instance, state in pairs(suppressed) do
        if not active[instance] then
            restore(instance, state, suppressed)
        end
    end
end

return VisualSuppression
]],
        ["games/rivals/world/WorldPolicy.lua"] = [[local WorldPolicy = {}

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        connection:Disconnect()
    end
end

local function connect(signal, callback)
    if signal and type(signal.Connect) == "function" then
        local ok, connection = pcall(signal.Connect, signal, callback)
        return ok and connection or nil
    end
    local event = signal and signal.Event
    if event and type(event.Connect) == "function" then
        local ok, connection = pcall(event.Connect, event, callback)
        return ok and connection or nil
    end
    return nil
end

local function value(fighter, key)
    if type(fighter) ~= "table" then
        return nil
    end
    if type(fighter.Get) == "function" then
        local ok, result = pcall(fighter.Get, fighter, key)
        if ok and result ~= nil then
            return result
        end
    end
    local data = fighter.Data
    return type(data) == "table" and data[key] or nil
end

local function connectFighterValue(fighter, key, callback)
    local events = type(fighter) == "table" and fighter._value_changed_events
    return type(events) == "table" and connect(events[key], callback) or nil
end

function WorldPolicy.new(options)
    assert(type(options) == "table", "RIVALS world policy requires options")
    assert(options.workspace, "RIVALS world policy requires Workspace")
    assert(
        type(options.getLocalFighter) == "function",
        "RIVALS world policy requires a fighter getter"
    )
    assert(type(options.isOpponent) == "function", "RIVALS world policy requires opponent policy")
    assert(
        type(options.getPlayerTone) == "function",
        "RIVALS world policy requires player-tone policy"
    )
    assert(type(options.getWeapon) == "function", "RIVALS world policy requires weapon labels")

    local workspace = options.workspace
    local getLocalFighter = options.getLocalFighter
    return {
        isPlayerEligible = options.isOpponent,
        getPlayerTone = options.getPlayerTone,
        getWeapon = options.getWeapon,
        connectPlayerChanged = function(player, invalidate)
            local connections = {}
            if player and player.GetAttributeChangedSignal then
                table.insert(
                    connections,
                    player:GetAttributeChangedSignal("EnvironmentID"):Connect(invalidate)
                )
                table.insert(
                    connections,
                    player:GetAttributeChangedSignal("TeamID"):Connect(invalidate)
                )
            end
            local fighter = type(options.getFighter) == "function" and options.getFighter(player)
                or nil
            local equippedChanged = fighter and fighter.EquippedItemChanged
            local equippedConnection = connect(equippedChanged, invalidate)
            if equippedConnection then
                table.insert(connections, equippedConnection)
            end
            return function()
                for _, connection in ipairs(connections) do
                    disconnect(connection)
                end
            end
        end,
        subscribeChanged = function(invalidate)
            local player = options.localPlayer
            if not player or not player.GetAttributeChangedSignal then
                return nil
            end
            local connections = {
                player:GetAttributeChangedSignal("EnvironmentID"):Connect(invalidate),
                player:GetAttributeChangedSignal("TeamID"):Connect(invalidate),
            }
            return function()
                for _, connection in ipairs(connections) do
                    disconnect(connection)
                end
            end
        end,
        subscribeExtras = function(onAdd, onRemove)
            assert(type(onAdd) == "function" and type(onRemove) == "function")
            local stopped = false
            local connections = {}
            local entityConnections = {}
            local entities = {}
            local emitted = {}
            local folder

            local function remember(connection, target)
                if connection then
                    table.insert(target or connections, connection)
                end
            end

            local function removeEmission(entity)
                if emitted[entity] then
                    emitted[entity] = nil
                    onRemove(entity)
                end
            end

            local function descriptor(entity)
                if not entity or type(entity.IsA) ~= "function" or not entity:IsA("Model") then
                    return nil
                end
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local rootPart = entity:FindFirstChild("HumanoidRootPart")
                if
                    not humanoid
                    or not rootPart
                    or type(humanoid.Health) ~= "number"
                    or humanoid.Health <= 0
                then
                    return nil
                end
                local fighter = getLocalFighter()
                local environmentID = value(fighter, "EnvironmentID")
                local entityEnvironmentID = entity:GetAttribute("EnvironmentID")
                if environmentID ~= nil and entityEnvironmentID ~= environmentID then
                    return nil
                end
                return {
                    key = entity,
                    character = entity,
                    humanoid = humanoid,
                    rootPart = rootPart,
                    name = entity.Name,
                }
            end

            local function active()
                return value(getLocalFighter(), "IsInShootingRange") == true
            end

            local function syncEntity(entity)
                if stopped or not entities[entity] then
                    return
                end
                local nextDescriptor = active() and descriptor(entity) or nil
                if nextDescriptor then
                    if not emitted[entity] then
                        emitted[entity] = true
                        onAdd(nextDescriptor)
                    end
                else
                    removeEmission(entity)
                end
            end

            local function untrackEntity(entity)
                entities[entity] = nil
                removeEmission(entity)
                for _, connection in ipairs(entityConnections[entity] or {}) do
                    disconnect(connection)
                end
                entityConnections[entity] = nil
            end

            local function trackEntity(entity)
                if stopped or entities[entity] then
                    return
                end
                entities[entity] = true
                local owned = {}
                entityConnections[entity] = owned
                if entity.GetAttributeChangedSignal then
                    remember(
                        connect(entity:GetAttributeChangedSignal("EnvironmentID"), function()
                            syncEntity(entity)
                        end),
                        owned
                    )
                end
                if entity.ChildAdded then
                    remember(
                        connect(entity.ChildAdded, function()
                            syncEntity(entity)
                        end),
                        owned
                    )
                end
                if entity.ChildRemoved then
                    remember(
                        connect(entity.ChildRemoved, function()
                            syncEntity(entity)
                        end),
                        owned
                    )
                end
                local humanoid = entity.FindFirstChildOfClass
                    and entity:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    if humanoid.HealthChanged then
                        remember(
                            connect(humanoid.HealthChanged, function()
                                syncEntity(entity)
                            end),
                            owned
                        )
                    elseif humanoid.GetPropertyChangedSignal then
                        remember(
                            connect(humanoid:GetPropertyChangedSignal("Health"), function()
                                syncEntity(entity)
                            end),
                            owned
                        )
                    end
                    if humanoid.Died then
                        remember(
                            connect(humanoid.Died, function()
                                syncEntity(entity)
                            end),
                            owned
                        )
                    end
                end
                syncEntity(entity)
            end

            local folderConnections = {}
            local activeConnections = {}
            local rangeActive = false
            local function detachFolder()
                for _, connection in ipairs(folderConnections) do
                    disconnect(connection)
                end
                table.clear(folderConnections)
                local tracked = {}
                for entity in pairs(entities) do
                    table.insert(tracked, entity)
                end
                for _, entity in ipairs(tracked) do
                    untrackEntity(entity)
                end
                folder = nil
            end

            local function attachFolder(nextFolder)
                if not rangeActive or folder == nextFolder then
                    return
                end
                detachFolder()
                folder = nextFolder
                if not folder then
                    return
                end
                if folder.ChildAdded then
                    remember(connect(folder.ChildAdded, trackEntity), folderConnections)
                end
                if folder.ChildRemoved then
                    remember(connect(folder.ChildRemoved, untrackEntity), folderConnections)
                end
                for _, entity in ipairs(folder:GetChildren()) do
                    trackEntity(entity)
                end
            end

            local function syncAll()
                if stopped or not rangeActive then
                    return
                end
                for entity in pairs(entities) do
                    syncEntity(entity)
                end
            end

            local function deactivateRange()
                if not rangeActive then
                    return
                end
                rangeActive = false
                detachFolder()
                for _, connection in ipairs(activeConnections) do
                    disconnect(connection)
                end
                table.clear(activeConnections)
            end

            local function activateRange()
                if rangeActive or stopped then
                    return
                end
                rangeActive = true
                if workspace.ChildAdded then
                    remember(
                        connect(workspace.ChildAdded, function(child)
                            if child.Name == "ShootingRangeEntities" then
                                attachFolder(child)
                            end
                        end),
                        activeConnections
                    )
                end
                if workspace.ChildRemoved then
                    remember(
                        connect(workspace.ChildRemoved, function(child)
                            if child == folder then
                                detachFolder()
                            end
                        end),
                        activeConnections
                    )
                end
                attachFolder(workspace:FindFirstChild("ShootingRangeEntities"))
            end

            local function syncActive()
                if stopped then
                    return
                end
                if active() then
                    activateRange()
                else
                    deactivateRange()
                end
            end

            local fighter = getLocalFighter()
            remember(connectFighterValue(fighter, "IsInShootingRange", syncActive))
            remember(connectFighterValue(fighter, "EnvironmentID", function()
                syncActive()
                syncAll()
            end))
            syncActive()

            return function()
                if stopped then
                    return
                end
                deactivateRange()
                stopped = true
                for _, connection in ipairs(connections) do
                    disconnect(connection)
                end
                table.clear(connections)
            end
        end,
    }
end

return WorldPolicy
]],
    },
}
