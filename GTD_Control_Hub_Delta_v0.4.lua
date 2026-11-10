--[[
    GTD CONTROL HUB • DELTA v0.4
    Placement-coordinate macro recorder + animated UI.

    Macro design:
      • Records ONLY successful calls to ReplicatedStorage.RemoteFunctions.PlaceUnit.
      • Stores unit key, map-world Vector3 position, yaw and delay between placements.
      • Does NOT record player movement, camera movement, mouse coordinates or keyboard input.
      • Playback invokes PlaceUnit with the stored unit key and world-space placement payload.

    Notes:
      • The exact PlaceUnit remote/payload may change in a future GTD update.
      • If the remote or hookfunction is unavailable, the recorder reports that in the UI.
      • Automation buttons are discovered from visible game UI text; game labels can change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ENV = (type(getgenv) == "function" and getgenv()) or _G

-- Clean up a previous UI instance. The one-time remote hook is reused on reload.
if ENV.__GTD_CONTROL_HUB then
    pcall(function()
        local previous = ENV.__GTD_CONTROL_HUB
        if typeof(previous) == "Instance" then
            previous:Destroy()
        elseif previous.Gui then
            previous.Gui:Destroy()
        end
    end)
end
for _, oldName in ipairs({"GTDControlHub_Delta", "GTDControlHub_Delta_v04"}) do
    local oldUi = PlayerGui:FindFirstChild(oldName)
    if oldUi then pcall(function() oldUi:Destroy() end) end
end

local Theme = {
    bg = Color3.fromRGB(12, 15, 24),
    panel = Color3.fromRGB(19, 24, 36),
    panel2 = Color3.fromRGB(25, 32, 47),
    panel3 = Color3.fromRGB(32, 41, 59),
    border = Color3.fromRGB(47, 61, 83),
    text = Color3.fromRGB(239, 244, 255),
    muted = Color3.fromRGB(143, 157, 180),
    accent = Color3.fromRGB(106, 126, 255),
    accent2 = Color3.fromRGB(59, 211, 190),
    green = Color3.fromRGB(55, 190, 133),
    red = Color3.fromRGB(239, 91, 111),
    amber = Color3.fromRGB(246, 184, 76),
}

local State = {
    Recording = false,
    Playing = false,
    Loop = false,
    Placements = {},
    MacroName = "My GTD Strategy",
    Status = "Ready",
    SelectedTab = "Overview",
    AutoSkip = false,
    AutoSpeed = false,
    AutoTargetFirst = false,
    AutoMode = false,
    AutoReplay = false,
    AutoClaim = false,
    DesiredMap = "Dojo Dynasty",
    DesiredMode = "Level 6",
}

local Connections = {}
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(Connections, c)
    return c
end

local function make(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end

local function round(obj, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, obj)
end

local function outline(obj, color, transparency, thickness)
    return make("UIStroke", {
        Color = color or Theme.border,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function tween(obj, duration, props, style, direction)
    local info = TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local function label(parent, text, size, color, font, props)
    props = props or {}
    props.BackgroundTransparency = 1
    props.Text = text or ""
    props.TextColor3 = color or Theme.text
    props.Font = font or Enum.Font.Gotham
    props.TextSize = size or 13
    props.Parent = parent
    return make("TextLabel", props)
end

local StatusText, StatusDot

local function setStatus(text, color)
    State.Status = tostring(text)
    if StatusText then StatusText.Text = State.Status end
    if StatusDot then
        tween(StatusDot, 0.18, {BackgroundColor3 = color or Theme.accent2})
    end
end

local Gui = make("ScreenGui", {
    Name = "GTDControlHub_Delta_v04",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 99999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)
ENV.__GTD_CONTROL_HUB = {Gui = Gui, State = State}

-- Soft backdrop and main shell.
local Shadow = make("Frame", {
    Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 570),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.48,
    BorderSizePixel = 0,
}, Gui)
round(Shadow, 20)

local Main = make("Frame", {
    Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(800, 550),
    BackgroundColor3 = Theme.bg, BorderSizePixel = 0, ClipsDescendants = true,
}, Gui)
round(Main, 18)
outline(Main, Theme.border, 0.12, 1)

local MainGradient = make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 25, 42)),
        ColorSequenceKeypoint.new(0.55, Theme.bg),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 29, 38)),
    }),
    Rotation = 25,
}, Main)

-- Header.
local Header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 66),
    BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
}, Main)
local HeaderGrad = make("UIGradient", {
    Color = ColorSequence.new(Theme.panel, Color3.fromRGB(33, 42, 68)),
    Rotation = 0,
}, Header)

local BrandMark = make("Frame", {
    Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(38, 38),
    BackgroundColor3 = Theme.accent, BorderSizePixel = 0,
}, Header)
round(BrandMark, 12)
make("UIGradient", {
    Color = ColorSequence.new(Theme.accent, Theme.accent2), Rotation = 35,
}, BrandMark)
label(BrandMark, "G", 22, Color3.new(1,1,1), Enum.Font.GothamBlack, {
    Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
})

