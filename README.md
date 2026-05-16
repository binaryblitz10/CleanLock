# CleanLock

A native macOS menu-bar utility that temporarily disables your keyboard and trackpad so you can clean your MacBook without triggering accidental input.

- Native Swift + AppKit. No Electron, no webview, no helper daemons.
- Single foreground process. CGEventTap is auto-cleaned by the kernel on process death — no persistent kernel state, no risk of staying locked across a crash.
- Fail-safe by design: any uncertainty unlocks input rather than trapping the user.

---

## Build instructions

The repo ships source files and an [XcodeGen](https://github.com/yonaskolb/XcodeGen) project spec (`project.yml`). XcodeGen generates a deterministic `.xcodeproj` from the spec — this avoids the fragility of a hand-edited `project.pbxproj`.

### Option A — XcodeGen (recommended)

```sh
brew install xcodegen
cd CleanLock
xcodegen generate
open CleanLock.xcodeproj
```

In Xcode, set your signing team if you want to distribute. For local use the default `-` (ad-hoc) signing is fine. Build & run with ⌘R.

### Option B — Manual Xcode setup

1. In Xcode: **File → New → Project → macOS → App**, choose `CleanLock`, language Swift, interface AppKit, no Core Data, no tests.
2. Delete the auto-generated `AppDelegate.swift`, `ViewController.swift`, `Main.storyboard`, and any `@main` `App.swift`.
3. Drag the `CleanLock/` folder from this repo into the project (copy if needed). Make sure all `.swift` files are added to the `CleanLock` target.
4. In **Build Settings**, set:
   - `INFOPLIST_KEY_LSUIElement` (or in Info.plist: `Application is agent (UIElement)` = YES)
   - `ENABLE_APP_SANDBOX` = NO (sandboxed apps cannot install HID event taps)
   - macOS Deployment Target ≥ 13.0
5. Link `Carbon.framework` (for the global hotkey), `AppKit`, `ApplicationServices`, `IOKit`.
6. Build & run.

The first run will prompt for **Accessibility** permission. Grant it in **System Settings → Privacy & Security → Accessibility**, then quit and relaunch.

---

## Usage

1. Click the menu-bar `⌨` icon → **Start Cleaning Mode** (or press the configured hotkey, default `⌃⇧⌘K`).
2. The screen goes black with the message:

   > **Cleaning Mode**
   >
   > Your keyboard and mouse are disabled.
   > Press the Command (⌘) key 6 times to exit.

3. Wipe down your keyboard / trackpad. Input is consumed at the HID event-tap level.
4. To exit: press **Command six times** within ~3 s per press.

Settings (`⌘,` from the menu) let you change the hotkey, auto-unlock timeout, and launch-at-login.

---

## Architecture

```
CleanLock/
├── App/                 AppDelegate, NSApplicationMain entry
├── MenuBar/             NSStatusItem + menu
├── Cleaning/            CleaningModeManager — state machine
├── Events/              EventInterceptor — CGEventTap
├── Overlay/             OverlayWindowController — full-screen black window
├── Safety/              SafetyManager — sleep/wake, signals, exceptions
├── Hotkey/              HotkeyManager — Carbon RegisterEventHotKey
├── Permissions/         Accessibility check + prompt
├── Settings/            Preferences + minimal AppKit settings window
├── Info.plist
└── CleanLock.entitlements
```

State machine (`CleaningModeManager`):

```
   idle ──activate──▶ activating ──▶ active
    ▲                                  │
    │                                  ▼
   idle ◀──teardown── deactivating ◀──┘
                          ▲
                       failed
```

Transitions only happen on the main thread, gated by the current state — double activation and concurrent teardown are impossible.

---

## Event interception decisions

CleanLock installs a single `kCGHIDEventTap` at `headInsertEventTap` with the default (active) tap option. The tap callback returns `nil` for every event, with one exception: `flagsChanged` events also drive the **6× Command** unlock counter.

- **Why `kCGHIDEventTap`**: it sees events before the WindowServer and most system shortcuts (Cmd-Tab, Mission Control gestures, media keys via system-defined events, brightness, Spotlight). The session-level tap would miss many of these.
- **Why `defaultTap` rather than listen-only**: returning `nil` actually consumes the event. Listen-only cannot block input.
- **Why catch all event types (`CGEventMask(UInt64.max)`)**: simpler and more robust than enumerating types. Avoids gaps when new event types are added.
- **Why count Command from `flagsChanged` only**: discrete press detection (off→on transition) inherently filters key repeat and held keys. No timers, no polling.
- **Why exit on `tapDisabledByTimeout` / `tapDisabledByUserInput`**: when the tap is invalidated by the system, re-enabling it is brittle. Bailing out is the safe choice.

### Known limitations (intentional)

- **Power button & Touch ID** are hardware-handled by SMC/Secure Enclave and cannot be intercepted by user-space code. Pressing them will sleep or lock the Mac — which CleanLock then treats as a "safe wake" and automatically deactivates.
- **Force Quit (`⌘⌥⎋`)** is intercepted by WindowServer at a layer above HID taps on some macOS versions. We block what we can; we do not try to defeat this.
- **`fn` globe key Dictation toggle** on Apple Silicon laptops can sometimes briefly surface UI before the tap consumes it. We do not work around this with private APIs.
- **External keyboards / mice** are intercepted (HID tap sees them) but if Bluetooth disconnects mid-cleaning the device's own buttons obviously aren't going through us.

---

## Fail-safe behavior

CleanLock prioritises user safety over aggressive locking. It deactivates immediately on:

| Condition | Trigger |
|---|---|
| System will sleep | `NSWorkspace.willSleepNotification` |
| Lid close | Triggers sleep notification |
| Screen lock | `com.apple.screenIsLocked` distributed notification |
| Display reconfiguration | `NSApplication.didChangeScreenParametersNotification` |
| Event tap invalidated | `kCGEventTapDisabledByTimeout` / `…ByUserInput` callback |
| Auto-unlock timeout | Default 5 minutes (configurable; can be disabled) |
| Uncaught Obj-C exception | `NSSetUncaughtExceptionHandler` |
| App termination | `applicationWillTerminate` |
| Process crash / `SIGSEGV` / `SIGTERM` | Signal handler re-raises after marking tap for teardown; kernel cleans up the event tap when the process exits |

Because the event tap and overlay live entirely inside this single process, **if CleanLock dies in any way, input is restored automatically by the OS**. There is no helper daemon, no LaunchAgent, no kext, no persistent system state to leak.

---

## Permissions

Required:

- **Accessibility** (`AXIsProcessTrusted`) — needed to install an HID event tap.

Not required:

- ❌ Input Monitoring — HID taps installed with Accessibility do not need this. We avoid prompting for it.
- ❌ Screen Recording — overlay rendering is our own NSWindow.
- ❌ Full Disk Access, Camera, Microphone, etc.

Sandboxing is **disabled** (`com.apple.security.app-sandbox = false`) because sandboxed apps cannot install HID event taps. This is the standard configuration for utility apps like Karabiner, Hammerspoon, etc.

---

## Testing checklist

Manual test plan (see source comments where relevant):

- [ ] Activate via menu — overlay appears, input ignored.
- [ ] Activate via global hotkey while another app is focused.
- [ ] Press Cmd six times → unlocks. Press Cmd five times, wait 4 s, press once → does **not** unlock (counter resets).
- [ ] Hold Cmd — counts as a single press (no auto-repeat).
- [ ] While active, attempt `⌘⇥`, `⌘Space`, F-row brightness/volume, Mission Control swipe — all consumed.
- [ ] Close lid → wake — app is unlocked, no stuck overlay.
- [ ] Plug/unplug external keyboard — still locked, no crash.
- [ ] Plug/unplug external display — automatically deactivates.
- [ ] Revoke Accessibility while running — next activation shows the prompt; no silent failure.
- [ ] `kill -9 CleanLock` while active — input restored within ~1 s.
- [ ] Auto-unlock timeout fires correctly.
- [ ] Rapid toggle via hotkey — no double activation, no leaks (Activity Monitor stays flat).

---

## Performance notes

- Idle: no timers, no polling, no run-loop sources except those NSApplication creates by default. CPU stays at ~0%.
- Active: one CFRunLoopSource for the event tap; callback work is allocation-free except for the Cmd-press dispatch.
- Memory footprint: a few MB. The overlay is a single NSWindow with two NSTextFields.
- Activation latency: dominated by `CGEvent.tapCreate` (sub-millisecond on modern Macs). Overlay shows first so users see immediate feedback.

---

## License

MIT — do what you want, no warranty.
