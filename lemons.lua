local BASE_URL = "https://plunderer-hub.caceresforums.workers.dev/?file="
local C     = loadstring(game:HttpGet(BASE_URL .. "shared/constants.lua", true))()
local Keys = {}

function Keys.show(_, data, callback)
    -- bypass key system completely
    callback()
end
local UILib = loadstring(game:HttpGet(BASE_URL .. "shared/ui.lua",        true))()

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local TeleportService     = game:GetService("TeleportService")
local TweenService        = game:GetService("TweenService")
local StarterGui          = game:GetService("StarterGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local localPlayer = Players.LocalPlayer

Keys.show(C, {gameName = "Sell Lemons Edition"}, function()

local States = {
    autobuy      = false,
    autoupgrade  = false,
    autocashvine = false,
    autocashdrop = false,
    antiafk      = false,
    noclip       = false,
    uitoggle     = true,
}

local Keybinds = {
    autobuy      = Enum.KeyCode.Z,
    autoupgrade  = Enum.KeyCode.X,
    autocashvine = Enum.KeyCode.C,
    autocashdrop = Enum.KeyCode.V,
    antiafk      = Enum.KeyCode.RightAlt,
    noclip       = Enum.KeyCode.N,
    uitoggle     = Enum.KeyCode.L,
}

local ListeningToBind = nil
local scriptRunning   = true
local Connections     = {}
local walkSpeed       = 16

local tpUFOKey   = false
local tpVineDoor = false
local tpVineKey  = false
local pullLeversFlag = false

local myTycoon = nil
local function findMyTycoon()
    for _, t in ipairs(workspace:GetChildren()) do
        if t.Name:find("Tycoon") then
            local ov = t:FindFirstChild("Owner")
            if ov and ov:IsA("ObjectValue") and ov.Value == localPlayer then
                return t
            end
        end
    end
    return nil
end
myTycoon = findMyTycoon()
task.spawn(function()
    while scriptRunning do
        task.wait(5)
        if not myTycoon or not myTycoon.Parent then myTycoon = findMyTycoon() end
    end
end)

local function getSewer()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("Sewer")
end

local function getRoot()
    local char = localPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid"), char
end

task.spawn(function()
    while scriptRunning do
        if not States.autobuy or not myTycoon then task.wait(0.5) continue end
        task.wait(0.05)
        local purchases = myTycoon:FindFirstChild("Purchases")
        if not purchases then continue end
        for _, desc in ipairs(purchases:GetDescendants()) do
            if not States.autobuy then break end
            if desc:IsA("ProximityPrompt") then
                pcall(function() fireproximityprompt(desc) end)
            end
        end
    end
end)

task.spawn(function()
    while scriptRunning do
        if not States.autoupgrade or not myTycoon then task.wait(0.5) continue end
        task.wait(0.3)
        local root = getRoot()
        if not root then continue end
        local origCF = root.CFrame
        local purchases = myTycoon:FindFirstChild("Purchases")
        if not purchases then continue end
        for _, desc in ipairs(purchases:GetDescendants()) do
            if not States.autoupgrade then break end
            if desc:IsA("BasePart") and desc.Name == "Button" then
                root.CFrame = CFrame.new(desc.Position)
                task.wait(0.08)
            end
        end
        if root and root.Parent then root.CFrame = origCF end
    end
end)

task.spawn(function()
    while scriptRunning do
        if not States.autocashvine then task.wait(0.5) continue end
        task.wait(0.2)
        local root = getRoot()
        if not root then continue end
        local sewer = getSewer()
        local cashVine = sewer and sewer:FindFirstChild("CashVine")
        if not cashVine then continue end
        local origCF = root.CFrame
        for _, desc in ipairs(cashVine:GetDescendants()) do
            if not States.autocashvine then break end
            if desc:IsA("ProximityPrompt") then
                pcall(function() fireproximityprompt(desc) end)
                task.wait(0.02)
            elseif desc:IsA("BasePart") and (desc.Name == "Cash" or desc.Name:lower():find("cash")) then
                root.CFrame = CFrame.new(desc.Position)
                task.wait(0.05)
            end
        end
        if root and root.Parent then root.CFrame = origCF end
    end
end)

task.spawn(function()
    while scriptRunning do
        if not States.autocashdrop then task.wait(0.5) continue end
        task.wait(0.15)
        local root = getRoot()
        if not root then continue end
        local cashDrops = workspace:FindFirstChild("CashDrops")
        if not cashDrops then continue end
        local origCF = root.CFrame
        for _, drop in ipairs(cashDrops:GetChildren()) do
            if not States.autocashdrop then break end
            local pos
            if drop:IsA("Model") and drop.PrimaryPart then pos = drop.PrimaryPart.Position
            elseif drop:IsA("BasePart") then pos = drop.Position end
            if pos then
                root.CFrame = CFrame.new(pos)
                task.wait(0.05)
                for _, desc in ipairs(drop:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        pcall(function() fireproximityprompt(desc) end)
                    end
                end
            end
        end
        if root and root.Parent then root.CFrame = origCF end
    end
end)

task.spawn(function()
    while scriptRunning do
        if not pullLeversFlag then task.wait(0.3) continue end
        local root = getRoot()
        local sewer = getSewer()
        if not root or not sewer then pullLeversFlag = false continue end
        local origCF = root.CFrame
        for _, child in ipairs(sewer:GetChildren()) do
            if child.Name:lower():find("door") then
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc.Name == "Lever" and desc:IsA("BasePart") then
                        root.CFrame = CFrame.new(desc.Position + Vector3.new(0, 3, 0))
                        task.wait(0.2)
                        local pp = desc:FindFirstChildOfClass("ProximityPrompt")
                            or desc.Parent:FindFirstChildOfClass("ProximityPrompt")
                        if pp then
                            pcall(function() fireproximityprompt(pp) end)
                            task.wait(0.1)
                        else
                            for _, d2 in ipairs(child:GetDescendants()) do
                                if d2:IsA("ProximityPrompt") then
                                    local p = d2.Parent:IsA("BasePart") and d2.Parent.Position + Vector3.new(0,3,0) or desc.Position + Vector3.new(0,3,0)
                                    root.CFrame = CFrame.new(p)
                                    task.wait(0.15)
                                    pcall(function() fireproximityprompt(d2) end)
                                    task.wait(0.1)
                                end
                            end
                        end
                    end
                end
            end
        end
        if root and root.Parent then root.CFrame = origCF end
        pullLeversFlag = false
    end
end)

task.spawn(function()
    while scriptRunning do
        task.wait(0.1)
        local root = getRoot()
        if not root then continue end
        if tpUFOKey then
            local sewer = getSewer()
            local k = sewer and sewer:FindFirstChild("SewerAlien") and sewer.SewerAlien:FindFirstChild("UFOKey")
            if k and k:IsA("BasePart") then root.CFrame = CFrame.new(k.Position + Vector3.new(0, 3, 0)) end
            tpUFOKey = false
        end
        if tpVineDoor then
            local sewer = getSewer()
            local d = sewer and sewer:FindFirstChild("CashVine") and sewer.CashVine:FindFirstChild("VineDoor")
            if d and d:IsA("BasePart") then root.CFrame = CFrame.new(d.Position + Vector3.new(0, 3, 0)) end
            tpVineDoor = false
        end
        if tpVineKey then
            local sewer = getSewer()
            local k = sewer and sewer:FindFirstChild("CashVine") and sewer.CashVine:FindFirstChild("VineKey")
            if k and k:IsA("BasePart") then root.CFrame = CFrame.new(k.Position + Vector3.new(0, 3, 0)) end
            tpVineKey = false
        end
    end
end)

local speedConn = RunService.Heartbeat:Connect(function()
    if not scriptRunning then return end
    local _, hum = getRoot()
    if hum and hum.WalkSpeed ~= walkSpeed then hum.WalkSpeed = walkSpeed end
end)
table.insert(Connections, speedConn)

local noclipConn = RunService.Stepped:Connect(function()
    if not scriptRunning or not States.noclip then return end
    local char = localPlayer.Character
    if not char then return end
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)
table.insert(Connections, noclipConn)

localPlayer.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then hum.WalkSpeed = walkSpeed end
end)

local afkConn = localPlayer.Idled:Connect(function()
    if States.antiafk and scriptRunning then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
    end
end)
table.insert(Connections, afkConn)

local oldGui = localPlayer.PlayerGui:FindFirstChild("GothamHubSL")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "GothamHubSL"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 760, 0, 600)
main.Position = UDim2.new(0.5, -380, 0.5, -300)
main.BackgroundColor3 = C.BG_HUB
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner").Parent = main
Instance.new("UIStroke", main).Color = C.VINO_TINTO_EXTREMO

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 65)
topBar.BackgroundTransparency = 1
topBar.Parent = main

