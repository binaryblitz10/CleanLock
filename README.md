# CleanLock

A small native macOS utility that disables your keyboard and trackpad so you can clean your MacBook without triggering accidental input.

![macOS 15.0+](https://img.shields.io/badge/macOS-15.0%2B-blue) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## Features

- Disables keyboard and trackpad at the system level
- Full-screen overlay with clear exit instructions
- Two modes: persistent menu bar app or launcher mode
- Configurable activation hotkey and auto-unlock timeout
- Native Swift + AppKit — no Electron, no helper daemons, no background services

## Installation

1. Download `CleanLock.zip` from the [latest release](../../releases/latest)
2. Unzip and move `CleanLock.app` to your `/Applications` folder
3. **First launch:** Required once to bypass Gatekeeper, since the app is not signed with an Apple Developer certificate.
4. Grant **Accessibility** permission when prompted in System Settings

## Permissions

CleanLock requires only one permission:

- **Accessibility** — needed to install a system-level input event tap

## License

MIT — see [LICENSE](LICENSE).
