--[[
    GTD Control Hub — Delta prototype v0.3
    Standalone client-side UI automation prototype for Garden Tower Defense.

    Notes:
    - Does NOT download or execute remote code.
    - Uses visible in-game TextButtons where possible; labels may differ by game update.
    - Macro playback uses VirtualInputManager when exposed by the executor.
    - No game RemoteEvents are guessed or fired.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)
local LocalPlayer = Players.LocalPlayer

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if ENV.__GTD_CONTROL_HUB then
    pcall(function() ENV.__GTD_CONTROL_HUB:Destroy() end)
end

-- Use PlayerGui directly. The Delta smoke test confirmed it is visible;
-- gethui() can return a container that exists but does not render in some builds.
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local previousGui = PlayerGui:FindFirstChild("GTDControlHub_Delta")
if previousGui then
    pcall(function() previousGui:Destroy() end)
end

local State = {
    AutoSkip = false,
    AutoSpeed = false,
    AutoTargetFirst = false,
    AutoMode = false,
    AutoReplay = false,
    AutoClaim = false,
    Recording = false,
    Playing = false,
    LoopMacro = false,
    DesiredMap = "Dojo",
    DesiredMode = "Hard",
    Macro = {},
    Status = "Ready",
}

local lastAction = {}
local claimedButtons = setmetatable({}, { __mode = "k" })
local macroLastTime = 0
local stopPlayback = false
local speedDone = false
local modeDone = false
local lastTargetClick = 0
local lastSkipClick = 0
local lastReplayClick = 0
local lastClaimScan = 0

local function setStatus(message)
    State.Status = tostring(message)
    if ENV.__GTD_HUB_STATUS_LABEL then
        pcall(function() ENV.__GTD_HUB_STATUS_LABEL.Text = "Status: " .. State.Status end)
    end
end

local function safeCall(fn, ...)
    local args = { ... }
    local ok, result = pcall(function() return fn(table.unpack(args)) end)
    return ok, result
end

-- Parent the hub to PlayerGui, the same container verified by the Delta test.
local Gui = Instance.new("ScreenGui")
Gui.Name = "GTDControlHub_Delta"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.DisplayOrder = 999999
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Enabled = true
Gui.Parent = PlayerGui
ENV.__GTD_CONTROL_HUB = Gui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(390, 555)
Main.Position = UDim2.new(0, 25, 0.5, -277)
Main.BackgroundColor3 = Color3.fromRGB(22, 24, 31)
Main.BorderSizePixel = 0
Main.Parent = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(75, 83, 105)
MainStroke.Thickness = 1
MainStroke.Parent = Main

local Top = Instance.new("Frame")
Top.Size = UDim2.new(1, 0, 0, 42)
Top.BackgroundColor3 = Color3.fromRGB(32, 36, 47)
Top.BorderSizePixel = 0
Top.Parent = Main
Instance.new("UICorner", Top).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(12, 0)
Title.Size = UDim2.new(1, -92, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.Text = "GTD CONTROL HUB  •  DELTA"
Title.TextColor3 = Color3.fromRGB(240, 243, 255)
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Top

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(30, 28)
Close.Position = UDim2.new(1, -38, 0, 7)
Close.BackgroundColor3 = Color3.fromRGB(174, 61, 68)
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 20
Close.Parent = Top
Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 6)

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(30, 28)
Minimize.Position = UDim2.new(1, -73, 0, 7)
Minimize.BackgroundColor3 = Color3.fromRGB(65, 73, 94)
Minimize.Text = "—"
Minimize.TextColor3 = Color3.new(1, 1, 1)
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 16
Minimize.Parent = Top
Instance.new("UICorner", Minimize).CornerRadius = UDim.new(0, 6)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.BackgroundTransparency = 1
StatusLabel.Position = UDim2.fromOffset(13, 47)
StatusLabel.Size = UDim2.new(1, -26, 0, 22)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Status: Ready"
StatusLabel.TextColor3 = Color3.fromRGB(155, 202, 170)
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Main
ENV.__GTD_HUB_STATUS_LABEL = StatusLabel

local Scroll = Instance.new("ScrollingFrame")
Scroll.Name = "Controls"
Scroll.Position = UDim2.fromOffset(10, 73)
Scroll.Size = UDim2.new(1, -20, 1, -84)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 4
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.Parent = Main

local List = Instance.new("UIListLayout")
List.Padding = UDim.new(0, 7)
List.SortOrder = Enum.SortOrder.LayoutOrder
List.Parent = Scroll
List:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scroll.CanvasSize = UDim2.fromOffset(0, List.AbsoluteContentSize.Y + 10)
end)

