/// Onboarding completion keys.
///
/// SharedPreferences key prefix marking onboarding completion (stored per-user
/// as `<key>_<userId>`). The string value is preserved from the legacy
/// onboarding2 flow so already-onboarded users are NOT re-prompted after the
/// legacy flow was removed.
const String kOnboarding2CompletedKey = 'onboarding2_completed';
