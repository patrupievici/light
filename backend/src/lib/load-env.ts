import fs from 'node:fs'
import path from 'node:path'

/**
 * Load `backend/.env` into `process.env` when keys are unset (no dotenv dependency).
 * Supports `KEY=value` and optional surrounding quotes on value.
 */
function parseEnvFile(envPath: string): void {
  if (!fs.existsSync(envPath)) return
  const text = fs.readFileSync(envPath, 'utf8')
  for (const line of text.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq <= 0) continue
    const key = trimmed.slice(0, eq).trim()
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue
    let val = trimmed.slice(eq + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    if (process.env[key] === undefined) process.env[key] = val
  }
}

export function loadEnvFile(): void {
  try {
    const root = process.cwd()
    const dotEnv = path.join(root, '.env')
    const legacyEnv = path.join(root, 'env')
    if (fs.existsSync(dotEnv)) {
      parseEnvFile(dotEnv)
    } else if (fs.existsSync(legacyEnv)) {
      parseEnvFile(legacyEnv)
    }
  } catch {
    // ignore missing/unreadable env files
  }
}