local function addSection(text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -4, 0, 22)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Text = string.upper(text)
    label.TextColor3 = Color3.fromRGB(130, 169, 240)
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = Scroll
    return label
end

local function addButton(text, callback, height)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -4, 0, height or 34)
    button.BackgroundColor3 = Color3.fromRGB(43, 48, 62)
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Font = Enum.Font.GothamSemibold
    button.Text = text
    button.TextColor3 = Color3.fromRGB(235, 238, 248)
    button.TextSize = 12
    button.Parent = Scroll
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    button.Activated:Connect(callback)
    return button
end

local function addToggle(label, key)
    local button
    button = addButton("", function()
        State[key] = not State[key]
        button.Text = label .. ": " .. (State[key] and "ON" or "OFF")
        button.BackgroundColor3 = State[key] and Color3.fromRGB(46, 105, 79) or Color3.fromRGB(43, 48, 62)
        setStatus(label .. (State[key] and " enabled" or " disabled"))
    end)
    button.Text = label .. ": OFF"
    return button
end

local function addTextBox(label, defaultValue, onChanged)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -4, 0, 48)
    holder.BackgroundColor3 = Color3.fromRGB(35, 39, 51)
    holder.BorderSizePixel = 0
    holder.Parent = Scroll
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 7)

    local caption = Instance.new("TextLabel")
    caption.BackgroundTransparency = 1
    caption.Position = UDim2.fromOffset(9, 2)
    caption.Size = UDim2.new(1, -18, 0, 17)
    caption.Font = Enum.Font.Gotham
    caption.Text = label
    caption.TextColor3 = Color3.fromRGB(161, 168, 185)
    caption.TextSize = 10
    caption.TextXAlignment = Enum.TextXAlignment.Left
    caption.Parent = holder

    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(8, 21)
    box.Size = UDim2.new(1, -16, 0, 22)
    box.BackgroundColor3 = Color3.fromRGB(23, 26, 34)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.Text = defaultValue
    box.TextColor3 = Color3.fromRGB(245, 246, 250)
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = holder
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    box.FocusLost:Connect(function()
        onChanged(box.Text)
        setStatus(label .. " updated")
    end)
    return box
end

addSection("Match automation")
addToggle("Auto Skip Waves", "AutoSkip")
addToggle("Auto Speed (x3)", "AutoSpeed")
addToggle("Auto Target First", "AutoTargetFirst")
addToggle("Auto Select Map / Mode", "AutoMode")
addToggle("Auto Replay", "AutoReplay")
addToggle("Auto Claim Rewards", "AutoClaim")

addTextBox("Preferred map (visible button text)", State.DesiredMap, function(value)
    State.DesiredMap = value
    modeDone = false
end)
addTextBox("Preferred mode / difficulty (visible button text)", State.DesiredMode, function(value)
    State.DesiredMode = value
    modeDone = false
end)

