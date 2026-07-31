local Composition = {
    dependencies = {
        checkpointStore = "games/town/CheckpointStore",
    },
}

local function unavailable(message)
    return false, message
end

function Composition.bind(context, dependencies)
    assert(type(context) == "table", "Town composition requires a context")
    assert(type(dependencies) == "table", "Town composition requires dependencies")
    local CheckpointStore = assert(
        dependencies.checkpointStore,
        "Town composition requires its checkpoint store"
    )
    local checkpoint = CheckpointStore.new({
        decode = context.decode,
        deleteFile = context.files.delete,
        encode = context.encode,
        isFile = context.files.isFile,
        listFiles = context.files.list,
        makeFolder = context.files.makeFolder,
        readFile = context.files.read,
        root = context.config("TownCopyCheckpointRoot", "universal-hub/private/town-copy"),
        userId = context.userId,
        writeFile = context.files.write,
    })
    if checkpoint.available then
        pcall(function()
            checkpoint:prune()
        end)
    end

    local function adapter()
        return context.getAdapter()
    end

    local function spawn(methodName, message, ...)
        local current = adapter()
        if not current or type(current[methodName]) ~= "function" then
            return unavailable(message)
        end
        local arguments = { ... }
        context.spawn(function()
            current[methodName](current, table.unpack(arguments))
        end)
        return true
    end

    local result = {
        adapter = {
            checkpoint = checkpoint,
        },
        inputCapture = {
            releaseMouseOnDisable = true,
        },
        overlay = {
            listPlotOwners = function()
                local current = adapter()
                if current and type(current.listPlotOwners) == "function" then
                    return current:listPlotOwners()
                end
                return {}
            end,
            copyPlot = function(ownerName, saveName)
                return spawn("copyPlot", "Plot copying is not ready", ownerName, saveName)
            end,
            cancelPlotCopy = function()
                return spawn("cancelCopy", "Plot copy cancellation is not ready")
            end,
            confirmPlotCopy = function()
                return spawn("confirmCopy", "Plot copy confirmation is not ready")
            end,
            discardPlotCopy = function()
                return spawn("discardCopy", "Plot copy discard is not ready")
            end,
            resumePlotCopy = function()
                return spawn("resumeCopy", "Plot copy resume is not ready")
            end,
            retryPlotCopyCleanup = function()
                return spawn("retryCopyCleanup", "Plot copy cleanup is not ready")
            end,
            cleanupPlotCopyCheckpoint = function()
                return spawn(
                    "cleanupCopyCheckpoint",
                    "Local copy recovery cleanup is not ready"
                )
            end,
            reportPlotCopyError = function(message)
                context.getStore():Patch({
                    plotCopy = {
                        active = false,
                        confirmedProgress = 0,
                        context = message,
                        error = message,
                        phase = "Copy blocked",
                        state = "error",
                    },
                })
            end,
        },
    }

    function result.afterAdapter(current)
        if type(current.inspectCopyRecovery) ~= "function" then
            return
        end
        local recovered = pcall(function()
            current:inspectCopyRecovery()
        end)
        if not recovered then
            context.getStore():Patch({
                plotCopy = {
                    active = false,
                    context = "Recovery inspection failed before any Town mutation",
                    error = "Persistent copy recovery could not be inspected",
                    phase = "Copy blocked",
                    state = "error",
                },
            })
        end
    end

    return result
end

return Composition
