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

local Targeting = importDependency("games/rivals/Targeting", "./Targeting")
local ProjectileAim = importDependency("games/rivals/ProjectileAim", "./ProjectileAim")
local HookRuntime = importDependency("games/rivals/HookRuntime", "./HookRuntime")
local WeaponPolicy = importDependency("games/rivals/WeaponPolicy", "./WeaponPolicy")
local Effects = importDependency("games/rivals/Effects", "./Effects")
local Movement = importDependency("games/rivals/Movement", "./Movement")
local CombatState = importDependency("games/rivals/CombatState", "./CombatState")
local ModePolicy = importDependency("games/rivals/ModePolicy", "./ModePolicy")
local GunGameRuntime = importDependency("games/rivals/GunGameRuntime", "./GunGameRuntime")
local ObservationRuntime = importDependency("games/rivals/ObservationRuntime", "./ObservationRuntime")

local Rivals = {}

local TRIGGER_INTERVAL = 0.1
local TRIGGER_RADIUS = 8
local RICOCHET_CACHE_INTERVAL = 0.15
local SPLASH_CACHE_INTERVAL = 0.1
local SLINGSHOT_CACHE_INTERVAL = 0.2
local SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS = 65

function Rivals.isOpponent(localPlayer, player, character)
    if player == localPlayer or not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end

    if localPlayer:GetAttribute("EnvironmentID") ~= player:GetAttribute("EnvironmentID") then
        return false
    end

    local localTeam = localPlayer:GetAttribute("TeamID")
    local playerTeam = player:GetAttribute("TeamID")
    return localTeam == nil or playerTeam == nil or localTeam ~= playerTeam
end

function Rivals.capabilityContext(context)
    context = context or {}
    local duelController = context.duelController
    local player = context.player
    if not duelController then
        local gameObject = context.game or game
        local players = gameObject:GetService("Players")
        player = player or players.LocalPlayer
        local controllers = player.PlayerScripts:WaitForChild("Controllers")
        local duelControllerModule = controllers:WaitForChild("DuelController")
        duelController = (context.requireModule or require)(duelControllerModule)
    end
    return {
        isGunGame = ModePolicy.controllerIsGunGame(duelController, player),
    }
end

function Rivals.capabilitiesFor(context, declaredCapabilities)
    context = context or {}
    local autoPickupAvailable = context.isGunGame == true
        and context.fireTouchInterestAvailable == true
    local hookFeaturesAvailable = context.hookFunctionAvailable == true
        and context.restoreFunctionAvailable == true
    local capabilities = {}
    for _, capability in ipairs(declaredCapabilities or {}) do
        local available = capability ~= "autoPickup" or autoPickupAvailable
        if capability == "shotAim" or capability == "alwaysScoped" then
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
    if not Rivals.isOpponent(localPlayer, player, character)
        or character:FindFirstChildOfClass("ForceField") ~= nil
    then
        return false
    end

    return isGunGame ~= true
        or not Rivals.entityIsInvincible(fighter and fighter.Entity)
end

