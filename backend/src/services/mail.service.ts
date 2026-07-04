/**
 * Tiny transactional mail service (Resend HTTP API via global fetch — no npm
 * dependency). Configuration:
 *
 *   RESEND_API_KEY — Resend API key. When missing, emails are NOT sent; the
 *                    payload is logged server-side instead so dev/staging
 *                    flows (e.g. password reset codes) remain testable.
 *   MAIL_FROM      — From header, defaults to "Zvelt <onboarding@resend.dev>"
 *                    (Resend's sandbox sender, works without domain setup).
 *
 * Sending is strictly best-effort: this module never throws. Callers such as
 * the password-forgot endpoint must respond 200 regardless of mail outcome
 * (anti-enumeration), so failures are logged and swallowed here.
 */

const RESEND_ENDPOINT = 'https://api.resend.com/emails'
const DEFAULT_FROM = 'Zvelt <onboarding@resend.dev>'

interface SendEmailInput {
  to: string
  subject: string
  text: string
}

/** Send a plain-text email. Never throws; returns true when handed to Resend. */
export async function sendEmail({ to, subject, text }: SendEmailInput): Promise<boolean> {
  const apiKey = process.env.RESEND_API_KEY
  if (!apiKey) {
    // Server-side log only — nothing here reaches an API response. Callers
    // log their own dev fallback (e.g. the reset code) on `false`.
    console.log(`[mail] RESEND_API_KEY not set — skipped email to ${to}: "${subject}"`)
    return false
  }

  try {
    const res = await fetch(RESEND_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: process.env.MAIL_FROM ?? DEFAULT_FROM,
        to: [to],
        subject,
        text,
      }),
    })
    if (!res.ok) {
      const body = await res.text().catch(() => '')
      console.error(`[mail] Resend responded ${res.status} for ${to}: ${body}`)
      return false
    }
    return true
  } catch (err) {
    console.error(`[mail] failed to send email to ${to}:`, err)
    return false
  }
}

/** Password-reset code email. Never throws (see module docblock). */
export async function sendPasswordResetEmail(to: string, code: string): Promise<void> {
  const sent = await sendEmail({
    to,
    subject: 'Your Zvelt password reset code',
    text:
      `Your Zvelt password reset code is: ${code}\n\n` +
      'It expires in 15 minutes. If you did not request a password reset, ' +
      'you can safely ignore this email — your password will not change.',
  })
  if (!sent) {
    // Keep the code discoverable server-side ONLY in non-production (email not
    // configured in dev/staging). In production a mail failure must NOT print a
    // live reset code + address to the logs — that is an account-takeover vector
    // for anyone who can read them.
    if (process.env.NODE_ENV !== 'production') {
      console.log(`[mail] password reset code for ${to}: ${code}`)
    } else {
      console.error(`[mail] password reset email could not be delivered to ${to}`)
    }
  }
}
