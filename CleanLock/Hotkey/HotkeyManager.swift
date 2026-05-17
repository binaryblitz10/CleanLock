import AppKit
import Carbon.HIToolbox
import os.log

/// Global hotkey registered through Carbon's RegisterEventHotKey API — the
/// supported native path for system-wide shortcuts on macOS. It works even
/// when the app is unfocused and does not require Accessibility access.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x434C4E4C /* 'CLNL' */), id: 1)

    private let log = OSLog(subsystem: "com.cleanlock.app", category: "Hotkey")

    private init() {}

    func registerStoredHotkey() {
        let stored = Preferences.shared.hotkey

        // Don't register if no keyCode is set (avoids accessibility prompts)
        guard stored.keyCode != 0 else {
            unregister()
            os_log("No hotkey set, skipping registration", log: log, type: .info)
            return
        }

        let ok = register(keyCode: stored.keyCode, modifiers: stored.carbonModifiers)
        if !ok {
            os_log("Failed to register stored hotkey (keyCode=%d, modifiers=0x%x)",
                   log: log, type: .error, stored.keyCode, stored.carbonModifiers)
        } else {
            os_log("Registered hotkey (keyCode=%d, modifiers=0x%x)",
                   log: log, type: .info, stored.keyCode, stored.carbonModifiers)
        }
    }

    /// Replaces any existing registration. Returns true on success.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        // Don't register if no keyCode is set
        guard keyCode != 0 && modifiers != 0 else {
            return true // Consider this successful (no-op)
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let eventRef = eventRef, let userData = userData else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        manager.onTrigger?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            os_log("InstallEventHandler failed with status %d", log: log, type: .error, installStatus)
            return false
        }

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            os_log("RegisterEventHotKey failed with status %d", log: log, type: .error, status)
        }
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
