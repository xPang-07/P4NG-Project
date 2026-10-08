-- ═══════════════════════════════════════════════════════════════
--   SLAYER 2 — FULL DATA → WEB (v7 · performance)
--   • GC scanned ONCE (cached table refs — no 5s rescans)
--   • UI labels cached (no 5s PlayerGui walks)
--   • Payload hash dedupe (no redundant HTTP)
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    ------------------------------------------------------------------
    -- Config
    ------------------------------------------------------------------
    local WEB           = "http://localhost:3000"
    local SEND_INTERVAL = 5
    local UI_POLL       = 2
    local GC_RESCAN     = 90      -- seconds, only if data goes stale
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

    local function log(fmt, ...) if DEBUG then print(("[P4NG] "..fmt):format(...)) end end
    local function isTable(v) return type(v) == "table" end
    local function count(t) local c = 0; for _ in pairs(t) do c += 1 end; return c end

    ------------------------------------------------------------------
    -- Key matching
    ------------------------------------------------------------------
    local INFO_KEYS = {
        "level","lvl","title","titleid","mastery","masteries",
        "exp","experience","xp","coins","money","gold","cash","yen","currency",
        "kills","deaths","wins","losses","rank","tier","grade",
        "clan","clanname","family","breathing","breath","style","fightingstyle",
        "strength","defense","agility","speed","health","maxhealth","stamina",
        "race","bloodline","playtime","hours",
    }
    local NORM_KEYS = {}
    for i, p in ipairs(INFO_KEYS) do
        NORM_KEYS[i] = p:gsub("[%s_%-%.]", "")
    end

    local function normalize(k) return string.lower(tostring(k)):gsub("[%s_%-%.]", "") end

    local function matchKey(k)
        local nk = normalize(k)
        for i = 1, #NORM_KEYS do
            if string.find(nk, NORM_KEYS[i], 1, true) then return true end
        end
        return false
    end

    ------------------------------------------------------------------
    -- Attribute / children readers
    ------------------------------------------------------------------
    local function scanAttrs(inst, out)
        if not inst then return end
        local ok, attrs = pcall(function() return inst:GetAttributes() end)
        if not ok or not attrs then return end
        for k, v in pairs(attrs) do
            if out[k] == nil and matchKey(k) then
                local t = typeof(v)
                if t == "number" or t == "string" or t == "boolean" then out[k] = v end
            end
        end
    end

    local function scanChildren(inst, out)
        if not inst then return end
        local ok, children = pcall(function() return inst:GetChildren() end)
        if not ok then return end
        for _, c in ipairs(children) do
            local cn = c.ClassName
            if cn == "IntValue" or cn == "NumberValue"
               or cn == "StringValue" or cn == "BoolValue" then
                if out[c.Name] == nil and matchKey(c.Name) then out[c.Name] = c.Value end
            elseif cn == "Folder" then
                scanChildren(c, out)
            end
        end
    end

    ------------------------------------------------------------------
    -- ONE-TIME GC SCAN — cache table references
    ------------------------------------------------------------------
    local dataTables = {}
    local lastGCScan = 0

    local function scanForDataTables()
        local found = {}
        local scanned = 0
        for _, v in pairs(getgc(true)) do
            scanned += 1
            if scanned > 150000 then break end
            if type(v) == "table" then
                local hits, n = 0, 0
                for k, val in pairs(v) do
                    n += 1
                    if n > 40 then break end
                    if type(k) == "string" and matchKey(k) then
                        local tv = type(val)
                        if tv == "number" or tv == "string" or tv == "boolean" then
                            hits += 1
                            if hits >= 3 then break end
                        end
                    end
                end
                if hits >= 3 then found[#found + 1] = v end
            end
        end
        return found
    end

    local function collectFrom(tbl, out, depth)
        if not isTable(tbl) then return end
        local n = 0
        for k, v in pairs(tbl) do
            n += 1
            if n > 150 then break end
            if type(k) == "string" then
                if out[k] == nil and matchKey(k) then
                    local tv = type(v)
                    if tv == "number" or tv == "string" or tv == "boolean" then
                        out[k] = v
                    end
                end
                if depth > 0 and isTable(v) then
                    collectFrom(v, out, depth - 1)
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- UI label cache
    ------------------------------------------------------------------
    local uiLabels = {}
    local lastUIScan = 0

    local function cacheUILabels()
        local t = {}
        local pg = lp:FindFirstChild("PlayerGui")
        if pg then
            local ok, desc = pcall(function() return pg:GetDescendants() end)
            if ok then
                for _, d in ipairs(desc) do
                    if d:IsA("TextLabel") and d.Visible then
                        local n = d.Name:lower()
                        local kind
                        if n:find("level") or n:find("lvl") then kind = "Level"
                        elseif n:find("title") or n:find("rank") then kind = "Title"
                        elseif n:find("clan") then kind = "Clan"
                        end
                        if kind then t[#t + 1] = { obj = d, kind = kind } end
                    end
                end
            end
        end
        uiLabels = t
        lastUIScan = os.clock()
    end

    local function readUILabels()
        if os.clock() - lastUIScan > 30 then cacheUILabels() end
        local out = {}
        for _, e in ipairs(uiLabels) do
            local obj = e.obj
            if obj and obj.Parent then
                local txt = obj.Text
                if e.kind == "Level" then
                    local n = tonumber(txt) or tonumber(tostring(txt):match("(%d+)"))
                    if n then out.Level = n end
                elseif #txt < 60 then
                    out[e.kind] = txt
                end
            end
        end
        return out
    end

    ------------------------------------------------------------------
    -- Character info refresh (CHEAP — reads cached refs only)
    ------------------------------------------------------------------
    local cachedInfo = {}

    local function refreshCharacterInfo()
        local info = {}

        scanAttrs(lp, info)
        if lp.Character then scanAttrs(lp.Character, info) end

        local ls = lp:FindFirstChild("leaderstats")
        if ls then scanChildren(ls, info) end

        -- read from cached GC table references (no re-scan!)
        if #dataTables == 0 or os.clock() - lastGCScan > GC_RESCAN then
            dataTables = scanForDataTables()
            lastGCScan = os.clock()
            log("GC scan → %d candidate tables", #dataTables)
        end
        for i = 1, #dataTables do
            collectFrom(dataTables[i], info, 1)
        end

        for k, v in pairs(readUILabels()) do
            if info[k] == nil then info[k] = v end
        end

        cachedInfo = info
    end

    ------------------------------------------------------------------
    -- INVENTORY — press M once, cache children
    ------------------------------------------------------------------
    local function pressM()
        pcall(function()
            VIM:SendKeyEvent(true,  Enum.KeyCode.M, false, game)
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
        local bg = holder and holder:FindFirstChild("Background")
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
                            if rawget(item, "Rarity") and rawget(item, "Icon")
                               and rawget(item, "Category") then
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
            elseif amtObj:IsA("IntValue") or amtObj:IsA("NumberValue") then
                txt = tostring(amtObj.Value)
            end
            if txt then
                amount = tonumber(txt) or tonumber(tostring(txt):match("%d+")) or 1
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

    local function refreshCache(ah)
        if not ah then return end
        local new = {}
        for _, frame in ipairs(ah:GetChildren()) do
            local name, amount = readFrame(frame)
            if name then
                local info = dbByName[name] or {}
                new[name] = {
                    Name     = name,
                    Amount   = amount,
                    ItemId   = info.Id,
                    Rarity   = info.Rarity,
                    Icon     = info.Icon,
                    Category = info.Category,
                }
            end
        end
        cache = new
    end

    ------------------------------------------------------------------
    -- Setup DB
    ------------------------------------------------------------------
    local DB = findDB()
    if not DB then return warn("❌ ไม่เจอ Item DB") end
    for id, item in pairs(DB) do
        if type(id) == "string" and isTable(item) then dbByName[id] = item end
    end
    print(("✅ เจอ DB: %d items"):format(count(dbByName)))

    print("🎯 กด M เปิดกระเป๋าครั้งแรก...")
    pressM()
    task.wait(0.8)

    local ah, holder = findHolder()
    if ah then
        refreshCache(ah)
        print(("✅ อ่านกระเป๋าครั้งแรก %d items"):format(count(cache)))
        hideUI(holder)
        ah.ChildAdded:Connect(function()   task.wait(0.15); refreshCache(ah) end)
        ah.ChildRemoved:Connect(function() task.wait(0.15); refreshCache(ah) end)
    end

    local function getMyInventory()
        local r = {}
        for _, item in pairs(cache) do r[#r + 1] = item end
        return r
    end
    getgenv().getMyInventory = getMyInventory
    getgenv().getMyInfo      = function() return cachedInfo end

    ------------------------------------------------------------------
    -- SEND — hash dedupe (skip HTTP if nothing changed)
    ------------------------------------------------------------------
    local lastInvCore, lastCharCore

    local function postJSON(url, payloadStr)
        local ok, res = pcall(req, {
            Url = url, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payloadStr,
        })
        if not ok or not res then return false end
        local code = res.StatusCode or res.Status or res.status
        return tostring(code) == "200"
    end

    local function sendInv()
        local list = getMyInventory()
        if #list == 0 then return end

        local out = {}
        for _, it in ipairs(list) do
            local icon = it.Icon
            if type(icon) == "string" then icon = icon:match("(%d+)") or icon end
            out[#out + 1] = {
                Name = it.Name, Amount = it.Amount, Rarity = it.Rarity,
                Category = it.Category, Icon = icon, ItemId = it.ItemId,
            }
        end

        -- hash-dedupe: build WITHOUT timestamp so identical payloads are caught
        local coreTable = { items = out, userId = lp.UserId }
        local coreJSON  = HttpService:JSONEncode(coreTable)
        if coreJSON == lastInvCore then return end
        lastInvCore = coreJSON

        coreTable.game      = tostring(game.PlaceId)
        coreTable.player    = lp.Name
        coreTable.timestamp = os.time()

        local ok = postJSON(WEB .. "/api/inventory", HttpService:JSONEncode(coreTable))
        if ok then
            print(("[SEND-INV] %s | ✅ %d items"):format(os.date("%H:%M:%S"), #out))
        end
    end

    local function sendChar()
        if count(cachedInfo) == 0 then return end

        local coreTable = { info = cachedInfo, userId = lp.UserId }
        local coreJSON  = HttpService:JSONEncode(coreTable)
        if coreJSON == lastCharCore then return end
        lastCharCore = coreJSON

        coreTable.game      = tostring(game.PlaceId)
        coreTable.player    = lp.Name
        coreTable.timestamp = os.time()

        local ok = postJSON(WEB .. "/api/character", HttpService:JSONEncode(coreTable))
        if ok then
            print(("[SEND-CHAR] %s | ✅ %d fields"):format(os.date("%H:%M:%S"), count(cachedInfo)))
        end
    end

    ------------------------------------------------------------------
    -- Main loops
    ------------------------------------------------------------------
    cacheUILabels()
    refreshCharacterInfo()
    print(("✅ Character info: %d fields"):format(count(cachedInfo)))

    sendInv()
    sendChar()

    task.spawn(function()
        while task.wait(UI_POLL) do
            if ah then refreshCache(ah) end
        end
    end)

    task.spawn(function()
        while task.wait(SEND_INTERVAL) do
            refreshCharacterInfo()
            sendInv()
            sendChar()
        end
    end)

    -- Watchdog: re-press M if the inventory cache goes empty
    task.spawn(function()
        local emptyRounds = 0
        while task.wait(2) do
            if count(cache) == 0 then
                emptyRounds += 1
                if emptyRounds >= 5 then
                    print("♻️ cache ว่าง — กด M ใหม่...")
                    pressM()
                    task.wait(0.6)
                    ah, holder = findHolder()
                    if ah then
                        refreshCache(ah)
                        hideUI(holder)
                    end
                    emptyRounds = 0
                end
            else
                emptyRounds = 0
            end
        end
    end)

    print("✅ พร้อม! ข้อมูลทั้งกระเป๋า + ตัวละครจะอัปเดตอัตโนมัติ")
end)
