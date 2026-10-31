-- ============================================
-- Auto Farm System (Mode Selection + Auto Attack/Skills)
-- UI: Orion Library
-- ============================================

local OrionLib = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Orion/main/source'))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ล้าง GUI เก่ากรณีรันซ้ำ
if getgenv().AutoFarmLoaded then
    OrionLib:Destroy()
    task.wait(0.3)
end
getgenv().AutoFarmLoaded = true

-- ============================================
-- ตัวแปรระบบ (Settings & Status)
-- ============================================
getgenv().SelectedMode = "Story"
getgenv().SelectedStage = "Stage 1"
getgenv().SelectedDifficulty = "Normal"

getgenv().AutoFarm = false
getgenv().AutoSkills = true
getgenv().AutoClick = true
getgenv().FarmDistance = 3 -- ระยะห่างตอนวาร์ปไปอยู่หลังมอนสเตอร์

-- ============================================
-- ฟังก์ชันช่วยเหลือ (Helper Functions)
-- ============================================

-- 1. ฟังก์ชันค้นหามอนสเตอร์ที่ใกล้ที่สุด
local function getClosestMonster()
    local closest = nil
    local shortestDistance = math.huge
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end

    -- 🔴 [ปรับแก้ไข] เปลี่ยนชื่อโฟลเดอร์มอนสเตอร์ตามเกมที่เล่น เช่น workspace.Enemies หรือ workspace.Monsters
    local monsterFolder = workspace:FindFirstChild("Enemies") or workspace:FindFirstChild("Monsters") or workspace

    for _, obj in pairs(monsterFolder:GetChildren()) do
        local hum = obj:FindFirstChildOfClass("Humanoid")
        local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("PrimaryPart")

        if hum and hrp and hum.Health > 0 and obj ~= char then
            local distance = (char.HumanoidRootPart.Position - hrp.Position).Magnitude
            if distance < shortestDistance then
                closest = obj
                shortestDistance = distance
            end
        end
    end
    return closest
end

-- 2. ฟังก์ชันจำลองการกดปุ่มสกิล (Key Pressing)
local function pressKey(keyCode)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

-- 3. ฟังก์ชันจำลองการคลิกโจมตี
local function doAutoClick()
    VirtualUser:Button1Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(0.05)
    VirtualUser:Button1Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end

-- ============================================
-- สร้างหน้าต่าง GUI (Orion Window)
-- ============================================
local Window = OrionLib:MakeWindow({
    Name = "⚔️ Auto Farm System",
    HidePremium = false,
    SaveConfig = false,
    IntroText = "Auto Farm Loading..."
})

-- --------------------------------------------
-- TAB 1: เลือกด่าน & เข้าเกม (Stage Select)
-- --------------------------------------------
local SelectTab = Window:MakeTab({
    Name = "เลือกด่าน (Stage)",
    Icon = "rbxassetid://4483345998"
})

SelectTab:AddSection({ Name = "1. ตั้งค่าการเข้าด่าน" })

SelectTab:AddDropdown({
    Name = "เลือกโหมด (Mode)",
    Default = "Story",
    Options = {"Story", "Infinite", "Raid", "Dungeon"},
    Callback = function(Value)
        getgenv().SelectedMode = Value
    end
})

SelectTab:AddDropdown({
    Name = "เลือกด่าน (Stage)",
    Default = "Stage 1",
    Options = {"Stage 1", "Stage 2", "Stage 3", "Stage 4", "Stage 5"},
    Callback = function(Value)
        getgenv().SelectedStage = Value
    end
})

SelectTab:AddDropdown({
    Name = "เลือกความยาก (Difficulty)",
    Default = "Normal",
    Options = {"Easy", "Normal", "Hard", "Nightmare"},
    Callback = function(Value)
        getgenv().SelectedDifficulty = Value
    end
})

