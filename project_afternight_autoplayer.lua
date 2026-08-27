-- Project Afternight autoplayer (Matcha)
-- Tab: Autoplayer21 | Toggle Enabled, then play. ms slider = press ms early.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

pcall(function() setrobloxinput(true) end)

local codeOf = {
    D = 68, F = 70, J = 74, K = 75,
    Space = 32, L = 76, A = 65, S = 83, W = 87, E = 69, Z = 90, X = 88,
}

local cfg = { enabled = false, ms = 8, comp = 0, slack = 60, maxX = 150, debug = false, holdH = 260, tailMargin = 60, keys = { "D", "F", "J", "K" } }
local EXTRA = { "Space", "L", "A", "S", "W", "E", "Z", "X" }

local state = { strums = {}, notes = {}, keyList = {}, inSong = false, side = "L" }
local pressed = {}
local downKind = {}
local pressAddr = {}
local holdUntil = {}
local holdTail = {}
local lastPressed = {}
local pressX = {}
local pressY = {}
local lastPressedX = {}
local lastPressedY = {}
local lastRel = {}
local beatToken = tostring(math.random(1000, 9999)) .. tostring(math.random(1000, 9999))
    local born = tick()
    local dupDetected = false
local speed = 900
local noteTrack = {}
local sline = {}
local slineN = -1
local frameCnt = 0
local hudAcc = nil
local lastDbg = 0
local lastBreaks = nil
local tuneCooldown = 0
local ratingDir = -1
local ratingBefore = nil
local rateCooldown = 0
local rateStale = 0
local lastRatingSeen = nil
local lastSongRating = nil
local emptyScans = 0

-- v21: persisted settings from the Matcha workspace (C:/matcha/workspace)
local savedMs, savedSlack, savedDbg, savedComp
pcall(function()
    local chunk = readfile("ap_settings.txt")
    if chunk then
        local f = loadstring(chunk)
        if f then
            local okT, t = pcall(f)
            if okT and type(t) == "table" then
                savedMs = type(t.ms) == "number" and t.ms or nil
                savedSlack = type(t.slack) == "number" and t.slack or nil
                savedDbg = type(t.debug) == "boolean" and t.debug or nil
                savedComp = type(t.comp) == "number" and t.comp or nil
            end
        end
    end
end)
if savedMs then cfg.ms = math.clamp(savedMs, 5, 150) end
if savedSlack then cfg.slack = math.clamp(savedSlack, 10, 400) end
if savedDbg ~= nil then cfg.debug = savedDbg end
if savedComp then cfg.comp = math.clamp(savedComp, 0, 40) end

local overlay = Drawing.new("Text")
overlay.Size = 13
overlay.Center = true
overlay.Outline = true
overlay.Position = Vector2.new(8, 8)
overlay.Visible = false

local function releaseAll()
    for i, key in ipairs(state.keyList) do
        if pressed[i] then
            keyrelease(codeOf[key])
            pressed[i] = false
        end
    end
    downKind = {}
    pressAddr = {}
    holdTail = {}
    lastPressed = {}
    lastRel = {}
    pressX = {}
    pressY = {}
    lastPressedX = {}
    lastPressedY = {}
end

