--[[
    GTD CONTROL HUB • DELTA v2.2.36 PATCH LOADER

    Builds on v2.2.30 with a match-cycle detector fix, restores REFRESH,
    and keeps the persistent controls on the Macro Recorder card:
      • RE-RECORD: load the selected saved macro, then arm recording to the
        same filename. The old file remains until STOP & SAVE.
      • DELETE: two-click confirmation, removes the selected JSON and its
        entry from index.json.
      • CANCEL: the RE-RECORD button becomes CANCEL while overwrite is armed.

    Unlike v2.2.33, the controls are visible on the main Macro Recorder card;
    they do not depend on opening the dropdown to discover them.
]]

local BASE_URL = "https://raw.githubusercontent.com/litvinovasez-eng/gtd-control-hub/main/GTD_Control_Hub_Delta_v2.2.30.lua"
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local fetched, source = pcall(function()
    return game:HttpGet(BASE_URL)
end)
if not fetched or type(source) ~= "string" or source == "" then
    error("GTD Control Hub v2.2.36: failed to download base v2.2.30: " .. tostring(source))
end

-- v2.2.30 identified a match only by Context path + GameStartTime. Some GTD
-- restarts reuse both values, so the playback worker sees the next match as the
-- already-played one and waits forever. Give every observed live-match transition
-- a monotonically increasing cycle id, without changing the placement timeline.
local oldLoopHead = [==[
local function runAutomation()
    while Gui.Parent do
        task.wait(0.10)
        local context = getActiveContext()
        local roundKey = getRoundKey(context)
        local liveRound = isInLiveRound(context)
        State.ActiveContext = context
]==]
local newLoopHead = [==[
local function runAutomation()
    local lastObservedLiveRound = false
    local lastObservedBaseRoundKey = nil
    local matchCycle = 0

    while Gui.Parent do
        task.wait(0.10)
        local context = getActiveContext()
        local baseRoundKey = getRoundKey(context)
        local liveRound = isInLiveRound(context)

        -- Count a new match when a live round starts again, even if GTD reuses
        -- the same Context name and GameStartTime. Also preserve the original
        -- behavior when the base key itself changes while still live.
        local newMatch = liveRound and (
            not lastObservedLiveRound or baseRoundKey ~= lastObservedBaseRoundKey
        )
        if newMatch then
            matchCycle = matchCycle + 1
            print("[GTD Macro Loop] Detected live match cycle " .. tostring(matchCycle)
                .. " • " .. tostring(baseRoundKey))
        end

        lastObservedLiveRound = liveRound
        lastObservedBaseRoundKey = baseRoundKey
        local roundKey = tostring(baseRoundKey) .. ":cycle=" .. tostring(matchCycle)
        State.MatchCycle = matchCycle
        State.ActiveContext = context
]==]

local function replaceExactlyOnce(haystack, needle, replacement, label)
    local first, last = string.find(haystack, needle, 1, true)
    if not first then
        error("GTD Control Hub v2.2.36: source patch target not found: " .. label)
    end
    local second = string.find(haystack, needle, last + 1, true)
    if second then
        error("GTD Control Hub v2.2.36: source patch target is ambiguous: " .. label)
    end
    return string.sub(haystack, 1, first - 1) .. replacement .. string.sub(haystack, last + 1)
end

source = replaceExactlyOnce(source, oldLoopHead, newLoopHead, "runAutomation match-cycle detector")

local compiler = loadstring or load
if type(compiler) ~= "function" then
    error("GTD Control Hub v2.2.36: loadstring is unavailable")
end
local compiled, runBase = pcall(compiler, source)
if not compiled or type(runBase) ~= "function" then
    error("GTD Control Hub v2.2.36: patched base compile failed: " .. tostring(runBase))
end
runBase()

-- Wait for the base UI and v2.2.31 refresh control.
local startedAt = os.clock()
local HUB, STATE
repeat
    task.wait(0.1)
    HUB = ENV.__GTD_CONTROL_HUB
    STATE = type(HUB) == "table" and HUB.State or nil
until (type(STATE) == "table"
    and STATE.MacroPickerButton and STATE.MacroPickerButton.Parent
    and STATE.MacroDropdownPanel
    and STATE.RefreshMacroSlotSelector
    and STATE.SelectMacroFile)
    or os.clock() - startedAt >= 12