addSection("Macro recorder")
local RecordButton = addButton("●  START RECORDING", function()
    if State.Playing then setStatus("Stop playback before recording") return end
    State.Macro = {}
    State.Recording = true
    macroLastTime = os.clock()
    RecordButton.Text = "●  RECORDING — PRESS STOP WHEN DONE"
    RecordButton.BackgroundColor3 = Color3.fromRGB(143, 60, 66)
    setStatus("Recording clicks and key presses")
end)
local StopRecordButton = addButton("■  STOP & SAVE MACRO", function()
    if not State.Recording then setStatus("Recorder is not running") return end
    State.Recording = false
    RecordButton.Text = "●  START RECORDING"
    RecordButton.BackgroundColor3 = Color3.fromRGB(43, 48, 62)

    local folder = "GTDControlHub"
    local path = folder .. "/macro.json"
    local saved = false
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and type(writefile) == "function" then
            if not isfolder(folder) then makefolder(folder) end
            writefile(path, HttpService:JSONEncode(State.Macro))
            saved = true
        end
    end)
    if saved then
        setStatus("Saved " .. #State.Macro .. " actions to " .. path)
    else
        setStatus("Recorded " .. #State.Macro .. " actions (memory only; file API unavailable)")
    end
end)
local PlayButton = addButton("▶  PLAY MACRO", function()
    if State.Recording then setStatus("Stop recording before playback") return end
    if State.Playing then setStatus("Macro is already playing") return end
    if #State.Macro == 0 then
        local loaded = false
        pcall(function()
            if type(isfile) == "function" and type(readfile) == "function" and isfile("GTDControlHub/macro.json") then
                State.Macro = HttpService:JSONDecode(readfile("GTDControlHub/macro.json"))
                loaded = true
            end
        end)
        if not loaded or #State.Macro == 0 then setStatus("No saved macro found") return end
    end
    if not VirtualInputManager then setStatus("VirtualInputManager unavailable in this Delta build") return end

    State.Playing = true
    stopPlayback = false
    setStatus("Playing macro (" .. #State.Macro .. " actions)")
    task.spawn(function()
        repeat
            for _, action in ipairs(State.Macro) do
                if stopPlayback then break end
                task.wait(math.clamp(tonumber(action.delay) or 0, 0, 8))
                if stopPlayback then break end
                pcall(function()
                    if action.kind == "mouse" then
                        local button = tonumber(action.button) or 0
                        VirtualInputManager:SendMouseButtonEvent(action.x, action.y, button, true, game, 0)
                        task.wait(0.045)
                        VirtualInputManager:SendMouseButtonEvent(action.x, action.y, button, false, game, 0)
                    elseif action.kind == "key" then
                        local keyCode = Enum.KeyCode[action.key]
                        if keyCode then
                            VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                            task.wait(0.045)
                            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
                        end
                    end
                end)
            end
        until stopPlayback or not State.LoopMacro
        State.Playing = false
        setStatus(stopPlayback and "Macro stopped" or "Macro finished")
    end)
end)
local StopPlayButton = addButton("■  STOP PLAYBACK", function()
    stopPlayback = true
    State.Playing = false
    setStatus("Stopping macro")
end)
addToggle("Loop Macro", "LoopMacro")

addSection("Utility")
addButton("↻  RELOAD SAVED MACRO", function()
    local ok, result = pcall(function()
        assert(type(isfile) == "function" and type(readfile) == "function", "file API unavailable")
        assert(isfile("GTDControlHub/macro.json"), "macro file not found")
        return HttpService:JSONDecode(readfile("GTDControlHub/macro.json"))
    end)
    if ok and type(result) == "table" then
        State.Macro = result
        setStatus("Loaded " .. #State.Macro .. " macro actions")
    else
        setStatus("Could not load macro: " .. tostring(result))
    end
end)
addButton("🧹  CLEAR MACRO", function()
    if State.Playing then stopPlayback = true end
    State.Macro = {}
    setStatus("Macro cleared from memory")
end)
addButton("Hide / Show panel: RightShift", function()
    Main.Visible = not Main.Visible
end)

-- Dragging the panel
local dragging, dragStart, startPos = false, nil, nil
Top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)
Top.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local minimized = false
Minimize.Activated:Connect(function()
    minimized = not minimized
    Scroll.Visible = not minimized
    StatusLabel.Visible = not minimized
    Main.Size = minimized and UDim2.fromOffset(390, 42) or UDim2.fromOffset(390, 555)
    setStatus(minimized and "Panel minimized" or "Ready")
end)
Close.Activated:Connect(function()
    stopPlayback = true
    State.Recording = false
    State.Playing = false
    Gui:Destroy()
    ENV.__GTD_CONTROL_HUB = nil
    ENV.__GTD_HUB_STATUS_LABEL = nil
end)

local function isInsideHub(position)
    if not Main.Visible then return false end
    local p = Main.AbsolutePosition
    local s = Main.AbsoluteSize
    return position.X >= p.X and position.X <= p.X + s.X and position.Y >= p.Y and position.Y <= p.Y + s.Y
end

-- Capture real player input for the macro. Hub UI clicks are excluded.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not State.Recording or State.Playing then return end
    local now = os.clock()
    local delayValue = math.clamp(now - macroLastTime, 0, 8)
    local action

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.MouseButton2
        or input.UserInputType == Enum.UserInputType.MouseButton3 then
        local pos = UserInputService:GetMouseLocation()
        if isInsideHub(pos) then return end
        local button = 0
        if input.UserInputType == Enum.UserInputType.MouseButton2 then button = 1 end
        if input.UserInputType == Enum.UserInputType.MouseButton3 then button = 2 end
        action = { kind = "mouse", x = math.floor(pos.X), y = math.floor(pos.Y), button = button, delay = delayValue }
    elseif input.UserInputType == Enum.UserInputType.Keyboard then
        action = { kind = "key", key = input.KeyCode.Name, delay = delayValue }
    end

    if action then
        table.insert(State.Macro, action)
        macroLastTime = now
    end
end)

local function normalize(text)
    text = tostring(text or ""):lower()
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function getGameButtons()
    local result = {}
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return result end
    for _, item in ipairs(playerGui:GetDescendants()) do
        if item:IsA("TextButton") and item.Visible and item.AbsoluteSize.X > 0 and item.AbsoluteSize.Y > 0 then
            table.insert(result, item)
        end
    end
    return result
end

local function activateButton(button)
    if not button or not button.Parent then return false end
    if type(firesignal) == "function" then
        local ok = pcall(function() firesignal(button.Activated) end)
        if ok then return true end
        ok = pcall(function() firesignal(button.MouseButton1Click) end)
        if ok then return true end
    end
    local ok = pcall(function() button:Activate() end)
    if ok then return true end
    return false
end

local function findButtonByText(matchFn)
    for _, button in ipairs(getGameButtons()) do
        local text = normalize(button.Text)
        if text ~= "" and matchFn(text, button) then
            return button, text
        end
    end
    return nil
end

local function clickFirstMatching(key, matchFn, cooldown)
    local button = findButtonByText(matchFn)
    if button then
        local now = os.clock()
        if now - (lastAction[key] or 0) >= (cooldown or 1) then
            if activateButton(button) then
                lastAction[key] = now
                return true, button.Text
            end
        end
    end
    return false
end

local function runAutoSkip()
    local now = os.clock()
    if now - lastSkipClick < 1.25 then return end
    local ok, label = clickFirstMatching("skip", function(text)
        return text:find("skip", 1, true) ~= nil or text:find("vote skip", 1, true) ~= nil
    end, 1.25)
    if ok then
        lastSkipClick = now
        setStatus("Auto Skip clicked: " .. tostring(label))
    end
end

local function runAutoSpeed()
    if speedDone then return end
    local speedButton, text = findButtonByText(function(value)
        return value:find("3x", 1, true) ~= nil or value:find("x3", 1, true) ~= nil or value:find("triple speed", 1, true) ~= nil
    end)
    if speedButton then
        -- Avoid clicking if the visible control already says the selected speed is x3.
        if text:find("speed", 1, true) and (text:find("3x", 1, true) or text:find("x3", 1, true)) then
            speedDone = true
            setStatus("Auto Speed: x3 appears selected")
            return
        end
        if activateButton(speedButton) then
            speedDone = true
            setStatus("Auto Speed selected: " .. tostring(speedButton.Text))
            return
        end
    end

    local menuButton = findButtonByText(function(value)
        return value == "speed" or value == "game speed" or value:find("speed: 1x", 1, true) ~= nil or value:find("speed 1x", 1, true) ~= nil
    end)
    if menuButton and os.clock() - (lastAction.openSpeed or 0) > 2 then
        if activateButton(menuButton) then
            lastAction.openSpeed = os.clock()
            setStatus("Opened speed selector; looking for x3")
        end
    end
end

local function runAutoTarget()
    if os.clock() - lastTargetClick < 2 then return end
    local button, text = findButtonByText(function(value)
        return value == "first" or value == "first enemy" or value == "target: first" or value == "target first"
    end)
    if button then
        -- Only selects an explicit visible First option; it does not fire game remotes.
        if activateButton(button) then
            lastTargetClick = os.clock()
            setStatus("Target priority set via visible First option")
        end
    end
end

local function runAutoMode()
    if modeDone then return end
    local mapNeedle = normalize(State.DesiredMap)
    local modeNeedle = normalize(State.DesiredMode)
    if mapNeedle == "" or modeNeedle == "" then return end

    local mapButton = findButtonByText(function(text)
        return text == mapNeedle or text:find(mapNeedle, 1, true) ~= nil
    end)
    if mapButton and not lastAction.map then
        if activateButton(mapButton) then
            lastAction.map = os.clock()
            setStatus("Selected map option: " .. tostring(mapButton.Text))
            return
        end
    end

    if lastAction.map and os.clock() - lastAction.map < 0.65 then return end
    local modeButton = findButtonByText(function(text)
        return text == modeNeedle or text:find(modeNeedle, 1, true) ~= nil
    end)
    if modeButton then
        if activateButton(modeButton) then
            modeDone = true
            setStatus("Selected mode option: " .. tostring(modeButton.Text))
        end
    end
end

local function runAutoReplay()
    if os.clock() - lastReplayClick < 2 then return end
    local button = findButtonByText(function(text)
        return text:find("play again", 1, true) ~= nil or text == "replay" or text == "play again!"
    end)
    if button and activateButton(button) then
        lastReplayClick = os.clock()
        speedDone = false
        modeDone = false
        lastAction.map = nil
        setStatus("Auto Replay clicked")
    end
end

local function runAutoClaim()
    if os.clock() - lastClaimScan < 1.5 then return end
    lastClaimScan = os.clock()
    for _, button in ipairs(getGameButtons()) do
        local text = normalize(button.Text)
        if not claimedButtons[button] and (text == "claim" or text == "collect" or text == "claim reward" or text == "collect reward") then
            if activateButton(button) then
                claimedButtons[button] = true
                setStatus("Claimed visible reward")
                break
            end
        end
    end
end

-- Keyboard shortcut: RightShift hides/shows the hub.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.RightShift then
        Main.Visible = not Main.Visible
    end
end)

-- Main automation loop. All game interactions are through currently visible UI buttons.
task.spawn(function()
    setStatus("Loaded — toggle the features you need")
    while Gui.Parent do
        task.wait(0.3)
        if State.AutoSkip then pcall(runAutoSkip) end
        if State.AutoSpeed then pcall(runAutoSpeed) end
        if State.AutoTargetFirst then pcall(runAutoTarget) end
        if State.AutoMode then pcall(runAutoMode) end
        if State.AutoReplay then pcall(runAutoReplay) end
        if State.AutoClaim then pcall(runAutoClaim) end
    end
end)

setStatus("Loaded v0.3 — PlayerGui mode; RightShift hides/shows panel")
print("[GTD Control Hub v0.3] Loaded for Delta. Parent=PlayerGui. RightShift = hide/show.")
