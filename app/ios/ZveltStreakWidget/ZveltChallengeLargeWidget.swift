import WidgetKit
import SwiftUI

// MARK: - Data

struct ChallengeEntry: TimelineEntry {
    let date: Date
    let challengeName: String
    let daysLeftLabel: String
    let entries: [LeaderboardEntry]
    let cta: String
}

struct LeaderboardEntry: Identifiable {
    let id: Int
    let name: String
    let kcal: Int
    let isMe: Bool
}

// MARK: - Provider

struct ChallengeLargeProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> ChallengeEntry {
        ChallengeEntry(date: .now, challengeName: "Pack Challenge", daysLeftLabel: "3 days left",
                       entries: [
                           LeaderboardEntry(id: 0, name: "Mihai", kcal: 1870, isMe: false),
                           LeaderboardEntry(id: 1, name: "Alex",  kcal: 1640, isMe: false),
                           LeaderboardEntry(id: 2, name: "You",   kcal: 1520, isMe: true),
                       ],
                       cta: "Push 320 kcal to overtake Alex")
    }

    func getSnapshot(in context: Context, completion: @escaping (ChallengeEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChallengeEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> ChallengeEntry {
        let d = defaults
        let name     = d?.string(forKey: "pack_challenge_name")  ?? "Pack Challenge"
        let days     = d?.string(forKey: "pack_days_left_label") ?? ""
        let cta      = d?.string(forKey: "pack_cta")             ?? ""
        let lbRaw    = d?.string(forKey: "pack_leaderboard")     ?? ""
        let entries  = parseLeaderboard(lbRaw)
        return ChallengeEntry(date: .now, challengeName: name, daysLeftLabel: days,
                              entries: entries, cta: cta)
    }

    private func parseLeaderboard(_ raw: String) -> [LeaderboardEntry] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").enumerated().compactMap { (i, token) in
            let parts = token.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard parts.count >= 2 else { return nil }
            let name  = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard let kcal = Int(String(parts[1]).trimmingCharacters(in: .whitespaces)) else { return nil }
            let isMe  = parts.count > 2 && parts[2].trimmingCharacters(in: .whitespaces) == "1"
            return LeaderboardEntry(id: i, name: name, kcal: kcal, isMe: isMe)
        }
    }
}

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let maxKcal: Int

    private let purple    = Color(red: 0x7B/255, green: 0x52/255, blue: 0xFF/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let meBg      = Color(red: 0x15/255, green: 0x10/255, blue: 0x2A/255)
    private let avatarBg  = Color(red: 0x2C/255, green: 0x2C/255, blue: 0x38/255)
    private let meAvatarBg = Color(red: 0x2A/255, green: 0x1F/255, blue: 0x5C/255)
    private let barTrack  = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x26/255)

    private let numFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    var body: some View {
        ZStack {
            if entry.isMe { meBg.cornerRadius(8) }

            HStack(spacing: 8) {
                // Rank
                Text("\(rank)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(entry.isMe ? purple : secondary)
                    .frame(width: 18)

                // Avatar circle with initial
                ZStack {
                    Circle()
                        .fill(entry.isMe ? meAvatarBg : avatarBg)
                        .frame(width: 34, height: 34)
                    Text(String(entry.name.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                // Name + bar
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    GeometryReader { geo in
                        let ratio = maxKcal > 0 ? CGFloat(entry.kcal) / CGFloat(maxKcal) : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(barTrack).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(purple)
                                .frame(width: geo.size.width * ratio, height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                // Kcal value
                Text("\(numFmt.string(from: NSNumber(value: entry.kcal)) ?? "\(entry.kcal)") kcal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Widget view

struct ChallengeLargeWidgetView: View {
    let entry: ChallengeEntry

    private let bgColor   = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let purple    = Color(red: 0x7B/255, green: 0x52/255, blue: 0xFF/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)
    private let cardBg    = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x22/255)
    private let orange    = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x1F/255)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 14))
                        .foregroundColor(purple)
                    Text(entry.challengeName.isEmpty ? "Pack Challenge" : entry.challengeName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if !entry.daysLeftLabel.isEmpty {
                        Text(entry.daysLeftLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(purple)
                    }
                }

                // Leaderboard
                let maxKcal = entry.entries.map(\.kcal).max() ?? 1
                VStack(spacing: 4) {
                    ForEach(Array(entry.entries.enumerated()), id: \.element.id) { i, e in
                        LeaderboardRow(rank: i + 1, entry: e, maxKcal: maxKcal)
                    }
                }
                .padding(.top, 10)

                Spacer()

                // CTA row
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 0xFF/255, green: 0xB1/255, blue: 0x5C/255), orange],
                                           startPoint: .top, endPoint: .bottom)
                        )

                    Text(entry.cta.isEmpty ? "Open app to see challenge" : entry.cta)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(purple)
                            .frame(width: 30, height: 30)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(10)
                .background(cardBg)
                .cornerRadius(10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Widget

struct ZveltChallengeLargeWidget: Widget {
    let kind: String = "ZveltChallengeLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChallengeLargeProvider()) { entry in
            ChallengeLargeWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://challenge"))
        }
        .configurationDisplayName("Pack Challenge")
        .description("Pack challenge leaderboard and gap to next rank.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemLarge) {
    ZveltChallengeLargeWidget()
} timeline: {
    ChallengeEntry(date: .now, challengeName: "Pack Challenge", daysLeftLabel: "3 days left",
                   entries: [
                       LeaderboardEntry(id: 0, name: "Mihai", kcal: 1870, isMe: false),
                       LeaderboardEntry(id: 1, name: "Alex",  kcal: 1640, isMe: false),
                       LeaderboardEntry(id: 2, name: "You",   kcal: 1520, isMe: true),
                   ],
                   cta: "Push 320 kcal to overtake Alex")
}