if type(STATE) ~= "table" or not STATE.MacroPickerButton or not STATE.MacroPickerButton.Parent then
    error("GTD Control Hub v2.2.36: Macro Recorder controls were not found")
end

local HttpService = game:GetService("HttpService")
local card = STATE.MacroPickerButton.Parent

local function setStatus(message, color)
    if type(HUB.SetStatus) == "function" then
        HUB.SetStatus(message, color)
    end
end

-- Preserve v2.2.31's manual macro-list refresh control.
if STATE.MacroRefreshButton then pcall(function() STATE.MacroRefreshButton:Destroy() end) end
STATE.MacroPickerButton.Size = UDim2.new(1, -108, 0, 27)
local refreshButton = Instance.new("TextButton")
refreshButton.Name = "MacroRefreshButton"
refreshButton.Position = UDim2.new(1, -94, 0, 31)
refreshButton.Size = UDim2.fromOffset(80, 27)
refreshButton.BackgroundColor3 = Color3.fromRGB(43, 27, 69)
refreshButton.Text = "↻ REFRESH"
refreshButton.TextColor3 = Color3.fromRGB(72, 255, 166)
refreshButton.Font = Enum.Font.GothamBold
refreshButton.TextSize = 9
refreshButton.BorderSizePixel = 0
refreshButton.AutoButtonColor = true
refreshButton.Parent = card
local refreshCorner = Instance.new("UICorner")
refreshCorner.CornerRadius = UDim.new(0, 7)
refreshCorner.Parent = refreshButton
STATE.MacroRefreshButton = refreshButton
local refreshConnection = refreshButton.Activated:Connect(function()
    local ok, err = pcall(function()
        if type(STATE.EnsureMacroFolders) == "function" then STATE.EnsureMacroFolders() end
        local preferred = STATE.SelectedMacroSlotName
        if not preferred and not STATE.MacroIsDraft then preferred = STATE.MacroName end
        STATE.RefreshMacroSlotSelector(preferred)
        STATE.MacroDropdownPanel.Visible = true
        STATE.RenderMacroDropdown()
        if STATE.MacroIsDraft and STATE.MacroDropdownScroll then
            local draft = Instance.new("TextLabel")
            draft.Name = "CurrentMacroDraft"
            draft.Size = UDim2.new(1, -6, 0, 32)
            draft.BackgroundColor3 = Color3.fromRGB(43, 27, 69)
            draft.BackgroundTransparency = 0.08
            draft.Text = "✎ DRAFT: " .. tostring(STATE.MacroName) .. " • NOT SAVED"
            draft.TextColor3 = Color3.fromRGB(72, 255, 166)
            draft.Font = Enum.Font.GothamBold
            draft.TextSize = 9
            draft.TextWrapped = true
            draft.TextXAlignment = Enum.TextXAlignment.Left
            draft.BorderSizePixel = 0
            draft.LayoutOrder = 0
            draft.ZIndex = 82
            draft.Parent = STATE.MacroDropdownScroll
        end
        setStatus("Macro list refreshed • " .. tostring(#(STATE.MacroSlots or {})) .. " saved",
            Color3.fromRGB(72, 245, 153))
    end)
    if not ok then setStatus("Refresh error: " .. tostring(err), Color3.fromRGB(255, 83, 126)) end
end)
if type(HUB.Connections) == "table" then table.insert(HUB.Connections, refreshConnection) end


local function macroPath(name)
    local safe = tostring(name or "Macro")
        :gsub("[^%w%-%_ ]", "_")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    if safe == "" then safe = "Macro" end
    return "GTDControlHub/Macros/" .. safe .. ".json"
end

local function isBusy()
    return STATE.Recording == true
        or STATE.RecordingArmed == true
        or STATE.Playing == true
end

local function savedFileExists(name)
    local path = macroPath(name)
    if type(isfile) == "function" then
        local ok, result = pcall(isfile, path)
        if ok then return result == true end
    end
    if type(readfile) == "function" then
        local ok = pcall(readfile, path)
        return ok
    end
    return false
end

local function getSelectedSavedMacro()
    if STATE.MacroIsDraft then return nil end
    local selected = STATE.SelectedMacroSlotName
    if type(selected) ~= "string" or selected == "" then return nil end
    if not STATE.MacroName or macroPath(selected) ~= macroPath(STATE.MacroName) then
        return nil
    end
    if not savedFileExists(selected) then return nil end
    return selected
end

-- Find the existing action counter so the two persistent buttons have room.
local countLabel
for _, child in ipairs(card:GetChildren()) do
    if child:IsA("TextLabel") then
        local lower = string.lower(child.Text or "")
        if string.find(lower, "actions", 1, true) or string.find(lower, "macro selected", 1, true) then
            countLabel = child
            break
        end
    end
end
if countLabel then
    countLabel.Position = UDim2.fromOffset(14, 94)
    countLabel.Size = UDim2.new(1, -190, 0, 16)
    countLabel.TextTruncate = Enum.TextTruncate.AtEnd
end

-- Remove controls from a previous execution of this same patch without touching
-- the base selector or REFRESH button.
for _, name in ipairs({"MacroReRecordButton", "MacroDeleteSelectedButton"}) do
    local old = card:FindFirstChild(name)
    if old then pcall(function() old:Destroy() end) end
end

local function makeActionButton(name, position, textValue, bg, fg)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = position
    button.Size = UDim2.fromOffset(80, 23)
    button.BackgroundColor3 = bg
    button.Text = textValue
    button.TextColor3 = fg
    button.Font = Enum.Font.GothamBold
    button.TextSize = 8
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Active = true
    button.Visible = true
    button.ZIndex = 5
    button.Parent = card
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = button
    return button
end

local reRecordButton = makeActionButton(
    "MacroReRecordButton",
    UDim2.new(1, -184, 0, 91),
    "RE-RECORD",
    Color3.fromRGB(57, 43, 30),
    Color3.fromRGB(160, 140, 110)
)
local deleteButton = makeActionButton(
    "MacroDeleteSelectedButton",
    UDim2.new(1, -96, 0, 91),
    "DELETE",
    Color3.fromRGB(48, 34, 42),
    Color3.fromRGB(150, 115, 125)
)

local pendingDeleteName = nil
local pendingDeleteAt = nil

local function updateActionButtons()
    if not reRecordButton.Parent or not deleteButton.Parent then return end

    if STATE.MacroOverwriteArmed then
        reRecordButton.Text = "CANCEL"
        reRecordButton.BackgroundColor3 = Color3.fromRGB(75, 35, 48)
        reRecordButton.TextColor3 = Color3.fromRGB(255, 135, 155)
        reRecordButton.Active = true
        reRecordButton.AutoButtonColor = true
        deleteButton.Active = false
        deleteButton.AutoButtonColor = false
        deleteButton.BackgroundColor3 = Color3.fromRGB(40, 31, 37)
        deleteButton.TextColor3 = Color3.fromRGB(115, 95, 105)
        deleteButton.Text = "DELETE"
        return
    end

    local selected = getSelectedSavedMacro()
    if selected then
        reRecordButton.Text = "RE-RECORD"
        reRecordButton.BackgroundColor3 = Color3.fromRGB(83, 53, 30)
        reRecordButton.TextColor3 = Color3.fromRGB(255, 210, 128)
        reRecordButton.Active = true
        reRecordButton.AutoButtonColor = true

        deleteButton.Text = (pendingDeleteName == selected) and "CONFIRM?" or "DELETE"
        deleteButton.BackgroundColor3 = (pendingDeleteName == selected)
            and Color3.fromRGB(100, 30, 48) or Color3.fromRGB(75, 30, 48)
        deleteButton.TextColor3 = Color3.fromRGB(255, 125, 150)
        deleteButton.Active = true
        deleteButton.AutoButtonColor = true
    else
        -- Keep both controls visually obvious even before a macro is selected.
        -- The handlers explain the required selection instead of hiding the buttons.
        reRecordButton.Text = "RE-RECORD"
        reRecordButton.BackgroundColor3 = Color3.fromRGB(83, 53, 30)
        reRecordButton.TextColor3 = Color3.fromRGB(255, 210, 128)
        reRecordButton.Active = not isBusy()
        reRecordButton.AutoButtonColor = not isBusy()

        deleteButton.Text = (pendingDeleteName ~= nil) and "CONFIRM?" or "DELETE"
        deleteButton.BackgroundColor3 = Color3.fromRGB(75, 30, 48)
        deleteButton.TextColor3 = Color3.fromRGB(255, 125, 150)
        deleteButton.Active = not isBusy()
        deleteButton.AutoButtonColor = not isBusy()
        if pendingDeleteName ~= nil then
            local stillSelected = getSelectedSavedMacro()
            if stillSelected ~= pendingDeleteName then
                pendingDeleteName = nil
                pendingDeleteAt = nil
                deleteButton.Text = "DELETE"
            end
        end
    end
end

-- Keep buttons synchronized whenever the base code changes or refreshes selection.
local originalRefresh = STATE.RefreshMacroSlotSelector
STATE.RefreshMacroSlotSelector = function(...)
    local result = originalRefresh(...)
    if not STATE.MacroIsDraft then
        STATE.MacroOverwriteArmed = false
        STATE.MacroOverwriteTargetName = nil
    end
    updateActionButtons()
    return result
end

local function armOverwrite(name)
    if isBusy() then
        setStatus("Stop recording / playback before re-recording a macro", Color3.fromRGB(255, 199, 107))
        return false
    end
    if STATE.MacroOverwriteArmed then
        setStatus("A re-record is already armed • press CANCEL only after stopping the recorder", Color3.fromRGB(255, 199, 107))
        return false
    end
    if STATE.MacroIsDraft and #(STATE.Placements or {}) > 0 then
        setStatus("Save or cancel the current draft before switching macros", Color3.fromRGB(255, 199, 107))
        return false
    end
    if not savedFileExists(name) then
        setStatus("Saved macro file not found: " .. tostring(name), Color3.fromRGB(255, 83, 126))
        return false
    end

    -- Load the exact selected JSON before enabling draft mode. This is critical:
    -- START RECORDING will then use the same filename, and STOP & SAVE replaces it.
    local loaded = STATE.SelectMacroFile(name)
    if loaded ~= true then
        setStatus("Could not load macro before re-recording: " .. tostring(name), Color3.fromRGB(255, 83, 126))
        return false
    end

    STATE.MacroName = name
    STATE.MacroIsDraft = true
    STATE.MacroOverwriteArmed = true
    STATE.MacroOverwriteTargetName = name
    STATE.SelectedMacroSlotName = nil
    STATE.SelectedMacroSlotIndex = nil
    if type(STATE.RefreshMacroSlotSelector) == "function" then
        STATE.RefreshMacroSlotSelector(name)
    end
    if STATE.MacroDropdownPanel then STATE.MacroDropdownPanel.Visible = false end
    updateActionButtons()
    setStatus(
        "RE-RECORD READY: " .. name .. " • press START RECORDING; STOP & SAVE overwrites this file",
        Color3.fromRGB(255, 199, 107)
    )
    return true
end

local function cancelOverwrite()
    if isBusy() then
        setStatus("Stop recording / playback before cancelling re-record", Color3.fromRGB(255, 199, 107))
        return
    end
    if not STATE.MacroOverwriteArmed then return end

    local target = STATE.MacroOverwriteTargetName or STATE.MacroName
    STATE.MacroOverwriteArmed = false
    STATE.MacroOverwriteTargetName = nil
    STATE.MacroIsDraft = false
    STATE.SelectedMacroSlotName = target
    STATE.SelectedMacroSlotIndex = nil

    local loaded = STATE.SelectMacroFile(target)
    if loaded then
        setStatus("Re-record cancelled • original saved macro restored: " .. target, Color3.fromRGB(72, 245, 153))
    else
        setStatus("Cancelled re-record, but could not reload saved macro: " .. target, Color3.fromRGB(255, 83, 126))
    end
    updateActionButtons()
end

local function deleteSavedMacro(name)
    if isBusy() then
        setStatus("Stop recording / playback before deleting a macro", Color3.fromRGB(255, 199, 107))
        return false
    end
    if STATE.MacroOverwriteArmed then
        setStatus("Cancel RE-RECORD mode before deleting a macro", Color3.fromRGB(255, 199, 107))
        return false
    end

    local targetPath = macroPath(name)
    local exists = savedFileExists(name)
    if exists then
        if type(delfile) ~= "function" then
            setStatus("This executor does not expose delfile; cannot delete macro", Color3.fromRGB(255, 83, 126))
            return false
        end
        local deleted, deleteError = pcall(delfile, targetPath)
        if not deleted then
            setStatus("Delete failed: " .. tostring(deleteError), Color3.fromRGB(255, 83, 126))
            return false
        end
        if type(isfile) == "function" then
            local checkOk, stillExists = pcall(isfile, targetPath)
            if checkOk and stillExists then
                setStatus("The macro file still exists after delete request", Color3.fromRGB(255, 83, 126))
                return false
            end
        end
    end

    local allNames = {}
    if type(STATE.ReadMacroSlotNames) == "function" then
        local ok, names = pcall(STATE.ReadMacroSlotNames)
        if ok and type(names) == "table" then allNames = names end
    end
    local remaining = {}
    for _, savedName in ipairs(allNames) do
        if macroPath(savedName) ~= targetPath then
            remaining[#remaining + 1] = savedName
        end
    end

    local indexOk, indexError = pcall(function()
        if type(writefile) ~= "function" then error("writefile is unavailable") end
        if type(STATE.EnsureMacroFolders) == "function" then STATE.EnsureMacroFolders() end
        writefile(STATE.MacroIndexPath, HttpService:JSONEncode(remaining))
    end)

    local wasCurrent = STATE.MacroName and macroPath(STATE.MacroName) == targetPath
    pendingDeleteName = nil
    pendingDeleteAt = nil
    STATE.MacroSlots = remaining

    if wasCurrent then
        STATE.MacroIsDraft = false
        STATE.MacroOverwriteArmed = false
        STATE.MacroOverwriteTargetName = nil
        STATE.SelectedMacroSlotName = nil
        STATE.SelectedMacroSlotIndex = nil
        STATE.Placements = {}
        if remaining[1] and type(STATE.SelectMacroFile) == "function" then
            STATE.SelectMacroFile(remaining[1])
        else
            STATE.MacroName = "My GTD Strategy"
            STATE.RefreshMacroSlotSelector(nil)
            if countLabel then countLabel.Text = "0 actions • no saved macro selected" end
        end
    else
        STATE.RefreshMacroSlotSelector(STATE.MacroName)
    end

    if STATE.MacroDropdownPanel and STATE.MacroDropdownPanel.Visible
        and type(STATE.RenderMacroDropdown) == "function" then
        STATE.RenderMacroDropdown()
    end
    updateActionButtons()

    if indexOk then
        setStatus("Deleted saved macro: " .. tostring(name), Color3.fromRGB(72, 245, 153))
    else
        setStatus(
            "Macro file deleted, but index.json update failed: " .. tostring(indexError),
            Color3.fromRGB(255, 199, 107)
        )
    end
    return true
end

local reRecordConnection = reRecordButton.Activated:Connect(function()
    if STATE.MacroOverwriteArmed then
        cancelOverwrite()
        return
    end
    local selected = getSelectedSavedMacro()
    if not selected then
        setStatus("Open SELECT MACRO and select a saved macro first", Color3.fromRGB(255, 199, 107))
        return
    end
    armOverwrite(selected)
end)

local deleteConnection = deleteButton.Activated:Connect(function()
    local selected = getSelectedSavedMacro()
    if not selected then
        setStatus("Select a saved macro before deleting", Color3.fromRGB(255, 199, 107))
        return
    end
    if isBusy() then
        setStatus("Stop recording / playback before deleting a macro", Color3.fromRGB(255, 199, 107))
        return
    end
    if pendingDeleteName == selected and pendingDeleteAt and os.clock() - pendingDeleteAt <= 8 then
        deleteSavedMacro(selected)
    else
        pendingDeleteName = selected
        pendingDeleteAt = os.clock()
        updateActionButtons()
        setStatus("Click CONFIRM? within 8 seconds to delete: " .. selected, Color3.fromRGB(255, 125, 150))
    end
end)

if type(HUB.Connections) == "table" then
    table.insert(HUB.Connections, reRecordConnection)
    table.insert(HUB.Connections, deleteConnection)
end

updateActionButtons()
STATE.MacroToolsVersion = "2.2.36"
STATE.MacroToolsCard = card
setStatus("Macro tools v2.2.36 attached • open Macro Recorder to use RE-RECORD / DELETE", Color3.fromRGB(72, 245, 153))
print("[GTD Control Hub v2.2.36] Controls created: "
    .. tostring(card:FindFirstChild("MacroReRecordButton") ~= nil) .. " / "
    .. tostring(card:FindFirstChild("MacroDeleteSelectedButton") ~= nil)
    .. " • card=" .. card:GetFullName())
