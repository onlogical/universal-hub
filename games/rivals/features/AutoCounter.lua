local AutoCounter = {}

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
