import Foundation

@Observable
class ProcessMonitor {
    var runningPIDs: [Int32] = []
    private var timer: Timer?

    struct ProcessInfo {
        let pid: Int32
    }

    static func parseProcessLine(_ line: String) -> ProcessInfo? {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard let first = parts.first, let pid = Int32(first) else { return nil }
        return ProcessInfo(pid: pid)
    }

    func startMonitoring(interval: TimeInterval = 5.0) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "claude"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").map(String.init)

            runningPIDs = lines.compactMap { Self.parseProcessLine($0)?.pid }
        } catch {
            runningPIDs = []
        }
    }
}
