--[[
    GTD CONTROL HUB • DELTA v2.2.39 MATCH-LOOP + CLICK-CAPTURE PATCH LOADER

    Fixes premature macro replay after GameEnd and keeps optional mouse-click
    recording / playback for Corn Maze harvesting. GameEnd closing now only
    arms the detector; playback resumes after the Context / GameStartTime / RunId
    changes, confirming that the next match actually exists.
]]

local PATCH_URL = "https://raw.githubusercontent.com/litvinovasez-eng/gtd-control-hub/main/GTD_Control_Hub_Delta_v2.2.37.lua"
local fetched, loaderSource = pcall(function()
    return game:HttpGet(PATCH_URL)
end)
if not fetched or type(loaderSource) ~= "string" or loaderSource == "" then
    error("GTD Control Hub v2.2.39: failed to download v2.2.37 patch loader: " .. tostring(loaderSource))
end

-- Replace the v2.2.37 GameEnd-hidden edge trigger with a real next-round gate.
-- Hiding GameEnd only arms the detector; it does NOT make the old Context live again.
local detectorMarker = "local function replaceExactlyOnce(haystack, needle, replacement, label)"
local detectorPos = string.find(loaderSource, detectorMarker, 1, true)
if not detectorPos then
    error("GTD Control Hub v2.2.39: could not locate match-cycle detector definition")
end
local fixedDetector = [====[
newLoopHead = [==[
local function runAutomation()
    local endNodes = {}
    local visibleEndCount = 0
    local hasSeenEndOverlay = false
    local awaitingNewRound = false
    local endedBaseRoundKey = nil
    local matchCycle = 0
    State.MatchCycle = 0
    State.MatchAwaitingNewRound = false
    State.LastConfirmedLiveBaseRoundKey = nil

    local function setEndNodeVisible(node, visible)
        local previous = endNodes[node]
        if previous == visible then return end
        endNodes[node] = visible

        if visible then
            visibleEndCount = visibleEndCount + 1
            hasSeenEndOverlay = true
        else
            visibleEndCount = math.max(0, visibleEndCount - 1)
            if visibleEndCount == 0 and hasSeenEndOverlay then
                hasSeenEndOverlay = false
                awaitingNewRound = true
                State.MatchAwaitingNewRound = true
                endedBaseRoundKey = State.LastConfirmedLiveBaseRoundKey
                    or State.CurrentBaseRoundKey
                print("[GTD Macro Loop] GameEnd closed; waiting for a different match ID • old="
                    .. tostring(endedBaseRoundKey or "not captured"))
            end
        end
    end

    local function watchGameEndNode(object)
        if not object or object.Name ~= "GameEnd" or not object:IsA("GuiObject") then return end
        if endNodes[object] ~= nil then return end
        endNodes[object] = false
        connect(object:GetPropertyChangedSignal("Visible"), function()
            setEndNodeVisible(object, object.Visible)
        end)
        setEndNodeVisible(object, object.Visible)
    end

    local function removeGameEndNode(object)
        if endNodes[object] ~= nil then
            setEndNodeVisible(object, false)
            endNodes[object] = nil
        end
    end

    -- Attach to both known GTD GUI roots and catch recreated GameEnd nodes.
    for _, rootName in ipairs({"GameGui", "GameGuiNoInset"}) do
        local root = PlayerGui:FindFirstChild(rootName)
        local screen = root and root:FindFirstChild("Screen")
        local middle = screen and screen:FindFirstChild("Middle")
        local endGui = middle and middle:FindFirstChild("GameEnd")
        if endGui then watchGameEndNode(endGui) end
    end
    connect(PlayerGui.DescendantAdded, watchGameEndNode)
    connect(PlayerGui.DescendantRemoving, removeGameEndNode)

    while Gui.Parent do
        task.wait(0.10)
        local context = getActiveContext()
        local baseRoundKey = getRoundKey(context)
        local runId = getGameAttribute("RunId", context)
        baseRoundKey = tostring(baseRoundKey) .. ":runId=" .. tostring(runId or "no-run-id")
        local liveRound = isInLiveRound(context)

        -- If launched while the end screen is already open, capture the old ID
        -- before it closes. Never treat the old GameStartTime as a new round.
        if visibleEndCount > 0 and not awaitingNewRound then
            endedBaseRoundKey = State.LastConfirmedLiveBaseRoundKey or baseRoundKey
        end

        if awaitingNewRound then
            if not endedBaseRoundKey then
                -- First observation after attaching to an already-open GameEnd UI.
                endedBaseRoundKey = baseRoundKey
                liveRound = false
            elseif liveRound and baseRoundKey ~= endedBaseRoundKey then
                awaitingNewRound = false
                State.MatchAwaitingNewRound = false
                matchCycle = matchCycle + 1
                State.MatchCycle = matchCycle
                print("[GTD Macro Loop] Confirmed next match #" .. tostring(matchCycle)
                    .. " • new=" .. tostring(baseRoundKey))
            else
                -- GameEnd disappearing is not sufficient: keep playback asleep
                -- until Context identity, GameStartTime, or RunId really changes.
                liveRound = false
            end
        end

        if liveRound then
            State.LastConfirmedLiveBaseRoundKey = baseRoundKey
        end

        local roundKey = tostring(baseRoundKey) .. ":matchCycle=" .. tostring(matchCycle)
        State.BaseRoundKey = baseRoundKey
        State.ActiveContext = context
        State.RoundLive = liveRound
        State.CurrentRoundKey = roundKey
]==]

]====]
loaderSource = string.sub(loaderSource, 1, detectorPos - 1)
    .. fixedDetector .. string.sub(loaderSource, detectorPos)

