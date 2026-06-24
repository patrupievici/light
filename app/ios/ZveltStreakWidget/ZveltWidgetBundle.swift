import WidgetKit
import SwiftUI

@main
struct ZveltWidgetBundle: WidgetBundle {
    var body: some Widget {
        ZveltStreakWidget()
        ZveltXpWidget()
        ZveltXpMediumWidget()
        ZveltDayStreakWidget()
        ZveltChainWidget()
        ZveltRecoverySmallWidget()
        ZveltRecoveryMediumWidget()
        ZveltChallengeSmallWidget()
        ZveltChallengeLargeWidget()
    }
}
