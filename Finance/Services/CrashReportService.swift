//
//  CrashReportService.swift
//  Finance
//
//  Created by OpenCode on 15/05/2026.
//

import Foundation

struct CrashReport: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let summary: String
    let details: String
}

final class CrashReportService {
    static let shared = CrashReportService()

    private struct DiagnosticEvent: Codable, Equatable {
        let timestamp: Date
        let message: String
    }

    private enum SessionState: String {
        case active
        case clean
    }

    private let defaults = UserDefaults.standard
    private let sessionRunningKey = "CrashReportService.sessionRunning"
    private let sessionStateKey = "CrashReportService.sessionState"
    private let lastBreadcrumbKey = "CrashReportService.lastBreadcrumb"
    private let diagnosticEventsKey = "CrashReportService.diagnosticEvents"
    private let reportShownKey = "CrashReportService.reportShown"
    private let maxDiagnosticEvents = 50

    private var reportsDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CrashReports", isDirectory: true)
    }

    private var reportURL: URL? {
        reportsDirectory?.appendingPathComponent("last-crash.txt")
    }

    var lastBreadcrumb: String {
        defaults.string(forKey: lastBreadcrumbKey) ?? "Sin acción registrada"
    }

    private init() {}

    func install() {
        startNewSessionDetectingPreviousCrash()
    }

    func recordBreadcrumb(_ message: String) {
        defaults.set(message, forKey: lastBreadcrumbKey)
        recordDiagnosticEvent(message)
    }

    func recordDiagnosticEvent(_ message: String) {
        let sanitizedMessage = sanitized(message)
        var events = diagnosticEvents()
        events.append(DiagnosticEvent(timestamp: Date(), message: sanitizedMessage))
        if events.count > maxDiagnosticEvents {
            events.removeFirst(events.count - maxDiagnosticEvents)
        }

        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: diagnosticEventsKey)
        }
    }

    func markSessionRunning() {
        defaults.set(true, forKey: sessionRunningKey)
        defaults.set(SessionState.active.rawValue, forKey: sessionStateKey)
    }

    func markSessionClean() {
        defaults.set(false, forKey: sessionRunningKey)
        defaults.set(SessionState.clean.rawValue, forKey: sessionStateKey)
    }

    func pendingReport() -> CrashReport? {
        guard defaults.bool(forKey: reportShownKey) == false else { return nil }
        guard let reportURL, FileManager.default.fileExists(atPath: reportURL.path) else { return nil }
        guard let details = try? String(contentsOf: reportURL, encoding: .utf8), !details.isEmpty else { return nil }

        let values = parseKeyValueReport(details)
        let date = values["timestamp"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let summary: String

        summary = "La sesión anterior no se cerró correctamente."

        return CrashReport(date: date, summary: summary, details: details)
    }

    func markPendingReportSeen() {
        defaults.set(true, forKey: reportShownKey)
        if let reportURL {
            try? FileManager.default.removeItem(at: reportURL)
        }
    }

    private func startNewSessionDetectingPreviousCrash() {
        let previousSessionWasActive = defaults.string(forKey: sessionStateKey) == SessionState.active.rawValue
        let shouldReportUncleanExit = defaults.bool(forKey: sessionRunningKey)
            && previousSessionWasActive
            && reportURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true

        if shouldReportUncleanExit {
            let report = """
            type=unclean_exit
            timestamp=\(ISO8601DateFormatter().string(from: Date()))
            version=\(AppVersion.current)
            breadcrumb=\(lastBreadcrumb)
            reason=La app se abrió después de una sesión que quedó marcada como activa en primer plano. iOS no expuso una señal concreta.
            recent_events:
            \(formattedDiagnosticEvents())
            """
            writeReport(report)
        }

        defaults.set(false, forKey: reportShownKey)
        markSessionClean()
    }

    private func writeReport(_ report: String) {
        guard let reportsDirectory, let reportURL else { return }
        try? FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        defaults.set(false, forKey: reportShownKey)
    }

    private func parseKeyValueReport(_ report: String) -> [String: String] {
        report
            .components(separatedBy: .newlines)
            .reduce(into: [:]) { values, line in
                guard let separator = line.firstIndex(of: "=") else { return }
                let key = String(line[..<separator])
                let valueStart = line.index(after: separator)
                let value = String(line[valueStart...])
                values[key] = value
            }
    }

    private func diagnosticEvents() -> [DiagnosticEvent] {
        guard let data = defaults.data(forKey: diagnosticEventsKey),
              let events = try? JSONDecoder().decode([DiagnosticEvent].self, from: data)
        else { return [] }

        return Array(events.suffix(maxDiagnosticEvents))
    }

    private func formattedDiagnosticEvents() -> String {
        let formatter = ISO8601DateFormatter()
        let events = diagnosticEvents()

        guard !events.isEmpty else { return "- Sin eventos recientes" }

        return events
            .map { "- \(formatter.string(from: $0.timestamp)) \($0.message)" }
            .joined(separator: "\n")
    }

    private func sanitized(_ message: String) -> String {
        let singleLine = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(500))
    }
}
