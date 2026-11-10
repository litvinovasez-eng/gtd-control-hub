--[[
    GTD CONTROL HUB • DELTA v1.4
    Placement-coordinate macro recorder + direct GTD remote automation + animated UI.

    Macro design:
      • Records ONLY successful calls to ReplicatedStorage.RemoteFunctions.PlaceUnit.
      • Stores unit key, map-world Vector3 position, yaw and delay between placements.
      • Does NOT record player movement, camera movement, mouse coordinates or keyboard input.
      • Playback invokes PlaceUnit with the stored unit key and world-space placement payload.

    Notes:
      • The exact PlaceUnit remote/payload may change in a future GTD update.
      • Speed and Auto Skip use GTD RemoteEvents; difficulty/replay use RemoteFunctions.
      • Game UI is read only for phase/state detection; no game UI buttons are clicked.
      • Remote names/signatures are source-verified, but still require live in-game validation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
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
for _, oldName in ipairs({"GTDControlHub_Delta", "GTDControlHub_Delta_v04", "GTDControlHub_Delta_v12", "GTDControlHub_Delta_v14"}) do
    local oldUi = PlayerGui:FindFirstChild(oldName)
    if oldUi then pcall(function() oldUi:Destroy() end) end
end

local Theme = {
    bg = Color3.fromRGB(6, 9, 24),
    panel = Color3.fromRGB(13, 18, 40),
    panel2 = Color3.fromRGB(18, 27, 57),
    panel3 = Color3.fromRGB(27, 39, 78),
    border = Color3.fromRGB(58, 78, 133),
    text = Color3.fromRGB(241, 246, 255),
    muted = Color3.fromRGB(148, 164, 201),
    accent = Color3.fromRGB(128, 101, 255),
    accent2 = Color3.fromRGB(61, 218, 255),
    green = Color3.fromRGB(58, 214, 164),
    red = Color3.fromRGB(255, 92, 139),
    amber = Color3.fromRGB(255, 193, 92),
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
    AutoReplay = false,
    AutoSelectDifficulty = true,
    SelectedSpeed = 3,
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
    Name = "GTDControlHub_Delta_v14",
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
        ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 24, 66)),
        ColorSequenceKeypoint.new(0.55, Theme.bg),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 38, 62)),
    }),
    Rotation = 25,
}, Main)

-- Animated starfield: subtle drifting stars and occasional shooting-star streaks.
-- The layer is non-interactive and sits behind all controls/cards.
local StarField = make("Frame", {
    Name = "CosmicStarField", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 1,
}, Main)
StarField.ClipsDescendants = true

