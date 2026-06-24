// Side-effect module: load backend/.env into process.env BEFORE anything that
// reads env (prisma, deepseek). Import this FIRST. Dependency-free.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

try {
  const txt = readFileSync(resolve(process.cwd(), '.env'), 'utf8')
  for (const line of txt.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/)
    if (!m) continue
    let v = m[2].trim()
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1)
    }
    if (process.env[m[1]] === undefined) process.env[m[1]] = v
  }
} catch {
  /* no .env — rely on the ambient environment */
}
