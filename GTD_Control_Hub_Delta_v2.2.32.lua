--[[
    GTD CONTROL HUB • DELTA v2.2.32 PATCH LOADER

    Builds on the verified v2.2.31 macro-list refresh patch.
    Adds:
      • DELETE per saved macro (two-click confirmation).
      • RE-RECORD selected saved macro under the same name.
      • Existing macro is kept until STOP & SAVE writes the replacement.

    The main recorder/playback code remains in v2.2.30 and is loaded through v2.2.31.
]]

local BASE_URL = "https://raw.githubusercontent.com/litvinovasez-eng/gtd-control-hub/main/GTD_Control_Hub_Delta_v2.2.31.lua"
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local fetched, source = pcall(function()
    return game:HttpGet(BASE_URL)
end)
if not fetched or type(source) ~= "string" or source == "" then
    error("GTD Control Hub v2.2.32: could not download the v2.2.31 base script: " .. tostring(source))
end

local compiler = loadstring or load
if type(compiler) ~= "function" then
    error("GTD Control Hub v2.2.32: loadstring is unavailable in this executor")
end

local compiled, runBase = pcall(compiler, source)
if not compiled or type(runBase) ~= "function" then
    error("GTD Control Hub v2.2.32: could not compile the base script: " .. tostring(runBase))
end
runBase()

-- Wait for the existing hub and v2.2.31 refresh control to finish initializing.
local startedAt = os.clock()
local HUB, STATE, picker
repeat
    task.wait(0.1)
    HUB = ENV.__GTD_CONTROL_HUB
    STATE = type(HUB) == "table" and HUB.State or nil
    picker = type(STATE) == "table" and STATE.MacroPickerButton or nil
until (picker and picker.Parent and STATE.RefreshMacroButton) or os.clock() - startedAt >= 10

if not (picker and picker.Parent and STATE.RefreshMacroButton) then
    error("GTD Control Hub v2.2.32: Macro Recorder controls were not found")
end

local HttpService = game:GetService("HttpService")

local function macroPath(name)
    local safe = tostring(name or "Macro")
        :gsub("[^%w%-%_ ]", "_")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    if safe == "" then safe = "Macro" end
    return "GTDControlHub/Macros/" .. safe .. ".json"
end

local function setStatus(message, color)
    if type(HUB.SetStatus) == "function" then
        HUB.SetStatus(message, color)
    end
end

local function isBusy()
    return STATE.Recording == true
        or STATE.RecordingArmed == true
        or STATE.Playing == true
end

-- Place the overwrite control in the free space beside the action counter.
local macroCard = picker.Parent
local countLabel
for _, child in ipairs(macroCard:GetChildren()) do
    if child:IsA("TextLabel") and string.find(string.lower(child.Text or ""), "actions", 1, true) then
        countLabel = child
        break
    end
end
if countLabel then
    countLabel.Size = UDim2.new(1, -108, 0, 18)
end

if STATE.MacroOverwriteButton then
    pcall(function() STATE.MacroOverwriteButton:Destroy() end)
end

local overwriteButton = Instance.new("TextButton")
overwriteButton.Name = "MacroOverwriteButton"
overwriteButton.Position = UDim2.new(1, -94, 0, 91)
overwriteButton.Size = UDim2.fromOffset(80, 23)
overwriteButton.BackgroundColor3 = Color3.fromRGB(83, 53, 30)
overwriteButton.Text = "RE-RECORD"
overwriteButton.TextColor3 = Color3.fromRGB(255, 210, 128)
overwriteButton.Font = Enum.Font.GothamBold
overwriteButton.TextSize = 8
overwriteButton.BorderSizePixel = 0
overwriteButton.AutoButtonColor = true
overwriteButton.Visible = false
overwriteButton.Parent = macroCard
local overwriteCorner = Instance.new("UICorner")
overwriteCorner.CornerRadius = UDim.new(0, 7)
overwriteCorner.Parent = overwriteButton
STATE.MacroOverwriteButton = overwriteButton

