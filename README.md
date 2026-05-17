# CleanLock

A small native macOS utility that disables your keyboard and trackpad so you can clean your MacBook without triggering accidental input.

![macOS 13.0+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

<!-- Screenshots -->
<!-- TODO: Add screenshots -->
<!-- ![CleanLock launcher](screenshots/launcher.png) -->
<!-- ![Cleaning mode overlay](screenshots/overlay.png) -->
<!-- ![Settings](screenshots/settings.png) -->

---

## Features

- Disables keyboard and trackpad at the system level
- Full-screen overlay with clear exit instructions
- Two modes: persistent menu bar app or ephemeral one-shot launcher
- Configurable activation hotkey and auto-unlock timeout
- Native Swift + AppKit — no Electron, no helper daemons, no background services
- Fail-safe: if CleanLock crashes or is force-quit, input is restored automatically by the OS

## Installation

1. Download `CleanLock.zip` from the [latest release](../../releases/latest)
2. Unzip and move `CleanLock.app` to your `/Applications` folder
3. **First launch:** right-click the app → **Open** (required once to bypass Gatekeeper — the app is not signed with an Apple Developer certificate)
4. Grant **Accessibility** permission when prompted in System Settings

## Usage

### Persistent mode (default)

CleanLock sits in your menu bar as a `⌨` icon.

1. Click the icon → **Start Cleaning Mode**, or press the configured hotkey (`⌃⇧⌘K` by default)
2. The screen goes black — your keyboard and trackpad are now disabled
3. Wipe down your Mac
4. **To exit:** hold both left and right `⌘` keys simultaneously for 3 seconds

### Ephemeral mode

Launches directly into Cleaning Mode and quits automatically when done — no persistent menu bar icon.

Switch between modes in **Settings** (`⌘,`).

## Settings

- **Startup behavior** — persistent menu bar app or ephemeral launcher
- **Activation hotkey** — customizable key combo
- **Auto-unlock timeout** — automatically exit after a set time (1, 3, 5, 10, or 30 minutes; or disabled)
- **Launch at Login** — start CleanLock automatically on login

## Permissions

CleanLock requires only one permission:

- **Accessibility** — needed to install a system-level input event tap

It does not request Input Monitoring, Screen Recording, or any other permission.

## Build from Source

```sh
brew install xcodegen
git clone https://github.com/binaryblitz10/CleanLock.git
cd CleanLock
xcodegen generate
open CleanLock.xcodeproj
```

Build and run with `⌘R`. Grant Accessibility permission when prompted, then quit and relaunch.

## License

MIT — see [LICENSE](LICENSE).
