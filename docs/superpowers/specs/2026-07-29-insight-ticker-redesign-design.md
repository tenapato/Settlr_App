# Dashboard insight ticker redesign

## Context

The dashboard's "Spending Insights Strip" (`Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift`) was recently added to replace two redundant, oversized category cards (a donut chart and a bar-list). It renders a composition bar + legend followed by a horizontally-scrollable row of bordered `InsightTile` cards (fixed 148×84pt, one per qualifying insight).

Real test data (a workspace with $20 total spend, all in one uncategorized bucket) exposed two problems, refined into this design across a brainstorming session:

1. **Card sizing was broken, not padded.** `InsightTile` forced a fixed 84pt height with a `Spacer` + `.frame(alignment: .topLeading)` hack. When content was short, the leftover space below the text was untethered dead space, not real padding — it read as a layout bug rather than a design choice.
2. **The row itself felt wrong.** A manually-swiped row of 2-5 bordered cards reads as an unfinished, arbitrarily-truncated list ("infinite scroll of cards"), especially when only 1-2 insights qualify and the row doesn't fill the screen width. The user wants the glanceable, always-moving feel of a financial stock ticker instead — something that keeps changing on its own rather than sitting static waiting to be swiped.

This spec supersedes the initial "fix `InsightTile` padding" plan — that card is being removed entirely in favor of a ticker-tape display, which makes the padding question moot.

## Decisions made during brainstorming

- **Style: literal auto-scrolling ticker tape** (Approach A of three presented), not an auto-advancing single-card carousel or a snap-scrolling row. Chosen explicitly over the more "readable" carousel option because the user wants the stock-ticker aesthetic specifically.
- **Data must be simplified** to compensate for the reduced legibility of scrolling text (vs. the carousel alternative, which would have kept full detail).
- **Manual override required**: touching the ticker stops it; it is not a pure unstoppable animation.
- **Auto-resumes after a short idle period** (~2.5s) rather than staying manual for the rest of the visit — matches patterns like Apple Music's "Up Next" or the App Store featured banner.
- **Composition bar + legend and the insight-selection engine (`SpendingInsights.build`) are explicitly out of scope** — only the display of already-selected insights changes.

## Design

### 1. Simplified ticker item format

Each `SpendingInsight` collapses to a single line instead of today's four (eyebrow / title+swatch / value / detail):

```
<glyph> <short label> <value>
```

- **glyph**: the category color dot (`swatch`) when present; nothing otherwise. No separate directional arrow is added — `signedPercentString` (used by the biggest-increase/decrease, vs-last-month, and vs-average insights) already bakes a ▲/▼ into the value text itself, so a second glyph would duplicate it.
- **short label**: the category name, or a short static phrase for non-category insights ("Ahorraste", "Subiste", "Top 3 categorías").
- **value**: the single most important number (the percentage in almost every case) — colored by `SpendingInsight.Tone` exactly as today.

The eyebrow text (`MAYOR GASTO`, `GASTO NUEVO`, ...) and the currency `detail` line are dropped from the ticker display. Nothing is deleted from the `SpendingInsight` model — `build()` is untouched — this is purely a new, terser rendering of the same data. Full detail remains one tap away via the existing `onOpenCategories` navigation to the Categories tab.

Examples:
```
● Sin categoría 100%   ·   Food & drink ▲ +142%   ·   Ahorraste 74%
```

### 2. Visual style

No bordered card / chip. Plain colored text directly on the dashboard background (`Theme.bg`), matching a real ticker tape rather than a row of app cards. Items are separated by a `Theme.faint` `·` dot. Font: `.system(size: 13, weight: .semibold, design: .rounded)`, `.monospacedDigit()` on the value portion.

### 3. Marquee mechanics

- The full simplified-item sequence is laid out once in an `HStack`, its total width measured (via a `GeometryReader`/`PreferenceKey`, the existing project idiom for measuring — see `AnnualEvolutionChart`'s use of `GeometryReader`), then rendered **twice back-to-back** inside the scrolling container so the loop point is never visible.
- A continuously-incrementing offset (driven by `TimelineView(.animation)`, which this codebase hasn't used yet but is standard SwiftUI and dependency-free) moves the double-wide content left at a constant rate (~30pt/sec — tuned during implementation for comfortable reading speed). Once the offset passes the width of one copy, it wraps by subtracting that width, so the animation is imperceptibly seamless.
- If there are 0 qualifying insights, the ticker section doesn't render at all (matches the existing `SpendingInsightsStrip` empty-state behavior).

### 4. Interaction

- A `DragGesture(minimumDistance: 0)` on the ticker: on first touch, the auto-advance timer stops immediately (offset freezes where it is).
- While dragging, the offset tracks the finger 1:1 (standard drag-to-scroll, wrapped with the same modulo logic so it loops in both directions).
- On release, after **2.5s** of no further touch, auto-scroll resumes from the current offset at the same constant rate.
- A tap (drag ends with ~0 translation) on a specific item still calls `onOpenCategories`, same as the current `InsightTile` button behavior — tap-to-navigate is preserved, only continuous dragging is new.

### 5. Accessibility default

When `\.accessibilityReduceMotion` is true, the ticker does not auto-scroll — it renders as a static, manually-swipeable row (plain `ScrollView(.horizontal)` of the same simplified single-line items, no animation loop). This is a standard iOS expectation for any perpetually-moving UI and costs little to add alongside the rest of this work.

### What's unchanged

- `SpendingCompositionBar` (the bar + legend above the ticker) — untouched.
- `SpendingInsights.build(current:previous:months:)` — untouched; still returns up to 5 `SpendingInsight` values, same scoring/selection logic.
- `SpendingInsightsStrip`'s outer header, empty-state gating, and reveal animation on appear — untouched.
- Tap-through navigation to the Categories tab (`onOpenCategories`) — preserved.

### Files touched

- `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift` — `InsightTile` is deleted; a new ticker view (working name `InsightTicker`) replaces `tilesRow`'s `ScrollView(.horizontal)` of `InsightTile`s.

No new file, no `project.pbxproj` change, no model or view-model change.

## Verification

1. Build: `xcodebuild -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath build build`.
2. Visual: dashboard's insight row auto-scrolls continuously and loops with no visible seam or jump, at a speed where each item is comfortably readable.
3. Touch the ticker mid-scroll: it stops immediately; dragging moves it 1:1; releasing resumes auto-scroll after ~2.5s.
4. Tap (not drag) an item: navigates to the Categories tab, same as before.
5. Enable Reduce Motion (Simulator: Settings → Accessibility → Motion → Reduce Motion) and confirm the ticker becomes a static, manually-swipeable row instead of auto-scrolling.
6. Confirm this works correctly with both 1 qualifying insight (the degenerate case from the original screenshot) and 5 (the max).
