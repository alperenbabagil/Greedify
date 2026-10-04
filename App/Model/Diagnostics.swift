import Foundation
import GreedifyKit
import MetricKit

/// Fills `ErrorLog` with what happens outside the code paths that record errors themselves:
/// macOS crash and resource reports for Greedify and librespot, and MetricKit's diagnostics (hangs,
/// CPU and disk-write exceptions). Each is one line in errors.log; MetricKit's full JSON is kept beside it.
@MainActor
final class Diagnostics {
    static let lastScanKey = "crashReportsScannedAt"
    private let subscriber = MetricSubscriber()

    /// Opens errors.log, then scans for crash reports in the background and subscribes to MetricKit.
    func start() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        ErrorLog.shared.open(directory: GreedifyPaths.logs)
        ErrorLog.shared.note("Greedify \(version) launched")
        MXMetricManager.shared.add(subscriber)

        // The first scan looks back a week, so a crash just before this feature existed still shows up.
        let since = UserDefaults.standard.object(forKey: Self.lastScanKey) as? Date ?? Date(timeIntervalSinceNow: -7 * 86_400)
        let scannedAt = Date()
        Task.detached(priority: .utility) {
            for report in CrashReports.find(since: since) {
                ErrorLog.shared.record("crash report " + CrashReports.summary(of: report), category: "crash")
            }
            await MainActor.run { UserDefaults.standard.set(scannedAt, forKey: Self.lastScanKey) }
        }
    }
}

/// Receives MetricKit's diagnostic payloads (delivered at most daily, on a background queue).
private final class MetricSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let counts = [("crash", payload.crashDiagnostics?.count), ("hang", payload.hangDiagnostics?.count),
                          ("CPU", payload.cpuExceptionDiagnostics?.count), ("disk-write", payload.diskWriteExceptionDiagnostics?.count)]
                .compactMap { name, n in n.flatMap { $0 > 0 ? "\($0) \(name)" : nil } }
            guard !counts.isEmpty else { continue }
            let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
            let file = GreedifyPaths.logs.appendingPathComponent("metrickit-\(stamp).json")
            try? payload.jsonRepresentation().write(to: file, options: .atomic)
            ErrorLog.shared.record("MetricKit: \(counts.joined(separator: ", ")) → \(file.lastPathComponent)", category: "crash")
        }
    }
}
