# ZVELT — Design System v2
> Light mode · premium · minimal · editorial · type-driven · single orange signal

The uploaded **ZVELT design system** is the single source of truth. Every screen
normalizes to these tokens. Feel: premium, breathable, calm-but-athletic, polished
like a production mobile product. Preserve consistency over creativity.

> Implemented in Dart as `ZveltTokens` + `ZType` in `zvelt_tokens.dart` (1:1 mirror).

---

## 1. Typography

| Role | Family | Used for |
|---|---|---|
| **Primary** | **Inter** | UI, headings, body copy, buttons |
| **Secondary (mono)** | **IBM Plex Mono** | BPM · pace · calories · distance · workout metrics · timestamps · labels · technical indicators |

Never use mono for body text, descriptions, buttons, or large content blocks.

### Type scale (Inter)
| Style | Size | Weight | Line height | Usage |
|---|---|---|---|---|
| Display XL | 52px | 600 | 120% | Hero, welcome |
| Display L | 42px | 600 | 120% | Large titles |
| Display M | 34px | 600 | 120% | Section headers |
| H1 | 28px | 600 | 120% | Page titles |
| H2 | 24px | 600 | 120% | Sub-section titles |
| H3 | 20px | 600 | 140% | Card titles |
| H4 | 18px | 600 | 140% | Small headings |
| Body L | 17px | 400 | 160% | Primary text |
| Body M | 15px | 400 | 160% | Secondary text |
| Body S | 13px | 400 | 160% | Supporting text |
| Mono S | 12px | 400 | 160% | Metrics, labels |
| Mono XS | 11px | 400 | 160% | Timestamps, tiny labels |

### Utility classes (tokens.css)
- `.z-display` / `.z-clean` — Inter 600, tight tracking (headings)
- `.z-stat` — Inter 600 tabular (KPI numbers: welcome total, big counts)
- `.z-num` — **IBM Plex Mono** 500 tabular (metric readouts: BPM, pace, distance, timers, weights)
- `.z-eyebrow` — IBM Plex Mono 500, 10px, uppercase, `--z-text-3` (technical labels)

---

## 2. Color system

### Neutral backgrounds
| Token | Value | Role |
|---|---|---|
| `--z-bg` | `#F6F7F5` | bg-primary — page |
| `--z-surface` | `#FFFFFF` | bg-secondary — card |
| `--z-bg-2` | `#EEF1ED` | bg-tertiary — inset block |
| `--z-surface-2` | `#FCFCFA` | bg-elevated — subtle inset |
| `--z-surface-3` | `#E6E8E4` | progress track / muted thumb |

### Text
| Token | Value | Role |
|---|---|---|
| `--z-text` | `#111111` | text-primary |
| `--z-text-2` | `#5F6360` | text-secondary |
| `--z-text-3` | `#939893` | text-tertiary (eyebrows, meta) |
| `--z-text-4` | `#BFC3BE` | text-disabled / dividers |

### Accent — orange is a **signal color only**
Use for: active states · key KPIs · focused indicators · progress highlights · FAB.
Never use for: large decorative fills · dominant backgrounds · gratuitous gradients.

| Token | Value | Role |
|---|---|---|
| `--z-brand` | `#FF7A2F` | accent-primary |
| `--z-brand-deep` | `#E86B24` | accent-hover / press / gradient anchor |
| `--z-brand-tint` | `#FFE4D2` | accent-soft — chip bg, hero halo |
| `--z-brand-3` | `#FFB088` | light variant — halo, XP |
| `--z-brand-glow` | `rgba(255,122,47,0.18)` | accent-glow |

### Biometric / category palette (one focus per screen)
| Token | Value | Category |
|---|---|---|
| `--z-recovery` | `#7BC6FF` | recovery (blue) |
| `--z-sleep` | `#A58BFF` | sleep (violet) |
| `--z-stress` / `--z-strain` | `#FFB86B` | stress (amber) |
| `--z-strength` | `#2EC27E` | strength (green) |
| `--z-cardio` | `#FF6B6B` | cardio (red) |

### Semantic
`--z-success #2EC27E` · `--z-info #7BC6FF` · `--z-warn #FFB86B` · `--z-error #E5484D`

---

## 3. Spacing — strict 4pt rhythm
`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48`

- Screen edge padding: **18px** L/R.
- Card-to-card gap: **12px**.
- Consistent internal card padding; generous vertical breathing.

---

## 4. Radius
| Token | Value | Use |
|---|---|---|
| `--z-r-sm` | 10px | tiles, inputs, small buttons |
| `--z-r-md` | 16px | mid chips & rows |
| `--z-r-lg` | 24px | **all cards** |
| `--z-r-xl` | 32px | modal sheets |
| `--z-r-pill` | 999px | pills, chips, FAB |

---

## 5. Elevation — subtle shadows only, no card borders
| Token | Value |
|---|---|
| `--z-shadow-card` | `0 1px 2px rgba(17,17,17,.02), 0 4px 12px rgba(17,17,17,.03)` |
| `--z-shadow-hero` | `0 8px 24px rgba(17,17,17,.04), 0 2px 6px rgba(17,17,17,.02)` |
| `--z-shadow-float` | `0 12px 36px rgba(17,17,17,.08)` |

Separation is shadow + spacing, never heavy borders.

---

## 6. Components
- **Buttons:** Primary (orange fill, white text) · Secondary (orange outline) · Tertiary (orange text)
- **Chips/Tags:** pill, soft tinted bg, category-colored dot + label (Run, Recovery, Sleep, Strength, Stress)
- **Progress/Indicator:** thin ring (orange on `--z-surface-3` track), light bar groups
- **Cards:** lightweight, calm, soft, minimally separated; consistent radius + padding; subtle sparklines

Charts stay subtle and low-noise: thin strokes, soft gradient fills, no glow or financial-dashboard density.

Navigation stays lightweight and non-dominant: no oversized tab bars, no heavy floating nav.

---

## 7. Restrictions
Avoid: crypto/gaming aesthetics · oversized type/buttons · aggressive gradients · heavy
shadows · glassmorphism overload · neon · clutter · unnecessary borders · inconsistent
spacing. Do **not** redesign UX flow or information architecture — normalize, refine, unify.
