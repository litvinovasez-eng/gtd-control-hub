--[[
    GTD CONTROL HUB • DELTA v1.0
    Placement-coordinate macro recorder + replay/difficulty automation + animated UI.

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
    AutoSelectDifficulty = true,
    AutoClaim = false,
    DesiredMap = "Dojo Dynasty",
    DesiredDifficulty = "Impossible",
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

local RecordingPill = make("Frame", {
    Position = UDim2.new(1, -410, 0, 20), Size = UDim2.fromOffset(96, 27),
    BackgroundColor3 = Color3.fromRGB(79, 32, 46), BorderSizePixel = 0,
    Visible = false,
}, Header)
round(RecordingPill, 20)
local RecordingDot = make("Frame", {
    Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(7, 7),
    BackgroundColor3 = Theme.red, BorderSizePixel = 0,
}, RecordingPill)
round(RecordingDot, 10)
local RecordingText = label(RecordingPill, "REC 0", 10, Color3.fromRGB(255, 220, 225), Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -29, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
})

local StatusPill = make("Frame", {
    Position = UDim2.new(1, -300, 0, 20), Size = UDim2.fromOffset(125, 27),
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
    Position = UDim2.new(1, -92, 0, 17), Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = Theme.panel3, Text = "—", TextColor3 = Theme.text,
    Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false,
    BorderSizePixel = 0,
}, Header)
round(Minimize, 9)
local Close = make("TextButton", {
    Position = UDim2.new(1, -16, 0, 17), AnchorPoint = Vector2.new(1,0),
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
    Position = UDim2.fromOffset(15,35), Size = UDim2.new(1,-155,0,36), TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
})
local MacroRecBadge = make("Frame", {
    Position = UDim2.new(1, -126, 0, 13), Size = UDim2.fromOffset(110, 26),
    BackgroundColor3 = Color3.fromRGB(75, 35, 48), BorderSizePixel = 0,
    Visible = false,
}, MacroInfo)
round(MacroRecBadge, 20)
local MacroRecDot = make("Frame", {
    Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = Theme.red, BorderSizePixel = 0,
}, MacroRecBadge)
round(MacroRecDot, 10)
local MacroRecText = label(MacroRecBadge, "REC • LIVE", 9, Color3.fromRGB(255, 220, 225), Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(25, 0), Size = UDim2.new(1, -30, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
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

-- Page: Automation. All controls are scrollable so map + difficulty selectors
-- remain available on smaller screens as well.
local AutoPage = createPage("Automation")
pageTitle(AutoPage, "Automation", "Replay flow, map/difficulty selection and in-match helpers")
local AutoScroll = make("ScrollingFrame", {
    Name = "AutomationScroll",
    Position = UDim2.fromOffset(18, 82), Size = UDim2.new(1, -36, 1, -94),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.accent2,
    CanvasSize = UDim2.fromOffset(0, 540),
}, AutoPage)
AutoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
AutoScroll.ScrollingDirection = Enum.ScrollingDirection.Y

local MapOptions = {
    "Farm Frenzy", "Enchanted Expedition", "Tropical Takedown",
    "Radioactive Rampage", "Graveyard Gauntlet", "Garden Grind",
    "Dojo Dynasty", "Winter Wonderland", "Space Showdown",
}
local DifficultyOptions = {
    "Easy", "Normal", "Hard", "Insane", "Impossible",
    "Apocalypse", "Freezing", "Void", "Hell", "Endless",
}

local MapPickButton, DifficultyPickButton
local mapBox, modeBox
local PickerCard = card(AutoScroll, UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 91), Theme.accent)
label(PickerCard, "NEXT MATCH • MAP & DIFFICULTY", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 9), Size = UDim2.new(1, -26, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
MapPickButton = secondaryButton(PickerCard, "MAP  •  " .. State.DesiredMap .. "  ›", UDim2.fromOffset(12, 34), UDim2.new(0.5, -18, 0, 39), function()
    local idx = 1
    for i, value in ipairs(MapOptions) do if value == State.DesiredMap then idx = i break end end
    idx = idx % #MapOptions + 1
    State.DesiredMap = MapOptions[idx]
    MapPickButton.Text = "MAP  •  " .. State.DesiredMap .. "  ›"
    if mapBox then mapBox.Text = State.DesiredMap end
    setStatus("Next map: " .. State.DesiredMap, Theme.accent2)
end)
DifficultyPickButton = secondaryButton(PickerCard, "DIFFICULTY  •  " .. State.DesiredDifficulty .. "  ›", UDim2.new(0.5, 6, 0, 34), UDim2.new(0.5, -18, 0, 39), function()
    local idx = 1
    for i, value in ipairs(DifficultyOptions) do if value == State.DesiredDifficulty then idx = i break end end
    idx = idx % #DifficultyOptions + 1
    State.DesiredDifficulty = DifficultyOptions[idx]
    DifficultyPickButton.Text = "DIFFICULTY  •  " .. State.DesiredDifficulty .. "  ›"
    if modeBox then modeBox.Text = State.DesiredDifficulty end
    setStatus("Next difficulty: " .. State.DesiredDifficulty, Theme.accent2)
end)
label(PickerCard, "EASY  ·  NORMAL  ·  HARD  ·  INSANE  ·  IMPOSSIBLE  ·  APOCALYPSE  ·  FREEZING  ·  VOID  ·  HELL  ·  ENDLESS", 7, Theme.muted, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -24, 0, 11), TextXAlignment = Enum.TextXAlignment.Left,
})

local AutoRows = {}
local function autoRow(index, titleText, desc, key)
    local _, refresh = createToggle(AutoScroll, titleText, desc, key, UDim2.fromOffset(0, 100 + (index-1)*65))
    AutoRows[key] = refresh
end
autoRow(1, "Auto Skip Waves", "Enable Auto Skip or press Vote Skip when it appears", "AutoSkip")
autoRow(2, "Auto Speed x3", "Open Game Speed if needed, then select x3", "AutoSpeed")
autoRow(3, "Auto Target First", "Select First when the target-priority option is visible", "AutoTargetFirst")
autoRow(4, "Auto Select Map", "Select the configured map during the replay menu", "AutoMode")
autoRow(5, "Auto Replay", "Press Autoplay / Play Again on the results screen", "AutoReplay")
autoRow(6, "Auto Claim Rewards", "Collect visible Claim / Collect rewards", "AutoClaim")
autoRow(7, "Auto Select Difficulty", "Choose the selected difficulty after Autoplay", "AutoSelectDifficulty")

-- Page: Settings.
local SettingsPage = createPage("Settings")
pageTitle(SettingsPage, "Settings", "Edit the map and difficulty labels used by Automation")
local SettingsCard = card(SettingsPage, UDim2.fromOffset(24, 91), UDim2.new(1,-48,0,180))
label(SettingsCard, "MATCH PREFERENCES", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,14), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(SettingsCard, "Map button text", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,43), Size = UDim2.new(1,-30,0,15), TextXAlignment = Enum.TextXAlignment.Left,
})
mapBox = make("TextBox", {
    Position = UDim2.fromOffset(15,61), Size = UDim2.new(1,-30,0,30),
    BackgroundColor3 = Theme.panel3, Text = State.DesiredMap, TextColor3 = Theme.text,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsCard)
round(mapBox, 7)
label(SettingsCard, "Difficulty button text", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,101), Size = UDim2.new(1,-30,0,15), TextXAlignment = Enum.TextXAlignment.Left,
})
modeBox = make("TextBox", {
    Position = UDim2.fromOffset(15,119), Size = UDim2.new(1,-30,0,30),
    BackgroundColor3 = Theme.panel3, Text = State.DesiredDifficulty, TextColor3 = Theme.text,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsCard)
round(modeBox, 7)
connect(mapBox.FocusLost, function() State.DesiredMap = mapBox.Text; MapPickButton.Text = "MAP  •  " .. State.DesiredMap .. "  ›"; setStatus("Map preference updated") end)
connect(modeBox.FocusLost, function() State.DesiredDifficulty = modeBox.Text; DifficultyPickButton.Text = "DIFFICULTY  •  " .. State.DesiredDifficulty .. "  ›"; setStatus("Difficulty preference updated") end)

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
    local count = #State.Placements
    if PlacementCount then PlacementCount.Text = tostring(count) end
    if CountLabel then CountLabel.Text = tostring(count) .. " placements recorded" end
    if RecordingPill then
        RecordingPill.Visible = State.Recording
        RecordingText.Text = "REC " .. tostring(count)
    end
    if MacroRecBadge then
        MacroRecBadge.Visible = State.Recording
        MacroRecText.Text = "REC • " .. tostring(count)
    end
    if RecordBtn then
        RecordBtn.Text = State.Recording and "●  RECORDING — LIVE" or "●  START RECORDING"
    end
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
    RecordBtn.BackgroundColor3 = Theme.red
    tween(RecordBtn, 0.15, {BackgroundColor3 = Color3.fromRGB(185, 45, 70)})
    showPage("Macro Recorder")
    setStatus("● RECORDING PLACEMENTS — place units normally", Theme.red)
end

local function stopRecordingAndSave()
    if not State.Recording then setStatus("Recorder is not active", Theme.amber); return end
    State.Recording = false
    updateMacroCount()
    RecordBtn.BackgroundColor3 = Theme.accent
    saveMacro()
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

-- Visible in-game UI helpers. GTD uses TextButtons and ImageButtons with
-- nested TextLabels, so scan both button classes and their visible label children.
local function normalizeText(textValue)
    return tostring(textValue or ""):lower():gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function isEffectivelyVisible(obj)
    local current = obj
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return true
end

local function getButtonLabels(button)
    local labels = {}
    if button:IsA("TextButton") and button.Text and button.Text ~= "" then
        labels[#labels+1] = normalizeText(button.Text)
    end
    for _, child in ipairs(button:GetDescendants()) do
        if (child:IsA("TextLabel") or child:IsA("TextButton"))
            and child.Text and child.Text ~= "" and isEffectivelyVisible(child) then
            labels[#labels+1] = normalizeText(child.Text)
        end
    end
    return labels
end

local function getGameButtons()
    local list = {}
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("GuiButton") and isEffectivelyVisible(obj)
            and obj.AbsoluteSize.X > 0 and obj.AbsoluteSize.Y > 0
            and not obj:IsDescendantOf(Gui) then
            list[#list+1] = obj
        end
    end
    return list
end

local function activateButton(button)
    if not button or not button.Parent then return false end
    if type(firesignal) == "function" then
        -- GTD button callbacks commonly subscribe to MouseButton1Click.
        local ok = pcall(function() firesignal(button.MouseButton1Click) end)
        if ok then return true end
        ok = pcall(function() firesignal(button.Activated) end)
        if ok then return true end
    end
    local ok = pcall(function() button:Activate() end)
    return ok
end

local AutoLast = {}
local function findGameButton(matchFn)
    for _, button in ipairs(getGameButtons()) do
        for _, textValue in ipairs(getButtonLabels(button)) do
            if matchFn(textValue, button) then return button, textValue end
        end
    end
    return nil
end

local function choiceMatches(textValue, wanted)
    local text = normalizeText(textValue)
    local needle = normalizeText(wanted)
    if text == "" or needle == "" then return false end
    if text == needle then return true end
    if text:sub(1, #needle + 1) == needle .. " " then return true end
    if text:sub(1, #needle + 1) == needle .. ":" then return true end
    if text:sub(1, #needle + 1) == needle .. "(" then return true end
    -- Some GTD selector buttons show e.g. "40 Waves • Impossible".
    local at = text:find(needle, 1, true)
    if at then
        local before = at == 1 and " " or text:sub(at - 1, at - 1)
        local afterIndex = at + #needle
        local after = afterIndex > #text and " " or text:sub(afterIndex, afterIndex)
        if before:match("[%s%p]") and after:match("[%s%p]") then return true end
    end
    return false
end

local function findChoiceButton(wanted)
    return findGameButton(function(textValue)
        return choiceMatches(textValue, wanted)
    end)
end

-- Some GTD builds show the chooser as "Level 1", "Level 2" ... instead
-- of printing the difficulty name on each button. These orders mirror the
-- named Classic difficulty progression. Exact visible names are always tried first.
local MapDifficultyOrder = {
    ["Farm Frenzy"] = {"Easy", "Normal", "Hard", "Insane"},
    ["Enchanted Expedition"] = {"Easy", "Normal", "Hard", "Insane", "Impossible"},
    ["Tropical Takedown"] = {"Easy", "Normal", "Hard", "Insane", "Impossible"},
    ["Radioactive Rampage"] = {"Easy", "Normal", "Hard", "Insane", "Impossible"},
    ["Graveyard Gauntlet"] = {"Easy", "Normal", "Hard", "Insane", "Impossible"},
    ["Garden Grind"] = {"Easy", "Normal", "Hard", "Insane", "Impossible"},
    ["Dojo Dynasty"] = {"Easy", "Normal", "Hard", "Insane", "Impossible", "Apocalypse"},
    ["Winter Wonderland"] = {"Easy", "Normal", "Hard", "Insane", "Impossible", "Apocalypse"},
    ["Space Showdown"] = {"Easy", "Normal", "Hard", "Insane", "Impossible", "Apocalypse"},
}
local MapDifficultyAliases = {
    ["Winter Wonderland"] = {Freezing = 6},
    ["Space Showdown"] = {Void = 6},
}
local ExtendedDifficultyLevels = {
    Hell = 7,
    Endless = 8,
}

local function getLevelNumberForDifficulty(mapName, difficultyName)
    local aliases = MapDifficultyAliases[mapName]
    if aliases and aliases[difficultyName] then return aliases[difficultyName] end
    local order = MapDifficultyOrder[mapName]
    if order then
        for i, name in ipairs(order) do
            if normalizeText(name) == normalizeText(difficultyName) then return i end
        end
    end
    -- Extended difficulties can appear on event/special maps; only select if
    -- the matching Level N button is actually present in the current picker.
    return ExtendedDifficultyLevels[difficultyName]
end

local function findVisibleUiTextContaining(needles)
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if not obj:IsDescendantOf(Gui)
            and (obj:IsA("TextLabel") or obj:IsA("TextButton"))
            and isEffectivelyVisible(obj) then
            local t = normalizeText(obj.Text)
            for _, needle in ipairs(needles) do
                if t:find(normalizeText(needle), 1, true) then return true end
            end
        end
    end
    return false
end

local function autoClick(key, matcher, cooldown, statusText)
    if os.clock() - (AutoLast[key] or 0) < (cooldown or 1.5) then return false end
    local button = findGameButton(matcher)
    if button and activateButton(button) then
        AutoLast[key] = os.clock()
        setStatus(statusText or ("Activated " .. key), Theme.accent2)
        return true
    end
    return false
end

local speedApplied = false
local speedOpenAttemptAt = 0
local speedCycleClicks = 0
local speedStatusAt = 0
local replayStage = nil -- nil | "select_map" | "select_difficulty" | "waiting_match"
local replayStageStarted = 0
local replayClickedAt = 0
local replayLastStatusAt = 0
local replayMapPicked = false
local replayDifficultyPicked = false

local function resetRoundAutomation()
    speedApplied = false
    speedCycleClicks = 0
    AutoLast.first = nil
    AutoLast.skipToggle = nil
    AutoLast.voteSkip = nil
    AutoLast.mapSelected = nil
    AutoLast.difficultySelected = nil
    replayStage = nil
    replayMapPicked = false
    replayDifficultyPicked = false
end

local function runAutoSkip()
    -- Enable a dedicated Auto Skip toggle only when its state explicitly says OFF.
    local offButton = findGameButton(function(t)
        return t == "auto skip: off" or t == "auto skip off" or t == "auto skip (off)"
    end)
    if offButton and AutoLast.skipToggle == nil then
        if activateButton(offButton) then
            AutoLast.skipToggle = true
            setStatus("Auto Skip enabled", Theme.accent2)
            return
        end
    end
    local onButton = findGameButton(function(t)
        return t == "auto skip: on" or t == "auto skip on" or t == "auto skip (on)"
    end)
    if onButton then AutoLast.skipToggle = true end

    -- If this round exposes a vote-skip action, press it once per cooldown.
    autoClick("voteSkip", function(t)
        return t == "skip" or t:find("vote skip", 1, true) ~= nil
            or t:find("skip wave", 1, true) ~= nil
    end, 1.25, "Vote Skip pressed")
end

local function runAutoSpeed()
    if speedApplied then return end

    -- Select the explicit x3 option. This works for TextButtons and nested labels in ImageButtons.
    local direct = findGameButton(function(t)
        return t == "x3" or t == "3x" or t == "3x speed" or t == "speed x3"
            or t == "game speed x3" or t == "game speed: x3" or t == "game speed: 3x"
            or t == "speed: x3" or t == "speed: 3x"
            or t:find("speed x3", 1, true) ~= nil or t:find("speed 3x", 1, true) ~= nil
    end)
    if direct then
        if activateButton(direct) then
            speedApplied = true
            setStatus("Game speed set to x3", Theme.accent2)
        end
        return
    end

    -- Some layouts show the selected speed on the control itself.
    local selected = findGameButton(function(t)
        return (t:find("game speed", 1, true) or t:find("speed:", 1, true))
            and (t:find("x3", 1, true) or t:find("3x", 1, true))
    end)
    if selected then
        speedApplied = true
        setStatus("Game speed already x3", Theme.accent2)
        return
    end

    -- Open the speed picker when its opener is visible. Do not repeatedly spam it.
    local opener = findGameButton(function(t)
        return t == "game speed" or t == "speed" or t == "game speed:" or t == "speed:"
            or t == "game speed: x1" or t == "game speed: 1x"
            or t == "speed: x1" or t == "speed: 1x"
            or t == "game speed x1" or t == "game speed 1x"
    end)
    if opener and os.clock() - speedOpenAttemptAt > 1.5 then
        speedOpenAttemptAt = os.clock()
        if activateButton(opener) then
            setStatus("Opened Game Speed picker — selecting x3", Theme.accent2)
        end
    elseif os.clock() - speedStatusAt > 5 then
        speedStatusAt = os.clock()
        setStatus("Auto Speed: waiting for the visible x3 control", Theme.amber)
    end
end

local function runAutoTargetFirst()
    -- First may be inside the target menu; open that menu once if it is not already visible.
    local first = findChoiceButton("First")
    if first then
        autoClick("first", function(t) return choiceMatches(t, "First") end, 2.0, "Target priority: First")
        return
    end
    autoClick("targetMenu", function(t)
        return t == "target" or t == "targeting" or t == "priority" or t == "target priority"
    end, 6.0, "Opened target-priority menu")
end

local function runAutoClaim()
    autoClick("claim", function(t)
        return t == "claim" or t == "collect" or t == "claim reward" or t == "collect reward"
            or t == "claim rewards" or t == "collect rewards"
    end, 1.8, "Reward claimed")
end

local function runAutoMapSelection()
    local mapNeedle = normalizeText(State.DesiredMap)
    if mapNeedle == "" or AutoLast.mapSelected then return false end
    local button = findChoiceButton(State.DesiredMap)
    if button and activateButton(button) then
        AutoLast.mapSelected = true
        setStatus("Map selected: " .. State.DesiredMap, Theme.accent2)
        return true
    end
    return false
end

local function runAutoDifficultySelection()
    local wanted = State.DesiredDifficulty
    if AutoLast.difficultySelected then return false end

    -- Preferred path: the actual button/child label contains Easy, Impossible, etc.
    local button = findChoiceButton(wanted)
    if button and activateButton(button) then
        AutoLast.difficultySelected = true
        setStatus("Difficulty selected: " .. wanted, Theme.accent2)
        return true
    end

    -- Fallback for GTD versions whose buttons are numbered Level 1..N.
    local levelNumber = getLevelNumberForDifficulty(State.DesiredMap, wanted)
    if levelNumber then
        local levelButton = findChoiceButton("Level " .. tostring(levelNumber))
        if levelButton and activateButton(levelButton) then
            AutoLast.difficultySelected = true
            setStatus("Difficulty " .. wanted .. " selected via Level " .. tostring(levelNumber), Theme.accent2)
            return true
        end
    end
    return false
end

local function isReplayControlText(t)
    return t == "autoplay" or t == "auto play" or t == "play again"
        or t == "play again!" or t == "replay" or t == "next match"
        or t:find("autoplay", 1, true) ~= nil
end

local function hasMatchHud()
    -- The result overlay can coexist with HUD controls; never mistake the
    -- still-visible Autoplay button for a newly-started match.
    if findGameButton(isReplayControlText) then return false end
    if findGameButton(function(t)
        return t == "x1" or t == "x2" or t == "x3" or t == "auto skip"
            or t == "game speed" or t:find("wave ", 1, true) ~= nil
    end) then return true end
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if not obj:IsDescendantOf(Gui) and obj:IsA("TextLabel") and isEffectivelyVisible(obj) then
            local textValue = normalizeText(obj.Text)
            if textValue:match("wave%s*[:%-]?%s*%d+") then return true end
        end
    end
    return false
end

local function runAutoReplayFlow()
    local now = os.clock()
    if replayStage == nil then
        -- In the current GTD result flow the button is usually named Autoplay.
        local button = findGameButton(isReplayControlText)
        if button and now - replayClickedAt > 8 then
            if activateButton(button) then
                replayClickedAt = now
                replayStageStarted = now
                replayStage = State.AutoMode and "select_map"
                    or (State.AutoSelectDifficulty and "select_difficulty" or "waiting_match")
                replayMapPicked = false
                replayDifficultyPicked = false
                AutoLast.mapSelected = nil
                AutoLast.difficultySelected = nil
                speedApplied = false
                speedCycleClicks = 0
                setStatus("Autoplay pressed — continuing replay flow", Theme.accent2)
            end
        end
        return
    end

    if replayStage == "waiting_match" then
        if hasMatchHud() then
            resetRoundAutomation()
            setStatus("New match detected", Theme.accent2)
        elseif now - replayStageStarted > 35 then
            replayStage = nil
            setStatus("Replay clicked, but no new match HUD was detected", Theme.amber)
        end
        return
    end

    if replayStage == "select_map" then
        if runAutoMapSelection() then
            replayMapPicked = true
            replayStage = State.AutoSelectDifficulty and "select_difficulty" or "waiting_match"
            replayStageStarted = now
            return
        end
        if now - replayStageStarted > 8 then
            -- A replay can retain the previous map and show only the difficulty picker.
            replayStage = State.AutoSelectDifficulty and "select_difficulty" or "waiting_match"
            replayStageStarted = now
        elseif now - replayLastStatusAt > 3 then
            replayLastStatusAt = now
            setStatus("Replay flow: waiting for map option " .. State.DesiredMap, Theme.amber)
        end
        return
    end

    if replayStage == "select_difficulty" then
        if not State.AutoSelectDifficulty then
            replayStage = "waiting_match"
            replayStageStarted = now
            return
        end
        if runAutoDifficultySelection() then
            replayDifficultyPicked = true
            replayStage = "waiting_match"
            replayStageStarted = now
            speedApplied = false
            speedCycleClicks = 0
            return
        end
        if hasMatchHud() then
            -- Some autoplay flows start instantly and skip the picker.
            replayStage = "waiting_match"
            replayStageStarted = now
            return
        end
        if now - replayStageStarted > 18 then
            local wanted = State.DesiredDifficulty
            local visible = {}
            for _, name in ipairs(DifficultyOptions) do
                if findChoiceButton(name) then visible[#visible+1] = name end
            end
            local numbered = {}
            for level = 1, 10 do
                if findChoiceButton("Level " .. tostring(level)) then numbered[#numbered+1] = "Level " .. tostring(level) end
            end
            replayStage = nil
            local suffix = #visible > 0 and (". Visible: " .. table.concat(visible, ", ")) or ""
            if #numbered > 0 then suffix = suffix .. ". Numbered options: " .. table.concat(numbered, ", ") end
            if #visible == 0 and #numbered == 0 then suffix = ". No difficulty buttons were detected" end
            setStatus("Difficulty not found: " .. wanted .. suffix, Theme.amber)
            return
        end
        if now - replayLastStatusAt > 3 then
            replayLastStatusAt = now
            setStatus("Waiting for " .. State.DesiredDifficulty .. " selector (name / Level N)", Theme.amber)
        end
    end
end

local function runAutomation()
    while Gui.Parent do
        task.wait(0.25)
        if State.AutoReplay then runAutoReplayFlow() end
        if State.AutoSkip then runAutoSkip() end
        if State.AutoSpeed then runAutoSpeed() end
        if State.AutoTargetFirst then runAutoTargetFirst() end
        if State.AutoMode and replayStage == nil then
            if hasVisibleUiTextContaining({"choose map", "select map", "pick a map"}) then
                runAutoMapSelection()
            end
        end
        if State.AutoSelectDifficulty and replayStage == nil then
            local levelPickerVisible = hasVisibleUiTextContaining({"choose level", "choose difficulty", "select difficulty", "select level"})
            if levelPickerVisible then
                runAutoDifficultySelection()
            else
                AutoLast.difficultySelected = nil
            end
        end
        if State.AutoMode and replayStage == nil then
            local mapPickerVisible = hasVisibleUiTextContaining({"choose map", "select map", "pick a map"})
            if not mapPickerVisible then AutoLast.mapSelected = nil end
        end
        if State.AutoClaim then runAutoClaim() end
    end
end

-- Minimize, close, drag and page controls.
local minimized = false
local function setMinimized(value)
    minimized = value
    local goal = minimized and UDim2.fromOffset(800,66) or UDim2.fromOffset(800,550)
    tween(Main, 0.25, {Size = goal})
    tween(Shadow, 0.25, {Size = minimized and UDim2.fromOffset(820,76) or UDim2.fromOffset(820,570)})
    Sidebar.Visible = not minimized
    Content.Visible = not minimized
    Minimize.Text = minimized and "□" or "—"
end
connect(Minimize.Activated, function() setMinimized(not minimized) end)
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
        if not Main.Visible then
            Main.Visible = true
            Shadow.Visible = true
            setMinimized(false)
        elseif minimized then
            setMinimized(false)
        else
            Main.Visible = false
            Shadow.Visible = false
        end
    end
end)

-- Persistent placement-recording indicator in the header and Macro Recorder card.
task.spawn(function()
    while Gui.Parent do
        if State.Recording then
            tween(RecordingDot, 0.32, {BackgroundTransparency = 0.72})
            tween(MacroRecDot, 0.32, {BackgroundTransparency = 0.72})
            task.wait(0.34)
            tween(RecordingDot, 0.32, {BackgroundTransparency = 0})
            tween(MacroRecDot, 0.32, {BackgroundTransparency = 0})
            task.wait(0.34)
        else
            RecordingPill.Visible = false
            MacroRecBadge.Visible = false
            task.wait(0.25)
        end
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

print("[GTD Control Hub v1.0] Loaded. Placement-only macros; replay/difficulty automation active.")
