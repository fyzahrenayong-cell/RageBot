--!nocheck
-- Always.winning | Rage Only
-- Sleepy / Meow combat core — silent aim + melee aura
-- Module dropdown: which targeting/silent path to run

if getgenv().AlwaysWinningRage and getgenv().AlwaysWinningRage.Unload then
    pcall(getgenv().AlwaysWinningRage.Unload)
end

local Players = cloneref and cloneref(game:GetService("Players")) or game:GetService("Players")
local RunService = cloneref and cloneref(game:GetService("RunService")) or game:GetService("RunService")
local Workspace = cloneref and cloneref(game:GetService("Workspace")) or game:GetService("Workspace")
local UserInputService = cloneref and cloneref(game:GetService("UserInputService")) or game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

getgenv().meow_flags = getgenv().meow_flags or {}
local flags = getgenv().meow_flags

-- defaults: silent + melee on, FOV wide
flags.silent_aim_enabled = flags.silent_aim_enabled ~= false and true or flags.silent_aim_enabled
if flags.silent_aim_enabled == nil then flags.silent_aim_enabled = true end
flags.hit_chance = flags.hit_chance or 100
flags.fov_radius_smoothed = flags.fov_radius_smoothed or 400
flags.target_priority = flags.target_priority or "Closest"
flags.target_hitbox = flags.target_hitbox or "Head"
flags.knife_rage = flags.knife_rage ~= false
if flags.knife_rage == nil then flags.knife_rage = true end
flags.melee_safe_reach = flags.melee_safe_reach or 12
flags.melee_auto_face_back = true
flags.avoid_katana = flags.avoid_katana or false
flags.riot_shield_check = flags.riot_shield_check or false
flags.module = flags.module or "Sleepy"
flags.show_fov = flags.show_fov ~= false
flags.aimbot_enabled = false
flags.aimbot_active = false

getgenv().meowState = getgenv().meowState or {
    Destroyed = false,
    PriorityList = {},
    CurrentTarget = nil,
    LastTargetPlayer = nil,
    LastMeleeAttack = 0,
}
local meowState = getgenv().meowState
meowState.Destroyed = false

