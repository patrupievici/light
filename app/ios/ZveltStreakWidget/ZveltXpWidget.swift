import WidgetKit
import SwiftUI

// MARK: - Data

struct XpEntry: TimelineEntry {
    let date: Date
    let xpPercent: Int
    let kcal: Int
    let streak: Int
}

// MARK: - Provider

struct XpProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> XpEntry {
        XpEntry(date: .now, xpPercent: 68, kcal: 412, streak: 7)
    }

    func getSnapshot(in context: Context, completion: @escaping (XpEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XpEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> XpEntry {
        let xp     = Int(defaults?.string(forKey: "today_xp_percent") ?? "0") ?? 0
        let kcal   = Int(defaults?.string(forKey: "today_kcal")       ?? "0") ?? 0
        let streak = Int(defaults?.string(forKey: "today_streak")     ?? "0") ?? 0
        return XpEntry(date: .now, xpPercent: xp, kcal: kcal, streak: streak)
    }
}

// MARK: - Circular progress ring

struct XpRing: View {
    let progress: Double   // 0.0 – 1.0
    let lineWidth: CGFloat

    private let trackColor    = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x22/255)
    private let arcStart      = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255) // #FF5A1F
    private let arcMid        = Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255) // #FFB020

    var body: some View {
        ZStack {
            // Track (full circle)
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: [arcStart, arcMid, arcStart],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Widget view

struct XpWidgetView: View {
    let entry: XpEntry

    private let bgColor       = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let secondaryText = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let accentOrange  = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)
    private let flameAmber    = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x5C/255)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 5) {

                // Ring + centre text
                ZStack {
                    XpRing(
                        progress: Double(entry.xpPercent) / 100.0,
                        lineWidth: 14
                    )
                    .padding(6)

                    VStack(spacing: 1) {
                        Text("\(entry.xpPercent)%")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("XP")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                // Stats row
                HStack(spacing: 0) {
                    statCell(value: "\(entry.kcal)", label: "kcal")

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 18)

                    statCell(value: "\(entry.streak)", label: "day streak")
                }

                // Footer
                Text("Today: \(entry.xpPercent)% complete")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accentOrange)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(
                    LinearGradient(
                        colors: [flameAmber, accentOrange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget

struct ZveltXpWidget: Widget {
    let kind: String = "ZveltXpWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: XpProvider()) { entry in
            XpWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://dashboard"))
        }
        .configurationDisplayName("XP Progress")
        .description("Daily XP progress, calories burned and current streak.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ZveltXpWidget()
} timeline: {
    XpEntry(date: .now, xpPercent: 68, kcal: 412, streak: 7)
    XpEntry(date: .now, xpPercent: 100, kcal: 820, streak: 14)
}
