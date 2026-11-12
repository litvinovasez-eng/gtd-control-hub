--[[
    GTD CONTROL HUB • DELTA v2.2.20
    Placement-coordinate macro recorder + direct GTD remote automation + animated UI.

    Macro design:
      • Records PlaceUnit, SellUnit, SellAll, upgrades and unit abilities.
      • Maps each deployed tower to a stable macro key, then rebinds that key to the new server ID on playback.
      • Stores map-relative placement coordinates and ordered action timestamps.
      • Does NOT record player movement, camera movement, mouse coordinates or keyboard input.
      • Playback uses local GTD RemoteFunctions; no third-party API or key system is loaded.

    Notes:
      • Playback requires the PlaceUnit RemoteFunction and its payload shape to remain compatible with the recorded game build.
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

-- Remove only the leftover key dialog created by the previous third-party GTD API.
for _, child in ipairs(PlayerGui:GetChildren()) do
    if child:IsA("ScreenGui") then
        local isOldGTDKeyDialog = false
        for _, descendant in ipairs(child:GetDescendants()) do
            if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
                and tostring(descendant.Text):find("Key System by tseting-nil", 1, true) then
                isOldGTDKeyDialog = true
                break
            end
        end
        if isOldGTDKeyDialog then pcall(function() child:Destroy() end) end
    end
end

-- Clean up the previous hub completely before creating another instance.
-- New builds store a Cleanup callback that disconnects their event listeners and
-- entity watchers. Older builds only exposed Gui, so fall back to destroying it.
if ENV.__GTD_CONTROL_HUB then
    local previous = ENV.__GTD_CONTROL_HUB
    local cleaned = false
    if type(previous) == "table" and type(previous.Cleanup) == "function" then
        cleaned = pcall(previous.Cleanup)
    end
    if not cleaned then
        pcall(function()
            if typeof(previous) == "Instance" then
                previous:Destroy()
            elseif type(previous) == "table" and previous.Gui then
                previous.Gui:Destroy()
            end
        end)
    end
end
for _, oldName in ipairs({"GTDControlHub_Delta", "GTDControlHub_Delta_v04", "GTDControlHub_Delta_v12", "GTDControlHub_Delta_v14", "GTDControlHub_Delta_v16", "GTDControlHub_Delta_v17", "GTDControlHub_Delta_v18", "GTDControlHub_Delta_v19", "GTDControlHub_Delta_v20", "GTDControlHub_Delta_v21", "GTDControlHub_Delta_v22", "GTDControlHub_Delta_v221", "GTDControlHub_Delta_v222", "GTDControlHub_Delta_v223", "GTDControlHub_Delta_v224", "GTDControlHub_Delta_v225", "GTDControlHub_Delta_v226", "GTDControlHub_Delta_v227", "GTDControlHub_Delta_v228", "GTDControlHub_Delta_v229", "GTDControlHub_Delta_v2210", "GTDControlHub_Delta_v2211", "GTDControlHub_Delta_v2212", "GTDControlHub_Delta_v2213", "GTDControlHub_Delta_v2214", "GTDControlHub_Delta_v2215", "GTDControlHub_Delta_v2216", "GTDControlHub_Delta_v2217", "GTDControlHub_Delta_v2218", "GTDControlHub_Delta_v2219"}) do
    local oldUi = PlayerGui:FindFirstChild(oldName)
    if oldUi then pcall(function() oldUi:Destroy() end) end
end

-- Orion-like violet glass + neon green visual palette. Layout coordinates stay unchanged.
local Theme = {
    bg = Color3.fromRGB(13, 8, 25),
    panel = Color3.fromRGB(23, 14, 42),
    panel2 = Color3.fromRGB(34, 20, 59),
    panel3 = Color3.fromRGB(43, 27, 69),
    border = Color3.fromRGB(132, 79, 174),
    text = Color3.fromRGB(249, 246, 255),
    muted = Color3.fromRGB(169, 158, 190),
    accent = Color3.fromRGB(174, 78, 255),
    accent2 = Color3.fromRGB(72, 255, 166),
    green = Color3.fromRGB(72, 245, 153),
    red = Color3.fromRGB(255, 83, 126),
    amber = Color3.fromRGB(255, 199, 107),
}

local State = {
    Recording = false,
    RecordingArmed = false,
    RecordingRoundKey = nil,
    Playing = false,
    Loop = true,
    PlaybackArmed = false,
    PlaybackTaskId = 0,
    MacroMapId = nil,
    MacroDifficultyId = nil,
    MacroNight = false,
    MacroGameStartTime = nil,
    RoundLive = false,
    CurrentRoundKey = nil,
    ActiveContext = nil,
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
    AllowRecordedSales = true, -- recorded Sell/SellAll actions replay by default; can be disabled in the macro page
}

local Connections = {}
do
    State.ErrorTrace = function(err)
        local message = tostring(err)
        if debug and type(debug.traceback) == "function" then
            local ok, trace = pcall(debug.traceback, message, 2)
            if ok and type(trace) == "string" then return trace end
        end
        return message
    end
    State.ReportRuntimeError = function(scope, err)
        local fullDetail = tostring(err)
        State.LastRuntimeErrorFull = fullDetail
        -- Keep the on-screen status readable. Full traceback remains in the executor
        -- console and State.LastRuntimeErrorFull instead of flooding the UI with lines.
        local firstLine = fullDetail:match("^([^\r\n]+)") or fullDetail
        if #firstLine > 220 then firstLine = string.sub(firstLine, 1, 220) .. "…" end
        local message = "Ошибка [" .. tostring(scope) .. "]: " .. firstLine
        State.LastRuntimeError = message
        warn("[GTD Control Hub v2.2.20] " .. message .. "\n" .. fullDetail)
        local hub = ENV.__GTD_CONTROL_HUB
        if type(hub) == "table" then
            hub.LastRuntimeError = message
            hub.LastRuntimeErrorFull = fullDetail
            if type(hub.SetStatus) == "function" then
                pcall(hub.SetStatus, message, Theme.red)
            end
        end
    end
end

local function connect(signal, callback)
    local c = signal:Connect(function(...)
        local args = table.pack(...)
        local ok, err = xpcall(function()
            callback(table.unpack(args, 1, args.n))
        end, State.ErrorTrace)
        if not ok then State.ReportRuntimeError("event callback", err) end
    end)
    table.insert(Connections, c)
    return c
end

local function make(className, props, parent)
    local obj = Instance.new(className)
    -- Executor environments may wrap pairs()/property proxies differently. Only
    -- string property names are valid for Roblox Instances; ignore numeric keys
    -- rather than aborting the entire UI build before the hub becomes visible.
    if type(props) == "table" then
        for k, v in next, props do
            if type(k) == "string" then
                local ok, err = pcall(function()
                    obj[k] = v
                end)
                if not ok then
                    warn("[GTD Hub UI] Property " .. k .. " on " .. tostring(className) .. " failed: " .. tostring(err))
                end
            else
                warn("[GTD Hub UI] Ignored non-string property key on " .. tostring(className) .. ": " .. tostring(k))
            end
        end
    end
    if parent then
        local ok, err = pcall(function() obj.Parent = parent end)
        if not ok then
            warn("[GTD Hub UI] Parent assignment failed for " .. tostring(className) .. ": " .. tostring(err))
        end
    end
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
local updateDashboard

local function setStatus(text, color)
    State.Status = tostring(text)
    if StatusText then StatusText.Text = State.Status end
    if updateDashboard then updateDashboard() end
    if StatusDot then
        tween(StatusDot, 0.18, {BackgroundColor3 = color or Theme.accent2})
    end
end

local Gui = make("ScreenGui", {
    Name = "GTDControlHub_Delta_v2219",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 99999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)
ENV.__GTD_CONTROL_HUB = {Gui = Gui, State = State, SetStatus = setStatus, Connections = Connections}

-- Soft backdrop and main shell.
local Shadow = make("Frame", {
    Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1200, 800),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.58,
    BorderSizePixel = 0,
}, Gui)
round(Shadow, 20)
local ShadowScale = make("UIScale", {Scale = 0.72}, Shadow)

local Main = make("Frame", {
    Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1180, 780),
    BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.20, BorderSizePixel = 0, ClipsDescendants = true,
}, Gui)
round(Main, 18)
outline(Main, Theme.accent, 0.12, 1.15)
local MainGlow = make("UIStroke", {
    Color = Theme.accent,
    Transparency = 0.84,
    Thickness = 5,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, Main)
-- A UIScale shrinks the whole existing interface uniformly instead of moving controls around.
local MainScale = make("UIScale", {Scale = 0.72}, Main)
local function updateWindowScale()
    local camera = Workspace.CurrentCamera
    local view = camera and camera.ViewportSize
    local scale = 0.72
    if view then
        scale = math.min(0.72, (view.X - 48) / 1180, (view.Y - 48) / 780)
        scale = math.max(0.48, scale)
    end
    MainScale.Scale = scale
    ShadowScale.Scale = scale
end
updateWindowScale()
if Workspace.CurrentCamera then
    connect(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateWindowScale)
end
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    if Workspace.CurrentCamera then
        connect(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateWindowScale)
        updateWindowScale()
    end
end)

local MainGradient = make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 22, 76)),
        ColorSequenceKeypoint.new(0.55, Theme.bg),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 45, 35)),
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
        Position = UDim2.fromOffset(math.random(8, 1172), math.random(0, 778)),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = (i % 3 == 0) and Theme.green or Color3.fromRGB(221, 209, 255),
        BackgroundTransparency = math.random(25, 65) / 100,
        BorderSizePixel = 0, ZIndex = 1,
    }, StarField)
    round(star, 10)
    task.spawn(function()
        while Gui.Parent and star.Parent do
            local x = math.random(12, 1170)
            local y = math.random(-40, 740)
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
        Color = ColorSequence.new(Theme.accent2, Color3.fromRGB(91, 255, 178)),
    }, streak)
    task.spawn(function()
        while Gui.Parent and streak.Parent do
            task.wait(math.random(4, 9))
            streak.Position = UDim2.fromOffset(math.random(130, 1100), math.random(-20, 330))
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
    Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -76, 0, 68),
    BackgroundColor3 = Theme.panel, BackgroundTransparency = 1, BorderSizePixel = 0,
}, Main)
local HeaderGrad = make("UIGradient", {
    Color = ColorSequence.new(Theme.panel, Color3.fromRGB(49, 27, 73)),
    Rotation = 0,
}, Header)

local BrandMark = make("Frame", {
    Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(38, 38),
    BackgroundColor3 = Theme.accent, BorderSizePixel = 0,
}, Header)
round(BrandMark, 12)
BrandMark.Visible = false
make("UIGradient", {
    Color = ColorSequence.new(Theme.accent, Theme.accent2), Rotation = 35,
}, BrandMark)
label(BrandMark, "G", 22, Color3.new(1,1,1), Enum.Font.GothamBlack, {
    Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
})

local HeaderBrandTitle = label(Header, "GTD CONTROL HUB", 16, Theme.text, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(70, 13), Size = UDim2.fromOffset(240, 22),
    TextXAlignment = Enum.TextXAlignment.Left,
})
local HeaderBrandSubtitle = label(Header, "DELTA  •  COSMIC CONTROL SUITE", 9, Theme.muted, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(71, 36), Size = UDim2.fromOffset(260, 16),
    TextXAlignment = Enum.TextXAlignment.Left,
})
HeaderBrandTitle.Visible = false
HeaderBrandSubtitle.Visible = false

local RecordingPill = make("Frame", {
    Position = UDim2.new(1, -350, 0, 20), Size = UDim2.fromOffset(96, 27),
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
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})

local StatusPill = make("Frame", {
    Position = UDim2.new(1, -250, 0, 20), Size = UDim2.fromOffset(152, 27),
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
    Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(72, 30, 52),
    Text = "×", TextColor3 = Theme.red, Font = Enum.Font.GothamBold,
    TextSize = 19, AutoButtonColor = false, BorderSizePixel = 0,
}, Header)
round(Close, 9)

-- Sidebar and content region.
local Sidebar = make("Frame", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 76, 1, 0),
    BackgroundColor3 = Color3.fromRGB(14, 9, 27), BackgroundTransparency = 0.14, BorderSizePixel = 0,
}, Main)
local SideLine = make("Frame", {
    Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = Theme.border, BackgroundTransparency = 0.3, BorderSizePixel = 0,
}, Sidebar)
local RailStatusDot = make("Frame", {Position = UDim2.fromOffset(33, 26), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Theme.green, BorderSizePixel = 0}, Sidebar)
round(RailStatusDot, 10)
local RailLogo = make("Frame", {Position = UDim2.fromOffset(14, 52), Size = UDim2.fromOffset(48, 42), BackgroundColor3 = Theme.panel2, BackgroundTransparency = 0.12, BorderSizePixel = 0}, Sidebar)
round(RailLogo, 12)
outline(RailLogo, Theme.accent, 0.38, 1)
label(RailLogo, "✦", 22, Theme.accent2, Enum.Font.GothamBold, {Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center})

local Content = make("Frame", {
    Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -76, 1, 0),
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
    {name="Overview", icon="▦"},
    {name="Macro Recorder", icon="◉"},
    {name="Automation", icon="⚡"},
    {name="Settings", icon="⚙"},
}
for i, info in ipairs(navInfo) do
    local button = make("TextButton", {
        Position = UDim2.fromOffset(12, 112 + (i-1)*60), Size = UDim2.fromOffset(52, 48),
        BackgroundColor3 = Color3.fromRGB(25, 15, 42), Text = "", BorderSizePixel = 0,
        AutoButtonColor = false,
    }, Sidebar)
    round(button, 9)
    local bar = make("Frame", {
        Name = "ActiveBar", Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(3, 32),
        BackgroundColor3 = Theme.accent2, BackgroundTransparency = 1, BorderSizePixel = 0,
    }, button)
    round(bar, 4)
    label(button, info.icon, 19, Theme.accent2, Enum.Font.GothamBold, {
        Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
    })
    NavButtons[info.name] = button
    connect(button.Activated, function() showPage(info.name) end)
    connect(button.MouseEnter, function()
        if currentPage ~= info.name then tween(button, 0.12, {BackgroundColor3 = Theme.panel2}) end
    end)
    connect(button.MouseLeave, function()
        if currentPage ~= info.name then tween(button, 0.12, {BackgroundColor3 = Color3.fromRGB(25, 15, 42)}) end
    end)
end

