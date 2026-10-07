-- ═══════════════════════════════════════════════════════════════
--  P4NG Launcher · api.lua v2.0
--  รวม: ต้นฉบับ (ตรวจจับหลุดสมบูรณ์) + ของผม (port discovery, userId, desc)
-- ═══════════════════════════════════════════════════════════════

-- ── ป้องกัน double-inject ─────────────────────────────────────
if _G.P4NG and _G.P4NG._initialized then return _G.P4NG end

local Players    = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local CoreGui    = game:GetService("CoreGui")

-- รอ LocalPlayer
repeat task.wait() until game:IsLoaded()
local lp = Players.LocalPlayer
repeat task.wait() until lp

local P4NG = {
    _initialized = true,
    VERSION      = "2.0",
    PORTS        = { 3030, 3031, 3032 },
    INTERVAL     = 10,
    MAX_RETRIES  = 3,
    RETRY_DELAY  = 0.5,
    DEBUG        = false,

    -- ★ จากต้นฉบับ: error code ที่ไม่ใช่การหลุดจริง
    IGNORED_ERRORS = {
        [285] = true,   -- DisconnectClientInitiated
        [768] = true, [769] = true, [770] = true,
        [771] = true, [772] = true, [773] = true,
        [774] = true, [775] = true,
    },
    IGNORED_MESSAGES = {
        DisconnectClientInitiated = true,
    },

    -- ── state ──
    Running       = true,
    KickMessage   = "",
    PromptReason  = nil,
    DisconnectCode = nil,
    Notified      = false,
    ActivePort    = nil,
}
_G.P4NG = P4NG

-- ── logger ────────────────────────────────────────────────────
local function log(fmt, ...)
    if P4NG.DEBUG then
        print(("[P4NG] " .. fmt):format(...))
    end
end

-- ── HTTP function ─────────────────────────────────────────────
local httpFn = request or http_request
    or (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)

if not httpFn then
    return warn("[P4NG] executor ไม่รองรับ HTTP")
end

-- ── Port discovery (ของผม — กันพอร์ตชน) ─────────────────────
local function ping(port)
    local ok, res = pcall(httpFn, {
        Url    = ("http://127.0.0.1:%d/"):format(port),
        Method = "GET",
    })
    if not ok or not res then return false end
    local code = res.StatusCode or res.Status or res.status
    return tonumber(code) == 200
end

local function getPort()
    if P4NG.ActivePort and ping(P4NG.ActivePort) then
        return P4NG.ActivePort
    end
    for _, p in ipairs(P4NG.PORTS) do
        if ping(p) then
            P4NG.ActivePort = p
            return p
        end
    end
    P4NG.ActivePort = nil
    return nil
end

-- ── ส่ง + retry (ของต้นฉบับ) ────────────────────────────────
local function post(path, body)
    local payload = HttpService:JSONEncode(body)
    for attempt = 1, P4NG.MAX_RETRIES do
        local port = getPort()
        if port then
            local ok, res = pcall(httpFn, {
                Url     = ("http://127.0.0.1:%d%s"):format(port, path),
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = payload,
            })
            if ok and res then
                local code = res.StatusCode or res.Status or res.status
                if tonumber(code) == 200 then return true end
            end
        end
        if attempt < P4NG.MAX_RETRIES then
            task.wait(P4NG.RETRY_DELAY)
        end
    end
    return false
end

-- ── heartbeat ─────────────────────────────────────────────────
local function beat()
    return post("/", {
        username = lp.Name,
        userId   = lp.UserId,        -- ★ ของผม
        placeId  = game.PlaceId,
        jobId    = game.JobId,
        gameId   = game.GameId,
    })
end
P4NG.beat = beat

-- ── Public API ────────────────────────────────────────────────
function P4NG.desc(text)
    post("/api/desc", {
        username = lp.Name,
        userId   = lp.UserId,
        desc     = tostring(text or ""):sub(1, 160),
    })
end

function P4NG.drop(reason, code)
    post("/api/disconnect", {
        username   = lp.Name,
        userId     = lp.UserId,
        reason     = tostring(reason or "unknown"):sub(1, 160),
        error_code = code,
    })