for i = 1, 34 do
    local size = math.random(2, 4)
    local star = make("Frame", {
        Name = "DriftingStar" .. tostring(i),
        Position = UDim2.fromOffset(math.random(8, 792), math.random(0, 548)),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = (i % 3 == 0) and Theme.accent2 or Color3.fromRGB(210, 223, 255),
        BackgroundTransparency = math.random(25, 65) / 100,
        BorderSizePixel = 0, ZIndex = 1,
    }, StarField)
    round(star, 10)
    task.spawn(function()
        while Gui.Parent and star.Parent do
            local x = math.random(12, 785)
            local y = math.random(-40, 520)
            local travel = math.random(85, 260)
            local duration = math.random(35, 75) / 10
            star.Position = UDim2.fromOffset(x, y)
            star.BackgroundTransparency = math.random(18, 58) / 100
            tween(star, duration, {
                Position = UDim2.fromOffset(x + math.random(-24, 24), y + travel),
                BackgroundTransparency = 1,
            }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
            task.wait(duration)
        end
    end)
end

for i = 1, 2 do
    local streak = make("Frame", {
        Name = "ShootingStar" .. tostring(i), Size = UDim2.fromOffset(76, 2),
        BackgroundColor3 = Theme.accent2, BackgroundTransparency = 1,
        BorderSizePixel = 0, Rotation = 25, ZIndex = 1,
    }, StarField)
    make("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.65, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Color = ColorSequence.new(Theme.accent2, Color3.fromRGB(194, 164, 255)),
    }, streak)
    task.spawn(function()
        while Gui.Parent and streak.Parent do
            task.wait(math.random(4, 9))
            streak.Position = UDim2.fromOffset(math.random(130, 730), math.random(-20, 220))
            streak.BackgroundTransparency = 0.18
            tween(streak, 0.95, {
                Position = UDim2.fromOffset(streak.Position.X.Offset - 180, streak.Position.Y.Offset + 120),
                BackgroundTransparency = 1,
            }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        end
    end)
end

-- Header.
local Header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 66),
    BackgroundColor3 = Theme.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0,
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
label(Header, "DELTA  •  COSMIC CONTROL SUITE", 9, Theme.muted, Enum.Font.GothamMedium, {
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
    BackgroundColor3 = Color3.fromRGB(10, 15, 34), BackgroundTransparency = 0.08, BorderSizePixel = 0,
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

local function createToggle(parent, titleText, description, key, position, onChanged)
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
        if onChanged then
            local ok, err = pcall(onChanged, State[key])
            if not ok then setStatus(titleText .. " error: " .. tostring(err), Theme.red) end
        end
    end)
    refresh(false)
    return row, refresh
end

-- Page: Overview.
local Overview = createPage("Overview")
pageTitle(Overview, "Welcome back", "A cosmic command deck for Garden Tower Defense")
local Hero = card(Overview, UDim2.fromOffset(24, 91), UDim2.new(1, -48, 0, 130), Theme.accent)
make("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(42,53,91), Color3.fromRGB(24,70,75)), Rotation = 15}, Hero)
label(Hero, "STRATEGY AUTOMATION", 9, Color3.fromRGB(174,197,255), Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(18, 18), Size = UDim2.new(1,-36,0,17), TextXAlignment = Enum.TextXAlignment.Left,
})
label(Hero, "Defend beyond the stars.", 22, Theme.text, Enum.Font.GothamBold, {
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

-- Page: Automation. Every game action below is sent through GTD remotes.
local AutoPage = createPage("Automation")
pageTitle(AutoPage, "Automation", "Direct GTD remote calls • no game-screen clicking")
local AutoScroll = make("ScrollingFrame", {
    Name = "AutomationScroll",
    Position = UDim2.fromOffset(18, 82), Size = UDim2.new(1, -36, 1, -94),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.accent2,
    CanvasSize = UDim2.fromOffset(0, 620),
}, AutoPage)
AutoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
AutoScroll.ScrollingDirection = Enum.ScrollingDirection.Y

local DifficultyOptions = {"Easy", "Normal", "Hard", "Insane", "Impossible", "Apocalypse"}
local DifficultyPickButton
local modeBox
local PickerCard = card(AutoScroll, UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 78), Theme.accent)
label(PickerCard, "NEXT DIFFICULTY VOTE", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 9), Size = UDim2.new(1, -26, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
DifficultyPickButton = secondaryButton(PickerCard, "DIFFICULTY  •  " .. State.DesiredDifficulty .. "  ›", UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 34), function()
    local idx = 1
    for i, value in ipairs(DifficultyOptions) do if value == State.DesiredDifficulty then idx = i break end end
    idx = idx % #DifficultyOptions + 1
    State.DesiredDifficulty = DifficultyOptions[idx]
    DifficultyPickButton.Text = "DIFFICULTY  •  " .. State.DesiredDifficulty .. "  ›"
    if modeBox then modeBox.Text = State.DesiredDifficulty end
    setStatus("Difficulty vote target: " .. State.DesiredDifficulty, Theme.accent2)
end)

local AutoRows = {}
local function autoRow(y, titleText, desc, key, callback)
    local _, refresh = createToggle(AutoScroll, titleText, desc, key, UDim2.fromOffset(0, y), callback)
    AutoRows[key] = refresh
end
autoRow(88, "Auto Skip Waves", "SetAutoSkip RemoteEvent: true / false", "AutoSkip", function(enabled)
    if enabled then
        -- The loop applies this when the next live round is available.
        State.__AutoSkipNeedsApply = true
        setStatus("Auto Skip armed; sending SetAutoSkip(true) in the active round", Theme.accent2)
    else
        local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local remote = remotes and remotes:FindFirstChild("SetAutoSkip")
        if remote and remote:IsA("RemoteEvent") then
            local ok, err = pcall(function() remote:FireServer(false) end)
            if ok then setStatus("SetAutoSkip(false) sent", Theme.accent2)
            else setStatus("SetAutoSkip failed: " .. tostring(err), Theme.red) end
        else
            setStatus("RemoteEvents.SetAutoSkip not found", Theme.red)
        end
    end
end)
autoRow(153, "Auto Speed", "Automatically applies your selected 2× / 3× speed", "AutoSpeed", function(enabled)
    if enabled then State.__SpeedNeedsApply = true end
end)

local SpeedCard = card(AutoScroll, UDim2.fromOffset(0, 218), UDim2.new(1, -10, 0, 58), Theme.accent2)
label(SpeedCard, "GAME SPEED", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 7), Size = UDim2.new(0.45, -13, 0, 15), TextXAlignment = Enum.TextXAlignment.Left,
})
local Speed2Button, Speed3Button
Speed2Button = secondaryButton(SpeedCard, "2×", UDim2.new(0.5, -74, 0, 9), UDim2.fromOffset(62, 38), function()
    State.SelectedSpeed = 2
    Speed2Button.BackgroundColor3 = Theme.accent
    Speed3Button.BackgroundColor3 = Theme.panel3
    State.__SpeedNeedsApply = true
    setStatus("Selected speed: 2× • applying in the active round" .. (State.AutoSpeed and " (auto reapply ON)" or ""), Theme.accent2)
end)
Speed3Button = secondaryButton(SpeedCard, "3×", UDim2.new(0.5, 12, 0, 9), UDim2.fromOffset(62, 38), function()
    State.SelectedSpeed = 3
    Speed3Button.BackgroundColor3 = Theme.accent
    Speed2Button.BackgroundColor3 = Theme.panel3
    State.__SpeedNeedsApply = true
    setStatus("Selected speed: 3× • applying in the active round" .. (State.AutoSpeed and " (auto reapply ON)" or ""), Theme.accent2)
end)
Speed2Button.BackgroundColor3 = State.SelectedSpeed == 2 and Theme.accent or Theme.panel3
Speed3Button.BackgroundColor3 = State.SelectedSpeed == 3 and Theme.accent or Theme.panel3

