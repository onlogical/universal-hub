local Logger = require("../modules/Logger")

local files = {
	["universal-hub/logs/latest.log"] = "previous-session\n",
}
local now = 10
local folders = {}
local options = {
	appendFile = function(path, content)
		files[path] = (files[path] or "") .. content
	end,
	archiveName = function()
		return "session-fixed"
	end,
	isFile = function(path)
		return files[path] ~= nil
	end,
	makeFolder = function(path)
		folders[path] = true
	end,
	now = function()
		return now
	end,
	readFile = function(path)
		assert(files[path] ~= nil)
		return files[path]
	end,
	writeFile = function(path, content)
		files[path] = content
	end,
}

local logger = Logger.new(options)
assert(folders["universal-hub"] and folders["universal-hub/logs"])
assert(files["universal-hub/logs/session-fixed.log"] == "previous-session\n")
now = 10.25
logger:info("test", "egg dropped", { uid = "egg-1", state = "Dropped" })
logger:warn("test", "retrying")
local snapshot = logger:snapshot()
assert(#snapshot == 3 and snapshot[2]:find("egg dropped", 1, true))
assert(files["universal-hub/logs/latest.log"]:find("uid=egg-1", 1, true))
logger:close({ reason = "test" })
local closedContent = files["universal-hub/logs/latest.log"]
logger:error("test", "must not append")
assert(files["universal-hub/logs/latest.log"] == closedContent)

local replacement = Logger.new(options)
assert(files["universal-hub/logs/session-fixed-2.log"] == closedContent)
assert(files["universal-hub/logs/latest.log"]:find("START", 1, true))
replacement:close()
print("logger-ok")
