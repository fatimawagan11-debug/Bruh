--[[
    SleepyHub Orion — Rivals
    Combat core rebuilt: Silent Aim, Aimbot, ESP, Melee Aura
    UI: Orion (mobile-friendly)
]]

if getgenv and getgenv().SleepyOrionUnload then
    pcall(getgenv().SleepyOrionUnload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local FLAGS = {
    silent_enabled = true,
    silent_fov = 180,
    silent_show_fov = true,
    silent_team_check = true,
    silent_wall_check = false,
    silent_hitpart = "Head", -- Head | HRP | Closest
    silent_prediction = 0.14,
    silent_hitchance = 100,
    silent_priority = "Crosshair", -- Crosshair | Distance | Health

    aimbot_enabled = false,
    aimbot_fov = 140,
    aimbot_show_fov = false,
    aimbot_smooth = 0.18,
    aimbot_team_check = true,
    aimbot_wall_check = false,
    aimbot_hitpart = "Head",
    aimbot_prediction = 0.12,
    aimbot_key = Enum.KeyCode.E,
    aimbot_hold = true,

    melee_enabled = false,
    melee_range = 14,
    melee_face = true,
    melee_cooldown = 0.12,

    esp_enabled = true,
    esp_team = false,
    esp_box = true,
    esp_name = true,
    esp_health = true,
    esp_tracers = false,
    esp_chams = true,
    esp_color = Color3.fromRGB(0, 162, 255),
    esp_enemy = Color3.fromRGB(255, 70, 70),

    max_distance = 1200,
}

local STATE = {
    target = nil,
    aimbotDown = false,
    lastMelee = 0,
    drawings = {},
    chams = {},
    boxes = {},
    unloaded = false,
}

-- =========================
-- UTILS
-- =========================
local function charOf(p)
    return p and p.Character
end

local function rootOf(p)
    local c = charOf(p)
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function humOf(p)
    local c = charOf(p)
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function isAlive(p)
    local h = humOf(p)
    return h and h.Health > 0
end

local function sameTeam(p)
    if not FLAGS.silent_team_check and not FLAGS.aimbot_team_check then
        return false
    end
    if LocalPlayer.Team and p.Team then
        return LocalPlayer.Team == p.Team
    end
    local a = LocalPlayer:GetAttribute("Team") or LocalPlayer:GetAttribute("TeamId")
    local b = p:GetAttribute("Team") or p:GetAttribute("TeamId")
    if a ~= nil and b ~= nil then
        return a == b
    end
    return false
end

local function getHitPart(character, mode)
    if not character then return nil end
    mode = mode or "Head"
    if mode == "Head" then
        return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    elseif mode == "HRP" or mode == "Torso" then
        return character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")
    elseif mode == "Closest" then
        local mousePos = UserInputService:GetMouseLocation()
        local best, bestD
        for _, name in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso" }) do
            local part = character:FindFirstChild(name)
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                    if not bestD or d < bestD then
                        bestD = d
                        best = part
                    end
                end
            end
        end
        return best or character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    end
    return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function visibleCheck(fromPos, toPart)
    if not toPart then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = { LocalPlayer.Character }
    if toPart.Parent then
        exclude[#exclude + 1] = toPart.Parent
    end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    local dir = toPart.Position - fromPos
    local hit = Workspace:Raycast(fromPos, dir, params)
    if not hit then return true end
    return hit.Instance and hit.Instance:IsDescendantOf(toPart.Parent)
end

local function predictPos(part, t)
    if not part then return nil end
    t = t or 0
    local vel = part.AssemblyLinearVelocity
    return part.Position + vel * t
end

local function screenDistToMouse(worldPos)
    local sp, onScreen = Camera:WorldToViewportPoint(worldPos)
    local mousePos = UserInputService:GetMouseLocation()
    if not onScreen and sp.Z < 0 then
        return math.huge, false
    end
    return (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude, onScreen and sp.Z > 0
end

-- =========================
-- TARGET SELECTION (god tier)
-- =========================
local function scoreTarget(pl, part, mode, fov)
    local myRoot = rootOf(LocalPlayer)
    if not myRoot or not part then return math.huge end

    local pred = predictPos(part, mode == "silent" and FLAGS.silent_prediction or FLAGS.aimbot_prediction)
    local dist3 = (pred - myRoot.Position).Magnitude
    if dist3 > FLAGS.max_distance then return math.huge end

    local sd, onScreen = screenDistToMouse(pred)
    local useFov = mode == "silent" and FLAGS.silent_fov or FLAGS.aimbot_fov
    if sd > useFov then return math.huge end

    if mode == "silent" and FLAGS.silent_wall_check then
        if not visibleCheck(Camera.CFrame.Position, part) then return math.huge end
    end
    if mode == "aimbot" and FLAGS.aimbot_wall_check then
        if not visibleCheck(Camera.CFrame.Position, part) then return math.huge end
    end

    local priority = FLAGS.silent_priority
    local hum = humOf(pl)
    local health = hum and hum.Health or 100

    -- Lower score = better
    if priority == "Distance" then
        return dist3
    elseif priority == "Health" then
        return health + dist3 * 0.01
    else -- Crosshair
        return sd * 1.35 + dist3 * 0.02 + health * 0.01
    end
end

local function getBestTarget(mode)
    local best, bestScore, bestPart
    local hitMode = mode == "silent" and FLAGS.silent_hitpart or FLAGS.aimbot_hitpart
    local teamFlag = mode == "silent" and FLAGS.silent_team_check or FLAGS.aimbot_team_check

    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAlive(pl) then
            if not (teamFlag and sameTeam(pl)) then
                local char = charOf(pl)
                local part = getHitPart(char, hitMode)
                if part then
                    local score = scoreTarget(pl, part, mode, nil)
                    if score < (bestScore or math.huge) then
                        bestScore = score
                        best = pl
                        bestPart = part
                    end
                end
            end
        end
    end
    return best, bestPart
end

-- =========================
-- FOV CIRCLES
-- =========================
local function drawing(class, props)
    local ok, obj = pcall(function()
        return Drawing.new(class)
    end)
    if not ok or not obj then return nil end
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    return obj
end

local silentFov = drawing("Circle", {
    Thickness = 1.5,
    NumSides = 64,
    Radius = 180,
    Filled = false,
    Color = Color3.fromRGB(0, 162, 255),
    Transparency = 0.85,
    Visible = false,
})
local aimbotFov = drawing("Circle", {
    Thickness = 1.5,
    NumSides = 64,
    Radius = 140,
    Filled = false,
    Color = Color3.fromRGB(255, 255, 255),
    Transparency = 0.7,
    Visible = false,
})

local function updateFovCircles()
    local mp = UserInputService:GetMouseLocation()
    if silentFov then
        silentFov.Position = mp
        silentFov.Radius = FLAGS.silent_fov
        silentFov.Visible = FLAGS.silent_enabled and FLAGS.silent_show_fov and not STATE.unloaded
    end
    if aimbotFov then
        aimbotFov.Position = mp
        aimbotFov.Radius = FLAGS.aimbot_fov
        aimbotFov.Visible = FLAGS.aimbot_enabled and FLAGS.aimbot_show_fov and not STATE.unloaded
    end
end

-- =========================
-- SILENT AIM (hook mouse)
-- =========================
local function silentAimPoint()
    if not FLAGS.silent_enabled then return nil end
    if FLAGS.silent_hitchance < 100 and math.random(1, 100) > FLAGS.silent_hitchance then
        return nil
    end
    local target, part = getBestTarget("silent")
    STATE.target = target
    if not part then return nil end
    local pred = predictPos(part, FLAGS.silent_prediction)
    return pred, part
end

-- Robust: override mouse.Hit / mouse.Target via metatable when possible
local function applySilentHooks()
    pcall(function()
        local mt = getrawmetatable(game)
        if not mt then return end
        local oldIndex = mt.__index
        if type(setreadonly) == "function" then
            setreadonly(mt, false)
        end
        mt.__index = newcclosure and newcclosure(function(self, key)
            if not STATE.unloaded and FLAGS.silent_enabled then
                if self == Mouse and (key == "Hit" or key == "Target") then
                    local point, part = silentAimPoint()
                    if point then
                        if key == "Hit" then
                            return CFrame.new(point)
                        end
                        if key == "Target" and part then
                            return part
                        end
                    end
                end
            end
            return oldIndex(self, key)
        end) or function(self, key)
            if not STATE.unloaded and FLAGS.silent_enabled then
                if self == Mouse and (key == "Hit" or key == "Target") then
                    local point, part = silentAimPoint()
                    if point then
                        if key == "Hit" then
                            return CFrame.new(point)
                        end
                        if key == "Target" and part then
                            return part
                        end
                    end
                end
            end
            return oldIndex(self, key)
        end
        if type(setreadonly) == "function" then
            setreadonly(mt, true)
        end
    end)
end
applySilentHooks()

-- Also push camera-ray style for games that ray from camera
RunService.RenderStepped:Connect(function()
    if STATE.unloaded then return end
    updateFovCircles()
end)

-- =========================
-- AIMBOT
-- =========================
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == FLAGS.aimbot_key then
        STATE.aimbotDown = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == FLAGS.aimbot_key then
        STATE.aimbotDown = false
    end
end)

RunService.RenderStepped:Connect(function(dt)
    if STATE.unloaded or not FLAGS.aimbot_enabled then return end
    if FLAGS.aimbot_hold and not STATE.aimbotDown then return end

    local target, part = getBestTarget("aimbot")
    if not part then return end
    local pred = predictPos(part, FLAGS.aimbot_prediction)
    local cf = CFrame.new(Camera.CFrame.Position, pred)
    local smooth = math.clamp(FLAGS.aimbot_smooth, 0.01, 1)
    Camera.CFrame = Camera.CFrame:Lerp(cf, 1 - math.exp(-dt / smooth))
end)

-- =========================
-- MELEE AURA
-- =========================
local function tryMelee()
    if not FLAGS.melee_enabled then return end
    local now = os.clock()
    if now - STATE.lastMelee < FLAGS.melee_cooldown then return end
    local myRoot = rootOf(LocalPlayer)
    if not myRoot then return end

    local best, bestDist
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAlive(pl) and not (FLAGS.silent_team_check and sameTeam(pl)) then
            local r = rootOf(pl)
            if r then
                local d = (r.Position - myRoot.Position).Magnitude
                if d <= FLAGS.melee_range and (not bestDist or d < bestDist) then
                    bestDist = d
                    best = pl
                end
            end
        end
    end
    if not best then return end
    local tr = rootOf(best)
    if not tr then return end

    if FLAGS.melee_face then
        -- face their BACK for backstab-style games
        local behind = tr.Position - tr.CFrame.LookVector * 2.5
        myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(behind.X, myRoot.Position.Y, behind.Z))
    end

    -- Tool activate
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            pcall(function() tool:Activate() end)
        end
    end
    STATE.lastMelee = now
end

RunService.Heartbeat:Connect(function()
    if STATE.unloaded then return end
    pcall(tryMelee)
end)

-- =========================
-- ESP
-- =========================
local function clearEspFor(pl)
    if STATE.chams[pl] then
        pcall(function() STATE.chams[pl]:Destroy() end)
        STATE.chams[pl] = nil
    end
    if STATE.boxes[pl] then
        for _, d in pairs(STATE.boxes[pl]) do
            pcall(function() d:Remove() end)
        end
        STATE.boxes[pl] = nil
    end
end

local function ensureChams(pl)
    if not FLAGS.esp_chams then
        if STATE.chams[pl] then
            pcall(function() STATE.chams[pl]:Destroy() end)
            STATE.chams[pl] = nil
        end
        return
    end
    local char = charOf(pl)
    if not char then return end
    local h = STATE.chams[pl]
    if h and h.Parent then
        h.Adornee = char
        return
    end
    local hl = Instance.new("Highlight")
    hl.Name = "_SleepyEsp"
    hl.Adornee = char
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.FillColor = (FLAGS.esp_team and sameTeam(pl)) and FLAGS.esp_color or FLAGS.esp_enemy
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function()
        hl.Parent = (gethui and gethui()) or CoreGui
    end)
    if not hl.Parent then
        hl.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    STATE.chams[pl] = hl
