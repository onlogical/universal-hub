local AutoOpenEggs = {}
AutoOpenEggs.__index = AutoOpenEggs

local SCAN_INTERVAL = 0.25

function AutoOpenEggs.new(options)
    assert(
        options
            and options.eggCmds
            and options.renderer
            and options.localPlayer
            and options.runService
    )
    return setmetatable({
        eggCmds = options.eggCmds,
        renderer = options.renderer,
        localPlayer = options.localPlayer,
        runService = options.runService,
        spawn = options.spawn or task.spawn,
        opening = {},
        elapsed = 0,
        enabled = false,
    }, AutoOpenEggs)
end

function AutoOpenEggs:_scan()
    local records = self.eggCmds.GetOwnerRuntimeRecords(self.localPlayer.UserId)
    for uid in pairs(self.opening) do
        if not records[uid] or not self.eggCmds.IsLocalEggReady(uid) then
            self.opening[uid] = nil
        end
    end
    for uid, record in pairs(records) do
        if record.Placement and self.eggCmds.IsLocalEggReady(uid) and not self.opening[uid] then
            self.opening[uid] = true
            self.spawn(function()
                if not self.renderer.ActivateLocalEgg(uid) then
                    self.opening[uid] = nil
                end
            end)
        end
    end
end

function AutoOpenEggs:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self:_scan()
        self.connection = self.runService.Heartbeat:Connect(function(deltaTime)
            self.elapsed += deltaTime
            if self.elapsed >= SCAN_INTERVAL then
                self.elapsed = 0
                self:_scan()
            end
        end)
        return
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    table.clear(self.opening)
    self.elapsed = 0
end

function AutoOpenEggs:stop()
    self:setEnabled(false)
end

return AutoOpenEggs
