import WidgetKit
import SwiftUI

// MARK: - Data

struct XpMediumEntry: TimelineEntry {
    let date: Date
    let xpCurrent: Int
    let xpGoal: Int
    let xpPercent: Int
    let kcal: Int
    let steps: Int
    let activeMin: Int
    let weekPercents: [Int]   // 7 values Mon–Sun, 0–100
    let todayWeekDay: Int     // 0=Mon … 6=Sun
}

// MARK: - Provider

struct XpMediumProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> XpMediumEntry {
        XpMediumEntry(date: .now, xpCurrent: 2150, xpGoal: 3000, xpPercent: 68,
                      kcal: 412, steps: 8752, activeMin: 54,
                      weekPercents: [40, 60, 20, 80, 30, 68, 0], todayWeekDay: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (XpMediumEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XpMediumEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> XpMediumEntry {
        let d = defaults
        let xpCurrent  = Int(d?.string(forKey: "today_xp_current")  ?? "0") ?? 0
        let xpGoal     = Int(d?.string(forKey: "today_xp_goal")     ?? "3000") ?? 3000
        let xpPercent  = Int(d?.string(forKey: "today_xp_percent")  ?? "0") ?? 0
        let kcal       = Int(d?.string(forKey: "today_kcal")        ?? "0") ?? 0
        let steps      = Int(d?.string(forKey: "today_steps")       ?? "0") ?? 0
        let activeMin  = Int(d?.string(forKey: "today_active_min")  ?? "0") ?? 0
        let todayIdx   = Int(d?.string(forKey: "today_week_day")    ?? "0") ?? 0
        let weekRaw    = d?.string(forKey: "week_xp_percents") ?? ""
        let weekPcts   = weekRaw.split(separator: ",")
                                .map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        let weekPadded = (weekPcts + Array(repeating: 0, count: max(0, 7 - weekPcts.count)))
        return XpMediumEntry(date: .now, xpCurrent: xpCurrent, xpGoal: xpGoal,
                             xpPercent: xpPercent, kcal: kcal, steps: steps,
                             activeMin: activeMin,
                             weekPercents: Array(weekPadded.prefix(7)),
                             todayWeekDay: todayIdx)
    }
}

// MARK: - Bar Chart

struct WeekBarChart: View {
    let percents: [Int]
    let todayIdx: Int

    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    private let accent   = Color(red: 1, green: 0.353, blue: 0.122)   // #FF5A1F
    private let barBg    = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x26/255)
    private let dayColor = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        let pct = CGFloat(percents.indices.contains(i) ? percents[i] : 0) / 100.0
                        let barH = max(pct * geo.size.height, 4)
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(i == todayIdx ? accent : barBg)
                                .frame(height: barH)
                        }
                    }
                    Text(days[i])
                        .font(.system(size: 9, weight: i == todayIdx ? .bold : .regular))
                        .foregroundColor(i == todayIdx ? accent : dayColor)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Widget view

struct XpMediumWidgetView: View {
    let entry: XpMediumEntry

    private let bgColor      = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let secondary    = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let accent       = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)
    private let trackColor   = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x26/255)
    private let flameAmber   = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x5C/255)

    private let numFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    private func fmt(_ n: Int) -> String {
        numFmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 5) {

                // Header
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(accent)
                            .frame(width: 22, height: 22)
                        Text("Z")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.white)
                    }
                    Text("Daily Progress")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Today")
                        .font(.system(size: 11))
                        .foregroundColor(secondary)
                }

                // XP amount
                Text("\(fmt(entry.xpCurrent)) / \(fmt(entry.xpGoal)) XP")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                // Progress bar + %
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(trackColor)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent)
                                .frame(width: geo.size.width * CGFloat(entry.xpPercent) / 100.0,
                                       height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(entry.xpPercent)%")
                        .font(.system(size: 11))
                        .foregroundColor(secondary)
                        .frame(width: 30, alignment: .trailing)
                }

                // Stats row
                HStack(spacing: 0) {
                    statCell(icon: "flame.fill", useGradient: true, value: fmt(entry.kcal), label: "kcal")
                    statCell(icon: "shoeprints.fill", useGradient: false, value: fmt(entry.steps), label: "steps")
                    statCell(icon: "timer", useGradient: false, value: "\(entry.activeMin)", label: "min")
                }

                // 7-Day header
                HStack {
                    Text("7-Day Progress")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("100%").frame(maxHeight: .infinity, alignment: .top)
                        Text("50%").frame(maxHeight: .infinity, alignment: .center)
                        Text("0%").frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .font(.system(size: 8))
                    .foregroundColor(secondary)
                    .frame(height: 30)
                }

                // Bar chart
                WeekBarChart(percents: entry.weekPercents, todayIdx: entry.todayWeekDay)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)

                // CTA button
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accent)
                    HStack {
                        Text("Finish today's goal")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 30)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func statCell(icon: String, useGradient: Bool, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Group {
                if useGradient {
                    Image(systemName: icon)
                        .foregroundStyle(
                            LinearGradient(colors: [flameAmber, accent],
                                           startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    Image(systemName: icon)
                        .foregroundColor(secondary)
                }
            }
            .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct ZveltXpMediumWidget: Widget {
    let kind: String = "ZveltXpMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: XpMediumProvider()) { entry in
            XpMediumWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://dashboard"))
        }
        .configurationDisplayName("Daily Progress")
        .description("XP progress, calories, steps and 7-day history.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    ZveltXpMediumWidget()
} timeline: {
    XpMediumEntry(date: .now, xpCurrent: 2150, xpGoal: 3000, xpPercent: 68,
                  kcal: 412, steps: 8752, activeMin: 54,
                  weekPercents: [40, 60, 20, 80, 30, 68, 0], todayWeekDay: 5)
}
