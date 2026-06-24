import WidgetKit
import SwiftUI

// MARK: - Data

struct ChainEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let weekCompletion: [Bool]   // 7 values Mon–Sun, true = workout done
    let todayWeekDay: Int        // 0=Mon … 6=Sun
    let lastWorkoutName: String
    let lastWorkoutTime: String
    let lastWorkoutDurationMin: Int?
}

// MARK: - Provider

struct ChainProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> ChainEntry {
        ChainEntry(date: .now, streak: 5,
                   weekCompletion: [true, true, true, true, true, false, false],
                   todayWeekDay: 5,
                   lastWorkoutName: "Push Day A",
                   lastWorkoutTime: "Yesterday, 18:45",
                   lastWorkoutDurationMin: 52)
    }

    func getSnapshot(in context: Context, completion: @escaping (ChainEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChainEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> ChainEntry {
        let d = defaults
        let streak   = Int(d?.string(forKey: "today_streak") ?? "0") ?? 0
        let todayIdx = Int(d?.string(forKey: "today_week_day") ?? "0") ?? 0
        let rawCompletion = d?.string(forKey: "week_completion") ?? ""
        let completion = parseCompletion(rawCompletion)

        let name     = d?.string(forKey: "last_workout_name")          ?? ""
        let time     = d?.string(forKey: "last_workout_time_label")    ?? ""
        let durStr   = d?.string(forKey: "last_workout_duration_min")
        let duration = durStr.flatMap { Int($0) }

        return ChainEntry(date: .now, streak: streak,
                          weekCompletion: completion, todayWeekDay: todayIdx,
                          lastWorkoutName: name, lastWorkoutTime: time,
                          lastWorkoutDurationMin: duration)
    }

    private func parseCompletion(_ raw: String) -> [Bool] {
        guard !raw.isEmpty else { return Array(repeating: false, count: 7) }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let bools = parts.map { $0 == "1" }
        let padded = bools + Array(repeating: false, count: max(0, 7 - bools.count))
        return Array(padded.prefix(7))
    }
}

// MARK: - Chain Circle

struct ChainCircle: View {
    let done: Bool
    let isToday: Bool

    private let accent    = Color(red: 1,           green: 0.353, blue: 0.122)
    private let emptyBg   = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x26/255)
    private let todayBg   = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x22/255)

    var body: some View {
        ZStack {
            if done {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            } else if isToday {
                Circle().fill(todayBg)
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    .foregroundColor(accent)
            } else {
                Circle().fill(emptyBg)
            }
        }
    }
}

// MARK: - Widget view

struct ChainWidgetView: View {
    let entry: ChainEntry

    private let bgColor   = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let accent    = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let cardBg    = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x22/255)
    private let divider   = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x26/255)

    private let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Text("Don't Break the Chain")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if entry.streak > 0 {
                        Text("\(entry.streak) days")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(accent)
                    }
                }

                // Day labels
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(days[i])
                            .font(.system(size: 10))
                            .foregroundColor(secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 10)

                // Chain circles
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        ChainCircle(
                            done: entry.weekCompletion.indices.contains(i) ? entry.weekCompletion[i] : false,
                            isToday: i == entry.todayWeekDay
                        )
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
                .padding(.top, 4)

                // Divider
                Divider()
                    .background(divider)
                    .padding(.vertical, 10)

                // Last workout card
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 14))
                        .foregroundColor(secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.lastWorkoutName.isEmpty ? "No workouts yet" : entry.lastWorkoutName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if !entry.lastWorkoutTime.isEmpty {
                            Text(entry.lastWorkoutTime)
                                .font(.system(size: 11))
                                .foregroundColor(secondary)
                        }
                    }

                    Spacer()

                    if let dur = entry.lastWorkoutDurationMin {
                        Text("\(dur)m")
                            .font(.system(size: 11))
                            .foregroundColor(secondary)
                    }
                }
                .padding(10)
                .background(cardBg)
                .cornerRadius(10)

                Spacer()

                // CTA
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accent)
                    HStack {
                        Text("Train now")
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
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Widget

struct ZveltChainWidget: Widget {
    let kind: String = "ZveltChainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChainProvider()) { entry in
            ChainWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://dashboard"))
        }
        .configurationDisplayName("Don't Break the Chain")
        .description("7-day workout chain and last session info.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemLarge) {
    ZveltChainWidget()
} timeline: {
    ChainEntry(date: .now, streak: 5,
               weekCompletion: [true, true, true, true, true, false, false],
               todayWeekDay: 5,
               lastWorkoutName: "Push Day A",
               lastWorkoutTime: "Yesterday, 18:45",
               lastWorkoutDurationMin: 52)
}
