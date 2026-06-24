import WidgetKit
import SwiftUI

// MARK: - Data

struct RecoveryMediumEntry: TimelineEntry {
    let date: Date
    let score: Int
    let status: String
    let message: String
    let recommendationCta: String
    let aiRec: String
    let sleepLabel: String
    let sleepRating: String
    let sleepBar: Int
    let stressValue: String
    let stressRating: String
    let stressBar: Int
    let hrvLabel: String
    let hrvRating: String
    let hrvBar: Int
}

// MARK: - Provider

struct RecoveryMediumProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> RecoveryMediumEntry {
        RecoveryMediumEntry(date: .now, score: 82, status: "Ready to train",
                            message: "Your body is ready.",
                            recommendationCta: "Go for strength today.",
                            aiRec: "Go for Strength today",
                            sleepLabel: "7h 23m", sleepRating: "Good", sleepBar: 80,
                            stressValue: "34", stressRating: "Low", stressBar: 75,
                            hrvLabel: "64 ms", hrvRating: "Good", hrvBar: 70)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryMediumEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryMediumEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> RecoveryMediumEntry {
        let d = defaults
        return RecoveryMediumEntry(
            date: .now,
            score:             Int(d?.string(forKey: "recovery_score")             ?? "0") ?? 0,
            status:            d?.string(forKey: "recovery_status")            ?? "Ready to train",
            message:           d?.string(forKey: "recovery_message")           ?? "",
            recommendationCta: d?.string(forKey: "recovery_recommendation_cta") ?? "",
            aiRec:             d?.string(forKey: "recovery_ai_rec")            ?? "Open app to sync",
            sleepLabel:        d?.string(forKey: "recovery_sleep_label")       ?? "—",
            sleepRating:       d?.string(forKey: "recovery_sleep_rating")      ?? "—",
            sleepBar:          Int(d?.string(forKey: "recovery_sleep_bar")     ?? "0") ?? 0,
            stressValue:       d?.string(forKey: "recovery_stress_value")      ?? "—",
            stressRating:      d?.string(forKey: "recovery_stress_rating")     ?? "—",
            stressBar:         Int(d?.string(forKey: "recovery_stress_bar")    ?? "0") ?? 0,
            hrvLabel:          d?.string(forKey: "recovery_hrv_label")         ?? "—",
            hrvRating:         d?.string(forKey: "recovery_hrv_rating")        ?? "—",
            hrvBar:            Int(d?.string(forKey: "recovery_hrv_bar")       ?? "0") ?? 0
        )
    }
}

// MARK: - Helpers

private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 70...100: return Color(red: 0x2E/255, green: 0xEA/255, blue: 0x7A/255)
    case 40..<70:  return Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255)
    default:       return Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
    }
}

private func ratingColor(_ rating: String) -> Color {
    switch rating.lowercased().trimmingCharacters(in: .whitespaces) {
    case "good", "low", "excellent": return Color(red: 0x2E/255, green: 0xEA/255, blue: 0x7A/255)
    case "fair", "moderate":         return Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255)
    case "poor", "high":             return Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
    default:                         return Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let rating: String
    let barPercent: Int
    let barColor: Color

    private let cardBg   = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x22/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let trackColor = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x26/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(rating)
                .font(.system(size: 10))
                .foregroundColor(ratingColor(rating))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(trackColor)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(barPercent) / 100.0, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, 2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .cornerRadius(10)
    }
}

// MARK: - Widget view

struct RecoveryMediumWidgetView: View {
    let entry: RecoveryMediumEntry

    private let bgColor   = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let cardBg    = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x22/255)
    private let accent    = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)
    private let green     = Color(red: 0x2E/255, green: 0xEA/255, blue: 0x7A/255)
    private let blue      = Color(red: 0x2F/255, green: 0x6B/255, blue: 0xFF/255)
    private let purple    = Color(red: 0x7B/255, green: 0x68/255, blue: 0xEE/255)
    private let red       = Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundColor(green)
                    Text("Recovery")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Today")
                        .font(.system(size: 11))
                        .foregroundColor(secondary)
                }

                // Score + message
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.score)%")
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(entry.status.isEmpty ? "Ready to train" : entry.status)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(scoreColor(entry.score))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if !entry.message.isEmpty {
                            Text(entry.message)
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .lineSpacing(2)
                        }
                        if !entry.recommendationCta.isEmpty {
                            Text(entry.recommendationCta)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(green)
                                .lineSpacing(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 8)

                // Stat cards
                HStack(spacing: 6) {
                    StatCard(icon: "moon.fill", iconColor: purple,
                             label: "Sleep", value: entry.sleepLabel,
                             rating: entry.sleepRating, barPercent: entry.sleepBar,
                             barColor: blue)
                    StatCard(icon: "waveform.path.ecg", iconColor: green,
                             label: "Stress", value: entry.stressValue,
                             rating: entry.stressRating, barPercent: entry.stressBar,
                             barColor: green)
                    StatCard(icon: "heart.fill", iconColor: red,
                             label: "HRV", value: entry.hrvLabel,
                             rating: entry.hrvRating, barPercent: entry.hrvBar,
                             barColor: green)
                }
                .padding(.top, 8)

                // AI Recommendation
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AI Recommendation")
                            .font(.system(size: 10))
                            .foregroundColor(secondary)
                        Text(entry.aiRec.isEmpty ? "Open app to sync" : entry.aiRec)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondary)
                }
                .padding(10)
                .background(cardBg)
                .cornerRadius(10)
                .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Widget

struct ZveltRecoveryMediumWidget: Widget {
    let kind: String = "ZveltRecoveryMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoveryMediumProvider()) { entry in
            RecoveryMediumWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://recovery"))
        }
        .configurationDisplayName("Recovery")
        .description("Recovery score, sleep, stress, HRV and AI recommendation.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    ZveltRecoveryMediumWidget()
} timeline: {
    RecoveryMediumEntry(date: .now, score: 82, status: "Ready to train",
                        message: "Your body is ready.",
                        recommendationCta: "Go for strength today.",
                        aiRec: "Go for Strength today",
                        sleepLabel: "7h 23m", sleepRating: "Good", sleepBar: 80,
                        stressValue: "34", stressRating: "Low", stressBar: 75,
                        hrvLabel: "64 ms", hrvRating: "Good", hrvBar: 70)
}
