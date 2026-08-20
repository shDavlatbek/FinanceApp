# Tally — Design Direction

The bar: someone screenshots the Home screen and posts it in the repo README, and people star the repo because of how it looks. Not "clean Material demo" — a designed product.

## Aesthetic: "calm ledger"

Money apps scream (red alerts, dense tables). Tally is calm, dark, typographic. Numbers are the heroes; chrome disappears.

- **Dark-first.** Near-black ink surfaces, not gray Material dark. Light theme exists and gets equal care.
- **One accent.** Warm lime `#C8F55A` (dark) / deep green `#3E7C4F` (light) used *sparingly*: primary actions, income accents, active states. Expenses are neutral ink — spending is normal life, not an error. Red only for destructive actions.
- **Oversized numerals.** The month total is huge (48–64 pt, tight tracking, tabular figures). Everything else steps far down. Type scale contrast is the identity.
- **Soft depth.** 20–24 px card radii, hairline borders (8–12 % white), no drop-shadow soup.

## Tokens (dark)

| token | value |
|---|---|
| bg | #0E0F0C |
| surface | #171814 |
| surfaceRaised | #1E201A |
| border | #FFFFFF14 |
| textPrimary | #F4F5EF |
| textSecondary | #9A9C92 |
| accent | #C8F55A |
| onAccent | #10120B |
| income | #C8F55A |
| expense | #F4F5EF (neutral!) |
| danger | #E86A5A |

Light theme mirrors: bg #F7F7F2, surface #FFFFFF, textPrimary #191B14, accent #3E7C4F, borders #00000012. Category colors come from the seed palette in ARCHITECTURE.md and are used for bars/donut slices and category chips only.

## Typography

Bundle fonts as assets (offline app — no runtime fetching). **Manrope** for everything, with `FontFeature.tabularFigures()` on all money values. Weights: 800 for hero numbers, 700 titles, 600 buttons/chips, 500 body, 400 secondary. If Manrope can't be bundled, system font is acceptable — tabular figures still required.

## Motion (required, not optional)

- Hero month number animates on change (count-up/tween ~450 ms, `Curves.easeOutCubic`)
- Category bars grow in with staggered delays (~40 ms apart) on screen entry
- Entry sheet: springy slide-up; numpad keys give haptic feedback (`HapticFeedback.lightImpact`)
- List items: implicit animations on insert/remove (AnimatedList or animated switcher patterns)
- Page transitions: fade-through, 250–300 ms; never default jarring cuts
- All durations 200–450 ms; nothing bounces more than once

## Screen notes

- **Home:** hero block (net for the period, income/spent as small caption chips) → horizontal period switcher → `Day · Month` lens toggle → category bars (emoji, name, amount, thin animated bar as % of period max) → "Recent" (5) in the month lens, the whole day's entries in the day lens → FAB `+`
- **Period lens:** a small segmented `Day · Month` pill sits directly under the switcher, quiet enough never to compete with the hero number. Segmented text, not an icon — the same idiom as the entry sheet's income/expense toggle, and an unlabelled icon would fail the anti-goals below. Day mode reads `Today` / `Yesterday` / `Tue, Aug 19`; the trend under the Stats donut becomes 14 days instead of 6 months. The lens is per-device UI state, persisted locally — the bot has no use for it.
- **Transfers:** never rendered as income or expense. Neutral ink, an unsigned amount (it is the same money in a different pocket), a `🔄` medallion and the two accounts as the subtitle: `Cash → Savings`.
- **Entry sheet:** full-height modal. Big amount display top (live-formatted), custom numpad (not system keyboard), kind toggle (expense/income) as segmented pill, category grid of emoji chips, optional note field + date chip row (Today / Yesterday / pick)
- **Stats:** donut with center total, tap slice → highlight + legend row emphasis; 6-month bar trend below
- **Empty states:** designed, warm, one-line copy + subtle illustration built from emoji/typography (no stock art)
- Bottom navigation: 4 items (Home, History, Stats, Settings), FAB centered or docked

## Anti-goals

No gradients-on-everything, no glassmorphism, no confetti, no red expense numbers, no dense data tables, no default Material widgets left unstyled (Chips, AppBars visibly default = fail).