function Rivals.new(context)
    assert(context and context.oh, "RIVALS adapter requires Hydroxide")
    assert(context.store, "RIVALS adapter requires a reactive store")
    assert(context.press and context.release, "RIVALS adapter requires held input support")
    assert(context.aimClick, "RIVALS adapter requires secondary click support")
    assert(context.aimPress and context.aimRelease, "RIVALS adapter requires held aiming support")

    local clock = context.clock or os.clock
    local itemClock = context.itemClock or tick
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
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
    local CameraController = loadModule(cameraControllerModule)
    local DuelController = loadModule(duelControllerModule)
    local FighterController = loadModule(fighterControllerModule)
    local ControlsController = loadModule(controlsControllerModule)
    local MechanicsController = loadModule(mechanicsControllerModule)
    local function isGunGame()
        return ModePolicy.controllerIsGunGame(DuelController, LocalPlayer)
    end
    local PickWeaponsPage = context.pickWeaponsPage or loadModule(
        LocalPlayer.PlayerScripts:WaitForChild("Modules")
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
    local stopped = false
    local nextTriggerAt = 0
    local triggerHeld = false
    local triggerHeldAt = 0
    local triggerHeldItem
    local gunbladeComboState
    local fireHeld = false
    local fireHeldItem
    local ricochetCache
    local splashCache
    local slingshotCache
    local aimPlan
    local aimTargetKey
    local aimTargetWeapon
    local humanAimCharacter
    local humanAimState
    local renderDelta = 1 / 60
    local observations = {}
    local self = {}
    local getNetworkPing = context.getNetworkPing or function()
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
    local observeThrowables = context.observeThrowables or function(camera, environmentID)
        return effects:observeThrowables(camera, environmentID)
    end

    local function releaseFire()
        if not fireHeld then
            return
        end
        context.release()
        fireHeld = false
        fireHeldItem = nil
    end

    local function fighterFor(player)
        if player == LocalPlayer then
            return FighterController.LocalFighter
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
        local item = fighter and fighter.EquippedItem
        local data = item and item.Data
        return WeaponPolicy.isDeflector(item)
            and type(data) == "table"
            and data.FOVOffset == 5
    end

    local function localFighterIsActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return fighter ~= nil
            and CameraController._current_subject == fighter
            and humanoid ~= nil
            and humanoid.Health > 0
    end

    local function localFighterIsInCombat()
        local fighter = FighterController.LocalFighter
        return CombatState.isCombatEligible(
            fighter,
            DuelController:GetDuel(LocalPlayer),
            PickWeaponsPage:IsOpen()
        )
    end

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
        controlsController = ControlsController,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        getSettings = function()
            return store:Get().settings
        end,
        isActive = localFighterIsActive,
        isInCombat = localFighterIsInCombat,
        isInputCaptured = context.isInputCaptured,
        mechanicsController = MechanicsController,
        movementDirection = context.movementDirection,
        shouldSuppressJump = function()
            return suppressBhopJump
        end,
        spawn = spawn,
        userInputService = UserInputService,
    })

    local function isOpponent(player, character)
        return Rivals.isOpponent(LocalPlayer, player, character)
    end

    local function isTargetable(player, character)
        return Rivals.isTargetable(
            LocalPlayer,
            player,
            character,
            fighterFor(player),
            isGunGame()
        )
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

    local function selectTarget(maxScreenDistance, includeBlocked)
        local settings = store:Get().settings
        local options = {
            includeBlocked = includeBlocked,
            isEligible = isTargetable,
            screenOrigin = UserInputService:GetMouseLocation(),
        }
        if maxScreenDistance then
            options.maxScreenDistance = maxScreenDistance
        elseif not settings.fullScreenAim then
            options.maxScreenDistance = settings.fov
        end
        local function nearest(values)
            local eligible = {}
            for _, observation in ipairs(values) do
                if observation.player == observation.character
                    or isTargetable(observation.player, observation.character)
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
                local damage = candidate
                    and WeaponPolicy.finishingDamage(item, candidate, distance)
                return type(damage) == "number"
                    and type(candidate.health) == "number"
                    and damage >= candidate.health
                    and candidate
                    or nil
            end
            selected = Rivals.lowestHealthObservation(observations, finishable, nearest)
                or Rivals.lowestHealthObservation(observations, accepted, nearest)
                or nearest(observations)
            aimTargetKey = selected
                and (selected.character or selected.player or selected.part)
                or nil
        else
            selected, aimTargetKey = Targeting.selectObservation(
                observations,
                aimTargetKey,
                nearest
            )
        end
        return selected
    end

    local function selectBackstabTarget(localPosition, info, acquisitionDistance)
        local nearest
        local nearestDistance = math.huge
        local lowestHealth = math.huge
        for _, observation in ipairs(observations) do
            local character = observation.character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local plan = WeaponPolicy.backstabPlan(
                localPosition,
                observation,
                info,
                acquisitionDistance
            )
            if observation.visible
                and isTargetable(observation.player, character)
                and root
                and plan
            then
                local distance = (localPosition - root.Position).Magnitude
                local health = type(observation.health) == "number"
                        and observation.health
                    or math.huge
                local preferred = isGunGame()
                        and (health < lowestHealth
                            or health == lowestHealth and distance < nearestDistance)
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
                local result = position and gunbladeRaycast
                    and gunbladeRaycast(localRoot.Position, position - localRoot.Position)
                local instance = result and result.Instance
                local clear = not instance
                    or instance.IsDescendantOf
                        and instance:IsDescendantOf(character)
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

    local function plannedAimTarget(target, item)
        local now = clock()
        local settings = store:Get().settings
        local options = headAimOptions()
        if aimPlan
            and aimPlan.character == target.character
            and aimPlan.headshotRate == settings.headshotRate
            and aimPlan.humanAim == settings.humanAim
            and aimPlan.item == item
            and aimPlan.missRate == settings.missRate
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
        local planned = Targeting.applyAimRates(target, settings, random, options)
        aimPlan = {
            character = target.character,
            expiresAt = now + math.max(TRIGGER_INTERVAL, cooldown or TRIGGER_INTERVAL),
            headshotRate = settings.headshotRate,
            humanAim = settings.humanAim,
            item = item,
            missRate = settings.missRate,
            target = planned,
        }
        return planned
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
    local solveRicochet = context.solveRicochet or ProjectileAim.solveRicochet
    local solveSplashAim = context.solveSplashAim or ProjectileAim.solveSplashAim
    local solveBouncingProjectile = context.solveBouncingProjectile or ProjectileAim.solveBouncingProjectile

    local observationRuntime = ObservationRuntime.new({
        effects = effects,
        equippedWeapon = equippedWeapon,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        isOpponent = isOpponent,
        targeting = targeting,
        workspace = Workspace,
    })

    local function setAimRotation(rotation, instant, character, maximumHumanSmoothness)
        local applied = rotation
        if instant then
            CameraController:SetRotation(rotation)
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
        local pitchError = math.abs(rotation.X - applied.X)
        local yawError = math.abs((rotation.Y - applied.Y + math.pi) % (math.pi * 2) - math.pi)
        return math.max(pitchError, yawError) <= math.rad(0.5)
    end

    local function alignCamera(shotOnly)
        local settings = store:Get().settings
        local enabled = shotOnly and settings.shotAim
            or (settings.silentAim and not settings.shotAim)
        if not enabled
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
        then
            if not settings.silentAim
                and not settings.shotAim
                or context.isInputCaptured()
                or not localFighterIsActive()
                or not localFighterIsInCombat()
            then
                aimTargetKey = nil
                aimTargetWeapon = nil
            end
            return nil
        end
        local function settleAim(rotation, instant, character, maximumSmoothness)
            if shotOnly then
                return true
            end
            return setAimRotation(
                rotation,
                instant,
                character,
                maximumSmoothness
            )
        end

        local fighter = FighterController.LocalFighter
        local item = fighter and fighter.EquippedItem
        local automationPolicy = WeaponPolicy.automationPolicy(item)
        local aimMode = shotOnly and "silentAim" or "cameraAim"
        if automationPolicy[aimMode] ~= true then
            aimTargetKey = nil
            aimTargetWeapon = nil
            aimPlan = nil
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
            aimTargetKey = nil
            aimTargetWeapon = nil
            target = localRoot and selectBackstabTarget(localRoot.Position, item.Info)
        else
            if aimTargetWeapon ~= item then
                aimTargetKey = nil
                aimTargetWeapon = item
            end
            target = selectTarget(nil, energyRifle or slingshot or splashProjectile)
        end
        local camera = Workspace.CurrentCamera
        if not target or not camera then
            if not target then
                aimTargetKey = nil
            end
            return nil
        end
        if not knife then
            aimTargetKey = target.character or target.player or target.part
        end

        local cameraFrame = camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
        local origin = cameraFrame.Position
        local now = clock()
        if knife then
            local plan = target.backstabPlan
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, plan.aimPosition),
                true,
                target.character
            )
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
        target = plannedAimTarget(target, item)

        if slingshot and target.position then
            local cacheValid = slingshotCache
                and slingshotCache.target == target.character
                and now < slingshotCache.expiresAt
                and (slingshotCache.origin - origin).Magnitude <= 0.5
                and (slingshotCache.targetPosition - target.position).Magnitude <= 0.5
            if not cacheValid then
                slingshotCache = {
                    expiresAt = now + SLINGSHOT_CACHE_INTERVAL,
                    origin = origin,
                    solution = solveBouncingProjectile(
                        origin,
                        target,
                        item.Info,
                        environmentRaycast(),
                        Workspace.Gravity,
                        getNetworkPing()
                    ),
                    target = target.character,
                    targetPosition = target.position,
                }
            end

            if slingshotCache.solution then
                local aimSettled = settleAim(
                    Targeting.rotationToward(origin, origin + slingshotCache.solution.direction),
                    false,
                    target.character,
                    SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.slingshot = slingshotCache.solution
                aligned.visible = true
                return aligned
            end
        else
            slingshotCache = nil
        end

        if splashProjectile and target.position then
            local raycast = environmentRaycast()
            local cacheValid = splashCache
                and splashCache.target == target.character
                and splashCache.item == item
                and now < splashCache.expiresAt
                and (splashCache.origin - origin).Magnitude <= 0.5
                and (splashCache.targetPosition - target.position).Magnitude <= 0.5
                and (
                    not splashCache.solution
                    or ProjectileAim.isSplashSolutionCurrent(
                        origin,
                        splashCache.solution,
                        item.Info,
                        raycast,
                        Workspace.Gravity
                    )
                )
            if not cacheValid then
                splashCache = {
                    expiresAt = now + SPLASH_CACHE_INTERVAL,
                    item = item,
                    origin = origin,
                    solution = solveSplashAim(
                        origin,
                        target,
                        item.Info,
                        raycast,
                        Workspace.Gravity
                    ),
                    target = target.character,
                    targetPosition = target.position,
                }
            end

            if splashCache.solution then
                local aimSettled = settleAim(
                    Targeting.rotationToward(origin, origin + splashCache.solution.direction),
                    false,
                    target.character
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.splashImpact = splashCache.solution
                aligned.visible = true
                return aligned
            end
        else
            splashCache = nil
        end
        if splashProjectile then
            return nil
        end

        if target.visible and ProjectileAim.isDirectProjectile(item) then
            local solution = ProjectileAim.solveProjectileAim(
                origin,
                target,
                item.Info,
                Workspace.Gravity,
                shotOnly and renderDelta or 0
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
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, target.position),
                false,
                target.character
            )
            ricochetCache = nil
            local aligned = table.clone(target)
            aligned.aimSettled = aimSettled
            return aligned
        end
        if not energyRifle or not target.position then
            return nil
        end

        local cacheValid = ricochetCache
            and ricochetCache.target == target.character
            and now < ricochetCache.expiresAt
            and (ricochetCache.origin - origin).Magnitude <= 0.5
            and (ricochetCache.targetPosition - target.position).Magnitude <= 0.5
        if not cacheValid then
            ricochetCache = {
                direction = solveRicochet(origin, target.position, environmentRaycast()),
                expiresAt = now + RICOCHET_CACHE_INTERVAL,
                origin = origin,
                target = target.character,
                targetPosition = target.position,
            }
        end

        local solution = ricochetCache.direction
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

    local function silentAimPoint(aligned, origin, distance)
        local solution = aligned
            and (aligned.slingshot
                or aligned.splashImpact
                or aligned.projectileAim
                or aligned.ricochet)
        if solution and typeof(solution.direction) == "Vector3" then
            return origin + solution.direction.Unit * distance
        end
        return aligned and aligned.position
    end

    local hookRuntime = HookRuntime.new({
        capabilities = context.capabilities,
        hookFunction = context.hookFunction,
        restoreFunction = context.restoreFunction,
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

    local function updateShotAimPresentation(aligned)
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local origin = cameraFrame and cameraFrame.Position
        local point = origin
            and silentAimPoint(aligned, origin, ProjectileAim.MAX_DISTANCE)
        if not point then
            shotPresentation:clear()
            return nil
        end
        shotPresentation:update(Targeting.rotationToward(origin, point), aligned)
        return shotPresentation:getPresentedTarget()
    end

    local function refreshHooks()
        hookRuntime:refresh()
    end

    local function runTriggerBot(alignedTarget)
        local settings = store:Get().settings
        if not settings.triggerBot
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
        then
            gunbladeComboState = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end
        local fighter = FighterController.LocalFighter
        local item = fighter and fighter.EquippedItem
        if WeaponPolicy.automationPolicy(item).triggerBot ~= true then
            gunbladeComboState = nil
            aimPlan = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end
        local gunblade = WeaponPolicy.isDualModeBlade(item)
        if not gunblade and alignedTarget and alignedTarget.aimSettled == false then
            local humanReticleReady = settings.humanAim
                and (alignedTarget.screenDistance or math.huge) <= TRIGGER_RADIUS
                and not alignedTarget.ricochet
                and not alignedTarget.slingshot
                and not alignedTarget.splashImpact
                and not alignedTarget.projectileAim
            if not humanReticleReady then
                releaseFire()
                return
            end
        end

        local target
        if gunblade then
            if settings.shotAim then
                target = alignedTarget
            else
                target = selectDualModeBladeTarget(fighter, item)
            end
        else
            target = alignedTarget
            if not target and not settings.shotAim then
                target = selectTarget(TRIGGER_RADIUS)
            end
        end
        if not target or not target.visible then
            gunbladeComboState = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
                nextTriggerAt = clock() + TRIGGER_INTERVAL
            end
            return
        end
        if not gunblade
            and not alignedTarget
            and (target.screenDistance or math.huge) > TRIGGER_RADIUS
        then
            gunbladeComboState = nil
            releaseFire()
            return
        end
        if isDeflecting(target.player) then
            gunbladeComboState = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end

        if gunblade then
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end

            local entity = fighter and fighter.Entity
            local localRoot = entity and entity.RootPart
            local localPosition = localRoot and localRoot.Position
            local targetPosition = targetRootPosition(target)
            local targetDistance = localPosition
                and targetPosition
                and (targetPosition - localPosition).Magnitude
            local action
            gunbladeComboState, action = WeaponPolicy.gunbladeTriggerAction(
                gunbladeComboState,
                item,
                target.character or target.player or target,
                targetDistance,
                clock()
            )
            if not action then
                return
            end

            local camera = Workspace.CurrentCamera
            local cameraFrame = camera
                and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
            local cameraPosition = cameraFrame and cameraFrame.Position
            local cameraOffset = cameraPosition
                and targetPosition
                and targetPosition - cameraPosition
            local visibleFrame = camera and camera.CFrame
            local visibleRotation = CameraController.Rotation
            if cameraOffset and cameraOffset.Magnitude > 1e-3 then
                CameraController:SetRotation(
                    Targeting.rotationToward(cameraPosition, targetPosition)
                )
                camera.CFrame = CFrame.lookAt(cameraPosition, targetPosition)
            end
            if action.kind == "dash" then
                context.aimClick()
            else
                context.click()
            end
            if visibleFrame then
                camera.CFrame = visibleFrame
            end
            if visibleRotation then
                CameraController:SetRotation(visibleRotation)
            end
            aimPlan = nil
            return
        end
        gunbladeComboState = nil
        if ProjectileAim.isSplashProjectile(item)
            and not (alignedTarget and alignedTarget.splashImpact)
        then
            releaseFire()
            return
        end
        if WeaponPolicy.isBackstabKnife(item) then
            releaseFire()
            if not WeaponPolicy.backstabTriggerReady(
                fighter,
                item,
                alignedTarget,
                isGunGame()
            ) then
                return
            end
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            if clock() < nextTriggerAt then
                return
            end
            nextTriggerAt = clock() + (item.Info.HeavyAttackCooldown or TRIGGER_INTERVAL)
            context.aimClick()
            return
        end
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local targetDistance = cameraFrame
            and target.position
            and (target.position - cameraFrame.Position).Magnitude
        if targetDistance and not WeaponPolicy.triggerDamageReady(item, target, targetDistance) then
            releaseFire()
            return
        end
        local sniperCrouching = WeaponPolicy.isScoped(item)
            and localFighterIsCrouching(fighter)
        if not WeaponPolicy.sniperTriggerReady(
            CameraController,
            item,
            target,
            targetDistance,
            sniperCrouching,
            settings.alwaysScoped == true
        ) then
            releaseFire()
            return
        end
        if item and item.Name == "Revolver" then
            releaseFire()
            local action =
                WeaponPolicy.revolverTriggerAction(item, target, targetDistance, itemClock())
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            if not action or clock() < nextTriggerAt then
                return
            end
            nextTriggerAt = clock() + action.cooldown
            if action.kind == "fan" then
                context.aimClick()
            else
                context.click()
            end
            aimPlan = nil
            return
        end
        if item and item.Name == "Bow" and type(item.Info) == "table" then
            releaseFire()
            if not triggerHeld then
                if clock() < nextTriggerAt then
                    return
                end
                if WeaponPolicy.bowQuickShotLethal(item, target) then
                    nextTriggerAt = clock() + (item.Info.ShootCooldown or TRIGGER_INTERVAL)
                    context.click()
                    aimPlan = nil
                    return
                end
                triggerHeld = true
                triggerHeldAt = clock()
                triggerHeldItem = item
                context.aimPress()
                return
            end
            if triggerHeldItem ~= item then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
                nextTriggerAt = clock() + TRIGGER_INTERVAL
                return
            end
            if clock() - triggerHeldAt + 1e-3 < WeaponPolicy.bowChargeTime(item, target) then
                return
            end

            context.aimRelease()
            triggerHeld = false
            triggerHeldItem = nil
            nextTriggerAt = clock() + (item.Info.ChargeReleaseCooldown or TRIGGER_INTERVAL)
            aimPlan = nil
            return
        end

        if triggerHeld then
            context.aimRelease()
            triggerHeld = false
            triggerHeldItem = nil
        end
        if WeaponPolicy.holdToFire(item) then
            if not WeaponPolicy.adsSettled(CameraController, item) then
                releaseFire()
                return
            end
            if fireHeld and fireHeldItem == item then
                return
            end
            releaseFire()
            if clock() < nextTriggerAt then
                return
            end
            fireHeld = true
            fireHeldItem = item
            context.press()
            aimPlan = nil
            return
        end

        releaseFire()
        if clock() < nextTriggerAt or not WeaponPolicy.adsSettled(CameraController, item) then
            return
        end

        nextTriggerAt = clock() + TRIGGER_INTERVAL
        context.click()
        aimPlan = nil
    end

    local renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if stopped then
            return
        end
        refreshHooks()
        if type(deltaTime) == "number" and deltaTime > 0 then
            renderDelta = deltaTime
        end

        gunGameRuntime:update()
        local settings = store:Get().settings
        local observationsEnabled = settings.silentAim == true
            or settings.shotAim == true
            or settings.triggerBot == true
            or settings.boxes == true
            or settings.chams == true
            or settings.names == true
            or settings.health == true
            or settings.weapon == true
        if observationsEnabled then
            observations = observationRuntime:update(UserInputService:GetMouseLocation())
        elseif #observations > 0 then
            observations = {}
        end
        local utilityObservations = {}
        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        if (settings.utilityEsp or settings.noSmoke)
            and localFighterIsInCombat()
            and Workspace.CurrentCamera
        then
            local environmentID = type(data) == "table" and data.EnvironmentID
                or LocalPlayer:GetAttribute("EnvironmentID")
            local observedUtilities = observeThrowables(Workspace.CurrentCamera, environmentID)
            if settings.utilityEsp then
                utilityObservations = observedUtilities
            end
        end
        effects:update(settings)
        context.render(observations, UserInputService:GetMouseLocation(), utilityObservations)
        local alignedTarget = alignCamera()
        if not alignedTarget and settings.shotAim then
            alignedTarget = alignCamera(true)
        end
        local triggerTarget = alignedTarget
        if settings.shotAim then
            triggerTarget = updateShotAimPresentation(alignedTarget)
        else
            shotPresentation:clear()
        end
        suppressBhopJump = WeaponPolicy.isBackstabKnife(
            fighter and fighter.EquippedItem
        )
            and alignedTarget ~= nil
            and alignedTarget.knifePath ~= nil
        movement:update()
        local trajectory = alignedTarget
            and ((alignedTarget.ricochet and alignedTarget.ricochet.path)
                or (alignedTarget.slingshot and alignedTarget.slingshot.path)
                or alignedTarget.knifePath)
        effects:renderTrajectory(trajectory)
        runTriggerBot(triggerTarget)
    end)

    function self.stop()
        if stopped then
            return
        end
        stopped = true
        gunGameRuntime:stop()
        hookRuntime:stop()
        if triggerHeld then
            context.aimRelease()
            triggerHeld = false
        end
        releaseFire()
        movement:stop()
        effects:stop()
        renderConnection:Disconnect()
    end

    self.capabilities = context.capabilities or {}
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget

    function self:cycleSkin() end
    function self:setWear() end
    function self:toggleStatTrak() end
    function self:resetSkin() end
    function self:cycleGlove() end
    function self:setGloveWear() end
    function self:setGloveColor() end
    function self:resetGlove() end

    return self
end

return Rivals