local logo = Instance.new("ImageLabel")
logo.Size = UDim2.new(0, 58, 0, 58)
logo.Position = UDim2.new(0, 14, 0.5, -29)
logo.BackgroundTransparency = 1
logo.Image = C.LOGO_ID
logo.Parent = topBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0, 220, 1, 0)
titleLbl.Position = UDim2.new(0, 88, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.TextColor3 = C.TEXT_MAIN
titleLbl.Text = "GOTHAM HUB"
titleLbl.Font = C.FONT_HUB_TITLE
titleLbl.TextSize = 16
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = topBar

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 240, 1, -65)
sidebar.Position = UDim2.new(0, 0, 0, 65)
sidebar.BackgroundColor3 = C.BG_SIDE
sidebar.BorderSizePixel = 0
sidebar.Parent = main
local sideSep = Instance.new("Frame")
sideSep.Size = UDim2.new(0, 1, 1, 0)
sideSep.Position = UDim2.new(1, -1, 0, 0)
sideSep.BackgroundColor3 = C.VINO_TINTO_EXTREMO
sideSep.Parent = sidebar

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -240, 1, -65)
contentArea.Position = UDim2.new(0, 240, 0, 65)
contentArea.BackgroundTransparency = 1
contentArea.Parent = main

local function makePage()
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.Parent = contentArea
    return f