label(Header, "GTD CONTROL HUB", 16, Theme.text, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(70, 13), Size = UDim2.fromOffset(240, 22),
    TextXAlignment = Enum.TextXAlignment.Left,
})
label(Header, "DELTA  •  PLACEMENT MACROS", 9, Theme.muted, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(71, 36), Size = UDim2.fromOffset(260, 16),
    TextXAlignment = Enum.TextXAlignment.Left,
})

local StatusPill = make("Frame", {
    Position = UDim2.new(1, -210, 0, 20), Size = UDim2.fromOffset(145, 27),
    BackgroundColor3 = Theme.panel3, BorderSizePixel = 0,
}, Header)
round(StatusPill, 20)
StatusDot = make("Frame", {
    Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(7, 7),
    BackgroundColor3 = Theme.accent2, BorderSizePixel = 0,
}, StatusPill)
round(StatusDot, 10)
StatusText = label(StatusPill, "Ready", 10, Theme.muted, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -29, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
})

local Minimize = make("TextButton", {
    Position = UDim2.new(1, -54, 0, 17), Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = Theme.panel3, Text = "—", TextColor3 = Theme.text,
    Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false,
    BorderSizePixel = 0,
}, Header)
round(Minimize, 9)
local Close = make("TextButton", {
    Position = UDim2.new(1, -18, 0, 17), AnchorPoint = Vector2.new(1,0),
    Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(75, 37, 51),
    Text = "×", TextColor3 = Theme.red, Font = Enum.Font.GothamBold,
    TextSize = 19, AutoButtonColor = false, BorderSizePixel = 0,
}, Header)
round(Close, 9)

-- Sidebar and content region.
local Sidebar = make("Frame", {
    Position = UDim2.fromOffset(0, 66), Size = UDim2.new(0, 178, 1, -66),
    BackgroundColor3 = Color3.fromRGB(15, 19, 30), BorderSizePixel = 0,
}, Main)
local SideLine = make("Frame", {
    Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = Theme.border, BackgroundTransparency = 0.3, BorderSizePixel = 0,
}, Sidebar)
label(Sidebar, "WORKSPACE", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(18, 22), Size = UDim2.new(1, -30, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
})

local Content = make("Frame", {
    Position = UDim2.fromOffset(178, 66), Size = UDim2.new(1, -178, 1, -66),
    BackgroundTransparency = 1, BorderSizePixel = 0,
}, Main)

local Pages = {}
local NavButtons = {}
local currentPage = nil

local function createPage(name)
    local page = make("Frame", {
        Name = name, Size = UDim2.fromScale(1,1),
        BackgroundTransparency = 1, Visible = false,
    }, Content)
    Pages[name] = page
    return page
end

local function showPage(name)
    local page = Pages[name]
    if not page or currentPage == name then return end
    local old = currentPage and Pages[currentPage]
    currentPage = name
    State.SelectedTab = name
    for tabName, button in pairs(NavButtons) do
        local active = tabName == name
        local accent = button:FindFirstChild("ActiveBar")
        tween(button, 0.18, {BackgroundColor3 = active and Theme.panel3 or Color3.fromRGB(15,19,30)})
        if accent then tween(accent, 0.2, {BackgroundTransparency = active and 0 or 1}) end
        local txt = button:FindFirstChild("NavText")
        if txt then tween(txt, 0.18, {TextColor3 = active and Theme.text or Theme.muted}) end
    end
    if old then
        tween(old, 0.13, {Position = UDim2.fromOffset(-12,0)})
        task.delay(0.13, function() if old and old.Parent then old.Visible = false end end)
    end
    page.Visible = true
    page.Position = UDim2.fromOffset(12,0)
    page.BackgroundTransparency = 1
    tween(page, 0.24, {Position = UDim2.fromOffset(0,0)}, Enum.EasingStyle.Quint)
end

