# Deep Work Timer

A tiny macOS menu bar timer for deep work sessions. When a work session starts it
turns on a Focus mode and swaps your wallpaper; when the session ends (or you
stop, or the app quits) everything goes back.

- Countdown in the menu bar (work / break)
- Work → break cycle with a long break every N sessions (default 50 / 10 / 20, long break every 3)
- Sound + notification when a phase ends
- Today's session count and focus time
- Focus mode on/off via Shortcuts, custom or generated wallpaper
- Launch at login

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
| `DeepWorkTimerApp.swift` | App entry, menu bar label, quit cleanup |
| `TimerModel.swift` | Phases, countdown (end-date based, survives sleep), stats, alerts |
| `SessionEffects.swift` | Focus via Shortcuts, wallpaper swap/restore, default wallpaper |
| `MenuContentView.swift` | Popover UI and settings |
| `Prefs.swift` | UserDefaults keys and defaults |