local anchor = 'source = replaceExactlyOnce(source, oldLoopHead, newLoopHead, "runAutomation GameEnd event detector")'
local first, last = string.find(loaderSource, anchor, 1, true)
if not first then
    error("GTD Control Hub v2.2.39: could not find the v2.2.37 source-patch insertion point")
end
if string.find(loaderSource, anchor, last + 1, true) then
    error("GTD Control Hub v2.2.39: source-patch insertion point is ambiguous")
end

local clickPatch = [====[
source = replaceExactlyOnce(source, oldLoopHead, newLoopHead, "runAutomation GameEnd event detector")

-- Add optional mouse-click recording / playback without changing the existing
-- tower action format. Mouse clicks share the same sequence and timing timeline.
source = replaceExactlyOnce(source,
    [==[label(MacroInfo, "Records placements, upgrades, abilities and unit sales in match order.\nRecord from the first placement so actions can be linked to each tower.", 10, Theme.muted, Enum.Font.Gotham, {]==],
    [==[label(MacroInfo, "Records placements, upgrades, abilities, sales and world clicks in match order.\nEnable MOUSE ON to capture map clicks.", 10, Theme.muted, Enum.Font.Gotham, {]==],
    "Macro Recorder description")

source = replaceExactlyOnce(source,
    [==[label(LoopToggleRow, "Repeat macro on every new match", 10, Theme.text, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(12,0), Size = UDim2.new(1,-90,1,0), TextXAlignment = Enum.TextXAlignment.Left,
})]==],
    [==[label(LoopToggleRow, "Repeat macro on every new match", 10, Theme.text, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(12,0), Size = UDim2.new(1,-145,1,0), TextXAlignment = Enum.TextXAlignment.Left,
})]==],
    "Mouse click toggle label width")

source = replaceExactlyOnce(source,
    [==[if State.Loop then
    LoopSwitch.BackgroundColor3 = Theme.green]==],
    [==[State.RecordMouseClicks = State.RecordMouseClicks ~= false
local MouseClickToggleButton = secondaryButton(
    LoopToggleRow,
    State.RecordMouseClicks and "MOUSE ON" or "MOUSE OFF",
    UDim2.new(1,-130,0.5,-13), UDim2.fromOffset(68,26), function() end
)
MouseClickToggleButton.TextSize = 8
MouseClickToggleButton.BackgroundColor3 = State.RecordMouseClicks and Theme.green or Theme.panel3
connect(MouseClickToggleButton.Activated, function()
    State.RecordMouseClicks = not State.RecordMouseClicks
    MouseClickToggleButton.Text = State.RecordMouseClicks and "MOUSE ON" or "MOUSE OFF"
    MouseClickToggleButton.BackgroundColor3 = State.RecordMouseClicks and Theme.green or Theme.panel3
    setStatus(State.RecordMouseClicks and "Mouse click recording enabled" or "Mouse click recording disabled",
        State.RecordMouseClicks and Theme.green or Theme.amber)
end)

if State.Loop then
    LoopSwitch.BackgroundColor3 = Theme.green]==],
    "Mouse click capture toggle")

source = replaceExactlyOnce(source,
    "local validTypes = {Place = true, Upgrade = true, AutoUpgrade = true, Ability = true, Sell = true, SellAll = true}",
    "local validTypes = {Place = true, Upgrade = true, AutoUpgrade = true, Ability = true, Sell = true, SellAll = true, MouseClick = true}",
    "MouseClick action type")

source = replaceExactlyOnce(source,
    [==[        requiredRemotes[remoteName] = true
        if actionType == "Place" then
            if type(action.unit) ~= "string" or action.unit == "" then]==],
    [==[        if remoteName then requiredRemotes[remoteName] = true end
        if actionType == "MouseClick" then
            local nx, ny = tonumber(action.xNorm), tonumber(action.yNorm)
            if nx == nil or ny == nil or nx < 0 or nx > 1 or ny < 0 or ny > 1 then
                setStatus("Ошибка запуска: у клика №" .. tostring(index) .. " повреждены координаты", Theme.red)
                return
            end
        elseif actionType == "Place" then
            if type(action.unit) ~= "string" or action.unit == "" then]==],
    "MouseClick validation")

source = replaceExactlyOnce(source,
    '        elseif actionType ~= "SellAll" then\n            if not action.towerKey and tonumber(action.sourceGameId) == nil then',
    '        elseif actionType ~= "SellAll" and actionType ~= "MouseClick" then\n            if not action.towerKey and tonumber(action.sourceGameId) == nil then',
    "Exclude MouseClick from tower validation")

source = replaceExactlyOnce(source,
    [==[                        elseif actionType == "SellAll" then
                            if not State.AllowRecordedSales then]==],
    [==[                        elseif actionType == "MouseClick" then
                            local clickCamera = Workspace.CurrentCamera
                            if not clickCamera then
                                actionError = "current camera is unavailable for recorded mouse click"
                            else
                                local viewport = clickCamera.ViewportSize
                                if not viewport or viewport.X < 1 or viewport.Y < 1 then
                                    actionError = "current viewport is unavailable for recorded mouse click"
                                else
                                    local nx = math.clamp(tonumber(action.xNorm) or 0, 0, 1)
                                    local ny = math.clamp(tonumber(action.yNorm) or 0, 0, 1)
                                    local clickX = math.clamp(math.floor(nx * viewport.X), 0, viewport.X - 1)
                                    local clickY = math.clamp(math.floor(ny * viewport.Y), 0, viewport.Y - 1)
                                    local clickSent = false

                                    -- Prefer VirtualInputManager, then executor mouse APIs,
                                    -- then the legacy VirtualUser fallback.
                                    local vimOk, virtualInput = pcall(function()
                                        return game:GetService("VirtualInputManager")
                                    end)
                                    if vimOk and virtualInput then
                                        local moveOk = pcall(function()
                                            virtualInput:SendMouseMoveEvent(clickX, clickY, game)
                                        end)
                                        local downOk = false
                                        if moveOk then
                                            downOk = pcall(function()
                                                virtualInput:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
                                            end)
                                        end
                                        task.wait(0.055)
                                        local upOk = pcall(function()
                                            virtualInput:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
                                        end)
                                        clickSent = moveOk and downOk and upOk
                                    end

                                    if not clickSent and type(mousemoveabs) == "function"
                                        and type(mouse1click) == "function" then
                                        local moved = pcall(mousemoveabs, clickX, clickY)
                                        if moved then
                                            task.wait(0.04)
                                            clickSent = pcall(mouse1click)
                                        end
                                    end

                                    if not clickSent then
                                        local vuOk, virtualUser = pcall(function()
                                            return game:GetService("VirtualUser")
                                        end)
                                        if vuOk and virtualUser then
                                            local downOk = pcall(function()
                                                virtualUser:CaptureController()
                                                virtualUser:Button1Down(Vector2.new(clickX, clickY), clickCamera.CFrame)
                                            end)
                                            task.wait(0.055)
                                            local upOk = pcall(function()
                                                virtualUser:Button1Up(Vector2.new(clickX, clickY), clickCamera.CFrame)
                                            end)
                                            clickSent = downOk and upOk
                                        end
                                    end

                                    actionOk = clickSent
                                    if not clickSent then
                                        actionError = "executor could not simulate a left mouse click (VirtualInputManager / mouse API / VirtualUser unavailable)"
                                    else
                                        setStatus(string.format("Mouse click %d/%d • %.3f, %.3f", index,
                                            #State.Placements, nx, ny), Theme.accent2)
                                    end
                                end
                            end
                        elseif actionType == "SellAll" then
                            if not State.AllowRecordedSales then]==],
    "MouseClick playback branch")

source = replaceExactlyOnce(source,
    [==[connect(UserInputService.InputBegan, function(input)
    if input.KeyCode == Enum.KeyCode.RightShift then]==],
    [==[-- Record ordinary left-clicks on the game viewport, outside the Macro Hub window.
-- Coordinates are normalized to the viewport to tolerate resolution changes.
connect(UserInputService.InputBegan, function(input, gameProcessedEvent)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if gameProcessedEvent or not State.RecordMouseClicks then return end
    if not State.Recording or State.Playing or not State.RoundLive
        or not State.RecordingRoundKey or State.RecordingRoundKey ~= State.CurrentRoundKey then return end

    local focusedOk, focusedTextBox = pcall(function()
        return UserInputService:GetFocusedTextBox()
    end)
    if focusedOk and focusedTextBox then return end

    local point = input.Position
    local px, py = tonumber(point.X), tonumber(point.Y)
    if not px or not py then return end

    if Main and Main.Visible then
        local origin, size = Main.AbsolutePosition, Main.AbsoluteSize
        if px >= origin.X and px <= origin.X + size.X
            and py >= origin.Y and py <= origin.Y + size.Y then
            return
        end
    end

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize
    if not viewport or viewport.X < 1 or viewport.Y < 1 then return end

    local sequence, elapsed, delay = nextMacroStamp()
    insertMacroAction({
        type = "MouseClick",
        xNorm = math.clamp(px / viewport.X, 0, 1),
        yNorm = math.clamp(py / viewport.Y, 0, 1),
        sequence = sequence,
        elapsed = elapsed,
        delay = delay,
    })
    setStatus(string.format("Recorded map click %d • %.3f, %.3f",
        #State.Placements, px / viewport.X, py / viewport.Y), Theme.green)
end)

connect(UserInputService.InputBegan, function(input)
    if input.KeyCode == Enum.KeyCode.RightShift then]==],
    "Mouse click recording listener")


]====]
loaderSource = string.sub(loaderSource, 1, first - 1) .. clickPatch .. string.sub(loaderSource, last + 1)
loaderSource = loaderSource:gsub("2%.2%.37", "2.2.39")

local compiler = loadstring or load
if type(compiler) ~= "function" then
    error("GTD Control Hub v2.2.39: loadstring is unavailable")
end
local compiled, runLoader = pcall(compiler, loaderSource)
if not compiled or type(runLoader) ~= "function" then
    error("GTD Control Hub v2.2.39: loader compile failed: " .. tostring(runLoader))
end
runLoader()
