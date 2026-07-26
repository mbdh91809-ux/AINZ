-- [[ Smart Combat, Movement & Checkpoint Suite: God Edition ]] --
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera

-- إعدادات الحفظ التلقائي لنقاط الانتقال
local fileName = "EasyCheckpoints_Map_" .. game.PlaceId .. ".txt"
local positions = { J = nil, K = nil, L = nil }

-- إعدادات الحالات والميزات
local Features = {
    KillAura = false,
    KillAuraAnims = false,
    AutoBlock = false,
    AttackRange = 25,
    SpeedEnabled = false,
    FlyEnabled = false,
    SpeedValue = 50,
    FlyValue = 50,
    WhiteList = ""
}

-- أزرار الكيبورد الافتراضية
local Keybinds = {
    KillAura = "X",
    AutoBlock = "C",
    SpeedEnabled = "Q",
    FlyEnabled = "E"
}

-- دالات حفظ وتحميل النقاط
local function saveToFile()
    if writefile then
        local dataToSave = {}
        for k, v in pairs(positions) do
            if v then dataToSave[k] = {v.X, v.Y, v.Z} end
        end
        pcall(writefile, fileName, HttpService:JSONEncode(dataToSave))
    end
end

local function loadFromFile()
    if readfile and isfile and isfile(fileName) then
        local success, content = pcall(readfile, fileName)
        if success and content then
            local success2, decoded = pcall(HttpService.JSONDecode, HttpService, content)
            if success2 and decoded then
                for k, v in pairs(decoded) do
                    positions[k] = Vector3.new(v[1], v[2], v[3])
                end
            end
        end
    end
end
loadFromFile()

-- الوصول إلى ريموتات اللعبة
local CombatRF = ReplicatedStorage:WaitForChild("OldPackages", 8):WaitForChild("Knit", 5):WaitForChild("Services", 5):WaitForChild("CombatService", 5):WaitForChild("RF", 5)
local HitRF, BlockRF = CombatRF:WaitForChild("Hit", 5), CombatRF:WaitForChild("Block", 5)

-- تحميل حركات الضرب
local animPath = ReplicatedStorage:WaitForChild("OldControllers", 8):WaitForChild("CombatClient", 5):WaitForChild("Animations", 5)
local rightPunch, leftPunch = animPath:WaitForChild("Right Punch", 5), animPath:WaitForChild("Left Punch", 5)
local ANIM_DELAY, lastAnimTime = 0.05, 0

local function PlayKillAuraAnim()
    local now = os.clock()
    if now - lastAnimTime < ANIM_DELAY then return end
    lastAnimTime = now
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if not anim then return end
    local punch = (math.random(1, 2) == 1) and rightPunch or leftPunch
    pcall(function() anim:LoadAnimation(punch):Play() end)
end

-- قائمة الحسابات المحمية (مستحيل تتدامج نهائياً)
local ProtectedPlayers = {
    ["ainz"] = true,
    ["sewar"] = true,
    ["h0outarou"] = true
}

-- فحص القائمة البيضاء + الحسابات المحمية
local function IsWhitelisted(plr)
    local targetUser = string.lower(plr.Name)
    local targetDisplay = string.lower(plr.DisplayName)
    
    -- فحص الحسابات المحمية تلقائياً
    if ProtectedPlayers[targetUser] or ProtectedPlayers[targetDisplay] then
        return true
    end
    
    -- فحص الـ WhiteList المكتوبة في الـ GUI
    if Features.WhiteList == "" then return false end
    local names = string.split(string.lower(Features.WhiteList), " ")
    for _, name in pairs(names) do
        if name ~= "" and (targetUser:find(name) or targetDisplay:find(name)) then return true end
    end
    return false
end