end

-- ── helpers (ของต้นฉบับ) ──────────────────────────────────────
local function isIgnored(code, msg)
    if code and P4NG.IGNORED_ERRORS[code] then return true end
    if msg and P4NG.IGNORED_MESSAGES[msg] then return true end
    return false
end

local function extractPromptText(prompt)
    local texts = {}
    for _, d in ipairs(prompt:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible then
            local t = d.Text
            if t and t ~= "" and t ~= "OK" and t ~= "Leave" and t ~= "Rejoin" then
                table.insert(texts, t)
            end
        end
    end
    -- dedupe
    local seen, out = {}, {}
    for _, t in ipairs(texts) do
        local s = t:gsub("^%s+", ""):gsub("%s+$", "")
        if s ~= "" and not seen[s] then
            seen[s] = true
            table.insert(out, s)
        end
    end
    return table.concat(out, " - ")
end

local function buildReason()
    if P4NG.PromptReason and P4NG.PromptReason ~= "" then
        return P4NG.PromptReason
    end
    if P4NG.KickMessage and P4NG.KickMessage ~= "" then
        return P4NG.KickMessage
    end
    return "Unknown"
end

local function notifyDisconnect()
    if P4NG.Notified then return end
    P4NG.Notified = true
    post("/api/disconnect", {
        username   = lp.Name,
        userId     = lp.UserId,
        reason     = buildReason(),
        error_code = P4NG.DisconnectCode,
    })
    task.wait(0.4)
end

-- ── ตรวจจับการหลุด ───────────────────────────────────────────

-- 1. Error code จาก GuiService
local function checkErrorCode()
    local code = GuiService:GetErrorCode().Value
    if code >= Enum.ConnectionError.DisconnectErrors.Value
       and not P4NG.IGNORED_ERRORS[code] then
        P4NG.DisconnectCode = code
        P4NG.Running = false
        return true
    end
    return false
end

-- 2. ErrorMessageChanged (kick message จาก server)
GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" then
        local code = GuiService:GetErrorCode().Value
        if isIgnored(code, msg) then return end
        P4NG.KickMessage = msg
        P4NG.DisconnectCode = code
        P4NG.Running = false
        notifyDisconnect()
    end
end)

-- 3. ErrorPrompt UI ใน CoreGui
CoreGui.DescendantAdded:Connect(function(inst)
    if not inst.Name:find("ErrorPrompt") then return end
    task.wait(0.25)
    local code = GuiService:GetErrorCode().Value
    if isIgnored(code, nil) then return end
    local ok, text = pcall(extractPromptText, inst)
    if not ok or text == "" or text == nil then return end
    P4NG.PromptReason = text
    P4NG.DisconnectCode = code
    P4NG.Running = false
    notifyDisconnect()
end)

-- 4. PlayerRemoving / AncestryChanged (ของผม — จับ graceful leave)
Players.PlayerRemoving:Connect(function(p)
    if p == lp then
        P4NG.Running = false
        P4NG.drop("PlayerRemoving")
    end
end)

lp.AncestryChanged:Connect(function(_, parent)
    if not parent then
        P4NG.Running = false
        P4NG.drop("AncestryChanged")
    end
end)

-- ── Auto-optimize (ของต้นฉบับ) ────────────────────────────────
pcall(function()
    local UserGameSettings = UserSettings():GetService("UserGameSettings")
    UserGameSettings.Rendering.QualityLevel = Enum.QualityLevel.Level01
    UserGameSettings.GraphicsQualityLevel = 1
    UserGameSettings.MasterVolume = 0
    log("optimize graphics: done")
end)

-- ── Main loop ────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.5)
    beat()

    while P4NG.Running do
        task.wait(P4NG.INTERVAL)
        if checkErrorCode() then break end
        beat()
    end

    if P4NG.DisconnectCode then
        notifyDisconnect()
    end
end)

log("พร้อมทำงาน v%s · port=%s · interval=%ds",
    P4NG.VERSION, tostring(P4NG.ActivePort or "?"), P4NG.INTERVAL)

return P4NG