end
local mainPage      = makePage() mainPage.Visible = true
local teleportsPage = makePage()
local settingsPage  = makePage()
local actionsPage   = makePage()

local UI = UILib.new({
    constants    = C,
    States       = States,
    Keybinds     = Keybinds,
    Connections  = Connections,
    getListening = function() return ListeningToBind end,
    setListening = function(v) ListeningToBind = v end,
})

local navMainBtn,      navMainLbl      = UI.createNavItem(sidebar, nil, "Main Scripts", 10)
local navTeleportsBtn, navTeleportsLbl = UI.createNavItem(sidebar, nil, "Teleports",    60)
local navSettingsBtn,  navSettingsLbl  = UI.createNavItem(sidebar, nil, "Settings",    110)
local navActionsBtn,   navActionsLbl   = UI.createNavItem(sidebar, nil, "Actions",     160)
navMainLbl.TextColor3 = C.TEXT_MAIN

local function reset()
    for _, l in ipairs({navMainLbl, navTeleportsLbl, navSettingsLbl, navActionsLbl}) do
        l.TextColor3 = C.TEXT_DIM
    end
end
local function switchTo(page, lbl)
    reset()
    lbl.TextColor3 = C.TEXT_MAIN
    for _, p in ipairs({mainPage, teleportsPage, settingsPage, actionsPage}) do p.Visible = false end
    page.Visible = true
end
navMainBtn.MouseButton1Click     :Connect(function() switchTo(mainPage,      navMainLbl)      end)
navTeleportsBtn.MouseButton1Click:Connect(function() switchTo(teleportsPage, navTeleportsLbl) end)
navSettingsBtn.MouseButton1Click :Connect(function() switchTo(settingsPage,  navSettingsLbl)  end)
navActionsBtn.MouseButton1Click  :Connect(function() switchTo(actionsPage,   navActionsLbl)   end)

