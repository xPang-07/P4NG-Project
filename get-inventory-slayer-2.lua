-- ═══════════════════════════════════════════════════════════════
--   SLAYER 2 — INVENTORY → WEB (Auto-update v5)
--   • กด M ครั้งเดียว — หลังจากนั้นอัปเดตอัตโนมัติ
--   • Auto-refresh: กด M ใหม่ถ้า cache ว่าง
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    -- ─────────────────────────────────────────
    -- ตั้งค่า
    -- ─────────────────────────────────────────
    local WEB          = "http://localhost:3000"
    local URL          = WEB .. "/api/inventory"
    local SEND_INTERVAL = 5      -- ส่งขึ้นเว็บทุก 5 วิ
    local UI_POLL       = 1.5    -- poll UI ทุก 1.5 วิ
    local DEBUG         = false

    local HttpService = game:GetService("HttpService")
    local Players     = game:GetService("Players")
    local VIM         = game:GetService("VirtualInputManager")
    local lp          = Players.LocalPlayer

    repeat task.wait() until game:IsLoaded()
    repeat task.wait() until lp

    local syn = _G.syn or _G.http
    local req = request or http_request
             or (syn and syn.request)
             or (_G.http and _G.http.request)
    if not req then return warn("❌ Executor ไม่รองรับ HTTP") end

    -- ─────────────────────────────────────────
    -- Helpers
    -- ─────────────────────────────────────────
    local function safeGet(t, k)
        local ok, v = pcall(rawget, t, k); if ok then return v end
    end
    local function isTable(v) return type(v) == "table" end
    local function count(t) local c=0; for _ in pairs(t) do c+=1 end; return c end

    -- ─────────────────────────────────────────
    -- กด M
    -- ─────────────────────────────────────────
    local function pressM()
        pcall(function()
            VIM:SendKeyEvent(true, Enum.KeyCode.M, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, Enum.KeyCode.M, false, game)
        end)
        if keypress   then pcall(keypress,   0x4D) end
        if keyrelease then pcall(keyrelease, 0x4D) end
    end

    -- ─────────────────────────────────────────
    -- หา UI holder
    -- ─────────────────────────────────────────
    local function findHolder()
        local pg = lp:FindFirstChild("PlayerGui"); if not pg then return end
        local h  = pg:FindFirstChild("ComponentsHolder"); if not h then return end
        local ah = h
        for _, p in ipairs({"Background","Frame","CharactersMain","CharHolder","ActualHolder"}) do
            if not ah then return end
            ah = ah:FindFirstChild(p)
        end
        return ah, h
    end

    -- ─────────────────────────────────────────
    -- ซ่อน UI (ไม่ให้ user เห็น)
    -- ─────────────────────────────────────────
    local function hideUI(holder)
        local bg = holder:FindFirstChild("Background")
        if bg and bg:IsA("GuiObject") then
            bg.Visible = false
        end
    end

    local function showUI(holder)
        local bg = holder:FindFirstChild("Background")
        if bg and bg:IsA("GuiObject") then
            bg.Visible = true
        end
    end

    -- ─────────────────────────────────────────
    -- หา Item DB
    -- ─────────────────────────────────────────
    local function findDB()
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" then
                local ok, valid = pcall(function()
                    local c, m = 0, 0
                    for k, item in pairs(v) do
                        c += 1
                        if c > 500 then break end
                        if type(k) == "string" and isTable(item) then
                            if safeGet(item,"Rarity")
                               and safeGet(item,"Icon")
                               and safeGet(item,"Category") then
                                m += 1
                                if m >= 50 then return true end
                            end
                        end
                    end
                    return false
                end)
                if ok and valid then return v end
            end
        end
    end

    -- ─────────────────────────────────────────
    -- อ่าน UI
    -- ─────────────────────────────────────────
    local dbByName = {}

    local function readFrame(frame)
        if not frame:IsA("Frame") then return nil end
        local name = frame.Name
        if not name or name == "" then return nil end

        local amount = 1

        -- ลอง path แบบตรงก่อน
        local amtObj = frame:FindFirstChild("Amount")
        if amtObj then
            local txt
            if amtObj:IsA("TextLabel") then txt = amtObj.Text
            elseif amtObj:IsA("IntValue") or amtObj:IsA("NumberValue") then txt = tostring(amtObj.Value)
            end
            if txt then
                local n = tonumber(txt) or tonumber(tostring(txt):match("%d+"))
                if n then amount = n end
            end
        end

        -- fallback: หา TextLabel ตัวแรกที่ text เป็นตัวเลขล้วน
        if amount == 1 then
            for _, d in ipairs(frame:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local n = tonumber(d.Text) or tonumber((d.Text or ""):match("^%s*(%d+)%s*$"))
                    if n then amount = n; break end
                end
            end
        end

        return name, amount
    end

    local cache = {}

    local function refreshCache()
        local ah = findHolder(); if not ah then return end
        local new = {}
        for _, frame in ipairs(ah:GetChildren()) do
            local name, amount = readFrame(frame)
            if name then
                local info = dbByName[name] or {}
                new[name] = {
                    Name     = name,
                    Amount   = amount,
                    ItemId   = safeGet(info, "Id"),
                    Rarity   = safeGet(info, "Rarity"),
                    Icon     = safeGet(info, "Icon"),
                    Category = safeGet(info, "Category"),
                }
            end
        end
        cache = new
    end

    -- ─────────────────────────────────────────
    -- Setup DB
    -- ─────────────────────────────────────────
    local DB = findDB()
    if not DB then return warn("❌ ไม่เจอ Item DB") end
    for id, item in pairs(DB) do
        if type(id) == "string" and isTable(item) then
            dbByName[id] = item
        end
    end
    print(("✅ เจอ DB: %d items"):format(count(dbByName)))

    -- ─────────────────────────────────────────
    -- กด M ครั้งแรก + ซ่อน UI
    -- ─────────────────────────────────────────
    print("🎯 กด M เปิดกระเป๋าครั้งแรก...")
    pressM()
    task.wait(0.8)

    local ah, holder = findHolder()
    if not ah then return warn("❌ ไม่เจอ UI holder — ลองใหม่") end

    refreshCache()
    print(("✅ อ่านครั้งแรกได้ %d items"):format(count(cache)))

    hideUI(holder)
    print("🙈 ซ่อน UI เรียบร้อย — จะอัปเดตอัตโนมัติจากนี้")

    -- ─────────────────────────────────────────
    -- Hook: ตรวจจับการเพิ่ม/ลบ item
    -- ─────────────────────────────────────────
    ah.ChildAdded:Connect(function()
        task.wait(0.15)
        refreshCache()
    end)
    ah.ChildRemoved:Connect(function()
        task.wait(0.15)
        refreshCache()
    end)

    -- ─────────────────────────────────────────
    -- Getter
    -- ─────────────────────────────────────────
    local function getMyInventory()
        local r = {}
        for _, item in pairs(cache) do r[#r+1] = item end
        return r
    end
    getgenv().getMyInventory = getMyInventory

    -- ─────────────────────────────────────────
    -- ส่งขึ้นเว็บ
    -- ─────────────────────────────────────────
    local function send()
        local list = getMyInventory()
        if #list == 0 then return end

        local out = {}
        for _, it in ipairs(list) do
            local icon = it.Icon
            if type(icon) == "string" then
                icon = icon:match("(%d+)") or icon
            end
            out[#out+1] = {
                Name     = it.Name,
                Amount   = it.Amount,
                Rarity   = it.Rarity,
                Category = it.Category,
                Icon     = icon,
                ItemId   = it.ItemId,
            }
        end

        local payload = HttpService:JSONEncode({
            game      = tostring(game.PlaceId),
            player    = lp.Name,
            userId    = lp.UserId,
            timestamp = os.time(),
            items     = out,
        })

        local ok, res = pcall(req, {
            Url     = URL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = payload,
        })

        if ok and res then
            local code = res.StatusCode or res.Status or res.status or "?"
            if tostring(code) == "200" then
                print(("[SEND] %s | ✅ %d items")
                    :format(os.date("%H:%M:%S"), #out))
            end
        end
    end

    send()

    -- ─────────────────────────────────────────
    -- Loop 1: Poll UI ทุก 1.5 วิ
    -- ─────────────────────────────────────────
    task.spawn(function()
        while task.wait(UI_POLL) do
            refreshCache()
        end
    end)

    -- ─────────────────────────────────────────
    -- Loop 2: ส่งขึ้นเว็บทุก 5 วิ
    -- ─────────────────────────────────────────
    task.spawn(function()
        while task.wait(SEND_INTERVAL) do
            send()
        end
    end)

    -- ─────────────────────────────────────────
    -- Watchdog: กด M ใหม่ถ้า cache ว่างเกิน 10 วิ
    -- ─────────────────────────────────────────
    task.spawn(function()
        local emptyRounds = 0
        while task.wait(2) do
            if count(cache) == 0 then
                emptyRounds += 1
                if emptyRounds >= 5 then
                    print("♻️ cache ว่าง — กด M ใหม่...")
                    pressM()
                    task.wait(0.6)
                    refreshCache()
                    if holder then hideUI(holder) end
                    emptyRounds = 0
                end
            else
                emptyRounds = 0
            end
        end
    end)

    print("✅ พร้อม! กด M แค่ครั้งเดียว — ระบบอัปเดตเองหลังจากนี้")
end)
