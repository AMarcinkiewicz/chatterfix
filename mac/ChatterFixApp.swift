import Cocoa
import ServiceManagement

// ChatterFix — menu bar app that suppresses keyboard chatter (spurious
// duplicate keypresses) on macOS.
//
// A chattering switch produces a key-down almost immediately after the key-up
// of the same key. Real typing (even fast double letters like "ll") leaves a
// larger gap. Any key-down that follows the previous key-up of the same key by
// less than the threshold is swallowed, along with its matching key-up.
// Auto-repeat events (holding a key) are flagged by the system and always pass.

// MARK: - Filtering engine (globals: the C tap callback cannot capture context)

var thresholdMs: Double = 50
var paused = false
var lastKeyUpMs: [Int64: Double] = [:]
var suppressNextUp = Set<Int64>()
var suppressedCount: [Int64: Int] = [:]
var totalSuppressed = 0
var eventTap: CFMachPort?

let keyNames: [Int64: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
    9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 26: "7", 28: "8",
    25: "9", 29: "0", 24: "=", 27: "-", 30: "]", 31: "O", 32: "U", 33: "[",
    34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
    48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape",
    117: "Forward Delete", 114: "Help", 115: "Home", 116: "Page Up",
    119: "End", 121: "Page Down", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
    96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
    103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
]

func keyName(_ code: Int64) -> String {
    keyNames[code] ?? "Key \(code)"
}

func nowMs() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)

    // macOS disables taps it thinks are unresponsive; re-enable and move on.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap, !paused { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    }
    guard type == .keyDown || type == .keyUp else { return pass }

    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let now = nowMs()

    if type == .keyDown {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat { return pass }
        if let lastUp = lastKeyUpMs[code], now - lastUp < thresholdMs {
            totalSuppressed += 1
            suppressedCount[code, default: 0] += 1
            suppressNextUp.insert(code)
            return nil
        }
        return pass
    }

    // keyUp: if we swallowed the down, swallow the matching up too, and keep
    // the original key-up time as the chatter reference point.
    if suppressNextUp.remove(code) != nil {
        return nil
    }
    lastKeyUpMs[code] = now
    return pass
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var permissionTimer: Timer?

    private let thresholdOptions: [(Double, String)] = [
        (30, "Gentle (30 ms)"),
        (40, "Moderate (40 ms)"),
        (50, "Standard (50 ms)"),
        (65, "Strong (65 ms)"),
        (80, "Maximum (80 ms)"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = UserDefaults.standard.object(forKey: "thresholdMs") as? Double {
            thresholdMs = saved
        }
        enableLoginItemOnFirstRun()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = NSImage(systemSymbolName: "keyboard",
                                  accessibilityDescription: "ChatterFix") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "⌨"
            }
        }
        menu.delegate = self
        statusItem.menu = menu

        // Prompts the system permission dialog on first launch; once the user
        // grants Accessibility, the timer notices and filtering starts without
        // needing a relaunch.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            startTap()
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
                [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.permissionTimer = nil
                    self?.startTap()
                }
            }
        }
    }

    private func startTap() {
        let mask = CGEventMask(
            1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        )
        guard let tap = eventTap else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "ChatterFix can't monitor the keyboard"
            alert.informativeText = """
                Please make sure ChatterFix is enabled under System Settings → \
                Privacy & Security → Accessibility (and Input Monitoring, if \
                listed there), then quit and reopen ChatterFix.
                """
            alert.runModal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Rebuild the menu every time it opens so the counts are live.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if eventTap == nil {
            status = "Waiting for permission…"
        } else if paused {
            status = "Paused"
        } else if totalSuppressed == 0 {
            status = "On — no chatter yet"
        } else {
            status = "On — \(totalSuppressed) double-press\(totalSuppressed == 1 ? "" : "es") blocked"
        }
        menu.addItem(NSMenuItem(title: "ChatterFix: \(status)", action: nil, keyEquivalent: ""))

        if eventTap == nil {
            addItem("Open Accessibility Settings…", #selector(openAccessibilitySettings))
        } else {
            addItem(paused ? "Resume Filtering" : "Pause Filtering", #selector(togglePause))
        }
        menu.addItem(.separator())

        let sensitivityMenu = NSMenu()
        for (ms, label) in thresholdOptions {
            let item = NSMenuItem(title: label, action: #selector(setThreshold(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = ms
            item.state = thresholdMs == ms ? .on : .off
            sensitivityMenu.addItem(item)
        }
        let sensitivity = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        menu.addItem(sensitivity)
        menu.setSubmenu(sensitivityMenu, for: sensitivity)

        let statsMenu = NSMenu()
        if suppressedCount.isEmpty {
            statsMenu.addItem(NSMenuItem(title: "No chatter detected yet",
                                         action: nil, keyEquivalent: ""))
        } else {
            for (code, count) in suppressedCount.sorted(by: { $0.value > $1.value }) {
                statsMenu.addItem(NSMenuItem(title: "\(keyName(code)) — \(count)×",
                                             action: nil, keyEquivalent: ""))
            }
        }
        let stats = NSMenuItem(title: "Blocked Keys", action: nil, keyEquivalent: "")
        menu.addItem(stats)
        menu.setSubmenu(statsMenu, for: stats)

        menu.addItem(.separator())
        let login = addItem("Start at Login", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        addItem("Quit ChatterFix", #selector(quit))
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func togglePause() {
        paused.toggle()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: !paused)
        }
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        guard let ms = sender.representedObject as? Double else { return }
        thresholdMs = ms
        UserDefaults.standard.set(ms, forKey: "thresholdMs")
    }

    // Start at Login is on by default, but only ever set once. The marker is
    // written on success rather than on attempt, which gives two things: a user
    // who turns it off is never overridden on the next launch, and a first run
    // where registration failed is retried instead of silently losing it.
    //
    // "thresholdMs" cannot serve as the marker: it is written only when the
    // sensitivity is changed, so anyone leaving it at the default would look
    // like a first run forever and have the setting forced back on every time.
    private func enableLoginItemOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didDefaultLoginItem") else { return }

        // Registration records wherever the bundle currently sits, so doing it
        // while running from the mounted .dmg would point login at a path that
        // is gone by the next boot. Leave the marker unset so it applies once
        // the app has been dragged to Applications.
        guard !Bundle.main.bundlePath.hasPrefix("/Volumes/") else { return }

        let service = SMAppService.mainApp
        guard service.status != .enabled else {
            defaults.set(true, forKey: "didDefaultLoginItem")
            return
        }
        do {
            try service.register()
            defaults.set(true, forKey: "didDefaultLoginItem")
        } catch {
            // Deliberately silent. This runs seconds after Gatekeeper has
            // already accused the app of being malware, and an error dialog
            // about a convenience setting would land badly. The menu item still
            // reflects the real state and can be switched on by hand.
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
