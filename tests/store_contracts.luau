local Store = require("../modules/Store")

local store = Store.new({
    settings = {
        enabled = false,
        fov = 100,
    },
    status = "loading",
})
local emissions = {}
local unsubscribe = store:Subscribe(function(state)
    table.insert(emissions, {
        enabled = state.settings.enabled,
        status = state.status,
    })
end)

store:Patch({
    settings = {
        enabled = true,
    },
    status = "ready",
})

assert(store:Get().settings.enabled == true)
assert(store:Get().settings.fov == 100, "Nested patches must retain unrelated settings")
assert(#emissions == 2 and emissions[2].status == "ready")

unsubscribe()
store:Patch({ status = "ignored by old subscriber" })
assert(#emissions == 2, "Unsubscribed listeners must not receive updates")

store:Patch({
    notes = {
        added = { "Warp" },
        changed = { "Private matches leave the loadout to you" },
        fixed = { "Spawn protection" },
    },
})
store:Patch({
    notes = {
        added = { "Warp", "Auto Counter" },
        changed = {},
        fixed = {},
    },
})
assert(store:Get().notes.added[1] == "Warp")
assert(store:Get().notes.added[2] == "Auto Counter")
assert(#store:Get().notes.changed == 0, "List patches must replace leftover changelog items")
assert(#store:Get().notes.fixed == 0, "Empty list patches must clear previous items")

store:Destroy()
store:Patch({ status = "stopped" })
assert(store:Get().status == "ignored by old subscriber", "Destroyed stores must reject patches")
print("store-contracts-ok")
