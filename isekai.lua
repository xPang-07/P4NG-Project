-- ============================================
-- Auto Farm & Utility Script (Orion UI Edition)
-- รองรับ: Orion Library / Multi-Tab / Speed / Noclip / Anti-AFK / Rejoin
-- ============================================

local OrionLib = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Orion/main/source'))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ลบ GUI เก่าออกก่อนเมื่อรันซ้ำ (Clean Re-run)
if getgenv().AutoFarmScriptLoaded then
    OrionLib:Destroy()
    task.wait(0.3)
end
getgenv().AutoFarmScriptLoaded = true

-- ตัวแปร Global กำหนดสถานะ
getgenv().AutoFarm = false
getgenv().FarmDelay = 0.5
getgenv().Noclip = false
getgenv().InfJump = false
getgenv().CustomSpeed = 16
getgenv().EnableSpeed = false

-- ============================================
-- 1) ระบบป้องกัน AFK Kick (Anti-AFK)
-- ============================================
if not getgenv().AntiAFKConnected then
    getgenv().AntiAFKConnected = true
    LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end

-- ============================================
-- 2) สร้าง หน้าต่างหลัก (GUI Window)
-- ============================================
local Window = OrionLib:MakeWindow({
    Name = "⚡ Auto Farm Hub",
    HidePremium = false,
    SaveConfig = false,
    ConfigFolder = "AutoFarmHub",
    IntroText = "Auto Farm Hub"
})

-- --------------------------------------------
-- TAB 1: Auto Farm (ระบบฟาร์ม)
-- --------------------------------------------
local FarmTab = Window:MakeTab({
    Name = "Auto Farm",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

FarmTab:AddSection({ Name = "ตั้งค่าการฟาร์มอัตโนมัติ" })

FarmTab:AddToggle({
    Name = "เปิดใช้งาน Auto Farm",
    Default = false,
    Callback = function(Value)
        getgenv().AutoFarm = Value
        if Value then
            task.spawn(function()
                while getgenv().AutoFarm do
                    local success, err = pcall(function()
                        -- ====================================================
                        -- 🔴 [ตำแหน่งใส่ LOGIC ฟาร์มของเกม]
                        --
                        -- ตัวอย่างที่ 1: ยิง RemoteEvent เพื่อตีมอน / เก็บของ
                        -- local remote = game:GetService("ReplicatedStorage"):FindFirstChild("AttackRemote")
                        -- if remote then remote:FireServer() end
                        --
                        -- ตัวอย่างที่ 2: วาร์ปตัวละครไปหาพิกัดเป้าหมาย
                        -- if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        --     LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(0, 50, 0)
                        -- end
                        -- ====================================================

                        print("[Auto Farm] Loop กำลังทำงาน...")
                    end)

                    if not success then
                        warn("[Auto Farm Error]: " .. tostring(err))
                    end

                    task.wait(getgenv().FarmDelay)
                end
            end)
        end
    end
})

FarmTab:AddSlider({
    Name = "หน่วงเวลา Loop (วินาที)",
    Min = 0.1,
    Max = 3.0,
    Default = 0.5,
    Color = Color3.fromRGB(0, 255, 150),
    Increment = 0.1,
    ValueName = "วิ",
    Callback = function(Value)
        getgenv().FarmDelay = Value
    end
})

-- --------------------------------------------
-- TAB 2: Player Mods (ปรับแต่งตัวละคร)
-- --------------------------------------------
local PlayerTab = Window:MakeTab({
    Name = "ตัวละคร (Player)",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

PlayerTab:AddSection({ Name = "ความเร็ว และการเคลื่อนที่" })

PlayerTab:AddToggle({
    Name = "เปิดใช้งานปรับความเร็ว (WalkSpeed)",
    Default = false,
    Callback = function(Value)
        getgenv().EnableSpeed = Value
    end
})

PlayerTab:AddSlider({
    Name = "กำหนดความเร็ว",
    Min = 16,
    Max = 300,
    Default = 16,
    Color = Color3.fromRGB(255, 200, 0),
    Increment = 1,
    ValueName = "Speed",
    Callback = function(Value)
        getgenv().CustomSpeed = Value
    end
})

PlayerTab:AddToggle({
    Name = "เดินทะลุกำแพง (Noclip)",
    Default = false,
    Callback = function(Value)
        getgenv().Noclip = Value
    end
})

PlayerTab:AddToggle({
    Name = "กระโดดได้ไม่จำกัด (Infinite Jump)",
    Default = false,
    Callback = function(Value)
        getgenv().InfJump = Value
    end
})

-- --------------------------------------------
-- TAB 3: Utilities & Server (เครื่องมือเสริม)
-- --------------------------------------------
local UtilTab = Window:MakeTab({
    Name = "เครื่องมือเสริม",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

UtilTab:AddSection({ Name = "จัดการเซิร์ฟเวอร์ & GUI" })

UtilTab:AddButton({
    Name = "เข้าห้องเดิมใหม่ (Rejoin Server)",
    Callback = function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
})

UtilTab:AddButton({
    Name = "ปิดสคริปต์และลบ GUI (Unload)",
    Callback = function()
        getgenv().AutoFarm = false
        getgenv().Noclip = false
        getgenv().InfJump = false
        getgenv().EnableSpeed = false
        getgenv().AutoFarmScriptLoaded = false
        OrionLib:Destroy()
    end
})

-- ============================================
-- 3) Background Event Handlers (Speed / Noclip / InfJump)
-- ============================================
RunService.Stepped:Connect(function()
    if LocalPlayer.Character then
        -- จัดการ WalkSpeed
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid and getgenv().EnableSpeed then
            humanoid.WalkSpeed = getgenv().CustomSpeed
        end

        -- จัดการ Noclip
        if getgenv().Noclip then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end
end)

-- จัดการ Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if getgenv().InfJump and LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:ChangeState("Jumping")
        end
    end
end)

OrionLib:Init()
