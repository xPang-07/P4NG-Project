-- ============================================================
-- Auto Farm Script — Full Flow (Dropdown → Load → Farm)
-- ============================================================

-- ============ ⚙️ CONFIG (ปรับตามเกมของคุณ) ============
local CONFIG = {
    -- สกิลและคูลดาวน์ (วินาที)
    Skills = {
        { key = Enum.KeyCode.Z, cooldown = 3 },
        { key = Enum.KeyCode.X, cooldown = 5 },
        { key = Enum.KeyCode.C, cooldown = 8 },
        { key = Enum.KeyCode.V, cooldown = 12 },
        { key = Enum.KeyCode.G, cooldown = 30 }, -- อันติ
    },
    ClickInterval = 0.2,       -- กดคลิกทุกกี่วินาที
    AttackRange   = 12,        -- ระยะที่ถือว่า "ถึงตัวมอน" แล้ว
    LoopInterval  = 0.1,       -- หน่วง loop หลัก
    MonsterFolders = { "Monsters", "Enemies", "Mobs", "Units", "Dummies" }, -- ชื่อโฟลเดอร์มอน
}

-- ============ 🔧 SERVICES / UTILS ============
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ล้าง GUI เก่า + หยุด loop เก่า
if getgenv().AF_Farming then getgenv().AF_Farming = false; task.wait(0.2) end
local oldGui = PlayerGui:FindFirstChild("AutoFarmGUI")
if oldGui then oldGui:Destroy() end
getgenv().AF_Farming = false

-- ป้องกัน AFK
LocalPlayer.Idled:Connect(function()
    VIM:SendMouseButtonEvent(0,0,0,true,game,0); task.wait(0.5)
    VIM:SendMouseButtonEvent(0,0,0,false,game,0)
end)

-- ---------- Utility ----------
local function getCharacter()
    local c = LocalPlayer.Character
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if hum and hrp and hum.Health > 0 then return c, hum, hrp end
end

local function findNearestMonster()
    local _, _, myHRP = getCharacter()
    if not myHRP then return nil, math.huge end

    local roots = {}
    for _, name in ipairs(CONFIG.MonsterFolders) do
        local f = workspace:FindFirstChild(name)
        if f then table.insert(roots, f) end
    end
    if #roots == 0 then roots = { workspace } end

    local nearest, nearestDist = nil, math.huge
    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("Model") then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                if hum and hum.Health > 0 and hrp then
                    local d = (hrp.Position - myHRP.Position).Magnitude
                    if d < nearestDist then nearest, nearestDist = obj, d end
                end
            end
        end
    end
    return nearest, nearestDist
end

local function sendClick()
    VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.03)
    VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

local function sendKey(keyCode)
    VIM:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VIM:SendKeyEvent(false, keyCode, false, game)
end

-- ============ 🎨 UI HELPERS ============
local function createFrame(parent, pos, size, color)
    local f = Instance.new("Frame")
    f.Position, f.Size = pos, size
    f.BackgroundColor3 = color or Color3.fromRGB(45,45,50)
    f.BorderSizePixel = 0
    f.Parent = parent
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,6)
    return f
end

local function createButton(parent, text, pos, size, color)
    local b = Instance.new("TextButton")
    b.Position, b.Size = pos, size
    b.BackgroundColor3 = color or Color3.fromRGB(0,150,80)
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamSemibold
    b.TextScaled = true
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    return b
end

-- Dropdown แบบ custom
local function createDropdown(parent, label, options, default, y)
    local holder = createFrame(parent, UDim2.new(0,0,0,y), UDim2.new(1,0,0,32), Color3.fromRGB(55,55,60))
    holder.ZIndex = 2

    local txt = Instance.new("TextLabel")
    txt.Size, txt.BackgroundTransparency = UDim2.new(1,-35,1,0), 1
    txt.Position = UDim2.new(0,10,0,0)
    txt.Text = label .. ": " .. tostring(default)
    txt.TextColor3, txt.Font = Color3.new(1,1,1), Enum.Font.Gotham
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.TextScaled = true
    txt.ZIndex = 3
    txt.Parent = holder

    local arrow = Instance.new("TextLabel")
    arrow.Size, arrow.Position = UDim2.new(0,30,1,0), UDim2.new(1,-30,0,0)
    arrow.Text, arrow.BackgroundTransparency = "▼", 1
    arrow.TextColor3, arrow.Font = Color3.new(1,1,1), Enum.Font.Gotham
    arrow.ZIndex = 3
    arrow.Parent = holder

    local list = createFrame(holder, UDim2.new(0,0,1,0), UDim2.new(1,0,0,#options*26), Color3.fromRGB(35,35,40))
    list.Visible = false
    list.ZIndex = 20

    local current = default
    for i, opt in ipairs(options) do
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1,0,0,26)
        item.Position = UDim2.new(0,0,0,(i-1)*26)
        item.BackgroundColor3 = Color3.fromRGB(35,35,40)
        item.BackgroundTransparency = 1
        item.Text = tostring(opt)
        item.TextColor3, item.Font = Color3.new(1,1,1), Enum.Font.Gotham
        item.TextScaled = true
        item.ZIndex = 21
        item.Parent = list
        item.MouseEnter:Connect(function() item.BackgroundTransparency = 0.3 end)
        item.MouseLeave:Connect(function() item.BackgroundTransparency = 1 end)
        item.MouseButton1Click:Connect(function()
            current = opt
            txt.Text = label .. ": " .. tostring(opt)
            list.Visible = false
        end)
    end

    holder.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            list.Visible = not list.Visible
        end
    end)

    return { get = function() return current end }