local function pageTitle(parent, titleText, subtitle)
    label(parent, titleText, 21, Theme.text, Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(24, 20), Size = UDim2.new(1, -250, 0, 32),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    label(parent, subtitle, 10, Theme.muted, Enum.Font.Gotham, {
        Position = UDim2.fromOffset(25, 54), Size = UDim2.new(1, -250, 0, 18),
        TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function card(parent, pos, size, accent)
    local f = make("Frame", {
        Position = pos, Size = size, BackgroundColor3 = Theme.panel,
        BackgroundTransparency = 0.20, BorderSizePixel = 0,
    }, parent)
    round(f, 13)
    make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 27, 73)),
            ColorSequenceKeypoint.new(0.52, Theme.panel),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 39, 42)),
        }),
        Rotation = 12,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.12),
            NumberSequenceKeypoint.new(0.5, 0.05),
            NumberSequenceKeypoint.new(1, 0.16),
        }),
    }, f)
    make("UIStroke", {
        Color = accent or Theme.accent,
        Transparency = 0.88,
        Thickness = 4,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, f)
    outline(f, accent or Theme.border, 0.20, 1.1)
    return f
end

local function primaryButton(parent, textValue, pos, size, color, callback)
    local b = make("TextButton", {
        Position = pos, Size = size, BackgroundColor3 = color or Theme.accent, BackgroundTransparency = 0.08,
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
    make("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(53, 31, 78), Color3.fromRGB(26, 49, 45)),
        Rotation = 0,
    }, b)
    local buttonStroke = outline(b, Theme.accent, 0.28, 1)
    make("UIStroke", {Color = Theme.green, Transparency = 0.93, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, b)
    connect(b.MouseEnter, function()
        tween(b, 0.12, {BackgroundColor3 = Color3.fromRGB(69, 41, 96)})
        if buttonStroke then tween(buttonStroke, 0.12, {Transparency = 0.05}) end
    end)
    connect(b.MouseLeave, function()
        tween(b, 0.12, {BackgroundColor3 = Theme.panel3})
        if buttonStroke then tween(buttonStroke, 0.12, {Transparency = 0.28}) end
    end)
    connect(b.Activated, callback)
    return b
end

local function createToggle(parent, titleText, description, key, position, onChanged)
    local row = make("Frame", {
        Position = position, Size = UDim2.new(1, -28, 0, 59),
        BackgroundColor3 = Theme.panel, BackgroundTransparency = 0.18, BorderSizePixel = 0,
    }, parent)
    round(row, 10)
    make("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(43, 25, 67), Color3.fromRGB(20, 39, 40)), Rotation = 0}, row)
    outline(row, Theme.accent, 0.48, 1)
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
        if updateDashboard then updateDashboard() end
        if onChanged then
            local ok, err = pcall(onChanged, State[key])
            if not ok then setStatus(titleText .. " error: " .. tostring(err), Theme.red) end
        end
    end)
    refresh(false)
    return row, refresh
end

-- Page: Dashboard. The layout follows the supplied reference while retaining GTD-specific controls.
local Overview = createPage("Overview")
pageTitle(Overview, "Dashboard", "Overview & quick controls")

local DifficultyOptions = {"Easy", "Normal", "Hard", "Insane", "Impossible", "Apocalypse"}
local DifficultyPickButton
local modeBox

local DashPlacementValue, DashAutomationValue, DashLiveText
local DashMacroNameValue, DashMacroCountValue, DashDifficultyValue, DashStatusValue
local DashAutoSkipButton, DashAutoDifficultyButton, DashAutoReplayButton
local DashSpeed2Button, DashSpeed3Button, DashStartButton, DashStopButton

local DashStats = card(Overview, UDim2.fromOffset(24, 92), UDim2.new(0.64, -30, 0, 94), Theme.accent)
label(DashStats, "LIVE STATISTICS", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(18, 11), Size = UDim2.new(1, -36, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
local StatIconA = make("Frame", {Position = UDim2.fromOffset(18, 43), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Theme.green, BackgroundTransparency = 0.78, BorderSizePixel = 0}, DashStats)
round(StatIconA, 11)
label(StatIconA, "✦", 21, Theme.green, Enum.Font.GothamBold, {Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center})
DashPlacementValue = label(DashStats, "0", 26, Theme.green, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(68, 38), Size = UDim2.fromOffset(120, 31), TextXAlignment = Enum.TextXAlignment.Left,
})
label(DashStats, "UNIT PLACEMENTS", 8, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(69, 67), Size = UDim2.fromOffset(150, 14), TextXAlignment = Enum.TextXAlignment.Left,
})
local StatIconB = make("Frame", {Position = UDim2.new(0.48, 0, 0, 43), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Theme.accent, BackgroundTransparency = 0.78, BorderSizePixel = 0}, DashStats)
round(StatIconB, 11)
label(StatIconB, "⌘", 20, Theme.accent2, Enum.Font.GothamBold, {Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center})
DashAutomationValue = label(DashStats, "0", 26, Theme.green, Enum.Font.GothamBold, {
    Position = UDim2.new(0.48, 50, 0, 38), Size = UDim2.fromOffset(100, 31), TextXAlignment = Enum.TextXAlignment.Left,
})
label(DashStats, "ACTIVE AUTOMATIONS", 8, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.new(0.48, 51, 0, 67), Size = UDim2.fromOffset(180, 14), TextXAlignment = Enum.TextXAlignment.Left,
})

local DashLiveCard = card(Overview, UDim2.new(0.66, 0, 0, 92), UDim2.new(0.34, -48, 0, 94), Theme.accent2)
label(DashLiveCard, "LIVE", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(80, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
DashLiveText = label(DashLiveCard, "READY", 16, Theme.text, Enum.Font.GothamBold, {
    Position = UDim2.new(1, -160, 0, 10), Size = UDim2.fromOffset(140, 22), TextXAlignment = Enum.TextXAlignment.Right,
})
local PulseTrack = make("Frame", {Position = UDim2.new(0, 18, 1, -23), Size = UDim2.new(1, -36, 0, 2), BackgroundColor3 = Theme.accent, BackgroundTransparency = 0.60, BorderSizePixel = 0}, DashLiveCard)
round(PulseTrack, 4)
for i = 1, 34 do
    local dot = make("Frame", {
        Position = UDim2.new((i-1)/33, 0, 0.5, -1), Size = UDim2.fromOffset(2, 2),
        BackgroundColor3 = (i % 5 == 0) and Theme.accent2 or Theme.accent,
        BackgroundTransparency = 0.25 + ((i % 4) * 0.12), BorderSizePixel = 0,
    }, PulseTrack)
    round(dot, 3)
end

local function dashActionCard(pos, size, iconText, titleText, detailText, accent, destination)
    local f = card(Overview, pos, size, accent)
    local icon = make("Frame", {Position = UDim2.fromOffset(16, 17), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = accent, BackgroundTransparency = 0.78, BorderSizePixel = 0}, f)
    round(icon, 12)
    label(icon, iconText, 21, accent, Enum.Font.GothamBold, {Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center})
    label(f, titleText, 13, Theme.text, Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(76, 16), Size = UDim2.new(1, -92, 0, 22), TextXAlignment = Enum.TextXAlignment.Left,
    })
    label(f, detailText, 9, Theme.muted, Enum.Font.Gotham, {
        Position = UDim2.fromOffset(76, 40), Size = UDim2.new(1, -92, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
    })
    local open = secondaryButton(f, "OPEN  ›", UDim2.new(1, -86, 1, -31), UDim2.fromOffset(72, 22), function() showPage(destination) end)
    open.TextSize = 8
    return f
end

dashActionCard(UDim2.fromOffset(24, 202), UDim2.new(0.333, -30, 0, 90), "◉", "Macro Recorder", "Record placements, upgrades and abilities", Theme.accent, "Macro Recorder")
dashActionCard(UDim2.new(0.333, 0, 0, 202), UDim2.new(0.333, -26, 0, 90), "⚡", "Wave Automation", "Auto Skip, Auto Speed and Auto Replay", Theme.green, "Automation")
dashActionCard(UDim2.new(0.666, 0, 0, 202), UDim2.new(0.334, -48, 0, 90), "✧", "Unit Command Deck", "Sell, upgrade and activate deployed units", Theme.accent2, "Automation")

-- Compact one-click toggles and speed selection, matching the reference's large control tiles.
local DashControls = card(Overview, UDim2.fromOffset(24, 308), UDim2.new(1, -48, 0, 80), Theme.accent)
label(DashControls, "QUICK CONTROLS", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(180, 15), TextXAlignment = Enum.TextXAlignment.Left,
})
DashAutoSkipButton = secondaryButton(DashControls, "AUTO SKIP  •  OFF", UDim2.fromOffset(16, 31), UDim2.new(0.30, -20, 0, 36), function()
    State.AutoSkip = not State.AutoSkip
    if State.AutoSkip then
        State.__AutoSkipNeedsApply = true
        setStatus("Auto Skip enabled", Theme.green)
    else
        local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local remote = folder and folder:FindFirstChild("SetAutoSkip")
        if remote and remote:IsA("RemoteEvent") then pcall(function() remote:FireServer(false) end) end
        setStatus("Auto Skip disabled", Theme.muted)
    end
    if AutoRows and AutoRows.AutoSkip then AutoRows.AutoSkip() end
    if updateDashboard then updateDashboard() end
end)
DashAutoSkipButton.TextSize = 9
label(DashControls, "GAME SPEED", 8, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.new(0.34, 0, 0, 11), Size = UDim2.fromOffset(110, 13), TextXAlignment = Enum.TextXAlignment.Left,
})
DashSpeed2Button = secondaryButton(DashControls, "2×", UDim2.new(0.34, 0, 0, 31), UDim2.fromOffset(62, 36), function()
    State.SelectedSpeed = 2; State.__SpeedNeedsApply = true
    setStatus("Selected game speed: 2×", Theme.accent2)
    if Speed2Button then Speed2Button.BackgroundColor3 = Theme.accent; Speed3Button.BackgroundColor3 = Theme.panel3 end
    if updateDashboard then updateDashboard() end
end)
DashSpeed3Button = secondaryButton(DashControls, "3×", UDim2.new(0.34, 70, 0, 31), UDim2.fromOffset(62, 36), function()
    State.SelectedSpeed = 3; State.__SpeedNeedsApply = true
    setStatus("Selected game speed: 3×", Theme.accent2)
    if Speed3Button then Speed3Button.BackgroundColor3 = Theme.accent; Speed2Button.BackgroundColor3 = Theme.panel3 end
    if updateDashboard then updateDashboard() end
end)
DashAutoDifficultyButton = secondaryButton(DashControls, "AUTO DIFFICULTY  •  ON", UDim2.new(0.58, 0, 0, 31), UDim2.new(0.22, -10, 0, 36), function()
    State.AutoSelectDifficulty = not State.AutoSelectDifficulty
    if AutoRows and AutoRows.AutoSelectDifficulty then AutoRows.AutoSelectDifficulty() end
    setStatus("Auto Difficulty " .. (State.AutoSelectDifficulty and "enabled" or "disabled"), Theme.accent2)
    if updateDashboard then updateDashboard() end
end)
DashAutoDifficultyButton.TextSize = 8
DashAutoReplayButton = secondaryButton(DashControls, "AUTO REPLAY  •  ON", UDim2.new(0.80, 0, 0, 31), UDim2.new(0.20, -16, 0, 36), function()
    State.AutoReplay = not State.AutoReplay
    if AutoRows and AutoRows.AutoReplay then AutoRows.AutoReplay() end
    setStatus("Auto Replay " .. (State.AutoReplay and "enabled" or "disabled"), Theme.accent2)
    if updateDashboard then updateDashboard() end
end)
DashAutoReplayButton.TextSize = 8

local DashMacroCard = card(Overview, UDim2.fromOffset(24, 402), UDim2.new(0.60, -30, 0, 166), Theme.accent2)
label(DashMacroCard, "CURRENT BINDINGS", 9, Theme.muted, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(17, 12), Size = UDim2.new(1, -34, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
})
local BindingTrigger = make("Frame", {Position = UDim2.fromOffset(18, 48), Size = UDim2.new(0.29, -8, 0, 62), BackgroundColor3 = Theme.panel2, BackgroundTransparency = 0.12, BorderSizePixel = 0}, DashMacroCard)
round(BindingTrigger, 10)
label(BindingTrigger, "CAPTURE", 8, Theme.muted, Enum.Font.GothamBold, {Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1,0,0,14), TextXAlignment = Enum.TextXAlignment.Center})
label(BindingTrigger, "PLACE", 17, Theme.green, Enum.Font.GothamBold, {Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1,0,0,22), TextXAlignment = Enum.TextXAlignment.Center})
local BindingArrow1 = label(DashMacroCard, "→", 19, Theme.muted, Enum.Font.GothamBold, {Position = UDim2.new(0.29, -1, 0, 66), Size = UDim2.fromOffset(30, 30), TextXAlignment = Enum.TextXAlignment.Center})
local BindingWorld = make("Frame", {Position = UDim2.new(0.34, 0, 0, 48), Size = UDim2.new(0.29, -8, 0, 62), BackgroundColor3 = Theme.panel2, BackgroundTransparency = 0.12, BorderSizePixel = 0}, DashMacroCard)
round(BindingWorld, 10)
label(BindingWorld, "COORDINATES", 8, Theme.muted, Enum.Font.GothamBold, {Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1,0,0,14), TextXAlignment = Enum.TextXAlignment.Center})
label(BindingWorld, "WORLD XYZ", 15, Theme.green, Enum.Font.GothamBold, {Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1,0,0,20), TextXAlignment = Enum.TextXAlignment.Center})
label(DashMacroCard, "→", 19, Theme.muted, Enum.Font.GothamBold, {Position = UDim2.new(0.63, -1, 0, 66), Size = UDim2.fromOffset(30, 30), TextXAlignment = Enum.TextXAlignment.Center})
local BindingDelay = make("Frame", {Position = UDim2.new(0.68, 0, 0, 48), Size = UDim2.new(0.29, -22, 0, 62), BackgroundColor3 = Theme.panel2, BackgroundTransparency = 0.12, BorderSizePixel = 0}, DashMacroCard)
round(BindingDelay, 10)
label(BindingDelay, "MACRO", 8, Theme.muted, Enum.Font.GothamBold, {Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1,0,0,14), TextXAlignment = Enum.TextXAlignment.Center})
DashMacroCountValue = label(BindingDelay, "0 steps", 15, Theme.green, Enum.Font.GothamBold, {Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1,0,0,20), TextXAlignment = Enum.TextXAlignment.Center})
DashMacroNameValue = label(DashMacroCard, "My GTD Strategy", 9, Theme.muted, Enum.Font.Gotham, {Position = UDim2.fromOffset(18, 124), Size = UDim2.new(1, -36, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd})

local DashModeCard = card(Overview, UDim2.new(0.62, 0, 0, 402), UDim2.new(0.38, -48, 0, 166), Theme.green)
local ModeGlyph = make("Frame", {Position = UDim2.fromOffset(17, 17), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Theme.green, BackgroundTransparency = 0.78, BorderSizePixel = 0}, DashModeCard)
round(ModeGlyph, 12)
label(ModeGlyph, "✧", 20, Theme.green, Enum.Font.GothamBold, {Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center})
label(DashModeCard, "ACTIVE MODE", 8, Theme.green, Enum.Font.GothamBold, {Position = UDim2.fromOffset(70, 16), Size = UDim2.new(1,-88,0,14), TextXAlignment = Enum.TextXAlignment.Left})
DashDifficultyValue = label(DashModeCard, State.DesiredDifficulty, 17, Theme.text, Enum.Font.GothamBold, {Position = UDim2.fromOffset(70, 30), Size = UDim2.new(1,-88,0,24), TextXAlignment = Enum.TextXAlignment.Left})
local DashDiffCycle = secondaryButton(DashModeCard, "CHANGE DIFFICULTY  ›", UDim2.fromOffset(17, 78), UDim2.new(1, -34, 0, 30), function()
    local idx = 1
    for i, value in ipairs(DifficultyOptions) do if value == State.DesiredDifficulty then idx = i break end end
    State.DesiredDifficulty = DifficultyOptions[idx % #DifficultyOptions + 1]
    if DifficultyPickButton then DifficultyPickButton.Text = "DIFFICULTY  •  " .. State.DesiredDifficulty .. "  ›" end
    if modeBox then modeBox.Text = State.DesiredDifficulty end
    setStatus("Difficulty target: " .. State.DesiredDifficulty, Theme.accent2)
    if updateDashboard then updateDashboard() end
end)
DashDiffCycle.TextSize = 8
DashStatusValue = label(DashModeCard, "Status: Ready", 9, Theme.muted, Enum.Font.Gotham, {Position = UDim2.fromOffset(18, 119), Size = UDim2.new(1,-36,0,22), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd})

local DashTip = card(Overview, UDim2.fromOffset(24, 584), UDim2.new(1, -48, 0, 58), Theme.accent)
local TipGlyph = make("Frame", {Position = UDim2.fromOffset(16, 9), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Theme.accent, BackgroundTransparency = 0.72, BorderSizePixel = 0}, DashTip)
round(TipGlyph, 12)
label(TipGlyph, "✦", 20, Theme.accent2, Enum.Font.GothamBold, {Size = UDim2.fromScale(1,1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center})
label(DashTip, "PRO TIP", 10, Theme.accent2, Enum.Font.GothamBold, {Position = UDim2.fromOffset(70, 10), Size = UDim2.new(1,-88,0,16), TextXAlignment = Enum.TextXAlignment.Left})
label(DashTip, "Local PlaceUnit playback — no external key system; start in a live match.", 9, Theme.muted, Enum.Font.Gotham, {Position = UDim2.fromOffset(70, 28), Size = UDim2.new(1,-88,0,18), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd})

local DashFooter = card(Overview, UDim2.fromOffset(24, 658), UDim2.new(1, -48, 0, 58), Theme.accent2)
local DashFooterDot = make("Frame", {Position = UDim2.fromOffset(17, 24), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Theme.green, BorderSizePixel = 0}, DashFooter)
round(DashFooterDot, 10)
label(DashFooter, "ENGINE RUNNING", 9, Theme.green, Enum.Font.GothamBold, {Position = UDim2.fromOffset(34, 0), Size = UDim2.fromOffset(140, 58), TextXAlignment = Enum.TextXAlignment.Left})
DashStartButton = primaryButton(DashFooter, "▶  START PLAYBACK", UDim2.new(0.5, -152, 0, 9), UDim2.fromOffset(142, 40), Theme.accent, function() end)
DashStopButton = primaryButton(DashFooter, "■  STOP", UDim2.new(0.5, 0, 0, 9), UDim2.fromOffset(94, 40), Theme.red, function() end)
label(DashFooter, "v2.0  •  GTD CONTROL HUB", 8, Theme.muted, Enum.Font.Gotham, {Position = UDim2.new(1, -200, 0, 0), Size = UDim2.fromOffset(180, 58), TextXAlignment = Enum.TextXAlignment.Right})

updateDashboard = function()
    local active = 0
    if State.AutoSkip then active = active + 1 end
    if State.AutoSpeed then active = active + 1 end
    if State.AutoSelectDifficulty then active = active + 1 end
    if State.AutoReplay then active = active + 1 end
    if DashPlacementValue then DashPlacementValue.Text = tostring(#State.Placements) end
    if DashAutomationValue then DashAutomationValue.Text = tostring(active) end
    if DashLiveText then DashLiveText.Text = State.Recording and "RECORDING" or (State.PlaybackArmed and "WAITING" or (State.Playing and "PLAYING" or "READY")) end
    if DashStartButton then DashStartButton.Text = State.PlaybackArmed and "◷  WAITING FOR NEXT MATCH" or (State.Playing and "▶  PLAYING" or "▶  START PLAYBACK") end
    if DashMacroNameValue then DashMacroNameValue.Text = tostring(State.MacroName) end
    if DashMacroCountValue then DashMacroCountValue.Text = tostring(#State.Placements) .. " steps" end
    if DashDifficultyValue then DashDifficultyValue.Text = tostring(State.DesiredDifficulty) end
    if DashStatusValue then DashStatusValue.Text = "Status: " .. tostring(State.Status) end
    if DashAutoSkipButton then DashAutoSkipButton.Text = "AUTO SKIP  •  " .. (State.AutoSkip and "ON" or "OFF"); DashAutoSkipButton.BackgroundColor3 = State.AutoSkip and Theme.green or Theme.panel3 end
    if DashAutoDifficultyButton then DashAutoDifficultyButton.Text = "AUTO DIFFICULTY  •  " .. (State.AutoSelectDifficulty and "ON" or "OFF"); DashAutoDifficultyButton.BackgroundColor3 = State.AutoSelectDifficulty and Theme.green or Theme.panel3 end
    if DashAutoReplayButton then DashAutoReplayButton.Text = "AUTO REPLAY  •  " .. (State.AutoReplay and "ON" or "OFF"); DashAutoReplayButton.BackgroundColor3 = State.AutoReplay and Theme.green or Theme.panel3 end
    if DashSpeed2Button then DashSpeed2Button.BackgroundColor3 = State.SelectedSpeed == 2 and Theme.accent or Theme.panel3 end
    if DashSpeed3Button then DashSpeed3Button.BackgroundColor3 = State.SelectedSpeed == 3 and Theme.accent or Theme.panel3 end
end

-- Page: Macro recorder.
local MacroPage = createPage("Macro Recorder")
pageTitle(MacroPage, "Macro Recorder", "Capture placements, upgrades and abilities in exact match order")
local MacroInfo = card(MacroPage, UDim2.fromOffset(24, 91), UDim2.new(1,-48,0,82), Theme.accent2)
label(MacroInfo, "FULL ACTION CAPTURE", 10, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(15,13), Size = UDim2.new(1,-30,0,18), TextXAlignment = Enum.TextXAlignment.Left,
})
label(MacroInfo, "Records placements, upgrades, abilities and unit sales in match order.\nRecord from the first placement so actions can be linked to each tower.", 10, Theme.muted, Enum.Font.Gotham, {
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
    BackgroundColor3 = Theme.panel3, BackgroundTransparency = 0.14, Text = State.MacroName, TextColor3 = Theme.text,
    PlaceholderText = "Macro name", PlaceholderColor3 = Theme.muted,
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
}, MacroActions)
round(macroNameBox, 7)

local CountLabel = label(MacroActions, "0 actions recorded", 9, Theme.muted, Enum.Font.Gotham, {
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
label(LoopToggleRow, "Repeat macro on every new match", 10, Theme.text, Enum.Font.GothamMedium, {
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
if State.Loop then
    LoopSwitch.BackgroundColor3 = Theme.green
    LoopKnob.Position = UDim2.new(1,-17,0,3)
end

local RecentCard = card(MacroPage, UDim2.fromOffset(24, 465), UDim2.new(1,-48,0,72), Theme.accent)
label(RecentCard, "EXPORT RECORDED MACRO", 9, Theme.accent2, Enum.Font.GothamBold, {
    Position = UDim2.fromOffset(12,7), Size = UDim2.new(1,-24,0,14), TextXAlignment = Enum.TextXAlignment.Left,
})
local CopyMacroJSONBtn = secondaryButton(RecentCard, "COPY MACRO JSON", UDim2.fromOffset(12,29), UDim2.new(0.5,-18,0,32), function() end)
local CopyActionListBtn = secondaryButton(RecentCard, "COPY ACTION LIST", UDim2.new(0.5,6,0,29), UDim2.new(0.5,-18,0,32), function() end)

local ReplaySalesRow = make("Frame", {
    Position = UDim2.fromOffset(24, 547), Size = UDim2.new(1,-48,0,40),
    BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
}, MacroPage)
round(ReplaySalesRow, 9)
label(ReplaySalesRow, "Replay recorded Sell / Sell All actions", 9, Theme.text, Enum.Font.GothamMedium, {
    Position = UDim2.fromOffset(12,0), Size = UDim2.new(1,-126,1,0), TextXAlignment = Enum.TextXAlignment.Left,
})
local ReplaySalesToggle = secondaryButton(ReplaySalesRow, State.AllowRecordedSales and "ON • ALLOW" or "OFF • SAFE", UDim2.new(1,-106,0.5,-13), UDim2.fromOffset(94,26), function() end)
if State.AllowRecordedSales then ReplaySalesToggle.BackgroundColor3 = Theme.red end

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
    if updateDashboard then updateDashboard() end
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
    BackgroundColor3 = Theme.panel3, BackgroundTransparency = 0.14, Text = State.DesiredDifficulty, TextColor3 = Theme.text,
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
            if updateDashboard then updateDashboard() end
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
    if CountLabel then CountLabel.Text = tostring(count) .. " actions recorded" end
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
    if updateDashboard then updateDashboard() end
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
        version = 7,
        name = State.MacroName,
        createdAt = os.time(),
        coordinateSpace = "context_origin_relative",
        mapId = State.MacroMapId,
        difficultyId = State.MacroDifficultyId,
        night = State.MacroNight == true,
        actions = State.Placements,
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then setStatus("Could not encode macro", Theme.red); return false end
    local path = macroPath(State.MacroName)
    local wrote, err = pcall(writefile, path, encoded)
    if not wrote then setStatus("Save failed: " .. tostring(err), Theme.red); return false end
    setStatus("Saved " .. #State.Placements .. " actions", Theme.green)
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
    State.NextMacroSeq = 0
    for _, action in ipairs(State.Placements) do State.NextMacroSeq = math.max(State.NextMacroSeq, tonumber(action.sequence) or 0) end
    State.MacroMapId = type(data.mapId) == "string" and data.mapId or nil
    State.MacroDifficultyId = type(data.difficultyId) == "string" and data.difficultyId or nil
    State.MacroNight = data.night == true
    updateMacroCount()
    setStatus("Loaded " .. #State.Placements .. " actions", Theme.green)
    return true
end

local function makeMacroData()
    return {
        format = "GTDCH_PLACEMENT_MACRO",
        version = 7,
        name = State.MacroName,
        createdAt = os.time(),
        coordinateSpace = "context_origin_relative",
        mapId = State.MacroMapId,
        difficultyId = State.MacroDifficultyId,
        night = State.MacroNight == true,
        actions = State.Placements,
    }
end

local function encodeMacroJSON()
    local ok, encoded = pcall(function() return HttpService:JSONEncode(makeMacroData()) end)
    if not ok then return nil, tostring(encoded) end
    return encoded
end

local function copyTextToClipboard(value)
    local clipboard = setclipboard or toclipboard
    if type(clipboard) ~= "function" then return false, "clipboard function unavailable" end
    local ok, err = pcall(clipboard, value)
    if not ok then return false, tostring(err) end
    return true
end

local function copyMacroJSON()
    if #State.Placements == 0 and not loadMacro() then
        setStatus("No saved macro found to export", Theme.amber)
        return
    end
    local encoded, encodeError = encodeMacroJSON()
    if not encoded then setStatus("Macro export failed: " .. tostring(encodeError), Theme.red); return end
    local copied, copyError = copyTextToClipboard(encoded)
    if copied then
        setStatus("Macro JSON copied • paste it here in chat", Theme.green)
    else
        saveMacro()
        setStatus("Clipboard unavailable • saved at " .. macroPath(State.MacroName) .. " • " .. tostring(copyError), Theme.amber)
    end
end

local function copyMacroActionList()
    if #State.Placements == 0 and not loadMacro() then
        setStatus("No saved macro found to inspect", Theme.amber)
        return
    end
    local rows = {}
    for i, action in ipairs(State.Placements) do
        rows[#rows + 1] = string.format(
            "%03d | %-8s | unit=%s | key=%s | sourceGameId=%s | source=%s | saleRequest=%s | saleConfirmed=%s | seq=%s | elapsed=%.3f | delay=%.3f",
            i, tostring(action.type or "Place"), tostring(action.unit or "-"),
            tostring(action.towerKey or "-"), tostring(action.sourceGameId or "-"),
            tostring(action.sourceRemote or (action.type == "Sell" and "legacy/unverified" or "-")),
            tostring(action.saleRequest == true), tostring(action.verifiedRemoval == true), tostring(action.sequence or "-"),
            tonumber(action.elapsed) or 0, tonumber(action.delay) or 0)
    end
    local report = "GTD CONTROL HUB ACTION LOG\nMacro: " .. tostring(State.MacroName)
        .. "\nActions: " .. tostring(#State.Placements) .. "\n\n" .. table.concat(rows, "\n")
    local copied, copyError = copyTextToClipboard(report)
    if copied then setStatus("Action list copied • paste it here in chat", Theme.green)
    else setStatus("Clipboard unavailable: " .. tostring(copyError), Theme.amber) end
end

local Macro = {}
do
-- Macro action capture. GTD uses the same InvokeServer method for its RemoteFunctions;
-- hook one dispatcher and identify PlaceUnit / UpgradeUnit / ActivateUnitAbility by self.
local function findRemoteFunction(remoteName)
    local folder = ReplicatedStorage:FindFirstChild("RemoteFunctions")
    local remote = folder and folder:FindFirstChild(remoteName)
    if remote and remote:IsA("RemoteFunction") then return remote end
    return nil
end

local PlaceRemote = findRemoteFunction("PlaceUnit")
local UpgradeRemote = findRemoteFunction("UpgradeUnit")
local AbilityRemote = findRemoteFunction("ActivateUnitAbility")
local SellRemote = findRemoteFunction("SellUnit")
local SellAllRemote = findRemoteFunction("SellAll")

local function snapshotMacroMetadata(context)
    context = context or State.ActiveContext
    local config = nil
    local rawConfig = context and context:GetAttribute("Config")
    if type(rawConfig) == "string" then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(rawConfig) end)
        if ok and type(decoded) == "table" then config = decoded end
    end
    State.MacroMapId = (context and context:GetAttribute("MapId"))
        or (config and config.mapId) or Workspace:GetAttribute("MapId") or State.MacroMapId
    State.MacroDifficultyId = (context and context:GetAttribute("Difficulty"))
        or Workspace:GetAttribute("Difficulty") or State.MacroDifficultyId
    State.MacroNight = (config and config.night == true) or Workspace:GetAttribute("Night") == true
    local originValue = context and context:GetAttribute("Origin")
    State.MacroOrigin = typeof(originValue) == "CFrame" and originValue.Position
        or (typeof(originValue) == "Vector3" and originValue or nil)
    State.MacroStartClock = os.clock()
    local startTime = context and context:GetAttribute("GameStartTime")
    if type(startTime) == "number" and startTime > 0 then
        State.MacroGameStartTime = startTime
        State.MacroStartElapsedOffset = math.max(0, Workspace:GetServerTimeNow() - startTime)
    else
        State.MacroStartElapsedOffset = 0
    end
end

local function extractPlacement(unitKey, payload)
    if type(payload) ~= "table" then return nil end
    local pos = payload.Position
    local cf = payload.CF
    if typeof(pos) ~= "Vector3" and typeof(cf) == "CFrame" then pos = cf.Position end
    if typeof(pos) ~= "Vector3" then return nil end
    -- GTD's current PlaceUnit payload uses Rotation as a NUMBER (normally the
    -- placement rotation index), not a Vector3. Preserve the exact remote value.
    -- CF contains the world transform/yaw separately and is reconstructed from yaw.
    local remoteRotation = tonumber(payload.Rotation) or 0
    local yaw = 0
    if typeof(cf) == "CFrame" then
        local _, y, _ = cf:ToOrientation()
        yaw = y
    elseif typeof(payload.Rotation) == "Vector3" then
        -- Compatibility for old recorded payloads: use the Vector3 only to recover
        -- transform yaw; never send a Vector3 back in the current PlaceUnit request.
        yaw = math.rad(payload.Rotation.Y)
    end
    local origin = State.MacroOrigin
    local storedPos = origin and (pos - origin) or pos
    return {
        type = "Place",
        unit = tostring(unitKey or "unknown"),
        x = storedPos.X, y = storedPos.Y, z = storedPos.Z,
        relativeToOrigin = origin ~= nil,
        yaw = yaw,
        rotation = remoteRotation,
        valid = payload.Valid ~= false,
        fast = payload.WasFastPlaced == true,
        pathIndex = tonumber(payload.PathIndex),
        distanceAlongPath = tonumber(payload.DistanceAlongPath),
        delay = 0,
        elapsed = 0,
        time = os.clock(),
    }
end

local function getCurrentEntities(context)
    context = context or State.ActiveContext
    -- GTD builds have exposed Entities both directly under the active Context
    -- and under Context.Map. Keep Workspace.Map as a legacy fallback.
    local entities = context and context:FindFirstChild("Entities")
    if entities then return entities end
    local contextMap = context and context:FindFirstChild("Map")
    entities = contextMap and contextMap:FindFirstChild("Entities")
    if entities then return entities end
    local map = Workspace:FindFirstChild("Map")
    entities = map and map:FindFirstChild("Entities")
    if entities then return entities end
    return Workspace:FindFirstChild("Entities")
end

local function getTowerGameId(model)
    if not model then return nil end
    local id = model:GetAttribute("ID")
    if type(id) == "number" then return id end
    local inner = model:FindFirstChild(model.Name)
    id = inner and inner:GetAttribute("ID")
    return type(id) == "number" and id or nil
end

local function findLiveTowerModelById(gameId, context)
    local entities = getCurrentEntities(context)
    local targetId = tonumber(gameId)
    if not entities or not targetId then return nil end
    for _, child in ipairs(entities:GetChildren()) do
        if getTowerGameId(child) == targetId then
            return child
        end
    end
    return nil
end

-- A SellUnit call is not sufficient proof of a sale. Confirm that the exact
-- entity ID has actually disappeared before saving a destructive Sell action.
local function waitForRecordedTowerRemoval(gameId, timeoutSeconds, sessionId)
    local deadline = os.clock() + (timeoutSeconds or 2.5)
    repeat
        if State.RecordingSessionId ~= sessionId or not State.Recording then
            return false, "recording stopped"
        end
        local entities = getCurrentEntities(State.ActiveContext)
        if entities then
            local present = false
            for _, child in ipairs(entities:GetChildren()) do
                if getTowerGameId(child) == tonumber(gameId) then
                    present = true
                    break
                end
            end
            if not present then return true end
        end
        task.wait(0.08)
    until os.clock() >= deadline
    return false, "tower ID " .. tostring(gameId) .. " remained in Entities"
end

local function waitForTowerRemoval(gameId, timeoutSeconds, taskId)
    local deadline = os.clock() + (timeoutSeconds or 5)
    repeat
        if not State.Playing or (taskId and State.PlaybackTaskId ~= taskId) then
            return false, "playback stopped"
        end
        local entities = getCurrentEntities(State.ActiveContext)
        if entities then
            local stillPresent = false
            for _, child in ipairs(entities:GetChildren()) do
                if getTowerGameId(child) == tonumber(gameId) then
                    stillPresent = true
                    break
                end
            end
            if not stillPresent then return true end
        end
        task.wait(0.10)
    until os.clock() >= deadline
    return false, "server did not remove tower ID " .. tostring(gameId)
end

local function getTowerHomePosition(model)
    if not model then return nil end
    local visual = model:FindFirstChild("MovingSpawnVisual")
    local target = visual or model
    if target:IsA("BasePart") then return target.Position end
    local ok, pivot = pcall(function() return target:GetPivot() end)
    if ok and typeof(pivot) == "CFrame" then return pivot.Position end
    return nil
end

-- Event-driven tower-ID tracking with a cached set of IDs already present before
-- each placement. A small on-demand Entities fallback scan handles models whose
-- ChildAdded/ID timing does not line up with the RemoteFunction call.
local EntityArrivalConnection = nil
local EntityRemovalConnection = nil
local EntityArrivalFolder = nil
State.EntityArrivalEvents = State.EntityArrivalEvents or {}
State.EntityArrivalKnownIds = State.EntityArrivalKnownIds or {}
State.EntityArrivalSequence = tonumber(State.EntityArrivalSequence) or 0

local function recordEntityArrival(child)
    if not child or not child.Parent or child.Name:match("^enemy_") then return false end
    local id = getTowerGameId(child)
    if not id then return false end
    State.EntityArrivalKnownIds = State.EntityArrivalKnownIds or {}
    State.EntityArrivalKnownIds[id] = true
    local position = getTowerHomePosition(child)
    if not position then return false end
    local events = State.EntityArrivalEvents
    for _, event in ipairs(events) do
        if tonumber(event.id) == tonumber(id) then return true end
    end
    State.EntityArrivalSequence = (tonumber(State.EntityArrivalSequence) or 0) + 1
    events[#events + 1] = {
        sequence = State.EntityArrivalSequence,
        id = id,
        name = child.Name,
        position = position,
        time = os.clock(),
    }
    while #events > 160 do table.remove(events, 1) end
    return true
end

local function attachEntityArrivalWatcher(context)
    local entities = getCurrentEntities(context)
    if not entities then return false end
    if entities == EntityArrivalFolder and EntityArrivalConnection and EntityRemovalConnection then return true end
    if EntityArrivalConnection then
        pcall(function() EntityArrivalConnection:Disconnect() end)
        EntityArrivalConnection = nil
    end
    if EntityRemovalConnection then
        pcall(function() EntityRemovalConnection:Disconnect() end)
        EntityRemovalConnection = nil
    end
    EntityArrivalFolder = entities
    State.EntityArrivalEvents = {}
    State.EntityArrivalKnownIds = {}

    -- One initial snapshot per Entities folder, not a repeated polling scan.
    for _, child in ipairs(entities:GetChildren()) do
        if child and not child.Name:match("^enemy_") then
            local id = getTowerGameId(child)
            if id then State.EntityArrivalKnownIds[id] = true end
        end
    end

    EntityArrivalConnection = entities.ChildAdded:Connect(function(child)
        if not child or child.Name:match("^enemy_") then return end
        -- The server may assign ID / pivot just after parenting. Retry briefly in
        -- the event worker only; do not poll the full Entities tree from playback.
        task.spawn(function()
            for attempt = 1, 12 do -- max 0.6 s, not a 5-second polling worker
                if not child or not child.Parent then return end
                if recordEntityArrival(child) then return end
                task.wait(0.05)
            end
        end)
    end)
    EntityRemovalConnection = entities.ChildRemoved:Connect(function(child)
        local id = getTowerGameId(child)
        if id and State.EntityArrivalKnownIds then
            State.EntityArrivalKnownIds[id] = nil
        end
    end)
    return true
end

local function snapshotTowerIds(_context)
    -- IMPORTANT: called from the RemoteFunction hook immediately before PlaceUnit.
    -- It must be pure cached-table work: never attach listeners or call GetChildren here.
    local ids = {__eventSeq = tonumber(State.EntityArrivalSequence) or 0}
    for id in pairs(State.EntityArrivalKnownIds or {}) do
        ids[id] = true
    end
    return ids
end

local function actionWorldPositionForContext(action, context)
    local position = Vector3.new(tonumber(action.x) or 0, tonumber(action.y) or 0, tonumber(action.z) or 0)
    if action.relativeToOrigin then
        context = context or State.ActiveContext
        local originValue = context and context:GetAttribute("Origin")
        if typeof(originValue) == "CFrame" then
            position = position + originValue.Position
        elseif typeof(originValue) == "Vector3" then
            position = position + originValue
        else
            return nil
        end
    end
    return position
end

-- The ID attribute is the authoritative identifier used by UpgradeUnit and ActivateUnitAbility.
-- Prefer exact name + a close spawn point, and only use a wider fallback when there is one
-- unambiguous newly-created entity of that unit type.
local function findNewTowerId(action, beforeIds, context)
    -- First use the event cache (constant-time small queue; no world traversal).
    local targetPos = actionWorldPositionForContext(action, context)
    local minimumSequence = tonumber(beforeIds and beforeIds.__eventSeq) or 0
    local bestId, bestDistance, secondDistance = nil, math.huge, math.huge
    local events = State.EntityArrivalEvents or {}
    local now = os.clock()
    for i = #events, 1, -1 do
        local event = events[i]
        if event.sequence > minimumSequence
            and event.name == tostring(action.unit)
            and event.id
            and not (beforeIds and beforeIds[event.id])
            and not (State.PendingTowerIds and State.PendingTowerIds[event.id])
            and now - (event.time or now) <= 15 then
            local distance = (event.position and targetPos)
                and (event.position - targetPos).Magnitude or math.huge
            if distance < bestDistance then
                secondDistance = bestDistance
                bestId, bestDistance = event.id, distance
            elseif distance < secondDistance then
                secondDistance = distance
            end
        end
    end
    if bestId and bestDistance <= 2.5
        and (secondDistance == math.huge or secondDistance - bestDistance >= 0.25) then
        return bestId
    end
    return nil
end

local function scanForNewTowerIdOnce(action, beforeIds, context)
    -- Single bounded fallback after the ChildAdded cache had time to update.
    -- This is NOT a polling loop and never runs from the InvokeServer hook.
    local entities = getCurrentEntities(context)
    if not entities then return nil end
    local targetPos = actionWorldPositionForContext(action, context)
    local candidates = {}
    for _, child in ipairs(entities:GetChildren()) do
        if child and not child.Name:match("^enemy_") and child.Name == tostring(action.unit) then
            local id = getTowerGameId(child)
            if id and not (beforeIds and beforeIds[id]) then
                local pos = getTowerHomePosition(child)
                local distance = (pos and targetPos) and (pos - targetPos).Magnitude or math.huge
                candidates[#candidates + 1] = {id = id, model = child, distance = distance}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    local best = candidates[1]
    local second = candidates[2]
    if best and ((#candidates == 1 and (best.distance <= 3.0 or best.distance == math.huge))
        or (best.distance <= 3.0 and (not second or second.distance - best.distance >= 0.25))) then
        -- Feed the fallback result back into the same cache so later actions use
        -- a single consistent tower-ID mapping source.
        pcall(recordEntityArrival, best.model)
        return best.id
    end
    return nil
end

local function waitForNewTowerId(action, beforeIds, timeoutSeconds, taskId, recordingSession, context)
    -- Read the event queue cheaply. If the event/ID timing was missed, perform
    -- exactly one bounded Entities scan after 1.25 s, not a repeated 0.35 s scan.
    local deadline = os.clock() + (timeoutSeconds or 8)
    local fallbackAt = os.clock() + 1.25
    local fallbackDone = false
    repeat
        if taskId and (not State.Playing or State.PlaybackTaskId ~= taskId) then return nil end
        if recordingSession and State.RecordingSessionId ~= recordingSession then return nil end
        local excluded = beforeIds or {}
        if recordingSession then
            for id in pairs(State.PendingTowerIds or {}) do excluded[id] = true end
        end
        local id = findNewTowerId(action, excluded, context)
        if id then
            if recordingSession then
                State.PendingTowerIds = State.PendingTowerIds or {}
                State.PendingTowerIds[id] = true
            end
            return id
        end
        if not fallbackDone and os.clock() >= fallbackAt then
            fallbackDone = true
            id = scanForNewTowerIdOnce(action, excluded, context)
            if id then return id end
        end
        task.wait(0.08)
    until os.clock() >= deadline
    if not fallbackDone then
        local id = scanForNewTowerIdOnce(action, beforeIds or {}, context)
        if id then return id end
    end
    return nil
end

local function nextMacroStamp()
    State.NextMacroSeq = (tonumber(State.NextMacroSeq) or 0) + 1
    local now = os.clock()
    local elapsed = (tonumber(State.MacroStartElapsedOffset) or 0)
        + (State.MacroStartClock and math.max(0, now - State.MacroStartClock) or 0)
    local delay = State.LastActionClock and math.clamp(now - State.LastActionClock, 0, 60) or 0
    State.LastActionClock = now
    return State.NextMacroSeq, elapsed, delay
end

local function insertMacroAction(action)
    table.insert(State.Placements, action)
    table.sort(State.Placements, function(a, b)
        return (tonumber(a.sequence) or 0) < (tonumber(b.sequence) or 0)
    end)
    updateMacroCount()
end

local function findRecordedTowerKey(gameId)
    if not gameId then return nil end
    if State.RecordedTowerByGameId and State.RecordedTowerByGameId[gameId] then
        return State.RecordedTowerByGameId[gameId]
    end
    for _, action in ipairs(State.Placements) do
        if action.type == "Place" and tonumber(action.sourceGameId) == tonumber(gameId) then
            return action.towerKey
        end
    end
    return nil
end

local function recordTowerOperation(actionType, gameId, result, sessionId, saleConfirmed, saleRequest)
    if not State.Recording or State.Playing or not gameId then return end
    if actionType == "Sell" and saleRequest ~= true then return end
    -- UpgradeUnit returns false for a rejected upgrade on builds where the result is exposed.
    -- Some builds return nil, so only an explicit false is treated as rejection.
    if actionType == "Upgrade" and result == false then return end
    -- Ability calls are intentional player actions; GTD can return false for a
    -- cooldown/temporary rejection, but the macro should still retain the timing.

    local sequence, elapsed, delay = nextMacroStamp()
    task.spawn(function()
        local towerKey = findRecordedTowerKey(gameId)
        local deadline = os.clock() + 7
        while not towerKey and os.clock() < deadline
            and State.RecordingSessionId == sessionId do
            task.wait(0.08)
            towerKey = findRecordedTowerKey(gameId)
        end
        if State.RecordingSessionId ~= sessionId then return end
        if not towerKey then
            setStatus(actionType .. " was used, but this tower wasn't placed during this recording; action skipped", Theme.amber)
            return
        end

        if actionType == "Upgrade" then
            -- Avoid double-recording a manual upgrade. If the exact client tower table
            -- is cached, the Level watcher owns this change (manual and auto alike).
            -- If no table was found, fall back to the UpgradeUnit remote and advance the
            -- baseline so a later table discovery cannot record the same level again.
            local towerObject = State.TowerObjectByGameId and State.TowerObjectByGameId[tonumber(gameId)]
            if Macro.LevelWatcherAvailable and towerObject
                and type(rawget(towerObject, "Level")) == "number" then
                return
            end
            State.RecordedLevelByTowerKey = State.RecordedLevelByTowerKey or {}
            State.RecordedLevelByTowerKey[towerKey] = (State.RecordedLevelByTowerKey[towerKey] or 1) + 1
        end

        insertMacroAction({
            type = actionType,
            towerKey = towerKey,
            sourceGameId = gameId,
            sourceRemote = actionType == "Upgrade" and "UpgradeUnit"
                or actionType == "Ability" and "ActivateUnitAbility"
                or actionType == "Sell" and "SellUnit" or "unknown",
            saleRequest = actionType == "Sell" and saleRequest == true or nil,
            verifiedRemoval = actionType == "Sell" and saleConfirmed == true or nil,
            sequence = sequence,
            elapsed = elapsed,
            delay = delay,
        })
        local actionLabel = actionType == "Upgrade" and "Recorded upgrade"
            or actionType == "Ability" and "Recorded ability"
            or "Recorded sale request"
        setStatus(actionLabel .. " • " .. towerKey, Theme.green)
    end)
end

local function recordSellAll(result, sessionId)
    if not State.Recording or State.Playing or not State.RecordingRoundKey
        or State.RecordingRoundKey ~= State.CurrentRoundKey or result == false then return end
    if State.RecordingSessionId ~= sessionId then return end
    local sequence, elapsed, delay = nextMacroStamp()
    insertMacroAction({
        type = "SellAll",
        sequence = sequence,
        elapsed = elapsed,
        delay = delay,
    })
    setStatus("Recorded Sell All", Theme.green)
end

local function dispatchMacroBaseRemote(self, args, result, beforeIds)
    if not State.Recording or State.Playing or not State.RecordingRoundKey
        or State.RecordingRoundKey ~= State.CurrentRoundKey then return end
    local sessionId = State.RecordingSessionId
    if self == PlaceRemote then
        local action = extractPlacement(args[1], args[2])
        if not action or result == false then return end
        local sequence, elapsed, delay = nextMacroStamp()
        State.NextTowerKey = (tonumber(State.NextTowerKey) or 0) + 1
        action.sequence = sequence
        action.elapsed = elapsed
        action.delay = delay
        action.towerKey = "tower_" .. tostring(State.NextTowerKey)
        local context = State.ActiveContext
        task.spawn(function()
            insertMacroAction(action)
            setStatus("Recorded placement • " .. action.unit .. " • " .. action.towerKey, Theme.green)
            local id = waitForNewTowerId(action, beforeIds or {}, 8, nil, sessionId, context)
            if id and State.RecordingSessionId == sessionId then
                action.sourceGameId = id
                State.RecordedTowerByGameId = State.RecordedTowerByGameId or {}
                State.RecordedTowerByGameId[id] = action.towerKey
                State.PendingTowerIds = State.PendingTowerIds or {}
                State.PendingTowerIds[id] = nil
                State.RecordedLevelByTowerKey = State.RecordedLevelByTowerKey or {}
                State.RecordedLevelByTowerKey[action.towerKey] = 1
            else
                action.mappingFailed = true
                setStatus("Placed " .. action.unit .. " but couldn't read its server ID; its upgrades/ability/sale may not link", Theme.amber)
            end
        end)
    elseif self == UpgradeRemote and self.Name == "UpgradeUnit" then
        -- Capture manual upgrades from the exact UpgradeUnit remote. The Level watcher
        -- only adds level increases that were not already reflected in this baseline.
        recordTowerOperation("Upgrade", tonumber(args[1]), result, sessionId)
    elseif self == AbilityRemote and self.Name == "ActivateUnitAbility" then
        recordTowerOperation("Ability", tonumber(args[1]), result, sessionId)
    end
end

local function dispatchMacroSellRemote(self, args, result, _)
    if not State.Recording or State.Playing or not State.RecordingRoundKey
        or State.RecordingRoundKey ~= State.CurrentRoundKey then return end
    local sessionId = State.RecordingSessionId
    if self == SellRemote and self.Name == "SellUnit" then
        local gameId = tonumber(args[1])
        if not gameId then return end
        -- The exact SellUnit invocation is the player's explicit sale command.
        -- Do not infer sales from inventory-card visibility or wait for the model to vanish:
        -- GTD may update the unit panel and the Entities model on different frames.
        recordTowerOperation("Sell", gameId, result, sessionId, false, true)
    elseif self == SellAllRemote and self.Name == "SellAll" then
        recordSellAll(result, sessionId)
    end
end

local function dispatchMacroRemote(self, args, result, beforeIds)
    dispatchMacroBaseRemote(self, args, result, beforeIds)
    dispatchMacroSellRemote(self, args, result)
end

local macroHookReady = false

-- Disable dispatch from legacy hooks. Their wrappers close over prior-version State
-- tables; leaving them active caused stale callbacks and duplicate capture on reload.
local function disableLegacyHook(record)
    if type(record) == "table" and type(record.Holder) == "table" then
        record.Holder.Dispatch = nil
    end
end

local function installPersistentInvokeHook()
    disableLegacyHook(ENV.__GTD_ACTION_HOOK)
    disableLegacyHook(ENV.__GTD_SELL_HOOK)

    local record = ENV.__GTD_ACTION_HOOK_V2214
    local holder = type(record) == "table" and record.Holder or nil

    if not (type(holder) == "table" and record.HookKind == "dynamic-generic-v2214") then
        if type(hookfunction) ~= "function" then
            return false, "This Delta build does not expose hookfunction"
        end

        local rfClass = Instance.new("RemoteFunction")
        local invokeMethod = rfClass.InvokeServer
        rfClass:Destroy()

        holder = {Dispatch = nil, Prepare = nil, OnError = nil}
        local original = nil
        local ok, hookError = pcall(function()
            original = hookfunction(invokeMethod, function(self, ...)
                local args = table.pack(...)
                local beforeIds = nil

                -- Every callback is read from the persistent holder at call time.
                -- The installed closure therefore never captures an old script State.
                local prepare = holder.Prepare
                if type(prepare) == "function" then
                    local prepOk, prepResult = pcall(prepare, self, args)
                    if prepOk then
                        beforeIds = prepResult
                    elseif type(holder.OnError) == "function" then
                        pcall(holder.OnError, "prepare", prepResult)
                    end
                end

                local returns = table.pack(original(self, table.unpack(args, 1, args.n)))
                local dispatch = holder.Dispatch
                if type(dispatch) == "function" then
                    local dispatchOk, dispatchError = pcall(dispatch, self, args, returns[1], beforeIds)
                    if not dispatchOk and type(holder.OnError) == "function" then
                        pcall(holder.OnError, "dispatch", dispatchError)
                    end
                end
                return table.unpack(returns, 1, returns.n)
            end)
        end)

        if not ok then return false, tostring(hookError) end
        if type(original) ~= "function" then
            return false, "hookfunction did not return the original InvokeServer function"
        end

        record = {Holder = holder, HookKind = "dynamic-generic-v2214"}
        ENV.__GTD_ACTION_HOOK_V2214 = record
    end

    -- Rebind all state-dependent behavior to this script instance on every load.
    holder.Prepare = function(self)
        if self ~= PlaceRemote or not State.Recording or State.Playing then return nil end
        local beforeIds = snapshotTowerIds(State.ActiveContext)
        for id in pairs(State.RecordedTowerByGameId or {}) do
            beforeIds[id] = true
        end
        return beforeIds
    end
    holder.ActiveThreads = holder.ActiveThreads or {}
    holder.MainThreadKey = holder.MainThreadKey or {}
    holder.DispatchFromNamecall = dispatchMacroRemote
    -- The persistent hookfunction wrapper uses Holder.Dispatch. If a colon call
    -- passes through both hooks on an executor, suppress the inner dispatch and
    -- let the outer __namecall wrapper record it exactly once.
    holder.Dispatch = function(self, args, result, beforeIds)
        local thread = coroutine.running() or holder.MainThreadKey
        if holder.ActiveThreads[thread] then return end
        local dispatch = holder.DispatchFromNamecall
        if type(dispatch) == "function" then
            return dispatch(self, args, result, beforeIds)
        end
    end
    holder.OnError = function(stage, err)
        State.ReportRuntimeError("macro hook " .. tostring(stage), State.ErrorTrace(err))
    end

    -- GTD has used both function-style InvokeServer calls and colon/namecall
    -- calls. hookfunction alone misses the latter on some Delta builds, so add
    -- a single persistent __namecall hook which reads this holder dynamically.
    local namecallRecord = ENV.__GTD_ACTION_NAMECALL_HOOK_V2220
    local namecallHolder = type(namecallRecord) == "table" and namecallRecord.Holder or nil
    if not (type(namecallHolder) == "table" and namecallRecord.HookKind == "invoke-namecall-v2220") then
        if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
            namecallHolder = holder
            namecallHolder.ActiveThreads = namecallHolder.ActiveThreads or {}
            namecallHolder.MainThreadKey = namecallHolder.MainThreadKey or {}
            local oldNamecall = nil
            local wrapper = function(self, ...)
                local methodOk, methodName = pcall(getnamecallmethod)
                if not methodOk or (methodName ~= "InvokeServer" and methodName ~= "invokeserver") then
                    return oldNamecall(self, ...)
                end

                local thread = coroutine.running() or namecallHolder.MainThreadKey
                local active = namecallHolder.ActiveThreads
                if active[thread] then
                    return oldNamecall(self, ...)
                end
                active[thread] = true

                local args = table.pack(...)
                local beforeIds = nil
                local prepare = holder.Prepare
                if type(prepare) == "function" then
                    local prepOk, prepResult = pcall(prepare, self, args)
                    if prepOk then
                        beforeIds = prepResult
                    elseif type(holder.OnError) == "function" then
                        pcall(holder.OnError, "namecall prepare", prepResult)
                    end
                end

                local callOk, returns = pcall(function()
                    return table.pack(oldNamecall(self, table.unpack(args, 1, args.n)))
                end)
                if not callOk then
                    active[thread] = nil
                    error(returns, 0)
                end

                local dispatch = holder.DispatchFromNamecall
                if type(dispatch) == "function" then
                    local dispatchOk, dispatchError = pcall(dispatch, self, args, returns[1], beforeIds)
                    if not dispatchOk and type(holder.OnError) == "function" then
                        pcall(holder.OnError, "namecall dispatch", dispatchError)
                    end
                end

                active[thread] = nil
                return table.unpack(returns, 1, returns.n)
            end
            if type(newcclosure) == "function" then
                local okWrap, wrapped = pcall(newcclosure, wrapper)
                if okWrap and type(wrapped) == "function" then wrapper = wrapped end
            end
            local okNamecall, oldOrError = pcall(function()
                return hookmetamethod(game, "__namecall", wrapper)
            end)
            if okNamecall and type(oldOrError) == "function" then
                oldNamecall = oldOrError
                namecallRecord = {Holder = namecallHolder, HookKind = "invoke-namecall-v2220"}
                ENV.__GTD_ACTION_NAMECALL_HOOK_V2220 = namecallRecord
            else
                namecallHolder = nil
                warn("[GTD Control Hub v2.2.20] __namecall hook unavailable: " .. tostring(oldOrError))
            end
        end
    end

    if type(namecallHolder) == "table" then
        namecallHolder.ActiveThreads = namecallHolder.ActiveThreads or {}
        namecallHolder.MainThreadKey = namecallHolder.MainThreadKey or {}
    end

    return true, record
end

local function installTargetedRemoteHooks()
    local hookRecord = ENV.__GTD_ACTION_HOOK_V2214
    local holder = type(hookRecord) == "table" and hookRecord.Holder or nil
    if type(holder) ~= "table" or type(hookfunction) ~= "function" then return 0 end
    holder.TargetedRemotes = holder.TargetedRemotes or {}
    holder.ActiveThreads = holder.ActiveThreads or {}
    holder.MainThreadKey = holder.MainThreadKey or {}

    local targets = {PlaceRemote, UpgradeRemote, AbilityRemote, SellRemote, SellAllRemote}
    local installed = 0
    for _, remote in ipairs(targets) do
        if remote and holder.TargetedRemotes[remote] then
            installed = installed + 1
        elseif remote then
            local oldInvoke = nil
            local okHook = pcall(function()
                oldInvoke = hookfunction(remote.InvokeServer, function(self, ...)
                    if self ~= remote then
                        return oldInvoke(self, ...)
                    end

                    local thread = coroutine.running() or holder.MainThreadKey
                    local active = holder.ActiveThreads
                    if active[thread] then
                        return oldInvoke(self, ...)
                    end
                    active[thread] = true

                    local args = table.pack(...)
                    local beforeIds = nil
                    local prepare = holder.Prepare
                    if type(prepare) == "function" then
                        local prepOk, prepResult = pcall(prepare, self, args)
                        if prepOk then beforeIds = prepResult end
                    end

                    local callOk, returns = pcall(function()
                        return table.pack(oldInvoke(self, table.unpack(args, 1, args.n)))
                    end)
                    if not callOk then
                        active[thread] = nil
                        error(returns, 0)
                    end

                    local dispatch = holder.DispatchFromNamecall
                    if type(dispatch) == "function" then
                        local dispatchOk, dispatchError = pcall(dispatch, self, args, returns[1], beforeIds)
                        if not dispatchOk and type(holder.OnError) == "function" then
                            pcall(holder.OnError, "targeted remote dispatch", dispatchError)
                        end
                    end

                    active[thread] = nil
                    return table.unpack(returns, 1, returns.n)
                end)
                if type(oldInvoke) ~= "function" then
                    error("hookfunction did not return the original remote method")
                end
            end)
            if okHook then
                holder.TargetedRemotes[remote] = true
                installed = installed + 1
            else
                warn("[GTD Control Hub v2.2.20] Targeted hook failed for " .. tostring(remote.Name))
            end
        end
    end
    return installed
end

local function installPlaceHook()
    PlaceRemote = PlaceRemote or findRemoteFunction("PlaceUnit")
    UpgradeRemote = UpgradeRemote or findRemoteFunction("UpgradeUnit")
    AbilityRemote = AbilityRemote or findRemoteFunction("ActivateUnitAbility")
    SellRemote = SellRemote or findRemoteFunction("SellUnit")
    SellAllRemote = SellAllRemote or findRemoteFunction("SellAll")

    if not macroHookReady then
        if not PlaceRemote then
            setStatus("GTD PlaceUnit RemoteFunction not found", Theme.red)
            return false
        end
        local okHook, recordOrError = installPersistentInvokeHook()
        if not okHook then
            setStatus("Could not install macro action hook: " .. tostring(recordOrError), Theme.red)
            return false
        end
        macroHookReady = true
    end

    local targetedCount = installTargetedRemoteHooks()
    local namecallReady = type(ENV.__GTD_ACTION_NAMECALL_HOOK_V2220) == "table"
    setStatus("Macro hooks ready • targeted=" .. tostring(targetedCount)
        .. " • namecall=" .. tostring(namecallReady), Theme.green)
    return true
end

-- Upgrade state in GTD is reflected on a small client-side tower table
-- (ID / Level / IsAutoUpgrading / Owner). Watch only IDs already mapped from
-- this recording. Prefer filtergc; use getgc(true) only as a cold fallback,
-- at a 15-second cooldown, and clear its snapshot immediately after scanning.
Macro.LevelWatcherAvailable = type(filtergc) == "function" or type(getgc) == "function"
Macro.LevelWatcherRunning = false

local TOWER_OBJECT_KEYS = {"ID", "Level", "IsAutoUpgrading", "Owner"}
local hasTowerFilterGc = type(filtergc) == "function"
local towerScanCooldown = hasTowerFilterGc and 3 or 15
local lastTowerObjectScan = -math.huge

local function collectRecordedTowerObjects(neededIds)
    local remaining = 0
    for _ in pairs(neededIds) do remaining = remaining + 1 end
    if remaining == 0 then return end

    local function tryMatch(candidate)
        if type(candidate) ~= "table" then return false end
        local id = rawget(candidate, "ID")
        if id ~= nil and neededIds[id]
            and type(rawget(candidate, "Level")) == "number"
            and rawget(candidate, "IsAutoUpgrading") ~= nil
            and rawget(candidate, "Owner") == LocalPlayer then
            State.TowerObjectByGameId[id] = candidate
            neededIds[id] = nil
            remaining = remaining - 1
        end
        return remaining <= 0
    end

    if hasTowerFilterGc then
        local ok, found = pcall(filtergc, "table", {Keys = TOWER_OBJECT_KEYS}, false)
        if ok and type(found) == "table" then
            for _, candidate in ipairs(found) do
                if tryMatch(candidate) then break end
            end
            table.clear(found)
            return
        end
    end

    if type(getgc) == "function" then
        local ok, snapshot = pcall(getgc, true)
        if ok and type(snapshot) == "table" then
            for index = 1, #snapshot do
                if tryMatch(snapshot[index]) then break end
            end
            table.clear(snapshot)
        end
    end
end

local function scanRecordedTowerLevels()
    if not State.Recording or State.Playing or not State.RoundLive then return end
    State.TowerObjectByGameId = State.TowerObjectByGameId or {}
    State.RecordedTowerByGameId = State.RecordedTowerByGameId or {}
    State.RecordedLevelByTowerKey = State.RecordedLevelByTowerKey or {}

    local entities = getCurrentEntities(State.ActiveContext)
    if not entities then return end
    local presentIds = {}
    for _, model in ipairs(entities:GetChildren()) do
        if model and not model.Name:match("^enemy_") then
            local id = getTowerGameId(model)
            if id then presentIds[id] = true end
        end
    end

    local neededIds = {}
    for gameId in pairs(State.RecordedTowerByGameId) do
        if presentIds[gameId] and not State.TowerObjectByGameId[gameId] then
            neededIds[gameId] = true
        elseif not presentIds[gameId] then
            State.TowerObjectByGameId[gameId] = nil
        end
    end

    if next(neededIds) and (os.clock() - lastTowerObjectScan >= towerScanCooldown) then
        lastTowerObjectScan = os.clock()
        collectRecordedTowerObjects(neededIds)
    end

    for gameId, towerKey in pairs(State.RecordedTowerByGameId) do
        if presentIds[gameId] then
            local towerObject = State.TowerObjectByGameId[gameId]
            local currentLevel = towerObject and rawget(towerObject, "Level")
            if type(currentLevel) == "number" then
                local previousLevel = tonumber(State.RecordedLevelByTowerKey[towerKey]) or 1
                if currentLevel > previousLevel then
                    local gained = math.min(currentLevel - previousLevel, 20)
                    State.RecordedLevelByTowerKey[towerKey] = currentLevel
                    for _ = 1, gained do
                        local sequence, elapsed, delay = nextMacroStamp()
                        insertMacroAction({
                            type = "Upgrade",
                            towerKey = towerKey,
                            sourceGameId = gameId,
                            sourceRemote = "TowerLevelWatcher",
                            sequence = sequence,
                            elapsed = elapsed,
                            delay = delay,
                        })
                    end
                    setStatus("Recorded upgrade ×" .. tostring(gained) .. " • " .. tostring(towerKey), Theme.green)
                elseif currentLevel < previousLevel then
                    -- Keep the baseline sane if GTD resets a tower's internal level.
                    State.RecordedLevelByTowerKey[towerKey] = currentLevel
                end
            end
        end
    end
end

local function startTowerLevelWatcher()
    if Macro.LevelWatcherRunning then return true end
    Macro.LevelWatcherRunning = true
    task.spawn(function()
        while Gui and Gui.Parent and not State.Shutdown do
            task.wait(0.5)
            local ok, err = pcall(scanRecordedTowerLevels)
            if not ok then State.ReportRuntimeError("tower level watcher", err) end
        end
        Macro.LevelWatcherRunning = false
    end)
    if Macro.LevelWatcherAvailable then
        setStatus(hasTowerFilterGc and "Upgrade tracker ready • filtered tower cache" or "Upgrade tracker ready • 15s bounded cache scan", Theme.green)
    else
        setStatus("Upgrade tracker unavailable • remote-hook fallback only", Theme.amber)
    end
    return true
end

Macro.invokeTowerActionOnceWithTimeout = function(remoteName, gameId, timeoutSeconds, taskId)
    local remote = findRemoteFunction(remoteName)
    if not remote then return false, "RemoteFunctions." .. remoteName .. " not found" end
    local response = nil
    task.spawn(function()
        local ok, result = pcall(function() return remote:InvokeServer(gameId) end)
        response = {ok = ok, result = result}
    end)
    local deadline = os.clock() + (timeoutSeconds or 10)
    while State.Playing and State.PlaybackTaskId == taskId and not response and os.clock() < deadline do
        task.wait(0.08)
    end
    if not State.Playing or State.PlaybackTaskId ~= taskId then return false, "playback stopped" end
    if not response then return false, remoteName .. " timed out; no duplicate request sent" end
    if not response.ok then return false, remoteName .. " error: " .. tostring(response.result) end
    if response.result == false then
        return true, remoteName .. " returned false; checking whether the tower was removed"
    end
    return true
end

Macro.invokeTowerActionWithRetry = function(remoteName, gameId, timeoutSeconds, taskId)
    local remote = findRemoteFunction(remoteName)
    if not remote then return false, "RemoteFunctions." .. remoteName .. " not found" end
    local deadline = os.clock() + (timeoutSeconds or 15)
    repeat
        if not State.Playing or State.PlaybackTaskId ~= taskId or not State.RoundLive then
            return false, "playback stopped"
        end
        local response = nil
        task.spawn(function()
            local ok, result = pcall(function() return remote:InvokeServer(gameId) end)
            response = {ok = ok, result = result}
        end)
        local callDeadline = math.min(deadline, os.clock() + 8)
        while State.Playing and State.PlaybackTaskId == taskId and not response and os.clock() < callDeadline do
            task.wait(0.08)
        end
        if not response then return false, remoteName .. " timed out; no duplicate request sent" end
        if not response.ok then return false, remoteName .. " error: " .. tostring(response.result) end
        if response.result ~= false then return true end
        task.wait(0.70)
    until os.clock() >= deadline
    return false, remoteName .. " kept returning false (not enough cash / ability not ready)"
end

local function invokeNoArgumentRemoteWithTimeout(remoteName, timeoutSeconds, taskId)
    local remote = findRemoteFunction(remoteName)
    if not remote then return false, "RemoteFunctions." .. remoteName .. " not found" end
    local response = nil
    task.spawn(function()
        local ok, result = pcall(function() return remote:InvokeServer() end)
        response = {ok = ok, result = result}
    end)
    local deadline = os.clock() + (timeoutSeconds or 10)
    while State.Playing and State.PlaybackTaskId == taskId and not response and os.clock() < deadline do
        task.wait(0.08)
    end
    if not State.Playing or State.PlaybackTaskId ~= taskId then return false, "playback stopped" end
    if not response then return false, remoteName .. " timed out; no duplicate request sent" end
    if not response.ok then return false, remoteName .. " error: " .. tostring(response.result) end
    if response.result == false then return false, remoteName .. " was rejected by the server" end
    return true
end

Macro.invokeNoArgumentRemoteWithTimeout = invokeNoArgumentRemoteWithTimeout
Macro.snapshotMacroMetadata = snapshotMacroMetadata
Macro.waitForTowerRemoval = waitForTowerRemoval
Macro.startTowerLevelWatcher = startTowerLevelWatcher
Macro.PlaceRemote = PlaceRemote
Macro.findRemoteFunction = findRemoteFunction
Macro.snapshotTowerIds = snapshotTowerIds
Macro.findLiveTowerModelById = findLiveTowerModelById
Macro.waitForNewTowerId = waitForNewTowerId
Macro.attachEntityArrivalWatcher = attachEntityArrivalWatcher
Macro.actionWorldPositionForContext = actionWorldPositionForContext
Macro.installPlaceHook = installPlaceHook
Macro.cleanup = function()
    if EntityArrivalConnection then
        pcall(function() EntityArrivalConnection:Disconnect() end)
        EntityArrivalConnection = nil
    end
    if EntityRemovalConnection then
        pcall(function() EntityRemovalConnection:Disconnect() end)
        EntityRemovalConnection = nil
    end
    EntityArrivalFolder = nil
end

end
local function beginRecordingForRound(roundKey)
    if not State.RecordingArmed or not State.RoundLive or State.Playing then return end
    State.RecordingArmed = false
    State.Recording = true
    State.RecordingRoundKey = roundKey
    State.LastPlacementAt = nil
    Macro.snapshotMacroMetadata(State.ActiveContext)
    Macro.attachEntityArrivalWatcher(State.ActiveContext)
    updateMacroCount()
    RecordBtn.BackgroundColor3 = Theme.red
    tween(RecordBtn, 0.15, {BackgroundColor3 = Color3.fromRGB(185, 45, 70)})
    setStatus("● LIVE MATCH DETECTED — recording placements", Theme.red)
end

local function startRecording()
    if State.Playing then setStatus("Stop playback first", Theme.amber); return end
    if not Macro.installPlaceHook() then return end
    State.Placements = {}
    State.LastPlacementAt = nil
    State.NextMacroSeq = 0
    State.NextTowerKey = 0
    State.LastActionClock = nil
    State.RecordedTowerByGameId = {}
    State.PendingTowerIds = {}
    State.TowerObjectByGameId = {}
    State.RecordedLevelByTowerKey = {}
    State.RecordingSessionId = (tonumber(State.RecordingSessionId) or 0) + 1
    State.Recording = false
    State.RecordingArmed = true
    State.RecordingRoundKey = nil
    State.MacroMapId = nil
    State.MacroDifficultyId = nil
    State.MacroNight = false
    State.MacroGameStartTime = nil
    State.MacroOrigin = nil
    State.MacroStartClock = nil
    State.MacroStartElapsedOffset = 0
    updateMacroCount()
    showPage("Macro Recorder")
    if State.RoundLive and State.CurrentRoundKey then
        beginRecordingForRound(State.CurrentRoundKey)
    else
        setStatus("RECORDER ARMED — waiting for the real match to start", Theme.amber)
    end
end

local function stopRecordingAndSave()
    if not State.Recording and not State.RecordingArmed then
        setStatus("Recorder is not active", Theme.amber)
        return
    end
    local wasRecording = State.Recording
    State.Recording = false
    State.RecordingArmed = false
    State.RecordingRoundKey = nil
    updateMacroCount()
    RecordBtn.BackgroundColor3 = Theme.accent
    if wasRecording then
        saveMacro()
        if #State.Placements == 0 then
            setStatus("Match ended — no macro actions were captured", Theme.amber)
        else
            setStatus("Match ended • saved " .. #State.Placements .. " actions", Theme.green)
        end
    else
        setStatus("Recording arm cancelled", Theme.amber)
    end
end

local getGameAttribute -- assigned below; playMacro must capture this local, not a nil global

-- Local playback: calls the same PlaceUnit RemoteFunction that was captured by the recorder.
-- No third-party loader, remote script, key prompt, generated code or external authorization.
local function actionWorldPosition(action)
    local position = Macro.actionWorldPositionForContext(action, State.ActiveContext)
    if not position then
        return nil, "Context Origin is not ready; refusing to place at a wrong map position"
    end
    return position
end

local function waitForPlaybackTime(action, fallbackDelay, roundStartTime, taskId)
    local targetElapsed = tonumber(action.elapsed)
    if targetElapsed ~= nil then targetElapsed = math.max(0, targetElapsed) end

    -- Prefer the recorded server-time offset, so placements wait for approximately
    -- the same recorded time point as in the source match. Old macros fall back to delays.
    if type(roundStartTime) == "number" and roundStartTime > 0 and tonumber(action.elapsed) ~= nil then
        while State.Playing and State.PlaybackTaskId == taskId and State.RoundLive do
            local elapsedNow = Workspace:GetServerTimeNow() - roundStartTime
            local remaining = targetElapsed - elapsedNow
            if remaining <= 0 then return true end
            task.wait(math.min(remaining, 0.20))
        end
        return false
    end

    local remaining = math.max(0, tonumber(fallbackDelay) or 0)
    while remaining > 0 and State.Playing and State.PlaybackTaskId == taskId and State.RoundLive do
        local slice = math.min(remaining, 0.20)
        task.wait(slice)
        remaining = remaining - slice
    end
    return State.Playing and State.PlaybackTaskId == taskId and State.RoundLive
end

local function invokePlacementWithTimeout(action, payload, timeoutSeconds, taskId)
    local remote = Macro.PlaceRemote or Macro.findRemoteFunction("PlaceUnit")
    if not remote then return false, "PlaceUnit RemoteFunction disappeared" end

    Macro.attachEntityArrivalWatcher(State.ActiveContext)
    local snapshotFn = Macro.snapshotTowerIds
    if type(snapshotFn) ~= "function" then
        return false, "Macro snapshot helper is unavailable"
    end
    local beforeIds = snapshotFn(State.ActiveContext)
    local response = nil
    task.spawn(function()
        local ok, result = pcall(function()
            return remote:InvokeServer(action.unit, payload)
        end)
        response = {ok = ok, result = result}
    end)

    local deadline = os.clock() + (timeoutSeconds or 12)
    while State.Playing and State.PlaybackTaskId == taskId and not response and os.clock() < deadline do
        task.wait(0.10)
    end
    if not State.Playing or State.PlaybackTaskId ~= taskId then return false, "playback stopped" end
    if not response then
        return false, "PlaceUnit timed out; stopped to avoid sending duplicate requests"
    end
    if not response.ok then return false, "PlaceUnit error: " .. tostring(response.result), beforeIds end
    local result = response.result
    if result == false then
        -- Keep the pre-call ID snapshot even on explicit rejection. The retry
        -- verifier must only consider IDs created after THIS attempt, never a
        -- recent same-type tower from an earlier action.
        return false, "server returned false (unit unavailable, not equipped, not affordable, or invalid position)", beforeIds
    end
    if type(result) == "table" then
        local successFlag = result.success
        if successFlag == nil then successFlag = result.Success end
        if successFlag == nil then successFlag = result.ok end
        if successFlag == false then
            local reason = result.message or result.Message or result.error or result.Error or result.reason or result.Reason
            return false, "server rejected placement: " .. tostring(reason or "success=false"), beforeIds
        end
    elseif type(result) == "string" then
        local lower = string.lower(result)
        if lower:find("error", 1, true) or lower:find("reject", 1, true)
            or lower:find("invalid", 1, true) or lower:find("config", 1, true)
            or lower:find("state", 1, true) or lower:find("failed", 1, true) then
            return false, "server response: " .. result
        end
    end
    -- Return the pre-placement ID set so playback can bind this macro tower to its new server ID.
    return true, nil, beforeIds
end

local function invokePlacementWithRetry(action, payload, taskId)
    -- Explicit server rejection is safe to retry: no placement was accepted.
    -- A timeout or thrown remote error is NOT retried because the server may have
    -- processed the request even though the client did not receive the response.
    local deadline = os.clock() + 18
    local attempts = 0
    local lastError = "server rejected placement"
    repeat
        if not State.Playing or State.PlaybackTaskId ~= taskId or not State.RoundLive then
            return false, "playback stopped"
        end
        attempts = attempts + 1
        local placed, placeError, beforeIds = invokePlacementWithTimeout(action, payload, 8, taskId)
        if placed then return true, nil, beforeIds end
        lastError = tostring(placeError or "unknown placement failure")
        if not lastError:find("server returned false", 1, true) then
            return false, lastError
        end

        -- Guard against a server that created the tower but returned false. If its
        -- ID appeared, treat that attempt as successful and never place a duplicate.
        local existingId = Macro.waitForNewTowerId(action, beforeIds or {}, 0.9, taskId, nil, State.ActiveContext)
        if existingId then return true, nil, beforeIds, existingId end
        if os.clock() >= deadline then break end
        setStatus("Сервер пока отклоняет установку " .. tostring(action.unit)
            .. " — повтор №" .. tostring(attempts), Theme.amber)
        task.wait(0.65)
    until os.clock() >= deadline

    return false, "Установка " .. tostring(action.unit) .. " отклонена сервером после "
        .. tostring(attempts) .. " попыток. Проверь деньги, наличие юнита в колоде и допустимость позиции. Последний ответ: " .. lastError
end

local function stopPlayback()
    State.Playing = false
    State.PlaybackArmed = false
    State.PlaybackTaskId = State.PlaybackTaskId + 1
    setStatus("Macro playback stopped", Theme.amber)
end

local function playMacro()
    if State.Recording or State.RecordingArmed then
        setStatus("Stop recording before playback", Theme.amber)
        return
    end
    if State.Playing then
        setStatus(State.PlaybackArmed and "Macro armed • waiting for live match" or "Macro is playing", Theme.amber)
        return
    end
    if #State.Placements == 0 and not loadMacro() then return end
    if #State.Placements == 0 then
        setStatus("This macro has no actions", Theme.amber)
        return
    end

    -- Playback calls the game's RemoteFunctions directly. The InvokeServer hook is
    -- required only while RECORDING, to observe the player's actions; requiring it
    -- here made an executor hook failure block an otherwise valid saved macro.
    -- Validate the exact remotes needed by this macro, without installing/replacing hooks.
    local requiredRemotes = {}
    local validTypes = {Place = true, Upgrade = true, Ability = true, Sell = true, SellAll = true}
    for index, action in ipairs(State.Placements) do
        if type(action) ~= "table" then
            setStatus("Ошибка запуска: действие №" .. tostring(index) .. " повреждено", Theme.red)
            return
        end
        local actionType = action.type or "Place"
        if not validTypes[actionType] then
            setStatus("Ошибка запуска: неизвестное действие №" .. tostring(index) .. " (" .. tostring(actionType) .. ")", Theme.red)
            return
        end
        local remoteName = actionType == "Place" and "PlaceUnit"
            or actionType == "Upgrade" and "UpgradeUnit"
            or actionType == "Ability" and "ActivateUnitAbility"
            or actionType == "Sell" and "SellUnit"
            or actionType == "SellAll" and "SellAll"
        requiredRemotes[remoteName] = true
        if actionType == "Place" then
            if type(action.unit) ~= "string" or action.unit == "" then
                setStatus("Ошибка запуска: у установки №" .. tostring(index) .. " отсутствует имя юнита", Theme.red)
                return
            end
            if tonumber(action.x) == nil or tonumber(action.y) == nil or tonumber(action.z) == nil then
                setStatus("Ошибка запуска: у установки №" .. tostring(index) .. " повреждены координаты", Theme.red)
                return
            end
            if action.rotation ~= nil and tonumber(action.rotation) == nil then
                setStatus("Ошибка запуска: у установки №" .. tostring(index) .. " повреждён параметр поворота", Theme.red)
                return
            end
        elseif actionType ~= "SellAll" then
            if not action.towerKey and tonumber(action.sourceGameId) == nil then
                setStatus("Ошибка запуска: действие №" .. tostring(index) .. " не привязано к башне", Theme.red)
                return
            end
        end
    end
    for remoteName in pairs(requiredRemotes) do
        if not Macro.findRemoteFunction(remoteName) then
            setStatus("Нельзя запустить макрос: в игре нет RemoteFunctions." .. remoteName, Theme.red)
            return
        end
    end

    State.Playing = true
    State.PlaybackArmed = not (State.RoundLive and State.CurrentRoundKey)
    State.PlaybackTaskId = State.PlaybackTaskId + 1
    local taskId = State.PlaybackTaskId
    setStatus(State.PlaybackArmed and "Macro armed • waiting for live match (GameStartTime / GameEnd UI)" or "Local playback started", Theme.green)

    task.spawn(function()
        local ok, err = xpcall(function()
            local playedRoundKey = nil
            while State.Playing and State.PlaybackTaskId == taskId and Gui and Gui.Parent do
                -- The play command may be issued from the lobby. Arm now, then wait for
                -- a genuinely live Context instead of refusing to start immediately.
                if not State.RoundLive or not State.CurrentRoundKey then
                    State.PlaybackArmed = true
                    setStatus("Macro armed • waiting for live match", Theme.amber)
                    repeat task.wait(0.15) until not State.Playing or State.PlaybackTaskId ~= taskId
                        or (State.RoundLive and State.CurrentRoundKey and State.CurrentRoundKey ~= playedRoundKey)
                end
                if not State.Playing or State.PlaybackTaskId ~= taskId then break end
                if not State.RoundLive or not State.CurrentRoundKey then
                    task.wait(0.10)
                end
                if not State.RoundLive or not State.CurrentRoundKey then break end

                local roundKey = State.CurrentRoundKey
                if playedRoundKey == roundKey then
                    -- Avoid a tight loop if context detection briefly reports the same round.
                    task.wait(0.15)
                    if not State.Loop then break end
                else
                    playedRoundKey = roundKey
                    State.PlaybackArmed = false
                    local roundStartTime = tonumber(getGameAttribute("GameStartTime", State.ActiveContext))
                    Macro.attachEntityArrivalWatcher(State.ActiveContext)
                    local completed = 0
                    State.PlaybackTowerIds = {}
                    State.PlaybackTowerIdsBySourceGameId = {}
                    State.PlaybackTowerUnitByKey = {}
                    State.PlaybackTowerUnitBySourceGameId = {}
                    setStatus("Playing " .. #State.Placements .. " recorded actions", Theme.accent2)

                    for index, action in ipairs(State.Placements) do
                        if not State.Playing or State.PlaybackTaskId ~= taskId
                            or not State.RoundLive or State.CurrentRoundKey ~= roundKey then break end

                        local fallbackDelay = math.max(0, tonumber(action.delay) or 0)
                        if not waitForPlaybackTime(action, fallbackDelay, roundStartTime, taskId) then break end
                        if not State.RoundLive or State.CurrentRoundKey ~= roundKey then break end

                        local actionType = action.type or "Place" -- v2.1 and earlier macros contain placements only.
                        local actionOk, actionError = false, nil
                        if actionType == "Place" then
                            local pos, positionError = actionWorldPosition(action)
                            if not pos then
                                actionError = positionError
                            else
                                local yaw = tonumber(action.yaw) or 0
                                local payload = {
                                    Position = pos,
                                    CF = CFrame.new(pos) * CFrame.Angles(0, yaw, 0),
                                    -- Current GTD RemoteFunctions.PlaceUnit expects a numeric
                                    -- Rotation value. The old Vector3 payload caused the server
                                    -- to reject/throw during playback. `yaw` stays in CF only.
                                    Rotation = tonumber(action.rotation or action.Rotation) or 0,
                                    Valid = action.valid ~= false,
                                    WasFastPlaced = action.fast == true,
                                }
                                if tonumber(action.pathIndex) then
                                    payload.PathIndex = math.floor(tonumber(action.pathIndex))
                                    payload.DistanceAlongPath = tonumber(action.distanceAlongPath) or 0
                                end
                                setStatus(string.format("Placing %d/%d • %s", index, #State.Placements, tostring(action.unit)), Theme.accent2)
                                local placed, placeError, beforeIds, alreadyBoundId = invokePlacementWithRetry(action, payload, taskId)
                                if not placed then
                                    actionError = placeError
                                else
                                    local towerId = alreadyBoundId or Macro.waitForNewTowerId(action, beforeIds or {}, 9, taskId, nil, State.ActiveContext)
                                    if not towerId then
                                        actionError = "placed " .. tostring(action.unit) .. " but its new server ID wasn't found; dependent upgrades/abilities cannot be mapped"
                                    else
                                        local key = action.towerKey or ("legacy_tower_" .. tostring(index))
                                        State.PlaybackTowerIds[key] = towerId
                                        State.PlaybackTowerUnitByKey[key] = tostring(action.unit)
                                        local sourceGameId = tonumber(action.sourceGameId)
                                        if sourceGameId then
                                            State.PlaybackTowerIdsBySourceGameId[sourceGameId] = towerId
                                            State.PlaybackTowerUnitBySourceGameId[sourceGameId] = tostring(action.unit)
                                        end
                                        setStatus("Bound " .. key .. " -> live ID " .. tostring(towerId), Theme.green)
                                        actionOk = true
                                    end
                                end
                            end
                        elseif actionType == "Upgrade" or actionType == "Ability" or actionType == "Sell" then
                            if actionType == "Sell" and not (action.sourceRemote == "SellUnit"
                                or action.saleRequest == true or action.verifiedRemoval == true) then
                                actionOk = true
                                setStatus("Skipped malformed sale action • missing SellUnit source", Theme.amber)
                            elseif actionType == "Sell" and not State.AllowRecordedSales then
                                actionOk = true
                                setStatus("Skipped recorded sale • sales safety lock is OFF", Theme.amber)
                            else
                            local sourceGameId = tonumber(action.sourceGameId)
                            local towerId = action.towerKey and State.PlaybackTowerIds[action.towerKey]
                            if not towerId and sourceGameId then
                                towerId = State.PlaybackTowerIdsBySourceGameId
                                    and State.PlaybackTowerIdsBySourceGameId[sourceGameId]
                            end
                            local expectedUnit = action.towerKey and State.PlaybackTowerUnitByKey
                                and State.PlaybackTowerUnitByKey[action.towerKey]
                            if not expectedUnit and sourceGameId then
                                expectedUnit = State.PlaybackTowerUnitBySourceGameId
                                    and State.PlaybackTowerUnitBySourceGameId[sourceGameId]
                            end
                            if not towerId then
                                actionError = "no live tower ID bound for " .. tostring(action.towerKey or "unknown tower")
                            else
                                local liveModel = Macro.findLiveTowerModelById and Macro.findLiveTowerModelById(towerId, State.ActiveContext)
                                if not liveModel then
                                    actionError = "mapped live ID " .. tostring(towerId) .. " is not present in active Entities"
                                elseif expectedUnit and liveModel.Name ~= expectedUnit then
                                    actionError = "ID mapping mismatch: " .. tostring(towerId) .. " belongs to "
                                        .. tostring(liveModel.Name) .. ", expected " .. tostring(expectedUnit)
                                end
                                if actionError then
                                    -- Refuse to send a destructive or modifying request to a mismatched ID.
                                else
                                local remoteName = actionType == "Upgrade" and "UpgradeUnit"
                                    or actionType == "Ability" and "ActivateUnitAbility" or "SellUnit"
                                setStatus(string.format("%s %d/%d • %s • ID %s", actionType, index, #State.Placements,
                                    tostring(action.towerKey or "legacy"), tostring(towerId)), Theme.accent2)
                                if actionType == "Sell" then
                                    -- SellUnit return semantics are not consistently documented; send exactly once.
                                    actionOk, actionError = Macro.invokeTowerActionOnceWithTimeout(remoteName, towerId, 12, taskId)
                                else
                                    actionOk, actionError = Macro.invokeTowerActionWithRetry(remoteName, towerId,
                                        actionType == "Upgrade" and 25 or 10, taskId)
                                end
                                if actionOk and actionType == "Sell" then
                                    local removed, removeError = Macro.waitForTowerRemoval(towerId, 5, taskId)
                                    if removed then
                                        if action.towerKey then
                                            State.PlaybackTowerIds[action.towerKey] = nil
                                            if State.PlaybackTowerUnitByKey then State.PlaybackTowerUnitByKey[action.towerKey] = nil end
                                        end
                                        local sourceGameId = tonumber(action.sourceGameId)
                                        if sourceGameId then
                                            if State.PlaybackTowerIdsBySourceGameId then
                                                State.PlaybackTowerIdsBySourceGameId[sourceGameId] = nil
                                            end
                                            if State.PlaybackTowerUnitBySourceGameId then
                                                State.PlaybackTowerUnitBySourceGameId[sourceGameId] = nil
                                            end
                                        end
                                        if actionError then
                                            setStatus("Sell confirmed • " .. tostring(actionError), Theme.amber)
                                        end
                                    else
                                        -- Keep the live ID mapping for diagnostics; never infer a sale
                                        -- from inventory-card visibility. Continue the macro sequence.
                                        local note = actionError and (" • " .. tostring(actionError)) or ""
                                        setStatus("SellUnit did not remove the mapped tower: " .. tostring(removeError) .. note, Theme.amber)
                                    end
                                end
                                end -- live entity and unit type validation
                            end
                            end -- State.AllowRecordedSales
                        elseif actionType == "SellAll" then
                            if not State.AllowRecordedSales then
                                actionOk = true
                                setStatus("Skipped Sell All • sales safety lock is OFF", Theme.amber)
                            else
                                setStatus(string.format("Sell All %d/%d", index, #State.Placements), Theme.accent2)
                                actionOk, actionError = Macro.invokeNoArgumentRemoteWithTimeout("SellAll", 10, taskId)
                                if actionOk then
                                    State.PlaybackTowerIds = {}
                                    State.PlaybackTowerIdsBySourceGameId = {}
                                    State.PlaybackTowerUnitByKey = {}
                                    State.PlaybackTowerUnitBySourceGameId = {}
                                end
                            end
                        else
                            actionError = "unknown macro action type: " .. tostring(actionType)
                        end

                        if not actionOk then
                            if State.Playing and State.PlaybackTaskId == taskId then
                                State.Playing = false
                                State.PlaybackArmed = false
                                setStatus("Проигрывание остановлено на действии №" .. tostring(index) .. ": " .. tostring(actionError), Theme.red)
                            end
                            break
                        end
                        completed = completed + 1
                        setStatus(string.format("Completed %d/%d • %s", completed, #State.Placements, actionType), Theme.green)
                        task.wait(0.12)
                    end

                    if not State.Playing or State.PlaybackTaskId ~= taskId then break end
                    if not State.RoundLive or State.CurrentRoundKey ~= roundKey then
                        if not State.Loop then break end
                    elseif completed == #State.Placements then
                        if not State.Loop then
                            State.Playing = false
                            State.PlaybackArmed = false
                            setStatus("Macro complete • " .. completed .. " actions sent", Theme.green)
                            break
                        end
                        State.PlaybackArmed = true
                        setStatus("Macro complete • waiting for next match", Theme.green)
                    end
                end

                if not State.Loop then
                    State.Playing = false
                    State.PlaybackArmed = false
                    setStatus("Macro repeat disabled", Theme.amber)
                    break
                end
                repeat task.wait(0.15) until not State.Playing or State.PlaybackTaskId ~= taskId
                    or not State.Loop or (State.RoundLive and State.CurrentRoundKey ~= playedRoundKey)
            end
        end, State.ErrorTrace)
        if not ok and State.PlaybackTaskId == taskId then
            State.Playing = false
            State.PlaybackArmed = false
            State.ReportRuntimeError("ошибка проигрывания макроса", err)
        end
    end)
end

connect(RecordBtn.Activated, startRecording)
connect(StopRecordBtn.Activated, stopRecordingAndSave)
connect(CopyMacroJSONBtn.Activated, copyMacroJSON)
connect(CopyActionListBtn.Activated, copyMacroActionList)
connect(ReplaySalesToggle.Activated, function()
    State.AllowRecordedSales = not State.AllowRecordedSales
    ReplaySalesToggle.Text = State.AllowRecordedSales and "ON • ALLOW" or "OFF • SAFE"
    ReplaySalesToggle.BackgroundColor3 = State.AllowRecordedSales and Theme.red or Theme.panel3
    setStatus(State.AllowRecordedSales and "Recorded sales enabled" or "Recorded sales blocked for safety", State.AllowRecordedSales and Theme.amber or Theme.green)
end)
connect(PlayBtn.Activated, playMacro)
connect(StopPlayBtn.Activated, stopPlayback)
connect(DashStartButton.Activated, playMacro)
connect(DashStopButton.Activated, function()
    if State.Recording then stopRecordingAndSave() end
    if State.Playing then stopPlayback() end
end)
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

-- GTD GameStartTime is a Unix timestamp. GameEndTime must NOT be treated as
-- "ended" merely because it is a positive number: some builds expose a future
-- end/deadline timestamp while the round is still live. Use the visible GameEnd
-- overlay as the authoritative UI signal; only treat a numeric GameEndTime as
-- ended once an epoch timestamp has actually passed.
Macro.isGameEndOverlayVisible = function()
    for _, rootName in ipairs({"GameGui", "GameGuiNoInset"}) do
        local root = PlayerGui:FindFirstChild(rootName)
        local screen = root and root:FindFirstChild("Screen")
        local middle = screen and screen:FindFirstChild("Middle")
        local endGui = middle and middle:FindFirstChild("GameEnd")
        if endGui and endGui:IsA("GuiObject") and endGui.Visible then
            return true
        end
    end
    return false
end

Macro.isContextEnded = function(context)
    local endTime = context and context:GetAttribute("GameEndTime")
    if endTime == true then return true end
    if type(endTime) == "number" and endTime >= 1000000000 then
        local now = os.time()
        local ok, serverNow = pcall(function() return Workspace:GetServerTimeNow() end)
        if ok and type(serverNow) == "number" then now = serverNow end
        if endTime <= now then return true end
    end
    return Macro.isGameEndOverlayVisible()
end

local function getActiveContext()
    local contexts = Workspace:FindFirstChild("Contexts")
    if not contexts then return nil end
    local children = contexts:GetChildren()
    if #children == 0 then return nil end

    local bestActive, bestActiveScore = nil, -math.huge
    local bestCandidate, bestCandidateScore = nil, -math.huge
    for _, context in ipairs(children) do
        local isCandidate = context:IsA("Folder") or context:FindFirstChild("Entities")
            or context:GetAttribute("Config") ~= nil or context:GetAttribute("RunId") ~= nil
        if isCandidate then
            local startTime = context:GetAttribute("GameStartTime")
            local voteEnd = context:GetAttribute("DifficultyVoteEnd")
            local suffix = tonumber(context.Name:match("(%d+)$")) or 0
            local score = math.max(suffix * 1000,
                (type(startTime) == "number" and startTime or 0),
                (type(voteEnd) == "number" and voteEnd or 0))
            if score > bestCandidateScore then
                bestCandidate, bestCandidateScore = context, score
            end

            local hasStarted = type(startTime) == "number" and startTime > 0
            local hasEnded = Macro.isContextEnded(context)
            if hasStarted and not hasEnded then
                -- A real running Context outranks stale lobby/vote Contexts.
                local activeScore = 1000000000000 + startTime
                if activeScore > bestActiveScore then
                    bestActive, bestActiveScore = context, activeScore
                end
            end
        end
    end
    return bestActive or bestCandidate or children[#children]
end

getGameAttribute = function(attributeName, context)
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
    -- A Context folder or Entities container can exist during voting/loading.
    -- GameStartTime marks a started match. A future GameEndTime is a deadline,
    -- not proof that the match has already ended; use isContextEnded() instead.
    local startTime = getGameAttribute("GameStartTime", context)
    if type(startTime) ~= "number" or startTime <= 0 then return false end
    if Macro.isContextEnded(context) then return false end
    return true
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
            if not State.Playing then setStatus("Server state confirmed: " .. tostring(speed) .. "×", Theme.green) end
        elseif showFeedback ~= false and not State.Playing then
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
        if not State.Playing then setStatus("Unsupported difficulty: " .. tostring(State.DesiredDifficulty), Theme.amber) end
        return false
    end
    local remote = getRemote("RemoteFunctions", "PlaceDifficultyVote", "RemoteFunction")
    if not remote then
        if not State.Playing then setStatus("RemoteFunctions.PlaceDifficultyVote not found", Theme.red) end
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
        if not State.Playing then setStatus("Waiting for active GTD Context before voting " .. difficultyId, Theme.amber) end
        return false
    else
        ok, result = pcall(function()
            return remote:InvokeServer(difficultyId)
        end)
    end

    if not ok then
        if not State.Playing then setStatus("PlaceDifficultyVote failed: " .. tostring(result), Theme.red) end
        return false
    end

    if not context then
        if not State.Playing then setStatus("PlaceDifficultyVote(" .. difficultyId .. ") sent (legacy API; no Context folder)", Theme.accent2) end
        return true
    end

    -- Confirm against the authoritative Context attribute. Returning from InvokeServer
    -- only proves the request did not throw; it does not prove the vote was accepted.
    task.wait(0.35)
    local actual = context:GetAttribute("Difficulty")
    if difficultyMatches(actual, difficultyId) then
        if not State.Playing then setStatus("GTD confirmed difficulty: " .. State.DesiredDifficulty, Theme.green) end
        return true
    end

    if not State.Playing then
        setStatus("Vote sent: " .. difficultyId .. " • server Context.Difficulty=" .. tostring(actual or "not updated") .. " • retrying", Theme.amber)
    end
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
        task.wait(0.10)
        local context = getActiveContext()
        local roundKey = getRoundKey(context)
        local liveRound = isInLiveRound(context)
        State.ActiveContext = context
        State.RoundLive = liveRound
        State.CurrentRoundKey = roundKey

        -- Recorder starts only after GTD publishes a real GameStartTime.
        if State.RecordingArmed and liveRound and not State.Playing then
            beginRecordingForRound(roundKey)
        end
        -- Automatically seal the macro as soon as this match ends or a new run replaces it.
        if State.Recording and (not liveRound or State.RecordingRoundKey ~= roundKey) then
            stopRecordingAndSave()
        end

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
                    if not State.Playing then
                        setStatus("Difficulty not confirmed after " .. tostring(MAX_DIFFICULTY_VOTE_ATTEMPTS) .. " attempts. Check current vote phase / Context.", Theme.red)
                    end
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
    local goal = minimized and UDim2.fromOffset(1180,68) or UDim2.fromOffset(1180,780)
    tween(Main, 0.25, {Size = goal})
    tween(Shadow, 0.25, {Size = minimized and UDim2.fromOffset(1200,78) or UDim2.fromOffset(1200,800)})
    Sidebar.Visible = not minimized
    Content.Visible = not minimized
    Minimize.Text = minimized and "□" or "—"
end
connect(Minimize.Activated, function() setMinimized(not minimized) end)
connect(Close.Activated, function()
    State.Recording = false
    State.RecordingArmed = false
    State.RecordingRoundKey = nil
    State.Playing = false
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    tween(Main, 0.18, {Size = UDim2.fromOffset(1180,0)})
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
Main.Size = UDim2.fromOffset(1080, 700)
Main.BackgroundTransparency = 1
Shadow.Size = UDim2.fromOffset(1100, 720)
tween(Main, 0.35, {Size = UDim2.fromOffset(1180,780), BackgroundTransparency = 0.20}, Enum.EasingStyle.Back)
tween(Shadow, 0.35, {Size = UDim2.fromOffset(1200,800)}, Enum.EasingStyle.Back)
showPage("Overview")
setStatus("Ready • direct GTD remote mode", Theme.accent2)
if updateDashboard then updateDashboard() end

-- Persist a complete cleanup callback so the next execution cannot leave stale UI
-- listeners, entity watchers or automation workers attached to the previous instance.
if type(ENV.__GTD_CONTROL_HUB) == "table" then
    ENV.__GTD_CONTROL_HUB.Cleanup = function()
        State.Shutdown = true
        State.Recording = false
        State.RecordingArmed = false
        State.Playing = false
        State.PlaybackArmed = false
        State.PlaybackTaskId = (tonumber(State.PlaybackTaskId) or 0) + 1
        for _, connection in ipairs(Connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(Connections)
        if Macro and type(Macro.cleanup) == "function" then pcall(Macro.cleanup) end
        if Gui and Gui.Parent then pcall(function() Gui:Destroy() end) end
    end
    ENV.__GTD_CONTROL_HUB.SetStatus = setStatus
    ENV.__GTD_CONTROL_HUB.Connections = Connections
end

-- Startup is isolated: an executor hook failure must not abort the UI itself.
local hookInitOk, hookInitResult = pcall(Macro.installPlaceHook)
if not hookInitOk then
    State.ReportRuntimeError("macro hook initialization", hookInitResult)
elseif hookInitResult ~= true then
    setStatus("Macro hook unavailable • " .. tostring(hookInitResult or "unknown executor limitation"), Theme.amber)
end

local watcherInitOk, watcherInitError = pcall(Macro.startTowerLevelWatcher)
if not watcherInitOk then
    State.ReportRuntimeError("level watcher initialization", watcherInitError)
end

local automationInitOk, automationInitError = pcall(function()
    task.spawn(function()
        local ok, err = xpcall(runAutomation, State.ErrorTrace)
        if not ok and not State.Shutdown then State.ReportRuntimeError("automation worker", err) end
    end)
end)
if not automationInitOk then
    State.ReportRuntimeError("automation worker startup", automationInitError)
end

print("[GTD Control Hub v2.2.20] Loaded. Dual InvokeServer hooks; bounded tower-level watcher; numeric PlaceUnit Rotation payload.")
