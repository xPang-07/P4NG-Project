--[[
  P4NG api.lua  (v1.2)
  รันในเกมผ่าน executor (autoexec) → รายงานสถานะบัญชีให้แอป P4NG Launcher
    POST  /               เข้าเกมแล้ว {username, userId, placeId, jobId, gameId}   ส่งครั้งเดียวต่อรอบ
    POST  /api/disconnect หลุด        {username, userId, reason, error_code}
    POST  /api/desc       ข้อความในตาราง (ไม่บังคับ) {username, userId, desc}
        → สคริปต์ฟาร์มของคุณเรียก  getgenv().P4NG_SetDesc("Level: 225 // Spin: 4,500")  เมื่อค่าเปลี่ยน

  ★ v1.2: Auto Exec — ตอบกลับ POST / อาจมี {"script": "..."} (แอปส่งให้เมื่อ token ตรง) → รันครั้งเดียวต่อเซิร์ฟเวอร์
  ★ v1.1 (FIX #8):  retry แบบ exponential backoff ไม่จำกัดจำนวนครั้ง (จนกว่าแอปจะรับ)
  ★ v1.1 (FIX #11): กรองปุ่มหลายภาษา (ไทย/อังกฤษ) ก่อนดึงข้อความจาก ErrorPrompt
]]

repeat task.wait() until game:IsLoaded()

-- กันรันซ้อน (เช่นวางไฟล์ไว้ใน autoexec 2 ที่) — เฉพาะ server เดียวกัน
pcall(function()
    local env = getgenv and getgenv()
    if env then
        if env.__P4NG_JOB == game.JobId and game.JobId ~= "" then
            env.__P4NG_DUP = true
        end
        env.__P4NG_JOB = game.JobId
    end
end)
if getgenv and getgenv().__P4NG_DUP then
    getgenv().__P4NG_DUP = nil
    return
end

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService  = game:GetService("GuiService")
local CoreGui     = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
repeat task.wait() until LocalPlayer
LocalPlayer = Players.LocalPlayer

local API = {
    Config = {
        Host       = "http://localhost",
        Token      = "fbde813bc71bdbf7c172d911ca164072",   -- แอปเติมให้ตอนกดติดตั้ง · ห้ามแก้เอง (ต้องกดติดตั้งใหม่ถ้าต้องการ Auto Exec)
        Ports      = { 3030, 3031, 3032 },
        Interval   = 10,
        RetryDelay = 0.5,
        JoinDelay  = 3,
        MaxRetry   = 200,    -- เพดานกัน infinite loop (200 ครั้ง × เฉลี่ย ~15 วิ = 50 นาที)
    },

    State = {
        Running          = true,
        KickMessage      = "",
        PromptReason     = nil,
        DisconnectReason = nil,
        DisconnectCode   = nil,
        Notified         = false,
        BaseUrl          = nil,
    },

    IgnoredErrors = {
        [285] = true, [768] = true, [769] = true, [770] = true, [771] = true,
        [772] = true, [773] = true, [774] = true, [775] = true,
    },
    IgnoredMessages = { DisconnectClientInitiated = true },

    -- ★ FIX #11: กรองปุ่มทุกภาษา
    SkipTexts = {
        OK = true, Leave = true, Rejoin = true,
        ["ตกลง"] = true, ["ออก"] = true, ["กลับเข้าเกม"] = true, ["ปิด"] = true,
        ["ออกจากเกม"] = true, ["เชื่อมต่อใหม่"] = true,
    },

    Request        = request or http_request or (http and http.request),
    DisconnectBase = Enum.ConnectionError.DisconnectErrors.Value,
    Payload        = nil,
}

API.Payload = HttpService:JSONEncode({
    username = LocalPlayer.Name,
    userId   = LocalPlayer.UserId,
    placeId  = game.PlaceId,
    jobId    = game.JobId,
    gameId   = game.GameId,
})

if not API.Request then
    warn("[P4NG] executor นี้ไม่มี request/http_request — ส่งสถานะให้แอปไม่ได้")
    return
end

----------------------------------------------------------------- helpers

function API:IsDisconnect(code)
    return code >= self.DisconnectBase and not self.IgnoredErrors[code]
end

function API:ShouldIgnore(code, message)
    if code and self.IgnoredErrors[code] then return true end
    if message and self.IgnoredMessages[message] then return true end
    return false
end

function API:Post(url, body)
    local ok, res = pcall(function()
        return self.Request({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json", ["X-P4NG-Token"] = self.Config.Token },
            Body    = body,
        })
    end)
    if ok and type(res) == "table" then return res end
    return nil
end

function API:IsOurs(res)
    return res ~= nil
        and res.StatusCode == 200
        and type(res.Body) == "string"
        and res.Body:find("P4NG", 1, true) ~= nil
end

function API:PostToApp(path, body)
    local st = self.State
    if st.BaseUrl then
        local res = self:Post(st.BaseUrl .. path, body)
        if self:IsOurs(res) then return true, res end
        st.BaseUrl = nil
    end
    for _, port in ipairs(self.Config.Ports) do
        local base = self.Config.Host .. ":" .. port
        local res = self:Post(base .. path, body)
        if self:IsOurs(res) then
            st.BaseUrl = base
            return true, res
        end
    end
    return false
end

-- ★ FIX #8: retry แบบ backoff ไม่จำกัด (มีเพดานกัน infinite)
function API:PostWithRetry(path, body, onOk)
    task.spawn(function()
        local delay = self.Config.RetryDelay
        local tries = 0
        while tries < self.Config.MaxRetry do
            local ok, res = self:PostToApp(path, body)
            if ok then
                if onOk then pcall(onOk, res) end
                return
            end
            tries = tries + 1
            task.wait(delay)
            delay = math.min(delay * 1.5, 10)
        end
        warn("[P4NG] ส่งไม่ได้หลังลอง " .. self.Config.MaxRetry .. " ครั้ง")
    end)
end

-- ★ v1.2: รันสคริปต์ที่แอปส่งกลับมา (Auto Exec) — ครั้งเดียวต่อเซิร์ฟเวอร์
function API:RunRemote(res)
    local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok or type(data) ~= "table" then return end
    local src = data.script
    if type(src) ~= "string" or src == "" then return end

    local env = getgenv and getgenv()
    if env then
        if env.__P4NG_EXEC == game.JobId and game.JobId ~= "" then return end
        env.__P4NG_EXEC = game.JobId
    end
    if not loadstring then
        warn("[P4NG] executor นี้ไม่มี loadstring — รัน Auto Exec ไม่ได้")
        return
    end
    local fn, err = loadstring(src, "=P4NG_autoexec")
    if not fn then
        warn("[P4NG] Auto Exec compile error: " .. tostring(err))
        return
    end
    task.spawn(function()
        local ok2, e2 = pcall(fn)
        if not ok2 then warn("[P4NG] Auto Exec error: " .. tostring(e2)) end
    end)
end

function API:NotifyJoin()
    self:PostWithRetry("", self.Payload, function(res) self:RunRemote(res) end)
end

----------------------------------------------------------------- disconnect

function API:ExtractPromptText(prompt)
    local seen, parts = {}, {}
    for _, obj in ipairs(prompt:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            local text = obj.Text
            if text and text ~= "" and not self.SkipTexts[text] then
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if text ~= "" and not seen[text] then
                    seen[text] = true
                    table.insert(parts, text)
                end
            end
        end
    end
    return table.concat(parts, " - ")
end

function API:BuildReason()
    local st = self.State
    if st.PromptReason and st.PromptReason ~= "" then return st.PromptReason end
    if st.KickMessage and st.KickMessage ~= "" then return st.KickMessage end
    return "Unknown"
end

function API:NotifyDisconnect()
    local st = self.State
    if st.Notified then return end
    st.Notified = true

    local body = HttpService:JSONEncode({
        username   = LocalPlayer.Name,
        userId     = LocalPlayer.UserId,
        reason     = self:BuildReason(),
        error_code = st.DisconnectCode,
    })
    self:PostWithRetry("/api/disconnect", body)
end

function API:SetDesc(text)
    local body = HttpService:JSONEncode({
        username = LocalPlayer.Name,
        userId   = LocalPlayer.UserId,
        desc     = tostring(text or ""),
    })
    return self:PostToApp("/api/desc", body)
end

function API:CheckError()
    local code = GuiService:GetErrorCode().Value
    if self:IsDisconnect(code) then
        self.State.DisconnectCode   = code
        self.State.DisconnectReason = "Disconnect error"
        self.State.Running          = false
        return true
    end
    return false
end

function API:MonitorPrompts()
    CoreGui.DescendantAdded:Connect(function(obj)
        if not obj.Name:find("ErrorPrompt") then return end
        task.wait(0.25)

        local code = GuiService:GetErrorCode().Value
        if self:ShouldIgnore(code, nil) then return end

        local ok, text = pcall(function() return self:ExtractPromptText(obj) end)
        if not ok or text == nil or text == "" then return end

        self.State.PromptReason   = text
        self.State.DisconnectCode = code
        self.State.Running        = false
        self:NotifyDisconnect()
    end)
end

----------------------------------------------------------------- misc

function API:ApplyOptimizations()
    pcall(function()
        local gs = UserSettings():GetService("UserGameSettings")
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        gs.GraphicsQualityLevel = 1
        gs.MasterVolume = 0
    end)
end

function API:Init()
    GuiService.ErrorMessageChanged:Connect(function(message)
        if message and message ~= "" then
            local code = GuiService:GetErrorCode().Value
            if self:ShouldIgnore(code, message) then return end
            self.State.KickMessage    = message
            self.State.DisconnectCode = code
            self.State.Running        = false
            self:NotifyDisconnect()
        end
    end)

    self:ApplyOptimizations()
    self:MonitorPrompts()
    pcall(function()
        if getgenv then
            getgenv().P4NG_SetDesc = function(t) return self:SetDesc(t) end
        end
    end)

    task.wait(0.5)
    self:NotifyJoin()

    while self.State.Running do
        task.wait(self.Config.Interval)
        if self:CheckError() then break end
    end

    if self.State.DisconnectCode then
        self:NotifyDisconnect()
    end
end

API:Init()
