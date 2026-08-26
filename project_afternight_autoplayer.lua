-- Project Afternight autoplayer (Matcha)
-- Tab: Autoplayer21 | Toggle Enabled, then play. ms slider = press ms early.
-- v40: SUSTAIN HEAD FIX - sustain body pieces have DYNAMIC heights (the piece
--   shrinks/grows as it scrolls), so the EMA'd center minus half the current
--   height diverges from the true head position -> presses fired at wrong
--   times -> sustains missed "sometimes". Hold candidates now use the RAW head
--   (ln.p.Y - lineY); taps keep the EMA'd yE path.
-- v39: SUSTAIN MISS FIX - v38's unstable suppression (6 frames after an X jump
--   > 60px) blocked the FIRST press of a wobbling sustain (modchart sway): the
--   head crossing fell inside the suppression window -> sustain missed. Holds
--   (z.Y > holdH) are now exempt from the unstable guard in holdKeep and the
--   candidate scan; the used flag (one press per instance) still applies.
-- v38: PANIC FIX - when notes sit in positions they don't normally occupy
--   (modchart repositioning), the autoplayer used to panic: stale yE produced
--   garbage press distances (d=0..68 vs pdN~40) and re-detected sustain pieces
--   caused hold-press spam. Fix: per-note stability + usage flags in noteTrack -
--   an X jump > 60px/frame marks tk.unstable=6 (presses suppressed ~6 frames
--   until yE re-converges) and tk.used=true on first press prevents re-pressing
--   the same note instance (kills the hold spam); reinit clears all flags.
-- v37: POSITION-CHANGE MISSES. The v35 lane memory locked a note into its
--   remembered lane even when a modchart genuinely SWAPS it to another column
--   (margin maxX+80=230px > ~166px column spacing) -> the wrong lane key was
--   pressed -> miss. Now the lane reassigns with a DEBOUNCE: a note switching
--   toward the nearest strum must hold the new lane for 6+ frames (tk.sway
--   counter; reset on return to the remembered lane), while excursions farther
--   than maxX+80 switch immediately. Short wobble stays in lane; real lane
--   swaps follow the note.
-- v36: TUNER BLINDNESS FIX. The HUD accuracy label is recreated by the game mid-session
--   (observed as "failed to fetch text" for 40+ seconds in the 03:38 log); the cached
--   hudAcc reference now self-heals: every scan() re-verifies it (pcall Text read;
--   drop on failure) and re-finds it (HUD.Accuracy, else the first TextLabel whose text
--   contains "Breaks"), and the overlay/DBG read drops a dead reference immediately.
-- v35: MODCHART STABILITY. Per-address lane memory (noteTrack.lane): each note's
--   lane is remembered while its track lives and re-used while the note's X stays
--   within maxX+80 of the remembered strum, so drunk/wobble/reverse modcharts
--   can't flip a note between lanes frame-to-frame (re-assigned only on the
--   pool-reuse/teleport reinit). Notes with vy<=50 (stopped/reversed scroll) are
--   skipped by holds, press candidates and the successor-release scan until they
--   move again. Fast-section misses: the remaining negative-d presses are the
--   1-frame input-queue cost (~8ms at 120fps); bump the Latency comp slider 5-10.
-- v34: REVERT of v33. The task.delay-based tap scheduler is DEAD in Matcha:
--   the 02:57:11 log proved task.delay(delayMs) with delays ~14-24ms NEVER
--   fires its closure (only 0-delay tasks ran, pressing already-past notes).
--   Taps are back on the proven polling path (dual-form candidates, min-d,
--   1-frame gate, frame-travel successor lookahead) = the v32 state that
--   achieved 100% MFC on normal sections and ~97-98% on 5500px/s jacks
--   (Sick on dense entries is the polling architecture's ceiling).
-- v32: JACK QUEUE FIX. The successor-release lookahead was a fixed 40px;
--   at ~6000px/s one frame of travel is ~100px, so the 1-frame-queued press
--   landed ~60px past the line (negative-d presses, sub-Marvelous + breaks
--   in dense fast sections, e.g. the 02:49:58 log). Lookahead is now
--   frame-travel-aware: max(40, speed/60) so the queued press lands at d
--   ~= pdN at any scroll speed. (v31's ms=8/comp=0 timing was already
--   Marvelous-perfect on normal sections: 100% [MFC]/[WF]/[SDP], Combo 123,
--   zero breaks.)
-- v31: TUNER-GATING FIX. The per-song tuner and the tuner-state resets
--   (lastBreaks/ratingBefore/rateCooldown) ran on EVERY scan (0.25s), not just
--   at song starts: with a LIVE HUD the tuner compared mid-song ratings and
--   fired SONG flip/ms-> lines every few seconds (ms ping-ponged 8->18), and
--   the per-scan rateCooldown=0 reset destroyed the 4s RATE probe spacing
--   (RATE try lines every 1s). FIX: the SONG START block (print, per-song
--   tuner, resets) is now gated on the true !inSong transition, and the
--   out-of-song detection is DEBOUNCED (emptyScans - require 2 consecutive
--   scans with 0 strums before declaring the song over) so mid-song strum
--   flickers can no longer re-trigger it. ALSO: the +20ms queue/latency comp
--   OVERSHOT (v24 with no comp achieved 100% MFC; the +20 landed presses
--   ~18-20ms early = Good tier); comp is now cfg.comp default 0, exposed as
--   the ap21_comp slider (0-40) so it is off by default and tunable.
-- v30: QUEUE/LATENCY COMPENSATION + PARSER FIX. The v29 raw guard was a
--   regression: the 1-frame input queue delays presses ~16ms (~97px at 5800px/s),
--   pushing the note past the raw -10px guard -> the press never fired -> ~50%
--   misses in dense fast sections (log: every PRESS fired, breaks climbed to 17).
--   FIX: raw guard REMOVED; presses now fire with a +20ms compensation budget
--   (pdN = vy*(ms+20)/1000) so even a queue-delayed press lands on/near the line.
--   Also: the HUD acc text changed format ("Score:8490 | Combo Breaks:12 |
--   Accuracy:67.24% | (CLEAR)" - no spaces, "Accuracy:" instead of "Rating:"), so
--   the tuner parsers went blind; they now accept both formats (%s* tolerant).
-- v29: RANDOM-MISS FIX - the EMA-based lower bound (lowerB) alone lets presses
--   fire after the note's TRUE position already crossed the line: yE lags the
--   real position by ~0.43 frames of travel, so at high scroll speeds a press
--   at EMA-d=lowerB lands (after the ~17ms input latency) past the line and the
--   engine ignores it. Added a RAW guard: candidates must also satisfy
--   ln.c.Y - lineY >= -10 (raw center not past the line by >10px), so a press
--   can never fire after the note's true center crossed the line, regardless of
--   EMA lag or the 1-frame input queue.
-- v28: SUSTAIN FIX - the v26 5-frame re-press guard (holdGuard) was the
--   regression: it blocked the tap-sized HEAD note of a sustain from being
--   pressed in the 5 frames after the tall body piece was pressed and removed,
--   and the head press is what carries the sustain hit -> sustains skipped.
--   Guard REMOVED entirely; candidates are the v24 form (tall + head both
--   pressable, d = yE - z.Y/2 for holds) which was proven 100% MFC. The v25
--   "misses more often" was the stale-instance collision, not a sustain bug.
-- v27: single-instance heartbeat lock. Every 1s each running copy writes its
--   token+birth to C:/matcha/workspace/ap_heartbeat.txt. If another token with
--   a fresh (<2.5s) heartbeat is seen, the OLDER copy yields (releases all keys
--   and stops pressing, overlay shows DUP) while the newer copy keeps playing.
--   Fixes the recurring "misses sometimes" caused by stale autoplayer copies
--   colliding on the same keys (seen as 2 DBG lines per second and RATE lines
--   1s apart in the logs).
-- v26: restore tall sustain pieces as press candidates (some sustains have NO
--   separate head note - v25 skipped them and missed). The 5-frame re-press
--   guard (holdGuard) after every release kills the old hold->rel->head-press
--   flicker WITHOUT suppressing real taps. Climb floor raised 3 -> 6 so the
--   tuner cannot drift past the proven Marvelous zone on the late edge.
-- v25: mixed-sustain optimization. Sustains render as TWO ImageLabels: a tall
--   body piece (z.Y > holdH) plus a short tap-sized head note at the same X.
--   The body piece used to be pressed as kind="hold", the engine removes it
--   within a frame (holdKeep goes false) -> release, then the head got pressed
--   as a tap -> press/release/press flicker per sustain. FIX: body pieces are
--   EXCLUDED from press candidates (visual only - the head note carries the
--   hit; 100% MFC through sustain sections proved the engine never needed the
--   key held). Also: per-song tuner threshold 0.05 -> 0.15 and step 2 -> 1 to
--   stop the 8<->10 oscillation on rating noise.
-- v24: Marvelous hunting fix for the FROZEN HUD. The in-song accuracy text does
--   not update during a song (verified: "Rating: 98.41%" frozen while notes flow),
--   so the in-song climb went blind and ratcheted ms UP in the wrong direction.
--   FIX: (1) staleness guard - if the rating text is unchanged for 2+ probe
--   cycles the climb freezes instead of moving; (2) PER-SONG tuner - samples the
--   rating at each SONG START boundary (where the text finally refreshes) and
--   steps ms by 2 toward the direction that improved the rating, flipping when
--   it worsens (SONG ms-> / SONG flip lines); (3) climb starts at ratingDir = -1
--   (press LATER - the user's sicks come from early presses); (4) default ms
--   lowered 20 -> 8 (effective offset ~= ms + EMA-lag ~7ms + delivery ~17ms;
--   ms=8 lands ~18ms early = inside the Marvelous window vs ms=20 = ~30ms = Sick).
-- v23: the climb FREEZES while the rating reads 100% (ceiling) so it can no
-- longer run away upward on a perfect-but-frozen HUD; the probe band is
-- narrowed to 3-40ms; global speed clamp raised to 6000 to match per-note
-- velocity (release logic now consistent on ultra-fast scrolls); climb state
-- resets on each song start.
-- v22: MARVELOUS HUNTING - the auto-tuner now hill-climbs on the rating
-- ("Rating: X%" in the HUD): it probes ms +-1 every 4s in one direction and
-- flips when the rating drops, converging on the perfect press point instead
-- of settling for Sick. Combo Breaks still override (misses are worse than
-- sub-perfect ratings). Floor lowered to 5ms. ALSO FIXED: the 0.2s poller no
-- longer overwrites auto-tuned ms from the slider widget - it only writes when
-- the widget value actually changes (drag detection), so AUTO/RATE ms changes
-- survive until the user touches the slider.
-- v21: QOL - settings persist across reloads (readfile/writefile of
-- ap_settings.txt in the Matcha workspace: ms, slack, debug are saved on any
-- change and restored at load, then pushed into the UI sliders); a FOCUS
-- GUARD releases all keys when the game window loses focus (synthetic input
-- is dead unfocused and keys would stick); a "Test keys" button pulses every
-- lane key to verify the input pipeline without a song.
-- v20: MODCHART SUPPORT - speed now comes from PER-NOTE velocity tracking:
-- each note's Y is EMA-smoothed and its velocity EMA'd per-address, then the
-- global speed is the MEAN of all note velocities (camera shake is zero-mean
-- noise, so it cancels out of the mean instead of jittering speed like the old
-- front-note delta; scroll-speed change events adapt in ~2 frames because all
-- notes accelerate together). Presses use each note's OWN velocity
-- (pressDist = noteVy * ms) and its EMA'd position, so press timing is correct
-- in TIME at any scroll rate / during shake / during strum animation. Guards:
-- a note whose position teleports >120px or that vanishes >3 frames gets its
-- track re-initialized (note-pool reuse is safe).
-- v19: SCREEN-SHAKE ROBUSTNESS - the v16 speed SNAP copied shake jitter straight
-- into speed (huge + near-zero insts during a shake), collapsing pressDist to 6px
-- -> late presses -> accuracy tanks. Now speed comes from a position-EMA-smoothed
-- front note (shake is zero-mean so the EMA recovers the true trajectory; the
-- instS > 50 gate keeps speed frozen during freeze frames) and the receptor line
-- is EMA-smoothed per lane too, so presses track the TRUE hit line during shake.
-- v18: RE-PRESS FLUTTER FIX - v16 widened the candidate bound to -40px, but
-- lastPressed was still cleared at d < -15, so a note past the line but within
-- [-40,-15] got pressed -> released -> pressed forever (spam presses; the game's
-- anti-spam then eats real presses = "misses a lot" + "hits too early"). v18:
-- lowerB = -max(15, speed/60) (covers the 1-frame queue delay at any speed) and
-- lastPressed is kept until the note leaves that bound, so each note presses
-- exactly once. Also fixed the DBG print reading pressDist out of scope (moved
-- pressDist/lowerB above the enabled block) and capped auto-tune at 50ms.
-- v17: AUTO-CALIBRATION - reads the HUD "Combo Breaks" counter every second and
-- steers cfg.ms by itself: if breaks increase while enabled, presses are missing,
-- so it presses earlier (+5ms, cap 50). If the section is clean for a while it
-- eases back down toward the 20ms Sick default.
-- v16: candidate press bound widened to -40px (fast songs + 1-frame queue delay
-- could push a note past the old -15 bound before its press fired -> miss).
-- Speed now snaps instantly when the measured delta deviates >50% (scroll-speed
-- change events mid-song no longer cause a burst of misses while the filter lags).
-- v15: player strums identified by SIZE (z.Y > 130; player ~177-181 even mid-pulse
-- vs opponent ~115). v14's X-half split broke on the right side because the two
-- strum groups INTERLEAVE in X (opponent Strum3@670 sits between player Strum4@620
-- and Strum5@786), so halves mixed lanes and lane-1's timing used the opponent's
-- strum Y. Size grouping finds the player's strums regardless of side or interleave.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

pcall(function() setrobloxinput(true) end)

local codeOf = {
    D = 68, F = 70, J = 74, K = 75,
    Space = 32, L = 76, A = 65, S = 83, W = 87, E = 69, Z = 90, X = 88,
}

-- v13: time-based presses, default 20ms early. 55ms + ~17ms delivery latency
-- landed in the Good window; 20ms + latency ~= 37ms early = Sick.
local cfg = { enabled = false, ms = 8, comp = 0, slack = 60, maxX = 150, debug = false, holdH = 260, tailMargin = 60, keys = { "D", "F", "J", "K" } }
local EXTRA = { "Space", "L", "A", "S", "W", "E", "Z", "X" }

local state = { strums = {}, notes = {}, keyList = {}, inSong = false, side = "L" }
local pressed = {}
local downKind = {}
local pressAddr = {}
local holdUntil = {}
local lastPressed = {}
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
    lastPressed = {}
    lastRel = {}
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
                for _, ln in ipairs(laneNotes[i]) do
                    if ln.addr == lastPressed[i] then found = true; d = ln.yE - lineY end
                end
                if (not found) or d < lowerB or d > pressDist + cfg.slack then
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
                    local newHead = false
                    for _, ln in ipairs(laneNotes[i]) do
                        if ln.z.Y > cfg.holdH and not ln.used and ln.addr ~= pressAddr[i] and ln.vy > 50 then
                            local hd = ln.p.Y - lineY
                            if hd >= lowerB and hd <= pdN then
                                newHead = true
                            end
                        end
                    end
                    doRelease = newHead or (not holdKeep and (not holdUntil[i] or tick() > holdUntil[i]))
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
                    if pressAddr[i] then lastPressed[i] = pressAddr[i] end
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
                    if candKind == "hold" then
                        holdUntil[i] = tick() + math.max(0, cand.p.Y + cand.z.Y - lineY) / math.max(cand.vy, 50) + 0.15
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

print("Autoplayer42 loaded - double-sustain fix: holds get the successor-release (fresh edge for a second same-lane sustain). Rejoin first to clear old versions")