local fakePos = getgenv().fakePos or { Enabled = false, VirtualCF = nil, AutoHandoff = false, HandoffTicks = 0 }
local conns = {}
local function track(c) conns[#conns+1] = c; return c end

local fovCircle, fovOutline


-- ===== Sleepy / Meow helpers =====
is_deflecting = function(fighter)
    if not fighter then return false end
    local char = (type(fighter) == "table" and fighter.Character) or (typeof(fighter) == "Instance" and fighter)
    if not char then return false end
    local katana = char:FindFirstChild("Katana")
    if katana and katana:FindFirstChild("Deflecting") and katana.Deflecting.Value == true then
        return true
    end
    return false
end

shield_blocks_shot = function(targetRoot, shooterPos)
    if not targetRoot then return false end
    local char = targetRoot.Parent
    if not char then return false end
    local shield = char:FindFirstChild("Riot Shield") or char:FindFirstChild("Shield")
    if not shield then return false end
    local targetLook = targetRoot.CFrame.LookVector
    local shotDir = (shooterPos - targetRoot.Position).Unit
    return targetLook:Dot(shotDir) < -0.2
end

ragebot_is_priority = function(player)
    if not player then return false end
    local name = typeof(player) == "Instance" and player.Name or tostring(player)
    return meowState.PriorityList[name:lower()] == true
end

silent_closest_hitbox = function(char)
    if not char then return nil end
    local mode = flags.target_hitbox or "Head"
    if mode == "Head" then
        return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    elseif mode == "HumanoidRootPart" or mode == "Torso" then
        return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    elseif mode == "Random" then
        local parts = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"}
        return char:FindFirstChild(parts[math.random(1, #parts)]) or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

get_target = function()
    local myChar = LocalPlayer.Character
    if not myChar then return nil end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local bestTarget = nil
    local bestScore = math.huge
    local method = flags.target_priority or "Lowest Health"
    local fovRadius = flags.fov_radius_smoothed or 120
    local center = Camera.ViewportSize / 2

    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local char = pl.Character
            local hum = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")

            if hum and hum.Health > 0 and root and not char:FindFirstChildOfClass("ForceField") then
                if not (flags.riot_shield_check and shield_blocks_shot(root, myRoot.Position)) then
                    if not (flags.avoid_katana and is_deflecting(char)) then
                        local scrPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                        local fovDist = (Vector2.new(scrPos.X, scrPos.Y) - center).Magnitude

                        if not flags.silent_aim_enabled or fovDist <= fovRadius then
                            local dist = (root.Position - myRoot.Position).Magnitude
                            local health = hum.Health
                            local isPriority = ragebot_is_priority(pl)
                            local score = health

                            if method == "Distance" or method == "Closest Distance" then
                                score = dist
                            elseif method == "Crosshair" then
                                score = fovDist
                            elseif method == "FOV - Lowest Health" then
                                score = (health * 2) + fovDist
                            else
                                score = health
                            end

                            if isPriority then
                                score = score - 10000
                            end

                            if score < bestScore then
                                bestScore = score
                                bestTarget = {
                                    Player = pl,
                                    Character = char,
                                    Humanoid = hum,
                                    RootPart = root,
                                    HitPart = silent_closest_hitbox(char),
                                    Distance = dist,
                                    FOVDistance = fovDist,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    meowState.CurrentTarget = bestTarget
    if bestTarget then meowState.LastTargetPlayer = bestTarget.Player end
    return bestTarget
end
local function runMeleeAura()
    if not flags.knife_rage then return end
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local now = os.clock()
    if now - meowState.LastMeleeAttack < 0.12 then return end

    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local root = pl.Character:FindFirstChild("HumanoidRootPart")
            local hum = pl.Character:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local dist = (root.Position - myRoot.Position).Magnitude
                if dist <= (flags.melee_safe_reach or 12) then
                    meowState.LastMeleeAttack = now
                    pcall(function()
                        if flags.melee_auto_face_back ~= false then
                            myRoot.CFrame = CFrame.new(myRoot.Position, myRoot.Position - root.CFrame.LookVector)
                        end
                        local tool = myChar:FindFirstChildOfClass("Tool")
                        if tool then tool:Activate() end
                    end)
                    break
                end
            end
        end
    end
end


-- Minimal module: FOV closest head only (fallback)
local function get_target_minimal()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local best, bestScore = nil, math.huge
    local fov = flags.fov_radius_smoothed or 400
    local center = Camera.ViewportSize / 2
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local hum = pl.Character:FindFirstChildOfClass("Humanoid")
            local root = pl.Character:FindFirstChild("HumanoidRootPart")
            local head = pl.Character:FindFirstChild("Head") or root
            if hum and hum.Health > 0 and root and head then
                local sp, on = Camera:WorldToViewportPoint(head.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d <= fov and d < bestScore then
                        bestScore = d
                        best = { Player = pl, HitPart = head, Root = root }
                    end
                end
            end
        end
    end
    meowState.CurrentTarget = best
    return best
end

local function resolve_target()
    if flags.module == "Minimal" then
        return get_target_minimal()
    end
    -- Sleepy (default)
    return get_target()
end

-- Silent: Workspace ray redirect (Sleepy path)
if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if (not checkcaller or not checkcaller()) and flags.silent_aim_enabled then
            if (method == "Raycast" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay") and self == Workspace then
                local origin = args[1]
                if fakePos.Enabled and fakePos.VirtualCF then
                    origin = fakePos.VirtualCF.Position
                    args[1] = origin
                end
                local target = meowState.CurrentTarget or resolve_target()
                if target and target.HitPart then
                    local hitChance = flags.hit_chance or 100
                    if math.random(1, 100) <= hitChance then
                        local targetDir = (target.HitPart.Position - origin).Unit * 1000
                        args[2] = targetDir
                        if fakePos.Enabled and fakePos.AutoHandoff then
                            fakePos.HandoffTicks = 2
                        end
                        return oldNamecall(self, table.unpack(args))
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end)
else
    warn("[Always.winning] hookmetamethod missing — silent ray rewrite off")
end

-- FOV circle
local function ensureFov()
    if not Drawing then return end
    if not fovCircle then
        fovCircle = Drawing.new("Circle")
        fovCircle.Thickness = 1
        fovCircle.NumSides = 64
        fovCircle.Filled = false
        fovCircle.Color = Color3.fromRGB(255, 255, 255)
        fovCircle.Transparency = 1
        fovOutline = Drawing.new("Circle")
        fovOutline.Thickness = 2
        fovOutline.NumSides = 64
        fovOutline.Filled = false
        fovOutline.Color = Color3.fromRGB(0, 0, 0)
        fovOutline.Transparency = 0.5
    end
end

track(RunService.RenderStepped:Connect(function()
    if meowState.Destroyed then return end
    ensureFov()
    if not fovCircle then return end
    local show = flags.show_fov and flags.silent_aim_enabled
    fovCircle.Visible = show
    if fovOutline then fovOutline.Visible = show end
    if show then
        local c = Camera.ViewportSize / 2
        local r = flags.fov_radius_smoothed or 400
        fovCircle.Position = c
        fovCircle.Radius = r
        if fovOutline then
            fovOutline.Position = c
            fovOutline.Radius = r
        end
    end
end))

track(RunService.Heartbeat:Connect(function()
    if meowState.Destroyed then return end
    pcall(function()
        meowState.CurrentTarget = resolve_target()
        if flags.knife_rage then runMeleeAura() end
    end)
end))

-- ===== UI (Obsidian if available, else no UI — flags still live) =====
local function buildUI()
    local ok, Library = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua"))()
    end)
    if not ok or not Library then
        print("[Always.winning] No Obsidian — running headless with defaults")
        return
    end
    local Window = Library:CreateWindow({
        Title = "Always.winning | Rage",
        Footer = "silent + melee",
        Center = true,
        AutoShow = true,
        Resizable = true,
        MobileButtonsSide = "Right",
    })
    local Tabs = { Rage = Window:AddTab("Rage"), Settings = Window:AddTab("Settings") }
    local G = Tabs.Rage:AddLeftGroupbox("Silent")
    G:AddToggle("SilentOn", {
        Text = "Silent Aim",
        Default = flags.silent_aim_enabled,
        Callback = function(v) flags.silent_aim_enabled = v end,
    })
    G:AddToggle("ShowFov", {
        Text = "Show FOV",
        Default = flags.show_fov ~= false,
        Callback = function(v) flags.show_fov = v end,
    })
    G:AddSlider("FovR", {
        Text = "FOV Radius",
        Default = flags.fov_radius_smoothed or 400,
        Min = 20, Max = 800, Rounding = 0,
        Callback = function(v) flags.fov_radius_smoothed = v end,
    })
    G:AddSlider("HitChance", {
        Text = "Hit Chance %",
        Default = flags.hit_chance or 100,
        Min = 1, Max = 100, Rounding = 0,
        Callback = function(v) flags.hit_chance = v end,
    })
    G:AddDropdown("Hitbox", {
        Text = "Hitbox",
        Default = flags.target_hitbox or "Head",
        Values = { "Head", "HumanoidRootPart", "Torso", "Random" },
        Callback = function(v) flags.target_hitbox = v end,
    })
    G:AddDropdown("Priority", {
        Text = "Priority",
        Default = flags.target_priority or "Closest",
        Values = { "Closest", "Lowest Health", "Distance", "Crosshair", "FOV - Lowest Health" },
        Callback = function(v) flags.target_priority = v end,
    })

    local M = Tabs.Rage:AddRightGroupbox("Melee")
    M:AddToggle("KnifeRage", {
        Text = "Melee Aura",
        Default = flags.knife_rage,
        Callback = function(v) flags.knife_rage = v end,
    })
    M:AddSlider("MeleeReach", {
        Text = "Reach",
        Default = flags.melee_safe_reach or 12,
        Min = 4, Max = 30, Rounding = 0,
        Callback = function(v) flags.melee_safe_reach = v end,
    })
    M:AddToggle("FaceBack", {
        Text = "Face Back",
        Default = true,
        Callback = function(v) flags.melee_auto_face_back = v end,
    })

    local Mod = Tabs.Settings:AddLeftGroupbox("Module")
    Mod:AddDropdown("ModulePick", {
        Text = "Rage Module",
        Default = flags.module or "Sleepy",
        Values = { "Sleepy", "Minimal" },
        Callback = function(v) flags.module = v end,
    })
    Mod:AddLabel("Sleepy = full get_target + shield/priority")
    Mod:AddLabel("Minimal = FOV closest head only")

    local Sys = Tabs.Settings:AddRightGroupbox("System")
    Sys:AddButton("Unload", function()
        if getgenv().AlwaysWinningRage and getgenv().AlwaysWinningRage.Unload then
            getgenv().AlwaysWinningRage.Unload()
        end
        pcall(function() Library:Unload() end)
    end)

    Library:Notify({ Title = "Always.winning", Description = "Rage online — " .. tostring(flags.module), Time = 3 })
end

pcall(buildUI)

getgenv().AlwaysWinningRage = {
    Unload = function()
        meowState.Destroyed = true
        flags.silent_aim_enabled = false
        flags.knife_rage = false
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        table.clear(conns)
        if fovCircle then pcall(function() fovCircle:Remove() end) fovCircle = nil end
        if fovOutline then pcall(function() fovOutline:Remove() end) fovOutline = nil end
        getgenv().AlwaysWinningRage = nil
        print("[Always.winning] rage unloaded")
    end,
    flags = flags,
    state = meowState,
    get_target = resolve_target,
}

print("[Always.winning] rage online | module=" .. tostring(flags.module) .. " silent=" .. tostring(flags.silent_aim_enabled) .. " melee=" .. tostring(flags.knife_rage))
