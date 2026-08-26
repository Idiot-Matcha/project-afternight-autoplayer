# Project Afternight Autoplayer — Build & Debug Guide

How the script `project_afternight_autoplayer.lua` (v34) was created and made to work
in Matcha against Project Afternight (place 13042495892), a Psych-engine-style FNF
rhythm PvP game.

The short version: it reads the on-screen playfield (receptors + note images),
predicts each note's arrival at its receptor in **time**, and synthesizes real
keyboard input (D/F/J/K via Windows VK codes) so the game's own judgement pipeline
runs untouched. 34 versions were required — every version was one hypothesis.

---

## 1. Architecture of the final script (v34)

```
[scanner 0.25s]  finds strums + notes in PlayerGui.Main.Game
        |
[RenderStepped]  per-note tracking (yE/vy EMAs) -> speed estimate -> press band
        |            lane assignment by nearest strum X
        |            press/release decisions per lane
        |            heartbeat, focus guard, overlay, debug
        |
[auto-tune 1s]   Combo Breaks check + rating climb (per-song + in-song)
        |
[poller 0.2s]    UI sliders <-> cfg (drag detection) + settings persistence
```

- **Detection**: receptors are `ImageLabel`s named `Strum0`..`Strum7` directly under
  the fullscreen gameplay canvas `PlayerGui.Main.Game`. The player's four strums are
  the BIG ones (size.Y > 130 vs the opponent's ~115) — size, not screen half, decides
  the side. Sorted by X they become lanes 1-4.
- **Notes**: unnamed `ImageLabel`s (size.Y >= 100) parented directly to `Game`. They
  are POOLED — instances get reused across notes, so identity is unstable. The script
  never remembers a note between frames; it re-reads positions every frame and keys
  temporary state by the instance `Address` with staleness guards.
- **Sustains** are two images: a tall body piece (size.Y > 260) plus a tap-sized head
  at the same X. The head press carries the hit — the engine never needs the key held.
- **Timing**: press when the note's smoothed position is `pressDist = vy * ms / 1000`
  pixels before the line (ms default 8 = ~8ms early). `lowerB = -max(15, speed/60)`
  is the late edge of the band.
- **Speed** comes from each note's own velocity (yE/vy EMAs), averaged — this made
  the script immune to camera shake and modchart scroll changes.

---

## 2. Matcha gotchas (each one cost a version to learn)

1. **`setrobloxinput(true)` must be called once per session** before `keypress` works.
   It resets on Matcha restart / game rejoin. Without it, synthetic input is silently
   dropped. Every deployed script pcall's it at load.
2. **`keypress`/`keyrelease` take Windows VK codes as NUMBERS — not Roblox KeyCodes.**
   D=68, F=70, J=74, K=75, Space=32, L=76, A=65, S=83, W=87, E=69, Z=90, X=88.
   Using Roblox KeyCodes (D=100) sent Numpad4/6/*/+ — which are the game's volume
   keys. That's the bug where "the volume bar pops up and nothing presses".
3. **The Roblox window must be focused** — unfocused = zero events delivered.
   A focus guard (`isrbxactive()`) releases all keys when unfocused.
4. **Same-key press+release in the same frame = BOTH silently dropped** (proven by
   probes: `press;release` same frame -> 0 events; one frame apart -> all delivered).
   Cross-key same-frame is safe. Consequence: every lane has a 1-frame input queue —
   release one frame, press the next (`frameCnt > lastRel[i]`).
5. **`task.delay` is dead for 14-24ms delays in Matcha** — only 0-delay tasks fire.
   Sub-frame press scheduling is impossible; everything must poll at RenderStepped.
   (v33 tried a task.delay scheduler — nothing pressed; reverted.)
6. **The game's HUD accuracy text can be FROZEN during a song** (showing the previous
   song's result) or LIVE, and it has TWO formats (`"Score: 0 - Rating: 100% [MFC]..."`
   vs `"Score:0 | Combo Breaks:0 | Accuracy:100% | (MFC)"`). The tuners parse both and
   treat a frozen rating as stale (staleness guard) — a frozen rating must never move
   the press timing.
7. **UI library**: `UI.AddTab(name, fn)` — the fn runs every frame, so widgets are
   built once behind a `built` flag. Values via `UI.GetValue(id)` / `UI.SetValue(id)`.
8. **`readfile`/`writefile` are sandboxed to `C:/matcha/workspace`** — used for
   settings persistence and the heartbeat lock.

---

## 3. The timing evolution (what each big step changed)

| Version | Idea | Result |
|---|---|---|
| v1-4 | Fixed-pixel press window; discover input routing | Detection worked; nothing pressed until `setrobloxinput(true)` was found; then VK-vs-KeyCode bug |
| v5-7 | Press when note crosses the receptor | "Works, misses some notes"; jacks unreliable |
| v8 | Band logic (key held while any note in lane) | Holds perfect; **every jackhammer note after the first missed** (no fresh press edges) |
| v9-11 | Per-note press edges + input queue | Jacks fixed; found the same-frame drop rule |
| v12 | Time-based presses (`vy * ms / 1000`) | Timing constant at any scroll speed |
| v13-16 | Side detection (note-count, then size-threshold) | Right side works (strum halves interleave — size is the reliable signal) |
| v17 | Auto-calibration on Combo Breaks | Misses self-correct |
| v18-19 | Flutter fix (one press per note), shake-proof speed via EMA | Stable |
| v20 | Per-note velocity tracking | Modcharts/shake cancel out |
| v21 | QoL: persistence, focus guard, test-keys button | — |
| v22-24 | Marvelous hunting: rating climb, frozen-HUD staleness, ms=8 default | 100% [MFC] on normal sections |
| v25-28 | Sustain saga (see below) | Sustains hit reliably |
| v29-30 | Raw-position guard; +20ms comp | BOTH regressions — reverted |
| v31 | Tuner gating + out-of-song debounce | Fixed the real "tuner spam" bug |
| v32 | Frame-travel lookahead `max(40, speed/60)` | Late jacks improve |
| v33 | task.delay scheduler | Dead in Matcha — reverted |
| v34 | = v32 state, stable | The version you use |

---

## 4. The failed experiments (lessons, in order)

- **v8 band logic**: key held across a run — engine needs a press EDGE per note.
- **v26 holdGuard** (5-frame re-press lock): blocked the sustain's tap-sized head
  press after the tall body was pressed and removed by the engine → **sustains
  skipped**. The head press IS the hit. Removed.
- **v29 raw-position guard** (never press past the line): the 1-frame queue delays
  presses ~1 frame; at 5500px/s that's ~90px — the guard blocked those presses
  entirely → **~50% misses in fast sections**. Removed.
- **v30 +20ms latency comp**: pressed 18-20ms early → **Good tier instead of
  Marvelous** (the "sicks instead of marvelous" era). Reverted to comp=0.
- **v31 tuner misfire**: the per-song tuner and cooldown resets ran on EVERY 0.25s
  scan, not just at song starts — mid-song "SONG flip" spam and 1s-apart RATE probes
  while a live HUD changed every second → ms ping-ponged 8→18 and ratings dropped.
  Fixed by gating everything inside `if not state.inSong then` plus an
  `emptyScans >= 2` debounce so brief mid-song strum flickers don't end the song state.
- **v33 task.delay scheduler**: scheduled presses at 14-24ms never fired (only 0-delay
  closures ran) → **"it's not even pressing anything now"**. Reverted.

---

## 5. Stability systems

- **Heartbeat single-instance lock**: every copy writes `ap_heartbeat.txt`
  (token/birth/timestamp) once per second; an older copy that sees a fresher token
  disables itself (`dupDetected` + `releaseAll` + "DUP" in the overlay). This kills
  the recurring "two instances both pressing" bug (symptom: DBG/RATE lines interleaving
  ~1s apart, random misses) without forcing a rejoin.
- **lastPressed exclusion**: the note you just released can't be re-pressed; the
  exclusion clears when that note leaves the window, so pooled reuses stay safe.
- **Press gate**: `not pressed[i] and not dupDetected and frameCnt > lastRel[i]`
  — never presses on the same frame it released that key.
- **Release rules**: taps release on vanish / passed the line / a successor entering
  the window (lookahead `max(40, speed/60)`); holds release only when their tail
  passes (`holdKeep`).
- **Persistence**: ms/slack/debug/comp saved to `ap_settings.txt` on change and
  restored at load — plus poller drag-detection so auto-tuner changes survive until
  the user actually drags a slider.
- **Focus guard** releases all keys when the Roblox window loses focus.

---

## 6. The auto-tuners (why ms doesn't stay at 8 forever)

- **Per-song tuner**: at each real song start (debounced), it reads the rating text
  (which refreshes there), compares it to the previous song start, and steps `ms` by
  ±1 toward the better rating (0.15% threshold). Converges in ~4-8 songs.
- **In-song RATE climb**: while the HUD rating is live, it probes `ms` every 4s in one
  direction and flips when the rating drops; freezes at ≥99.5% and when the text is
  stale. Misses (Combo Breaks rising) take priority — ms jumps +5.
- ms is clamped 6-40. To override permanently, drag the ms slider — or set ms=8 in
  `C:\matcha\workspace\ap_settings.txt` and leave the tuners alone.

---

## 7. Usage

1. **Rejoin the game first** — this clears every stale script copy (the #1 cause of
   "misses").
2. Load `project_afternight_autoplayer.lua` from your scripts folder.
3. Enable on the **Autoplayer21** tab. Overlay shows `AP21: ON side=L ms=8 spd=... |
   lanes 4 notes N | d[...] | <HUD accuracy>`.
4. Sliders: **ms** (press ms early, 8 = Marvelous zone), **comp** (latency comp,
   leave 0), **slack** (release slack), **Debug** (prints SCHED/DBG lines), **Test
   keys** (pulses each lane key), **Release all**.
5. Expect ~100% MFC on normal sections; dense 5500px/s jacks may land a few Sick
   judgements — that's the 1-frame input-queue ceiling (halved at 120fps).

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "DUP" in overlay | Two copies running — rejoin, or the older copy auto-disables |
| Not pressing at all | Roblox unfocused, or `setrobloxinput` reset (rejoin/matcha restart) — reload the script |
| DBG/RATE lines ~1s apart, random misses | Stale second instance — rejoin |
| Volume bar pops up instead of pressing | VK codes not Roblox KeyCodes (historical bug, fixed since v5) |
| ms drifts on its own | The auto-tuners — working as designed; drag the slider to override |
| Right-side PvP broken | Player-2 keybinds were never captured (known limitation; solo always works) |

---

*Script file: `C:\matcha\scripts\project_afternight_autoplayer.lua` (v34, 724 lines)*
