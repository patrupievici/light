/**
 * User-generated-text sanitization for stored content (comments, captions).
 *
 * Strategy: ENCODE rather than naively strip. We HTML-entity-encode the five
 * dangerous characters so the value is safe to render in any HTML context, even
 * if a downstream client mistakenly uses `innerHTML`. The Flutter client renders
 * plain text (`Text` widget) and is safe regardless, but encoding on write makes
 * the stored value defensively safe everywhere.
 *
 * We do NOT try to allow a subset of "safe" HTML — these fields are plain text.
 */

const HTML_ENTITY_MAP: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#x27;',
}

/** Encode the 5 HTML-significant characters. Order matters: `&` first. */
export function encodeHtmlEntities(input: string): string {
  return input.replace(/[&<>"']/g, (ch) => HTML_ENTITY_MAP[ch] ?? ch)
}

/**
 * Sanitize free-text for storage: strip control chars, then HTML-entity-encode.
 * Tags become inert entities (`<script>` -> `&lt;script&gt;`) rather than being
 * silently removed, which both neutralizes XSS and preserves the user's literal
 * text. Tab (\x09), newline (\x0A) and carriage-return (\x0D) are preserved.
 *
 * Use this only for values that may be surfaced in an HTML/innerHTML context.
 * For text rendered by the Flutter `Text` widget (plain-text, never HTML),
 * prefer `stripControlChars` so the user's `<`, `>`, `&`, quotes survive
 * verbatim instead of showing as literal `&lt;`/`&amp;` entities on mobile.
 */
export function sanitizeUserText(input: string): string {
  // eslint-disable-next-line no-control-regex
  const noControl = input.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
  return encodeHtmlEntities(noControl).trim()
}

/**
 * Minimal cleanup for plain-text stored content (comments, captions) rendered by
 * the Flutter `Text` widget. Strips C0/C1 control characters (which can corrupt
 * display or smuggle terminal escapes) and trims surrounding whitespace, but does
 * NOT HTML-entity-encode — the mobile client renders plain text, so encoding here
 * would corrupt the display (a user typing `a < b` would see `a &lt; b`).
 *
 * Tab (\x09), newline (\x0A) and carriage-return (\x0D) are preserved so
 * multi-line comments keep their formatting. Length capping is the caller's job
 * (Zod `.max(...)` on the field).
 */
export function stripControlChars(input: string): string {
  // eslint-disable-next-line no-control-regex
  return input.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '').trim()
}