local function scan()
    pcall(function()
        local pg = lp:FindFirstChild("PlayerGui")
        local main = pg and pg:FindFirstChild("Main")
        local gameFrame = main and main:FindFirstChild("Game")
        if not gameFrame then
            if state.inSong then state.inSong = false; releaseAll() end
            return
        end
        local strums, notes = {}, {}
        for _, c in ipairs(gameFrame:GetChildren()) do
            if c.ClassName == "ImageLabel" then
                if c.Name:match("^Strum%d+$") then
                    strums[#strums + 1] = c
                else
                    local okz, z = pcall(function() return c.AbsoluteSize end)
                    if okz and z and z.Y >= 100 then
                        notes[#notes + 1] = c
                    end
                end
            end
        end
        if #strums == 0 then
            emptyScans = emptyScans + 1
            if state.inSong and emptyScans >= 2 then
                state.inSong = false
                releaseAll()
            end
            return
        end
        emptyScans = 0
        table.sort(strums, function(a, b)
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        end)
        local nS = #strums
        local playerStrums = {}
        local sideLabel = "all"
        if nS >= 6 then
            for _, st in ipairs(strums) do
                local ok, z = pcall(function() return st.AbsoluteSize end)
                if ok and z and z.Y > 130 then
                    playerStrums[#playerStrums + 1] = st
                end
            end
            table.sort(playerStrums, function(a, b)
                return a.AbsolutePosition.X < b.AbsolutePosition.X
            end)
            if #playerStrums == 0 then
                for i = 1, nS do playerStrums[i] = strums[i] end
                sideLabel = "all"
            else
                local meanX = 0
                for _, st in ipairs(playerStrums) do
                    local ok, p = pcall(function() return st.AbsolutePosition end)
                    if ok and p then meanX = meanX + p.X end
                end
                meanX = meanX / #playerStrums
                sideLabel = meanX < 960 and "L" or "R"
            end
        else
            for i = 1, nS do playerStrums[i] = strums[i] end
        end
        local count = #playerStrums
        local kl = {}
        for i = 1, count do
            kl[i] = cfg.keys[i] or EXTRA[i - #cfg.keys] or "D"
        end
        if not state.inSong then
            print("SONG START: strums=" .. nS .. " notes=" .. #notes .. " side=" .. sideLabel)
            if hudAcc then
                local okT, txt = pcall(function() return hudAcc.Text end)
                if okT and txt then
                    local cur = tonumber(txt:match("Rating:%s*(%d+%.?%d*)") or txt:match("Accuracy:%s*(%d+%.?%d*)"))
                    if cur then
                        if lastSongRating then
                            if cur > lastSongRating + 0.15 then
                                cfg.ms = math.clamp(cfg.ms + ratingDir, 6, 40)
                                print(("SONG ms->%d (%.2f->%.2f)"):format(cfg.ms, lastSongRating, cur))
                            elseif cur < lastSongRating - 0.15 then
                                ratingDir = -ratingDir
                                cfg.ms = math.clamp(cfg.ms + ratingDir, 6, 40)
                                print(("SONG flip ms->%d (%.2f->%.2f)"):format(cfg.ms, lastSongRating, cur))
                            end
                        end
                        lastSongRating = cur
                    end
                end
            end
            lastBreaks = nil
            tuneCooldown = 0
            ratingBefore = nil
            rateCooldown = 0
        end
        state.strums = playerStrums
        state.notes = notes
        state.keyList = kl
        state.side = sideLabel
        state.inSong = true
        if hudAcc then
            local okH = pcall(function() return hudAcc.Text end)
            if not okH then hudAcc = nil end
        end
        hudAcc = hudAcc or (main:FindFirstChild("HUD") and main.HUD:FindFirstChild("Accuracy"))
        if not hudAcc then
            local hud = main:FindFirstChild("HUD")
            if hud then
                for _, c in ipairs(hud:GetChildren()) do
                    if c.ClassName == "TextLabel" and tostring(c.Text):find("Breaks") then
                        hudAcc = c
                        break
                    end
                end
            end
        end
    end)
end

task.spawn(function()
    while true do
        scan()
        task.wait(0.25)
    end
end)

RunService.RenderStepped:Connect(function(dt)
    local t = tick()
    frameCnt = frameCnt + 1
    dt = math.clamp(dt or 1 / 60, 1 / 240, 1 / 30)
    if not state.inSong or #state.strums == 0 then
        if not cfg.enabled then releaseAll() end
        overlay.Visible = false
        return
    end
    local sc = {}
    local n = 0
    for i = 1, #state.strums do
        local ok1, p = pcall(function() return state.strums[i].AbsolutePosition end)
        local ok2, z = pcall(function() return state.strums[i].AbsoluteSize end)
        if ok1 and ok2 and p and z then n = n + 1; sc[n] = p + z * 0.5 end
    end
    if slineN ~= n then
        sline = {}
        slineN = n
    end
    for i = 1, n do
        sline[i] = sline[i] and (sline[i] * 0.8 + sc[i].Y * 0.2) or sc[i].Y
    end
    local laneNotes = {}
    for i = 1, n do laneNotes[i] = {} end
    for _, note in ipairs(state.notes) do
        local ok1, p = pcall(function() return note.AbsolutePosition end)
        local ok2, z = pcall(function() return note.AbsoluteSize end)
        local ok3, ad = pcall(function() return note.Address end)
        if ok1 and ok2 and p and z then
            local c = p + z * 0.5
            local bl, bd = 0, 1e9
            for i = 1, n do
                local dx = math.abs(c.X - sc[i].X)
                if dx < cfg.maxX then
                    local d = math.abs(c.Y - sc[i].Y)
                    if d < bd then bl, bd = i, d end
                end
            end
            if bl > 0 then
                local yE, vy = c.Y, speed
                local un, used = 0, false
                if ad then
                    local tk = noteTrack[ad]
                    if tk then
                        if frameCnt - tk.last > 3 or math.abs(c.Y - tk.y) > 120 then
                            tk.y = c.Y
                            tk.vy = speed
                            tk.last = frameCnt
                            tk.lane = nil
                            tk.sway = nil
                            tk.unstable = nil
                            tk.used = nil
                            tk.px = nil
                        else
                            local inst = (tk.y - c.Y) / dt
                            if inst > 30 then
                                tk.vy = tk.vy * 0.6 + math.clamp(inst, 50, 6000) * 0.4
                            end
                            tk.y = tk.y * 0.7 + c.Y * 0.3
                            tk.last = frameCnt
                        end
                        yE, vy = tk.y, tk.vy
                        if tk.px and math.abs(c.X - tk.px) > 60 then tk.unstable = 6 end
                        tk.px = c.X
                        un = tk.unstable or 0
                        used = tk.used == true
                        if tk.unstable and tk.unstable > 0 then tk.unstable = tk.unstable - 1 end
                        if tk.lane and sc[tk.lane] then
                            if math.abs(c.X - sc[tk.lane].X) > cfg.maxX + 80 then
                                tk.lane = bl
                                tk.sway = 0
                                tk.used = nil
                                tk.unstable = nil
                            elseif bl ~= tk.lane then
                                tk.sway = (tk.sway or 0) + 1
                                if tk.sway > 5 then
                                    tk.lane = bl
                                    tk.sway = 0
                                end
                            else
                                tk.sway = 0
                            end
                        else
                            tk.lane = bl
                            tk.sway = 0
                        end
                        if tk.used and tk.lane and sline[tk.lane] and (tk.y - sline[tk.lane]) < -60 then
                            tk.used = nil
                            tk.unstable = nil
                        end
                    else
                        noteTrack[ad] = { y = c.Y, vy = speed, last = frameCnt, lane = bl, sway = 0, px = c.X }
                    end
                end
                laneNotes[bl][#laneNotes[bl] + 1] = { p = p, z = z, c = c, addr = ad, yE = yE, vy = vy, un = un, used = used }
            end
        end
    end
    local vSum, vCnt = 0, 0
    for i = 1, n do
        for _, ln in ipairs(laneNotes[i]) do
            if ln.vy then vSum = vSum + ln.vy; vCnt = vCnt + 1 end
        end
    end
    if vCnt >= 2 then
        local meanV = vSum / vCnt
        if meanV > 50 then
            speed = speed * 0.6 + meanV * 0.4
            speed = math.clamp(speed, 80, 6000)
        end
    end
    local tkCnt = 0
    for _ in pairs(noteTrack) do tkCnt = tkCnt + 1 end
    if tkCnt > 96 then
        for ad, tk in pairs(noteTrack) do
            if frameCnt - tk.last > 30 then noteTrack[ad] = nil end
        end
    end
    local pressDist = math.clamp(speed * cfg.ms / 1000, 6, 250)
    local lowerB = -math.max(15, speed / 60)
    -- v21: focus guard - release everything when the game window is unfocused
    local active = true
    pcall(function() active = isrbxactive() end)
    if not active then
        releaseAll()
    end
    if cfg.enabled then
        for i = 1, n do
            local key = state.keyList[i]
            if not key then break end
            local lineY = sline[i]
            if lastPressed[i] then
                local found = false
                local d = nil
                local cX, cY = nil, nil
                for _, ln in ipairs(laneNotes[i]) do
                    if ln.addr == lastPressed[i] then found = true; d = ln.yE - lineY; cX = ln.c.X; cY = ln.c.Y end
                end
                if (not found) or d < lowerB or d > pressDist + cfg.slack
                    or (lastPressedX[i] and cX and math.abs(cX - lastPressedX[i]) > 90)
                    or (lastPressedY[i] and cY and (cY - lastPressedY[i]) > 150) then
                    lastPressed[i] = nil
                end
            end
            local holdKeep = false
            for _, ln in ipairs(laneNotes[i]) do
                if ln.z.Y > cfg.holdH and ln.vy > 50 and (ln.un <= 0 or ln.z.Y > cfg.holdH) and not ln.used then
                    local headD = ln.p.Y - lineY
                    local tailD = ln.p.Y + ln.z.Y - lineY
                    if headD <= pressDist + cfg.slack and tailD > -cfg.tailMargin then
                        holdKeep = true
                    end
                end
            end
            if pressed[i] then
                local doRelease = false
                if downKind[i] == "hold" then
                    local succ = false
                    local liveTail = holdTail[i]
                    for _, ln in ipairs(laneNotes[i]) do
                        if ln.addr == pressAddr[i] then
                            liveTail = ln.p.Y + ln.z.Y
                            break
                        end
                    end
                    if liveTail then
                        holdUntil[i] = math.max(holdUntil[i] or 0, tick() + math.max(0, liveTail - lineY) / math.max(speed, 50) + 0.15)
                    end
                    for _, ln in ipairs(laneNotes[i]) do
                        if not ln.used and ln.addr ~= pressAddr[i] and ln.vy > 50 then
                            local isH = ln.z.Y > cfg.holdH
                            local hd = isH and (ln.p.Y - lineY) or (ln.yE - lineY)
                            if hd >= lowerB and hd <= pdN then
                                local headY = isH and ln.p.Y or ln.yE
                                if (not liveTail) or headY > liveTail + 30 then
                                    succ = true
                                end
                            end
                        end
                    end
                    doRelease = succ or (not holdKeep and (not holdUntil[i] or tick() > holdUntil[i]))
                elseif downKind[i] == "tap" then
                    local ad = pressAddr[i]
                    local heldD = nil
                    local stillThere = false
                    for _, ln in ipairs(laneNotes[i]) do
                        if ln.addr == ad then stillThere = true; heldD = ln.c.Y - lineY end
                    end
                    if not stillThere then
                        doRelease = true
                    elseif heldD then
                        if heldD < -15 or heldD > pressDist + cfg.slack then
                            doRelease = true
                        else
                            for _, ln in ipairs(laneNotes[i]) do
                                if ln.addr ~= ad and ln.vy > 50 then
                                    local d = ln.z.Y > cfg.holdH and (ln.p.Y - lineY) or (ln.c.Y - lineY)
                                    if d <= pressDist + math.max(40, speed / 60) and d > heldD + 2 then
                                        doRelease = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                if doRelease then
                    keyrelease(codeOf[key])
                    pressed[i] = false
                    if pressAddr[i] then
                        lastPressed[i] = pressAddr[i]
                        lastPressedX[i] = pressX[i]
                        lastPressedY[i] = pressY[i]
                    end
                    downKind[i] = nil
                    pressAddr[i] = nil
                    lastRel[i] = frameCnt
                    if cfg.debug then print(("REL lane=%d key=%s"):format(i, key)) end
                end
            end
            if not pressed[i] and not dupDetected and (not lastRel[i] or frameCnt > lastRel[i]) then
                local cand = nil
                local candD = 1e9
                local candKind = "tap"
                for _, ln in ipairs(laneNotes[i]) do
                    if ln.addr ~= lastPressed[i] and ln.vy > 50 and (ln.un <= 0 or ln.z.Y > cfg.holdH) and not ln.used then
                        local isHold = ln.z.Y > cfg.holdH
                        local d = isHold and (ln.p.Y - lineY) or (ln.yE - lineY)
                        local pdN = math.clamp(ln.vy * (cfg.ms + cfg.comp) / 1000, 6, 250)
                        if d >= lowerB and d <= pdN and d < candD then
                            cand, candD, candKind = ln, d, isHold and "hold" or "tap"
                        end
                    end
                end
                if cand then
                    keypress(codeOf[key])
                    pressed[i] = true
                    downKind[i] = candKind
                    pressAddr[i] = cand.addr
                    pressX[i] = cand.c.X
                    pressY[i] = cand.c.Y
                    if candKind == "hold" then
                        holdUntil[i] = tick() + math.max(0, cand.p.Y + cand.z.Y - lineY) / math.max(cand.vy, 50) + 0.15
                        holdTail[i] = cand.p.Y + cand.z.Y
                    end
                    if cand.addr then
                        local tr = noteTrack[cand.addr]
                        if tr then tr.used = true end
                    end
                    if cfg.debug then print(("PRESS lane=%d key=%s %s d=%.0f"):format(i, key, candKind, candD)) end
                end
            end
        end
    end
    local minD = {}
    for i = 1, n do
        minD[i] = 1e9
        for _, ln in ipairs(laneNotes[i]) do
            local d = math.abs(ln.c.Y - sc[i].Y)
            if d < minD[i] then minD[i] = d end
        end
    end
    local accTxt = ""
    if hudAcc then
        local okA, tt = pcall(function() return hudAcc.Text end)
        if okA and tt then accTxt = tt else hudAcc = nil end
    end
    if cfg.debug and t - lastDbg > 0.6 then
        lastDbg = t
        local parts = {}
        for i = 1, n do parts[i] = minD[i] >= 1e9 and "-" or tostring(math.floor(minD[i])) end
        local held = {}
        for i = 1, n do held[i] = pressed[i] and "1" or "0" end
        print(("DBG spd=%.0f ms=%.0f pd=%.0f notes=%d d=[%s] held=[%s] acc=%s"):format(speed, cfg.ms, pressDist, #state.notes, table.concat(parts, ","), table.concat(held, ""), tostring(accTxt)))
    end
    local parts = {}
    for i = 1, n do parts[i] = minD[i] >= 1e9 and "-" or tostring(math.floor(minD[i])) end
    overlay.Text = ("AP21: %s%s side=%s ms=%.0f spd=%.0f | lanes %d notes %d | d[%s] | %s"):format(
        cfg.enabled and "ON" or "off", dupDetected and " DUP" or "", state.side, cfg.ms, speed, n, #state.notes, table.concat(parts, ","), accTxt)
    overlay.Visible = true
end)

local tabBuilt = false
UI.AddTab("Autoplayer21", function(tab)
    if not tabBuilt then
        tabBuilt = true
        local sec = tab:Section("Main", "left")
        sec:Toggle("ap21_enabled", "Enabled", false, function() end)
        sec:Keybind("ap21_kb", 0, "toggle")
        sec:SliderInt("ap21_ms", "Press ms early", 5, 150, 8, function() end)
        sec:SliderInt("ap21_comp", "Latency comp (ms)", 0, 40, 0, function() end)
        sec:SliderInt("ap21_slack", "Release slack (px)", 10, 400, 60, function() end)
        sec:Toggle("ap21_debug", "Debug prints", false, function() end)
        sec:Button("Release all", function() releaseAll() end)
        sec:Button("Test keys", function()
            task.spawn(function()
                local kl = state.keyList
                if #kl == 0 then kl = { "D", "F", "J", "K" } end
                for i = 1, #kl do
                    local c = codeOf[kl[i]]
                    if c then
                        keypress(c)
                        task.wait(0.04)
                        keyrelease(c)
                        task.wait(0.05)
                    end
                end
                print("KEY TEST done")
            end)
        end)
        pcall(function()
            if savedMs then UI.SetValue("ap21_ms", cfg.ms) end
            if savedComp then UI.SetValue("ap21_comp", cfg.comp) end
            if savedSlack then UI.SetValue("ap21_slack", cfg.slack) end
            if savedDbg ~= nil then UI.SetValue("ap21_debug", cfg.debug) end
        end)
    end
end)

task.spawn(function()
    local savedMs, savedSlack, savedDbg, savedComp = cfg.ms, cfg.slack, cfg.debug, cfg.comp
    local lastWidgetMs = nil
    while true do
        local ok, v = pcall(function() return UI.GetValue("ap21_enabled") end)
        if ok and type(v) == "boolean" then
            if v ~= cfg.enabled then print("ap21 toggle -> " .. tostring(v)) end
            cfg.enabled = v
        end
        local ok2, m = pcall(function() return UI.GetValue("ap21_ms") end)
        if ok2 and type(m) == "number" then
            if lastWidgetMs == nil then
                lastWidgetMs = m
            elseif m ~= lastWidgetMs then
                lastWidgetMs = m
                if m >= 5 then cfg.ms = m end
            end
        end
        local ok5, cp = pcall(function() return UI.GetValue("ap21_comp") end)
        if ok5 and type(cp) == "number" and cp >= 0 then cfg.comp = cp end
        local ok3, sl = pcall(function() return UI.GetValue("ap21_slack") end)
        if ok3 and type(sl) == "number" and sl >= 10 then cfg.slack = sl end
        local ok4, dbg = pcall(function() return UI.GetValue("ap21_debug") end)
        if ok4 and type(dbg) == "boolean" then cfg.debug = dbg end
        if cfg.ms ~= savedMs or cfg.slack ~= savedSlack or cfg.debug ~= savedDbg or cfg.comp ~= savedComp then
            savedMs, savedSlack, savedDbg, savedComp = cfg.ms, cfg.slack, cfg.debug, cfg.comp
            pcall(function()
                writefile("ap_settings.txt", ("return {ms=%d,slack=%d,debug=%s,comp=%d}"):format(
                    math.floor(savedMs), math.floor(savedSlack), tostring(savedDbg), math.floor(savedComp)))
            end)
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        if cfg.enabled and hudAcc then
            local okT, txt = pcall(function() return hudAcc.Text end)
            if okT and txt then
                local breaks = tonumber(txt:match("Combo Breaks:%s*(%d+)"))
                local rating = tonumber(txt:match("Rating:%s*(%d+%.?%d*)") or txt:match("Accuracy:%s*(%d+%.?%d*)"))
                if breaks then
                    if lastBreaks and tuneCooldown > 0 then
                        tuneCooldown = tuneCooldown - 1
                        if tuneCooldown == 0 then
                            if breaks > lastBreaks then
                                cfg.ms = math.min(cfg.ms + 5, 50)
                                tuneCooldown = 4
                                print(("AUTO ms->%d (breaks %d->%d)"):format(cfg.ms, lastBreaks, breaks))
                            elseif cfg.ms > 5 then
                                cfg.ms = cfg.ms - 2
                                tuneCooldown = 3
                                print(("AUTO ms->%d (clean)"):format(cfg.ms))
                            end
                        end
                    end
                    lastBreaks = breaks
                end
                if rating and lastBreaks and breaks <= lastBreaks then
                    if rating == lastRatingSeen then
                        rateStale = rateStale + 1
                    else
                        rateStale = 0
                    end
                    lastRatingSeen = rating
                    if rating >= 99.5 then
                        ratingBefore = nil
                        rateCooldown = 4
                    elseif rateStale >= 2 then
                        ratingBefore = rating
                        rateCooldown = 6
                    else
                        rateCooldown = rateCooldown - 1
                        if rateCooldown <= 0 then
                            if ratingBefore == nil then
                                ratingBefore = rating
                                cfg.ms = math.clamp(cfg.ms + ratingDir, 6, 40)
                                rateCooldown = 4
                                print(("RATE try ms->%d"):format(cfg.ms))
                            else
                                if rating < ratingBefore - 0.05 then
                                    ratingDir = -ratingDir
                                    cfg.ms = math.clamp(cfg.ms + ratingDir * 2, 6, 40)
                                    print(("RATE flip ms->%d (%.2f->%.2f)"):format(cfg.ms, ratingBefore, rating))
                                else
                                    cfg.ms = math.clamp(cfg.ms + ratingDir, 6, 40)
                                    print(("RATE ok ms->%d (%.2f->%.2f)"):format(cfg.ms, ratingBefore, rating))
                                end
                                ratingBefore = rating
                                rateCooldown = 4
                            end
                        end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local raw = readfile("ap_heartbeat.txt")
            if raw then
                local f, err = loadstring(raw)
                if f then
                    local ok, hb = pcall(f)
                    if ok and hb and type(hb) == "table" and hb.token and hb.token ~= beatToken and hb.last and tick() - hb.last < 2.5 then
                        if hb.birth and hb.birth < born then
                            -- the other copy is older; it yields, we keep going
                        else
                            -- we are the older/stale copy - yield
                            if not dupDetected then
                                dupDetected = true
                                releaseAll()
                                print("DUP INSTANCE detected - this is the OLDER copy, disabled (rejoin or load once).")
                            end
                        end
                    end
                end
            end
            if not dupDetected then
                writefile("ap_heartbeat.txt", ("return {token=%q,birth=%.3f,last=%.3f}"):format(beatToken, born, tick()))
            end
        end)
    end
end)

print("Autoplayer46 loaded - sustain end fix: chained pieces share the tail window, holdUntil tracks the live tail, releases only past the real end. Rejoin first to clear old versions")
