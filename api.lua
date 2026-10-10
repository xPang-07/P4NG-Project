--[[
  P4NG api.lua — ตัวรายงานสถานะของ P4NG Launcher (รันในเกมผ่าน executor)

  ทำอะไร
    • POST /               heartbeat ทุก 15 วิ (บอก launcher ว่าเข้าเกมแล้ว / ยังอยู่)
    • POST /api/disconnect  เมื่อโดนเตะ/หลุด/ขึ้นหน้า error
    • POST /api/desc        ข้อความสถานะสั้น ๆ (ถ้าตั้ง getgenv().P4NG_DESC)
    • GET  /api/script      ดึง Auto-Exec script จาก launcher มารัน (ถ้าเปิดไว้)

  ต้องการ executor ที่มี: request / http_request / syn.request  และ loadstring
  คุยกับ 127.0.0.1 เท่านั้น (พอร์ต 3030–3032 ตาม core/heartbeat.py) — ไม่ส่งข้อมูลออกเน็ต
  วางไฟล์นี้ในโฟลเดอร์ autoexec ของ executor ตัวเดียวใช้ได้ทุกบัญชี
]]

if getgenv and getgenv().__P4NG_API then return end
if getgenv then getgenv().__P4NG_API = true end

local PORTS         = { 3030, 3031, 3032 }
local BEAT_INTERVAL = 15      -- วิ (launcher ถือว่าเงียบถ้าเกิน ~30 วิ)
local HTTP_TIMEOUT  = 5

if not game:IsLoaded() then game.Loaded:Wait() end

local Players    = game:GetService("Players")
local GuiService = game:GetService("GuiService")
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

-- ── disconnect / kick ───────────────────────────────────────────
local dropped = false
local function reportDrop(reason, code)
    if dropped then return end
    dropped = true
    post("/api/disconnect", { reason = tostring(reason or "Unknown"), error_code = code })
end

pcall(function()
    GuiService.ErrorMessageChanged:Connect(function()
        local msg = GuiService:GetErrorMessage()
        if msg and msg ~= "" then
            local okc, code = pcall(function() return GuiService:GetErrorType().Value end)
            reportDrop(msg, okc and code or nil)
        end
    end)
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

-- ── heartbeat ──────────────────────────────────────────────────
task.spawn(function()
    task.wait(math.random() * 3)              -- กระจายจังหวะ ไม่ให้หลายบัญชียิงพร้อมกัน
    while not dropped do
        post("/")
        task.wait(BEAT_INTERVAL + math.random())
    end
end)
