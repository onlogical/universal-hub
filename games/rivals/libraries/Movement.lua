local Movement = {}
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
        wallPhase = options.wallPhase,
        wallPhaseAt = 0,
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
    if self.movement
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
        if self.mechanicsController.IsSliding == true
            or readState("IsSlidingLocally", false)
        then
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
            local away = Vector3.new(
                position.X - hazardPosition.X,
                0,
                position.Z - hazardPosition.Z
            )
            local hazardDistance = away.Magnitude
            local avoidanceRadius = hazard.label == "GRENADE" and 38
                or hazard.label == "THROWABLE" and 34
                or hazard.label == "FIRE" and 30
                or 28
            if hazardDistance > 0.01 and hazardDistance < avoidanceRadius then
                nearby = true
                repulsion += away.Unit
                    * ((avoidanceRadius - hazardDistance) / avoidanceRadius)
                    * 4
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

function Movement:updateTaskCombat(targetPosition, hazards, tactical)
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local humanoid = entity and entity.Humanoid
    local root = entity and (entity.RootPart or entity.HumanoidRootPart)
    if self.isTaskInputCaptured()
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
    if self.taskHumanoid and self.taskHumanoid ~= humanoid then self:stopTaskCombat() end
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
    local offset = Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
    local distance = offset.Magnitude
    if distance < 0.01 then humanoid:Move(Vector3.zero, false); return end
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
    if repulsion.Magnitude > 0.01 then direction = (direction + repulsion).Unit end
    local parkour
    if type(self.taskParkourProbe) == "function" then
        parkour = self.taskParkourProbe(root.Position, direction, fighter)
    end
    local obstacleBlocked = type(self.taskObstacleProbe) == "function"
        and self.taskObstacleProbe(root.Position, direction, fighter)
    local performedParkour = false
    local commit = self.taskParkourCommit
    if commit then
        local landingOffset = Vector3.new(
            commit.landing.X - root.Position.X,
            0,
            commit.landing.Z - root.Position.Z
        )
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
            if landingDistance > 0.05 then direction = landingOffset.Unit end
            performedParkour = true
            local velocity = root.AssemblyLinearVelocity
            local descending = typeof(velocity) == "Vector3" and velocity.Y < -1
            local info = fighter.EquippedItem and fighter.EquippedItem.Info
            if not grounded and descending and not commit.usedDoubleJump
                and type(info) == "table" and type(info.MaxDoubleJumps) == "number"
                and info.MaxDoubleJumps > 0
                and type(self.mechanicsController.DoubleJumpRequest) == "function"
            then
                pcall(self.mechanicsController.DoubleJumpRequest, self.mechanicsController)
                commit.usedDoubleJump = true
            end
        end
    end
    if not commit and now >= self.taskParkourAt and type(parkour) == "table" then
        if grounded and typeof(parkour.jumpLanding) == "Vector3"
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
                if landingOffset.Magnitude > 0.05 then direction = landingOffset.Unit end
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
        if self.taskObstacleProbe(root.Position, side, fighter) then side = -side end
        direction = side
    end
    if self.taskProgressAt == 0 then
        self.taskProgressAt = now
        self.taskProgressPosition = root.Position
    elseif now - self.taskProgressAt >= 0.65 then
        local progressed = self.taskProgressPosition
            and (root.Position - self.taskProgressPosition).Magnitude >= 0.75
        if not commit and grounded and not progressed and distance > 10 and now >= self.taskParkourAt
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
    local shouldUseMobility = not performedParkour
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
        pcall(
            self.mechanicsController.SetCrouching,
            self.mechanicsController,
            self.taskCrouching
        )
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
        for _, descendant in ipairs(model:GetDescendants()) do track(descendant) end
        self.wallNoclipConnection = model.DescendantAdded:Connect(track)
    end
    -- RIVALS may restore character collision during its own physics update.
    -- Reassert only cached character parts; no descendant traversal occurs here.
    for part in pairs(self.wallNoclipParts) do
        if part.Parent and part.CanCollide then part.CanCollide = false end
    end
end

function Movement:updateWallPhase(settings)
    settings = settings or self.getSettings()
    if settings.wallPhase ~= true
        or self.isInputCaptured()
        or type(self.wallPhase) ~= "function"
        or self.clock() < self.wallPhaseAt
    then
        return
    end
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local humanoid = entity and entity.Humanoid
    local direction = self.movementDirection and self.movementDirection()
        or humanoid and humanoid.MoveDirection
    if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.1 then return end
    if self.wallPhase(fighter, direction.Unit) == true then
        self.wallPhaseAt = self.clock() + 0.35
    end
end

function Movement:updateInfiniteJump(settings)
    settings = settings or self.getSettings()
    local held = self.userInputService:IsKeyDown(Enum.KeyCode.Space) == true
    if settings.infiniteJump == true
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
    if not isMoving
        or self.isInputCaptured()
        or not self.isActive()
        or not self.isInCombat()
    then
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