end

-- ============ 🖼️ MAIN GUI ============
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

local Main = createFrame(ScreenGui, UDim2.new(0,20,0,20), UDim2.new(0,300,0,0), Color3.fromRGB(28,28,32))
Main.Size = UDim2.new(0, 300, 0, 420)
Main.Active = true
Main.Draggable = true

local title = Instance.new("TextLabel")
title.Size, title.BackgroundColor3 = UDim2.new(1,0,0,36), Color3.fromRGB(20,20,24)
title.Text, title.TextColor3 = "⚡ Auto Farm", Color3.fromRGB(0,255,150)
title.Font, title.TextScaled = Enum.Font.GothamBold, true
title.Parent = Main
Instance.new("UICorner", title).CornerRadius = UDim.new(0,6)

-- === หน้า 1: เลือกด่าน ===
local PageSelect = Instance.new("Frame")
PageSelect.Size = UDim2.new(1,0,1,-36)
PageSelect.Position = UDim2.new(0,0,0,36)
PageSelect.BackgroundTransparency = 1
PageSelect.Parent = Main

local ddMode     = createDropdown(PageSelect, "โหมด",     {"Story","Raid","Event","Boss"}, "Story", 10)
local ddStage    = createDropdown(PageSelect, "ด่าน",     {"Stage 1","Stage 2","Stage 3","Stage 4","Stage 5"}, "Stage 1", 50)
local ddDifficulty = createDropdown(PageSelect, "ความยาก", {"Easy","Normal","Hard","Nightmare"}, "Normal", 90)

local btnLoad = createButton(PageSelect, "📥 โหลดด่าน", UDim2.new(0,10,0,140), UDim2.new(1,-20,0,42), Color3.fromRGB(0,120,200))

local lblStatus = Instance.new("TextLabel")
lblStatus.Size = UDim2.new(1,-20,0,30)
lblStatus.Position = UDim2.new(0,10,0,190)
lblStatus.BackgroundTransparency = 1
lblStatus.Text = "สถานะ: เลือกด่านก่อน"
lblStatus.TextColor3, lblStatus.Font = Color3.fromRGB(200,200,200), Enum.Font.Gotham
lblStatus.TextScaled = true
lblStatus.Parent = PageSelect

-- === หน้า 2: Auto Farm (ซ่อนไว้ก่อน) ===
local PageFarm = Instance.new("Frame")
PageFarm.Size = UDim2.new(1,0,1,-36)
PageFarm.Position = UDim2.new(0,0,0,36)
PageFarm.BackgroundTransparency = 1
PageFarm.Visible = false
PageFarm.Parent = Main

local lblFarmInfo = Instance.new("TextLabel")
lblFarmInfo.Size = UDim2.new(1,-20,0,40)
lblFarmInfo.Position = UDim2.new(0,10,0,10)
lblFarmInfo.BackgroundTransparency = 1
lblFarmInfo.Text = "📍 กำลังเล่น: -"
lblFarmInfo.TextColor3, lblFarmInfo.Font = Color3.fromRGB(0,255,150), Enum.Font.GothamBold
lblFarmInfo.TextScaled = true
lblFarmInfo.Parent = PageFarm

local btnFarm = createButton(PageFarm, "▶ เริ่ม Auto Farm", UDim2.new(0,10,0,60), UDim2.new(1,-20,0,50), Color3.fromRGB(0,170,0))

local lblFarmStat = Instance.new("TextLabel")
lblFarmStat.Size = UDim2.new(1,-20,0,30)
lblFarmStat.Position = UDim2.new(0,10,0,120)
lblFarmStat.BackgroundTransparency = 1
lblFarmStat.Text = "สถานะ: พร้อม"
lblFarmStat.TextColor3, lblFarmStat.Font = Color3.fromRGB(200,200,200), Enum.Font.Gotham
lblFarmStat.TextScaled = true
lblFarmStat.Parent = PageFarm

local btnBack = createButton(PageFarm, "↩ กลับ", UDim2.new(0,10,0,360), UDim2.new(1,-20,0,32), Color3.fromRGB(80,80,90))

