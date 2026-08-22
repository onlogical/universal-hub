local fs = require("@lune/fs")

local Definition = require("../games/duelinggrounds/Definition")
assert(Definition.defaults.attackRange == nil)
assert(Definition.defaults.randomAttackRange == nil)
assert(Definition.defaults.frameDataHud == nil)
assert(not table.find(Definition.sources, "games/duelinggrounds/features/combat/AttackRange"))
assert(not table.find(Definition.sources, "games/duelinggrounds/features/CombatTelemetryHud"))
assert(not table.find(Definition.sources, "games/duelinggrounds/features/combat/FrameData"))

local adapter = fs.readFile("games/DuelingGrounds.lua")
assert(not adapter:find("AttackRange", 1, true))
assert(not adapter:find("randomAttackRange", 1, true))
assert(adapter:find("context.updateCombatTelemetry", 1, true))

local presentation = fs.readFile("games/duelinggrounds/Presentation.lua")
assert(not presentation:find('id = "attackRange"', 1, true))
assert(not presentation:find("Random Range", 1, true))

local component = fs.readFile("ui/src/components/CombatTelemetry.tsx")
assert(component:find('from "@prism"', 1, true))
assert(component:find("FIGHT REPLAY", 1, true))
assert(component:find('kind: "drag" | "resize"', 1, true))
assert(component:find('locked ? "Unlock" : "Lock"', 1, true))

local menu = fs.readFile("ui/dist/Menu.lua")
assert(menu:find("FIGHT REPLAY", 1, true))

print("duelinggrounds-prism-telemetry-contracts-ok")
