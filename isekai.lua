-- ============================================
-- Auto Farm Script (Re-runnable Version)
-- รองรับ: รันซ้ำได้ / Loop อัตโนมัติ / ไม่มี GUI ซ้ำ
-- ============================================

-- ✅ 1) ลบ GUI เก่าทิ้งก่อน (ถ้ามี) เพื่อป้องกันการซ้ำ
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ล้าง GUI เก่า + หยุด Loop เก่า (ถ้ามี)
if getgenv().AutoFarmRunning then
    getgenv().AutoFarmRunning = false
    task.wait(0.2)
end

local oldGui = PlayerGui:FindFirstChild("AutoFarmGUI")
if oldGui then
    oldGui:Destroy()
end

-- เก็บสถานะไว้ใน getgenv() เพื่อให้เข้าถึงได้จากทุกที่
getgenv().AutoFarmRunning = false

-- ✅ 2) ป้องกัน AFK Kick
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

-- ============================================
-- 3) สร้าง GUI
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 250, 0, 180)
MainFrame.Position = UDim2.new(0.5, -125, 0.5, -90)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Title.Text = "⚡ Auto Farm (Loop)"
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Font = Enum.Font.GothamBold
Title.TextScaled = true
Title.Parent = MainFrame
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 10)

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0.9, 0, 0, 45)
ToggleButton.Position = UDim2.new(0.05, 0, 0.28, 0)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.Text = "▶ เริ่ม Auto Farm"
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.Font = Enum.Font.GothamSemibold
ToggleButton.TextScaled = true
ToggleButton.Parent = MainFrame
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 8)

-- ปุ่มตั้งค่าความเร็ว Loop
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(0.9, 0, 0, 20)
SpeedLabel.Position = UDim2.new(0.05, 0, 0.55, 0)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "หน่วงเวลา Loop: 0.5 วินาที"
SpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SpeedLabel.Font = Enum.Font.Gotham
SpeedLabel.TextScaled = true
SpeedLabel.Parent = MainFrame

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(0.5, 0, 0, 25)
SpeedBox.Position = UDim2.new(0.25, 0, 0.7, 0)
SpeedBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
SpeedBox.Text = "0.5"
SpeedBox.TextColor3 = Color3.new(1, 1, 1)
SpeedBox.Font = Enum.Font.Gotham
SpeedBox.TextScaled = true
SpeedBox.Parent = MainFrame
Instance.new("UICorner", SpeedBox).CornerRadius = UDim.new(0, 6)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 20)
StatusLabel.Position = UDim2.new(0.05, 0, 0.88, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "สถานะ: พร้อมทำงาน"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextScaled = true
StatusLabel.Parent = MainFrame

-- ============================================
-- 4) ฟังก์ชัน Auto Farm (Loop หลัก)
-- ============================================
local function runFarmLoop()
    local loopId = tick() -- ✅ ใช้ ID ระบุรอบ เพื่อป้องกัน loop ผีจากรอบเก่า

    while getgenv().AutoFarmRunning and getgenv().AutoFarmLoopId == loopId do
        -- อ่านค่าหน่วงเวลาจากช่องกรอก
        local delay = tonumber(SpeedBox.Text) or 0.5
        if delay < 0.1 then delay = 0.1 end

        -- ----------------------------------------------------
        -- [จุดแก้ไข] ใส่ logic ฟาร์มของคุณตรงนี้
        -- ตัวอย่าง:
        -- local remote = ReplicatedStorage:FindFirstChild("CollectReward")
        -- if remote then remote:FireServer() end
        -- ----------------------------------------------------
        local success, err = pcall(function()
            print("[Auto Farm] Loop ทำงาน (ID: " .. tostring(loopId) .. ")")
        end)

        if not success then
            warn("[Auto Farm] Error: " .. tostring(err))
        end

        StatusLabel.Text = "สถานะ: กำลังฟาร์ม..."
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)

        task.wait(delay) -- ✅ ใช้ task.wait() เพื่อให้ Executor ยังตอบสนองได้
    end

    print("[Auto Farm] Loop (ID: " .. tostring(loopId) .. ") หยุดแล้ว")
end

-- ============================================
-- 5) ปุ่มเปิด/ปิด พร้อมระบบ Re-run
-- ============================================
ToggleButton.MouseButton1Click:Connect(function()
    if not getgenv().AutoFarmRunning then
        -- ✅ เริ่ม Loop ใหม่ (สร้าง ID ใหม่ทุกครั้ง)
        getgenv().AutoFarmRunning = true
        getgenv().AutoFarmLoopId = tick()

        ToggleButton.Text = "⏹ หยุด Auto Farm"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
        task.spawn(runFarmLoop)
    else
        -- ✅ หยุด Loop (loop จะออกจาก while เองเมื่อเจอเงื่อนไข false)
        getgenv().AutoFarmRunning = false

        ToggleButton.Text = "▶ เริ่ม Auto Farm"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "สถานะ: หยุดทำงาน"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

-- อัปเดตข้อความ label เมื่อแก้ตัวเลข
SpeedBox.FocusLost:Connect(function()
    local v = tonumber(SpeedBox.Text)
    if v and v >= 0.1 then
        SpeedLabel.Text = "หน่วงเวลา Loop: " .. v .. " วินาที"
    else
        SpeedBox.Text = "0.5"
        SpeedLabel.Text = "หน่วงเวลา Loop: 0.5 วินาที"
    end
end)

print("[Auto Farm] โหลดสคริปต์สำเร็จ! กดปุ่มเพื่อเริ่ม/หยุดได้เลย")
