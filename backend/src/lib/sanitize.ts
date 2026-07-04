/**
 * User-generated-text sanitization for stored content (comments, captions).
 */

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
