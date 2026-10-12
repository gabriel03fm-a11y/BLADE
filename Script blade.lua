--[[
    BLADE BALL - AUTO PARRY SCRIPT
    Foco: Sistema de Auto Parry com previsão, UI mobile e otimização.
    Biblioteca UI: Rayfield
    Compatível: PC e Mobile (executores como Delta, Xeno, etc.)
--]]

--=====================================================================
-- SERVIÇOS E VARIÁVEIS GLOBAIS
--=====================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local BallsFolder = Workspace:WaitForChild("Balls", 10)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local ParryRemote = Remotes and Remotes:WaitForChild("ParryButtonPress", 10)

--=====================================================================
-- CONFIGURAÇÕES PADRÃO (podem ser alteradas pela UI)
--=====================================================================
local Config = {
    AutoParryEnabled = false,
    DetectionRange = 60,        -- Distância máxima de detecção (studs)
    FOV = 90,                   -- Ângulo máximo (graus) para considerar a bola vindo em direção ao jogador
    ParryDelay = 0.05,          -- Delay em segundos antes de executar o parry (compensação de ping)
    PredictionSensitivity = 0.5,-- Sensibilidade do sistema de previsão (0.1 a 1.0)
    PredictionMode = "Médio",   -- Baixo / Médio / Alto
    VisualEffects = true,       -- Mostrar efeitos visuais (indicador na bola e HUD)
    Status = "Aguardando",      -- Status atual do sistema
    TimeToImpact = 0,           -- Tempo estimado até o impacto
    BallDetected = false,       -- Se uma bola está sendo rastreada
    ParriedRecently = false,    -- Evita parrys múltiplos no mesmo ciclo
    LastParryTime = 0,          -- Cooldown interno
}

-- Cooldown mínimo entre parrys (evita spam)
local PARRY_COOLDOWN = 0.15

--=====================================================================
-- BIBLIOTECA DE UI (RAYFIELD)
--=====================================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Blade Ball | Auto Parry",
    LoadingTitle = "Carregando Auto Parry...",
    LoadingSubtitle = "por Assistente",
    ConfigurationSaving = {
        Enabled = false,
    },
    KeySystem = false,
})

-- Aba principal
local MainTab = Window:CreateTab("Auto Parry", 4483362458)

-- Seção: Controles
MainTab:CreateSection("Controles Principais")

-- Toggle: Auto Parry
MainTab:CreateToggle({
    Name = "Auto Parry",
    CurrentValue = false,
    Flag = "AutoParryToggle",
    Callback = function(value)
        Config.AutoParryEnabled = value
        if value then
            Config.Status = "Aguardando"
        else
            Config.Status = "Desativado"
            Config.BallDetected = false
            Config.TimeToImpact = 0
        end
    end,
})

-- Seção: Detecção
MainTab:CreateSection("Detecção")

-- Slider: Distância máxima de detecção
MainTab:CreateSlider({
    Name = "Distância Máxima (studs)",
    Range = {10, 150},
    Increment = 5,
    Suffix = "studs",
    CurrentValue = 60,
    Flag = "DetectionRange",
    Callback = function(value)
        Config.DetectionRange = value
    end,
})

-- Slider: FOV (ângulo máximo)
MainTab:CreateSlider({
    Name = "FOV / Ângulo Máximo",
    Range = {30, 180},
    Increment = 5,
    Suffix = "°",
    CurrentValue = 90,
    Flag = "FOV",
    Callback = function(value)
        Config.FOV = value
    end,
})

-- Seção: Timing
MainTab:CreateSection("Timing e Previsão")

-- Slider: Delay do parry
MainTab:CreateSlider({
    Name = "Delay do Parry",
    Range = {0, 200},
    Increment = 5,
    Suffix = "ms",
    CurrentValue = 50,
    Flag = "ParryDelay",
    Callback = function(value)
        Config.ParryDelay = value / 1000 -- Converte para segundos
    end,
})

-- Slider: Sensibilidade da previsão
MainTab:CreateSlider({
    Name = "Sensibilidade da Previsão",
    Range = {10, 100},
    Increment = 5,
    Suffix = "%",
    CurrentValue = 50,
    Flag = "PredictionSensitivity",
    Callback = function(value)
        Config.PredictionSensitivity = value / 100
    end,
})

-- Dropdown: Modo de Previsão
MainTab:CreateDropdown({
    Name = "Modo de Previsão",
    Options = {"Baixo", "Médio", "Alto"},
    CurrentOption = "Médio",
    Flag = "PredictionMode",
    Callback = function(option)
        Config.PredictionMode = option
    end,
})

-- Seção: Visual
MainTab:CreateSection("Visual")

-- Toggle: Efeitos Visuais
MainTab:CreateToggle({
    Name = "Efeitos Visuais",
    CurrentValue = true,
    Flag = "VisualEffects",
    Callback = function(value)
        Config.VisualEffects = value
    end,
})