autoRow(286, "Auto Difficulty", "Votes with PlaceDifficultyVote when the vote phase opens", "AutoSelectDifficulty", function(enabled)
    if enabled then State.__DifficultyNeedsApply = true end
end)
autoRow(351, "Auto Replay", "Calls RestartGame with the active Context when the round ends", "AutoReplay", function(enabled)
    if enabled then State.__ReplayNeedsApply = true end
end)

local SkipWaveCard = card(AutoScroll, UDim2.fromOffset(0, 416), UDim2.new(1, -10, 0, 58), Theme.accent)
label(SkipWaveCard, "ONE-TIME ACTION", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 7), Size = UDim2.new(0.45, -13, 0, 15), TextXAlignment = Enum.TextXAlignment.Left,
})
local SkipWaveButton = secondaryButton(SkipWaveCard, "SKIP CURRENT WAVE  →", UDim2.new(1, -190, 0, 9), UDim2.fromOffset(178, 38), function()
    local remotes = ReplicatedStorage:FindFirstChild("RemoteFunctions")
    local remote = remotes and remotes:FindFirstChild("SkipWave")
    if not remote or not remote:IsA("RemoteFunction") then
        setStatus("RemoteFunctions.SkipWave not found", Theme.red)
        return
    end
    local ok, result = pcall(function() return remote:InvokeServer() end)
    if ok then setStatus("SkipWave InvokeServer sent" .. (result == nil and "" or (" • " .. tostring(result))), Theme.accent2)
    else setStatus("SkipWave failed: " .. tostring(result), Theme.red) end
end)

-- Context-aware utility commands. Each action invokes a confirmed GTD remote directly.
local QuickActionCard = card(AutoScroll, UDim2.fromOffset(0, 484), UDim2.new(1, -10, 0, 146), Theme.accent)
label(QuickActionCard, "COMMAND DECK", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 9), Size = UDim2.new(1, -26, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
label(QuickActionCard, "One-shot server actions for your deployed units", 8, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(13, 27), Size = UDim2.new(1, -26, 0, 14), TextXAlignment = Enum.TextXAlignment.Left,
})

local function getEntitiesForQuickActions()
    local contexts = Workspace:FindFirstChild("Contexts")
    if contexts then
        local best, bestScore = nil, -1
        for _, context in ipairs(contexts:GetChildren()) do
            local entities = context:FindFirstChild("Entities")
            if entities then
                local score = 0
                local suffix = tonumber(context.Name:match("(%d+)$"))
                if suffix then score = suffix * 1000 end
                local startTime = context:GetAttribute("GameStartTime")
                if type(startTime) == "number" then score = math.max(score, startTime) end
                local voteEnd = context:GetAttribute("DifficultyVoteEnd")
                if type(voteEnd) == "number" then score = math.max(score, voteEnd) end
                local endTime = context:GetAttribute("GameEndTime")
                local baseHp = context:GetAttribute("BaseHP_1")
                if endTime == nil and (baseHp == nil or baseHp > 0) then score = score + 10000000000 end
                if score > bestScore then best, bestScore = entities, score end
            end
        end
        if best then return best end
    end
    local map = Workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("Entities") or nil
end

local function getDeployedUnitIds()
    local entities = getEntitiesForQuickActions()
    if not entities then return {}, "Active Context.Entities not found" end
    local ids, seen = {}, {}
    local function addId(model)
        local id = model:GetAttribute("ID")
        if type(id) ~= "number" then
            local inner = model:FindFirstChild(model.Name)
            id = inner and inner:GetAttribute("ID")
        end
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    for _, model in ipairs(entities:GetChildren()) do
        if string.sub(model.Name, 1, 5) == "unit_" then addId(model) end
    end
    return ids
