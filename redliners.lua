local BASE_URL = "https://plunderer-hub.caceresforums.workers.dev/?file="
local C    = loadstring(game:HttpGet(BASE_URL.."shared/constants.lua",true))()
local Keys = {}

function Keys.show(_, data, callback)
    -- bypass key system completely
    callback()
end

local Players = game:GetService("Players")
local Run     = game:GetService("RunService")
local UIS     = game:GetService("UserInputService")
local Http    = game:GetService("HttpService")
local SG      = game:GetService("StarterGui")
local WS      = game:GetService("Workspace")
local VIM     = game:GetService("VirtualInputManager")
local lp      = Players.LocalPlayer

-- ── Persistence ───────────────────────────────────────────────────────────────
local function cfgPath(tag)
    return("GothamHub_REDLINERS_%s_%s.json"):format((lp.Name or"u"):gsub("[^%w]",""),tag)
end
local function saveCfg(t,d) if writefile then pcall(function() writefile(cfgPath(t),Http:JSONEncode(d)) end) end end
local function loadCfg(t,def)
    if not isfile or not isfile(cfgPath(t)) then return def end
    local ok,r=pcall(function() return Http:JSONDecode(readfile(cfgPath(t))) end)
    if not ok or type(r)~="table" then return def end
    for k,v in pairs(def) do if r[k]==nil then r[k]=v end end return r
end
local function loadBuilds()
    if not isfile or not isfile(cfgPath("builds")) then return{} end
    local ok,d=pcall(function() return Http:JSONDecode(readfile(cfgPath("builds"))) end)
    return(ok and type(d)=="table") and d or{}
end
local function saveBuilds(b) if writefile then pcall(function() writefile(cfgPath("builds"),Http:JSONEncode(b)) end) end end
local function getAutoLoad()
    if not isfile or not isfile(cfgPath("autoload")) then return nil end
    local ok,d=pcall(function() return Http:JSONDecode(readfile(cfgPath("autoload"))) end)
    return(ok and type(d)=="table") and d.buildName or nil
end
local function setAutoLoad(name)
    if name then saveCfg("autoload",{buildName=name})
    else if delfile then pcall(function() delfile(cfgPath("autoload")) end) end end
end
local function notify(t,d) pcall(function() SG:SetCore("SendNotification",{Title="Gotham Hub",Text=t,Duration=d or 3}) end) end

