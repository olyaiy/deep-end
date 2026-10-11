# Deep Work Timer

A tiny macOS menu bar timer for deep work sessions. When a work session starts it
turns on a Focus mode and swaps your wallpaper; when the session ends (or you
stop, or the app quits) everything goes back.

- Progress ring + countdown in the menu bar; a dial you drag to set session length
- "What will you focus on?" intention, logged with each session
- Work → break cycle with a long break every N sessions (default 50 / 10 / 20, long break every 3)
- ±5 min mid-session, pause, skip, stop
- A floating banner + sound when a phase ends (works even when Focus silences notifications)
- Today's focus time vs. a daily goal, a 7-day chart, and a session log
- Focus mode on/off via Shortcuts, custom or generated wallpaper
- Launch at login

## Controls

In the popover: **Return** start · **Space** pause/resume · **+ / −** adjust 5 min ·
**⌘→** skip · **⌘.** stop · **⌘,** settings.

From anywhere (Shortcuts, Raycast, Alfred, Terminal) via URL:

```bash
open "deepwork://start?minutes=50&intent=Write%20the%20doc"
open "deepwork://toggle"        # start, or pause/resume
open "deepwork://pause"         # also: resume, stop, skip
open "deepwork://add?minutes=10"   # also: subtract
```

## Previewing the UI

`.build/release/DeepWorkTimer --snapshot ./snaps` renders every screen (light and dark)
to PNGs with sample data, then exits. Native text fields and menus show as placeholders.

## Build & run

Needs macOS 14+ and the Xcode Command Line Tools (full Xcode not required).

```bash
./build.sh
```

That builds `Deep Work Timer.app`, installs it to `~/Applications`, and launches
it. Re-run after any change. `./build.sh --no-install` only builds into `./build`.

## Setting up the Focus mode

macOS has no public API for Focus, so the app runs two Shortcuts by name. Create
them once in the Shortcuts app:

1. **Deep Work On**: add a **Set Focus** action → *Turn* your Focus (e.g. "Deep Work" or "Do Not Disturb") *On* → *Until Turned Off*.
2. **Deep Work Off**: add a **Set Focus** action → *Turn* the same Focus *Off*.

You can pick different shortcuts (or None) in the app's settings. Settings shows a
warning if a selected shortcut doesn't exist.

## Wallpaper

During work sessions the wallpaper switches to the image you choose in settings,
or a generated dark one (stored in `~/Library/Application Support/DeepWorkTimer`).
The original wallpaper for each display is saved and restored afterwards, even
after a crash (it's restored on next launch).

Known limitation: if your normal wallpaper is a dynamic or aerial one, restoring it
may land on a still version of it.

## Layout

| File | What it does |
|---|---|
| `DeepWorkTimerApp.swift` | App entry, menu bar label, `deepwork://` commands |
| `TimerModel.swift` | Phases, countdown (end-date based, survives sleep), stats, alerts |
| `SessionEffects.swift` | Focus via Shortcuts, wallpaper swap/restore, default wallpaper |
| `MenuContentView.swift` | Timer screen and today card |
| `SettingsView.swift` | Settings screen |
| `Theme.swift`, `Dial.swift` | Colors, button/toggle styles, the dial, menu bar icon |
| `Toast.swift` | Floating banner when a phase ends |
| `Snapshot.swift` | `--snapshot` UI renderer |
| `Prefs.swift` | UserDefaults keys and defaults |