do
    local leftScroll = Instance.new("ScrollingFrame")
    leftScroll.Size = UDim2.new(0.5, -15, 1, -30)
    leftScroll.Position = UDim2.new(0, 10, 0, 10)
    leftScroll.BackgroundColor3 = C.BG_CARD
    leftScroll.BorderSizePixel = 0
    leftScroll.ScrollBarThickness = 4
    leftScroll.ScrollBarImageColor3 = C.VINO_TINTO_EXTREMO
    leftScroll.CanvasSize = UDim2.new(0, 0, 0, 320)
    leftScroll.Parent = mainPage
    Instance.new("UICorner").Parent = leftScroll
    Instance.new("UIStroke", leftScroll).Color = C.VINO_TINTO_EXTREMO

    UI.createSectionTitle(leftScroll, "Main Scripts:", 10)
    UI.createFeatureRow(leftScroll, "Auto Buy",        45,  "autobuy")
    UI.createFeatureRow(leftScroll, "Auto Upgrade",    85,  "autoupgrade")
    UI.createFeatureRow(leftScroll, "Auto Cash Vine", 125,  "autocashvine")
    UI.createFeatureRow(leftScroll, "Auto Cash Drops",165, "autocashdrop")

    local right = Instance.new("Frame")
    right.Size = UDim2.new(0.5, -15, 1, -30)
    right.Position = UDim2.new(0.5, 5, 0, 10)
    right.BackgroundColor3 = C.BG_CARD
    right.Parent = mainPage
    Instance.new("UICorner").Parent = right
    Instance.new("UIStroke", right).Color = C.VINO_TINTO_EXTREMO

    local rTitle = Instance.new("TextLabel")
    rTitle.Size = UDim2.new(1, -20, 0, 35)
    rTitle.Position = UDim2.new(0, 15, 0, 5)
    rTitle.BackgroundTransparency = 1
    rTitle.TextColor3 = C.TEXT_MAIN
    rTitle.Text = "Information Panel"
    rTitle.Font = C.FONT_HUB_TITLE
    rTitle.TextSize = 14
    rTitle.TextXAlignment = Enum.TextXAlignment.Left
    rTitle.Parent = right
    local rSep = Instance.new("Frame")
    rSep.Size = UDim2.new(1, -30, 0, 1)
    rSep.Position = UDim2.new(0, 15, 0, 42)
    rSep.BackgroundColor3 = C.VINO_TINTO_EXTREMO
    rSep.Parent = right

    local function info(text, y)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -30, 0, 22)
        l.Position = UDim2.new(0, 15, 0, y)
        l.BackgroundTransparency = 1
        l.TextColor3 = Color3.fromRGB(160, 160, 160)
        l.Text = text
        l.Font = C.FONT_LABEL
        l.TextSize = 13
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = right
    end
    info("User: "..localPlayer.Name, 55)
    info("Executor: "..(identifyexecutor and identifyexecutor() or "Unknown"), 79)
    info("Game: Sell Lemons", 103)
    info("Owner: caceresman", 127)

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -30, 0, 25)
    sub.Position = UDim2.new(0, 50, 0, 150)
    sub.BackgroundTransparency = 1
    sub.TextColor3 = Color3.fromRGB(140, 140, 140)
    sub.Text = "Noah"
    sub.Font = C.FONT_OWNER_SUB
    sub.TextSize = 13
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = right

    local baseSep = Instance.new("Frame")
    baseSep.Size = UDim2.new(1, -30, 0, 1)
    baseSep.Position = UDim2.new(0, 15, 0, 180)
    baseSep.BackgroundColor3 = C.VINO_TINTO_EXTREMO
    baseSep.Parent = right

    local baseLabel = Instance.new("TextLabel")
    baseLabel.Size = UDim2.new(1, -20, 0, 40)
    baseLabel.Position = UDim2.new(0, 10, 0, 190)
    baseLabel.BackgroundTransparency = 1
    baseLabel.TextColor3 = C.TEXT_RED
    baseLabel.Text = "Searching for your base..."
    baseLabel.Font = C.FONT_LABEL_BOLD
    baseLabel.TextSize = 12
    baseLabel.TextWrapped = true
    baseLabel.TextXAlignment = Enum.TextXAlignment.Left
    baseLabel.Parent = right

    task.spawn(function()
        while scriptRunning do
            task.wait(3)
            if myTycoon and myTycoon.Parent then
                baseLabel.TextColor3 = C.TEXT_GREEN
                baseLabel.Text = "Base linked: "..myTycoon.Name
            else
                myTycoon = findMyTycoon()
                baseLabel.TextColor3 = C.TEXT_RED
                baseLabel.Text = "Searching for your base..."
            end
        end
    end)
end

