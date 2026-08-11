import Foundation

enum WindowKind: String, Codable {
    case fiveHour
    case sevenDay

    /// Nominal window length. Half of this is the tolerance that decides whether an
    /// observed reset belongs to the newest stored window or opens a new one.
    var seconds: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .sevenDay: return 7 * 86400
        }
    }
}

struct UsageWindow: Codable, Identifiable, Equatable {
    let kind: WindowKind
    let end: Date       // reset timestamp as observed from the API — the window's end
    let peak: Double    // highest utilization seen inside the window, 0...1

    var id: String { "\(kind.rawValue)-\(end.timeIntervalSince1970)" }
}

/// Persistent record of usage windows — one row per window, kept forever.
///
/// Bars used to be derived on the fly from raw snapshots trimmed at 30 days, which
/// capped how far back the charts could reach and made every bar depend on a snapshot
/// happening to land near the reset. Storing the window itself makes history unbounded
/// (~50 B per row) and keeps the peak, which is what the window was worth at reset.
final class WindowHistory {
    static let shared = WindowHistory()

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultDirectory().appendingPathComponent("windows.json")
    }

    private static func defaultDirectory() -> URL {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory
        }
        let dir = support.appendingPathComponent("ClaudeMonitorBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() -> [UsageWindow] {
        guard let data = try? Data(contentsOf: storageURL),
              let windows = try? JSONDecoder().decode([UsageWindow].self, from: data) else {
            return []
        }
        return windows.sorted { $0.end < $1.end }
    }

    /// Upsert the window ending at `end`.
    ///
    /// Utilization only grows inside a window, so keeping the max both matches the value
    /// at reset and survives the app being closed at that moment. Reset timestamps drift
    /// by minutes, so anything within half a window is the same window, not a new one.
    func record(kind: WindowKind, end: Date, value: Double) {
        var windows = load()

        // `load()` sorts ascending, so the last match is the newest window of that kind.
        if let idx = windows.lastIndex(where: { $0.kind == kind }),
           abs(windows[idx].end.timeIntervalSince(end)) < kind.seconds / 2 {
            windows[idx] = UsageWindow(kind: kind, end: end, peak: max(windows[idx].peak, value))
        } else {
            windows.append(UsageWindow(kind: kind, end: end, peak: value))
        }

        save(windows)
    }

    private func save(_ windows: [UsageWindow]) {
        let sorted = windows.sorted { $0.end < $1.end }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