SelectTab:AddButton({
    Name = "🚀 เริ่มต้น/เข้าด่าน (Start Game)",
    Callback = function()
        OrionLib:MakeNotification({
            Name = "ระบบส่งเข้าด่าน",
            Content = "กำลังเข้าด่าน: " .. getgenv().SelectedStage .. " (" .. getgenv().SelectedDifficulty .. ")",
            Time = 3
        })

        -- 🔴 [ปรับแก้ไข] ใส่ RemoteEvent สำหรับกดเข้าด่านของเกมนั้นๆ
        -- ตัวอย่าง:
        -- local joinRemote = ReplicatedStorage:FindFirstChild("JoinStageRemote")
        -- if joinRemote then
        --     joinRemote:FireServer(getgenv().SelectedMode, getgenv().SelectedStage, getgenv().SelectedDifficulty)
        -- end
    end
})

-- --------------------------------------------
-- TAB 2: ระบบฟาร์มอัตโนมัติ (Auto Farm)
-- --------------------------------------------
local FarmTab = Window:MakeTab({
    Name = "Auto Farm",
    Icon = "rbxassetid://4483345998"
})

FarmTab:AddSection({ Name = "2. เปิดใช้งาน Auto Farm & Skills" })

FarmTab:AddToggle({
    Name = "⚡ เปิดใช้งาน Auto Farm (วาร์ปไปหา มอนสเตอร์)",
    Default = false,
    Callback = function(Value)
        getgenv().AutoFarm = Value
        
        if Value then
            task.spawn(function()
                while getgenv().AutoFarm do
                    local monster = getClosestMonster()
                    local char = LocalPlayer.Character
                    
                    if monster and char and char:FindFirstChild("HumanoidRootPart") then
                        local monsterHrp = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("PrimaryPart")
                        if monsterHrp then
                            -- บังคับวาร์ปตัวละครไปอยู่ด้านหลังมอนสเตอร์
                            char.HumanoidRootPart.CFrame = monsterHrp.CFrame * CFrame.new(0, 0, getgenv().FarmDistance)
                        end
                    end
                    task.wait(0.05)
                end
            end)
        end
    end
})

FarmTab:AddToggle({
    Name = "🗡️ Auto Click (โจมตีปกติ)",
    Default = true,
    Callback = function(Value)
        getgenv().AutoClick = Value
    end
})

FarmTab:AddToggle({
    Name = "🔥 Auto Skill (Z, X, C, V, G)",
    Default = true,
    Callback = function(Value)
        getgenv().AutoSkills = Value
    end
})

FarmTab:AddSlider({
    Name = "ระยะห่างจากมอนสเตอร์ (Distance)",
    Min = 1,
    Max = 10,
    Default = 3,
    Color = Color3.fromRGB(0, 255, 150),
    Increment = 1,
    ValueName = "Studs",
    Callback = function(Value)
        getgenv().FarmDistance = Value
    end
})

-- ============================================
-- 3) Loop การกด Auto Click และ Auto Skill
-- ============================================

-- Loop Auto Click
task.spawn(function()
    while true do
        if getgenv().AutoFarm and getgenv().AutoClick then
            local monster = getClosestMonster()
            if monster then
                doAutoClick()
            end
        end
        task.wait(0.1)
    end
end)

-- Loop Auto Skill Rotation (Z -> X -> C -> V -> G)
task.spawn(function()
    local skillKeys = {
        Enum.KeyCode.Z,
        Enum.KeyCode.X,
        Enum.KeyCode.C,
        Enum.KeyCode.V,
        Enum.KeyCode.G
    }

    while true do
        if getgenv().AutoFarm and getgenv().AutoSkills then
            local monster = getClosestMonster()
            if monster then
                for _, key in ipairs(skillKeys) do
                    if not getgenv().AutoFarm or not getgenv().AutoSkills then break end
                    pressKey(key)
                    task.wait(0.2) -- หน่วงเวลาเล็กน้อยระหว่างกดแต่ละสกิล
                end
            end
        end
        task.wait(0.5)
    end
end)

OrionLib:Init()
