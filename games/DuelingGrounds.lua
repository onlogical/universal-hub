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

local Noclip = importDependency(
    "games/duelinggrounds/features/Noclip",
    "./duelinggrounds/features/Noclip"
)
local TeleportBehind = importDependency(
    "games/duelinggrounds/features/TeleportBehind",
    "./duelinggrounds/features/TeleportBehind"
)
local DuelEscape = importDependency(
    "games/duelinggrounds/features/DuelEscape",
    "./duelinggrounds/features/DuelEscape"
)
local MultiJump = importDependency(
    "games/duelinggrounds/features/MultiJump",
    "./duelinggrounds/features/MultiJump"
)
local Styles = importDependency(
    "games/duelinggrounds/features/combat/Styles",
    "./duelinggrounds/features/combat/Styles"
)
local WallEscape = importDependency(
    "games/duelinggrounds/features/combat/WallEscape",
    "./duelinggrounds/features/combat/WallEscape"
)
local Skill = importDependency(
    "games/duelinggrounds/features/combat/Skill",
    "./duelinggrounds/features/combat/Skill"
)
local TeleStyle = importDependency(
    "games/duelinggrounds/features/combat/TeleStyle",
    "./duelinggrounds/features/combat/TeleStyle"
)
local WinTitles = importDependency(
    "games/duelinggrounds/features/WinTitles",
    "./duelinggrounds/features/WinTitles"
)
local RecordingPersistence = importDependency(
    "games/duelinggrounds/recording/Persistence",
    "./duelinggrounds/recording/Persistence"
)
local RecordingRuntime = importDependency(
    "games/duelinggrounds/recording/Runtime",
    "./duelinggrounds/recording/Runtime"
)

local DuelingGrounds = {}

local AUTO_MOVE_DASH_EXTRA_REACH = 6
local AUTO_MOVE_DASH_COOLDOWN = 0.75
local DODGE_COOLDOWN = 0.35
local FIGHT_RETRY_INTERVAL = 0.05
local IMPACT_MARGIN = Vector3.new(2.5, 3, 2.5)
local OFFENSIVE_IMPACT_MARGIN = Vector3.new(1.5, 2.5, 0.75)
local OFFENSIVE_PREDICTION_MAX = 0.65
local OFFENSIVE_RECOVERY_MAX = 0.65
local OFFENSIVE_RECOVERY_MIN = 0.18
local PARRY_COOLDOWN = 0.05
local PARRY_HOLD_TIME = 0.12
local TARGET_BACKSTEP_DISTANCE = 4
local TELE_NETWORK_STANDOFF_DISTANCE = 8
local TELE_VISUAL_HOVER_HEIGHT = 50
local TELE_DEFAULT_BEHIND_DISTANCE = 5
local TELE_IMPACT_GRACE = 0.04
local ULTIMATE_RETRY_INTERVAL = 0.2
local ULTIMATE_SHIELD_BREAK_RESERVE = 4.5
local UNKNOWN_ATTACK_REACH = 12

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
        approachDistance = 9.25,
        orbitDistance = 8.25,
        retreatDistance = 7.25,
        maximumNeutralAttackDistance = 9.25,
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

local function triggersUltimateDamage(attackInfo)
    for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
        local impactInfo = impact.impactInfo
        local results = impactInfo and impactInfo.impactResults
        if results and results.GetHit and results.GetHit.triggerUltimate == true then
            return true
        end
    end
    return false
end

local function isHeavyAttackInfo(attackName, attackInfo)
    local normalizedName = string.lower(attackName or "")
    if string.find(normalizedName, "heavy", 1, true) then
        return true
    end
    local healthDamage = getImpactResultValue(attackInfo, "GetHit", "healthDamage")
    local postureDamage = getImpactResultValue(attackInfo, "Block", "postureDamage")
    return healthDamage >= 50 or postureDamage >= 30
end

local function getAttackInfo(characterHandler, track)
    local weaponHandler = characterHandler and characterHandler:GetEquippedWeaponHandler()
    local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
    local animation = track and track.Animation
    if not attackTypes or not animation then
        return nil
    end
    for attackName, attackInfo in pairs(attackTypes) do
        if sameAnimation(attackInfo.animation, animation) then
            return attackInfo, attackName
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
    local velocity = defenderRoot.AssemblyLinearVelocity or Vector3.zero
    local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontalVelocity.Magnitude > 18 then
        horizontalVelocity = horizontalVelocity.Unit * 18
    end
    for _, impact in ipairs(attackInfo.impacts or {}) do
        local impactTime = type(impact.markerTime) == "number" and impact.markerTime or 0
        local predictedPoint = defenderRoot.Position
            + horizontalVelocity * math.clamp(
                impactTime,
                0,
                OFFENSIVE_PREDICTION_MAX
            )
        if impactContainsPoint(
            attackerRoot,
            predictedPoint,
            impact,
            OFFENSIVE_IMPACT_MARGIN
        ) then
            return true
        end
        -- Target lock turns the attack toward its target when the action starts.
        -- Requiring the character's pre-attack facing to already overlap the
        -- hitbox suppresses every neutral attack while auto movement is orbiting.
        local impactInfo = impact.impactInfo
        local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
        local hitboxSize = impactInfo and impactInfo.hitboxSize
        if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
            local predictedOffset = predictedPoint - attackerRoot.Position
            local predictedDistance = Vector3.new(
                predictedOffset.X,
                0,
                predictedOffset.Z
            ).Magnitude
            local maximumReach = math.abs(hitboxCFrame.Position.Z)
                + hitboxSize.Z / 2
                + OFFENSIVE_IMPACT_MARGIN.Z
            if predictedDistance <= maximumReach then
                return true
            end
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

