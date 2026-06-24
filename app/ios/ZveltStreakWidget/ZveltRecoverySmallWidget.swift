import WidgetKit
import SwiftUI

// MARK: - Data

struct RecoverySmallEntry: TimelineEntry {
    let date: Date
    let score: Int
    let status: String
}

// MARK: - Provider

struct RecoverySmallProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> RecoverySmallEntry {
        RecoverySmallEntry(date: .now, score: 82, status: "Ready to train")
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoverySmallEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoverySmallEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> RecoverySmallEntry {
        let score  = Int(defaults?.string(forKey: "recovery_score")  ?? "0") ?? 0
        let status = defaults?.string(forKey: "recovery_status") ?? "Ready to train"
        return RecoverySmallEntry(date: .now, score: score, status: status)
    }
}

// MARK: - Widget view

struct RecoverySmallWidgetView: View {
    let entry: RecoverySmallEntry

    private let bgColor = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let track   = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x22/255)

    private var scoreColor: Color {
        switch entry.score {
        case 70...100: return Color(red: 0x2E/255, green: 0xEA/255, blue: 0x7A/255)
        case 40..<70:  return Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255)
        default:       return Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
        }
    }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Ring
                ZStack {
                    Circle()
                        .stroke(track, lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: CGFloat(entry.score) / 100.0)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(entry.score)%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Status
                Text(entry.status.isEmpty ? "Ready to train" : entry.status)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(scoreColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Checkmark circle
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(scoreColor)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Widget

struct ZveltRecoverySmallWidget: Widget {
    let kind: String = "ZveltRecoverySmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoverySmallProvider()) { entry in
            RecoverySmallWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://recovery"))
        }
        .configurationDisplayName("Recovery")
        .description("Recovery score ring at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ZveltRecoverySmallWidget()
} timeline: {
    RecoverySmallEntry(date: .now, score: 82, status: "Ready to train")
    RecoverySmallEntry(date: .now, score: 45, status: "Moderate")
}
