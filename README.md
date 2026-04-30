# SyncAgent

A lightweight macOS menu bar utility that prevents your system from going idle by simulating human-like mouse movement and occasional app switching when you've been away from the keyboard.

## Features

- Human-like mouse movement: curved bezier paths, ease-in/out, micro-jitter, four movement styles
- Randomised activity timing — irregular gaps (15–50s) with occasional longer pauses, not robotic fixed intervals
- Independent toggles for mouse movement and window switching
- Configurable idle trigger threshold: 1, 2, or 5 minutes
- Active scheduler — restrict simulation to specific hours and days
- Toggle on/off from the menu bar
- Launch at login support
- No Dock icon — lives entirely in the menu bar

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools

## Build & Install

```bash
git clone https://github.com/easonclaw-lgtm/keepawake.git
cd keepawake
make install
```

This builds a release binary, assembles the `.app` bundle, copies it to `/Applications/`, and launches it.

## Permissions

On first launch, macOS will prompt for **Accessibility** permission. This is required for mouse movement simulation and keyboard event posting.

If the prompt doesn't appear automatically:
> System Settings → Privacy & Security → Accessibility → add SyncAgent

## Usage

Click the menu bar icon to access controls:

```
● SyncAgent: ON
──────────────
✓ Mouse Movement
✓ Window Switch
──────────────
Idle Trigger:
  ✓ 1 minute
    2 minutes
    5 minutes
──────────────
✓ Schedule
  Hours: 8am – 6pm  ▶
  Days: Workdays     ▶
──────────────
  Launch at Login
──────────────
  Quit              ⌘Q
```

- **SyncAgent: ON/OFF** — master enable/disable toggle
- **Mouse Movement** — enable or disable cursor movement simulation
- **Window Switch** — enable or disable Cmd+Tab app switching
- **Idle Trigger** — how long the system must be idle before simulation starts
- **Schedule** — restrict simulation to a time window and set of days
  - **Hours** — four presets: `8am–6pm` (default), `9am–5pm`, `7am–7pm`, `6am–8pm`
  - **Days** — `Workdays (Mon–Fri)` (default), `Every Day`, or pick individual days
- **Launch at Login** — register as a login item via macOS ServiceManagement

All settings persist across relaunches.

## How simulation works

**Sleep prevention** uses `ProcessInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled])` — the same OS-level mechanism used by `caffeinate`, Lungo, and Amphetamine. The assertion is acquired as soon as the idle threshold is crossed and released the moment the user returns. This is the reliable path; synthetic mouse events alone are not guaranteed to reset the system display sleep timer on all macOS versions.

**Mouse movement** uses `CGEvent(mouseType: .mouseMoved)` posted at `.cghidEventTap` (HID hardware level) for the visual human-like simulation on top.

Once the idle threshold is crossed, SyncAgent waits 3–8 seconds before the first action, then fires activity bursts at randomised intervals:

| Interval | Probability | Reason |
|---|---|---|
| 15–50 seconds | 90% | Normal idle fidgeting |
| 60–180 seconds | 10% | "Reading" or focused pause |

Each burst picks a movement style at random:

| Style | Weight | Distance | Description |
|---|---|---|---|
| Small twitch | 40% | 15–45 px | Hand at rest, minor readjust |
| Normal sweep | 40% | 80–180 px | Typical repositioning |
| Large sweep | 15% | 180–350 px | Moving to a different area |
| Double move | 5% | sweep + twitch | Reach, pause, then settle |

Window switching (Cmd+Tab) fires at 20% probability per burst, with a minimum of 2 bursts between switches, and only after the mouse has settled.

## Makefile Targets

| Target | Description |
|---|---|
| `make build` | Compile release binary |
| `make bundle` | Assemble `SyncAgent.app` with ad-hoc codesign |
| `make install` | Bundle + copy to `/Applications/` + launch |
| `make uninstall` | Kill process and remove from `/Applications/` |
| `make clean` | Remove `.build/` and local `SyncAgent.app` |

## Architecture

Built with Swift 6 + AppKit. No external dependencies.

| File | Role |
|---|---|
| `ActivitySimulator.swift` | Idle detection, burst timing, bezier animation, Cmd+Tab |
| `StatusBarController.swift` | Menu bar item, menu construction, all user actions |
| `PreferencesManager.swift` | UserDefaults persistence, schedule logic, SMAppService |
| `AppDelegate.swift` | App lifecycle, Accessibility permission prompt |