-- ============ 🚀 LOAD STAGE LOGIC ============
-- [⚠️ แก้ตรงนี้] ใส่ RemoteEvent ที่ใช้โหลดด่านของเกมคุณ
local function requestLoadStage(mode, stage, difficulty)
    -- ตัวอย่าง: สมมติว่ามี RemoteEvent ชื่อ "StartStage"
    -- local remote = ReplicatedStorage:FindFirstChild("StartStage")
    -- if remote then remote:FireServer(mode, stage, difficulty) end
    print(("[Load] mode=%s stage=%s diff=%s"):format(mode, stage, difficulty))
end

-- รอจนมอนโผล่ใน workspace = ถือว่าโหลดเสร็จ
local function waitForStageLoaded(timeout)
    local t = tick()
    while tick() - t < (timeout or 15) do
        if findNearestMonster() then return true end
        task.wait(0.5)
    end
    return false
end

-- ============ 🌾 AUTO FARM LOOP ============
local function startFarming()
    getgenv().AF_Farming = true
    local loopId = tick()
    getgenv().AF_LoopId = loopId

    local lastClick = 0
    local skillLastUsed = {}
    for i in ipairs(CONFIG.Skills) do skillLastUsed[i] = 0 end

    while getgenv().AF_Farming and getgenv().AF_LoopId == loopId do
        local character, humanoid, hrp = getCharacter()
        local monster, dist = findNearestMonster()

        if character and humanoid and monster then
            local targetHRP = monster:FindFirstChild("HumanoidRootPart") or monster.PrimaryPart
            if targetHRP then
                if dist > CONFIG.AttackRange then
                    -- เดินเข้าหา
                    humanoid:MoveTo(targetHRP.Position)
                    lblFarmStat.Text = "🏃 กำลังเข้าใกล้มอน ("..math.floor(dist)..")"
                else
                    -- อยู่ในระยะ → หยุด + ตี + สกิล
                    humanoid:MoveTo(hrp.Position)
                    lblFarmStat.Text = "⚔️ กำลังโจมตี"

                    -- Auto click
                    if tick() - lastClick >= CONFIG.ClickInterval then
                        sendClick()
                        lastClick = tick()
                    end

                    -- Auto skill (เช็คคูลดาวน์)
                    for i, s in ipairs(CONFIG.Skills) do
                        if tick() - skillLastUsed[i] >= s.cooldown then
                            sendKey(s.key)
                            skillLastUsed[i] = tick()
                        end
                    end
                end
            end
        else
            lblFarmStat.Text = "🔍 ไม่พบมอน..."
        end

        task.wait(CONFIG.LoopInterval)
    end
    print("[AutoFarm] loop stopped")
end

-- ============ 🔗 BUTTON CONNECTIONS ============
btnLoad.MouseButton1Click:Connect(function()
    btnLoad.Text = "⏳ กำลังโหลด..."
    btnLoad.BackgroundColor3 = Color3.fromRGB(150,100,0)
    lblStatus.Text = "สถานะ: กำลังโหลดด่าน..."

    requestLoadStage(ddMode.get(), ddStage.get(), ddDifficulty.get())

    task.spawn(function()
        local ok = waitForStageLoaded(20)
        if ok then
            lblStatus.Text = "✅ โหลดเสร็จ"
            PageSelect.Visible = false
            PageFarm.Visible = true
            lblFarmInfo.Text = "📍 "..ddMode.get().." • "..ddStage.get().." • "..ddDifficulty.get()
            btnLoad.Text = "📥 โหลดด่าน"
            btnLoad.BackgroundColor3 = Color3.fromRGB(0,120,200)
        else
            lblStatus.Text = "❌ โหลดไม่สำเร็จ (timeout)"
            btnLoad.Text = "📥 โหลดด่าน"
            btnLoad.BackgroundColor3 = Color3.fromRGB(0,120,200)
        end
    end)
end)

btnFarm.MouseButton1Click:Connect(function()
    if not getgenv().AF_Farming then
        btnFarm.Text = "⏹ หยุด Auto Farm"
        btnFarm.BackgroundColor3 = Color3.fromRGB(200,0,0)
        task.spawn(startFarming)
    else
        getgenv().AF_Farming = false
        btnFarm.Text = "▶ เริ่ม Auto Farm"
        btnFarm.BackgroundColor3 = Color3.fromRGB(0,170,0)
        lblFarmStat.Text = "สถานะ: หยุด"
    end
end)

btnBack.MouseButton1Click:Connect(function()
    getgenv().AF_Farming = false
    btnFarm.Text = "▶ เริ่ม Auto Farm"
    btnFarm.BackgroundColor3 = Color3.fromRGB(0,170,0)
    PageFarm.Visible = false
    PageSelect.Visible = true
end)

print("[Auto Farm] ✅ โหลดสคริปต์สำเร็จ")
