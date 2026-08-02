import Cocoa

// chatterfix — suppress keyboard chatter (spurious duplicate keypresses) on macOS.
//
// A chattering switch produces a key-down almost immediately after the key-up
// of the same key. Real typing (even fast double letters like "ll") leaves a
// larger gap. Any key-down that follows the previous key-up of the same key by
// less than the threshold is swallowed, along with its matching key-up.
// Auto-repeat events (holding a key) are flagged by the system and always pass.

let version = "1.0.0"

var thresholdMs: Double = 50
var dryRun = false
var verbose = false
var watchedKeys: Set<Int64>? = nil

var lastKeyUpMs: [Int64: Double] = [:]
var suppressNextUp = Set<Int64>()
var suppressedCount: [Int64: Int] = [:]
var totalSuppressed = 0
var eventTap: CFMachPort?
let startDate = Date()

let keyNames: [Int64: String] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c",
    9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 26: "7", 28: "8",
    25: "9", 29: "0", 24: "=", 27: "-", 30: "]", 31: "o", 32: "u", 33: "[",
    34: "i", 35: "p", 36: "return", 37: "l", 38: "j", 39: "'", 40: "k",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".",
    48: "tab", 49: "space", 50: "`", 51: "delete", 53: "escape",
    117: "forward-delete", 114: "help", 115: "home", 116: "pageup",
    119: "end", 121: "pagedown", 122: "f1", 120: "f2", 99: "f3", 118: "f4",
    96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10",
    103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15",
    123: "left", 124: "right", 125: "down", 126: "up",
    65: "keypad-.", 67: "keypad-*", 69: "keypad-+", 71: "keypad-clear",
    75: "keypad-/", 76: "keypad-enter", 78: "keypad--", 81: "keypad-=",
    82: "keypad-0", 83: "keypad-1", 84: "keypad-2", 85: "keypad-3",
    86: "keypad-4", 87: "keypad-5", 88: "keypad-6", 89: "keypad-7",
    91: "keypad-8", 92: "keypad-9",
]
let keyCodesByName: [String: Int64] = Dictionary(
    keyNames.map { ($0.value, $0.key) },
    uniquingKeysWith: { first, _ in first }
)

func keyName(_ code: Int64) -> String {
    keyNames[code] ?? "keycode-\(code)"
}

func nowMs() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}

let clockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

func log(_ message: String) {
    print("[\(clockFormatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

func printStats() {
    let minutes = Int(Date().timeIntervalSince(startDate) / 60)
    print("\n--- chatterfix stats (running \(minutes) min) ---")
    if suppressedCount.isEmpty {
        print("No chatter \(dryRun ? "detected" : "suppressed").")
    } else {
        for (code, count) in suppressedCount.sorted(by: { $0.value > $1.value }) {
            print("  \(keyName(code)): \(count)")
        }
        print("Total \(dryRun ? "detected" : "suppressed"): \(totalSuppressed)")
    }
}

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)

    // macOS disables taps it thinks are unresponsive; re-enable and move on.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    }
    guard type == .keyDown || type == .keyUp else { return pass }

    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if let watched = watchedKeys, !watched.contains(code) { return pass }
    let now = nowMs()

    if type == .keyDown {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat { return pass }
        if let lastUp = lastKeyUpMs[code] {
            let interval = now - lastUp
            if interval < thresholdMs {
                totalSuppressed += 1
                suppressedCount[code, default: 0] += 1
                let action = dryRun ? "would suppress" : "suppressed"
                log("\(action) chatter on '\(keyName(code))' " +
                    "(\(Int(interval)) ms after key-up, total \(totalSuppressed))")
                if dryRun { return pass }
                suppressNextUp.insert(code)
                return nil
            }
            if verbose {
                log("pass '\(keyName(code))' (\(Int(interval)) ms after key-up)")
            }
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

func printUsage() {
    print("""
    chatterfix \(version) — keyboard chatter (double keypress) filter for macOS

    Usage: chatterfix [options]

      --threshold <ms>   Suppress a key-down arriving within <ms> of the same
                         key's key-up. Default: 50. Higher catches more chatter
                         but risks eating fast intentional double letters.
      --keys <list>      Only filter these keys, e.g. --keys e,space,return
                         (default: all keys). Raw keycodes also accepted.
      --dry-run          Log what would be suppressed without blocking anything.
                         Use this to tune the threshold safely.
      --verbose          Also log passed key-downs with their up→down interval.
      --help             Show this help.

    Requires the Accessibility permission (System Settings → Privacy &
    Security → Accessibility). Press Ctrl+C to quit and print stats.
    """)
}

// --- Parse arguments ---
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--threshold":
        guard !args.isEmpty, let value = Double(args.removeFirst()), value > 0 else {
            print("error: --threshold needs a positive number of milliseconds")
            exit(1)
        }
        thresholdMs = value
    case "--keys":
        guard !args.isEmpty else {
            print("error: --keys needs a comma-separated list, e.g. --keys e,space")
            exit(1)
        }
        var codes = Set<Int64>()
        for name in args.removeFirst().split(separator: ",") {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            if let code = keyCodesByName[key] {
                codes.insert(code)
            } else if let code = Int64(key) {
                codes.insert(code)
            } else {
                print("error: unknown key '\(key)'")
                exit(1)
            }
        }
        watchedKeys = codes
    case "--dry-run":
        dryRun = true
    case "--verbose":
        verbose = true
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        print("error: unknown option '\(arg)'\n")
        printUsage()
        exit(1)
    }
}

// --- Check Accessibility permission (prompts the user if missing) ---
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
if !trusted {
    print("""
    chatterfix needs the Accessibility permission to filter key events.

    Grant it in: System Settings → Privacy & Security → Accessibility
    (If you run chatterfix from Terminal, grant it to Terminal; if it runs
    via launchd, grant it to the chatterfix binary itself.)

    Then run chatterfix again.
    """)
    exit(1)
}

// --- Create the event tap ---
let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: dryRun ? .listenOnly : .defaultTap,
    eventsOfInterest: mask,
    callback: tapCallback,
    userInfo: nil
)
guard let tap = eventTap else {
    print("""
    error: could not create the event tap.

    This usually means a missing permission. Check both Accessibility and
    Input Monitoring in System Settings → Privacy & Security, then retry.
    """)
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
for sig in [SIGINT, SIGTERM] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        printStats()
        exit(0)
    }
    source.resume()
    // Keep the source alive for the lifetime of the process.
    _ = Unmanaged.passRetained(source)
}

var scope = "all keys"
if let watched = watchedKeys {
    scope = watched.map(keyName).sorted().joined(separator: ", ")
}
log("chatterfix \(version) running — threshold \(Int(thresholdMs)) ms, " +
    "keys: \(scope)\(dryRun ? " [dry-run: logging only]" : "")")
log("Press Ctrl+C to quit and print stats.")

CFRunLoopRun()
