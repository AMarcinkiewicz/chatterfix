import Cocoa
import CryptoKit

// Update checker for ChatterFix.
//
// Fetches a small signed manifest from chatterfix.app, and if it advertises a
// newer version offers to install it. The manifest is signed with a key held
// offline; the matching public key is compiled in below. Nothing is installed
// unless both the signature over the manifest and the SHA-256 of the downloaded
// disk image match, because ChatterFix runs with Accessibility permission and a
// spoofed update would be a keylogger.

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
    as? String ?? "0"

private let appcastURL = URL(string: "https://chatterfix.app/appcast.json")!

// RSA-2048 public key (PKCS#1 DER, base64). Pairs with ~/.chatterfix/release_private.pem.
private let publicKeyB64 = """
MIIBCgKCAQEA0bYycxxWZE0puOiWEyyXd/FM2KMsGE9/1WrRDPeFYC8SJ2wa2iHcgugbcohvdXEK\
iYWXwILnVQRexy/o4dRQWR+M/e/mJOBaqQV0MdTnbDthkV+sSxcSwSj7Cct1ZLWIxOk1IVmEyl47\
UuniQcrfJCfsANbXQviiOTQGsSw7uHp9x+0lTmkghKdigih+Qc+yuTKMVlMWsMOdNMxT7qO3xYtV\
9rfrBctvmI8Vy/xU+UDLBdGCjJ0evEQV8EAFa3VaWTBpb+ki7TjwpHX8qcINHrvt+cxbVbcLuL7L\
R2uf18yw/yLZhEcPxNvModpbb6fuKNRNzbQj3SyZw/j7I6mVywIDAQAB
"""

struct Appcast {
    let version: String
    let notesURL: String
    let dmgURL: URL
    let sha256: String
}

enum UpdateDefaults {
    static let auto = "autoInstallUpdates"
    static let skipped = "skippedVersion"
    static let lastCheck = "lastUpdateCheck"
}

// "1.10.0" > "1.9.0": compare numerically per component, not as strings.
func isNewer(_ candidate: String, than current: String) -> Bool {
    let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
    let b = current.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

private func verify(payload: String, signatureB64: String) -> Bool {
    guard let keyData = Data(base64Encoded: publicKeyB64.replacingOccurrences(of: "\n", with: "")),
          let sig = Data(base64Encoded: signatureB64),
          let payloadData = payload.data(using: .utf8) else { return false }

    let attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits as String: 2048,
    ]
    guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, nil) else {
        return false
    }
    return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                payloadData as CFData, sig as CFData, nil)
}

func fetchAppcast(completion: @escaping (Appcast?) -> Void) {
    var request = URLRequest(url: appcastURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let notes = json["notesUrl"] as? String,
              let mac = json["mac"] as? [String: Any],
              let urlString = mac["url"] as? String,
              let url = URL(string: urlString),
              let sha = mac["sha256"] as? String,
              let win = json["win"] as? [String: Any],
              let winURL = win["url"] as? String,
              let winSha = win["sha256"] as? String,
              let signature = json["signature"] as? String
        else { completion(nil); return }

        // Must match tools/sign_release.sh exactly, field for field.
        let payload = [version, urlString, sha, winURL, winSha, notes].joined(separator: "\n")
        guard verify(payload: payload, signatureB64: signature) else {
            NSLog("ChatterFix: update manifest failed signature check — ignoring")
            completion(nil); return
        }
        completion(Appcast(version: version, notesURL: notes, dmgURL: url, sha256: sha))
    }.resume()
}

func downloadAndVerify(_ appcast: Appcast, completion: @escaping (URL?) -> Void) {
    URLSession.shared.downloadTask(with: appcast.dmgURL) { tempURL, _, _ in
        guard let tempURL = tempURL, let data = try? Data(contentsOf: tempURL) else {
            completion(nil); return
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(appcast.sha256) == .orderedSame else {
            NSLog("ChatterFix: downloaded image hash mismatch — discarding")
            completion(nil); return
        }
        // Move somewhere stable; the URLSession temp file is deleted on return.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatterFix-\(appcast.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil else {
            completion(nil); return
        }
        completion(dest)
    }.resume()
}

// Mounts the verified image, swaps the bundle, and relaunches. Runs detached so
// it survives this process exiting.
func installUpdate(dmg: URL) -> Bool {
    let bundlePath = Bundle.main.bundlePath
    let script = """
    set -e
    MOUNT=$(mktemp -d)
    hdiutil attach "\(dmg.path)" -nobrowse -quiet -mountpoint "$MOUNT"
    # Wait for the current instance to exit before replacing it.
    while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
    rm -rf "\(bundlePath)"
    cp -R "$MOUNT/ChatterFix.app" "\(bundlePath)"
    hdiutil detach "$MOUNT" -quiet || true
    rm -f "\(dmg.path)"
    xattr -dr com.apple.quarantine "\(bundlePath)" 2>/dev/null || true
    open "\(bundlePath)"
    """
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", script]
    do { try task.run() } catch { return false }
    return true
}
