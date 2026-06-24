import WidgetKit
import SwiftUI

// MARK: - Data

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let atRisk: Bool
}

// MARK: - Provider

struct StreakProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 7, atRisk: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> StreakEntry {
        let streak = Int(defaults?.string(forKey: "today_streak") ?? "0") ?? 0
        let atRisk = defaults?.bool(forKey: "today_at_risk") ?? false
        return StreakEntry(date: .now, streak: streak, atRisk: atRisk)
    }
}

// MARK: - View

struct StreakWidgetView: View {
    let entry: StreakEntry
    @Environment(\.colorScheme) var colorScheme

    private let bgColor = Color(red: 0x12/255, green: 0x16/255, blue: 0x21/255)
    private let borderColor = Color(red: 0x23/255, green: 0x2B/255, blue: 0x3A/255)
    private let brandColor = Color(red: 0x2F/255, green: 0x6B/255, blue: 0xFF/255)
    private let flameOuter = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x5C/255)
    private let flameInner = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)
    private let secondaryText = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let warningColor = Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )

            VStack(spacing: 2) {
                Text("ZVELT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(brandColor)
                    .kerning(1.0)

                Image(systemName: "flame.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [flameOuter, flameInner],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.top, 4)

                Text("\(entry.streak)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("days")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(secondaryText)

                if entry.atRisk {
                    Text("Streak at risk")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(warningColor)
                        .padding(.top, 2)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Widget

struct ZveltStreakWidget: Widget {
    let kind: String = "ZveltStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://dashboard"))
        }
        .configurationDisplayName("Streak")
        .description("Your current workout streak.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ZveltStreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 12, atRisk: false)
    StreakEntry(date: .now, streak: 3, atRisk: true)
}
