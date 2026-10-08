-- ═══════════════════════════════════════════════════════════════
--   SLAYER 2 — FULL DATA → WEB (v6)
--   • กระเป๋า + Level + Title + Mastery + Stats
--   • กด M ครั้งเดียว → อัปเดตอัตโนมัติ
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    -- ─────────────────────────────────────────
    -- ตั้งค่า
    -- ─────────────────────────────────────────
    local WEB           = "http://localhost:3000"
    local URL_INV       = WEB .. "/api/inventory"
    local URL_CHAR      = WEB .. "/api/character"
    local SEND_INTERVAL = 5
    local UI_POLL       = 1.5
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
    if not req then return warn("❌ ไม่รองรับ HTTP") end

    -- ─────────────────────────────────────────
    -- Helpers
    -- ─────────────────────────────────────────
    local function safeGet(t, k)
        local ok, v = pcall(rawget, t, k); if ok then return v end
    end
    local function isTable(v) return type(v) == "table" end
    local function count(t) local c=0; for _ in pairs(t) do c+=1 end; return c end
    local function log(fmt, ...) if DEBUG then print(("[P4NG] "..fmt):format(...)) end end

    -- ─────────────────────────────────────────
    -- CHARACTER INFO — ดึงจากหลายแหล่ง
    -- ─────────────────────────────────────────
    local INFO_KEYS = {
        -- patterns ที่ต้องการ (lowercase)
        "level", "lvl",
        "title", "titleid",
        "mastery", "masteries",
        "exp", "experience", "xp",
        "coins", "money", "gold", "cash", "yen", "currency",
        "kills", "deaths", "wins", "losses",
        "rank", "tier", "grade",
        "clan", "clanname", "family",
        "breathing", "breath", "style", "fightingstyle",
        "strength", "defense", "agility", "speed",
        "health", "maxhealth", "stamina",
        "race", "bloodline",
        "playtime", "hours",
    }

    local function normalizeKey(k)
        return string.lower(tostring(k)):gsub("[%s_%-%.]", "")
    end

    local function matchKey(k)
        local nk = normalizeKey(k)
        for _, pat in ipairs(INFO_KEYS) do
            local np = normalizeKey(pat)
            if string.find(nk, np, 1, true) then return true end
        end
        return false
    end

    local function scanAttrs(inst, label)
        local out = {}
        if not inst then return out end
        local ok, attrs = pcall(function() return inst:GetAttributes() end)
        if not ok or not attrs then return out end
        for k, v in pairs(attrs) do
            if matchKey(k) then
                local t = typeof(v)
                if t == "number" or t == "string" or t == "boolean" then
                    out[k] = v
                end
            end
        end
        return out
    end

    local function scanChildren(inst, label)
        -- เช่น leaderstats (Folder → IntValue)
        local out = {}
        if not inst then return out end
        local ok, children = pcall(function() return inst:GetChildren() end)
        if not ok then return out end
        for _, c in ipairs(children) do
            local t = c.ClassName
            if t == "IntValue" or t == "NumberValue" or t == "StringValue" or t == "BoolValue" then
                if matchKey(c.Name) then
                    out[c.Name] = c.Value
                end
            elseif t == "Folder" then
                local sub = scanChildren(c, label)
                for k, v in pairs(sub) do out[k] = v end
            end
        end
        return out
    end

    local function findPlayerDataTable()
        -- สแกน GC หา table ที่ดูเหมือน player data
        local candidates = {}
        local checked = 0
        for _, v in pairs(getgc(true)) do
            checked += 1
            if checked > 500000 then break end
            if type(v) == "table" then
                local hits = 0
                local sample = {}
                local n = 0
                for k, val in pairs(v) do
                    n += 1
                    if n > 200 then break end
                    if type(k) == "string" and matchKey(k) then
                        local t = type(val)
                        if t == "number" or t == "string" or t == "boolean" then
                            hits += 1
                            if #sample < 30 then
                                sample[k] = val
                            end
                        end
                    end
                end
                if hits >= 3 then
                    candidates[#candidates+1] = {tbl = v, hits = hits, sample = sample, size = n}
                end
            end
        end
        table.sort(candidates, function(a,b) return a.hits > b.hits end)
        return candidates
    end

    local function scanUIForInfo()
        -- อ่าน HUD เพื่อหา Level/Title (มักแสดงเป็น TextLabel บนจอ)
        local found = {}
        local pg = lp:FindFirstChild("PlayerGui"); if not pg then return found end

        local ok, descendants = pcall(function() return pg:GetDescendants() end)
        if not ok then return found end

        for _, d in ipairs(descendants) do
            if d:IsA("TextLabel") and d.Visible then
                local n = d.Name:lower()
                -- Level display
                if n:find("level") or n:find("lvl") then
                    local num = tonumber(d.Text) or tonumber((d.Text or ""):match("(%d+)"))
                    if num then found.Level = num end
                end
                -- Title display
                if (n:find("title") or n:find("rank")) and d.Text and #d.Text < 60 then
                    found.Title = d.Text
                end
                -- Clan
                if n:find("clan") and d.Text and #d.Text < 40 then
                    found.Clan = d.Text
                end
            end
        end
        return found
    end

    -- ─────────────────────────────────────────
    -- เก็บข้อมูลตัวละคร
    -- ─────────────────────────────────────────
    local cachedInfo = {}

    local function refreshCharacterInfo()
        local info = {}

        -- 1. Player attributes
        for k, v in pairs(scanAttrs(lp, "Player")) do info[k] = v end

        -- 2. Character attributes
        if lp.Character then
            for k, v in pairs(scanAttrs(lp.Character, "Char")) do info[k] = v end
        end

        -- 3. leaderstats
        local ls = lp:FindFirstChild("leaderstats")
        if ls then
            for k, v in pairs(scanChildren(ls, "leaderstats")) do info[k] = v end
        end

        -- 4. PlayerData จาก GC (best match)
        local candidates = findPlayerDataTable()
        if #candidates > 0 then
            -- เอา top 3 มารวมกัน
            for i = 1, math.min(3, #candidates) do
                for k, v in pairs(candidates[i].sample) do
                    if info[k] == nil then info[k] = v end
                end
            end
            info._datatablesFound = #candidates
        end

        -- 5. UI scan (ค่าอาจไม่ครบ — เอามา merge)
        local ui = scanUIForInfo()
        for k, v in pairs(ui) do
            if info[k] == nil then info[k] = v end
        end

        cachedInfo = info
    end

    -- ─────────────────────────────────────────
    -- INVENTORY — กด M + ซ่อน UI (จาก v5)
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

    local function hideUI(holder)
        local bg = holder:FindFirstChild("Background")
        if bg and bg:IsA("GuiObject") then bg.Visible = false end
    end

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

    local dbByName = {}

    local function readFrame(frame)
        if not frame:IsA("Frame") then return nil end
        local name = frame.Name
        if not name or name == "" then return nil end
        local amount = 1
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
    -- กด M ครั้งแรก
    -- ─────────────────────────────────────────
    print("🎯 กด M เปิดกระเป๋าครั้งแรก...")
    pressM()
    task.wait(0.8)

    local ah, holder = findHolder()
    if ah then
        refreshCache()
        print(("✅ อ่านกระเป๋าครั้งแรก %d items"):format(count(cache)))
        if holder then hideUI(holder) end
        ah.ChildAdded:Connect(function() task.wait(0.15); refreshCache() end)
        ah.ChildRemoved:Connect(function() task.wait(0.15); refreshCache() end)
    end

    -- ─────────────────────────────────────────
    -- Getter
    -- ─────────────────────────────────────────
    local function getMyInventory()
        local r = {}
        for _, item in pairs(cache) do r[#r+1] = item end
        return r
    end
    getgenv().getMyInventory = getMyInventory
    getgenv().getMyInfo = function() return cachedInfo end

    -- ─────────────────────────────────────────
    -- ส่ง Inventory
    -- ─────────────────────────────────────────
    local function sendInv()
        local list = getMyInventory()
        if #list == 0 then return end
        local out = {}
        for _, it in ipairs(list) do
            local icon = it.Icon
            if type(icon) == "string" then icon = icon:match("(%d+)") or icon end
            out[#out+1] = {
                Name = it.Name, Amount = it.Amount, Rarity = it.Rarity,
                Category = it.Category, Icon = icon, ItemId = it.ItemId,
            }
        end
        local payload = HttpService:JSONEncode({
            game = tostring(game.PlaceId),
            player = lp.Name, userId = lp.UserId,
            timestamp = os.time(), items = out,
        })
        local ok, res = pcall(req, {
            Url = URL_INV, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload,
        })
        if ok and res then
            local code = res.StatusCode or res.Status or res.status or "?"
            if tostring(code) == "200" then
                print(("[SEND-INV] %s | ✅ %d items")
                    :format(os.date("%H:%M:%S"), #out))
            end
        end
    end

    -- ─────────────────────────────────────────
    -- ส่ง Character Info
    -- ─────────────────────────────────────────
    local function sendChar()
        if count(cachedInfo) == 0 then return end
        local payload = HttpService:JSONEncode({
            game      = tostring(game.PlaceId),
            player    = lp.Name,
            userId    = lp.UserId,
            timestamp = os.time(),
            info      = cachedInfo,
        })
        local ok, res = pcall(req, {
            Url = URL_CHAR, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload,
        })
        if ok and res then
            local code = res.StatusCode or res.Status or res.status or "?"
            if tostring(code) == "200" then
                print(("[SEND-CHAR] %s | ✅ %d fields")
                    :format(os.date("%H:%M:%S"), count(cachedInfo)))
            end
        end
    end

    -- ─────────────────────────────────────────
    -- Main setup
    -- ─────────────────────────────────────────
    refreshCharacterInfo()
    print(("✅ Character info: %d fields"):format(count(cachedInfo)))
    for k, v in pairs(cachedInfo) do
        if not tostring(k):find("^_") then
            print(("   %s = %s"):format(tostring(k), tostring(v)))
        end
    end

    sendInv()
    sendChar()

    -- ─────────────────────────────────────────
    -- Loops
    -- ─────────────────────────────────────────
    task.spawn(function()
        while task.wait(UI_POLL) do
            if ah then refreshCache() end
        end
    end)

    task.spawn(function()
        while task.wait(SEND_INTERVAL) do
            refreshCharacterInfo()
            sendInv()
            sendChar()
        end
    end)

    -- Watchdog: กด M ใหม่ถ้า cache ว่าง
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

    print("✅ พร้อม! ข้อมูลทั้งกระเป๋า + ตัวละครจะอัปเดตอัตโนมัติ")
end)
