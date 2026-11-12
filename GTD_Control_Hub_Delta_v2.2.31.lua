--[[
    GTD CONTROL HUB • DELTA v2.2.31 PATCH LOADER

    Adds a manual REFRESH button to the Macro Recorder tab and makes an
    unsaved macro draft visible in the dropdown. The full recorder/playback
    implementation is loaded from the existing, verified v2.2.30 source.

    Upload this file to the same GitHub repository as:
      GTD_Control_Hub_Delta_v2.2.31.lua

    Then use the v2.2.31 raw URL in Delta.
]]

local BASE_URL = "https://raw.githubusercontent.com/litvinovasez-eng/gtd-control-hub/main/GTD_Control_Hub_Delta_v2.2.30.lua"
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local fetched, source = pcall(function()
    return game:HttpGet(BASE_URL)
end)
if not fetched or type(source) ~= "string" or source == "" then
    error("GTD Control Hub v2.2.31: could not download the v2.2.30 base script: " .. tostring(source))
end

local compiler = loadstring or load
if type(compiler) ~= "function" then
    error("GTD Control Hub v2.2.31: loadstring is unavailable in this executor")
end

local compiled, runBase = pcall(compiler, source)
if not compiled or type(runBase) ~= "function" then
    error("GTD Control Hub v2.2.31: could not compile the base script: " .. tostring(runBase))
end
runBase()

-- Wait for the base UI to finish building before attaching the extra control.
local startedAt = os.clock()
local HUB, STATE, picker
repeat
    task.wait(0.1)
    HUB = ENV.__GTD_CONTROL_HUB
    STATE = type(HUB) == "table" and HUB.State or nil
    picker = type(STATE) == "table" and STATE.MacroPickerButton or nil
until (picker and picker.Parent) or os.clock() - startedAt >= 10

if not (picker and picker.Parent) then
    error("GTD Control Hub v2.2.31: Macro Recorder selector was not found")
end

-- Avoid leaving a duplicate refresh button if this patch is run again manually.
if STATE.MacroRefreshConnection then
    pcall(function() STATE.MacroRefreshConnection:Disconnect() end)
end
if STATE.MacroRefreshButton then
    pcall(function() STATE.MacroRefreshButton:Destroy() end)
end

picker.Size = UDim2.new(1, -108, 0, 27)

local refresh = Instance.new("TextButton")
refresh.Name = "MacroRefreshButton"
refresh.Position = UDim2.new(1, -94, 0, 31)
refresh.Size = UDim2.fromOffset(80, 27)
refresh.BackgroundColor3 = Color3.fromRGB(43, 27, 69)
refresh.Text = "↻ REFRESH"
refresh.TextColor3 = Color3.fromRGB(72, 255, 166)
refresh.Font = Enum.Font.GothamBold
refresh.TextSize = 9
refresh.BorderSizePixel = 0
refresh.AutoButtonColor = true
refresh.ZIndex = picker.ZIndex
refresh.Parent = picker.Parent

local refreshCorner = Instance.new("UICorner")
refreshCorner.CornerRadius = UDim.new(0, 7)
refreshCorner.Parent = refresh

STATE.MacroRefreshButton = refresh

local function showDraftInList()
    local scroll = STATE.MacroDropdownScroll
    if not (STATE.MacroIsDraft and scroll) then
        return
    end

    -- RenderMacroDropdown clears and rebuilds this container, so insert exactly
    -- one draft row after each refresh instead of accumulating duplicates.
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
    draft.Parent = scroll

    local draftCorner = Instance.new("UICorner")
    draftCorner.CornerRadius = UDim.new(0, 6)
    draftCorner.Parent = draft
end

local function refreshMacroList()
    local ok, err = pcall(function()
        if type(STATE.EnsureMacroFolders) == "function" then
            STATE.EnsureMacroFolders()
        end

        local preferred = STATE.SelectedMacroSlotName
        if not preferred and not STATE.MacroIsDraft then
            preferred = STATE.MacroName
        end

        -- This re-reads index.json and, when supported by the executor,
        -- the JSON files in GTDControlHub/Macros.
        STATE.RefreshMacroSlotSelector(preferred)
        STATE.MacroDropdownPanel.Visible = true
        STATE.RenderMacroDropdown()
        showDraftInList()

        local count = #(STATE.MacroSlots or {})
        local message = "Macro list refreshed • " .. tostring(count) .. " saved"
        if STATE.MacroIsDraft then
            message = message .. " • draft is not saved yet"
        end
        if type(HUB.SetStatus) == "function" then
            HUB.SetStatus(message, Color3.fromRGB(72, 245, 153))
        end
    end)

    if not ok and type(HUB.SetStatus) == "function" then
        HUB.SetStatus("Refresh error: " .. tostring(err), Color3.fromRGB(255, 83, 126))
    end
end

STATE.MacroRefreshConnection = refresh.Activated:Connect(refreshMacroList)
if type(HUB.Connections) == "table" then
    table.insert(HUB.Connections, STATE.MacroRefreshConnection)
end

print("[GTD Control Hub v2.2.31] Refresh button attached to Macro Recorder.")