--=====================================================================
-- HUD (INDICADOR VISUAL)
--=====================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoParryHUD"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Painel de status
local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(0, 220, 0, 80)
StatusFrame.Position = UDim2.new(0.5, -110, 0, 10)
StatusFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
StatusFrame.BackgroundTransparency = 0.2
StatusFrame.BorderSizePixel = 0
StatusFrame.Visible = true
StatusFrame.Parent = ScreenGui

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 8)
StatusCorner.Parent = StatusFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 24)
StatusLabel.Position = UDim2.new(0, 10, 0, 6)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Aguardando"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.TextSize = 14
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = StatusFrame

local TimeLabel = Instance.new("TextLabel")
TimeLabel.Size = UDim2.new(1, -20, 0, 20)
TimeLabel.Position = UDim2.new(0, 10, 0, 32)
TimeLabel.BackgroundTransparency = 1
TimeLabel.Text = "Impacto: --"
TimeLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
TimeLabel.TextSize = 12
TimeLabel.Font = Enum.Font.Gotham
TimeLabel.TextXAlignment = Enum.TextXAlignment.Left
TimeLabel.Parent = StatusFrame

local BallIndicator = Instance.new("Frame")
BallIndicator.Size = UDim2.new(0, 10, 0, 10)
BallIndicator.Position = UDim2.new(1, -20, 0, 10)
BallIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
BallIndicator.BorderSizePixel = 0
BallIndicator.Parent = StatusFrame

local BallIndicatorCorner = Instance.new("UICorner")
BallIndicatorCorner.CornerRadius = UDim.new(1, 0)
BallIndicatorCorner.Parent = BallIndicator

--=====================================================================
-- FUNÇÕES UTILITÁRIAS
--=====================================================================

--- Verifica se uma instância é uma bola válida do jogo.
local function IsValidBall(ball)
    return typeof(ball) == "Instance"
        and ball:IsA("BasePart")
        and ball:IsDescendantOf(BallsFolder)
        and ball:GetAttribute("realBall") == true
end

--- Obtém a bola ativa no momento (a que tem o atributo realBall).
local function GetActiveBall()
    for _, ball in ipairs(BallsFolder:GetChildren()) do
        if IsValidBall(ball) then
            return ball
        end
    end
    return nil
end

--- Verifica se o jogador local é o alvo atual da bola.
local function IsPlayerTarget(ball)
    if not ball then return false end

    -- Método 1: Atributo "target" contém o nome do jogador
    local targetName = ball:GetAttribute("target")
    if targetName == LocalPlayer.Name then
        return true
    end

    -- Método 2: Personagem tem um Highlight (indicador de alvo)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Highlight") then
        return true
    end

    return false
end

--- Calcula a direção da bola em relação ao jogador e verifica se está se aproximando.
--- Retorna: dotProduct (positivo = aproximando), distance, timeToImpact, speed
local function CalculateBallApproach(ball)
    local char = LocalPlayer.Character
    if not char then return nil end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local ballPos = ball.Position
    local hrpPos = hrp.Position
    local ballToPlayer = hrpPos - ballPos
    local distance = ballToPlayer.Magnitude

    -- Obtém a velocidade da bola (pode estar em "zoomies" ou na própria bola)
    local velocity = ball.AssemblyLinearVelocity
    if ball:FindFirstChild("zoomies") then
        local zoomies = ball.zoomies
        if zoomies:FindFirstChild("VectorVelocity") then
            velocity = zoomies.VectorVelocity
        end
    end

    local speed = velocity.Magnitude
    if speed < 1 then return nil end -- Bola praticamente parada

    -- Produto escalar: direção da bola . direção para o jogador
    local directionToPlayer = ballToPlayer.Unit
    local ballDirection = velocity.Unit
    local dotProduct = ballDirection:Dot(directionToPlayer)

    -- Tempo estimado até o impacto (simplificado)
    local timeToImpact = distance / speed

    return {
        dotProduct = dotProduct,
        distance = distance,
        timeToImpact = timeToImpact,
        speed = speed,
        velocity = velocity,
        ballPos = ballPos,
        hrpPos = hrpPos,
    }
end

--- Verifica se a bola está dentro do FOV (ângulo) configurado.
local function IsWithinFOV(ballInfo)
    if not ballInfo then return false end
    -- dotProduct >= cos(FOV/2) significa que a bola está vindo dentro do cone
    local halfFOVRad = math.rad(Config.FOV / 2)
    local cosThreshold = math.cos(halfFOVRad)
    return ballInfo.dotProduct >= cosThreshold
end