local navInfo = {
    {name="Overview", icon="⌂"},
    {name="Macro Recorder", icon="◉"},
    {name="Automation", icon="⚡"},
    {name="Settings", icon="⚙"},
}
for i, info in ipairs(navInfo) do
    local button = make("TextButton", {
        Position = UDim2.fromOffset(10, 52 + (i-1)*48), Size = UDim2.new(1, -20, 0, 40),
        BackgroundColor3 = Color3.fromRGB(15,19,30), Text = "", BorderSizePixel = 0,
        AutoButtonColor = false,
    }, Sidebar)
    round(button, 9)
    local bar = make("Frame", {
        Name = "ActiveBar", Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(3, 24),
        BackgroundColor3 = Theme.accent2, BackgroundTransparency = 1, BorderSizePixel = 0,
    }, button)
    round(bar, 4)
    label(button, info.icon, 17, Theme.accent2, Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(25, 40),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    label(button, info.name, 11, Theme.muted, Enum.Font.GothamSemibold, {
        Name = "NavText", Position = UDim2.fromOffset(45, 0),
        Size = UDim2.new(1, -52, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
    })
    NavButtons[info.name] = button
    connect(button.Activated, function() showPage(info.name) end)
    connect(button.MouseEnter, function()
        if currentPage ~= info.name then tween(button, 0.12, {BackgroundColor3 = Theme.panel2}) end
    end)
    connect(button.MouseLeave, function()
        if currentPage ~= info.name then tween(button, 0.12, {BackgroundColor3 = Color3.fromRGB(15,19,30)}) end
    end)
end

local function pageTitle(parent, titleText, subtitle)
    label(parent, titleText, 21, Theme.text, Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(24, 20), Size = UDim2.new(1, -48, 0, 30),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    label(parent, subtitle, 10, Theme.muted, Enum.Font.Gotham, {
        Position = UDim2.fromOffset(25, 52), Size = UDim2.new(1, -50, 0, 20),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function card(parent, pos, size, accent)
    local f = make("Frame", {
        Position = pos, Size = size, BackgroundColor3 = Theme.panel,
        BorderSizePixel = 0,
    }, parent)
    round(f, 13)
    outline(f, accent or Theme.border, 0.35, 1)
    return f
end

local function primaryButton(parent, textValue, pos, size, color, callback)
    local b = make("TextButton", {
        Position = pos, Size = size, BackgroundColor3 = color or Theme.accent,
        Text = textValue, TextColor3 = Color3.new(1,1,1),
        Font = Enum.Font.GothamBold, TextSize = 11, BorderSizePixel = 0,
        AutoButtonColor = false,
    }, parent)
    round(b, 9)
    local grad = make("UIGradient", {
        Color = ColorSequence.new(color or Theme.accent, color and color:Lerp(Color3.new(1,1,1), 0.12) or Theme.accent2),
        Rotation = 0,
    }, b)
    connect(b.MouseEnter, function() tween(b, 0.13, {BackgroundColor3 = (color or Theme.accent):Lerp(Color3.new(1,1,1),0.12)}) end)
    connect(b.MouseLeave, function() tween(b, 0.13, {BackgroundColor3 = color or Theme.accent}) end)
    connect(b.Activated, callback)
    return b
end

local function secondaryButton(parent, textValue, pos, size, callback)
    local b = make("TextButton", {
        Position = pos, Size = size, BackgroundColor3 = Theme.panel3,
        Text = textValue, TextColor3 = Theme.text,
        Font = Enum.Font.GothamSemibold, TextSize = 10, BorderSizePixel = 0,
        AutoButtonColor = false,
    }, parent)
    round(b, 9)
    outline(b, Theme.border, 0.35, 1)
    connect(b.MouseEnter, function() tween(b, 0.12, {BackgroundColor3 = Color3.fromRGB(42,54,76)}) end)
    connect(b.MouseLeave, function() tween(b, 0.12, {BackgroundColor3 = Theme.panel3}) end)
    connect(b.Activated, callback)
    return b
end

local function createToggle(parent, titleText, description, key, position)
    local row = make("Frame", {
        Position = position, Size = UDim2.new(1, -28, 0, 59),
        BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
    }, parent)
    round(row, 10)
    outline(row, Theme.border, 0.55, 1)
    label(row, titleText, 11, Theme.text, Enum.Font.GothamSemibold, {
        Position = UDim2.fromOffset(13, 9), Size = UDim2.new(1, -88, 0, 18),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    label(row, description, 9, Theme.muted, Enum.Font.Gotham, {
        Position = UDim2.fromOffset(13, 30), Size = UDim2.new(1, -88, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local track = make("TextButton", {
        Position = UDim2.new(1, -60, 0.5, -11), Size = UDim2.fromOffset(44, 22),
        BackgroundColor3 = Theme.panel3, Text = "", BorderSizePixel = 0,
        AutoButtonColor = false,
    }, row)
    round(track, 20)
    local knob = make("Frame", {
        Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(16,16),
        BackgroundColor3 = Color3.fromRGB(206,215,232), BorderSizePixel = 0,
    }, track)
    round(knob, 20)
    local function refresh(animated)
        local on = State[key]
        local goalTrack = on and Theme.green or Theme.panel3
        local goalPos = on and UDim2.new(1,-19,0,3) or UDim2.fromOffset(3,3)
        if animated then
            tween(track, 0.18, {BackgroundColor3 = goalTrack})
            tween(knob, 0.18, {Position = goalPos, BackgroundColor3 = Color3.new(1,1,1)})
        else
            track.BackgroundColor3 = goalTrack
            knob.Position = goalPos
        end
    end
    connect(track.Activated, function()
        State[key] = not State[key]
        refresh(true)
        setStatus(titleText .. (State[key] and " enabled" or " disabled"))
    end)
    refresh(false)
    return row, refresh
end

-- Page: Overview.
local Overview = createPage("Overview")
pageTitle(Overview, "Welcome back", "Your Garden Tower Defense control center")
local Hero = card(Overview, UDim2.fromOffset(24, 91), UDim2.new(1, -48, 0, 130), Theme.accent)
make("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(42,53,91), Color3.fromRGB(24,70,75)), Rotation = 15}, Hero)
label(Hero, "STRATEGY AUTOMATION", 9, Color3.fromRGB(174,197,255), Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(18, 18), Size = UDim2.new(1,-36,0,17), TextXAlignment = Enum.TextXAlignment.Left,
})
label(Hero, "Place. Record. Replay.", 22, Theme.text, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(18, 41), Size = UDim2.new(1,-36,0,32), TextXAlignment = Enum.TextXAlignment.Left,
})
label(Hero, "Coordinate-based macros — no mouse paths or player movement.", 10, Color3.fromRGB(198,211,231), Enum.Font.Gotham, {
    Position = UDim2.fromOffset(19, 79), Size = UDim2.new(1,-38,0,20), TextXAlignment = Enum.TextXAlignment.Left,
})
primaryButton(Hero, "OPEN MACRO RECORDER  →", UDim2.new(1,-187,1,-43), UDim2.fromOffset(168,30), Theme.accent, function()
    showPage("Macro Recorder")
end)

local StatsCard = card(Overview, UDim2.fromOffset(24, 236), UDim2.new(0.5,-30,0,93))
label(StatsCard, "RECORDED PLACEMENTS", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,14), Size = UDim2.new(1,-30,0,17), TextXAlignment = Enum.TextXAlignment.Left,
})
local PlacementCount = label(StatsCard, "0", 27, Theme.text, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,36), Size = UDim2.new(1,-30,0,35), TextXAlignment = Enum.TextXAlignment.Left,
})
local RuntimeCard = card(Overview, UDim2.new(0.5, 6, 0, 236), UDim2.new(0.5,-30,0,93), Theme.accent2)
label(RuntimeCard, "RECORDER MODE", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,14), Size = UDim2.new(1,-30,0,17), TextXAlignment = Enum.TextXAlignment.Left,
})
label(RuntimeCard, "PLACEUNIT / WORLD XYZ", 12, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,39), Size = UDim2.new(1,-30,0,22), TextXAlignment = Enum.TextXAlignment.Left,
})
local Quick = card(Overview, UDim2.fromOffset(24, 344), UDim2.new(1,-48,0,130))
label(Quick, "QUICK AUTOMATION", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,12), Size = UDim2.new(1,-30,0,16), TextXAlignment = Enum.TextXAlignment.Left,
})
label(Quick, "Use the Automation tab to configure wave skip, speed, target priority,\nmap/mode selection, replay and reward claiming.", 10, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,36), Size = UDim2.new(1,-30,0,42), TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
})
secondaryButton(Quick, "OPEN AUTOMATION", UDim2.fromOffset(15,86), UDim2.fromOffset(140,28), function()
    showPage("Automation")
end)

