/// Resolves a user-facing display name without exposing a raw user ID.
///
/// Previously the codebase fell back to `userId.substring(0, 8).toUpperCase()`
/// when both `displayName` and `username` were missing, which leaked the first
/// 8 hex chars of the user's UUID to every reader of a post / comment thread.
///
/// Resolution order:
/// 1. `displayName` (trimmed) if non-empty
/// 2. `@username` (trimmed) if non-empty
/// 3. literal `Athlete` — generic, no UUID
String resolveDisplayName({
  String? displayName,
  String? username,
  String? userId,
}) {
  if (displayName != null && displayName.trim().isNotEmpty) {
    return displayName.trim();
  }
  if (username != null && username.trim().isNotEmpty) {
    final u = username.trim();
    return u.startsWith('@') ? u : '@$u';
  }
  return 'Athlete';
}