end

local getRemote -- forward declaration; callbacks are created before the automation helpers below.
local function runUnitRemote(remoteName, description)
    local remote = getRemote("RemoteFunctions", remoteName, "RemoteFunction")
    if not remote then
        setStatus("RemoteFunctions." .. remoteName .. " not found", Theme.red)
        return
    end
    local ids, err = getDeployedUnitIds()
    if err then setStatus(err, Theme.red); return end
    if #ids == 0 then setStatus("No deployed unit IDs found in active Context", Theme.amber); return end
    local sent, failed = 0, 0
    for _, id in ipairs(ids) do
        local ok, result = pcall(function() return remote:InvokeServer(id) end)
        if ok and result ~= false then sent = sent + 1 else failed = failed + 1 end
        task.wait(0.08)
    end
    setStatus(description .. ": " .. tostring(sent) .. " sent / " .. tostring(failed) .. " rejected", failed == 0 and Theme.green or Theme.amber)
end

secondaryButton(QuickActionCard, "SELL ALL", UDim2.fromOffset(13, 53), UDim2.new(0.31, -8, 0, 34), function()
    local remote = getRemote("RemoteFunctions", "SellAll", "RemoteFunction")
    if not remote then setStatus("RemoteFunctions.SellAll not found", Theme.red); return end
    local ok, result = pcall(function() return remote:InvokeServer() end)
    if ok and result ~= false then setStatus("SellAll request sent", Theme.green)
    else setStatus("SellAll failed: " .. tostring(result), Theme.red) end
end)
secondaryButton(QuickActionCard, "UPGRADE ALL ONCE", UDim2.new(0.34, 0, 0, 53), UDim2.new(0.33, -8, 0, 34), function()
    runUnitRemote("UpgradeUnit", "Upgrade all once")
end)
secondaryButton(QuickActionCard, "USE ALL ABILITIES", UDim2.new(0.68, -2, 0, 53), UDim2.new(0.32, -11, 0, 34), function()
    runUnitRemote("ActivateUnitAbility", "Ability requests")
end)
label(QuickActionCard, "Actions call SellAll(), UpgradeUnit(gameId), or ActivateUnitAbility(gameId).", 8, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(13, 98), Size = UDim2.new(1, -26, 0, 30),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
})

local ApiCard = card(AutoScroll, UDim2.fromOffset(0, 640), UDim2.new(1, -10, 0, 150), Theme.accent2)
label(ApiCard, "DIRECT REMOTE API STATUS", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 9), Size = UDim2.new(1, -26, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
local ApiStatusText = label(ApiCard, "Click Check Remotes to inspect the live RemoteEvents / RemoteFunctions.\nGame GUI is never clicked by this panel.", 8, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(13, 34), Size = UDim2.new(1, -26, 0, 78),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
})
ApiStatusText.TextWrapped = true
local CheckRemotesButton = secondaryButton(ApiCard, "CHECK REMOTES", UDim2.new(1, -142, 1, -39), UDim2.fromOffset(128, 28), function() end)

