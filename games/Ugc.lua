local Ugc = {}

local GUARD_KEY = 0x46
local DEFAULT_PARRY_RANGE = 25
local DEFAULT_PARRY_DELAY = 0.05
local PARRY_COOLDOWN = 0.4

local function isAttackTrack(track)
    local priority = track.Priority
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
    local stopped = false
    local lastParryAt = -math.huge
    local seenTracks = setmetatable({}, { __mode = "k" })

    local function parry()
        if type(context.keyPress) ~= "function" or type(context.keyRelease) ~= "function" then
            return
        end
        context.keyPress(GUARD_KEY)
        task.delay(0.04, function()
            if not stopped then
                context.keyRelease(GUARD_KEY)
            end
        end)
    end

    local function updateAutoParry(settings)
        if settings.autoParry ~= true then
            return
        end
        local localCharacter = localPlayer.Character
        local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
        if not localRoot or os.clock() - lastParryAt < PARRY_COOLDOWN then
            return
        end
        local range = math.clamp(tonumber(settings.autoParryRange) or DEFAULT_PARRY_RANGE, 5, 60)
        for _, player in ipairs(context.players:GetPlayers()) do
            local character = player ~= localPlayer and player.Character or nil
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
            if root and animator and (root.Position - localRoot.Position).Magnitude <= range then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    if isAttackTrack(track) and not seenTracks[track] then
                        seenTracks[track] = true
                        lastParryAt = os.clock()
                        local delay = math.clamp(
                            tonumber(settings.autoParryDelay) or DEFAULT_PARRY_DELAY,
                            0,
                            0.5
                        )
                        task.delay(delay, parry)
                        return
                    end
                end
            end
        end
    end

    local connection = game:GetService("RunService").RenderStepped:Connect(function()
        if stopped then
            return
        end

        local settings = context.store:Get().settings or {}
        updateAutoParry(settings)
        local observations = {}
        if settings.showEnemies ~= false then
            observations = context.oh.targeting.observePlayers({
                isEligible = function(player)
                    return player ~= localPlayer
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
            "autoParry",
            "autoParryRange",
            "autoParryDelay",
        },
        isOpponent = function(player)
            return player ~= nil and player ~= localPlayer
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            if type(context.keyRelease) == "function" then
                context.keyRelease(GUARD_KEY)
            end
            connection:Disconnect()
        end,
    }
end

return Ugc
