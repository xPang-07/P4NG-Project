-- ============================================
-- ตัวอย่างสคริปต์ Auto Farm สำหรับ Roblox Executor
-- คำเตือน: การใช้สคริปต์โกงผิดกฎ TOS ของ Roblox และอาจทำให้บัญชีถูกระงับ
-- ============================================

-- บริการที่จำเป็น
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- ฟังก์ชันป้องกันการถูกเตะออกDue to AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

-- ============================================
-- 1. ส่วนสร้าง GUI (หน้าจอควบคุม)[reference:2][reference:3]
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmGUI"
ScreenGui.ResetOnSpawn = false -- ไม่ให้ GUI หายเมื่อตัวละครเกิดใหม่
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 250, 0, 150)
MainFrame.Position = UDim2.new(0.5, -125, 0.5, -75)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true -- ลากหน้าต่างได้
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Title.Text = "⚡ Auto Farm Menu"
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Font = Enum.Font.GothamBold
Title.TextScaled = true
Title.Parent = MainFrame
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 10)

-- ตัวแปรสถานะการฟาร์ม
local isFarming = false

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0.9, 0, 0, 45)
ToggleButton.Position = UDim2.new(0.05, 0, 0.4, 0)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.Text = "▶ เริ่ม Auto Farm"
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.Font = Enum.Font.GothamSemibold
ToggleButton.TextScaled = true
ToggleButton.Parent = MainFrame
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 8)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 25)
StatusLabel.Position = UDim2.new(0.05, 0, 0.85, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "สถานะ: พร้อมทำงาน"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextScaled = true
StatusLabel.Parent = MainFrame

-- ============================================
-- 2. ฟังก์ชัน Auto Farm (ส่วนที่ต้องปรับแต่งตามเกม)
-- ============================================
local function startFarming()
    while isFarming do
        task.wait(0.5) -- หน่วงเวลาเล็กน้อยเพื่อไม่ให้ Executor ทำงานหนักเกินไป[reference:4]

        -- ---------------------------------------------------------
        -- [จุดที่ต้องแก้ไข] ส่วนนี้คือหัวใจของการฟาร์ม
        -- คุณต้องค้นหาว่าเกมเป้าหมายใช้ RemoteEvent อะไรในการเก็บของ/โจมตี
        -- ตัวอย่าง: สมมติว่ามี RemoteEvent ชื่อ "CollectReward" ใน ReplicatedStorage
        -- ---------------------------------------------------------
        local success, err = pcall(function()
            -- ตัวอย่างการยิง RemoteEvent (ต้องแก้ชื่อและพารามิเตอร์ให้ตรงกับเกมจริง)
            -- local remote = ReplicatedStorage:FindFirstChild("CollectReward")
            -- if remote then
            --     remote:FireServer()
            -- end
            
            -- ตัวอย่างการโจมตี NPC ที่ใกล้ที่สุด (ต้องมีฟังก์ชันหา NPC)
            -- for _, obj in pairs(workspace:GetChildren()) do
            --     if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj.Humanoid.Health > 0 then
            --         -- ทำการโจมตี
            --         break
            --     end
            -- end
            
            print("[Auto Farm] กำลังทำงาน...")
        end)

        if not success then
            warn("[Auto Farm] เกิดข้อผิดพลาด: " .. tostring(err))
        end

        -- อัปเดตสถานะบน GUI
        StatusLabel.Text = "สถานะ: กำลังฟาร์ม..."
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    end
end

-- ============================================
-- 3. การเชื่อมต่อปุ่มกดกับฟังก์ชัน
-- ============================================
ToggleButton.MouseButton1Click:Connect(function()
    isFarming = not isFarming

    if isFarming then
        ToggleButton.Text = "⏹ หยุด Auto Farm"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
        task.spawn(startFarming) -- เริ่มลูปการฟาร์มใน Background
    else
        ToggleButton.Text = "▶ เริ่ม Auto Farm"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "สถานะ: หยุดทำงาน"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

print("[Auto Farm] โหลดสคริปต์สำเร็จ!")
