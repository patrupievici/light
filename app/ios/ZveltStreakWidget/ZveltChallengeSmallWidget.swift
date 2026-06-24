import WidgetKit
import SwiftUI

// MARK: - Data

struct ChallengeSmallEntry: TimelineEntry {
    let date: Date
    let challengeName: String
    let myRank: Int
    let gapLabel: String
    let gapToLabel: String
}

// MARK: - Provider

struct ChallengeSmallProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.lunaoscar.zvelt")

    func placeholder(in context: Context) -> ChallengeSmallEntry {
        ChallengeSmallEntry(date: .now, challengeName: "Pack Challenge",
                            myRank: 3, gapLabel: "-120 kcal", gapToLabel: "to #2")
    }

    func getSnapshot(in context: Context, completion: @escaping (ChallengeSmallEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChallengeSmallEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func makeEntry() -> ChallengeSmallEntry {
        let d = defaults
        let name    = d?.string(forKey: "pack_challenge_name") ?? "Pack Challenge"
        let rank    = Int(d?.string(forKey: "pack_my_rank") ?? "0") ?? 0
        let gap     = d?.string(forKey: "pack_gap_label") ?? ""
        let gapTo   = d?.string(forKey: "pack_gap_to_label") ?? ""
        return ChallengeSmallEntry(date: .now, challengeName: name,
                                   myRank: rank, gapLabel: gap, gapToLabel: gapTo)
    }
}

// MARK: - Widget view

struct ChallengeSmallWidgetView: View {
    let entry: ChallengeSmallEntry

    private let bgColor  = Color(red: 0x05/255, green: 0x05/255, blue: 0x05/255)
    private let purple   = Color(red: 0x7B/255, green: 0x52/255, blue: 0xFF/255)
    private let secondary = Color(red: 0xA9/255, green: 0xB0/255, blue: 0xC0/255)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 2) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20))
                    .foregroundColor(purple)

                Text(entry.myRank > 0 ? "#\(entry.myRank)" : "#–")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(purple)
                    .lineLimit(1)

                Text(entry.challengeName.isEmpty ? "Pack Challenge" : entry.challengeName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !entry.gapLabel.isEmpty {
                    VStack(spacing: 0) {
                        Text(entry.gapLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(purple)
                        if !entry.gapToLabel.isEmpty {
                            Text(entry.gapToLabel)
                                .font(.system(size: 10))
                                .foregroundColor(secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Widget

struct ZveltChallengeSmallWidget: Widget {
    let kind: String = "ZveltChallengeSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChallengeSmallProvider()) { entry in
            ChallengeSmallWidgetView(entry: entry)
                .widgetURL(URL(string: "zvelt://challenge"))
        }
        .configurationDisplayName("Pack Challenge")
        .description("Your rank in the active pack challenge.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ZveltChallengeSmallWidget()
} timeline: {
    ChallengeSmallEntry(date: .now, challengeName: "Pack Challenge",
                        myRank: 3, gapLabel: "-120 kcal", gapToLabel: "to #2")
}