-- دالة البحث عن اللاعبين بالاختصارات
local function GetPlayerByName(str)
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(str) == string.lower(p.Name) or string.sub(string.lower(p.Name), 1, #str) == string.lower(str) or string.lower(str) == string.lower(p.DisplayName) or string.sub(string.lower(p.DisplayName), 1, #str) == string.lower(str) then
            return p
        end
    end
    return nil
end

-- إنشاء تأثير التحديد باللون الأسود
local AuraHighlight = Instance.new("Highlight")
AuraHighlight.Name = "KillAuraTargetHighlight"
AuraHighlight.FillColor = Color3.fromRGB(0, 0, 0)
AuraHighlight.OutlineColor = Color3.fromRGB(0, 0, 0)
AuraHighlight.FillTransparency = 0.4
AuraHighlight.OutlineTransparency = 0

local function ClearHighlight()
    AuraHighlight.Adornee = nil
    AuraHighlight.Parent = nil
end

-- ────────────────────────────────────────────────
--  حلقة التحكم بالسرعة والطيران
-- ────────────────────────────────────────────────
local flyBodyVel, flyBodyGyro
RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    if Features.SpeedEnabled and hum.MoveDirection.Magnitude > 0 then
        root.CFrame = root.CFrame + (hum.MoveDirection * (Features.SpeedValue / 60))
    end

    if Features.FlyEnabled then
        if not flyBodyVel or flyBodyVel.Parent ~= root then
            if root:FindFirstChild("FlyVelocity") then root.FlyVelocity:Destroy() end
            if root:FindFirstChild("FlyGyro") then root.FlyGyro:Destroy() end
            
            flyBodyVel = Instance.new("BodyVelocity")
            flyBodyVel.Name = "FlyVelocity"
            flyBodyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBodyVel.Parent = root

            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.Name = "FlyGyro"
            flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBodyGyro.Parent = root
        end

        local camera = workspace.CurrentCamera
        local direction = Vector3.new(0,0,0)
        
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction = direction + camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction = direction - camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction = direction - camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction = direction + camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction = direction + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then direction = direction - Vector3.new(0, 1, 0) end

        flyBodyVel.Velocity = direction * Features.FlyValue
        flyBodyGyro.CFrame = camera.CFrame
        hum.PlatformStand = true
    else
        if flyBodyVel then flyBodyVel:Destroy() flyBodyVel = nil end
        if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
        if hum.PlatformStand then hum.PlatformStand = false end
    end
end)

-- ────────────────────────────────────────────────
--  الحلقة القتالية المعدلة: الأقرب + تحديد أسود + حماية الحسابات
-- ────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait()
        local char = LocalPlayer.Character
        local myRoot = char and char:FindFirstChild("HumanoidRootPart")
        
        if not myRoot then 
            ClearHighlight()
            continue 
        end
        
        if Features.AutoBlock then pcall(function() BlockRF:InvokeServer(true) end) end
        
        if Features.KillAura then
            local closestPlayer = nil
            local shortestDistance = Features.AttackRange

            for _, p in ipairs(Players:GetPlayers()) do
                if p == LocalPlayer or IsWhitelisted(p) then continue end
                
                local c = p.Character
                if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChild("Humanoid") and c.Humanoid.Health > 0 then
                    local dist = (c.HumanoidRootPart.Position - myRoot.Position).Magnitude
                    if dist < shortestDistance then
                        shortestDistance = dist
                        closestPlayer = p
                    end
                end
            end

            if closestPlayer and closestPlayer.Character then
                local targetChar = closestPlayer.Character
                local targetHum = targetChar:FindFirstChild("Humanoid")
                
                if AuraHighlight.Adornee ~= targetChar then
                    AuraHighlight.Adornee = targetChar
                    AuraHighlight.Parent = targetChar
                end

                if targetHum then
                    task.spawn(function() 
                        pcall(HitRF.InvokeServer, HitRF, targetHum, myRoot.Position) 
                    end)
                    if Features.KillAuraAnims then 
                        task.spawn(PlayKillAuraAnim) 
                    end
                end
            else
                ClearHighlight()
            end
        else
            ClearHighlight()
        end
    end
end)

