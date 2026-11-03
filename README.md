# Deep Work Timer

A tiny macOS menu bar timer for deep work sessions. When a work session starts it
turns on a Focus mode and swaps your wallpaper; when the session ends (or you
stop, or the app quits) everything goes back.

- Apple Clock–style design in white and red: a compact, horizontal popover
- A ring you drag to set session length; it drains as the session runs
- "What are you working on?" intention, logged with each session
- Work → break cycle with a long break every N sessions (default 50 / 10 / 20, long break every 3)
- ±5 min mid-session, pause, skip, stop
- When a session ends, the menu bar window opens on its own (with a sound) and your break waits for you to start it
- Today's focus time vs. a daily goal
- A standard macOS Settings window
- Focus mode on/off via Shortcuts, custom or generated wallpaper
- Launch at login

## Controls

In the popover: **Return** start · **Space** pause/resume · **+ / −** adjust 5 min ·
**⌘→** skip · **⌘.** cancel · **⌘,** settings.

From anywhere (Shortcuts, Raycast, Alfred, Terminal) via URL:

```bash
open "deepwork://start?minutes=50&intent=Write%20the%20doc"
open "deepwork://toggle"        # start, or pause/resume
open "deepwork://pause"         # also: resume, stop, skip
open "deepwork://add?minutes=10"   # also: subtract
open "deepwork://open"          # show the menu bar window
```

## Previewing the UI

`.build/release/DeepWorkTimer --preview` opens a window showing every state with real
Liquid Glass. `--snapshot ./snaps` renders every screen
to PNGs with sample data, then exits. Native text fields and menus show as placeholders.

## Build & run

Needs macOS 26+ (Liquid Glass) and the Xcode Command Line Tools (full Xcode not required).

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
The original wallpaper for each display is saved before anything changes and
restored afterwards: on stop, on quit, on `kill`, after a crash (on next launch), and
for a display unplugged mid-session (when it reconnects). A display whose current
wallpaper isn't a plain image file (e.g. a dynamic or aerial one) is left alone,
since it couldn't be put back exactly.

## Site blocking

Click the shield next to **Start**, or the "sites blocked" pill during a session, to pick what's blocked:
built-in categories (Social, Video, News, Shopping, Games, Sports, Chat), with any single site switched
off, plus your own categories and sites. Blocking runs only during focus sessions, not breaks.

How it works: blocked domains (plus their `www.`, `m.` and `mobile.` variants) go into a marked section
of `/etc/hosts` and come out when the session ends, or the next time the app launches if it was killed.
Editing `/etc/hosts` needs root, so **Set Up…** in the picker asks for your password once to install:

- `/usr/local/libexec/deepwork-block`, a root-owned script that only writes `0.0.0.0 <domain>` lines
  between its own markers (input is validated as domain names)
- `/etc/sudoers.d/deepworktimer`, letting your user run only that script without a password

To uninstall: `sudo rm /usr/local/libexec/deepwork-block /etc/sudoers.d/deepworktimer`.
Already-open tabs may keep working until reloaded, since browsers cache DNS briefly.

## Music

A now-playing strip in the menu bar window shows the current Spotify track with ⏮ ⏯ ⏭. In
Settings › Music you can have a session **resume music** or **play your focus playlist** (paste a
Spotify playlist or album link), and pause it when the session ends. Spotify is controlled with
AppleScript, so macOS asks once to let Deep Work Timer control Spotify. Choose **Any app** (or
without Spotify installed) and the buttons drive whatever is playing through macOS's media
controls instead, without track info.

## Layout

| File | What it does |
|---|---|
| `DeepWorkTimerApp.swift` | App entry, `deepwork://` commands |
| `TimerModel.swift` | Phases, countdown (end-date based, survives sleep), stats, alerts |
| `SessionEffects.swift` | Focus via Shortcuts, wallpaper swap/restore, default wallpaper |
| `MenuContentView.swift` | The popover |
| `SettingsView.swift` | Settings window |
| `Theme.swift`, `TimerRing.swift` | Colors, buttons, segmented control, the ring, menu bar icon |
| `MenuBarController.swift` | Menu bar item and its window (opens itself when a phase ends) |
| `Snapshot.swift` | `--snapshot` UI renderer |
| `Prefs.swift` | UserDefaults keys and defaults |
