local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local BallsFolder = Workspace:WaitForChild("Balls", 10)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local ParryRemote = Remotes and (Remotes:FindFirstChild("ParryButtonPress")
    or Remotes:FindFirstChild("Parry")
    or Remotes:FindFirstChild("Block"))

local Config = {
    AutoParryEnabled = false,
    DetectionRange = 60,
    FOV = 120,
    ParryDelay = 0,
    PredictionSensitivity = 0.5,
    PredictionMode = "Médio",
    VisualEffects = true,
    Status = "Aguardando",
    TimeToImpact = 0,
    BallDetected = false,
    ParriedRecently = false,
    LastParryTime = 0,
}
local PARRY_COOLDOWN = 0.12

-- ============ RAYFIELD UI ============
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Blade Ball | Auto Parry",
    LoadingTitle = "Carregando...",
    LoadingSubtitle = "Auto Parry",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})
local MainTab = Window:CreateTab("Auto Parry", 4483362458)

MainTab:CreateSection("Controles")
MainTab:CreateToggle({
    Name = "Auto Parry",
    CurrentValue = false,
    Callback = function(v) Config.AutoParryEnabled = v end,
})
MainTab:CreateToggle({
    Name = "Ativar Sistema",
    CurrentValue = false,
    Callback = function(v)
        Config.AutoParryEnabled = v
        if v then StartLoop() else StopLoop() end
    end,
})

MainTab:CreateSection("Detecção")
MainTab:CreateSlider({
    Name = "Distância Máxima", Range = {10,150}, Increment = 5, Suffix = "studs",
    CurrentValue = 60, Callback = function(v) Config.DetectionRange = v end,
})
MainTab:CreateSlider({
    Name = "FOV", Range = {30,180}, Increment = 5, Suffix = "°",
    CurrentValue = 120, Callback = function(v) Config.FOV = v end,
})

MainTab:CreateSection("Timing")
MainTab:CreateSlider({
    Name = "Delay do Parry", Range = {0,200}, Increment = 5, Suffix = "ms",
    CurrentValue = 0, Callback = function(v) Config.ParryDelay = v/1000 end,
})
MainTab:CreateSlider({
    Name = "Sensibilidade", Range = {10,100}, Increment = 5, Suffix = "%",
    CurrentValue = 50, Callback = function(v) Config.PredictionSensitivity = v/100 end,
})
MainTab:CreateDropdown({
    Name = "Modo de Previsão",
    Options = {"Baixo","Médio","Alto"},
    CurrentOption = "Médio",
    Callback = function(o) Config.PredictionMode = o end,
})
MainTab:CreateToggle({
    Name = "Efeitos Visuais", CurrentValue = true,
    Callback = function(v) Config.VisualEffects = v end,
})

-- ============ HUD ============
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoParryHUD"; ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(0,220,0,80)
StatusFrame.Position = UDim2.new(0.5,-110,0,10)
StatusFrame.BackgroundColor3 = Color3.fromRGB(20,20,25)
StatusFrame.BackgroundTransparency = 0.2
StatusFrame.BorderSizePixel = 0
StatusFrame.Parent = ScreenGui
Instance.new("UICorner", StatusFrame).CornerRadius = UDim.new(0,8)

local StatusLabel = Instance.new("TextLabel", StatusFrame)
StatusLabel.Size = UDim2.new(1,-20,0,24); StatusLabel.Position = UDim2.new(0,10,0,6)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Aguardando"
StatusLabel.TextColor3 = Color3.fromRGB(200,200,200)
StatusLabel.TextSize = 14; StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left

local TimeLabel = Instance.new("TextLabel", StatusFrame)
TimeLabel.Size = UDim2.new(1,-20,0,20); TimeLabel.Position = UDim2.new(0,10,0,32)
TimeLabel.BackgroundTransparency = 1; TimeLabel.Text = "Impacto: --"
TimeLabel.TextColor3 = Color3.fromRGB(150,150,150)
TimeLabel.TextSize = 12; TimeLabel.Font = Enum.Font.Gotham
TimeLabel.TextXAlignment = Enum.TextXAlignment.Left

local BallIndicator = Instance.new("Frame", StatusFrame)
BallIndicator.Size = UDim2.new(0,10,0,10); BallIndicator.Position = UDim2.new(1,-20,0,10)
BallIndicator.BackgroundColor3 = Color3.fromRGB(100,100,100)
BallIndicator.BorderSizePixel = 0
Instance.new("UICorner", BallIndicator).CornerRadius = UDim.new(1,0)

-- ============ UTIL ============
local function IsValidBall(b)
    return typeof(b) == "Instance" and b:IsA("BasePart")
        and b:IsDescendantOf(BallsFolder)
        and (b:GetAttribute("realBall") == true or true)
end

local function GetActiveBall()
    for _, b in ipairs(BallsFolder:GetChildren()) do
        if IsValidBall(b) then return b end
    end
end

local function GetBallVelocity(ball)
    local v = ball.AssemblyLinearVelocity
    if v.Magnitude > 1 then return v end
    local z = ball:FindFirstChild("zoomies")
    if z then
        for _, c in ipairs(z:GetDescendants()) do
            if (c:IsA("BodyVelocity") or c:IsA("LinearVelocity")) and c.Velocity.Magnitude > 1 then
                return c.Velocity
            end
        end
    end
    return v
