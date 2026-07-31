local Presentation = {}

local function report(host, message)
    pcall(host.action, host, "reportPlotCopyError", message)
end

local function invoke(host, callbackName)
    local succeeded, accepted, message = pcall(host.action, host, callbackName)
    if not succeeded then
        report(host, "Plot copy action failed")
    elseif accepted == false then
        report(host, message or "Plot copy action could not start")
    end
end

function Presentation.mount(host)
    host:aim()
    host:plotCopy({
        listOwners = function()
            return host:action("listPlotOwners")
        end,
        primary = function(ownerName, saveName, closeDropdown)
            local plotCopyState = host:read().plotCopy
            local copyState = plotCopyState and plotCopyState.state or "idle"
            if plotCopyState.localCleanupAvailable then
                invoke(host, "cleanupPlotCopyCheckpoint")
            elseif plotCopyState.retryCleanupAvailable then
                invoke(host, "retryPlotCopyCleanup")
            elseif plotCopyState.resumeAvailable and copyState ~= "awaiting_confirmation" then
                invoke(host, "resumePlotCopy")
            elseif copyState == "awaiting_confirmation" then
                invoke(host, "confirmPlotCopy")
            elseif copyState == "rollback" or copyState == "rollback_incomplete" then
                invoke(host, "retryPlotCopyCleanup")
            elseif copyState == "cleanup_pending" then
                invoke(host, "cleanupPlotCopyCheckpoint")
            elseif copyState == "paused" then
                invoke(host, "resumePlotCopy")
            elseif copyState == "copying"
                or copyState == "preflight"
                or copyState == "reconciling"
                or copyState == "resuming"
            then
                invoke(host, "cancelPlotCopy")
            elseif copyState == "idle" or copyState == "completed" or copyState == "error" then
                if not ownerName then
                    report(host, "Choose a player plot to copy")
                elseif saveName == "" then
                    report(host, "Enter a save name")
                else
                    closeDropdown()
                    local succeeded, accepted, message = pcall(
                        host.action,
                        host,
                        "copyPlot",
                        ownerName,
                        saveName
                    )
                    if not succeeded then
                        report(host, "Plot copy could not start: " .. tostring(accepted))
                    elseif accepted == false then
                        report(host, message or "Plot copy could not start")
                    end
                end
            end
        end,
        reportError = function(message)
            report(host, message)
        end,
        secondary = function()
            local plotCopyState = host:read().plotCopy or {}
            if plotCopyState.state == "awaiting_confirmation" then
                invoke(host, "cancelPlotCopy")
            elseif plotCopyState.state == "paused" then
                invoke(host, "discardPlotCopy")
            end
        end,
    })
    host:cosmetics()
end

return Presentation
