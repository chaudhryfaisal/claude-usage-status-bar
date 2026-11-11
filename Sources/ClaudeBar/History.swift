import Foundation
import SwiftUI
import Charts

struct Sample: Codable, Identifiable {
    var id: Date { t }
    let t: Date
    let v: Double   // utilization 0–100
}

/// Change-only history: a sample is stored only when a window's value differs from
/// the last stored one, so slow-moving quotas stay tiny and charts show true change points.
@MainActor
final class History {
    static let shared = History()
    private let maxSamples = 500
    private var data: [String: [Sample]] = [:]   // "accountID|windowID"
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .secondsSince1970
            data = (try? dec.decode([String: [Sample]].self, from: d)) ?? [:]
        }
    }

    func record(accountID: String, windows: [UsageWindow], at now: Date = Date()) {
        var changed = false
        for w in windows {
            let key = "\(accountID)|\(w.id)"
            var list = data[key] ?? []
            if let last = list.last, abs(last.v - w.utilization) < 0.0001 { continue }
            list.append(Sample(t: now, v: w.utilization))
            if list.count > maxSamples { list.removeFirst(list.count - maxSamples) }
            data[key] = list
            changed = true
        }
        if changed { save() }
    }

    /// Samples since the last reset (a drop in value), i.e. the current period.
    func currentPeriod(accountID: String, windowID: String) -> [Sample] {
        let list = data["\(accountID)|\(windowID)"] ?? []
        var start = 0
        for i in list.indices.dropFirst() where list[i].v < list[i - 1].v { start = i }
        return Array(list[start...])
    }

    func remove(accountID: String) {
        data = data.filter { !$0.key.hasPrefix("\(accountID)|") }
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(data) { try? d.write(to: url, options: .atomic) }
    }
}

/// Step chart of change points: dots only where the value changed, held flat until
/// the next change and extended to now. Hover a dot's area to read time and value.
struct HistoryChart: View {
    let samples: [Sample]
    let color: Color
    @State private var hover: Sample?

    private var line: [Sample] {
        guard let last = samples.last else { return [] }
        return samples + [Sample(t: Date(), v: last.v)]
    }

    var body: some View {
        if samples.count < 2 {
            Text(samples.isEmpty ? "No history yet" : "Tracking changes — chart appears after the next change")
                .font(.caption2).foregroundStyle(.tertiary)
        } else {
            Chart {
                ForEach(line) { s in
                    LineMark(x: .value("Time", s.t), y: .value("Used", s.v))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(color.opacity(0.6))
                }
                ForEach(samples) { s in
                    PointMark(x: .value("Time", s.t), y: .value("Used", s.v))
                        .symbolSize(hover?.t == s.t ? 70 : 24)
                        .foregroundStyle(color)
                }
                if let h = hover {
                    RuleMark(x: .value("Time", h.t))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("\(h.t.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(String(format: "%.2f", h.v))%")
                                .font(.caption2)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                }
            }
            .chartYScale(domain: 0...max(2, (samples.map(\.v).max() ?? 0) * 1.3))
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel(format: Decimal.FormatStyle.number.precision(.fractionLength(0))) } }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p):
                                let x = p.x - geo[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    hover = samples.min { abs($0.t.timeIntervalSince(date)) < abs($1.t.timeIntervalSince(date)) }
                                }
                            case .ended:
                                hover = nil
                            }
                        }
                }
            }
            .frame(height: 90)
        }
    }
}