do
    local tpCard = Instance.new("Frame")
    tpCard.Size = UDim2.new(1, -20, 1, -20)
    tpCard.Position = UDim2.new(0, 10, 0, 10)
    tpCard.BackgroundColor3 = C.BG_CARD
    tpCard.Parent = teleportsPage
    Instance.new("UICorner").Parent = tpCard
    Instance.new("UIStroke", tpCard).Color = C.VINO_TINTO_EXTREMO

    UI.createSectionTitle(tpCard, "Teleports", 5)
    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, -30, 0, 1)
    sep.Position = UDim2.new(0, 15, 0, 42)
    sep.BackgroundColor3 = C.VINO_TINTO_EXTREMO
    sep.Parent = tpCard

    local tpStand = UI.createActionButton(tpCard, "TP â†’ Lemon Stand", "Teleport to your tycoon base", 55)
    tpStand.MouseButton1Click:Connect(function()
        if not myTycoon then return end
        local root = getRoot()
        if not root then return end
        local target
        for _, name in ipairs({"Floor", "MainPart", "Entrance", "Spawn", "Base", "Core"}) do
            local f = myTycoon:FindFirstChild(name, true)
            if f and f:IsA("BasePart") then target = f break end
        end
        if not target then
            for _, desc in ipairs(myTycoon:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Transparency < 1 then target = desc break end
            end
        end
        if target then root.CFrame = CFrame.new(target.Position + Vector3.new(0, 5, 0)) end
    end)

    local tpUfo = UI.createActionButton(tpCard, "TP â†’ UFO Key", "Teleport to UFO key location", 125)
    tpUfo.MouseButton1Click:Connect(function() tpUFOKey = true end)

    local tpVDoor = UI.createActionButton(tpCard, "TP â†’ Vine Doors", "Teleport to the vine doors", 195)
    tpVDoor.MouseButton1Click:Connect(function() tpVineDoor = true end)

    local tpVKey = UI.createActionButton(tpCard, "TP â†’ Vine Key", "Teleport to the vine key", 265)
    tpVKey.MouseButton1Click:Connect(function() tpVineKey = true end)
end

do
    local sCard = Instance.new("Frame")
    sCard.Size = UDim2.new(1, -20, 1, -20)
    sCard.Position = UDim2.new(0, 10, 0, 10)
    sCard.BackgroundColor3 = C.BG_CARD
    sCard.Parent = settingsPage
    Instance.new("UICorner").Parent = sCard
    Instance.new("UIStroke", sCard).Color = C.VINO_TINTO_EXTREMO

    UI.createSectionTitle(sCard, "Hub Settings", 10)
    UI.createFeatureRow(sCard, "Toggle UI Keybind", 50,  "uitoggle")
    UI.createFeatureRow(sCard, "Anti-AFK Mode",     90,  "antiafk")
    UI.createFeatureRow(sCard, "Noclip Mode",      130,  "noclip")
    UI.createSlider(sCard, "WalkSpeed",            175, 16, 100, 16, function(v)
        walkSpeed = v
        local _, hum = getRoot()
        if hum then hum.WalkSpeed = v end
    end)

end

do
    local aCard = Instance.new("Frame")
    aCard.Size = UDim2.new(1, -20, 1, -20)
    aCard.Position = UDim2.new(0, 10, 0, 10)
    aCard.BackgroundColor3 = C.BG_CARD
    aCard.Parent = actionsPage
    Instance.new("UICorner").Parent = aCard
    Instance.new("UIStroke", aCard).Color = C.VINO_TINTO_EXTREMO

    UI.createSectionTitle(aCard, "Actions", 5)

    local rejoin = UI.createActionButton(aCard, "Rejoin Server", "Reconnects to the current server", 50)
    rejoin.MouseButton1Click:Connect(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, localPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
        end
    end)

    local pull = UI.createActionButton(aCard, "Pull All Levers", "Pulls all sewer levers once", 120)
    pull.MouseButton1Click:Connect(function() pullLeversFlag = true end)

    local unload = UI.createActionButton(aCard, "Unload Script", "Disables and removes the hub", 190, C.TEXT_RED)
    -- Discord icon button (blurple, interactive)
    local _dWrap = Instance.new("Frame")
    _dWrap.Size = UDim2.new(0, 44, 0, 44)
    _dWrap.Position = UDim2.new(0.5, -22, 0, 245)
    _dWrap.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
    _dWrap.BorderSizePixel = 0
    _dWrap.Parent = aCard
    Instance.new("UICorner").Parent = _dWrap
    local _dIcon = Instance.new("ImageButton")
    _dIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
    _dIcon.Position = UDim2.new(0.1, 0, 0.1, 0)
    _dIcon.BackgroundTransparency = 1
    _dIcon.Image = C.DISCORD_IMG_ID
    _dIcon.Parent = _dWrap
    _dIcon.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard("https://discord.gg/AD5NsXxMjn")
            _dWrap.BackgroundColor3 = Color3.fromRGB(60, 80, 200)
            task.delay(1.5, function() _dWrap.BackgroundColor3 = Color3.fromRGB(88, 101, 242) end)
        end
    end)


    unload.MouseButton1Click:Connect(function()
        scriptRunning = false
        for _, c in pairs(Connections) do pcall(function() c:Disconnect() end) end
        pcall(function() gui:Destroy() end)
    end)
end

local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if ListeningToBind then
        Keybinds[ListeningToBind] = input.KeyCode
        ListeningToBind = nil
        return
    end
    for feature, key in pairs(Keybinds) do
        if key and key ~= Enum.KeyCode.None and input.KeyCode == key then
            if feature == "uitoggle" then
                main.Visible = not main.Visible
            else
                States[feature] = not States[feature]
            end
        end
    end
end)
table.insert(Connections, inputConn)

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "Gotham Hub",
        Text  = "Sell Lemons loaded. Press L to toggle.",
        Duration = 5,
    })
end)

end)