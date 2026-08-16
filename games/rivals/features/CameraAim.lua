local RICOCHET_CACHE_INTERVAL = 0.15
local SPLASH_CACHE_INTERVAL = 0.1
local SLINGSHOT_CACHE_INTERVAL = 0.2
local SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS = 65

local CameraAim = {}
CameraAim.__index = CameraAim

function CameraAim.enabled(settings, shotOnly, taskCombatActive)
    settings = settings or {}
    local cameraAimEnabled = settings.silentAim == true or taskCombatActive == true
    return shotOnly and settings.shotAim == true
        or (cameraAimEnabled and settings.shotAim ~= true)
end

function CameraAim.shouldClearRetention(settings, taskCombatActive, inputCaptured, fighterActive, inCombat)
    settings = settings or {}
    local cameraAimEnabled = settings.silentAim == true or taskCombatActive == true
    return not cameraAimEnabled
        and settings.shotAim ~= true
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
    if not enabled
        or (ctx.inputCaptured and taskCombatActive ~= true)
        or not fighterActive
        or not inCombat
    then
        if CameraAim.shouldClearRetention(
            settings,
            taskCombatActive,
            ctx.inputCaptured,
            fighterActive,
            inCombat
        ) then
            ctx.clearRetention()
        end
        return nil
    end
    local function settleAim(rotation, instant, character, maximumSmoothness)
        if shotOnly then
            return true
        end
        return ctx.setAimRotation(
            rotation,
            instant,
            character,
            maximumSmoothness
        )
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
        target = ctx.selectTarget(
            nil,
            cameraAim or energyRifle or slingshot or splashProjectile,
            cameraAim or taskCombatActive == true
        )
        if not target and (cameraAim or taskCombatActive == true) then
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
    if not shotOnly
        and not knife
        and target.visible ~= true
        and typeof(target.position) == "Vector3"
    then
        local aligned = table.clone(target)
        aligned.aimSettled = settleAim(
            Targeting.rotationToward(origin, target.position),
            true,
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
    local taskRates
    if taskCombatActive == true then
        local observedRates = ctx.taskSkillRuntime:update(
            entity and entity.Humanoid,
            target,
            ctx.renderDelta
        )
        if taskDebug then
            taskDebug.adaptiveRates = observedRates
        end
        if observedRates.ready == true then taskRates = observedRates end
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
                solution = ctx.solveSplashAim(
                    origin,
                    target,
                    item.Info,
                    raycast,
                    ctx.gravity
                ),
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
        local aimSettled = settleAim(
            Targeting.rotationToward(origin, target.position),
            false,
            target.character
        )
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
