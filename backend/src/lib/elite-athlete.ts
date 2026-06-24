/**
 * Heuristic: user competes at national/international/pro level (not just “advanced gym”).
 * Used to branch AI goal-advice away from generic beginner gym tips.
 */
const ELITE_HINT_PATTERNS: RegExp[] = [
  /\beuropean champion\b/i,
  /\bworld champion\b/i,
  /\beuro(?:pean)?\s+championship\b/i,
  /\bworld championship\b/i,
  /\bolympian\b/i,
  /\bolympic\s+games\b/i,
  /\bolympic\s+(team|qualifier|qualifying|medal|final)\b/i,
  /\bnational team\b/i,
  /\bfirst\s+division\b/i,
  /\btop\s*(?:flight|tier)\b/i,
  /\b(?:premier|serie\s*a|la\s*liga|bundesliga|ligue\s*1)\b/i,
  /\bchampions\s+league\b/i,
  /\bworld\s+cup\b/i,
  /\binternational\s+(cap|level|competition)\b/i,
  /\bprofessional\s+(footballer|football|soccer|rugby|hockey|basketball|tennis|player|athlete)\b/i,
  /\bpro\s+(football|soccer|rugby|hockey|basketball|tennis)\b/i,
  /\belite\s+(level|sport|competition|athlete)\b/i,
  /\bcompete[s]?\s+professionally\b/i,
  /\bcompete[s]?\s+at\s+(?:the\s+)?(?:highest|international|professional)\b/i,
  /\bfifa\b/i,
  /\bufefa\b/i,
  /\bd1\b.*\b(?:ncaa|college)\b/i,
  /\bdivision\s*(?:one|1|i)\b.*\b(?:sport|football|soccer|basketball)\b/i,
  /\bpodium\b.*\b(?:world|european|national)\b/i,
  /\bgold\s+medal\b/i,
  /\b(?:nba|nfl|mlb|nhl)\b/i,
]

export function signalsEliteCompetitionLevel(raw: string): boolean {
  const t = raw.trim()
  if (t.length < 8) return false
  return ELITE_HINT_PATTERNS.some((re) => re.test(t))
}