-- Page: Macro recorder.
local MacroPage = createPage("Macro Recorder")
pageTitle(MacroPage, "Macro Recorder", "Capture the actual unit placement request and map coordinates")
local MacroInfo = card(MacroPage, UDim2.fromOffset(24, 91), UDim2.new(1,-48,0,82), Theme.accent2)
label(MacroInfo, "PLACEMENT-ONLY CAPTURE", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,13), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(MacroInfo, "Records unit key + world XYZ + rotation. No WASD, camera,\nmouse coordinates or character CFrame are stored.", 10, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,35), Size = UDim2.new(1,-30,0,36), TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
})

local MacroActions = card(MacroPage, UDim2.fromOffset(24, 187), UDim2.new(1,-48,0,112))
label(MacroActions, "MACRO ACTIONS", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(14,10), Size = UDim2.new(1,-28,0,16), TextXAlignment = Enum.TextXAlignment.Left,
})
local macroNameBox = make("TextBox", {
    Position = UDim2.fromOffset(14,31), Size = UDim2.new(1,-28,0,27),
    BackgroundColor3 = Theme.panel3, Text = State.MacroName, TextColor3 = Theme.text,
    PlaceholderText = "Macro name", PlaceholderColor3 = Theme.muted,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, MacroActions)
round(macroNameBox, 7)

local CountLabel = label(MacroActions, "0 placements recorded", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(14,66), Size = UDim2.new(1,-28,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})

local ButtonRow = make("Frame", {
    Position = UDim2.fromOffset(24, 312), Size = UDim2.new(1,-48,0,42),
    BackgroundTransparency = 1,
}, MacroPage)
local RecordBtn = primaryButton(ButtonRow, "●  START RECORDING", UDim2.fromOffset(0,0), UDim2.new(0.5,-6,1,0), Theme.red, function() end)
local StopRecordBtn = secondaryButton(ButtonRow, "■  STOP & SAVE", UDim2.new(0.5,6,0,0), UDim2.new(0.5,-6,1,0), function() end)

local PlaybackRow = make("Frame", {
    Position = UDim2.fromOffset(24, 364), Size = UDim2.new(1,-48,0,40),
    BackgroundTransparency = 1,
}, MacroPage)
local PlayBtn = primaryButton(PlaybackRow, "▶  PLAY MACRO", UDim2.fromOffset(0,0), UDim2.new(0.5,-6,1,0), Theme.green, function() end)
local StopPlayBtn = secondaryButton(PlaybackRow, "■  STOP PLAYBACK", UDim2.new(0.5,6,0,0), UDim2.new(0.5,-6,1,0), function() end)

local LoopToggleRow = make("Frame", {
    Position = UDim2.fromOffset(24, 415), Size = UDim2.new(1,-48,0,40),
    BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
}, MacroPage)
round(LoopToggleRow, 9)
label(LoopToggleRow, "Loop macro after it finishes", 10, Theme.text, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(12,0), Size = UDim2.new(1,-90,1,0), TextXAlignment = Enum.TextXAlignment.Left,
})
local LoopSwitch = make("TextButton", {
    Position = UDim2.new(1,-58,0.5,-10), Size = UDim2.fromOffset(44,20),
    BackgroundColor3 = Theme.panel3, Text = "", BorderSizePixel = 0, AutoButtonColor = false,
}, LoopToggleRow)
round(LoopSwitch, 20)
local LoopKnob = make("Frame", {
    Position = UDim2.fromOffset(3,3), Size = UDim2.fromOffset(14,14),
    BackgroundColor3 = Theme.text, BorderSizePixel = 0,
}, LoopSwitch)
round(LoopKnob, 20)
connect(LoopSwitch.Activated, function()
    State.Loop = not State.Loop
    tween(LoopSwitch, 0.17, {BackgroundColor3 = State.Loop and Theme.green or Theme.panel3})
    tween(LoopKnob, 0.17, {Position = State.Loop and UDim2.new(1,-17,0,3) or UDim2.fromOffset(3,3)})
end)

