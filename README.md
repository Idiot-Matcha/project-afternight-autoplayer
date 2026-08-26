# Project Afternight Autoplayer

A Matcha (Roblox executor) autoplayer for the Project Afternight rhythm game (place 13042495892).

## Files
- `project_afternight_autoplayer.lua` — the autoplayer script (load from the Matcha scripts folder)
- `project_afternight_autoplayer_GUIDE.md` — full build/debug history and usage guide

## Usage
1. Rejoin the game first (clears stale script instances).
2. Load `project_afternight_autoplayer.lua` from the Matcha scripts panel.
3. Use the **Autoplayer21** tab: toggle Enabled, adjust ms (press earliness, default 8), comp (latency compensation, 0-40), Debug, Release all, Test keys.
4. Play — expect 100% [MFC]/[WF]/[SDP] on normal sections.

## Features
- Size-based player-side detection (works both sides, left/right)
- Per-note velocity tracking (EMA) — handles scroll-speed changes, shakes, modcharts
- Debounced lane memory — notes keep their lane through wobble, follow real lane swaps
- Unstable-note suppression + one-press-per-note guards
- Sustain handling: head press + key held through the body to the tail, successor-release for double sustains
- 1-frame input queue (Matcha same-key same-frame press+release drops)
- Auto-tuners: per-song rating sampling, in-song RATE climb, Combo Breaks priority
- Heartbeat single-instance lock, settings persistence, focus guard, on-screen status overlay

## Matcha requirements
- `setrobloxinput(true)` must run once per session (the script does it at load)
- Game window must be focused for synthetic input
- VK codes are used (D=68, F=70, J=74, K=75)
