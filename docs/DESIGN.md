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
- Entry sheet: springy slide-up; every pick (kind, category, account, date) gives haptic feedback (`HapticFeedback.selectionClick`) and a save gives `mediumImpact`
- List items: implicit animations on insert/remove (AnimatedList or animated switcher patterns)
- Page transitions: fade-through, 250–300 ms; never default jarring cuts
- All durations 200–450 ms; nothing bounces more than once

## Screen notes

- **Home:** hero block (net for the period, income/spent as small caption chips) → period bar → category bars (emoji, name, amount, thin animated bar as % of period max) → "Recent" (5) in the month lens, the whole day's entries in the day lens → FAB `+`
- **Period bar:** one line, `‹ Aug 2026 ⌄ ›` on the left and a segmented `Day · Month · Range` pill on the right. The date itself is the button: tapping it opens the picker for the current lens — the platform date picker for a day, a year-stepper + twelve-month grid for a month, a from/to sheet with presets (last 7 / 30 days, this month, last month, this year) for a range. The chevrons page one day, one month, or one range-length at a time, and never page into the future. Labels stay compact (`Aug 2026`, not `August 2026`) because the row is shared; the hero caption above spells the period out in full.
- **Range lens:** an inclusive span of whole days. The trend under the Stats donut buckets by day up to 31 days and by month beyond that, so a year-long range is twelve bars rather than 365. Home lists the range's entries capped at 50 — Home is a summary, not the ledger.
- **Money that does not fit:** amounts shrink before they truncate, and drop their currency symbol before they shrink into unreadability. Never ellipsize a number: `15 360…` is not an amount. A zero-decimal, high-denomination currency (soʻm) is several times wider than the same figure in dollars, and every money slot has to survive it.
- **Time and order:** every row shows its time of day, because the time is what orders a day. The entry sheet carries a time control under the date chips (its own line — four chips leave no room for "Yesterday" in Russian or Uzbek). In History, long-press a row to drag it into place inside its day; swipe still deletes. The lifted row scales slightly and never gains a Material drop shadow.
- **Transfers:** never rendered as income or expense. Neutral ink, an unsigned amount (it is the same money in a different pocket), a `🔄` medallion and the two accounts as the subtitle: `Cash → Savings`.
- **Entry sheet:** full-height modal. Big amount **field** top (live-formatted, see below), kind toggle (expense/income/transfer) as a segmented pill, category grid of emoji chips, an account strip, optional note field + date chip row (Today / Yesterday / pick) and a time chip
- **The amount is a real text field**, not a custom numpad *(changed 2026-08-21, owner's call; it was a numpad before)*. A field brings the platform's numeric keyboard, its caret, and — the reason for the change — **select, copy and paste**, which a grid of tap targets cannot offer. What it must not cost is the look, so the field keeps the hero numeral's face: oversized tabular figures, thousands grouping inserted **live as you type**, the locale's decimal separator, no more decimals than the currency has, and the currency symbol glued to the left of the number with the pair centred as one unit. It steps its face size down as the number grows rather than clipping. The keyboard is `numberWithOptions(decimal:)`, never `phone` — a dialpad offers `+`, `*` and `#`, and on iOS has no decimal key. A new entry opens with the field focused (the amount is what you came to type); an edit does not. Picking anything closes the keyboard, because the next thing after picking is always Save.
- **Stats:** donut with center total, tap slice → highlight + legend row emphasis; 6-month bar trend below
- **Empty states:** designed, warm, one-line copy + subtle illustration built from emoji/typography (no stock art)
- Bottom navigation: 4 items (Home, History, Stats, Settings), FAB centered or docked

## Anti-goals

No gradients-on-everything, no glassmorphism, no confetti, no red expense numbers, no dense data tables, no default Material widgets left unstyled (Chips, AppBars visibly default = fail).