function DuelingGrounds.new(context)
    assert(type(context) == "table", "DuelingGrounds adapter requires context")
    assert(context.oh and context.oh.targeting, "DuelingGrounds requires Hydroxide Targeting")
    assert(context.players and context.players.LocalPlayer, "DuelingGrounds requires Players")
    assert(type(context.render) == "function", "DuelingGrounds requires a renderer")
    assert(context.store, "DuelingGrounds requires a reactive store")

    local localPlayer = context.players.LocalPlayer
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local GameManager = require(replicatedStorage.GameManager)
    local characterController = GameManager:GetController("CharacterController")
    local matchController = GameManager:GetController("MatchController")
    local pingController = GameManager:GetController("PingController")
    local playerInputController = GameManager:GetController("PlayerInputController")
    local targetLockController = GameManager:GetController("TargetLockController")
    local stopped = false
    local lastDodgeAt = -math.huge
    local lastApproachDashAt = -math.huge
    local lastJumpAttackAt = -math.huge
    local lastCriticalStrikeAt = -math.huge
    local lastUltimateAttemptAt = -math.huge
    local nextFightAt = 0
    local lastFightAttackAt = -math.huge
    local nextNeutralAttackAt = -math.huge
    local pendingDodgeCounterAt = nil
    local pendingDodgeCounterUntil = nil
    local pendingJumpAttackUntil = nil
    local defenseIntent = nil
    local lastParryAt = -math.huge
    local activeParryBlock = nil
    local boundTarget = nil
    local observedEnemies = {}
    local noclip = Noclip.new()
    local winTitles = WinTitles.new()
    local duelEscape = DuelEscape.new({
        clearTarget = function()
            targetLockController.Target = nil
        end,
        getRoot = function()
            local handler = characterController:GetLocalCharacterHandler()
            return handler and handler.Root
        end,
        inputService = game:GetService("UserInputService"),
        isDuelActive = function()
            return matchController.ActiveLocalPlayerMatch ~= nil
        end,
        localPlayer = localPlayer,
        stopMovement = function()
            playerInputController.CurrentInput.MoveDirection = Vector3.zero
        end,
        store = context.store,
        workspace = context.workspace or workspace,
    })
    local multiJump = MultiJump.new({
        getHumanoid = function()
            local handler = characterController:GetLocalCharacterHandler()
            return handler and handler.Humanoid
        end,
        inputService = game:GetService("UserInputService"),
        store = context.store,
    })
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
    local nextOrbitSwitchAt = 0
    local wallEscapeDirection = nil
    local wallEscapeUntil = -math.huge
    local offenseRandom = Random.new()
    local skillRandom = Random.new()
    local ultimateReadyAt = nil
    local dynamicState = {
        mode = "offensive",
        deflectTimes = {},
        defensiveUntil = -math.huge,
        probeUntil = nil,
    }
    local teleState = {
        phase = "idle",
        targetRoot = nil,
        awayDirection = nil,
        armUntil = nil,
        pendingAt = nil,
        track = nil,
        attackInfo = nil,
        attackName = nil,
        serverCFrame = nil,
    }
    local teleNetworkHook = nil
    local updateCharacterCFrameRemote = nil
    pcall(function()
        updateCharacterCFrameRemote = game:GetService("ReplicatedStorage")
            :WaitForChild("Remotes")
            :WaitForChild("PlayerCharacter")
            :WaitForChild("Request")
            :WaitForChild("UpdateCharacterCFrame")
    end)
    if updateCharacterCFrameRemote
        and type(hookmetamethod) == "function"
        and type(newcclosure) == "function"
        and type(getnamecallmethod) == "function"
    then
        teleNetworkHook = { enabled = true }
        local previousNamecall
        previousNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if teleNetworkHook.enabled
                and not stopped
                and self == updateCharacterCFrameRemote
                and getnamecallmethod() == "FireServer"
                and teleState.serverCFrame
            then
                local arguments = table.pack(...)
                arguments[1] = teleState.serverCFrame
                return previousNamecall(self, table.unpack(arguments, 1, arguments.n))
            end
            return previousNamecall(self, ...)
        end))
    end
    local boundLocalCombatHandler = nil
    local boundLocalCombatWeapon = nil
    local localCombatConnection = nil
    local localDeflectAnimations = {}
    local lastTelemetryPublishAt = -math.huge
    local lastCombatStyle = nil
    local environment = type(getgenv) == "function" and getgenv() or _G
    local recording = RecordingRuntime.new({
        environment = environment,
        persistence = RecordingPersistence.new({
            writefile = type(writefile) == "function" and writefile or nil,
            makefolder = type(makefolder) == "function" and makefolder or nil,
            isfolder = type(isfolder) == "function" and isfolder or nil,
            jsonEncode = function(value)
                return game:GetService("HttpService"):JSONEncode(value)
            end,
        }),
    })
    local function appendCurrentMatchEvent(kind, data)
        recording:recordEvent(kind, data)
    end

    local function logCombatDecision(kind, data)
        recording:recordDecision(kind, data)
    end

    local function updateMatchRecording(settings, punishWindow)
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        local localHandler = characterController:GetLocalCharacterHandler()
        local targetHandler = targetModel
            and characterController:GetCharacterHandler(targetModel)
            or nil
        local localWeapon = getWeaponInfo(localHandler)
        local targetWeapon = getWeaponInfo(targetHandler)
        local targetPlayer = targetModel and context.players:GetPlayerFromCharacter(targetModel)
        recording:update({
            target = target,
            targetModel = targetModel,
            targetHandler = targetHandler,
            localHandler = localHandler,
            dynamicMode = settings.combatStyle == "dynamic" and dynamicState.mode or nil,
            defense = defenseIntent and defenseIntent.kind or nil,
            critical = targetLockController.CriticalStrikeTarget ~= nil,
            punishWindow = punishWindow or 0,
            metadata = {
                gameId = game.GameId,
                placeId = game.PlaceId,
                jobId = game.JobId,
                localPlayer = localPlayer.Name,
                localUserId = localPlayer.UserId,
                target = targetPlayer and targetPlayer.Name or targetModel and targetModel.Name,
                targetUserId = targetPlayer and targetPlayer.UserId or nil,
                selfWeapon = localWeapon and localWeapon.WeaponName or nil,
                targetWeapon = targetWeapon and targetWeapon.WeaponName or nil,
            },
        }, settings)
    end

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

    local function resetDynamicState()
        dynamicState.mode = "offensive"
        table.clear(dynamicState.deflectTimes)
        dynamicState.defensiveUntil = -math.huge
        dynamicState.probeUntil = nil
    end

    local function resetTeleState()
        teleState.phase = "idle"
        teleState.targetRoot = nil
        teleState.awayDirection = nil
        teleState.armUntil = nil
        teleState.pendingAt = nil
        teleState.track = nil
        teleState.attackInfo = nil
        teleState.attackName = nil
        teleState.serverCFrame = nil
    end

    local function recordDynamicDeflect()
        local settings = context.store:Get().settings or {}
        if settings.combatStyle ~= "dynamic"
            or os.clock() - lastFightAttackAt > 1.2
        then
            return
        end
        local now = os.clock()
        table.insert(dynamicState.deflectTimes, now)
        while dynamicState.deflectTimes[1]
            and now - dynamicState.deflectTimes[1] > 8
        do
            table.remove(dynamicState.deflectTimes, 1)
        end
        if #dynamicState.deflectTimes >= 3 or dynamicState.mode == "probing" then
            dynamicState.mode = "defensive"
            dynamicState.probeUntil = nil
            dynamicState.defensiveUntil = now
                + math.min(2.5 + #dynamicState.deflectTimes * 0.5, 5)
        end
    end

    local function disconnectLocalCombatObservation()
        if localCombatConnection then
            localCombatConnection:Disconnect()
            localCombatConnection = nil
        end
        boundLocalCombatHandler = nil
        boundLocalCombatWeapon = nil
        table.clear(localDeflectAnimations)
    end

    local function updateLocalCombatObservation()
        local handler = characterController:GetLocalCharacterHandler()
        local weaponHandler = handler and handler:GetEquippedWeaponHandler()
        if handler == boundLocalCombatHandler
            and weaponHandler == boundLocalCombatWeapon
        then
            return
        end
        disconnectLocalCombatObservation()
        boundLocalCombatHandler = handler
        boundLocalCombatWeapon = weaponHandler
        local animator = handler and handler.Animator
        local weaponInfo = weaponHandler and weaponHandler.WeaponInfo
        if not animator or not weaponInfo then
            return
        end
        for _, attackInfo in pairs(weaponInfo.BasicAttackTypes or {}) do
            collectAnimations(attackInfo.deflectStun, localDeflectAnimations, {})
        end
        localCombatConnection = animator.AnimationPlayed:Connect(function(track)
            local animation = track.Animation
            local animationId = animation and animation.AnimationId or ""
            local animationName = string.lower(animation and animation.Name or "")
            local attackInfo, attackName = getAttackInfo(handler, track)
            local settings = context.store:Get().settings or {}
            if settings.combatStyle == "tele"
                and teleState.phase == "pending"
                and attackInfo
            then
                teleState.phase = "waitingImpact"
                teleState.track = track
                teleState.attackInfo = attackInfo
            end
            appendCurrentMatchEvent("animation", {
                side = "self",
                id = animationId,
                name = attackName or animation and animation.Name or "",
                attack = attackName,
            })
            if localDeflectAnimations[animationId]
                or string.find(animationName, "deflected", 1, true)
            then
                recordDynamicDeflect()
            end
        end)
    end

    local function rebuildTargetAnimationSets(handler)
        local animationSets = {
            block = {},
            parry = {},
            stagger = {},
        }
        local weaponInfo = getWeaponInfo(handler)
        if not weaponInfo then
            return animationSets
        end
        addAnimation(animationSets.block, weaponInfo.BlockAnimation)
        local animations = weaponInfo.Animations
        addAnimation(animationSets.block, animations and animations.Block)
        local staggerTypes = weaponInfo.StaggerTypes or {}
        collectAnimations(staggerTypes.Parry, animationSets.parry, {})
        collectAnimations(staggerTypes.PostureBreak, animationSets.stagger, {})
        collectAnimations(staggerTypes.PostureParry, animationSets.stagger, {})
        for _, attackInfo in pairs(weaponInfo.BasicAttackTypes or {}) do
            collectAnimations(attackInfo.deflectStun, animationSets.stagger, {})
        end
        return animationSets
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

    local function executeDodge(intent)
        if os.clock() - lastDodgeAt < DODGE_COOLDOWN then
            return false, "dodge cooldown"
        end
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager then
            return false, "action manager unavailable"
        end
        if not actionManager:CanStartDodge() then
            local currentAction = actionManager.CurrentAction
            return false, currentAction and "current action locked" or "dodge unavailable"
        end
        local target = targetLockController.Target
        local localRoot = localHandler.Root
        local offset = target and localRoot and (target.Position - localRoot.Position) or Vector3.zero
        local direction = Vector3.new(offset.X, 0, offset.Z)
        local settings = context.store:Get().settings or {}
        local localModel = localHandler and (localHandler.OriginalModel or localHandler.Model)
        local stylePreferences = Styles.preferences(settings.combatStyle, {
            health = localModel and localModel:GetAttribute("Health"),
            maximumHealth = localModel and localModel:GetAttribute("MaxHealth"),
            posture = localModel and localModel:GetAttribute("Posture"),
            maximumPosture = localModel and localModel:GetAttribute("MaxPosture"),
            defenseReady = actionManager
                and (actionManager._dodgeStamina or 0) >= 0.99
                and (actionManager._blockStrength or 0) > 0.01,
        }, dynamicState)
        local counterAllowed = stylePreferences.counterAllowed
        local dodgeMode = intent.mode
        if direction.Magnitude <= 0.001 then
            local camera = context.workspace.CurrentCamera
            local look = camera and camera.CFrame.LookVector or Vector3.zAxis
            direction = Vector3.new(look.X, 0, look.Z)
        end
        direction = direction.Magnitude > 0 and direction.Unit or Vector3.zAxis
        local isReverse = true
        if dodgeMode == "heavy" and target and localRoot then
            local toward = direction
            local lateral = Vector3.new(-toward.Z, 0, toward.X) * dodgeCounterDirection
            local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
            direction = distance > 9 and (lateral * 0.8 + toward * 0.6).Unit or lateral
            dodgeCounterDirection = -dodgeCounterDirection
            isReverse = false
        elseif counterAllowed and target and localRoot then
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
        lastDodgeAt = os.clock()
        if counterAllowed then
            pendingDodgeCounterAt = dodgeMode == "heavy" and lastDodgeAt
                or lastDodgeAt + 0.16
            pendingDodgeCounterUntil = lastDodgeAt + 0.32
        else
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
        end
        return true
    end

    local function tryDodgeCounter(localHandler, actionManager, targetHandler, targetRoot)
        if not pendingDodgeCounterUntil then
            return false
        end
        local now = os.clock()
        if now > pendingDodgeCounterUntil then
            appendCurrentMatchEvent("dodgeCounter", { result = "expired" })
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
            appendCurrentMatchEvent("dodgeCounter", { result = "targetInvulnerable" })
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
                        appendCurrentMatchEvent("dodgeCounter", {
                            result = "multiHitPending",
                            timeUntilImpact = timeUntilImpact,
                        })
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
            appendCurrentMatchEvent("dodgeCounter", {
                result = distance > reach and "outOfRange" or "pathBlocked",
                distance = distance,
                reach = reach,
            })
            return true
        end
        if actionManager:TryQueueBasicAttack("Light") then
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
            lastFightAttackAt = now
            local canCancel = getAttackMarker(attackInfo, "canCancel") or 0.5
            nextNeutralAttackAt = now + canCancel
                + offenseRandom:NextNumber(OFFENSIVE_RECOVERY_MIN, OFFENSIVE_RECOVERY_MAX)
            appendCurrentMatchEvent("dodgeCounter", {
                result = "queued",
                attack = attackName,
                distance = distance,
            })
        else
            appendCurrentMatchEvent("dodgeCounter", {
                result = "queueRejected",
                attack = attackName,
                distance = distance,
            })
        end
        return true
    end

    local function executeParry()
        local localHandler = characterController:GetLocalCharacterHandler()
        local actionManager = localHandler and localHandler.ActionManager
        if not actionManager then
            return false, "action manager unavailable"
        end
        if actionManager.BlockAction then
            return false, "block action active"
        end
        if os.clock() - lastParryAt < PARRY_COOLDOWN then
            return false, "parry cooldown"
        end
        if (actionManager._blockStrength or 0) <= 0.01 then
            return false, "block strength depleted"
        end
        local canStart, replaceCurrent = actionManager:CanStartBlock()
        if not canStart then
            local currentAction = actionManager.CurrentAction
            return false, currentAction and "current action locked" or "parry unavailable"
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
        lastParryAt = os.clock()
        task.delay(PARRY_HOLD_TIME, function()
            if activeParryBlock == block then
                block._wantsToRelease = true
                activeParryBlock = nil
            end
        end)
        return true
    end

    local function executeDefenseIntent()
        local intent = defenseIntent
        if not intent then
            return
        end
        local now = os.clock()
        if now > intent.expiresAt then
            logCombatDecision("defenseExpired", {
                attack = intent.attackName,
                impactIndex = intent.impactIndex,
                impactCount = intent.impactCount,
                winner = intent.kind,
                reason = intent.lastFailure,
            })
            defenseIntent = nil
            return
        end
        local succeeded, reason
        if intent.kind == "dodge" then
            succeeded, reason = executeDodge(intent)
        else
            succeeded, reason = executeParry()
        end
        if not succeeded then
            intent.lastFailure = reason
            if now >= intent.impactAt - 0.04 then
                local fallbackKind = intent.kind == "dodge" and "parry" or "dodge"
                local fallbackSucceeded, fallbackReason
                local localHandler = characterController:GetLocalCharacterHandler()
                if localHandler and localHandler.IsDodging then
                    fallbackReason = "dodge action active"
                elseif fallbackKind == "parry" and intent.parryable then
                    fallbackSucceeded, fallbackReason = executeParry()
                elseif fallbackKind == "dodge" then
                    fallbackSucceeded, fallbackReason = executeDodge({ mode = intent.mode })
                end
                if fallbackSucceeded then
                    logCombatDecision("defenseFallback", {
                        attack = intent.attackName,
                        impactIndex = intent.impactIndex,
                        impactCount = intent.impactCount,
                        winner = fallbackKind,
                        replaced = intent.kind,
                        reason = reason,
                    })
                    defenseIntent = nil
                elseif fallbackReason then
                    intent.lastFailure = reason .. "; fallback: " .. fallbackReason
                end
            end
            return
        end
        logCombatDecision("defenseExecuted", {
            attack = intent.attackName,
            impactIndex = intent.impactIndex,
            impactCount = intent.impactCount,
            winner = intent.kind,
            reason = intent.reason,
            mode = intent.mode,
            timeUntilImpact = intent.impactAt - now,
        })
        defenseIntent = nil
    end

    local function queueDefenseIntent(intent)
        if defenseIntent
            and defenseIntent.impactAt <= intent.impactAt
        then
            return false
        end
        defenseIntent = intent
        logCombatDecision("defenseSelected", {
            attack = intent.attackName,
            impactIndex = intent.impactIndex,
            impactCount = intent.impactCount,
            winner = intent.kind,
            reason = intent.reason,
            mode = intent.mode,
            canDodge = intent.canDodge,
            canParry = intent.canParry,
            dodgeStamina = intent.dodgeStamina,
            currentAction = intent.currentAction,
            currentCanCancel = intent.currentCanCancel,
            timeUntilImpact = intent.impactAt - os.clock(),
        })
        executeDefenseIntent()
        return true
    end

    local updateIncomingThreats

    local function observeThreatTrack(handler, track)
        if activeThreats[track] or track.Looped then
            return
        end
        local attackInfo, attackName = getAttackInfo(handler, track)
        if not attackInfo then
            return
        end
        activeThreats[track] = {
            attackInfo = attackInfo,
            attackName = attackName,
            isHeavy = isHeavyAttackInfo(attackName, attackInfo),
            handler = handler,
            reacted = {},
            startedAt = os.clock(),
        }
        if attackName == "JumpAttack" and updateIncomingThreats then
            updateIncomingThreats()
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

    local function observeTargetTrack(handler, track, animationSets, observeCombatState)
        local animation = track.Animation
        local attackInfo, attackName = getAttackInfo(handler, track)
        appendCurrentMatchEvent("animation", {
            side = "target",
            id = animation and animation.AnimationId or "",
            name = attackName or animation and animation.Name or "",
            attack = attackName,
        })
        if attackInfo then
            observeThreatTrack(handler, track)
            return
        end
        if not observeCombatState then
            return
        end
        local animationId = animation and animation.AnimationId or ""
        local animationName = string.lower(animation and animation.Name or "")
        local now = os.clock()
        if animationSets.block[animationId] or animationName == "block" then
            targetCombatState.blockTracks[track] = now
        elseif animationSets.parry[animationId] then
            targetCombatState.parryUntil = math.max(
                targetCombatState.parryUntil,
                now + getTrackRemaining(track, 0.45)
            )
        elseif string.find(animationName, "dodge", 1, true) then
            targetCombatState.dodgeUntil = math.max(
                targetCombatState.dodgeUntil,
                now + getTrackRemaining(track, 0.65)
            )
        elseif animationSets.stagger[animationId]
            or string.find(animationName, "posturebreak", 1, true)
        then
            targetCombatState.staggerUntil = math.max(
                targetCombatState.staggerUntil,
                now + getTrackRemaining(track, 0.5)
            )
        end
    end

    local function disconnectEnemyAnimations()
        for _, observation in pairs(observedEnemies) do
            observation.connection:Disconnect()
        end
        table.clear(observedEnemies)
        boundTarget = nil
        table.clear(activeThreats)
        table.clear(targetCombatState.blockTracks)
        targetCombatState.dodgeUntil = -math.huge
        targetCombatState.parryUntil = -math.huge
        targetCombatState.staggerUntil = -math.huge
    end

    local function refreshEnemyAnimations()
        local localCharacter = localPlayer.Character
        local localTeamGroup = localCharacter and localCharacter:GetAttribute("TeamGroup")
        local lockedTarget = targetLockController.Target
        local lockedModel = lockedTarget and lockedTarget:FindFirstAncestorWhichIsA("Model")
        local currentModels = {}
        for _, player in ipairs(context.players:GetPlayers()) do
            local model = player.Character
            local teamGroup = model and model:GetAttribute("TeamGroup")
            if player ~= localPlayer
                and model
                and model:GetAttribute("IsDead") ~= true
                and (model == lockedModel
                    or (localTeamGroup ~= nil
                        and teamGroup ~= nil
                        and teamGroup ~= localTeamGroup))
            then
                currentModels[model] = true
                if not observedEnemies[model] then
                    local handler = characterController:GetCharacterHandler(model)
                    local animator = handler and handler.Animator
                    if animator then
                        local animationSets = rebuildTargetAnimationSets(handler)
                        local function observe(track)
                            local target = targetLockController.Target
                            local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
                            observeTargetTrack(handler, track, animationSets, targetModel == model)
                        end
                        observedEnemies[model] = {
                            connection = animator.AnimationPlayed:Connect(observe),
                            handler = handler,
                        }
                        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                            observe(track)
                        end
                    end
                end
            end
        end
        for model, observation in pairs(observedEnemies) do
            if not currentModels[model] then
                observation.connection:Disconnect()
                observedEnemies[model] = nil
                for track, threat in pairs(activeThreats) do
                    if threat.handler == observation.handler then
                        activeThreats[track] = nil
                    end
                end
            end
        end
    end

    updateIncomingThreats = function()
        local localHandler = characterController:GetLocalCharacterHandler()
        local localRoot = localHandler and localHandler.Root
        if not localRoot then
            return
        end
        local settings = context.store:Get().settings or {}
        local skill = Skill.profile(settings.botSkill)
        local leadTime = math.clamp(
            (pingController:GetPing() or 0)
                + 0.04
                - Skill.reactionDelay(skill, skillRandom),
            0.01,
            0.16
        )
        for track, threat in pairs(activeThreats) do
            if not track.IsPlaying then
                activeThreats[track] = nil
                continue
            end
            local targetHandler = threat.handler
            local targetRoot = targetHandler and targetHandler.Root
            local targetModel = targetHandler and targetHandler.OriginalModel
            local speed = math.max(math.abs(track.Speed), 0.05)
            local isHeavyAttack = threat.isHeavy == true
            local impactCount = #(threat.attackInfo.impacts or {})
            local reactionLead = isHeavyAttack and math.max(leadTime, 0.2) or leadTime
            for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                if threat.reacted[index] then
                    continue
                end
                local timeUntilImpact = (impact.markerTime - track.TimePosition) / speed
                if timeUntilImpact < -0.08 then
                    threat.reacted[index] = true
                elseif timeUntilImpact <= reactionLead
                    and attackCanReach(targetRoot, localRoot, { impacts = { impact } }, false)
                    and hasClearPath(
                        targetRoot,
                        { targetHandler.Model, targetModel },
                        localRoot,
                        { localHandler.Model, localHandler.OriginalModel }
                    )
                then
                    if not Skill.shouldAct(skill, skillRandom) then
                        threat.reacted[index] = true
                        logCombatDecision("defenseMissed", {
                            attack = threat.attackName,
                            impactIndex = index,
                            impactCount = impactCount,
                            skill = skill.level,
                        })
                        continue
                    end
                    local impactResults = impact.impactInfo and impact.impactInfo.impactResults
                    local actionManager = localHandler.ActionManager
                    local currentAction = actionManager and actionManager.CurrentAction
                    local dodgeStamina = actionManager and actionManager._dodgeStamina or 0
                    local dodgeReady = actionManager ~= nil
                        and dodgeStamina >= 0.99
                        and os.clock() - lastDodgeAt >= DODGE_COOLDOWN
                    local canDodge = dodgeReady and actionManager:CanStartDodge()
                    local canStartBlock = false
                    if actionManager
                        and not actionManager.BlockAction
                        and (actionManager._blockStrength or 0) > 0.01
                        and os.clock() - lastParryAt >= PARRY_COOLDOWN
                    then
                        canStartBlock = actionManager:CanStartBlock()
                    end
                    local parryable = impactResults ~= nil
                        and impactResults.Parry ~= nil
                    local winner
                    local reason
                    if isHeavyAttack and impactCount > 1 and canStartBlock and parryable then
                        winner = "parry"
                        reason = "interrupt multi-hit heavy"
                    elseif isHeavyAttack and dodgeReady then
                        winner = "dodge"
                        reason = "heavy counter"
                    elseif not parryable then
                        winner = "dodge"
                        reason = "unparryable impact"
                    elseif canStartBlock then
                        winner = "parry"
                        reason = isHeavyAttack and "dodge unavailable" or "parryable impact"
                    elseif dodgeReady then
                        winner = "dodge"
                        reason = "parry unavailable"
                    else
                        winner = "parry"
                        reason = "no ready defense; parry fallback"
                    end
                    local now = os.clock()
                    local selected = queueDefenseIntent({
                        kind = winner,
                        mode = isHeavyAttack and "heavy" or nil,
                        attackName = threat.attackName,
                        impactIndex = index,
                        impactCount = impactCount,
                        reason = reason,
                        canDodge = canDodge,
                        canParry = canStartBlock,
                        dodgeStamina = dodgeStamina,
                        parryable = parryable,
                        currentAction = currentAction and currentAction.ActionType or nil,
                        currentCanCancel = currentAction and currentAction.CanCancel or nil,
                        impactAt = now + timeUntilImpact,
                        expiresAt = now + timeUntilImpact + 0.08,
                    })
                    if selected then
                        threat.reacted[index] = true
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
        if settings.combatStyle ~= lastCombatStyle then
            resetDynamicState()
            resetTeleState()
            lastCombatStyle = settings.combatStyle
        end
        if settings.autoFight ~= true then
            defenseIntent = nil
            pendingDodgeCounterAt = nil
            pendingDodgeCounterUntil = nil
            pendingJumpAttackUntil = nil
            disconnectEnemyAnimations()
            resetTeleState()
            return
        end
        executeDefenseIntent()
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        if targetModel ~= boundTarget then
            boundTarget = targetModel
            table.clear(targetCombatState.blockTracks)
            targetCombatState.dodgeUntil = -math.huge
            targetCombatState.parryUntil = -math.huge
            targetCombatState.staggerUntil = -math.huge
        end
        refreshEnemyAnimations()
        updateIncomingThreats()
    end

    local function teleCharacter(localHandler, destination)
        local root = localHandler and localHandler.Root
        local model = root and root:FindFirstAncestorWhichIsA("Model")
        if not root or not model or not destination then
            return false
        end
        if playerInputController.CurrentInput then
            playerInputController.CurrentInput.MoveDirection = Vector3.zero
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        model:PivotTo(destination)
        return true
    end

    local function teleAway(localHandler, targetRoot)
        local localRoot = localHandler and localHandler.Root
        if not localRoot or not targetRoot then
            return false
        end
        local look = targetRoot.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude <= 0.001 then
            flatLook = Vector3.new(0, 0, -1)
        end
        local visualDestination = targetRoot.Position
            + Vector3.new(0, TELE_VISUAL_HOVER_HEIGHT, 0)
        local networkDestination = targetRoot.Position
            + flatLook.Unit * TELE_NETWORK_STANDOFF_DISTANCE
        networkDestination = Vector3.new(
            networkDestination.X,
            targetRoot.Position.Y,
            networkDestination.Z
        )
        local visualCFrame = CFrame.lookAt(
            visualDestination,
            visualDestination + flatLook.Unit
        )
        teleState.serverCFrame = CFrame.lookAt(
            networkDestination,
            Vector3.new(targetRoot.Position.X, networkDestination.Y, targetRoot.Position.Z)
        )
        return teleCharacter(localHandler, visualCFrame)
    end

    local function getTeleBehindDistance(attackInfo)
        local selectedImpact
        local selectedTime = math.huge
        for _, impact in ipairs(attackInfo and attackInfo.impacts or {}) do
            local markerTime = type(impact.markerTime) == "number"
                and impact.markerTime
                or math.huge
            if markerTime < selectedTime then
                selectedTime = markerTime
                selectedImpact = impact
            end
        end
        local impactInfo = selectedImpact and selectedImpact.impactInfo
        local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
        if typeof(hitboxCFrame) == "CFrame" then
            return math.clamp(math.abs(hitboxCFrame.Position.Z), 2, 8)
        end
        return TELE_DEFAULT_BEHIND_DISTANCE
    end

    local function getTeleBehindCFrame(targetRoot, attackInfo)
        if not targetRoot then
            return nil
        end
        local look = targetRoot.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude <= 0.001 then
            return nil
        end
        local distance = getTeleBehindDistance(attackInfo)
        local destination = targetRoot.Position - flatLook.Unit * distance
        destination = Vector3.new(destination.X, targetRoot.Position.Y, destination.Z)
        return CFrame.lookAt(
            destination,
            Vector3.new(targetRoot.Position.X, destination.Y, targetRoot.Position.Z)
        )
    end

    local function teleBehind(localHandler, targetRoot, attackInfo)
        local destination = getTeleBehindCFrame(targetRoot, attackInfo)
        teleState.serverCFrame = destination
        return teleCharacter(localHandler, destination)
    end

    local function updateTeleAttack(localHandler, actionManager, targetRoot)
        local now = os.clock()
        if teleState.targetRoot ~= targetRoot then
            resetTeleState()
            teleState.targetRoot = targetRoot
        end
        if teleState.phase == "arming" then
            teleAway(localHandler, targetRoot)
            if now < (teleState.armUntil or now) then
                return
            end
            if actionManager.CurrentAction or actionManager._queuedActionType then
                teleAway(localHandler, targetRoot)
                resetTeleState()
                teleState.targetRoot = targetRoot
                return
            end
            teleState.phase = "pending"
            teleState.pendingAt = now
            local queued = actionManager:TryQueueBasicAttack("Light")
            if not queued then
                teleAway(localHandler, targetRoot)
                resetTeleState()
                teleState.targetRoot = targetRoot
                return
            end
            lastFightAttackAt = now
            local canCancel = getAttackMarker(teleState.attackInfo, "canCancel")
                or getLastImpactTime(teleState.attackInfo)
                or 0.5
            nextNeutralAttackAt = now + canCancel + OFFENSIVE_RECOVERY_MIN
            appendCurrentMatchEvent("teleAttack", {
                result = "queued",
                attack = teleState.attackName,
            })
            return
        end

        if teleState.phase == "pending" then
            teleAway(localHandler, targetRoot)
            if now - (teleState.pendingAt or now) > 0.75 then
                resetTeleState()
                teleState.targetRoot = targetRoot
            end
            return
        end

        local track = teleState.track
        local attackInfo = teleState.attackInfo
        if teleState.phase == "waitingImpact" then
            if not track or not track.IsPlaying then
                teleAway(localHandler, targetRoot)
                resetTeleState()
                teleState.targetRoot = targetRoot
                return
            end
            local firstImpact = getFirstImpactTime(attackInfo) or 0.25
            local leadTime = math.clamp(
                (pingController:GetPing() or 0) * 2 + 0.1,
                0.25,
                0.35
            )
            if TeleStyle.shouldWarpIn(track.TimePosition, track.Speed, firstImpact, leadTime) then
                teleState.phase = "impact"
                teleBehind(localHandler, targetRoot, attackInfo)
            else
                teleAway(localHandler, targetRoot)
            end
            return
        end

        if teleState.phase == "impact" then
            local lastImpact = getLastImpactTime(attackInfo)
                or getFirstImpactTime(attackInfo)
                or 0.25
            if not track
                or not track.IsPlaying
                or TeleStyle.shouldWarpAway(
                    track.TimePosition,
                    track.Speed,
                    lastImpact,
                    TELE_IMPACT_GRACE
                )
            then
                teleAway(localHandler, targetRoot)
                teleState.phase = "recovering"
            else
                teleBehind(localHandler, targetRoot, attackInfo)
            end
            return
        end

        if teleState.phase == "recovering" then
            teleAway(localHandler, targetRoot)
            if not actionManager.CurrentAction
                and not actionManager._queuedActionType
                and now >= nextNeutralAttackAt
            then
                resetTeleState()
                teleState.targetRoot = targetRoot
            end
            return
        end

        if defenseIntent
            or localHandler.IsParrying
            or actionManager.BlockAction
            or hasIncomingThreat(true)
            or actionManager.CurrentAction
            or actionManager._queuedActionType
            or now < nextNeutralAttackAt
        then
            teleAway(localHandler, targetRoot)
            return
        end

        local weaponHandler = localHandler:GetEquippedWeaponHandler()
        local attackTypes = weaponHandler and weaponHandler.WeaponInfo.BasicAttackTypes
        local resolvedName = actionManager:_resolveAttackName("Light")
        local attackInfoForTiming = resolvedName and attackTypes and attackTypes[resolvedName]
        if not attackInfoForTiming then
            return
        end

        teleState.phase = "arming"
        teleState.attackInfo = attackInfoForTiming
        teleState.attackName = resolvedName
        teleState.armUntil = now + math.clamp(
            (pingController:GetPing() or 0) * 2 + 0.05,
            0.18,
            0.3
        )
        teleAway(localHandler, targetRoot)
    end

    local function updateAutoFight(settings)
        if settings.autoFight ~= true then
            return
        end
        if settings.combatStyle ~= "tele" then
            if os.clock() < nextFightAt then
                return
            end
            nextFightAt = os.clock() + FIGHT_RETRY_INTERVAL
        end
        local target = targetLockController.Target
        if settings.combatStyle == "tele" and not target then
            target = teleState.targetRoot
        end
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
        if settings.combatStyle == "tele" then
            updateTeleAttack(localHandler, actionManager, targetRoot)
            return
        end
        if settings.combatStyle == "baby" then
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
        local now = os.clock()
        local ultimateAvailable = localHandler:CanPerformUltimate()
        if ultimateAvailable then
            ultimateReadyAt = ultimateReadyAt or now
        else
            ultimateReadyAt = nil
        end
        local criticalTarget = targetLockController.CriticalStrikeTarget
        local criticalModel = criticalTarget and criticalTarget.Parent
        if criticalModel
            and os.clock() - lastCriticalStrikeAt >= 0.25
        then
            local criticalHandler = characterController:GetCharacterHandler(criticalModel)
            local criticalRoot = criticalHandler and criticalHandler.Root
                or criticalModel.PrimaryPart
            local localRoot = localHandler.Root
            local weaponHandler = localHandler:GetEquippedWeaponHandler()
            local weaponInfo = weaponHandler and weaponHandler.WeaponInfo
            local attackTypes = weaponInfo and weaponInfo.BasicAttackTypes
            local ultimateInfo = attackTypes and attackTypes.Ultimate
            local ultimateOpening = ultimateInfo ~= nil
                and triggersUltimateDamage(ultimateInfo)
                and ultimateAvailable
                and offensiveAttackCanReach(localRoot, criticalRoot, ultimateInfo)
                and hasClearPath(
                    localRoot,
                    { localHandler.Model, localHandler.OriginalModel },
                    criticalRoot,
                    { criticalHandler and criticalHandler.Model, criticalModel }
                )
            if ultimateOpening then
                if actionManager._queuedActionType == "BasicAttack" then
                    actionManager:_clearQueuedAction()
                end
                local currentAction = actionManager.CurrentAction
                if currentAction
                    and currentAction.ActionType == "BasicAttack"
                    and currentAction.CanCancel
                then
                    actionManager:SwitchToAction(nil)
                end
                if actionManager.CurrentAction or actionManager._queuedActionType then
                    return
                end
                local queued = actionManager:TryQueueBasicAttack("Ultimate")
                lastUltimateAttemptAt = os.clock()
                appendCurrentMatchEvent("criticalDecision", {
                    choice = queued and "shieldBreakUltimate" or "criticalFallback",
                    ultimateResult = queued and "queueAccepted" or "rejected",
                })
                if queued then
                    ultimateReadyAt = nil
                    lastFightAttackAt = lastUltimateAttemptAt
                    local canCancel = getAttackMarker(ultimateInfo, "canCancel")
                        or getFirstImpactTime(ultimateInfo)
                        or 0.5
                    nextNeutralAttackAt = lastFightAttackAt
                        + canCancel
                        + OFFENSIVE_RECOVERY_MIN
                    return
                end
            end
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
        if settings.combatStyle == "dynamic" then
            local now = os.clock()
            if dynamicState.mode == "probing" and dynamicState.probeUntil then
                if now < dynamicState.probeUntil then
                    return
                end
                resetDynamicState()
            elseif dynamicState.mode == "defensive" then
                local viablePunish = targetIsStaggered()
                    or getTargetPunishWindow() >= 0.35
                if now < dynamicState.defensiveUntil and not viablePunish then
                    pendingJumpAttackUntil = nil
                    if actionManager._queuedActionType == "BasicAttack"
                        or actionManager._queuedActionType == "Jump"
                    then
                        actionManager:_clearQueuedAction()
                    end
                    return
                end
                dynamicState.mode = "probing"
                dynamicState.probeUntil = nil
            end
        end
        local targetAvoidingAttack = targetIsDodging()
            or targetIsParrying()
            or (targetHandler and (targetHandler.IsDodging or targetHandler.IsParrying))
        if targetAvoidingAttack and not localHandler:CanPerformUltimate() then
            pendingJumpAttackUntil = nil
            if actionManager._queuedActionType == "Jump" then
                actionManager:_clearQueuedAction()
            end
            return
        end
        if defenseIntent or localHandler.IsParrying or actionManager.BlockAction then
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
        local targetStateModel = targetHandler and targetHandler.Model or targetModel
        local targetPosture = targetStateModel and targetStateModel:GetAttribute("Posture")
        local targetMaximumPosture = targetStateModel
            and targetStateModel:GetAttribute("MaxPosture")
        local targetCloseToPostureBreak = type(targetPosture) == "number"
            and type(targetMaximumPosture) == "number"
            and targetMaximumPosture > 0
            and targetPosture / targetMaximumPosture <= 0.4
        local reserveUltimateForShieldBreak = ultimateAvailable
            and ((ultimateReadyAt and now - ultimateReadyAt < ULTIMATE_SHIELD_BREAK_RESERVE)
                or targetCloseToPostureBreak)
        local priorityWeaponHandler = localHandler:GetEquippedWeaponHandler()
        local priorityWeaponInfo = priorityWeaponHandler
            and priorityWeaponHandler.WeaponInfo
        local priorityAttackTypes = priorityWeaponInfo
            and priorityWeaponInfo.BasicAttackTypes
        local priorityUltimateInfo = priorityAttackTypes and priorityAttackTypes.Ultimate
        local priorityUltimateInRange = priorityUltimateInfo ~= nil
            and ultimateAvailable
            and not reserveUltimateForShieldBreak
            and offensiveAttackCanReach(localHandler.Root, targetRoot, priorityUltimateInfo)
            and hasClearPath(
                localHandler.Root,
                { localHandler.Model, localHandler.OriginalModel },
                targetRoot,
                { targetHandler and targetHandler.Model, targetModel }
            )
        if priorityUltimateInRange then
            if actionManager._queuedActionType == "BasicAttack" then
                actionManager:_clearQueuedAction()
            end
            local currentAction = actionManager.CurrentAction
            if currentAction
                and currentAction.ActionType == "BasicAttack"
                and currentAction.CanCancel
            then
                actionManager:SwitchToAction(nil)
            end
        end
        local currentAction = actionManager.CurrentAction
        if currentAction
            and currentAction.ActionType == "BasicAttack"
            and currentAction.CanQueueBasicAttacks
            and not actionManager._queuedActionType
            and not defenseIntent
            and not hasIncomingThreat(true)
            and not targetIsDodging()
            and not targetIsParrying()
            and not (targetHandler and (targetHandler.IsDodging or targetHandler.IsParrying))
        then
            local skill = Skill.profile(settings.botSkill)
            local stylePreferences = Styles.preferences(settings.combatStyle, nil, dynamicState)
            if (stylePreferences.aggressiveCombos or Skill.shouldPunish(skill, skillRandom))
                and actionManager:TryQueueBasicAttack("Light")
            then
                lastFightAttackAt = os.clock()
                appendCurrentMatchEvent("comboAttack", {
                    result = "queued",
                    attack = actionManager:_resolveAttackName("Light"),
                    skill = skill.level,
                })
            end
            return
        end
        if currentAction or actionManager._queuedActionType then
            return
        end
        if os.clock() < nextNeutralAttackAt and not priorityUltimateInRange then
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
        local stylePreferences = Styles.preferences(settings.combatStyle, {
            health = localHandler.Model and localHandler.Model:GetAttribute("Health"),
            maximumHealth = localHandler.Model and localHandler.Model:GetAttribute("MaxHealth"),
            posture = localHandler.Model and localHandler.Model:GetAttribute("Posture"),
            maximumPosture = localHandler.Model and localHandler.Model:GetAttribute("MaxPosture"),
            defenseReady = (actionManager._dodgeStamina or 0) >= 0.99
                and (actionManager._blockStrength or 0) > 0.01,
        }, dynamicState)
        if stylePreferences.movement then
            local movement = stylePreferences.movement
            profile = {
                approachDistance = movement.approachDistance
                    or profile.approachDistance,
                orbitDistance = movement.orbitDistance
                    or profile.orbitDistance
                        * (movement.orbitDistanceScale or 1),
                retreatDistance = movement.retreatDistance
                    or profile.retreatDistance,
                neutralAttack = profile.neutralAttack,
                neutralCadence = profile.neutralCadence,
                safeRangeBuffer = profile.safeRangeBuffer,
                maximumNeutralAttackDistance = profile.maximumNeutralAttackDistance,
            }
        end
        local distance = (Vector3.new(targetRoot.Position.X, 0, targetRoot.Position.Z)
            - Vector3.new(localRoot.Position.X, 0, localRoot.Position.Z)).Magnitude
        local targetReach = getTargetGeometricReach(targetHandler)
        local safelyOutsideCounterRange = targetReach <= 0
            or distance >= targetReach + profile.safeRangeBuffer
        local targetBlocking = targetIsBlocking()
            or (targetHandler and targetHandler.IsBlocking)
        local targetStaggered = targetIsStaggered()
        local punishWindow = getTargetPunishWindow()
        local skill = Skill.profile(settings.botSkill)

        if not priorityUltimateInRange
            and os.clock() - lastFightAttackAt < profile.neutralCadence
        then
            return
        end

        local lightInfo = attackTypes[actionManager:_resolveAttackName("Light")]
        local heavyInfo = attackTypes[actionManager:_resolveAttackName("Heavy")]
        local ultimateInfo = attackTypes.Ultimate
        local ultimateReady = ultimateInfo ~= nil
            and ultimateAvailable
            and not reserveUltimateForShieldBreak
            and os.clock() - lastUltimateAttemptAt >= ULTIMATE_RETRY_INTERVAL
        local ultimateCanHit = ultimateReady
            and offensiveAttackCanReach(localRoot, targetRoot, ultimateInfo)
        local normalAttackWithinRange = profile.maximumNeutralAttackDistance == nil
            or distance <= profile.maximumNeutralAttackDistance
        local lightCanHit = normalAttackWithinRange
            and offensiveAttackCanReach(localRoot, targetRoot, lightInfo)
        local heavyCanHit = normalAttackWithinRange
            and offensiveAttackCanReach(localRoot, targetRoot, heavyInfo)
        local attack
        if ultimateCanHit then
            if not Skill.shouldPunish(skill, skillRandom) then
                return
            end
            attack = "Ultimate"
        elseif targetAvoidingAttack then
            return
        elseif targetBlocking or targetStaggered then
            if not Skill.shouldPunish(skill, skillRandom) then
                return
            end
            attack = "Heavy"
        elseif lightCanHit and stylePreferences.allowOffense ~= false then
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

        if attack ~= "Ultimate"
            and punishWindow > 0
            and not targetStaggered
            and attackImpactTime + networkMargin >= punishWindow
        then
            return
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
            attackInfo = alternateInfo
        end

        local queued = actionManager:TryQueueBasicAttack(attack)
        if attack == "Ultimate" then
            lastUltimateAttemptAt = os.clock()
            appendCurrentMatchEvent("ultimateAttempt", {
                result = queued and "queueAccepted" or "rejected",
                distance = distance,
                targetBlocking = targetBlocking,
                targetDodging = targetIsDodging()
                    or (targetHandler and targetHandler.IsDodging)
                    or false,
                targetParrying = targetIsParrying()
                    or (targetHandler and targetHandler.IsParrying)
                    or false,
            })
        end
        if queued then
            lastFightAttackAt = os.clock()
            local canCancel = getAttackMarker(attackInfo, "canCancel")
                or getFirstImpactTime(attackInfo)
                or 0.5
            local recoveryDelay = (targetBlocking or targetStaggered or punishWindow > 0)
                and OFFENSIVE_RECOVERY_MIN
                or offenseRandom:NextNumber(OFFENSIVE_RECOVERY_MIN, OFFENSIVE_RECOVERY_MAX)
            nextNeutralAttackAt = lastFightAttackAt + canCancel + recoveryDelay
            if settings.combatStyle == "dynamic"
                and dynamicState.mode == "probing"
            then
                dynamicState.probeUntil = lastFightAttackAt + 1.25
            end
        end
    end

    local function updateAutoMovement(settings)
        if settings.autoMovement ~= true or settings.autoFight ~= true then
            autoMoveMode = nil
            autoMoveTarget = nil
            lastMovementCheckPosition = nil
            return
        end
        if settings.combatStyle == "tele" then
            autoMoveMode = nil
            autoMoveTarget = nil
            lastMovementCheckPosition = nil
            if playerInputController.CurrentInput then
                playerInputController.CurrentInput.MoveDirection = Vector3.zero
            end
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
        local stylePreferences = Styles.preferences(settings.combatStyle, {
            health = localHandler.Model and localHandler.Model:GetAttribute("Health"),
            maximumHealth = localHandler.Model and localHandler.Model:GetAttribute("MaxHealth"),
            posture = localHandler.Model and localHandler.Model:GetAttribute("Posture"),
            maximumPosture = localHandler.Model and localHandler.Model:GetAttribute("MaxPosture"),
            defenseReady = (actionManager._dodgeStamina or 0) >= 0.99
                and (actionManager._blockStrength or 0) > 0.01,
        }, dynamicState)
        if stylePreferences.movement then
            local movement = stylePreferences.movement
            profile = {
                approachDistance = movement.approachDistance
                    or profile.approachDistance,
                orbitDistance = movement.orbitDistance
                    or profile.orbitDistance
                        * (movement.orbitDistanceScale or 1),
                retreatDistance = movement.retreatDistance
                    or profile.retreatDistance,
                neutralAttack = profile.neutralAttack,
                neutralCadence = profile.neutralCadence,
                safeRangeBuffer = profile.safeRangeBuffer,
                maximumNeutralAttackDistance = profile.maximumNeutralAttackDistance,
            }
        end

        local currentAction = actionManager.CurrentAction
        local canMoveAfterImpact = currentAction
            and currentAction.ActionType == "BasicAttack"
            and currentAction.CanCancel
            and not actionManager._queuedActionType
        if defenseIntent
            or hasIncomingThreat(true)
            or actionManager._queuedActionType
            or actionManager.BlockAction
            or (currentAction and not canMoveAfterImpact)
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
            nextOrbitSwitchAt = os.clock()
                + offenseRandom:NextNumber(1.2, 2.6)
            wallEscapeDirection = nil
            wallEscapeUntil = -math.huge
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
        local flashyDash = stylePreferences.proactiveDashCounter == true
            and distance > attackReach + 0.25
            and distance <= attackReach + AUTO_MOVE_DASH_EXTRA_REACH
        if attackReach > 0
            and (settings.combatStyle == "offensive" or flashyDash)
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
            lastDodgeAt = os.clock()
            lastApproachDashAt = lastDodgeAt
            if flashyDash then
                pendingDodgeCounterAt = lastDodgeAt + 0.12
                pendingDodgeCounterUntil = lastDodgeAt + 0.38
            end
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
            if os.clock() >= nextOrbitSwitchAt then
                orbitDirection = -orbitDirection
                nextOrbitSwitchAt = os.clock()
                    + (stylePreferences.movement and stylePreferences.movement.orbitInterval
                        or offenseRandom:NextNumber(1.2, 2.6))
            end
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
        local rayOrigin = localRoot.Position + Vector3.new(0, 0.5, 0)
        local function castObstacle(castDirection, castDistance)
            local result = context.workspace:Raycast(
                rayOrigin,
                castDirection * castDistance,
                parameters
            )
            return result and result.Instance.CanCollide and result or nil
        end
        local obstacle = castObstacle(direction, 3)
        if obstacle and obstacle.Instance.CanCollide then
            if stylePreferences.escapeCorners == true then
                local now = os.clock()
                if not wallEscapeDirection or now >= wallEscapeUntil then
                    direction, orbitDirection = WallEscape.choose(
                        toward,
                        castObstacle,
                        6,
                        orbitDirection
                    )
                    wallEscapeDirection = direction
                    wallEscapeUntil = now + 0.6
                else
                    direction = wallEscapeDirection
                end
            else
                orbitDirection = -orbitDirection
                direction = Vector3.new(-toward.Z, 0, toward.X) * orbitDirection
            end
            autoMoveMode = "orbit"
        elseif os.clock() >= wallEscapeUntil then
            wallEscapeDirection = nil
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

    local function updateCombatTelemetry(settings)
        if type(context.updateCombatTelemetry) ~= "function" then
            return
        end
        local now = os.clock()
        if now - lastTelemetryPublishAt < 0.05 then
            return
        end
        lastTelemetryPublishAt = now
        local latest = recording:getLatestMatch()
        context.updateCombatTelemetry({
            replayVisible = settings.fightReplay == true,
            replay = latest and latest.timeline or nil,
        })
    end

    local function updateTeleportBehind(settings)
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        local targetRoot = targetModel and targetModel:FindFirstChild("HumanoidRootPart") or target
        local localHandler = characterController:GetLocalCharacterHandler()
        local localRoot = localHandler and localHandler.Root
        TeleportBehind.update(settings, {
            targetDead = targetModel and targetModel:GetAttribute("IsDead") == true,
            localRoot = localRoot,
            targetRoot = targetRoot,
            distance = TARGET_BACKSTEP_DISTANCE,
        })
    end

    local runService = game:GetService("RunService")
    local telePhysicsConnection = runService.PreSimulation:Connect(function()
        if stopped then
            return
        end

        local settings = context.store:Get().settings or {}
        if settings.autoFight ~= true
            or settings.combatStyle ~= "tele"
            or not teleState.serverCFrame
        then
            return
        end

        local localHandler = characterController:GetLocalCharacterHandler()
        local root = localHandler and localHandler.Root
        if root then
            root.CFrame = teleState.serverCFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    local connection = runService.RenderStepped:Connect(function()
        if stopped then
            return
        end

        local settings = context.store:Get().settings or {}
        updateLocalCombatObservation()
        updateAutoDefense(settings)
        updateMatchRecording(settings, getTargetPunishWindow())
        updateCombatTelemetry(settings)
        updateTeleportBehind(settings)
        updateAutoFight(settings)
        updateAutoMovement(settings)
        noclip:update(settings.noclip == true, localPlayer.Character)
        winTitles:update(settings.showWins == true, context.players)
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
            "showWins",
            "autoFight",
            "autoMovement",
            "duelEscapeKey",
            "fightReplay",
            "combatStyle",
            "teleportBehind",
            "multiJump",
            "noclip",
        },
        isOpponent = function(player)
            return player ~= nil and player ~= localPlayer
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            if teleNetworkHook then
                teleNetworkHook.enabled = false
            end
            recording:stop("sessionStopped")
            if type(context.updateCombatTelemetry) == "function" then
                context.updateCombatTelemetry(nil)
            end
            disconnectEnemyAnimations()
            disconnectLocalCombatObservation()
            duelEscape:stop()
            multiJump:stop()
            noclip:stop()
            winTitles:stop()
            if activeParryBlock then
                activeParryBlock._wantsToRelease = true
                activeParryBlock = nil
            end
            telePhysicsConnection:Disconnect()
            connection:Disconnect()
        end,
    }
end

return DuelingGrounds