local RecentCard = card(MacroPage, UDim2.fromOffset(24, 465), UDim2.new(1,-48,0,1))
RecentCard.Visible = false -- reserved; action count/status stays compact in this first recorder build.

-- Page: Automation.
local AutoPage = createPage("Automation")
pageTitle(AutoPage, "Automation", "These switches use visible in-game controls; labels may vary by update")
local AutoRows = {}
local function autoRow(index, titleText, desc, key)
    local _, refresh = createToggle(AutoPage, titleText, desc, key, UDim2.fromOffset(24, 88 + (index-1)*67))
    AutoRows[key] = refresh
end
autoRow(1, "Auto Skip Waves", "Presses the visible Skip / Vote Skip control", "AutoSkip")
autoRow(2, "Auto Speed x3", "Selects the visible 3x game-speed option", "AutoSpeed")
autoRow(3, "Auto Target First", "Selects the visible First target-priority option", "AutoTargetFirst")
autoRow(4, "Auto Select Map / Mode", "Uses the map and level text configured in Settings", "AutoMode")
autoRow(5, "Auto Replay", "Presses Play Again when the result screen appears", "AutoReplay")
autoRow(6, "Auto Claim Rewards", "Claims visible Claim / Collect buttons", "AutoClaim")

-- Page: Settings.
local SettingsPage = createPage("Settings")
pageTitle(SettingsPage, "Settings", "Choose the map and level labels used by Auto Select")
local SettingsCard = card(SettingsPage, UDim2.fromOffset(24, 91), UDim2.new(1,-48,0,180))
label(SettingsCard, "MATCH PREFERENCES", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,14), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(SettingsCard, "Map button text", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,43), Size = UDim2.new(1,-30,0,15), TextXAlignment = Enum.TextXAlignment.Left,
})
local mapBox = make("TextBox", {
    Position = UDim2.fromOffset(15,61), Size = UDim2.new(1,-30,0,30),
    BackgroundColor3 = Theme.panel3, Text = State.DesiredMap, TextColor3 = Theme.text,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsCard)
round(mapBox, 7)
label(SettingsCard, "Mode / level button text", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,101), Size = UDim2.new(1,-30,0,15), TextXAlignment = Enum.TextXAlignment.Left,
})
local modeBox = make("TextBox", {
    Position = UDim2.fromOffset(15,119), Size = UDim2.new(1,-30,0,30),
    BackgroundColor3 = Theme.panel3, Text = State.DesiredMode, TextColor3 = Theme.text,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsCard)
round(modeBox, 7)
connect(mapBox.FocusLost, function() State.DesiredMap = mapBox.Text; setStatus("Map preference updated") end)
connect(modeBox.FocusLost, function() State.DesiredMode = modeBox.Text; setStatus("Mode preference updated") end)

local InfoCard = card(SettingsPage, UDim2.fromOffset(24, 289), UDim2.new(1,-48,0,128), Theme.accent)
label(InfoCard, "ABOUT PLACEMENT MACROS", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,13), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(InfoCard, "The recorder listens only to PlaceUnit InvokeServer calls.\nPlayback reuses the saved unit key and world-space transform.\nIt never records or replays player movement or mouse paths.", 10, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,40), Size = UDim2.new(1,-30,0,72),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
})