local function updateOverwriteButton()
    if not overwriteButton.Parent then return end

    if STATE.MacroOverwriteArmed and not isBusy() then
        overwriteButton.Visible = true
        overwriteButton.Text = "CANCEL"
        overwriteButton.BackgroundColor3 = Color3.fromRGB(75, 35, 48)
        overwriteButton.TextColor3 = Color3.fromRGB(255, 135, 155)
    elseif not STATE.MacroIsDraft
        and STATE.SelectedMacroSlotName
        and STATE.MacroName
        and macroPath(STATE.SelectedMacroSlotName) == macroPath(STATE.MacroName)
        and not isBusy() then
        overwriteButton.Visible = true
        overwriteButton.Text = "RE-RECORD"
        overwriteButton.BackgroundColor3 = Color3.fromRGB(83, 53, 30)
        overwriteButton.TextColor3 = Color3.fromRGB(255, 210, 128)
    else
        overwriteButton.Visible = false
    end

    if countLabel and STATE.MacroOverwriteArmed then
        countLabel.Text = tostring(#(STATE.Placements or {})) .. " actions  •  overwrite armed"
    end
end

-- Wrap the selector refresh so the overwrite control always reflects the active slot.
local originalRefreshSelector = STATE.RefreshMacroSlotSelector
STATE.RefreshMacroSlotSelector = function(...)
    local result = originalRefreshSelector(...)
    if not STATE.MacroIsDraft then
        STATE.MacroOverwriteArmed = false
        STATE.MacroOverwriteTargetName = nil
    end
    updateOverwriteButton()
    return result
end

-- Arm overwrite explicitly. The original file is untouched until STOP & SAVE.
local overwriteConnection = overwriteButton.Activated:Connect(function()
    if isBusy() then
        setStatus("Stop recording / playback before changing the macro", Color3.fromRGB(255, 199, 107))
        return
    end

    if STATE.MacroOverwriteArmed then
        local target = STATE.MacroOverwriteTargetName or STATE.MacroName
        STATE.MacroOverwriteArmed = false
        STATE.MacroOverwriteTargetName = nil
        STATE.MacroIsDraft = false
        STATE.SelectedMacroSlotName = target
        STATE.RefreshMacroSlotSelector(target)
        setStatus("Overwrite cancelled • the saved macro is unchanged", Color3.fromRGB(72, 245, 153))
        return
    end

    local target = STATE.SelectedMacroSlotName
    if not target or STATE.MacroIsDraft or macroPath(target) ~= macroPath(STATE.MacroName) then
        setStatus("Select a saved macro first", Color3.fromRGB(255, 199, 107))
        return
    end

    local path = macroPath(target)
    if type(isfile) == "function" and not isfile(path) then
        setStatus("Saved macro file is missing • refresh the list", Color3.fromRGB(255, 83, 126))
        return
    end

    STATE.MacroName = target
    STATE.MacroOverwriteArmed = true
    STATE.MacroOverwriteTargetName = target
    STATE.MacroIsDraft = true
    STATE.SelectedMacroSlotName = nil
    STATE.SelectedMacroSlotIndex = nil
    STATE.RefreshMacroSlotSelector(target)
    STATE.MacroDropdownPanel.Visible = false
    setStatus(
        "RE-RECORD ARMED: " .. target .. " • old file stays safe until STOP & SAVE",
        Color3.fromRGB(255, 199, 107)
    )
    updateOverwriteButton()
end)

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
    local exists = false
    if type(isfile) == "function" then
        local checkOk, result = pcall(isfile, targetPath)
        exists = checkOk and result == true
    end

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
        if type(isfile) == "function" and isfile(targetPath) then
            setStatus("Delete was requested, but the macro file still exists", Color3.fromRGB(255, 83, 126))
            return false
        end
    end

    -- Remove the deleted name from index.json as well as from the actual JSON file.
    local allNames = {}
    if type(STATE.ReadMacroSlotNames) == "function" then
        local readOk, names = pcall(STATE.ReadMacroSlotNames)
        if readOk and type(names) == "table" then allNames = names end
    end
    local remaining = {}
    for _, savedName in ipairs(allNames) do
        if macroPath(savedName) ~= targetPath then
            remaining[#remaining + 1] = savedName
        end
    end

    local indexWritten, indexError = pcall(function()
        if type(writefile) ~= "function" then error("writefile is unavailable") end
        if type(STATE.EnsureMacroFolders) == "function" then STATE.EnsureMacroFolders() end
        writefile(STATE.MacroIndexPath, HttpService:JSONEncode(remaining))
    end)

    local wasCurrent = STATE.MacroName and macroPath(STATE.MacroName) == targetPath
    STATE.PendingDeleteMacroName = nil
    STATE.PendingDeleteMacroAt = nil

    if wasCurrent then
        STATE.MacroIsDraft = false
        STATE.MacroOverwriteArmed = false
        STATE.MacroOverwriteTargetName = nil
        STATE.SelectedMacroSlotName = nil
        STATE.SelectedMacroSlotIndex = nil
        STATE.Placements = {}
        STATE.MacroName = remaining[1] or "My GTD Strategy"

        if remaining[1] and type(STATE.SelectMacroFile) == "function" then
            STATE.SelectMacroFile(remaining[1])
        else
            STATE.RefreshMacroSlotSelector(nil)
        end
    else
        STATE.MacroSlots = remaining
        STATE.RefreshMacroSlotSelector(STATE.MacroName)
    end

    STATE.MacroDropdownPanel.Visible = true
    STATE.RenderMacroDropdown()
    updateOverwriteButton()

    if indexWritten then
        setStatus("Deleted macro: " .. tostring(name), Color3.fromRGB(72, 245, 153))
    else
        setStatus(
            "Macro file deleted, but index update failed: " .. tostring(indexError),
            Color3.fromRGB(255, 199, 107)
        )
    end
    return true
end

-- Wrap dropdown rendering and turn every saved option into a row with a DEL control.
local originalRenderDropdown = STATE.RenderMacroDropdown
STATE.MacroDeleteConnections = STATE.MacroDeleteConnections or {}
STATE.RenderMacroDropdown = function(...)
    originalRenderDropdown(...)

    local scroll = STATE.MacroDropdownScroll
    if not scroll then return end
    for index, name in ipairs(STATE.MacroSlots or {}) do
        local option = scroll:FindFirstChild("MacroOption_" .. tostring(index))
        if option and option:IsA("TextButton") then
            local row = Instance.new("Frame")
            row.Name = "MacroRow_" .. tostring(index)
            row.Size = UDim2.new(1, -6, 0, 25)
            row.BackgroundTransparency = 1
            row.BorderSizePixel = 0
            row.LayoutOrder = index
            row.ZIndex = 82
            row.Parent = scroll

            option.Parent = row
            option.Position = UDim2.fromOffset(0, 0)
            option.Size = UDim2.new(1, -43, 1, 0)
            option.ZIndex = 83

            local deleteButton = Instance.new("TextButton")
            deleteButton.Name = "DeleteMacroButton_" .. tostring(index)
            deleteButton.Position = UDim2.new(1, -39, 0, 0)
            deleteButton.Size = UDim2.fromOffset(39, 25)
            deleteButton.BackgroundColor3 = Color3.fromRGB(75, 30, 48)
            deleteButton.Text = STATE.PendingDeleteMacroName == name and "SURE?" or "DEL"
            deleteButton.TextColor3 = Color3.fromRGB(255, 125, 150)
            deleteButton.Font = Enum.Font.GothamBold
            deleteButton.TextSize = 8
            deleteButton.BorderSizePixel = 0
            deleteButton.AutoButtonColor = true
            deleteButton.ZIndex = 84
            deleteButton.Parent = row
            local deleteCorner = Instance.new("UICorner")
            deleteCorner.CornerRadius = UDim.new(0, 6)
            deleteCorner.Parent = deleteButton

            local connection = deleteButton.Activated:Connect(function()
                if isBusy() then
                    setStatus("Stop recording / playback before deleting a macro", Color3.fromRGB(255, 199, 107))
                    return
                end
                if STATE.PendingDeleteMacroName == name
                    and STATE.PendingDeleteMacroAt
                    and os.clock() - STATE.PendingDeleteMacroAt <= 8 then
                    deleteSavedMacro(name)
                else
                    STATE.PendingDeleteMacroName = name
                    STATE.PendingDeleteMacroAt = os.clock()
                    deleteButton.Text = "SURE?"
                    setStatus("Click SURE? again within 8 seconds to delete: " .. tostring(name), Color3.fromRGB(255, 125, 150))
                end
            end)
            table.insert(STATE.MacroDropdownConnections, connection)
        end
    end
end

-- Initial refresh also applies the per-row delete controls.
STATE.RefreshMacroSlotSelector(STATE.SelectedMacroSlotName or (not STATE.MacroIsDraft and STATE.MacroName or nil))
if STATE.MacroDropdownPanel then
    STATE.MacroDropdownPanel.Visible = false
end
updateOverwriteButton()

-- Track the overwrite button's connection in the hub's cleanup list.
if type(HUB.Connections) == "table" then
    table.insert(HUB.Connections, overwriteConnection)
end

print("[GTD Control Hub v2.2.32] Delete saved macros + same-name re-record enabled.")
