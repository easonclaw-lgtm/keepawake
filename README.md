# SyncAgent

A lightweight macOS menu bar utility that prevents your system from going idle by simulating human-like mouse movement and occasional app switching when you've been away from the keyboard.

## Features

- Smooth, curved mouse movement with natural ease-in/out and micro-jitter
- Periodic Cmd+Tab app switching to register session activity
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

- **SyncAgent: ON/OFF** — enable or disable activity simulation
- **Idle Trigger** — how long to wait before simulating activity
- **Schedule** — restrict simulation to a time window and set of days
  - **Hours** — choose from four presets: `8am–6pm` (default), `9am–5pm`, `7am–7pm`, `6am–8pm`
  - **Days** — `Workdays (Mon–Fri)` (default), `Every Day`, or pick individual days
- **Launch at Login** — register as a login item via macOS ServiceManagement

All settings persist across relaunches.

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
| `ActivitySimulator.swift` | Idle detection, bezier mouse animation, Cmd+Tab |
| `StatusBarController.swift` | Menu bar item and menu construction |
| `PreferencesManager.swift` | UserDefaults persistence, SMAppService login item |
| `AppDelegate.swift` | App lifecycle, Accessibility permission prompt |