end

local function espStep()
    if not FLAGS.esp_enabled then
        for pl in pairs(STATE.chams) do clearEspFor(pl) end
        for pl in pairs(STATE.boxes) do clearEspFor(pl) end
        return
    end
    local seen = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAlive(pl) then
            if FLAGS.esp_team or not sameTeam(pl) then
                seen[pl] = true
                ensureChams(pl)
            end
        end
    end
    for pl in pairs(STATE.chams) do
        if not seen[pl] then clearEspFor(pl) end
    end
    for pl in pairs(STATE.boxes) do
        if not seen[pl] then clearEspFor(pl) end
    end
end

RunService.RenderStepped:Connect(function()
    if STATE.unloaded then return end
    pcall(espStep)
end)

Players.PlayerRemoving:Connect(function(pl)
    clearEspFor(pl)
end)

-- =========================
-- ORION UI
-- =========================
local OrionLib
do
    local urls = {
        "https://raw.githubusercontent.com/Seven7-lua/Roblox/refs/heads/main/Librarys/Orion/Orion.lua",
        "https://raw.githubusercontent.com/Robloxexploiter691/Mobilefriendlyorion/main/Orion",
        "https://raw.githubusercontent.com/shlexware/Orion/main/source",
    }
    for _, url in ipairs(urls) do
        local ok, res = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok and res then
            OrionLib = res
            break
        end
    end
    if not OrionLib then
        error("[SleepyHub Orion] Failed to load Orion UI")
    end
