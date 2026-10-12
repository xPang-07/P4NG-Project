--[[
  P4NG api.lua — ตัวรายงานสถานะของ P4NG Launcher (รันในเกมผ่าน executor)

  ทำอะไร
    • POST /               heartbeat ทุก 15 วิ (บอก launcher ว่าเข้าเกมแล้ว / ยังอยู่) + retry
    • POST /api/disconnect  เมื่อโดนเตะ/หลุด/ขึ้นหน้า error (จับ 3 ทาง + กรอง false positive)
    • POST /api/desc        ข้อความสถานะสั้น ๆ (ถ้าตั้ง getgenv().P4NG_DESC)
    • GET  /api/script      ดึง Auto-Exec script จาก launcher มารัน (ถ้าเปิดไว้)

  ตัวเลือก (ตั้งก่อนรันไฟล์นี้ ผ่าน getgenv())
    P4NG_LOWGFX = false   ปิดโหมดลดภาระเครื่อง (ค่าเริ่มต้นเปิด: กราฟิกต่ำสุด + ปิดเสียง)
    P4NG_FPS    = 15      จำกัด FPS (ต้องมี setfpscap) — ไม่ตั้ง = ไม่ยุ่ง

  ต้องการ executor ที่มี: request / http_request / syn.request  และ loadstring
  คุยกับ 127.0.0.1 เท่านั้น (พอร์ต 3030–3032 ตาม core/heartbeat.py) — ไม่ส่งข้อมูลออกเน็ต
  วางไฟล์นี้ในโฟลเดอร์ autoexec ของ executor ตัวเดียวใช้ได้ทุกบัญชี
]]

if getgenv and getgenv().__P4NG_API then return end
if getgenv then getgenv().__P4NG_API = true end

local PORTS         = { 3030, 3031, 3032 }
local BEAT_INTERVAL = 15      -- วิ (launcher ถือว่าเงียบถ้าเกิน ~30 วิ)
local HTTP_TIMEOUT  = 5
local BEAT_RETRIES  = 3       -- ลองซ้ำต่อรอบ heartbeat
local BEAT_RETRY_WAIT = 0.5
local POLL_INTERVAL = 3       -- เช็ก GetErrorCode สำรอง (วิ)

-- error code ที่ไม่ใช่การหลุดจริง (กัน false positive)
local IGNORED_CODES = {
    [285] = true,
    [768] = true, [769] = true, [770] = true, [771] = true,
    [772] = true, [773] = true, [774] = true, [775] = true,
}
-- ข้อความที่ไม่ใช่การหลุดจริง
local IGNORED_MESSAGES = {
    DisconnectClientInitiated = true,
}
-- ข้อความปุ่ม/ขยะใน prompt ที่ไม่เอามาเป็น reason
local PROMPT_SKIP = { ["OK"] = true, ["Leave"] = true, ["Rejoin"] = true, ["Reconnect"] = true }

if not game:IsLoaded() then game.Loaded:Wait() end

local Players     = game:GetService("Players")
local GuiService  = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local http = (syn and syn.request) or (http and http.request) or http_request or request
    or (fluxus and fluxus.request)
if not http then
    warn("[P4NG] executor นี้ไม่มี request/http_request — api.lua ทำงานไม่ได้")
    return
end

local player = Players.LocalPlayer
while not player do task.wait(0.2); player = Players.LocalPlayer end

local base -- http://127.0.0.1:PORT

local function call(method, path, body)
    local ok, res = pcall(http, {
        Url = base .. path,
        Method = method,
        Headers = { ["Content-Type"] = "application/json" },
        Body = body and HttpService:JSONEncode(body) or nil,
        Timeout = HTTP_TIMEOUT,
    })
    if not ok or type(res) ~= "table" then return nil end
    local code = res.StatusCode or res.status_code
    if code and code ~= 200 then return nil end
    local okj, data = pcall(HttpService.JSONDecode, HttpService, res.Body or "")
    return okj and data or nil
end

local function findPort()
    for _, p in ipairs(PORTS) do
        base = "http://127.0.0.1:" .. p
        local r = call("GET", "/")
        if r and r.service == "P4NG" then return true end
    end
    base = nil
    return false
end

local function identity()
    return {
        username = player.Name,
        userId   = player.UserId,
        placeId  = game.PlaceId,
        jobId    = game.JobId,
        gameId   = game.GameId,
    }
end

local function post(path, extra)
    if not base and not findPort() then return end
    local body = identity()
    for k, v in pairs(extra or {}) do body[k] = v end
    local r = call("POST", path, body)
    if not r then            -- launcher อาจเปลี่ยนพอร์ต/เพิ่งเปิดใหม่ → หาใหม่รอบหน้า
        base = nil
    end
    return r
end

-- ── ลดภาระเครื่อง (เปิดเป็นค่าเริ่มต้น ปิดด้วย P4NG_LOWGFX = false) ──
if not (getgenv and getgenv().P4NG_LOWGFX == false) then
    pcall(function()
        local gs = UserSettings():GetService("UserGameSettings")
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        gs.GraphicsQualityLevel = 1
        gs.MasterVolume = 0
    end)