-- ────────────────────────────────────────────────
--  إنشاء الـ Smart GUI مع إصلاح مسار الظهور
-- ────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MasterSuiteGui"
ScreenGui.ResetOnSpawn = false

local CoreGui = game:GetService("CoreGui")
local old = CoreGui:FindFirstChild("MasterSuiteGui")
if old then old:Destroy() end
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
MainFrame.Size = UDim2.new(0, 260, 0, 480)
MainFrame.Active = true; MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
local FrameStroke = Instance.new("UIStroke", MainFrame)
FrameStroke.Thickness = 2

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
Title.Text = "⚡ MASTER HACK SUITE v4 ⚡"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 14
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 8)

local ContentFrame = Instance.new("ScrollingFrame", MainFrame)
ContentFrame.Size = UDim2.new(1, 0, 1, -35)
ContentFrame.Position = UDim2.new(0, 0, 0, 35)
ContentFrame.BackgroundTransparency = 1
ContentFrame.BorderSizePixel = 0
ContentFrame.ScrollBarThickness = 3
ContentFrame.CanvasSize = UDim2.new(0, 0, 0, 680)
local UIListLayout = Instance.new("UIListLayout", ContentFrame)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 8)
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local toggleButtons = {}
local function CreateRow(featureName, displayName, hasValue)
    local row = Instance.new("Frame", ContentFrame)
    row.Size = UDim2.new(0, 240, 0, 35)
    row.BackgroundTransparency = 1

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0, 140, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    btn.Text = displayName .. " : OFF"
    btn.TextColor3 = Color3.fromRGB(200, 200, 200)
    btn.Font = Enum.Font.SourceSansSemibold
    btn.TextSize = 13
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    toggleButtons[featureName] = btn

    btn.MouseButton1Click:Connect(function()
        Features[featureName] = not Features[featureName]
        btn.BackgroundColor3 = Features[featureName] and Color3.fromRGB(255, 0, 80) or Color3.fromRGB(30, 30, 38)
        btn.Text = displayName .. (Features[featureName] and " : ON 🔥" or " : OFF")
        btn.TextColor3 = Features[featureName] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    end)

    local bindBox = Instance.new("TextBox", row)
    bindBox.Size = UDim2.new(0, 40, 1, 0)
    bindBox.Position = UDim2.new(0, 145, 0, 0)
    bindBox.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    bindBox.Text = Keybinds[featureName] or "None"
    bindBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    bindBox.Font = Enum.Font.SourceSansBold
    bindBox.TextSize = 13
    Instance.new("UICorner", bindBox).CornerRadius = UDim.new(0, 6)
    bindBox.FocusLost:Connect(function() Keybinds[featureName] = string.upper(bindBox.Text) end)

    if hasValue then
        local valBox = Instance.new("TextBox", row)
        valBox.Size = UDim2.new(0, 45, 1, 0)
        valBox.Position = UDim2.new(0, 190, 0, 0)
        valBox.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        valBox.Text = tostring(Features[hasValue])
        valBox.TextColor3 = Color3.fromRGB(0, 255, 150)
        valBox.Font = Enum.Font.SourceSansBold
        valBox.TextSize = 13
        Instance.new("UICorner", valBox).CornerRadius = UDim.new(0, 6)
        valBox.FocusLost:Connect(function() Features[hasValue] = tonumber(valBox.Text) or Features[hasValue] end)
    end
end
CreateRow("KillAura", "Kill Aura", "AttackRange")
CreateRow("AutoBlock", "Auto Block", nil)
CreateRow("SpeedEnabled", "Speed", "SpeedValue")
CreateRow("FlyEnabled", "Flight Mode", "FlyValue")

