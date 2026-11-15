--[[
    GTD CONTROL HUB • DELTA v2.2.37

    Playback reliability update, based on the existing v2.2.30 source:
      • Stable per-match session generation, including Context reuse.
      • Short grace for transient RoundLive=false flickers during playback.
      • Late PlaceUnit response verification through Entity ChildAdded events;
        no duplicate placement is sent after an ambiguous timeout.
      • Longer event-ID/model replication window before dependent actions run.
      • The loop preference is retained in the executor environment.
      • Macro list refresh, same-name RE-RECORD, CANCEL and DELETE remain
        integrated in the main Macro Recorder card.

    This is a source-transforming loader. Upload this complete file to the
    repository as GTD_Control_Hub_Delta_v2.2.37.lua, then run its raw URL.
]]

local BASE_URL = "https://raw.githubusercontent.com/litvinovasez-eng/gtd-control-hub/main/GTD_Control_Hub_Delta_v2.2.30.lua"
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local downloaded, source = pcall(function()
    return game:HttpGet(BASE_URL)
end)
if not downloaded or type(source) ~= "string" or source == "" then
    error("GTD Control Hub v2.2.37: could not download the base source: " .. tostring(source))
end

local function plainReplace(text, oldText, newText, label, expectedCount)
    local result = {}
    local position = 1
    local count = 0
    while true do
        local first, last = string.find(text, oldText, position, true)
        if not first then break end
        result[#result + 1] = string.sub(text, position, first - 1)
        result[#result + 1] = newText
        position = last + 1
        count = count + 1
    end
    result[#result + 1] = string.sub(text, position)
    if expectedCount ~= nil and count ~= expectedCount then
        error("GTD Control Hub v2.2.37 patch mismatch [" .. tostring(label)
            .. "]: expected " .. tostring(expectedCount) .. ", found " .. tostring(count))
    end
    return table.concat(result), count
end

local function replaceBetween(text, startMarker, endMarker, newText, label)
    local first = string.find(text, startMarker, 1, true)
    if not first then error("GTD Control Hub v2.2.37 missing start anchor: " .. label) end
    local finish = string.find(text, endMarker, first, true)
    if not finish then error("GTD Control Hub v2.2.37 missing end anchor: " .. label) end
    return string.sub(text, 1, first - 1) .. newText .. "\n" .. string.sub(text, finish)
end

-- Version and GUI identity.
source = plainReplace(source, "v2.2.30", "v2.2.37", "version labels")
source = plainReplace(source, "GTDControlHub_Delta_v2230", "GTDControlHub_Delta_v2236", "GUI identity")

-- Persist the loop toggle between script re-executions where the executor environment survives.
source = plainReplace(source, "    Loop = true,", "    Loop = ENV.__GTDCH_MACRO_LOOP ~= false,", "loop default", 1)
source = plainReplace(source,
[[connect(LoopSwitch.Activated, function()
    State.Loop = not State.Loop
    tween(LoopSwitch, 0.17, {BackgroundColor3 = State.Loop and Theme.green or Theme.panel3})]],
[[connect(LoopSwitch.Activated, function()
    State.Loop = not State.Loop
    ENV.__GTDCH_MACRO_LOOP = State.Loop
    tween(LoopSwitch, 0.17, {BackgroundColor3 = State.Loop and Theme.green or Theme.panel3})]],
    "persist loop switch", 1)

-- Replace timeline waiting so a short RoundLive=false transition does not discard the queue.
source = replaceBetween(source, "local function waitForPlaybackTime(", "\nlocal function invokePlacementWithTimeout", [[Macro.WaitForPlaybackRound = function(expectedRoundKey, taskId, graceSeconds)
    local deadline = os.clock() + (tonumber(graceSeconds) or 4.5)
    repeat
        if not State.Playing or State.PlaybackTaskId ~= taskId then return false end
        if expectedRoundKey and State.CurrentRoundKey ~= expectedRoundKey then return false end
        if State.RoundLive then return true end
        task.wait(0.10)
    until os.clock() >= deadline
    return State.Playing and State.PlaybackTaskId == taskId
        and (not expectedRoundKey or State.CurrentRoundKey == expectedRoundKey)
        and State.RoundLive
end

local function waitForPlaybackTime(action, fallbackDelay, timelineClock, firstActionElapsed, taskId, expectedRoundKey)
    local actionElapsed = tonumber(action.elapsed)
    local function sessionValid()
        return State.Playing and State.PlaybackTaskId == taskId
            and (not expectedRoundKey or State.CurrentRoundKey == expectedRoundKey)
    end

    -- Keep recorded action gaps while tolerating brief false updates during UI/context swaps.
    if timelineClock and firstActionElapsed ~= nil and actionElapsed ~= nil then
        local offset = math.max(0, actionElapsed - firstActionElapsed)
        local targetClock = timelineClock + offset
        local lastLiveAt = os.clock()
        while sessionValid() do
            if State.RoundLive then
                lastLiveAt = os.clock()
                local remaining = targetClock - os.clock()
                if remaining <= 0 then return true end
                task.wait(math.min(remaining, 0.20))
            else
                if os.clock() - lastLiveAt > 4.5 then return false end
                task.wait(0.10)
            end
        end
        return false
    end

    local remaining = math.max(0, tonumber(fallbackDelay) or 0)
    local lastLiveAt = os.clock()
    while remaining > 0 and sessionValid() do
        if State.RoundLive then
            lastLiveAt = os.clock()
            local slice = math.min(remaining, 0.20)
            task.wait(slice)
            remaining = remaining - slice
        else
            if os.clock() - lastLiveAt > 4.5 then return false end
            task.wait(0.10)
        end
    end
    return sessionValid() and State.RoundLive
end]], "round-tolerant playback timeline")

-- Keep the pre-call ID snapshot when a PlaceUnit InvokeServer times out.
source = plainReplace(source,
[[if not response then
        return false, "PlaceUnit timed out; stopped to avoid sending duplicate requests"
    end]],
[[if not response then
        return false, "PlaceUnit timed out; checking for a late server placement before stopping", beforeIds
    end]], "preserve snapshot on timeout", 1)

-- Placement retry should tolerate short live-state flickers without sending duplicate calls.
source = plainReplace(source,
[[local function invokePlacementWithRetry(action, payload, taskId)
    -- Explicit server rejection is safe to retry: no placement was accepted.
    -- A timeout or thrown remote error is NOT retried because the server may have
    -- processed the request even though the client did not receive the response.
    local deadline = os.clock() + 18
    local attempts = 0
    local lastError = "server rejected placement"
    repeat
        if not State.Playing or State.PlaybackTaskId ~= taskId or not State.RoundLive then
            return false, "playback stopped"
        end]],
[[local function invokePlacementWithRetry(action, payload, taskId, expectedRoundKey)
    -- Explicit rejection is safe to retry. Ambiguous timeout/error responses are never
    -- resent until the event cache confirms whether the first request actually placed a tower.
    local deadline = os.clock() + 18
    local attempts = 0
    local lastError = "server rejected placement"
    repeat
        if not Macro.WaitForPlaybackRound(expectedRoundKey, taskId, 4.5) then
            return false, "playback round changed or stopped before placement retry"
        end]], "placement retry round grace", 1)

-- On ambiguous timeout/error, look for the placed entity before declaring failure.
source = plainReplace(source,
[[        lastError = tostring(placeError or "unknown placement failure")
        if not lastError:find("server returned false", 1, true) then
            return false, lastError
        end]],
[[        lastError = tostring(placeError or "unknown placement failure")
        if lastError:find("timed out", 1, true) or lastError:find("PlaceUnit error:", 1, true) then
            -- The server may have accepted PlaceUnit even if InvokeServer timed out locally.
            -- Confirm via ChildAdded events before deciding that the action failed.
            local lateId = Macro.waitForNewTowerId(action, beforeIds or {}, 18, taskId, nil, State.ActiveContext)
            if lateId then return true, nil, beforeIds, lateId end
            return false, lastError .. " • no matching late tower event was observed"
        end
        if not lastError:find("server returned false", 1, true) then
            return false, lastError
        end]], "late placement confirmation", 1)

-- Give every match a generation, even when GTD reuses the same Context/Entities and start time.
source = replaceBetween(source, "local function getRoundKey(context)", "\nlocal function isInLiveRound", [[-- Generate a session key when a fresh match starts even if GTD reuses Context/Entities.
State.RoundSessionGeneration = tonumber(State.RoundSessionGeneration) or 0
State.RoundSessionContext = nil
State.RoundSessionEntities = nil
State.RoundSessionBaseKey = nil
State.RoundSessionEndedSince = nil

local function getRoundKey(context)
    local startTime = getGameAttribute("GameStartTime", context)
    local entities = context and context:FindFirstChild("Entities") or nil
    local baseKey = context and context:GetFullName() .. ":" .. tostring(startTime or "no-start-time")
        or "workspace:" .. tostring(startTime or "no-context")
    local structureChanged = baseKey ~= State.RoundSessionBaseKey
        or context ~= State.RoundSessionContext
        or entities ~= State.RoundSessionEntities

    if structureChanged then
        State.RoundSessionGeneration = State.RoundSessionGeneration + 1
        State.RoundSessionBaseKey = baseKey
        State.RoundSessionContext = context
        State.RoundSessionEntities = entities
        State.RoundSessionEndedSince = nil
    end

    local started = type(startTime) == "number" and startTime > 0
    local ended = not started or Macro.isContextEnded(context)
    if ended then
        State.RoundSessionEndedSince = State.RoundSessionEndedSince or os.clock()
    elseif State.RoundSessionEndedSince then
        -- Ignore one-frame GameEnd/Context flickers; only increment after a stable end-to-live transition.
        if os.clock() - State.RoundSessionEndedSince >= 0.65 then
            State.RoundSessionGeneration = State.RoundSessionGeneration + 1
        end
        State.RoundSessionEndedSince = nil
    end

    return baseKey .. ":session:" .. tostring(State.RoundSessionGeneration)
end]], "round session generation")

-- Do not abort the action queue solely because RoundLive was false for one update.
source = plainReplace(source,
[[if not State.Playing or State.PlaybackTaskId ~= taskId
                            or not State.RoundLive or State.CurrentRoundKey ~= roundKey then break end

                        local fallbackDelay = math.max(0, tonumber(action.delay) or 0)
                        if not waitForPlaybackTime(action, fallbackDelay, timelineClock, firstActionElapsed, taskId) then break end
                        if not State.RoundLive or State.CurrentRoundKey ~= roundKey then break end]],
[[if not State.Playing or State.PlaybackTaskId ~= taskId
                            or State.CurrentRoundKey ~= roundKey then break end

                        local fallbackDelay = math.max(0, tonumber(action.delay) or 0)
                        if not waitForPlaybackTime(action, fallbackDelay, timelineClock, firstActionElapsed, taskId, roundKey) then break end
                        if not State.Playing or State.PlaybackTaskId ~= taskId
                            or State.CurrentRoundKey ~= roundKey then break end]], "action queue live-state grace", 1)

source = plainReplace(source,
"invokePlacementWithRetry(placementAction, payload, taskId)",
"invokePlacementWithRetry(placementAction, payload, taskId, roundKey)", "pass expected session to placement", 1)
source = plainReplace(source,
"Macro.waitForNewTowerId(placementAction, beforeIds or {}, 9, taskId, nil, State.ActiveContext)",
"Macro.waitForNewTowerId(placementAction, beforeIds or {}, 18, taskId, nil, State.ActiveContext)", "longer tower ID wait", 1)
source = plainReplace(source,
"and now - (event.time or now) <= 15 then",
"and now - (event.time or now) <= 30 then", "longer arrival event retention", 1)

-- Wait briefly for a replicated entity model instead of prematurely aborting dependent actions.
source = plainReplace(source,
[[                                local liveModel = Macro.findLiveTowerModelById and Macro.findLiveTowerModelById(towerId, State.ActiveContext)
                                if not liveModel then
                                    actionError = "mapped live ID " .. tostring(towerId) .. " is not present in active Entities"
                                elseif expectedUnit and liveModel.Name ~= expectedUnit then]],
[[                                local liveModel = Macro.findLiveTowerModelById and Macro.findLiveTowerModelById(towerId, State.ActiveContext)
                                if not liveModel then
                                    local modelWaitDeadline = os.clock() + 4
                                    repeat
                                        if not State.Playing or State.PlaybackTaskId ~= taskId
                                            or State.CurrentRoundKey ~= roundKey then break end
                                        task.wait(0.10)
                                        liveModel = Macro.findLiveTowerModelById and Macro.findLiveTowerModelById(towerId, State.ActiveContext)
                                    until liveModel or os.clock() >= modelWaitDeadline
                                end
                                if not liveModel then
                                    actionError = "mapped live ID " .. tostring(towerId) .. " did not replicate into Entities within 4s"
                                elseif expectedUnit and liveModel.Name ~= expectedUnit then]], "wait for tower model replication", 1)

-- If a match boundary interrupts an action, keep the loop armed for the next match.
source = plainReplace(source,
[[                        if not actionOk then
                            if State.Playing and State.PlaybackTaskId == taskId then
                                State.Playing = false
                                State.PlaybackArmed = false
                                setStatus("Проигрывание остановлено на действии №" .. tostring(index) .. ": " .. tostring(actionError), Theme.red)
                            end
                            break
                        end]],
[[                        if not actionOk then
                            if State.Playing and State.PlaybackTaskId == taskId then
                                if State.Loop and (not State.RoundLive or State.CurrentRoundKey ~= roundKey) then
                                    setStatus("Матч сменился на действии №" .. tostring(index)
                                        .. " • полный макрос повторится в следующем матче", Theme.amber)
                                else
                                    State.Playing = false
                                    State.PlaybackArmed = false
                                    setStatus("Проигрывание остановлено на действии №" .. tostring(index)
                                        .. " (" .. tostring(actionType) .. "): " .. tostring(actionError), Theme.red)
                                end
                            end
                            break
                        end]], "keep loop alive after round boundary", 1)

-- Clear overwrite state after a successful same-name save.
source = plainReplace(source,
[[    State.MacroIsDraft = false
    State.SelectedMacroSlotName = State.MacroName
    State.RefreshMacroSlotSelector(State.MacroName)]],
[[    State.MacroIsDraft = false
    State.MacroOverwriteArmed = false
    State.MacroOverwriteTargetName = nil
    State.SelectedMacroSlotName = State.MacroName
    State.RefreshMacroSlotSelector(State.MacroName)]], "clear re-record state after save", 1)

-- Keep macro-management controls directly in the base script.
do
    local macroTools = [=[
-- Integrated macro controls: refresh, same-name re-record and delete.
do
    State.MacroRefreshButton = secondaryButton(MacroActions, "↻ REFRESH",
        UDim2.new(1,-94,0,31), UDim2.fromOffset(80,27), function() end)
    State.MacroRefreshButton.TextSize = 9
    State.MacroPickerButton.Size = UDim2.new(1,-108,0,27)
    CountLabel.Size = UDim2.new(1,-190,0,16)

    State.MacroReRecordButton = secondaryButton(MacroActions, "RE-RECORD",
        UDim2.new(1,-184,0,91), UDim2.fromOffset(80,23), function() end)
    State.MacroDeleteSelectedButton = secondaryButton(MacroActions, "DELETE",
        UDim2.new(1,-96,0,91), UDim2.fromOffset(80,23), function() end)

    State.UpdateMacroToolButtons = function()
        local selected = not State.MacroIsDraft and State.SelectedMacroSlotName
        local valid = type(selected) == "string" and selected ~= "" and State.MacroName == selected
        local busy = State.Recording or State.RecordingArmed or State.Playing
        State.MacroReRecordButton.Text = State.MacroOverwriteArmed and "CANCEL" or "RE-RECORD"
        State.MacroReRecordButton.Active = not busy and (State.MacroOverwriteArmed or valid)
        State.MacroReRecordButton.AutoButtonColor = State.MacroReRecordButton.Active
        State.MacroReRecordButton.BackgroundColor3 = State.MacroOverwriteArmed
            and Theme.red or (valid and Theme.panel3 or Theme.panel)
        State.MacroDeleteSelectedButton.Active = not busy and valid
        State.MacroDeleteSelectedButton.AutoButtonColor = State.MacroDeleteSelectedButton.Active
        State.MacroDeleteSelectedButton.BackgroundColor3 = valid and Theme.red or Theme.panel
        State.MacroDeleteSelectedButton.Text = selected and State.MacroDeleteConfirmName == selected
            and "CONFIRM?" or "DELETE"
    end

    State.RefreshMacroSlotSelectorOriginal = State.RefreshMacroSlotSelector
    State.RefreshMacroSlotSelector = function(...)
        local result = State.RefreshMacroSlotSelectorOriginal(...)
        State.UpdateMacroToolButtons()
        return result
    end

    connect(State.MacroRefreshButton.Activated, function()
        local ok, err = pcall(State.EnsureMacroFolders)
        if not ok then setStatus("Macro folder refresh failed: " .. tostring(err), Theme.red); return end
        State.RefreshMacroSlotSelector(State.SelectedMacroSlotName or (not State.MacroIsDraft and State.MacroName or nil))
        State.MacroDropdownPanel.Visible = true
        State.RenderMacroDropdown()
        setStatus("Macro list refreshed • " .. tostring(#State.MacroSlots) .. " saved", Theme.green)
    end)

    connect(State.MacroReRecordButton.Activated, function()
        if State.Recording or State.RecordingArmed or State.Playing then
            setStatus("Stop recording / playback first", Theme.amber); return
        end
        if State.MacroOverwriteArmed then
            local target = State.MacroOverwriteTargetName or State.MacroName
            State.MacroOverwriteArmed = false
            State.MacroOverwriteTargetName = nil
            State.MacroIsDraft = false
            State.SelectedMacroSlotName = target
            State.SelectMacroFile(target)
            State.UpdateMacroToolButtons()
            setStatus("Re-record cancelled • original macro restored", Theme.green)
            return
        end
        local target = State.SelectedMacroSlotName
        if type(target) ~= "string" or target == "" or State.MacroIsDraft then
            setStatus("Select a saved macro first", Theme.amber); return
        end
        if not State.SelectMacroFile(target) then
            setStatus("Could not load selected macro before re-record", Theme.red); return
        end
        State.MacroName = target
        State.MacroIsDraft = true
        State.MacroOverwriteArmed = true
        State.MacroOverwriteTargetName = target
        State.SelectedMacroSlotName = nil
        State.SelectedMacroSlotIndex = nil
        State.RefreshMacroSlotSelector(target)
        setStatus("RE-RECORD READY • " .. target .. " • START RECORDING, then STOP & SAVE", Theme.amber)
        State.UpdateMacroToolButtons()
    end)

    connect(State.MacroDeleteSelectedButton.Activated, function()
        if State.Recording or State.RecordingArmed or State.Playing then
            setStatus("Stop recording / playback before deleting", Theme.amber); return
        end
        local target = State.SelectedMacroSlotName
        if type(target) ~= "string" or target == "" or State.MacroIsDraft then
            setStatus("Select a saved macro first", Theme.amber); return
        end
        if State.MacroDeleteConfirmName ~= target or not State.MacroDeleteConfirmAt
            or os.clock() - State.MacroDeleteConfirmAt > 8 then
            State.MacroDeleteConfirmName = target
            State.MacroDeleteConfirmAt = os.clock()
            State.UpdateMacroToolButtons()
            setStatus("Click CONFIRM? within 8 seconds to delete " .. target, Theme.red)
            return
        end
        local path = macroPath(target)
        if type(delfile) ~= "function" then setStatus("Delta delfile API unavailable", Theme.red); return end
        local deleted, deleteError = pcall(delfile, path)
        if not deleted then setStatus("Delete failed: " .. tostring(deleteError), Theme.red); return end
        local remaining = {}
        for _, name in ipairs(State.ReadMacroSlotNames()) do
            if macroPath(name) ~= path then table.insert(remaining, name) end
        end
        local indexOk, indexError = pcall(function()
            State.EnsureMacroFolders()
            writefile(State.MacroIndexPath, HttpService:JSONEncode(remaining))
        end)
        State.MacroDeleteConfirmName = nil
        State.MacroDeleteConfirmAt = nil
        State.MacroSlots = remaining
        if State.MacroName == target then
            State.Placements = {}
            State.MacroIsDraft = false
            State.MacroOverwriteArmed = false
            State.MacroOverwriteTargetName = nil
            State.SelectedMacroSlotName = nil
            State.SelectedMacroSlotIndex = nil
            if remaining[1] then
                State.SelectMacroFile(remaining[1])
            else
                State.MacroName = "My GTD Strategy"
                State.RefreshMacroSlotSelector(nil)
                updateMacroCount()
            end
        else
            State.RefreshMacroSlotSelector(State.MacroName)
        end
        State.RenderMacroDropdown()
        State.UpdateMacroToolButtons()
        if indexOk then
            setStatus("Deleted macro: " .. target, Theme.green)
        else
            setStatus("Macro deleted, but index update failed: " .. tostring(indexError), Theme.amber)
        end
    end)
    State.UpdateMacroToolButtons()
end
]=]
    source = plainReplace(source, "-- Minimize, close, drag and page controls.", macroTools .. "\n-- Minimize, close, drag and page controls.", "integrated macro controls", 1)
end

local compile = loadstring or load
if type(compile) ~= "function" then error("GTD Control Hub v2.2.37: executor compiler unavailable") end
local compiled, runBase = pcall(compile, source)
if not compiled or type(runBase) ~= "function" then
    error("GTD Control Hub v2.2.37: patched source compile failed: " .. tostring(runBase))
end
runBase()
print("[GTD Control Hub v2.2.37] Playback session recovery, repeat generation and macro controls loaded.")
