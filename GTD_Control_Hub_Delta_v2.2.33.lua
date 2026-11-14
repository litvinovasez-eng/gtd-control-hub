--[[
    GTD CONTROL HUB • DELTA v2.2.33 PATCH LOADER

    Builds on v2.2.32 and adds per-saved-macro actions:
      • LOAD
      • RE-RECORD (loads that exact JSON, then records back to the same filename)
      • DEL (the existing two-click delete remains)

    The prior saved file is not deleted when re-record starts. It is replaced only
    by the base recorder's normal STOP & SAVE call. CANCEL reloads the untouched file.
]]

local BASE_URL = "https://raw.githubusercontent.com/litvinovasez-eng/gtd-control-hub/main/GTD_Control_Hub_Delta_v2.2.32.lua"
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local fetched, source = pcall(function()
    return game:HttpGet(BASE_URL)
end)
if not fetched or type(source) ~= "string" or source == "" then
    error("GTD Control Hub v2.2.33: failed to download v2.2.32: " .. tostring(source))
end

local compiler = loadstring or load
if type(compiler) ~= "function" then
    error("GTD Control Hub v2.2.33: loadstring is unavailable")
end
local compiled, runBase = pcall(compiler, source)
if not compiled or type(runBase) ~= "function" then
    error("GTD Control Hub v2.2.33: base compile failed: " .. tostring(runBase))
end
runBase()

local startedAt = os.clock()
local HUB, STATE
repeat
    task.wait(0.1)
    HUB = ENV.__GTD_CONTROL_HUB
    STATE = type(HUB) == "table" and HUB.State or nil
until (type(STATE) == "table"
    and STATE.MacroPickerButton
    and STATE.RenderMacroDropdown
    and STATE.SelectMacroFile
    and STATE.MacroOverwriteButton)
    or os.clock() - startedAt >= 10

if type(STATE) ~= "table" or not STATE.RenderMacroDropdown or not STATE.SelectMacroFile then
    error("GTD Control Hub v2.2.33: Macro Recorder did not initialize")
end

local function setStatus(message, color)
    if type(HUB.SetStatus) == "function" then HUB.SetStatus(message, color) end
end

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

local function updateActionState()
    local cancel = STATE.MacroCancelOverwriteButton
    if cancel and cancel.Parent then
        cancel.Visible = STATE.MacroOverwriteArmed == true and not isBusy()
    end
    local legacy = STATE.MacroOverwriteButton
    if legacy and legacy.Parent then
        -- The previous global button has a stale callback attached by v2.2.32.
        -- Hide it; the per-row action below is the single supported entry point.
        legacy.Visible = false
    end
end

local originalRefresh = STATE.RefreshMacroSlotSelector
STATE.RefreshMacroSlotSelector = function(...)
    local result = originalRefresh(...)
    updateActionState()
    return result
end

