-- ═══════════════════════════════════════════════════════════════
--   SLAYERS 2 — INVENTORY → WEB (ALL-IN-ONE v4)
--   • สแกน GC หา Item DB + Inventory (auto)
--   • Auto-refind เมื่อกระเป๋าหลุด
--   • Auto-exec script จาก /api/script
--   • Heartbeat + ตรวจจับการหลุด
--   • ส่งข้อมูลขึ้นเว็บทุก 5 วิ
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    local WEB = "http://localhost:3000"
    local URL = WEB .. "/api/inventory"
    local SEND_INTERVAL = 5
    local DEBUG = false

    local HttpService = game:GetService("HttpService")
    local Players = game:GetService("Players")
    local GuiService = game:GetService("GuiService")
    local CoreGui = game:GetService("CoreGui")
    local lp = Players.LocalPlayer

    -- ── รอ LocalPlayer ──
    repeat task.wait() until game:IsLoaded()
    repeat task.wait() until lp

    -- ── HTTP function ──
    local syn = _G.syn or _G.http
    local req = request or http_request
             or (syn and syn.request)
             or (_G.http and _G.http.request)
    if not req then return warn("❌ Executor ไม่รองรับ HTTP") end

    -- ═══════════════════════════════════════════════════════════
    --  HELPERS
    -- ═══════════════════════════════════════════════════════════
    local function safeGet(t, k)
        local ok, v = pcall(rawget, t, k)
        if ok then return v end
    end
    local function isTable(v) return type(v) == "table" end
    local function log(fmt, ...)
        if DEBUG then print(("[P4NG] " .. fmt):format(...)) end
    end

    -- ═══════════════════════════════════════════════════════════
    --  SCAN GC — หา Item DB
    -- ═══════════════════════════════════════════════════════════
    local function isItemDB(t)
        local ok, result = pcall(function()
            local c, m = 0, 0
            for _, item in pairs(t) do
                c += 1
                if c > 600 then break end
                if isTable(item) then
                    if safeGet(item, "Rarity")
                       and safeGet(item, "Icon")
                       and safeGet(item, "Category") then
                        m += 1
                        if m >= 50 then return true end
                    end
                end
            end
            return false
        end)
        return ok and result
    end

    -- ═══════════════════════════════════════════════════════════
    --  SCAN GC — หา Inventory (key = ชื่อ item)
    -- ═══════════════════════════════════════════════════════════
    local function isInventory(t)
        local ok, result = pcall(function()
            local c, s = 0, 0
            for k, item in pairs(t) do
                c += 1
                if c > 100 then return false end
                if type(k) == "string" and isTable(item) then
                    local amt = safeGet(item, "Amount")
                    local iid = safeGet(item, "ItemId")
                    if amt ~= nil and iid ~= nil then
                        s += 1
                    end
                end
            end
            return c >= 2 and c <= 100 and s >= 2
        end)
        return ok and result
    end

    -- ═══════════════════════════════════════════════════════════
    --  Build getMyInventory()
    -- ═══════════════════════════════════════════════════════════
    local function buildGetter(DB, INV)
        -- index DB: key ของ DB คือชื่อ item
        local dbByName, dbById = {}, {}
        for id, item in pairs(DB) do
            if isTable(item) then
                if type(id) == "string" then dbByName[id] = item end
                if type(id) == "number" then dbById[tostring(id)] = item end
                local iid  = safeGet(item, "Id")
                local name = safeGet(item, "Name")
                if iid  then dbById[tostring(iid)] = item end
                if name then dbByName[name] = item end
            end
        end

        return function()
            local result = {}
            for name, entry in pairs(INV) do
                if type(name) == "string" and isTable(entry) then
                    local itemId = safeGet(entry, "ItemId")
                    local info = dbByName[name]
                              or dbById[tostring(itemId)]
                              or {}
                    result[#result + 1] = {
                        Name        = name,
                        Amount      = safeGet(entry, "Amount") or 1,
                        ItemId      = itemId,
                        RefineLevel = safeGet(entry, "RefineLevel") or 0,
                        Order       = safeGet(entry, "Order"),
                        Rarity      = safeGet(info, "Rarity"),
                        Icon        = safeGet(info, "Icon"),
                        Category    = safeGet(info, "Category"),
                    }
                end
            end
            table.sort(result, function(a, b)
                return (a.Order or 999) < (b.Order or 999)
            end)
            return result
        end
    end

    -- ═══════════════════════════════════════════════════════════
    --  สแกน GC หา DB + INV
    -- ═══════════════════════════════════════════════════════════
    local function scanGC()
        print("⏳ กำลังสแกน GC...")
        local DB, INV
        local checked = 0
        local t0 = tick()

        for _, v in pairs(getgc(true)) do
            checked += 1
            if checked > 2000000 then break end
            if type(v) == "table" then
                if not DB and isItemDB(v) then
                    DB = v
                    print("   ✅ เจอ Item DB")
                end
                if not INV and isInventory(v) then
                    INV = v
                    print("   ✅ เจอกระเป๋า")
                end
                if DB and INV then break end
            end
        end

        print(("   สแกน %d tables ใน %.2fs"):format(checked, tick() - t0))
        return DB, INV
    end

    -- ═══════════════════════════════════════════════════════════
    --  SEND ขึ้นเว็บ
    -- ═══════════════════════════════════════════════════════════
    local getMyInventory

    local function send()
        if not getMyInventory then return end
        local inv = getMyInventory()
        if #inv == 0 then return end

        local send = {}
        for _, it in ipairs(inv) do
            local icon = it.Icon
            if type(icon) == "string" then
                icon = icon:match("(%d+)") or icon
            end
            send[#send + 1] = {
                Name     = it.Name,
                Amount   = it.Amount,
                Rarity   = it.Rarity,
                Category = it.Category,
                Icon     = icon,
                ItemId   = it.ItemId,
            }
        end

        local payload = HttpService:JSONEncode({
            player    = lp.Name,
            userId    = lp.UserId,
            timestamp = os.time(),
            items     = send,
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
                    :format(os.date("%H:%M:%S"), #send))
            else
                warn(("[SEND] %s | ⚠️ HTTP %s")
                    :format(os.date("%H:%M:%S"), tostring(code)))
            end
        else
            warn("[SEND] ❌ ล้มเหลว: " .. tostring(res))
        end
    end

    -- ═══════════════════════════════════════════════════════════
    --  MAIN — scan + loop
    -- ═══════════════════════════════════════════════════════════
    local DB, INV = scanGC()

    if not DB then
        warn("❌ ไม่เจอ Item DB — ลองรันใหม่อีกครั้ง")
        return
    end
    if not INV then
        warn("❌ ไม่เจอกระเป๋า — ลองเปิดกระเป๋า 1 ครั้ง แล้วรันใหม่")
        return
    end

    getMyInventory = buildGetter(DB, INV)
    getgenv().getMyInventory = getMyInventory

    local list = getMyInventory()
    print(("\n✅ พร้อม! กระเป๋ามี %d ชนิด:"):format(#list))
    for i, it in ipairs(list) do
        print(("   [%d] %s x%s (R%s)")
            :format(i, it.Name, it.Amount, tostring(it.Rarity)))
    end
    print("")

    send()

    -- ── Loop ส่ง + auto-refind ──
    task.spawn(function()
        while task.wait(SEND_INTERVAL) do
            -- ตรวจ reference หลุด
            local size = 0
            for _ in pairs(INV) do
                size += 1
                if size > 1 then break end
            end
            if size == 0 then
                print("♻️ กระเป๋าหลุด — หาใหม่...")
                local newDB, newINV = scanGC()
                if newDB and newINV then
                    DB, INV = newDB, newINV
                    getMyInventory = buildGetter(DB, INV)
                    getgenv().getMyInventory = getMyInventory
                end
            end
            send()
        end
    end)

    print("🎯 ส่งทุก " .. SEND_INTERVAL .. " วิ → " .. URL)
end)