--- Executa a ação de parry.
local function ExecuteParry()
    local now = tick()
    if now - Config.LastParryTime < PARRY_COOLDOWN then return end

    Config.LastParryTime = now

    -- Método preferido: disparar o remote de parry (mais confiável)
    if ParryRemote then
        ParryRemote:FireServer()
    else
        -- Fallback: simular clique do mouse (funciona na maioria dos casos)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end

    Config.Status = "Parry executado"
    Config.ParriedRecently = true

    -- Reset do status após breve período
    task.delay(0.3, function()
        if Config.Status == "Parry executado" then
            Config.Status = "Aguardando"
        end
    end)
end

--- Atualiza o HUD com as informações atuais.
local function UpdateHUD()
    if not Config.VisualEffects then
        StatusFrame.Visible = false
        return
    end

    StatusFrame.Visible = true
    StatusLabel.Text = "Status: " .. Config.Status
    TimeLabel.Text = Config.BallDetected
        and string.format("Impacto: %.2fs", Config.TimeToImpact)
        or "Impacto: --"

    -- Indicador colorido
    if Config.Status == "Parry executado" then
        BallIndicator.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
    elseif Config.BallDetected then
        BallIndicator.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    else
        BallIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    end
end

--=====================================================================
-- LOOP PRINCIPAL (PreSimulation para timing preciso)
--=====================================================================
local ParryConnection = nil

--- Função principal executada a cada frame (apenas quando Auto Parry está ativo).
local function OnPreSimulation()
    if not Config.AutoParryEnabled then
        Config.BallDetected = false
        Config.Status = "Aguardando"
        Config.TimeToImpact = 0
        UpdateHUD()
        return
    end

    local ball = GetActiveBall()
    if not ball then
        Config.BallDetected = false
        Config.Status = "Aguardando"
        Config.TimeToImpact = 0
        Config.ParriedRecently = false
        UpdateHUD()
        return
    end

    -- Verifica se o jogador é o alvo
    if not IsPlayerTarget(ball) then
        Config.BallDetected = false
        Config.Status = "Aguardando"
        Config.TimeToImpact = 0
        Config.ParriedRecently = false
        UpdateHUD()
        return
    end

    -- Calcula informações da bola
    local info = CalculateBallApproach(ball)
    if not info then
        Config.BallDetected = false
        UpdateHUD()
        return
    end

    -- Verifica distância máxima
    if info.distance > Config.DetectionRange then
        Config.BallDetected = false
        Config.Status = "Aguardando"
        UpdateHUD()
        return
    end

    -- Verifica se a bola está se aproximando (dotProduct > 0)
    -- e dentro do FOV configurado
    if info.dotProduct <= 0 or not IsWithinFOV(info) then
        Config.BallDetected = false
        Config.Status = "Aguardando"
        UpdateHUD()
        return
    end

    -- Bola detectada e vindo na direção do jogador
    Config.BallDetected = true
    Config.TimeToImpact = info.timeToImpact

    -- Ajusta o tempo alvo com base no modo de previsão e sensibilidade
    local predictionFactor = Config.PredictionSensitivity
    local modeMultiplier = 1.0

    if Config.PredictionMode == "Baixo" then
        modeMultiplier = 0.7
    elseif Config.PredictionMode == "Alto" then
        modeMultiplier = 1.3
    end

    local adjustedTargetTime = predictionFactor * modeMultiplier * 0.5 -- Base de 0.5s

    -- Adiciona o delay configurado
    local effectiveTargetTime = adjustedTargetTime + Config.ParryDelay

    -- Verifica se é o momento de executar o parry
    if not Config.ParriedRecently and info.timeToImpact <= effectiveTargetTime then
        Config.Status = "Bola detectada"
        ExecuteParry()
    else
        Config.Status = "Bola detectada"
    end

    UpdateHUD()
end

--=====================================================================
-- CONTROLE DE ATIVAÇÃO / DESATIVAÇÃO
--=====================================================================

--- Inicia o loop de detecção.
local function StartParryLoop()
    if ParryConnection then return end
    ParryConnection = RunService.PreSimulation:Connect(OnPreSimulation)
end

--- Para o loop e limpa conexões.
local function StopParryLoop()
    if ParryConnection then
        ParryConnection:Disconnect()
        ParryConnection = nil
    end
end

-- Observa mudanças no toggle de Auto Parry para iniciar/parar o loop
MainTab:CreateToggle({
    Name = "Ativar Sistema",
    CurrentValue = false,
    Flag = "SystemActive",
    Callback = function(value)
        Config.AutoParryEnabled = value
        if value then
            StartParryLoop()
        else
            StopParryLoop()
        end
    end,
})

--=====================================================================
-- LIMPEZA AO DESCARREGAR
--=====================================================================
-- Desconecta todas as conexões quando o script for interrompido
game:BindToClose(function()
    StopParryLoop()
    if ScreenGui then
        ScreenGui:Destroy()
    end
end)

-- Notificação inicial
Rayfield:Notify({
    Title = "Auto Parry Carregado",
    Content = "Use o toggle 'Ativar Sistema' para começar.",
    Duration = 5,
    Image = 4483362458,
})