end
pcall(function()
    local fps = getgenv and getgenv().P4NG_FPS
    if type(fps) == "number" and setfpscap then setfpscap(fps) end
end)

-- ── disconnect / kick ───────────────────────────────────────────
local dropped   = false   -- ส่งรายงานแล้ว (หยุด heartbeat)
local pending   = false   -- กำลังรอรวบรวม reason
local kickMsg   = nil     -- ข้อความจาก ErrorMessageChanged
local promptMsg = nil     -- ข้อความจาก ErrorPrompt (แม่นกว่า)
local dropCode  = nil

local function getCode()
    local ok, v = pcall(function() return GuiService:GetErrorCode().Value end)
    return ok and v or nil
end

-- ขีดเส้น "หลุดจริง": code >= DisconnectErrors และไม่อยู่ใน ignore list
local disconnectBase
pcall(function() disconnectBase = Enum.ConnectionError.DisconnectErrors.Value end)

local function shouldIgnore(code, msg)
    if code and IGNORED_CODES[code] then return true end
    if msg and IGNORED_MESSAGES[msg] then return true end
    return false
end

local function isDisconnectCode(code)
    return code ~= nil and disconnectBase ~= nil
        and code >= disconnectBase and not IGNORED_CODES[code]
end

local function buildReason()
    if promptMsg and promptMsg ~= "" then return promptMsg end
    if kickMsg and kickMsg ~= "" then return kickMsg end
    return "Unknown"
end

-- รอสั้น ๆ ให้ prompt โผล่มา จะได้ reason ที่ครบ แล้วส่งครั้งเดียว
local function reportDrop(code)
    if dropped or pending then return end
    pending = true
    dropCode = code or dropCode
    task.spawn(function()
        task.wait(0.4)
        dropped = true
        post("/api/disconnect", { reason = buildReason(), error_code = dropCode })
    end)
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function extractPromptText(root)
    local seen, out = {}, {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible then
            local t = d.Text
            if t and t ~= "" and not PROMPT_SKIP[t] then
                t = trim(t)
                if t ~= "" and not seen[t] then
                    seen[t] = true
                    table.insert(out, t)
                end
            end
        end
    end
    return table.concat(out, " - ")
end

-- ทาง 1: ErrorMessageChanged
pcall(function()
    GuiService.ErrorMessageChanged:Connect(function()
        local msg = GuiService:GetErrorMessage()
        if not msg or msg == "" then return end
        local code = getCode()
        if shouldIgnore(code, msg) then return end
        kickMsg = msg
        reportDrop(code)
    end)
end)

-- ทาง 2: ดัก ErrorPrompt ใน CoreGui (ดึงข้อความจริงที่ผู้เล่นเห็น)
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    CoreGui.DescendantAdded:Connect(function(obj)
        if dropped or not obj.Name:find("ErrorPrompt") then return end
        task.wait(0.25)
        local code = getCode()
        if shouldIgnore(code, nil) then return end
        local ok, text = pcall(extractPromptText, obj)
        if not ok or not text or text == "" then return end
        promptMsg = text
        reportDrop(code)
    end)
end)

-- ทาง 3: poll GetErrorCode เป็นตัวสำรอง (เผื่อสองทางบนพลาด)
task.spawn(function()
    while not dropped and not pending do
        task.wait(POLL_INTERVAL)
        local code = getCode()
        if isDisconnectCode(code) then
            reportDrop(code)
            break
        end
    end
end)

-- ── auto-exec (ดึง script จาก launcher ครั้งเดียวต่อการเข้าเกม) ──
task.spawn(function()
    if not findPort() then
        for _ = 1, 20 do          -- launcher อาจยังไม่พร้อม — ลองต่อ ~1 นาที
            task.wait(3)
            if findPort() then break end
        end
    end
    if not base then return end

    local r = call("GET", "/api/script?uid=" .. tostring(player.UserId))
    local src = r and r.script
    if type(src) ~= "string" or src:match("^%s*$") then return end

    task.wait(tonumber(r.delay) or 2)
    local fn, err = loadstring(src)
    if not fn then
        warn("[P4NG] script คอมไพล์ไม่ผ่าน: " .. tostring(err))
        return
    end
    local ok, e = pcall(fn)
    if not ok then warn("[P4NG] script error: " .. tostring(e)) end
end)

-- ── desc (ตั้งใน script ของคุณ: getgenv().P4NG_DESC = "ข้อความ") ──
local lastDesc
task.spawn(function()
    while task.wait(5) do
        local d = getgenv and getgenv().P4NG_DESC
        if type(d) == "string" and d ~= lastDesc then
            lastDesc = d
            post("/api/desc", { desc = d })
        end
    end
end)

-- ── heartbeat (retry ในแต่ละรอบ; post() จะหาพอร์ตใหม่เองถ้าพลาด) ──
task.spawn(function()
    task.wait(math.random() * 3)              -- กระจายจังหวะ ไม่ให้หลายบัญชียิงพร้อมกัน
    while not dropped and not pending do
        for i = 1, BEAT_RETRIES do
            if post("/") then break end
            if i < BEAT_RETRIES then task.wait(BEAT_RETRY_WAIT) end
        end
        task.wait(BEAT_INTERVAL + math.random())
    end
end)