Keys.show(C,{gameName="REDLINERS"},function()

-- ── State & Config ────────────────────────────────────────────────────────────
local ON  = {}
local Cfg = loadCfg("cfg",{
    fovRadius  = 150,
    smoothing  = 1.0,    -- 1.0 = instant snap (brusco/directo), <1 = smooth
    parryRange = 30,
    maxDist    = 800,
})
local Keybinds = loadCfg("keybinds",{
    autoparry   = "P",
    esp         = "H",
    chams       = "J",
    wallcheck   = "K",
    showfov     = "B",
    aimbot      = "None",  -- aimbot is hold Q/LMB, no toggle key needed
    togglehub   = "L",
})
local conns  = {}
local alive  = true
local BOXES  = {}   -- SelectionBox refs  (esp boxes)
local CHAMS  = {}   -- Highlight refs     (chams esp)
local activeLoadedBuild = nil
local listeningFor = nil
local kbBtnRefs = {}
local togBtnRefs = {}

-- ── Entity helpers ────────────────────────────────────────────────────────────
local function getEntitiesFolder() return WS:FindFirstChild("Entities") end
local function getMyChar() return lp.Character end
local function getMyRoot()
    local c=getMyChar() return c and c:FindFirstChild("HumanoidRootPart")
end

local function isEnemy(entity)
    local myChar=getMyChar()
    if entity==myChar then return false end
    local hum=entity:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health>0
end

local function getEnemies()
    local myChar = getMyChar()
    local seen   = {}
    local t      = {}

    local function tryAdd(model)
        if not model or model == myChar or seen[model] then return end
        local hum  = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        if hum and hum.Health > 0 and root then
            seen[model] = true
            t[#t+1] = {model=model, root=root}
        end
    end

    -- Source 1: workspace.Entities (game's primary entity folder)
    local ef = getEntitiesFolder()
    if ef then for _, e in ipairs(ef:GetChildren()) do tryAdd(e) end end

    -- Source 2: Players[*].Character (catches far/streamed players)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character then tryAdd(plr.Character) end
    end

    return t
end

local function getNearestEnemy()
    local cam=WS.CurrentCamera
    local center=cam.ViewportSize/2
    local best,bestDist=nil,math.huge
    for _,e in ipairs(getEnemies()) do
        local head=e.model:FindFirstChild("Head") or e.root
        local pos,vis=cam:WorldToViewportPoint(head.Position)
        if vis then
            local d=(Vector2.new(pos.X,pos.Y)-center).Magnitude
            if d<bestDist and d<=Cfg.fovRadius then
                bestDist=d best=e
            end
        end
    end
    return best
end

-- Wall check: raycast from our root to enemy root
local function hasLOS(enemyRoot)
    local myRoot=getMyRoot() if not myRoot then return true end
    local origin=myRoot.Position
    local dir=enemyRoot.Position-origin
    local params=RaycastParams.new()
    params.FilterDescendantsInstances={getMyChar(),getEntitiesFolder()}
    params.FilterType=Enum.RaycastFilterType.Exclude
    local result=WS:Raycast(origin,dir,params)
    return result==nil  -- nil = nothing in the way = has LOS
end

-- ── Auto Parry ────────────────────────────────────────────────────────────────
local parryCooldown = false
local parryAnims    = {}   -- track which animation IDs we've seen start

local function pressF()
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
end

local parryTimer = 0
table.insert(conns, Run.Heartbeat:Connect(function(dt)
    if not alive or not ON.autoparry or parryCooldown then return end
    local myRoot=getMyRoot() if not myRoot then return end

    for _,e in ipairs(getEnemies()) do
        if (e.root.Position-myRoot.Position).Magnitude > Cfg.parryRange then continue end

        -- Check animator for recently-started attack animations
        local hum=e.model:FindFirstChildOfClass("Humanoid")
        local anim=hum and hum:FindFirstChild("Animator")
        if not anim then continue end

        for _,track in ipairs(anim:GetPlayingAnimationTracks()) do
            -- A track in its first 0.25s = just started = possible attack
            local id=track.Animation and track.Animation.AnimationId or ""
            local key=e.model.Name..id
            if track.TimePosition>0 and track.TimePosition<0.25 and not parryAnims[key] then
                parryAnims[key]=true
                task.delay(0.5, function() parryAnims[key]=nil end)
                -- Auto-parry!
                pressF()
                parryCooldown=true
                task.delay(0.45, function() parryCooldown=false end)
                break
            end
        end
    end
end))

-- ── Aimbot (RenderPriority.Last — absolute last in render pipeline) ──────────
-- Runs AFTER everything else, including the game's own camera scripts.
-- No Q/LMB requirement — while ON, camera is permanently locked to nearest head.
Run:BindToRenderStep("GothamAimbot", Enum.RenderPriority.Last.Value, function()
    if not alive or not ON.aimbot then return end

    local myRoot = getMyRoot()
    if not myRoot then return end

    -- Find nearest enemy by WORLD DISTANCE (not screen position)
    local nearest, nearestDist = nil, math.huge
    for _, e in ipairs(getEnemies()) do
        local d = (e.root.Position - myRoot.Position).Magnitude
        if d < nearestDist then
            nearestDist = d
            nearest = e
        end
    end

    if not nearest then return end

    local head = nearest.model:FindFirstChild("Head") or nearest.root
    local cam  = WS.CurrentCamera

    -- Tiny upward offset so shots register at head center (not chin/neck)
    local targetPos = head.Position + Vector3.new(0, 0.25, 0)

    -- Hardlock: camera position stays, only direction changes to face head
    cam.CFrame = CFrame.new(cam.CFrame.Position, targetPos)
end)
table.insert(conns, {Disconnect = function()
    pcall(function() Run:UnbindFromRenderStep("GothamAimbot") end)
end})

-- ── ESP Boxes (SelectionBox on Entities) ─────────────────────────────────────
table.insert(conns, Run.Heartbeat:Connect(function()
    if not alive then return end

    if not ON.esp then
        for _,b in pairs(BOXES) do pcall(function() b:Destroy() end) end BOXES={} return
    end

    -- Clean stale
    for e,b in pairs(BOXES) do
        if not e or not e.Parent then pcall(function() b:Destroy() end) BOXES[e]=nil end
    end

    for _,e in ipairs(getEnemies()) do
        if not BOXES[e.model] then
            local b=Instance.new("SelectionBox")
            b.Adornee=e.model
            b.Color3=Color3.fromRGB(255,60,60)
            b.SurfaceTransparency=1
            b.LineThickness=0.06
            b.Parent=WS
            BOXES[e.model]=b
        end
    end
end))

-- ── Chams ESP (Highlight — always through ALL walls, no filtering) ───────────
table.insert(conns, Run.Heartbeat:Connect(function()
    if not alive then return end

    if not ON.chams then
        for _,h in pairs(CHAMS) do pcall(function() h:Destroy() end) end CHAMS={} return
    end

    -- Clean stale entries
    for e,h in pairs(CHAMS) do
        if not e or not e.Parent then pcall(function() h:Destroy() end) CHAMS[e]=nil end
    end

    -- Always create highlight for EVERY enemy — no wall check, no LOS filter
    for _,e in ipairs(getEnemies()) do
        if not CHAMS[e.model] then
            local h=Instance.new("Highlight")
            h.Adornee=e.model
            h.FillColor=Color3.fromRGB(255,50,50)
            h.OutlineColor=Color3.fromRGB(255,80,80)
            h.FillTransparency=0.4
            h.OutlineTransparency=0
            h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop  -- penetrates all geometry
            h.Parent=e.model
            CHAMS[e.model]=h
        end
    end
end))

-- ── FOV Circle ────────────────────────────────────────────────────────────────
local fovGui=Instance.new("ScreenGui") fovGui.Name="RedlinersFOV" fovGui.ResetOnSpawn=false
fovGui.IgnoreGuiInset=true fovGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling fovGui.Parent=lp:WaitForChild("PlayerGui")
local fovCircle=Instance.new("ImageLabel") fovCircle.BackgroundTransparency=1
fovCircle.AnchorPoint=Vector2.new(0.5,0.5) fovCircle.Position=UDim2.new(0.5,0,0.5,0)
fovCircle.Image="rbxassetid://3570695787" fovCircle.ImageColor3=Color3.fromRGB(255,255,255)
fovCircle.ImageTransparency=0.4 fovCircle.Visible=false fovCircle.Parent=fovGui
table.insert(conns,Run.RenderStepped:Connect(function()
    if not alive then return end
    fovCircle.Visible=ON.showfov
    if fovCircle.Visible then
        local d=Cfg.fovRadius*2 fovCircle.Size=UDim2.new(0,d,0,d)
    end
end))

-- ── Build helpers ─────────────────────────────────────────────────────────────
local function snapshot()
    return{name="",
        on={autoparry=ON.autoparry,aimbot=ON.aimbot,esp=ON.esp,chams=ON.chams,
            wallcheck=ON.wallcheck,showfov=ON.showfov},
        cfg={fovRadius=Cfg.fovRadius,smoothing=Cfg.smoothing,
             parryRange=Cfg.parryRange,maxDist=Cfg.maxDist},
        keybinds=Keybinds}
end
local function applyBuild(b)
    if b.on  then for k,v in pairs(b.on)  do ON[k]=v end end
    if b.cfg then
        for k,v in pairs(b.cfg) do if Cfg[k]~=nil then Cfg[k]=v end end
    end
    if b.keybinds then for k,v in pairs(b.keybinds) do Keybinds[k]=v end end
    for feat,btn in pairs(togBtnRefs) do
        if ON[feat] then btn.BackgroundColor3=C.VINO_TINTO_EXTREMO btn.Text="ON"  btn.TextColor3=Color3.fromRGB(15,15,15)
        else             btn.BackgroundColor3=C.BG_ROW              btn.Text="OFF" btn.TextColor3=C.TEXT_FADE end
    end
    for feat,btn in pairs(kbBtnRefs) do
        btn.Text=Keybinds[feat] and Keybinds[feat]~="" and Keybinds[feat] or "---"
    end
end

-- Auto-load
task.defer(function()
    local name=getAutoLoad() if not name then return end
    local builds=loadBuilds()
    for _,b in ipairs(builds) do
        if b.name==name then applyBuild(b) activeLoadedBuild=name
            notify("Auto-build: "..name,4) return end
    end
end)

-- ── GUI ───────────────────────────────────────────────────────────────────────
local old=lp.PlayerGui:FindFirstChild("GothamHubREDLINERS") if old then old:Destroy() end
local gui=Instance.new("ScreenGui") gui.Name="GothamHubREDLINERS" gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=lp:WaitForChild("PlayerGui")

local win=Instance.new("Frame")
win.Size=UDim2.new(0,760,0,560) win.Position=UDim2.new(0.5,-380,0.5,-280)
win.BackgroundColor3=C.BG_HUB win.BorderSizePixel=0 win.Active=true win.Draggable=true win.Parent=gui
Instance.new("UICorner").Parent=win
Instance.new("UIStroke",win).Color=C.VINO_TINTO_EXTREMO

-- Header
local hdr=Instance.new("Frame") hdr.Size=UDim2.new(1,0,0,62) hdr.BackgroundTransparency=1 hdr.Parent=win
local logo=Instance.new("ImageLabel") logo.Size=UDim2.new(0,52,0,52) logo.Position=UDim2.new(0,12,0.5,-26)
logo.BackgroundTransparency=1 logo.Image=C.LOGO_ID logo.Parent=hdr
local htl=Instance.new("TextLabel") htl.Size=UDim2.new(0.5,0,1,0) htl.Position=UDim2.new(0,76,0,0)
htl.BackgroundTransparency=1 htl.Text="GOTHAM HUB" htl.TextColor3=C.TEXT_MAIN
htl.Font=C.FONT_HUB_TITLE htl.TextSize=16 htl.TextXAlignment=Enum.TextXAlignment.Left htl.Parent=hdr
local hsep=Instance.new("Frame") hsep.Size=UDim2.new(1,0,0,1) hsep.Position=UDim2.new(0,0,0,62)
hsep.BackgroundColor3=C.VINO_TINTO_EXTREMO hsep.Parent=win

-- Sidebar
local side=Instance.new("Frame") side.Size=UDim2.new(0,200,1,-62) side.Position=UDim2.new(0,0,0,62)
side.BackgroundColor3=C.BG_SIDE side.BorderSizePixel=0 side.Parent=win
local ssep=Instance.new("Frame") ssep.Size=UDim2.new(0,1,1,0) ssep.Position=UDim2.new(1,-1,0,0)
ssep.BackgroundColor3=C.VINO_TINTO_EXTREMO ssep.Parent=side

local ca=Instance.new("Frame") ca.Size=UDim2.new(1,-200,1,-62) ca.Position=UDim2.new(0,200,0,62)
ca.BackgroundTransparency=1 ca.Parent=win

local function mkPage() local f=Instance.new("Frame") f.Size=UDim2.new(1,0,1,0) f.BackgroundTransparency=1 f.Visible=false f.Parent=ca return f end
local pMain=mkPage() pMain.Visible=true
local pCfg =mkPage()
local pAct =mkPage()

local navData={}
local function mkNav(lbl,y,pg)
    local b=Instance.new("TextButton") b.Size=UDim2.new(1,-16,0,38) b.Position=UDim2.new(0,8,0,y)
    b.BackgroundColor3=Color3.fromRGB(15,15,15) b.BorderSizePixel=0 b.Text="" b.Parent=side
    Instance.new("UICorner").Parent=b
    local ac=Instance.new("Frame") ac.Size=UDim2.new(0,3,1,0) ac.BackgroundColor3=C.VINO_TINTO_EXTREMO
    ac.BorderSizePixel=0 ac.Visible=false ac.Parent=b Instance.new("UICorner").Parent=ac
    local t=Instance.new("TextLabel") t.Size=UDim2.new(1,-10,1,0) t.Position=UDim2.new(0,14,0,0)
    t.BackgroundTransparency=1 t.Text=lbl t.TextColor3=C.TEXT_FADE
    t.Font=C.FONT_LABEL_BOLD t.TextSize=13 t.TextXAlignment=Enum.TextXAlignment.Left t.Parent=b
    navData[#navData+1]={t=t,pg=pg,ac=ac}
    b.MouseButton1Click:Connect(function()
        for _,n in ipairs(navData) do n.t.TextColor3=C.TEXT_FADE n.pg.Visible=false n.ac.Visible=false end
        t.TextColor3=C.TEXT_MAIN pg.Visible=true ac.Visible=true
    end)
    return t,ac
end
local nMain,aMain=mkNav("Main Scripts",10,pMain) mkNav("Config",58,pCfg) mkNav("Actions",106,pAct)
nMain.TextColor3=C.TEXT_MAIN aMain.Visible=true

-- ── UI builders ───────────────────────────────────────────────────────────────
local function sec(par,txt,y)
    local l=Instance.new("TextLabel") l.Size=UDim2.new(1,-16,0,14) l.Position=UDim2.new(0,8,0,y)
    l.BackgroundTransparency=1 l.Text=txt l.TextColor3=C.TEXT_FADE
    l.Font=C.FONT_LABEL_BOLD l.TextSize=10 l.TextXAlignment=Enum.TextXAlignment.Left l.Parent=par
end

local function mkRow(par,lbl,y,key,hint)
    local rowH=hint and 48 or 38
    local r=Instance.new("Frame") r.Size=UDim2.new(1,-16,0,rowH) r.Position=UDim2.new(0,8,0,y)
    r.BackgroundColor3=C.BG_ROW r.BorderSizePixel=0 r.Parent=par Instance.new("UICorner").Parent=r
    local acc=Instance.new("Frame") acc.Size=UDim2.new(0,3,1,0) acc.BackgroundColor3=C.VINO_TINTO_EXTREMO acc.BorderSizePixel=0 acc.Parent=r Instance.new("UICorner").Parent=acc
    local lbl2=Instance.new("TextLabel") lbl2.Size=UDim2.new(1,-136,0,hint and 22 or rowH)
    lbl2.Position=UDim2.new(0,12,0,hint and 4 or 0)
    lbl2.BackgroundTransparency=1 lbl2.Text=lbl lbl2.TextColor3=C.TEXT_MAIN
    lbl2.Font=C.FONT_LABEL_BOLD lbl2.TextSize=13 lbl2.TextXAlignment=Enum.TextXAlignment.Left lbl2.Parent=r
    if hint then
        local hl=Instance.new("TextLabel") hl.Size=UDim2.new(1,-136,0,14) hl.Position=UDim2.new(0,12,0,26)
        hl.BackgroundTransparency=1 hl.Text=hint hl.TextColor3=C.TEXT_FADE
        hl.Font=C.FONT_LABEL hl.TextSize=10 hl.TextXAlignment=Enum.TextXAlignment.Left hl.Parent=r
    end
    local kbBtn=Instance.new("TextButton") kbBtn.Size=UDim2.new(0,58,0,24) kbBtn.Position=UDim2.new(1,-120,0.5,-12)
    kbBtn.BackgroundColor3=Color3.fromRGB(22,22,22) kbBtn.BorderSizePixel=0
    kbBtn.Font=C.FONT_MONO kbBtn.TextSize=11 kbBtn.TextColor3=C.TEXT_FADE
    kbBtn.Text=Keybinds[key] and Keybinds[key]~="" and Keybinds[key] or "---"
    kbBtn.Parent=r Instance.new("UICorner").Parent=kbBtn kbBtnRefs[key]=kbBtn
    local togBtn=Instance.new("TextButton") togBtn.Size=UDim2.new(0,52,0,24) togBtn.Position=UDim2.new(1,-60,0.5,-12)
    togBtn.BackgroundColor3=ON[key] and C.VINO_TINTO_EXTREMO or C.BG_ROW
    togBtn.Text=ON[key] and "ON" or "OFF" togBtn.BorderSizePixel=0
    togBtn.TextColor3=ON[key] and Color3.fromRGB(15,15,15) or C.TEXT_FADE
    togBtn.Font=C.FONT_LABEL_BOLD togBtn.TextSize=12 togBtn.Parent=r Instance.new("UICorner").Parent=togBtn
    togBtnRefs[key]=togBtn
    togBtn.MouseButton1Click:Connect(function()
        ON[key]=not ON[key]
        togBtn.BackgroundColor3=ON[key] and C.VINO_TINTO_EXTREMO or C.BG_ROW
        togBtn.Text=ON[key] and "ON" or "OFF"
        togBtn.TextColor3=ON[key] and Color3.fromRGB(15,15,15) or C.TEXT_FADE
    end)
    kbBtn.MouseButton1Click:Connect(function()
        if listeningFor==key then listeningFor=nil kbBtn.BackgroundColor3=Color3.fromRGB(22,22,22) kbBtn.TextColor3=C.TEXT_FADE kbBtn.Text=Keybinds[key] and Keybinds[key]~="" and Keybinds[key] or "---" return end
        listeningFor=key kbBtn.BackgroundColor3=C.VINO_TINTO_EXTREMO kbBtn.TextColor3=Color3.fromRGB(15,15,15) kbBtn.Text="..."
        task.delay(4,function() if listeningFor==key then listeningFor=nil kbBtn.BackgroundColor3=Color3.fromRGB(22,22,22) kbBtn.TextColor3=C.TEXT_FADE kbBtn.Text=Keybinds[key] or"---" end end)
    end)
end

local function mkSlider(par,lbl,y,mn,mx,def,step,cb)
    step=step or 1
    local r=Instance.new("Frame") r.Size=UDim2.new(1,-16,0,52) r.Position=UDim2.new(0,8,0,y)
    r.BackgroundColor3=C.BG_ROW r.BorderSizePixel=0 r.Parent=par Instance.new("UICorner").Parent=r
    local acc=Instance.new("Frame") acc.Size=UDim2.new(0,3,1,0) acc.BackgroundColor3=C.VINO_TINTO_EXTREMO acc.BorderSizePixel=0 acc.Parent=r Instance.new("UICorner").Parent=acc
    local vl=Instance.new("TextLabel") vl.Size=UDim2.new(1,-14,0,20) vl.Position=UDim2.new(0,12,0,4)
    vl.BackgroundTransparency=1 vl.TextColor3=C.TEXT_MAIN vl.Font=C.FONT_LABEL vl.TextSize=12
    vl.TextXAlignment=Enum.TextXAlignment.Left vl.Parent=r
    local tr=Instance.new("Frame") tr.Size=UDim2.new(1,-20,0,6) tr.Position=UDim2.new(0,12,0,32)
    tr.BackgroundColor3=Color3.fromRGB(35,35,35) tr.BorderSizePixel=0 tr.Parent=r Instance.new("UICorner").Parent=tr
    local fi=Instance.new("Frame") fi.BackgroundColor3=C.VINO_TINTO_EXTREMO fi.BorderSizePixel=0
    fi.Size=UDim2.new((def-mn)/(mx-mn),0,1,0) fi.Parent=tr Instance.new("UICorner").Parent=fi
    local kn=Instance.new("TextButton") kn.Size=UDim2.new(0,14,0,14) kn.Position=UDim2.new((def-mn)/(mx-mn),-7,0.5,-7)
    kn.BackgroundColor3=C.TEXT_MAIN kn.BorderSizePixel=0 kn.Text="" kn.Parent=tr Instance.new("UICorner").Parent=kn
    local cur=def local drag=false
    local function fmtVal(v) return step<1 and string.format("%.2f",v) or tostring(v) end
    vl.Text=lbl..": "..fmtVal(cur)
    kn.MouseButton1Down:Connect(function() drag=true end)
    local uc=UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
    table.insert(conns,uc)
    local hc=Run.Heartbeat:Connect(function()
        if not drag then return end
        local mp=UIS:GetMouseLocation() local tp=tr.AbsolutePosition local ts=tr.AbsoluteSize
        local ratio=math.clamp((mp.X-tp.X)/ts.X,0,1)
        local raw=mn+ratio*(mx-mn)
        local nv=math.floor(raw/step+0.5)*step
        nv=math.clamp(nv,mn,mx)
        if nv~=cur then cur=nv vl.Text=lbl..": "..fmtVal(nv)
            local r2=(nv-mn)/(mx-mn) fi.Size=UDim2.new(r2,0,1,0) kn.Position=UDim2.new(r2,-7,0.5,-7) cb(nv) end
    end)
    table.insert(conns,hc)
end

local function mkBtn(par,lbl,y,fn,col)
    local b=Instance.new("TextButton") b.Size=UDim2.new(1,-16,0,38) b.Position=UDim2.new(0,8,0,y)
    b.BackgroundColor3=col or C.BG_ROW b.BorderSizePixel=0
    b.Text=lbl b.TextColor3=C.TEXT_MAIN b.Font=C.FONT_LABEL_BOLD b.TextSize=13 b.Parent=par
    local s=Instance.new("UIStroke") s.Color=col or C.VINO_TINTO_EXTREMO s.Thickness=1 s.Parent=b
    Instance.new("UICorner").Parent=b b.MouseButton1Click:Connect(fn) return b
end

-- ── Main Scripts Page ─────────────────────────────────────────────────────────
do
    local left=Instance.new("ScrollingFrame")
    left.Size=UDim2.new(0.5,-6,1,-6) left.Position=UDim2.new(0,3,0,3)
    left.BackgroundColor3=C.BG_CARD left.BorderSizePixel=0
    left.ScrollBarThickness=3 left.ScrollBarImageColor3=C.VINO_TINTO_EXTREMO
    left.CanvasSize=UDim2.new(0,0,0,550) left.Parent=pMain
    Instance.new("UICorner").Parent=left Instance.new("UIStroke",left).Color=C.VINO_TINTO_EXTREMO

    sec(left,"── AIMBOT ──",4)
    mkRow(left,"Aimbot Lock",20,"aimbot")
    sec(left,"── VISUAL ──",68)
    mkRow(left,"ESP Boxes",86,"esp")
    mkRow(left,"Wall Check (show through walls)",130,"wallcheck")
    mkRow(left,"Chams ESP",176,"chams")
    mkRow(left,"Show FOV",220,"showfov")
    sec(left,"── COMBAT ──",268)
    mkRow(left,"Auto Parry  [F auto]",286,"autoparry")

    sec(left,"── CONFIG ──",354)
    mkSlider(left,"Aimbot FOV",372,50,500,Cfg.fovRadius,1,function(v)
        Cfg.fovRadius=v saveCfg("cfg",Cfg)
    end)
    mkSlider(left,"Smoothing",432,0.01,1,Cfg.smoothing,0.01,function(v)
        Cfg.smoothing=v saveCfg("cfg",Cfg)
    end)
    mkSlider(left,"Parry Range (studs)",492,10,80,Cfg.parryRange,1,function(v)
        Cfg.parryRange=v saveCfg("cfg",Cfg)
    end)

    -- Right: info
    local right=Instance.new("Frame")
    right.Size=UDim2.new(0.5,-6,1,-6) right.Position=UDim2.new(0.5,3,0,3)
    right.BackgroundColor3=C.BG_CARD right.BorderSizePixel=0 right.Parent=pMain
    Instance.new("UICorner").Parent=right Instance.new("UIStroke",right).Color=C.VINO_TINTO_EXTREMO

    sec(right,"── INFORMATION ──",6)
    local function il(t,y)
        local l=Instance.new("TextLabel") l.Size=UDim2.new(1,-16,0,20) l.Position=UDim2.new(0,12,0,y)
        l.BackgroundTransparency=1 l.TextColor3=C.TEXT_DIM l.Text=t
        l.Font=C.FONT_LABEL l.TextSize=12 l.TextXAlignment=Enum.TextXAlignment.Left l.Parent=right
    end
    il("User: "..lp.Name,26)
    il("Executor: "..(identifyexecutor and identifyexecutor() or "Unknown"),46)
    il("Game: REDLINERS",66)
    il("Owner: caceresman",86)
    local ns=Instance.new("TextLabel") ns.Size=UDim2.new(1,-16,0,18) ns.Position=UDim2.new(0,46,0,106)
    ns.BackgroundTransparency=1 ns.TextColor3=C.TEXT_FADE ns.Text="Noah"
    ns.Font=C.FONT_OWNER_SUB ns.TextSize=12 ns.TextXAlignment=Enum.TextXAlignment.Left ns.Parent=right

    local div=Instance.new("Frame") div.Size=UDim2.new(1,-24,0,1) div.Position=UDim2.new(0,12,0,132)
    div.BackgroundColor3=C.VINO_TINTO_EXTREMO div.Parent=right

    sec(right,"── STATUS ──",140)
    local tgtLbl=Instance.new("TextLabel") tgtLbl.Size=UDim2.new(1,-16,0,18) tgtLbl.Position=UDim2.new(0,12,0,160)
    tgtLbl.BackgroundTransparency=1 tgtLbl.Font=C.FONT_LABEL tgtLbl.TextSize=12
    tgtLbl.TextColor3=C.TEXT_FADE tgtLbl.Text="Target: —" tgtLbl.TextXAlignment=Enum.TextXAlignment.Left tgtLbl.Parent=right
    local autoLbl=Instance.new("TextLabel") autoLbl.Size=UDim2.new(1,-16,0,18) autoLbl.Position=UDim2.new(0,12,0,180)
    autoLbl.BackgroundTransparency=1 autoLbl.Font=C.FONT_LABEL autoLbl.TextSize=12
    autoLbl.TextXAlignment=Enum.TextXAlignment.Left autoLbl.Parent=right
    local alName=getAutoLoad()
    autoLbl.Text=alName and ("Auto-load: "..alName) or "Auto-load: —"
    autoLbl.TextColor3=alName and C.TEXT_AMBER or C.TEXT_FADE

    local kbListen=Instance.new("TextLabel") kbListen.Size=UDim2.new(1,-16,0,18) kbListen.Position=UDim2.new(0,12,0,200)
    kbListen.BackgroundTransparency=1 kbListen.Font=C.FONT_LABEL_BOLD kbListen.TextSize=11
    kbListen.TextColor3=C.VINO_TINTO_EXTREMO kbListen.TextXAlignment=Enum.TextXAlignment.Left kbListen.Text="" kbListen.Parent=right

    local uTimer=0
    table.insert(conns,Run.Heartbeat:Connect(function(dt)
        if not alive then return end
        uTimer=uTimer+dt if uTimer<0.25 then return end uTimer=0
        local t=getNearestEnemy()
        if t then tgtLbl.Text="Target: "..t.model.Name tgtLbl.TextColor3=Color3.fromRGB(255,80,80)
        else      tgtLbl.Text="Target: —"              tgtLbl.TextColor3=C.TEXT_FADE end
        kbListen.Text=listeningFor and ("Listening: "..listeningFor.." (press key)") or ""
    end))
end

-- ── Config Page (Build Manager) ───────────────────────────────────────────────
do
    local builds=loadBuilds() local brows={}
    local currentAuto=getAutoLoad()

    local card=Instance.new("Frame") card.Size=UDim2.new(1,-6,1,-6) card.Position=UDim2.new(0,3,0,3)
    card.BackgroundColor3=C.BG_CARD card.Parent=pCfg
    Instance.new("UICorner").Parent=card Instance.new("UIStroke",card).Color=C.VINO_TINTO_EXTREMO
    sec(card,"── BUILD MANAGER ──",6)

    local nb=Instance.new("TextBox") nb.Size=UDim2.new(1,-208,0,30) nb.Position=UDim2.new(0,12,0,26)
    nb.BackgroundColor3=C.BG_INPUT nb.BorderSizePixel=0 nb.PlaceholderText="Build name..."
    nb.Text="" nb.TextColor3=C.TEXT_MAIN nb.PlaceholderColor3=C.TEXT_FADE
    nb.Font=C.FONT_LABEL nb.TextSize=13 nb.Parent=card Instance.new("UICorner").Parent=nb

    local svNew=Instance.new("TextButton") svNew.Size=UDim2.new(0,86,0,30) svNew.Position=UDim2.new(1,-196,0,26)
    svNew.BackgroundColor3=C.VINO_TINTO_EXTREMO svNew.BorderSizePixel=0 svNew.Text="Save"
    svNew.TextColor3=Color3.fromRGB(15,15,15) svNew.Font=C.FONT_LABEL_BOLD svNew.TextSize=12 svNew.Parent=card Instance.new("UICorner").Parent=svNew

    local svCur=Instance.new("TextButton") svCur.Size=UDim2.new(0,100,0,30) svCur.Position=UDim2.new(1,-102,0,26)
    svCur.BackgroundColor3=Color3.fromRGB(15,40,15) svCur.BorderSizePixel=0 svCur.Text="Save current"
    svCur.TextColor3=C.TEXT_GREEN svCur.Font=C.FONT_LABEL_BOLD svCur.TextSize=12 svCur.Parent=card Instance.new("UICorner").Parent=svCur

    local desc=Instance.new("TextLabel") desc.Size=UDim2.new(1,-24,0,14) desc.Position=UDim2.new(0,12,0,62)
    desc.BackgroundTransparency=1 desc.Font=C.FONT_LABEL desc.TextSize=10 desc.TextColor3=C.TEXT_FADE
    desc.Text="★ Auto-Load on startup  |  Load  |  Save = overwrite  |  X = delete"
    desc.TextXAlignment=Enum.TextXAlignment.Left desc.Parent=card

    local dv=Instance.new("Frame") dv.Size=UDim2.new(1,-24,0,1) dv.Position=UDim2.new(0,12,0,80)
    dv.BackgroundColor3=C.VINO_TINTO_EXTREMO dv.Parent=card

    local bsc=Instance.new("ScrollingFrame") bsc.Size=UDim2.new(1,-24,1,-90) bsc.Position=UDim2.new(0,12,0,86)
    bsc.BackgroundTransparency=1 bsc.BorderSizePixel=0 bsc.ScrollBarThickness=3
    bsc.ScrollBarImageColor3=C.VINO_TINTO_EXTREMO bsc.CanvasSize=UDim2.new(0,0,0,0) bsc.Parent=card

    local function refreshBuilds()
        for _,r in ipairs(brows) do r:Destroy() end brows={}
        bsc.CanvasSize=UDim2.new(0,0,0,math.max(#builds*50,10))
        for i,b in ipairs(builds) do
            local isAuto=(b.name==currentAuto)
            local row=Instance.new("Frame") row.Size=UDim2.new(1,-4,0,44) row.Position=UDim2.new(0,2,0,(i-1)*48)
            row.BackgroundColor3=C.BG_ROW row.BorderSizePixel=0 row.Parent=bsc Instance.new("UICorner").Parent=row table.insert(brows,row)
            local ac2=Instance.new("Frame") ac2.Size=UDim2.new(0,3,1,0) ac2.BackgroundColor3=C.VINO_TINTO_EXTREMO ac2.BorderSizePixel=0 ac2.Parent=row Instance.new("UICorner").Parent=ac2
            local star=Instance.new("TextButton") star.Size=UDim2.new(0,28,0,28) star.Position=UDim2.new(0,8,0.5,-14)
            star.BackgroundTransparency=1 star.Text=isAuto and "★" or "☆" star.TextColor3=isAuto and Color3.fromRGB(255,210,0) or C.TEXT_FADE
            star.Font=Enum.Font.GothamBold star.TextSize=16 star.BorderSizePixel=0 star.Parent=row
            local nl=Instance.new("TextLabel") nl.Size=UDim2.new(1,-210,1,0) nl.Position=UDim2.new(0,40,0,0)
            nl.BackgroundTransparency=1 nl.Text=b.name or("Build "..i) nl.TextColor3=C.TEXT_MAIN
            nl.Font=C.FONT_LABEL_BOLD nl.TextSize=13 nl.TextXAlignment=Enum.TextXAlignment.Left nl.Parent=row
            local lb=Instance.new("TextButton") lb.Size=UDim2.new(0,46,0,28) lb.Position=UDim2.new(1,-202,0.5,-14) lb.BackgroundColor3=C.VINO_TINTO_EXTREMO lb.BorderSizePixel=0 lb.Text="Load" lb.TextColor3=Color3.fromRGB(15,15,15) lb.Font=C.FONT_LABEL_BOLD lb.TextSize=12 lb.Parent=row Instance.new("UICorner").Parent=lb
            local sb2=Instance.new("TextButton") sb2.Size=UDim2.new(0,46,0,28) sb2.Position=UDim2.new(1,-150,0.5,-14) sb2.BackgroundColor3=Color3.fromRGB(15,40,15) sb2.BorderSizePixel=0 sb2.Text="Save" sb2.TextColor3=C.TEXT_GREEN sb2.Font=C.FONT_LABEL_BOLD sb2.TextSize=12 sb2.Parent=row Instance.new("UICorner").Parent=sb2
            local db=Instance.new("TextButton") db.Size=UDim2.new(0,30,0,28) db.Position=UDim2.new(1,-98,0.5,-14) db.BackgroundColor3=Color3.fromRGB(50,8,8) db.BorderSizePixel=0 db.Text="X" db.TextColor3=C.TEXT_MAIN db.Font=C.FONT_LABEL_BOLD db.TextSize=12 db.Parent=row Instance.new("UICorner").Parent=db
            local idx=i
            lb.MouseButton1Click:Connect(function() applyBuild(builds[idx]) activeLoadedBuild=builds[idx].name lb.Text="✓" task.delay(1.5,function() lb.Text="Load" end) end)
            sb2.MouseButton1Click:Connect(function() local s2=snapshot() s2.name=builds[idx].name builds[idx]=s2 saveBuilds(builds) refreshBuilds() sb2.Text="✓" task.delay(1.5,function() sb2.Text="Save" end) end)
            db.MouseButton1Click:Connect(function() if builds[idx].name==currentAuto then currentAuto=nil setAutoLoad(nil) end table.remove(builds,idx) saveBuilds(builds) refreshBuilds() end)
            star.MouseButton1Click:Connect(function()
                if isAuto then currentAuto=nil setAutoLoad(nil)
                else currentAuto=builds[idx].name setAutoLoad(builds[idx].name) notify("Auto-load: "..builds[idx].name,3) end
                refreshBuilds()
            end)
        end
    end

    svNew.MouseButton1Click:Connect(function()
        local name=nb.Text~="" and nb.Text or("Build "..(#builds+1))
        local s2=snapshot() s2.name=name table.insert(builds,s2) saveBuilds(builds) refreshBuilds()
        nb.Text="" svNew.Text="Saved!" task.delay(1.5,function() svNew.Text="Save" end)
    end)
    svCur.MouseButton1Click:Connect(function()
        if not activeLoadedBuild then notify("Load a build first",2) return end
        for i,b in ipairs(builds) do
            if b.name==activeLoadedBuild then
                local s2=snapshot() s2.name=b.name builds[i]=s2 saveBuilds(builds) refreshBuilds()
                svCur.Text="✓" task.delay(1.5,function() svCur.Text="Save current" end) return
            end
        end
    end)
    refreshBuilds()
end

-- ── Actions Page ─────────────────────────────────────────────────────────────
do
    local card=Instance.new("Frame") card.Size=UDim2.new(1,-6,1,-6) card.Position=UDim2.new(0,3,0,3)
    card.BackgroundColor3=C.BG_CARD card.Parent=pAct
    Instance.new("UICorner").Parent=card Instance.new("UIStroke",card).Color=C.VINO_TINTO_EXTREMO
    sec(card,"── ACTIONS ──",6)
    mkRow(card,"Toggle Hub",26,"togglehub")
    -- Discord icon button (blurple)
    local _dWrap=Instance.new("Frame") _dWrap.Size=UDim2.new(0,44,0,44) _dWrap.Position=UDim2.new(0.5,-22,0,130)
    _dWrap.BackgroundColor3=Color3.fromRGB(88,101,242) _dWrap.BorderSizePixel=0 _dWrap.Parent=card
    Instance.new("UICorner").Parent=_dWrap
    local _dIcon=Instance.new("ImageButton") _dIcon.Size=UDim2.new(0.8,0,0.8,0) _dIcon.Position=UDim2.new(0.1,0,0.1,0)
    _dIcon.BackgroundTransparency=1 _dIcon.Image=C.DISCORD_IMG_ID _dIcon.Parent=_dWrap
    _dIcon.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard("https://discord.gg/AD5NsXxMjn")
            _dWrap.BackgroundColor3=Color3.fromRGB(60,80,200)
            task.delay(1.5,function() _dWrap.BackgroundColor3=Color3.fromRGB(88,101,242) end)
        end
    end)
    mkBtn(card,"Unload Hub",184,function()
        alive=false
        for _,b in pairs(BOXES) do pcall(function() b:Destroy() end) end BOXES={}
        for _,h in pairs(CHAMS) do pcall(function() h:Destroy() end) end CHAMS={}
        for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        if fovGui then pcall(function() fovGui:Destroy() end) end
        pcall(function() gui:Destroy() end)
    end,Color3.fromRGB(35,6,6))
end

-- ── Global Input ──────────────────────────────────────────────────────────────
table.insert(conns,UIS.InputBegan:Connect(function(i,p)
    if p then return end
    if i.UserInputType~=Enum.UserInputType.Keyboard then return end
    local kc=i.KeyCode
    if listeningFor then
        local feat=listeningFor listeningFor=nil
        Keybinds[feat]=kc==Enum.KeyCode.Escape and nil or kc.Name
        saveCfg("keybinds",Keybinds)
        local btn=kbBtnRefs[feat]
        if btn then btn.BackgroundColor3=Color3.fromRGB(22,22,22) btn.TextColor3=C.TEXT_FADE btn.Text=Keybinds[feat] or"---" end
        return
    end
    if Keybinds.togglehub and kc.Name==Keybinds.togglehub then win.Visible=not win.Visible return end
    for feat,keyName in pairs(Keybinds) do
        if keyName and keyName~="None" and keyName~="" and kc.Name==keyName then
            ON[feat]=not ON[feat]
            local btn=togBtnRefs[feat]
            if btn then btn.BackgroundColor3=ON[feat] and C.VINO_TINTO_EXTREMO or C.BG_ROW btn.Text=ON[feat] and"ON" or"OFF" btn.TextColor3=ON[feat] and Color3.fromRGB(15,15,15) or C.TEXT_FADE end
        end
    end
end))

notify("REDLINERS loaded | L = toggle",4)

end) -- Keys.show