local WLFrame = Instance.new("Frame", ContentFrame)
WLFrame.Size = UDim2.new(0, 240, 0, 50)
WLFrame.BackgroundTransparency = 1
local WLLabel = Instance.new("TextLabel", WLFrame)
WLLabel.Size = UDim2.new(1, 0, 0, 18)
WLLabel.Text = "قائمة الأصدقاء البيضاء:"
WLLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
WLLabel.Font = Enum.Font.SourceSansBold
WLLabel.TextSize = 12
WLLabel.TextXAlignment = Enum.TextXAlignment.Left
local WLBox = Instance.new("TextBox", WLFrame)
WLBox.Size = UDim2.new(1, 0, 0, 28)
WLBox.Position = UDim2.new(0, 0, 0, 18)
WLBox.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
WLBox.PlaceholderText = "اسماء مفصولة بمسافة..."
WLBox.Text = Features.WhiteList
WLBox.TextColor3 = Color3.fromRGB(255, 255, 255)
WLBox.Font = Enum.Font.SourceSans
WLBox.TextSize = 12
Instance.new("UICorner", WLBox).CornerRadius = UDim.new(0, 6)
WLBox.FocusLost:Connect(function() Features.WhiteList = WLBox.Text end)

-- نقط الحفظ
local CPSectionLabel = Instance.new("TextLabel", ContentFrame)
CPSectionLabel.Size = UDim2.new(0, 240, 0, 20)
CPSectionLabel.Text = "── نقاط الحفظ الذكية (J, K, L) ──"
CPSectionLabel.TextColor3 = Color3.fromRGB(0, 150, 255)
CPSectionLabel.Font = Enum.Font.SourceSansBold
CPSectionLabel.TextSize = 12

local labels = {}
local function updateLabelText(name)
    local container = labels[name]
    if container then
        local btn = container:FindFirstChild("TextButton")
        if positions[name] then
            btn.Text = "نقطة [" .. name .. "]: جاهزة للـ TP ⚡"
            btn.TextColor3 = Color3.fromRGB(46, 204, 113)
        else
            btn.Text = "نقطة [" .. name .. "]: فارغة (اضغط للحفظ)"
            btn.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
    end
end

local function createSlotRow(name)
    local row = Instance.new("Frame", ContentFrame)
    row.Name = name
    row.Size = UDim2.new(0, 240, 0, 35)
    row.BackgroundTransparency = 1
    
    local mainBtn = Instance.new("TextButton", row)
    mainBtn.Size = UDim2.new(0, 185, 1, 0)
    mainBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    mainBtn.Font = Enum.Font.SourceSansSemibold
    mainBtn.TextSize = 13
    Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, 6)
    
    mainBtn.MouseButton1Click:Connect(function()
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            if positions[name] then
                root.CFrame = CFrame.new(positions[name] + Vector3.new(0, 3, 0))
            else
                positions[name] = root.Position
                saveToFile()
                updateLabelText(name)
            end
        end
    end)
    
    local resetBtn = Instance.new("TextButton", row)
    resetBtn.Size = UDim2.new(0, 50, 1, 0)
    resetBtn.Position = UDim2.new(0, 190, 0, 0)
    resetBtn.BackgroundColor3 = Color3.fromRGB(192, 57, 43)
    resetBtn.Text = "تغيير"
    resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetBtn.Font = Enum.Font.SourceSansBold
    resetBtn.TextSize = 12
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)
    
    resetBtn.MouseButton1Click:Connect(function()
        positions[name] = nil
        saveToFile()
        updateLabelText(name)
    end)
    
    labels[name] = row
    updateLabelText(name)
end

createSlotRow("J")
createSlotRow("K")
createSlotRow("L")

-- تعقب والتحكم باللاعبين
local TrackerLabel = Instance.new("TextLabel", ContentFrame)
TrackerLabel.Size = UDim2.new(0, 240, 0, 20)
TrackerLabel.Text = "── التحكم باللاعبين والمشاهدة ──"
TrackerLabel.TextColor3 = Color3.fromRGB(155, 89, 182)
TrackerLabel.Font = Enum.Font.SourceSansBold
TrackerLabel.TextSize = 12

local PlayerFrame = Instance.new("Frame", ContentFrame)
PlayerFrame.Size = UDim2.new(0, 240, 0, 75)
PlayerFrame.BackgroundTransparency = 1

