local Policy = require("../games/rivals/TaskPolicy")
local groups = { Tasks = {
    { Name = "Done", Progress = 1, Completed = true },
    { Name = "Beginner2", Progress = 1, Completed = false },
}, EventTasks = { { Name = "EventEliminations", Progress = 2, Completed = false } } }
local controller = { Get = function(_, key) return groups[key] end }
local library = { TASKS_DATA_NAMES = { "Tasks", "EventTasks" }, Info = {
    Beginner2 = { Title = "Break targets", Goal = 5 },
    EventEliminations = { Title = "Get eliminations", Goal = 10 },
} }
local snapshot = Policy.snapshot(library, controller)
assert(#snapshot == 3 and snapshot[2].progress == 1 and snapshot[2].goal == 5)
assert(Policy.classify(snapshot[2]).kind == "range")
assert(Policy.classify(snapshot[3]).family == "eliminations")
assert(Policy.select(snapshot).name == "Beginner2", "active Tasks group wins deterministically")
assert(not Policy.requiresCombat(snapshot[2]) and Policy.requiresCombat(snapshot[3]))
local all = {}
for i = 1, 9 do table.insert(all, { name = "Beginner" .. i, title = "", group = "Tasks" }) end
for i = 1, 6 do assert(Policy.classify(all[i]).kind == "range") end
for i = 7, 9 do assert(Policy.classify(all[i]).kind == "pvp") end
all[1].locked = true
assert(Policy.select(all).name == "Beginner2", "locked ordered work must be skipped")
print("rivals-task-policy-contracts-ok")