-- Helpers: macro state and persistence.
local function updateMacroCount()
    if PlacementCount then PlacementCount.Text = tostring(#State.Placements) end
    if CountLabel then CountLabel.Text = tostring(#State.Placements) .. " placements recorded" end
end

local function macroPath(name)
    local safe = tostring(name or "Macro"):gsub("[^%w%-%_ ]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
    if safe == "" then safe = "Macro" end
    return "GTDControlHub/Macros/" .. safe .. ".json"
end

local function saveMacro()
    if type(writefile) ~= "function" then
        setStatus("Delta file API unavailable — macro is kept in memory", Theme.amber)
        return false
    end
    local folderOk = pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            if not isfolder("GTDControlHub") then makefolder("GTDControlHub") end
            if not isfolder("GTDControlHub/Macros") then makefolder("GTDControlHub/Macros") end
        end
    end)
    local data = {
        format = "GTDCH_PLACEMENT_MACRO",
        version = 1,
        name = State.MacroName,
        createdAt = os.time(),
        coordinateSpace = "world",
        actions = State.Placements,
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then setStatus("Could not encode macro", Theme.red); return false end
    local path = macroPath(State.MacroName)
    local wrote, err = pcall(writefile, path, encoded)
    if not wrote then setStatus("Save failed: " .. tostring(err), Theme.red); return false end
    setStatus("Saved " .. #State.Placements .. " placements", Theme.green)
    return true
end

local function loadMacro()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        setStatus("Delta file read API unavailable", Theme.amber)
        return false
    end
    local path = macroPath(State.MacroName)
    if not isfile(path) then setStatus("Macro file not found: " .. path, Theme.amber); return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok or type(data) ~= "table" or data.format ~= "GTDCH_PLACEMENT_MACRO" or type(data.actions) ~= "table" then
        setStatus("Invalid macro file", Theme.red)
        return false
    end
    State.Placements = data.actions
    updateMacroCount()
    setStatus("Loaded " .. #State.Placements .. " placements", Theme.green)
    return true
end

-- The GTD PlaceUnit remote is targeted directly; no global input recording is used.
local function findPlaceRemote()
    local folder = ReplicatedStorage:FindFirstChild("RemoteFunctions")
    local remote = folder and folder:FindFirstChild("PlaceUnit", true)
    if not remote then remote = ReplicatedStorage:FindFirstChild("PlaceUnit", true) end
    if remote and remote:IsA("RemoteFunction") then return remote end
    return nil
end

local PlaceRemote = findPlaceRemote()
local function extractPlacement(unitKey, payload)
    if type(payload) ~= "table" then return nil end
    local pos = payload.Position
    local cf = payload.CF
    if typeof(pos) ~= "Vector3" and typeof(cf) == "CFrame" then pos = cf.Position end
    if typeof(pos) ~= "Vector3" then return nil end
    local yaw = 0
    if typeof(cf) == "CFrame" then
        local _, y, _ = cf:ToOrientation()
        yaw = y
    elseif typeof(payload.Rotation) == "Vector3" then
        yaw = math.rad(payload.Rotation.Y)
    end
    return {
        type = "Place",
        unit = tostring(unitKey or "unknown"),
        x = pos.X, y = pos.Y, z = pos.Z,
        yaw = yaw,
        valid = payload.Valid ~= false,
        fast = payload.WasFastPlaced == true,
        delay = 0,
        time = os.clock(),
    }
end

local hookReady = false
local function installPlaceHook()
    if hookReady then return true end
    local remote = PlaceRemote or findPlaceRemote()
    if not remote then
        setStatus("GTD PlaceUnit RemoteFunction not found", Theme.red)
        return false
    end
    if type(hookfunction) ~= "function" then
        setStatus("This Delta build does not expose hookfunction", Theme.red)
        return false
    end

    local existing = ENV.__GTD_PLACE_HOOK
    if existing and existing.Remote == remote and existing.Holder then
        existing.Holder.OnCall = function(unitKey, payload, serverResult)
            local action = extractPlacement(unitKey, payload)
            if not action or serverResult == false or not State.Recording or State.Playing then return end
            local now = os.clock()
            action.delay = State.LastPlacementAt and math.clamp(now - State.LastPlacementAt, 0, 30) or 0
            State.LastPlacementAt = now
            table.insert(State.Placements, action)
            updateMacroCount()
            setStatus("Recorded " .. action.unit .. " at " .. string.format("%.1f, %.1f, %.1f", action.x, action.y, action.z), Theme.green)
        end
        PlaceRemote = remote
        hookReady = true
        return true
    end

    local holder = {OnCall = nil}
    local original
    local ok, result = pcall(function()
        original = hookfunction(remote.InvokeServer, function(self, ...)
            local args = table.pack(...)
            local returns = table.pack(original(self, table.unpack(args, 1, args.n)))
            if self == remote and holder.OnCall then
                pcall(holder.OnCall, args[1], args[2], returns[1])
            end
            return table.unpack(returns, 1, returns.n)
        end)
        return true
    end)
    if not ok or not result or type(original) ~= "function" then
        setStatus("Could not hook PlaceUnit: " .. tostring(result), Theme.red)
        return false
    end

    ENV.__GTD_PLACE_HOOK = {Remote = remote, Holder = holder}
    holder.OnCall = function(unitKey, payload, serverResult)
        local action = extractPlacement(unitKey, payload)
        if not action or serverResult == false or not State.Recording or State.Playing then return end
        local now = os.clock()
        action.delay = math.clamp(now - (State.LastPlacementAt or now), 0, 30)
        State.LastPlacementAt = now
        table.insert(State.Placements, action)
        updateMacroCount()
        setStatus("Recorded " .. action.unit .. " at " .. string.format("%.1f, %.1f, %.1f", action.x, action.y, action.z), Theme.green)
    end
    PlaceRemote = remote
    hookReady = true
    setStatus("PlaceUnit hook ready", Theme.green)
    return true
end

local function startRecording()
    if State.Playing then setStatus("Stop playback first", Theme.amber); return end
    if not installPlaceHook() then return end
    State.Placements = {}
    State.LastPlacementAt = nil
    State.Recording = true
    updateMacroCount()
    setStatus("Recording unit placements only", Theme.red)
end

local function stopRecordingAndSave()
    if not State.Recording then setStatus("Recorder is not active", Theme.amber); return end
    State.Recording = false
    saveMacro()
    updateMacroCount()
    if #State.Placements == 0 then
        setStatus("No PlaceUnit calls captured — check the GTD remote path", Theme.amber)
    else
        setStatus("Recording saved: " .. #State.Placements .. " placements", Theme.green)
    end
end

local function stopPlayback()
    State.Playing = false
    setStatus("Playback stopping", Theme.amber)
end

local function playMacro()
    if State.Recording then setStatus("Stop recording before playback", Theme.amber); return end
    if State.Playing then setStatus("Already playing", Theme.amber); return end
    if #State.Placements == 0 then
        if not loadMacro() then return end
    end
    if not installPlaceHook() then return end
    State.Playing = true
    setStatus("Playing " .. #State.Placements .. " placement actions", Theme.green)
    task.spawn(function()
        repeat
            for index, action in ipairs(State.Placements) do
                if not State.Playing then break end
                task.wait(math.clamp(tonumber(action.delay) or 0, 0, 30))
                if not State.Playing then break end
                local pos = Vector3.new(tonumber(action.x) or 0, tonumber(action.y) or 0, tonumber(action.z) or 0)
                local yaw = tonumber(action.yaw) or 0
                local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
                local payload = {
                    Position = pos,
                    CF = cf,
                    Rotation = Vector3.new(0, math.deg(yaw), 0),
                    Valid = action.valid ~= false,
                    WasFastPlaced = action.fast == true,
                }
                local ok, result = pcall(function()
                    return PlaceRemote:InvokeServer(action.unit, payload)
                end)
                if ok then
                    setStatus(string.format("Placed %d/%d • %s", index, #State.Placements, action.unit), Theme.green)
                else
                    setStatus("Placement " .. index .. " failed: " .. tostring(result), Theme.red)
                    task.wait(0.5)
                end
            end
        until not State.Playing or not State.Loop
        State.Playing = false
        setStatus("Macro playback finished", Theme.accent2)
    end)
end

connect(RecordBtn.Activated, startRecording)
connect(StopRecordBtn.Activated, stopRecordingAndSave)
connect(PlayBtn.Activated, playMacro)
connect(StopPlayBtn.Activated, stopPlayback)
connect(macroNameBox.FocusLost, function() State.MacroName = macroNameBox.Text end)

-- Visible in-game UI helpers for the non-macro toggles.
local function normalizeText(textValue)
    return tostring(textValue or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function getGameButtons()
    local list = {}
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextButton") and obj.Visible and obj.AbsoluteSize.X > 0 and obj.AbsoluteSize.Y > 0
            and not obj:IsDescendantOf(Gui) then
            list[#list+1] = obj
        end
    end
    return list
end

local function activateButton(button)
    if not button or not button.Parent then return false end
    if type(firesignal) == "function" then
        local ok = pcall(function() firesignal(button.Activated) end)
        if ok then return true end
    end
    return pcall(function() button:Activate() end)
end

local AutoLast = {}
local function findGameButton(matchFn)
    for _, button in ipairs(getGameButtons()) do
        local txt = normalizeText(button.Text)
        if txt ~= "" and matchFn(txt, button) then return button, txt end
    end
    return nil
end

local function autoClick(key, matcher, cooldown, statusText)
    if os.clock() - (AutoLast[key] or 0) < (cooldown or 1.5) then return end
    local button = findGameButton(matcher)
    if button and activateButton(button) then
        AutoLast[key] = os.clock()
        setStatus(statusText or ("Activated " .. key), Theme.accent2)
    end
end

local speedSelected = false
local modeSelectedMap = false
local modeSelectedLevel = false
local function runAutomation()
    while Gui.Parent do
        task.wait(0.35)
        if State.AutoSkip then
            autoClick("skip", function(t) return t:find("skip",1,true) ~= nil end, 1.2, "Auto Skip activated")
        end
        if State.AutoSpeed and not speedSelected then
            local b = findGameButton(function(t) return t == "3x" or t == "x3" or t:find("3x speed",1,true) ~= nil end)
            if b and activateButton(b) then speedSelected = true; setStatus("Speed x3 selected", Theme.accent2) end
        end
        if State.AutoTargetFirst then
            autoClick("first", function(t) return t == "first" or t == "target: first" or t == "first enemy" end, 2, "Target priority: First")
        end
        if State.AutoMode then
            if not modeSelectedMap then
                local mapNeedle = normalizeText(State.DesiredMap)
                local b = findGameButton(function(t) return t == mapNeedle end)
                if b and activateButton(b) then modeSelectedMap = true; setStatus("Map selected: " .. State.DesiredMap, Theme.accent2) end
            elseif not modeSelectedLevel then
                local modeNeedle = normalizeText(State.DesiredMode)
                local b = findGameButton(function(t) return t == modeNeedle end)
                if b and activateButton(b) then modeSelectedLevel = true; setStatus("Mode selected: " .. State.DesiredMode, Theme.accent2) end
            end
        end
        if State.AutoReplay then
            autoClick("replay", function(t) return t:find("play again",1,true) ~= nil or t == "replay" end, 2.5, "Auto Replay activated")
            if AutoLast.replay and os.clock() - AutoLast.replay > 4 then speedSelected = false; modeSelectedMap = false; modeSelectedLevel = false end
        end
        if State.AutoClaim then
            autoClick("claim", function(t) return t == "claim" or t == "collect" or t == "claim reward" end, 2, "Reward claimed")
        end
    end
end

-- Minimize, close, drag and page controls.
local minimized = false
connect(Minimize.Activated, function()
    minimized = not minimized
    local goal = minimized and UDim2.fromOffset(800,66) or UDim2.fromOffset(800,550)
    tween(Main, 0.25, {Size = goal})
    tween(Shadow, 0.25, {Size = minimized and UDim2.fromOffset(820,76) or UDim2.fromOffset(820,570)})
    Sidebar.Visible = not minimized
    Content.Visible = not minimized
end)
connect(Close.Activated, function()
    State.Recording = false
    State.Playing = false
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    tween(Main, 0.18, {Size = UDim2.fromOffset(760,0)})
    tween(Shadow, 0.18, {BackgroundTransparency = 1})
    task.delay(0.2, function() if Gui then Gui:Destroy() end end)
end)

local dragging, dragStart, startPos = false, nil, nil
connect(Header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)
connect(Header.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
connect(UserInputService.InputChanged, function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        Shadow.Position = Main.Position
    end
end)
connect(UserInputService.InputBegan, function(input)
    if input.KeyCode == Enum.KeyCode.RightShift then
        Main.Visible = not Main.Visible
        Shadow.Visible = Main.Visible
    end
end)

-- Animated accent sweep and initial entrance.
task.spawn(function()
    while Gui.Parent do
        tween(BrandMark, 0.8, {Rotation = 8}, Enum.EasingStyle.Sine)
        task.wait(0.8)
        tween(BrandMark, 0.8, {Rotation = -8}, Enum.EasingStyle.Sine)
        task.wait(0.8)
    end
end)
Main.Size = UDim2.fromOffset(740, 500)
Main.BackgroundTransparency = 1
Shadow.Size = UDim2.fromOffset(760, 520)
tween(Main, 0.35, {Size = UDim2.fromOffset(800,550), BackgroundTransparency = 0}, Enum.EasingStyle.Back)
tween(Shadow, 0.35, {Size = UDim2.fromOffset(820,570)}, Enum.EasingStyle.Back)
showPage("Overview")
setStatus("Ready • placement recorder idle", Theme.accent2)

-- Install the placement hook once, so the UI can report availability before recording.
installPlaceHook()
task.spawn(runAutomation)

print("[GTD Control Hub v0.4] UI loaded. Macro capture is PlaceUnit-only; no mouse/key/movement capture.")
