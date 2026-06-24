import WidgetKit
import SwiftUI

// MARK: - Data

struct DayStreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let atRisk: Bool
}

// MARK: - Provider

struct DayStreakProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> DayStreakEntry {
        DayStreakEntry(date: .now, streak: 12, atRisk: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayStreakEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayStreakEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> DayStreakEntry {
        let streak = Int(defaults?.string(forKey: "today_streak") ?? "0") ?? 0
        let atRisk = defaults?.bool(forKey: "today_at_risk") ?? false
        return DayStreakEntry(date: .now, streak: streak, atRisk: atRisk)
    }
}

// MARK: - Widget view

struct DayStreakWidgetView: View {
    let entry: DayStreakEntry

    private let bgColor  = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let accent   = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let warning  = Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255)
    private let flameAmber = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x5C/255)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 2) {
                // Flame icon with gradient
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [flameAmber, accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Streak number
                Text("\(entry.streak)")
                    .font(.system(size: 46, weight: .black))
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // Label
                Text("Day Streak")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                // At-risk badge
                if entry.atRisk {
                    Text("⚠ At Risk")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(warning)
                        .padding(.top, 2)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Widget

struct ZveltDayStreakWidget: Widget {
    let kind: String = "ZveltDayStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayStreakProvider()) { entry in
            DayStreakWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://dashboard"))
        }
        .configurationDisplayName("Day Streak")
        .description("Your current workout streak at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ZveltDayStreakWidget()
} timeline: {
    DayStreakEntry(date: .now, streak: 12, atRisk: false)
    DayStreakEntry(date: .now, streak: 3,  atRisk: true)
}
