local Persistence = {}
Persistence.__index = Persistence

local ROOT_FOLDER = "universal-hub/beta/logs"
local MATCH_FOLDER = ROOT_FOLDER .. "/duelinggrounds_1v1s"

function Persistence.new(dependencies)
    dependencies = dependencies or {}
    return setmetatable({
        writefile = dependencies.writefile,
        makefolder = dependencies.makefolder,
        isfolder = dependencies.isfolder,
        jsonEncode = dependencies.jsonEncode,
    }, Persistence)
end

local function ensureFolder(self, folder)
    if self.makefolder and (not self.isfolder or not self.isfolder(folder)) then
        self.makefolder(folder)
    end
end

function Persistence:save(version, match)
    if type(self.writefile) ~= "function" or type(self.jsonEncode) ~= "function" then
        return false
    end

    return pcall(function()
        ensureFolder(self, ROOT_FOLDER)
        ensureFolder(self, MATCH_FOLDER)
        local safeTarget = string.gsub(match.metadata.target or "opponent", "[^%w_%-]", "_")
        local fileName = ("match_%d_%04d_%s.json"):format(
            match.metadata.startedAt,
            match.metadata.id,
            safeTarget
        )
        match.metadata.file = MATCH_FOLDER .. "/" .. fileName
        self.writefile(match.metadata.file, self.jsonEncode({
            version = version,
            metadata = match.metadata,
            events = match.events,
            samples = match.samples,
        }))
    end)
end

return Persistence
