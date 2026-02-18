import Foundation
import AppKit

@Observable
class UpdateChecker {
    static let shared = UpdateChecker()

    var latestVersion: String?
    var updateAvailable: Bool = false
    var upToDate: Bool = false  // true after check confirms no update
    var releaseURL: String?
    var downloadProgress: Double?  // nil = not downloading, 0..1 = progress
    var checkError: String?

    static let currentVersion = "1.5.1"
    private let repo = "paradoxlabdev/ClaudeMonitorBar"
    private var periodicTimer: Timer?

    func startPeriodicCheck() {
        check()
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        upToDate = false
        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.checkError = error.localizedDescription
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.checkError = "Could not parse release info"
                    return
                }

                let latest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                self.latestVersion = latest
                self.releaseURL = json["html_url"] as? String

                // Find .zip asset URL
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".zip"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            self.assetDownloadURL = downloadURL
                            break
                        }
                    }
                }

                let hasUpdate = Self.isNewer(latest, than: Self.currentVersion)
                self.updateAvailable = hasUpdate
                self.upToDate = !hasUpdate
                self.checkError = nil
            }
        }.resume()
    }

    // MARK: - Self-Update

    private var assetDownloadURL: String?

    func performUpdate() {
        // If we have a direct .zip asset, download and replace
        if let zipURL = assetDownloadURL {
            downloadAndReplace(from: zipURL)
            return
        }

        // Fallback: open GitHub release page
        if let urlStr = releaseURL, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    private func downloadAndReplace(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        downloadProgress = 0

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if error != nil || tempURL == nil {
                    self.checkError = "Download failed"
                    self.downloadProgress = nil
                    return
                }

                guard let tempURL else { return }
                self.installUpdate(from: tempURL)
            }
        }

        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        // Keep observation alive until task completes
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        task.resume()
    }

    private func installUpdate(from zipURL: URL) {
        let fm = FileManager.default
        let appPath = Bundle.main.bundlePath

        // Only update if running as .app bundle
        guard appPath.hasSuffix(".app") else {
            checkError = "Cannot self-update when running from terminal. Use build-app.sh."
            downloadProgress = nil
            return
        }

        let appURL = URL(fileURLWithPath: appPath)
        let appDir = appURL.deletingLastPathComponent()
        let appName = appURL.lastPathComponent

        do {
            // Create temp directory for extraction
            let tempDir = fm.temporaryDirectory.appendingPathComponent("ClaudeMonitorBar-update-\(UUID().uuidString)")
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Unzip
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipURL.path, "-d", tempDir.path]
            unzipProcess.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
            unzipProcess.standardOutput = nil
            unzipProcess.standardError = nil
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip update"])
            }

            // Find .app in extracted contents
            let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app found in update"])
            }

            // Write a relaunch script that waits for us to quit, replaces the app, and relaunches
            let script = """
            #!/bin/bash
            # Wait for the old app to quit
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            # Replace the old app
            rm -rf "\(appDir.appendingPathComponent(appName).path)"
            mv "\(newApp.path)" "\(appDir.appendingPathComponent(appName).path)"
            # Relaunch
            open "\(appDir.appendingPathComponent(appName).path)"
            # Cleanup
            rm -rf "\(tempDir.path)"
            rm -- "$0"
            """

            let scriptURL = fm.temporaryDirectory.appendingPathComponent("claude-monitor-update.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            // Launch the script and quit
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptURL.path]
            launcher.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
            try launcher.run()

            // Quit ourselves so the script can replace us
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            checkError = "Update failed: \(error.localizedDescription)"
            downloadProgress = nil
        }
    }

    // MARK: - Version Comparison

    /// Semantic version comparison: returns true if `a` is newer than `b`
    static func isNewer(_ a: String, than b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }
}