local UnsupportedCard = card(AutoScroll, UDim2.fromOffset(0, 800), UDim2.new(1, -10, 0, 86), Theme.panel2)
label(UnsupportedCard, "NOT FAKED / NOT CLICKED", 9, Theme.amber, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(13, 9), Size = UDim2.new(1, -26, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
label(UnsupportedCard, "Target First: mode IDs still need live verification. Map selection / Auto Claim: current lobby arguments and claim remote are not confirmed. They are deliberately not simulated with screen clicks.", 8, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(13, 31), Size = UDim2.new(1, -26, 0, 47),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
})

-- Page: Settings.
local SettingsPage = createPage("Settings")
pageTitle(SettingsPage, "Settings", "Difficulty preference and macro behavior")
local SettingsCard = card(SettingsPage, UDim2.fromOffset(24, 91), UDim2.new(1,-48,0,150))
label(SettingsCard, "MATCH PREFERENCES", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,14), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(SettingsCard, "Difficulty sent to PlaceDifficultyVote", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,43), Size = UDim2.new(1,-30,0,15), TextXAlignment = Enum.TextXAlignment.Left,
})
modeBox = make("TextBox", {
    Position = UDim2.fromOffset(15,66), Size = UDim2.new(1,-30,0,32),
    BackgroundColor3 = Theme.panel3, Text = State.DesiredDifficulty, TextColor3 = Theme.text,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsCard)
round(modeBox, 7)
connect(modeBox.FocusLost, function()
    local wanted = tostring(modeBox.Text or "")
    for _, option in ipairs(DifficultyOptions) do
        if string.lower(wanted) == string.lower(option) then
            State.DesiredDifficulty = option
            DifficultyPickButton.Text = "DIFFICULTY  •  " .. option .. "  ›"
            setStatus("Difficulty target updated: " .. option, Theme.accent2)
            return
        end
    end
    modeBox.Text = State.DesiredDifficulty
    setStatus("Unsupported difficulty name; choose Easy through Apocalypse", Theme.amber)
end)

local InfoCard = card(SettingsPage, UDim2.fromOffset(24, 257), UDim2.new(1,-48,0,156), Theme.accent)
label(InfoCard, "ABOUT THIS BUILD", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,13), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(InfoCard, "Speed → ChangeTickSpeed:FireServer(2 / 3)\nAuto Skip → SetAutoSkip:FireServer(true / false)\nDifficulty → PlaceDifficultyVote:InvokeServer(context, id)\nReplay → RestartGame:InvokeServer(context, false)\nQuick actions → SellAll / UpgradeUnit / ActivateUnitAbility.", 9, Theme.muted, Enum.Font.Gotham, {
    Position = UDim2.fromOffset(15,40), Size = UDim2.new(1,-30,0,105),
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
-- Direct GTD remote automation. GUI elements are read only for phase/state detection.
local DifficultyRemoteIds = {
    Easy = "dif_easy",
    Normal = "dif_normal",
    Hard = "dif_hard",
    Insane = "dif_insane",
    Impossible = "dif_impossible",
    Apocalypse = "dif_apocalypse",
}

getRemote = function(folderName, remoteName, expectedClass)
    local folder = ReplicatedStorage:FindFirstChild(folderName)
    local remote = folder and folder:FindFirstChild(remoteName)
    if remote and (not expectedClass or remote:IsA(expectedClass)) then return remote end
    return nil
end

local function getActiveContext()
    local contexts = Workspace:FindFirstChild("Contexts")
    if not contexts then return nil end
    local children = contexts:GetChildren()
    if #children == 0 then return nil end
    if #children == 1 then return children[1] end

    local best, bestScore = nil, -1
    for _, context in ipairs(children) do
        if context:IsA("Folder") or context:FindFirstChild("Entities")
            or context:GetAttribute("Config") ~= nil or context:GetAttribute("RunId") ~= nil then
            local score = 0
            local suffix = tonumber(context.Name:match("(%d+)$"))
            if suffix then score = suffix * 1000 end
            local startTime = context:GetAttribute("GameStartTime")
            if type(startTime) == "number" then score = math.max(score, startTime) end
            local voteEnd = context:GetAttribute("DifficultyVoteEnd")
            if type(voteEnd) == "number" then score = math.max(score, voteEnd) end
            local endTime = context:GetAttribute("GameEndTime")
            local baseHp = context:GetAttribute("BaseHP_1")
            if endTime == nil and (baseHp == nil or baseHp > 0) then
                score = score + 10000000000
            end
            if score > bestScore then bestScore, best = score, context end
        end
    end
    return best or children[#children]
end

local function getGameAttribute(attributeName, context)
    context = context or getActiveContext()
    local value = context and context:GetAttribute(attributeName)
    if value == nil then value = Workspace:GetAttribute(attributeName) end
    return value
end

local function getRoundKey(context)
    local startTime = getGameAttribute("GameStartTime", context)
    if context then return context:GetFullName() .. ":" .. tostring(startTime or "no-start-time") end
    return "workspace:" .. tostring(startTime or "no-context")
end

local function isInLiveRound(context)
    if context then
        local startTime = context:GetAttribute("GameStartTime")
        if startTime ~= nil then return true end
        if context:FindFirstChild("Entities") then return true end
    end
    local map = Workspace:FindFirstChild("Map")
    if map and map:FindFirstChild("Entities") then return true end
    local gameGui = PlayerGui:FindFirstChild("GameGuiNoInset")
    local screen = gameGui and gameGui:FindFirstChild("Screen")
    local top = screen and screen:FindFirstChild("Top")
    local waveControls = top and top:FindFirstChild("WaveControls")
    return waveControls ~= nil and waveControls.Visible ~= false
end

local function readAutoSkipTextState()
    local gui = PlayerGui:FindFirstChild("GameGuiNoInset")
    local node = gui
    for _, name in ipairs({"Screen", "Top", "WaveControls", "WaveControls", "AutoSkip", "TextLabel"}) do
        node = node and node:FindFirstChild(name)
    end
    local textValue = node and node:IsA("TextLabel") and node.Text or nil
    if not textValue then
        local controls = gui and gui:FindFirstChild("Screen")
        controls = controls and controls:FindFirstChild("Top")
        controls = controls and controls:FindFirstChild("WaveControls")
        local button = controls and controls:FindFirstChild("AutoSkip")
        local title = button and (button:FindFirstChild("Title") or button:FindFirstChild("TextLabel"))
        textValue = title and title:IsA("TextLabel") and title.Text or nil
    end
    if type(textValue) ~= "string" then return nil end
    local lower = string.lower(textValue)
    if lower:find("auto skip: on", 1, true) then return true end
    if lower:find("auto skip: off", 1, true) then return false end
    return nil
end

local function applyGameSpeed(showFeedback)
    local speed = tonumber(State.SelectedSpeed) or 3
    if speed ~= 2 and speed ~= 3 then speed = 3 end
    local remote = getRemote("RemoteEvents", "ChangeTickSpeed", "RemoteEvent")
    if not remote then
        if showFeedback ~= false then setStatus("RemoteEvents.ChangeTickSpeed (RemoteEvent) not found", Theme.red) end
        return false
    end
    local ok, err = pcall(function() remote:FireServer(speed) end)
    if not ok then
        if showFeedback ~= false then setStatus("ChangeTickSpeed failed: " .. tostring(err), Theme.red) end
        return false
    end
    if showFeedback ~= false then setStatus("ChangeTickSpeed(" .. tostring(speed) .. ") sent", Theme.accent2) end
    task.delay(0.65, function()
        if not Gui.Parent then return end
        local actual = tonumber(getGameAttribute("TickSpeed"))
        if actual == speed then
            setStatus("Server state confirmed: " .. tostring(speed) .. "×", Theme.green)
        elseif showFeedback ~= false then
            setStatus(tostring(speed) .. "× request sent; TickSpeed readback=" .. tostring(actual or "unavailable"), Theme.amber)
        end
    end)
    return true
end

local function applyAutoSkip(desired, showFeedback)
    desired = desired == true
    local remote = getRemote("RemoteEvents", "SetAutoSkip", "RemoteEvent")
    if not remote then
        if showFeedback ~= false then setStatus("RemoteEvents.SetAutoSkip (RemoteEvent) not found", Theme.red) end
        return false
    end
    local ok, err = pcall(function() remote:FireServer(desired) end)
    if not ok then
        if showFeedback ~= false then setStatus("SetAutoSkip failed: " .. tostring(err), Theme.red) end
        return false
    end
    if showFeedback ~= false then
        setStatus("SetAutoSkip(" .. tostring(desired) .. ") sent", Theme.accent2)
    end
    task.delay(0.65, function()
        if not Gui.Parent or showFeedback == false then return end
        local actual = readAutoSkipTextState()
        if actual == desired then
            setStatus("Auto Skip server state confirmed: " .. (desired and "ON" or "OFF"), Theme.green)
        elseif actual ~= nil then
            setStatus("Auto Skip request sent, but game reports " .. (actual and "ON" or "OFF"), Theme.amber)
        else
            setStatus("Auto Skip request sent; state readback unavailable", Theme.amber)
        end
    end)
    return true
end

local function isGuiEffectivelyVisible(object)
    local current = object
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return true
end

local function difficultyVoteVisible()
    -- Current GTD builds have used both GUI roots. Check the known paths first.
    for _, rootName in ipairs({"GameGui", "GameGuiNoInset"}) do
        local root = PlayerGui:FindFirstChild(rootName)
        local screen = root and root:FindFirstChild("Screen")
        local middle = screen and screen:FindFirstChild("Middle")
        local vote = middle and middle:FindFirstChild("DifficultyVote")
        if vote and vote:IsA("GuiObject") and isGuiEffectivelyVisible(vote) then
            return true
        end
    end

    -- Fallback for UI nesting changes: locate the visible DifficultyVote container.
    for _, object in ipairs(PlayerGui:GetDescendants()) do
        if object.Name == "DifficultyVote" and object:IsA("GuiObject")
            and isGuiEffectivelyVisible(object) then
            return true
        end
    end
    return false
end

local function difficultyMatches(actual, wanted)
    if actual == wanted then return true end
    if type(actual) == "string" and type(wanted) == "string" then
        local a = string.lower(actual):gsub("^dif_", "")
        local w = string.lower(wanted):gsub("^dif_", "")
        return a == w
    end
    return false
end

local function applyDifficultyVote(context)
    local difficultyId = DifficultyRemoteIds[State.DesiredDifficulty]
    if not difficultyId then
        setStatus("Unsupported difficulty: " .. tostring(State.DesiredDifficulty), Theme.amber)
        return false
    end
    local remote = getRemote("RemoteFunctions", "PlaceDifficultyVote", "RemoteFunction")
    if not remote then
        setStatus("RemoteFunctions.PlaceDifficultyVote not found", Theme.red)
        return false
    end

    context = context or getActiveContext()
    local contextsFolder = Workspace:FindFirstChild("Contexts")
    local ok, result

    -- GTD 1.76.0+ changed the official signature to (level Context, difficulty id).
    -- Older builds used only (difficulty id). Use the Context whenever the new
    -- Context system exists; never silently send the difficulty string in arg #1.
    if context then
        ok, result = pcall(function()
            return remote:InvokeServer(context, difficultyId)
        end)
    elseif contextsFolder then
        setStatus("Waiting for active GTD Context before voting " .. difficultyId, Theme.amber)
        return false
    else
        ok, result = pcall(function()
            return remote:InvokeServer(difficultyId)
        end)
    end

    if not ok then
        setStatus("PlaceDifficultyVote failed: " .. tostring(result), Theme.red)
        return false
    end

    if not context then
        setStatus("PlaceDifficultyVote(" .. difficultyId .. ") sent (legacy API; no Context folder)", Theme.accent2)
        return true
    end

    -- Confirm against the authoritative Context attribute. Returning from InvokeServer
    -- only proves the request did not throw; it does not prove the vote was accepted.
    task.wait(0.35)
    local actual = context:GetAttribute("Difficulty")
    if difficultyMatches(actual, difficultyId) then
        setStatus("GTD confirmed difficulty: " .. State.DesiredDifficulty, Theme.green)
        return true
    end

    setStatus("Vote sent: " .. difficultyId .. " • server Context.Difficulty=" .. tostring(actual or "not updated") .. " • retrying", Theme.amber)
    return false
end

local function gameEndVisible()
    local gameGui = PlayerGui:FindFirstChild("GameGui")
    local screen = gameGui and gameGui:FindFirstChild("Screen")
    local middle = screen and screen:FindFirstChild("Middle")
    local endGui = middle and middle:FindFirstChild("GameEnd")
    return endGui ~= nil and endGui.Visible == true
end

local function isRoundEnded(context)
    local endTime = getGameAttribute("GameEndTime", context)
    if endTime ~= nil and endTime ~= false and endTime ~= 0 then return true end
    return gameEndVisible()
end

local function restartRound(context)
    local remote = getRemote("RemoteFunctions", "RestartGame", "RemoteFunction")
    if not remote then
        setStatus("RemoteFunctions.RestartGame not found", Theme.red)
        return false
    end
    local ok, result = pcall(function()
        if context then return remote:InvokeServer(context, false) end
        return remote:InvokeServer()
    end)
    if not ok then
        setStatus("RestartGame failed: " .. tostring(result), Theme.red)
        return false
    end
    setStatus("RestartGame remote request sent", Theme.accent2)
    return true
end

local function checkRemoteStatus()
    local rows = {}
    local checks = {
        {"RemoteEvents.ChangeTickSpeed", "RemoteEvents", "ChangeTickSpeed", "RemoteEvent"},
        {"RemoteEvents.SetAutoSkip", "RemoteEvents", "SetAutoSkip", "RemoteEvent"},
        {"RemoteEvents.Entity_ChangeTargetingMode", "RemoteEvents", "Entity_ChangeTargetingMode", "RemoteEvent"},
        {"RemoteFunctions.SkipWave", "RemoteFunctions", "SkipWave", "RemoteFunction"},
        {"RemoteFunctions.PlaceDifficultyVote", "RemoteFunctions", "PlaceDifficultyVote", "RemoteFunction"},
        {"RemoteFunctions.RestartGame", "RemoteFunctions", "RestartGame", "RemoteFunction"},
        {"RemoteFunctions.PlaceUnit", "RemoteFunctions", "PlaceUnit", "RemoteFunction"},
        {"RemoteFunctions.UpgradeUnit", "RemoteFunctions", "UpgradeUnit", "RemoteFunction"},
        {"RemoteFunctions.SellUnit", "RemoteFunctions", "SellUnit", "RemoteFunction"},
        {"RemoteFunctions.SellAll", "RemoteFunctions", "SellAll", "RemoteFunction"},
        {"RemoteFunctions.ActivateUnitAbility", "RemoteFunctions", "ActivateUnitAbility", "RemoteFunction"},
    }
    for _, item in ipairs(checks) do
        local remote = getRemote(item[2], item[3], item[4])
        rows[#rows + 1] = (remote and "[OK] " or "[--] ") .. item[1]
    end
    ApiStatusText.Text = table.concat(rows, "\n")
    setStatus("Remote API check completed", Theme.accent2)
end
connect(CheckRemotesButton.Activated, checkRemoteStatus)

local lastRoundKey = nil
local lastSpeedRoundKey = nil
local lastSkipRoundKey = nil
local lastDifficultyVoteKey = nil
local lastReplayRoundKey = nil
local lastSpeedAttemptAt = 0
local lastSkipAttemptAt = 0
local lastDifficultyAttemptAt = 0
local lastReplayAttemptAt = 0

-- Difficulty votes are separate phases. GameStartTime / Context identity can stay
-- unchanged across repeated vote windows, so do not key difficulty by roundKey.
-- Use DifficultyVoteEnd when the game exposes it, plus a visibility-edge counter
-- as a fallback for builds that do not expose that attribute.
local difficultyVoteWasVisible = false
local difficultyVoteWindow = 0
local difficultyVoteAttemptKey = nil
local difficultyVoteAttempts = 0
local MAX_DIFFICULTY_VOTE_ATTEMPTS = 5

local function runAutomation()
    while Gui.Parent do
        task.wait(0.25)
        local context = getActiveContext()
        local roundKey = getRoundKey(context)
        local liveRound = isInLiveRound(context)
        local voteVisible = difficultyVoteVisible()

        if voteVisible and not difficultyVoteWasVisible then
            difficultyVoteWindow = difficultyVoteWindow + 1
        end

        if roundKey ~= lastRoundKey then
            lastRoundKey = roundKey
            lastSpeedRoundKey = nil
            lastSkipRoundKey = nil
            lastReplayRoundKey = nil
        end

        if liveRound and (State.__SpeedNeedsApply or (State.AutoSpeed and lastSpeedRoundKey ~= roundKey))
            and os.clock() - lastSpeedAttemptAt > 2 then
            lastSpeedAttemptAt = os.clock()
            if applyGameSpeed(false) then
                lastSpeedRoundKey = roundKey
                State.__SpeedNeedsApply = false
            end
        end
        if liveRound and State.AutoSkip
            and (State.__AutoSkipNeedsApply or lastSkipRoundKey ~= roundKey)
            and os.clock() - lastSkipAttemptAt > 2 then
            lastSkipAttemptAt = os.clock()
            if applyAutoSkip(true, false) then
                lastSkipRoundKey = roundKey
                State.__AutoSkipNeedsApply = false
            end
        end

        if voteVisible and State.AutoSelectDifficulty then
            local voteEnd = getGameAttribute("DifficultyVoteEnd", context)
            local voteMarker = voteEnd
            if voteMarker == nil then
                voteMarker = getGameAttribute("GameStartTime", context)
            end
            local contextKey = context and context:GetFullName() or "workspace"
            local voteKey = contextKey .. ":vote=" .. tostring(voteMarker or "no-vote-marker")
                .. ":window=" .. tostring(difficultyVoteWindow)
            if voteKey ~= difficultyVoteAttemptKey then
                difficultyVoteAttemptKey = voteKey
                difficultyVoteAttempts = 0
            end
            if voteKey ~= lastDifficultyVoteKey
                and difficultyVoteAttempts < MAX_DIFFICULTY_VOTE_ATTEMPTS
                and os.clock() - lastDifficultyAttemptAt > 0.9 then
                lastDifficultyAttemptAt = os.clock()
                difficultyVoteAttempts = difficultyVoteAttempts + 1
                if applyDifficultyVote(context) then
                    lastDifficultyVoteKey = voteKey
                elseif difficultyVoteAttempts >= MAX_DIFFICULTY_VOTE_ATTEMPTS then
                    setStatus("Difficulty not confirmed after " .. tostring(MAX_DIFFICULTY_VOTE_ATTEMPTS) .. " attempts. Check current vote phase / Context.", Theme.red)
                end
            end
        elseif not voteVisible then
            -- Re-arm for the next vote screen even when the same Context is reused.
            lastDifficultyVoteKey = nil
            difficultyVoteAttemptKey = nil
            difficultyVoteAttempts = 0
        end
        difficultyVoteWasVisible = voteVisible

        if State.AutoReplay and isRoundEnded(context) and lastReplayRoundKey ~= roundKey
            and os.clock() - lastReplayAttemptAt > 5 then
            lastReplayAttemptAt = os.clock()
            if restartRound(context) then lastReplayRoundKey = roundKey end
        end
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
setStatus("Ready • direct GTD remote mode", Theme.accent2)

-- Install the placement hook once, so the UI can report availability before recording.
installPlaceHook()
task.spawn(runAutomation)

print("[GTD Control Hub v1.4] Loaded. Cosmic UI + Context-aware voting + quick remote commands.")