local NameBox = Instance.new("TextBox", PlayerFrame)
NameBox.Size = UDim2.new(1, 0, 0, 30)
NameBox.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
NameBox.PlaceholderText = "اكتب اسم اللاعب هنا..."
NameBox.Text = ""
NameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
NameBox.Font = Enum.Font.SourceSans
NameBox.TextSize = 13
Instance.new("UICorner", NameBox).CornerRadius = UDim.new(0, 6)

local SpecBtn = Instance.new("TextButton", PlayerFrame)
SpecBtn.Size = UDim2.new(0, 115, 0, 35)
SpecBtn.Position = UDim2.new(0, 0, 0, 35)
SpecBtn.BackgroundColor3 = Color3.fromRGB(142, 68, 173)
SpecBtn.Text = "مشاهدة 👁"
SpecBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SpecBtn.Font = Enum.Font.SourceSansBold
SpecBtn.TextSize = 13
Instance.new("UICorner", SpecBtn).CornerRadius = UDim.new(0, 6)

local TeleportBtn = Instance.new("TextButton", PlayerFrame)
TeleportBtn.Size = UDim2.new(0, 115, 0, 35)
TeleportBtn.Position = UDim2.new(0, 125, 0, 35)
TeleportBtn.BackgroundColor3 = Color3.fromRGB(39, 174, 96)
TeleportBtn.Text = "انتقال إليه 🚀"
TeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportBtn.Font = Enum.Font.SourceSansBold
TeleportBtn.TextSize = 13
Instance.new("UICorner", TeleportBtn).CornerRadius = UDim.new(0, 6)

local spectating = false
SpecBtn.MouseButton1Click:Connect(function()
    local target = GetPlayerByName(NameBox.Text)
    if target and target ~= LocalPlayer then
        if not spectating then
            if target.Character and target.Character:FindFirstChild("Humanoid") then
                Camera.CameraSubject = target.Character.Humanoid
                SpecBtn.Text = "إلغاء ❌"
                SpecBtn.BackgroundColor3 = Color3.fromRGB(230, 126, 34)
                spectating = true
            end
        else
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                Camera.CameraSubject = LocalPlayer.Character.Humanoid
                SpecBtn.Text = "مشاهدة 👁"
                SpecBtn.BackgroundColor3 = Color3.fromRGB(142, 68, 173)
                spectating = false
            end
        end
    end
end)

TeleportBtn.MouseButton1Click:Connect(function()
    local target = GetPlayerByName(NameBox.Text)
    if target and target ~= LocalPlayer then
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if myRoot and targetRoot then
            myRoot.CFrame = targetRoot.CFrame + Vector3.new(0, 3, 0)
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local pressedKey = input.KeyCode.Name
    
    if input.KeyCode == Enum.KeyCode.LeftControl then
        MainFrame.Visible = not MainFrame.Visible
        return
    end
    
    for feat, bind in pairs(Keybinds) do
        if pressedKey == bind then
            Features[feat] = not Features[feat]
            local btn = toggleButtons[feat]
            if btn then
                btn.BackgroundColor3 = Features[feat] and Color3.fromRGB(255, 0, 80) or Color3.fromRGB(30, 30, 38)
                local displayName = feat == "KillAura" and "Kill Aura" or feat == "AutoBlock" and "Auto Block" or feat == "SpeedEnabled" and "Speed" or "Flight Mode"
                btn.Text = displayName .. (Features[feat] and " : ON 🔥" or " : OFF")
                btn.TextColor3 = Features[feat] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
            end
        end
    end
    
    if pressedKey == "J" or pressedKey == "K" or pressedKey == "L" then
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            if positions[pressedKey] then
                root.CFrame = CFrame.new(positions[pressedKey] + Vector3.new(0, 3, 0))
            else
                positions[pressedKey] = root.Position
                saveToFile()
                updateLabelText(pressedKey)
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    FrameStroke.Color = Color3.fromHSV((tick() * 0.15) % 1, 0.85, 1)
end)
