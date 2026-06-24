import 'package:intl/intl.dart';

/// Single source of truth for humanized timestamp strings across the social
/// surfaces (feed, post-detail, notifications, DM, conversations, circle,
/// race). Wave 19 audit (#F2) found three slightly different formats in the
/// same tab — "${n}m" vs "${n}m ago" vs "now"/"just now" — visible side-by-side
/// in scrollable lists. This helper collapses them all into one cadence.
///
/// Format ladder:
///   diff <60s        → "just now"
///   diff <60min      → "${n}m ago"
///   diff <24h        → "${n}h ago"
///   diff <7d         → "${n}d ago"
///   same year        → "Mar 14"
///   older            → "Mar 14, 2025"
///
/// Always pass a *local* DateTime — callers parsing ISO strings should
/// `DateTime.parse(iso).toLocal()` first.
String relativeTime(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);

  // Future / clock-skewed dates: treat as "just now" rather than negative.
  if (diff.isNegative) return 'just now';

  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';

  if (when.year == ref.year) {
    return DateFormat('MMM d').format(when);
  }
  return DateFormat('MMM d, y').format(when);
}

/// Long-form absolute timestamp for tooltips / accessibility values.
/// e.g. "Mar 14, 2026 at 3:42 PM"
String absoluteTime(DateTime when) =>
    DateFormat("MMM d, y 'at' h:mm a").format(when);

/// Null-safe wrapper around [relativeTime]. Accepts an ISO-8601 string
/// (typically the `createdAt` field from a server response). Returns an
/// empty string if [iso] is null/empty or fails to parse.
///
/// Wave 22 P1.7 — collapses 5 near-identical local `_safeRelative` /
/// `_timeAgo` / `_formatDate` helpers spread across conversations, DM,
/// notifications, post-detail and the feed card into a single canonical
/// entry point.
String safeRelativeTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    return relativeTime(DateTime.parse(iso).toLocal());
  } catch (_) {
    return '';
  }
}