end

local Window = OrionLib:MakeWindow({
    Name = "SleepyHub Orion | Rivals",
    HidePremium = true,
    SaveConfig = true,
    ConfigFolder = "SleepyOrionRivals",
    IntroEnabled = false,
})

local TabCombat = Window:MakeTab({ Name = "Silent", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabAim = Window:MakeTab({ Name = "Aimbot", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabMelee = Window:MakeTab({ Name = "Melee", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabEsp = Window:MakeTab({ Name = "ESP", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabSettings = Window:MakeTab({ Name = "Settings", Icon = "rbxassetid://4483345998", PremiumOnly = false })

-- Silent
TabCombat:AddParagraph("Silent Aim", "Predictive FOV targeting · hooks mouse Hit/Target")
TabCombat:AddToggle({
    Name = "Enable Silent Aim",
    Default = true,
    Callback = function(v) FLAGS.silent_enabled = v end,
})
TabCombat:AddToggle({
    Name = "Show FOV",
    Default = true,
    Callback = function(v) FLAGS.silent_show_fov = v end,
})
TabCombat:AddToggle({
    Name = "Team Check",
    Default = true,
    Callback = function(v) FLAGS.silent_team_check = v end,
})
TabCombat:AddToggle({
    Name = "Wall Check",
    Default = false,
    Callback = function(v) FLAGS.silent_wall_check = v end,
})
TabCombat:AddSlider({
    Name = "FOV",
    Min = 20,
    Max = 500,
    Default = 180,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "px",
    Callback = function(v) FLAGS.silent_fov = v end,
})
TabCombat:AddSlider({
    Name = "Prediction",
    Min = 0,
    Max = 40,
    Default = 14,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "ms*10",
    Callback = function(v) FLAGS.silent_prediction = v / 100 end,
})
TabCombat:AddSlider({
    Name = "Hit Chance",
    Min = 1,
    Max = 100,
    Default = 100,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "%",
    Callback = function(v) FLAGS.silent_hitchance = v end,
})
TabCombat:AddDropdown({
    Name = "Hit Part",
    Default = "Head",
    Options = { "Head", "HRP", "Closest" },
    Callback = function(v) FLAGS.silent_hitpart = v end,
})
TabCombat:AddDropdown({
    Name = "Priority",
    Default = "Crosshair",
    Options = { "Crosshair", "Distance", "Health" },
    Callback = function(v) FLAGS.silent_priority = v end,
})

-- Aimbot
TabAim:AddToggle({
    Name = "Enable Aimbot",
    Default = false,
    Callback = function(v) FLAGS.aimbot_enabled = v end,
})
TabAim:AddToggle({
    Name = "Show FOV",
    Default = false,
    Callback = function(v) FLAGS.aimbot_show_fov = v end,
})
TabAim:AddToggle({
    Name = "Team Check",
    Default = true,
    Callback = function(v) FLAGS.aimbot_team_check = v end,
})
TabAim:AddToggle({
    Name = "Wall Check",
    Default = false,
    Callback = function(v) FLAGS.aimbot_wall_check = v end,
})
TabAim:AddToggle({
    Name = "Hold Key",
    Default = true,
    Callback = function(v) FLAGS.aimbot_hold = v end,
})
TabAim:AddSlider({
    Name = "FOV",
    Min = 20,
    Max = 400,
    Default = 140,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "px",
    Callback = function(v) FLAGS.aimbot_fov = v end,
})
TabAim:AddSlider({
    Name = "Smoothness",
    Min = 1,
    Max = 50,
    Default = 18,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "",
    Callback = function(v) FLAGS.aimbot_smooth = v / 100 end,
})
TabAim:AddSlider({
    Name = "Prediction",
    Min = 0,
    Max = 40,
    Default = 12,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 1,
    ValueName = "",
    Callback = function(v) FLAGS.aimbot_prediction = v / 100 end,
})
TabAim:AddDropdown({
    Name = "Hit Part",
    Default = "Head",
    Options = { "Head", "HRP", "Closest" },
    Callback = function(v) FLAGS.aimbot_hitpart = v end,
})

-- Melee
TabMelee:AddToggle({
    Name = "Melee Aura",
    Default = false,
    Callback = function(v) FLAGS.melee_enabled = v end,
})
TabMelee:AddToggle({
    Name = "Face Back (Backstab)",
    Default = true,
    Callback = function(v) FLAGS.melee_face = v end,
})
TabMelee:AddSlider({
    Name = "Range",
    Min = 6,
    Max = 25,
    Default = 14,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 0.5,
    ValueName = "studs",
    Callback = function(v) FLAGS.melee_range = v end,
})

-- ESP
TabEsp:AddToggle({
    Name = "Enable ESP",
    Default = true,
    Callback = function(v) FLAGS.esp_enabled = v end,
})
TabEsp:AddToggle({
    Name = "Chams",
    Default = true,
    Callback = function(v) FLAGS.esp_chams = v end,
})
TabEsp:AddToggle({
    Name = "Show Teammates",
    Default = false,
    Callback = function(v) FLAGS.esp_team = v end,
})

-- Settings
TabSettings:AddSlider({
    Name = "Max Target Distance",
    Min = 100,
    Max = 2000,
    Default = 1200,
    Color = Color3.fromRGB(255, 255, 255),
    Increment = 50,
    ValueName = "studs",
    Callback = function(v) FLAGS.max_distance = v end,
})
TabSettings:AddButton({
    Name = "Unload",
    Callback = function()
        STATE.unloaded = true
        if silentFov then pcall(function() silentFov:Remove() end) end
        if aimbotFov then pcall(function() aimbotFov:Remove() end) end
        for pl in pairs(STATE.chams) do clearEspFor(pl) end
        for pl in pairs(STATE.boxes) do clearEspFor(pl) end
        pcall(function() OrionLib:Destroy() end)
        if getgenv then getgenv().SleepyOrionUnload = nil end
    end,
})

getgenv().SleepyOrionUnload = function()
    STATE.unloaded = true
    if silentFov then pcall(function() silentFov:Remove() end) end
    if aimbotFov then pcall(function() aimbotFov:Remove() end) end
    for pl in pairs(STATE.chams) do clearEspFor(pl) end
    pcall(function() OrionLib:Destroy() end)
end

OrionLib:MakeNotification({
    Name = "SleepyHub Orion",
    Content = "Rivals combat core loaded",
    Image = "rbxassetid://4483345998",
    Time = 4,
})
pcall(function() OrionLib:Init() end)
print("[SleepyHub Orion] Rivals ready")