local function armOverwrite(name)
    if isBusy() then
        setStatus("Stop recording / playback before re-recording a macro", Color3.fromRGB(255, 199, 107))
        return false
    end
    if STATE.MacroOverwriteArmed then
        setStatus("A re-record is already armed • cancel it first", Color3.fromRGB(255, 199, 107))
        return false
    end
    if STATE.MacroIsDraft and #(STATE.Placements or {}) > 0 then
        setStatus("Save or cancel the current draft before switching macros", Color3.fromRGB(255, 199, 107))
        return false
    end
    if not savedFileExists(name) then
        setStatus("Macro file not found: " .. tostring(name), Color3.fromRGB(255, 83, 126))
        return false
    end

    -- Always load the chosen file first. This synchronizes MacroName, SelectedMacroSlotName,
    -- map metadata and its recorded action list before entering overwrite mode.
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
    updateActionState()
    setStatus(
        "RE-RECORD READY: " .. name .. " • press START RECORDING; STOP & SAVE replaces this same file",
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
    -- Clear draft/armed flags before SelectMacroFile so its draft-loss guard does not
    -- reject reloading the original file after a cancelled or aborted recording.
    STATE.MacroOverwriteArmed = false
    STATE.MacroOverwriteTargetName = nil
    STATE.MacroIsDraft = false
    STATE.SelectedMacroSlotName = target
    STATE.SelectedMacroSlotIndex = nil

    local loaded = STATE.SelectMacroFile(target)
    if loaded then
        setStatus("Re-record cancelled • original macro restored: " .. target, Color3.fromRGB(72, 245, 153))
    else
        setStatus("Cancelled overwrite, but could not reload original macro: " .. target, Color3.fromRGB(255, 83, 126))
    end
    updateActionState()
end

-- Replace the stale, global-only overwrite control with an explicit CANCEL control.
local card = STATE.MacroPickerButton.Parent
if STATE.MacroCancelOverwriteButton then
    pcall(function() STATE.MacroCancelOverwriteButton:Destroy() end)
end
local cancelButton = Instance.new("TextButton")
cancelButton.Name = "MacroCancelOverwriteButton"
cancelButton.Position = UDim2.new(1, -94, 0, 91)
cancelButton.Size = UDim2.fromOffset(80, 23)
cancelButton.BackgroundColor3 = Color3.fromRGB(75, 35, 48)
cancelButton.Text = "CANCEL"
cancelButton.TextColor3 = Color3.fromRGB(255, 135, 155)
cancelButton.Font = Enum.Font.GothamBold
cancelButton.TextSize = 8
cancelButton.BorderSizePixel = 0
cancelButton.Visible = false
cancelButton.Parent = card
local cancelCorner = Instance.new("UICorner")
cancelCorner.CornerRadius = UDim.new(0, 7)
cancelCorner.Parent = cancelButton
STATE.MacroCancelOverwriteButton = cancelButton
local cancelConnection = cancelButton.Activated:Connect(cancelOverwrite)
if type(HUB.Connections) == "table" then table.insert(HUB.Connections, cancelConnection) end

-- Render each saved macro as: LOAD | RE-RECORD | DEL.
local previousRender = STATE.RenderMacroDropdown
STATE.RenderMacroDropdown = function(...)
    previousRender(...)
    local scroll = STATE.MacroDropdownScroll
    if not scroll then return end

    for index, name in ipairs(STATE.MacroSlots or {}) do
        local row = scroll:FindFirstChild("MacroRow_" .. tostring(index))
        local option = row and row:FindFirstChild("MacroOption_" .. tostring(index))
        local deleteButton = row and row:FindFirstChild("DeleteMacroButton_" .. tostring(index))
        if row and option and option:IsA("TextButton") then
            option.Position = UDim2.fromOffset(0, 0)
            option.Size = UDim2.new(1, -126, 1, 0)
            option.TextTruncate = Enum.TextTruncate.AtEnd

            if deleteButton and deleteButton:IsA("TextButton") then
                deleteButton.Position = UDim2.new(1, -39, 0, 0)
                deleteButton.Size = UDim2.fromOffset(39, 25)
            end

            local previousButton = row:FindFirstChild("ReRecordMacroButton_" .. tostring(index))
            if previousButton then previousButton:Destroy() end

            local reRecord = Instance.new("TextButton")
            reRecord.Name = "ReRecordMacroButton_" .. tostring(index)
            reRecord.Position = UDim2.new(1, -123, 0, 0)
            reRecord.Size = UDim2.fromOffset(80, 25)
            reRecord.BackgroundColor3 = Color3.fromRGB(83, 53, 30)
            reRecord.Text = "RE-RECORD"
            reRecord.TextColor3 = Color3.fromRGB(255, 210, 128)
            reRecord.Font = Enum.Font.GothamBold
            reRecord.TextSize = 8
            reRecord.BorderSizePixel = 0
            reRecord.AutoButtonColor = true
            reRecord.ZIndex = 84
            reRecord.Parent = row
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = reRecord

            local connection = reRecord.Activated:Connect(function()
                armOverwrite(name)
            end)
            STATE.MacroDropdownConnections = STATE.MacroDropdownConnections or {}
            table.insert(STATE.MacroDropdownConnections, connection)
        end
    end
end

-- Hide legacy button, but retain the base selector and delete logic from v2.2.32.
updateActionState()
print("[GTD Control Hub v2.2.33] Per-row RE-RECORD now loads the chosen macro before same-name save.")