end

local function IsPlayerTarget(ball)
    local target = ball:GetAttribute("target")
    if target then
        if typeof(target) == "Instance" and target == LocalPlayer then return true end
        if type(target) == "string" and (target == LocalPlayer.Name or target == LocalPlayer.DisplayName) then
            return true
        end
    end
    local char = LocalPlayer.Character
    if char then
        local hl = char:FindFirstChildOfClass("Highlight")
        if hl and hl.Enabled and hl.FillColor.R > 0.8 and hl.FillColor.G < 0.3 then
            return true
        end
    end
    return false
end

local function CalculateBallApproach(ball)
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local ballPos = ball.Position
    local hrpPos = hrp.Position
    local ballToPlayer = hrpPos - ballPos
    local distance = ballToPlayer.Magnitude
    if distance < 0.1 then return nil end

    local velocity = GetBallVelocity(ball)
    local speed = velocity.Magnitude
    if speed < 1 then return nil end

    local dotProduct = velocity.Unit:Dot(ballToPlayer.Unit)
    local timeToImpact = distance / speed

    return {
        dotProduct = dotProduct, distance = distance,
        timeToImpact = timeToImpact, speed = speed,
        velocity = velocity, ballPos = ballPos, hrpPos = hrpPos,
    }
end

local function ExecuteParry()
    local now = tick()
    if now - Config.LastParryTime < PARRY_COOLDOWN then return end
    Config.LastParryTime = now

    if ParryRemote then
        ParryRemote:FireServer()
    else
        VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,0)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,0)
    end
    Config.Status = "Parry executado"
    Config.ParriedRecently = true
    task.delay(0.25, function()
        if Config.Status == "Parry executado" then Config.Status = "Aguardando" end
        Config.ParriedRecently = false
    end)
end

local function UpdateHUD()
    if not Config.VisualEffects then StatusFrame.Visible = false; return end
    StatusFrame.Visible = true
    StatusLabel.Text = "Status: " .. Config.Status
    TimeLabel.Text = Config.BallDetected and string.format("Impacto: %.2fs", Config.TimeToImpact) or "Impacto: --"
    if Config.Status == "Parry executado" then
        BallIndicator.BackgroundColor3 = Color3.fromRGB(0,255,100)
    elseif Config.BallDetected then
        BallIndicator.BackgroundColor3 = Color3.fromRGB(255,200,0)
    else
        BallIndicator.BackgroundColor3 = Color3.fromRGB(100,100,100)
    end
end

-- ============ LOOP ============
local Conn
local function OnPreSimulation()
    if not Config.AutoParryEnabled then
        Config.BallDetected = false; Config.Status = "Aguardando"
        Config.TimeToImpact = 0; UpdateHUD(); return
    end

    local ball = GetActiveBall()
    if not ball then
        Config.BallDetected = false; Config.Status = "Aguardando"
        Config.TimeToImpact = 0; Config.ParriedRecently = false
        UpdateHUD(); return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then UpdateHUD(); return end

    local vel = GetBallVelocity(ball)
    local delta = hrp.Position - ball.Position
    local dist = delta.Magnitude

    if dist > Config.DetectionRange then
        Config.BallDetected = false; Config.Status = "Aguardando"
        UpdateHUD(); return
    end

    -- FALLBACK por proximidade (mais confiável)
    if dist < 18 and vel.Magnitude > 1 and delta.Unit:Dot(vel.Unit) > 0.3 then
        Config.BallDetected = true
        Config.TimeToImpact = dist / math.max(vel.Magnitude,1)
        Config.Status = "Bola detectada"
        if not Config.ParriedRecently then ExecuteParry() end
        UpdateHUD(); return
    end

    -- Verificação normal
    if not IsPlayerTarget(ball) then
        Config.BallDetected = false; Config.Status = "Aguardando"
        Config.TimeToImpact = 0; Config.ParriedRecently = false
        UpdateHUD(); return
    end

    local info = CalculateBallApproach(ball)
    if not info or info.dotProduct <= 0.2 then
        Config.BallDetected = false; Config.Status = "Aguardando"
        UpdateHUD(); return
    end

    Config.BallDetected = true
    Config.TimeToImpact = info.timeToImpact
    Config.Status = "Bola detectada"

    local modeMul = (Config.PredictionMode == "Alto" and 1.4)
        or (Config.PredictionMode == "Baixo" and 0.7) or 1.0
    local targetT = Config.PredictionSensitivity * modeMul * 0.2 + Config.ParryDelay

    if not Config.ParriedRecently and info.timeToImpact <= targetT then
        ExecuteParry()
    end
    UpdateHUD()
end

function StartLoop()
    if Conn then return end
    Conn = RunService.PreSimulation:Connect(OnPreSimulation)
end
function StopLoop()
    if Conn then Conn:Disconnect(); Conn = nil end
end

game:BindToClose(function() StopLoop(); ScreenGui:Destroy() end)

Rayfield:Notify({
    Title = "Auto Parry Carregado",
    Content = "Ative 'Ativar Sistema' para começar.",
    Duration = 5, Image = 4483362458,
})
