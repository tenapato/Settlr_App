# Settlr Signal design system

Version 1.1, finalized August 29, 2026.

This document is the implementation reference for Settlr's iOS redesign. The companion preview is `settlr-signal-components.html` in this directory. Product behavior and screen architecture are specified in `docs/superpowers/specs/2026-08-28-signal-black-app-redesign-design.md`.

## Identity

Settlr is a dark financial tool with one bright signal. The system should feel sharp and energetic when the user acts, then get out of the way while they read money and status.

Dark is the default appearance. Settings also offers Light and System. System follows the iPhone appearance after the user selects it.

`SettlrApp` owns the appearance override. Screens and sheets inherit that choice. Leaf views never force Dark, including the scanner editor, split payment method sheet, Savings management, Categories, authentication, and workspace selection.

Use lime for selection, progress, focus, and the primary action. Do not fill every card with it. Near-black space is part of the identity.

The three offset bars are the Settlr mark. Use the existing asset. Do not redraw it with a different bar count, angle, or spacing.

## Color tokens

### Dark

| Token | Value | Use |
| --- | --- | --- |
| `color.bg` | `#090A0B` | App and full-screen modal background |
| `color.surface` | `#15181B` | Cards and grouped content |
| `color.raised` | `#1D2124` | Selected segments, popovers, elevated controls |
| `color.separator` | `#2D3135` | Hairlines and quiet borders |
| `color.ink` | `#F4F5EF` | Primary text and entered amounts |
| `color.muted` | `#898F92` | Supporting copy and inactive navigation |
| `color.faint` | `#6F7578` | Eyebrows, placeholders, tertiary metadata |
| `color.signal` | `#CAFF3A` | Primary action, selection, focus, live progress |
| `color.buttonInk` | `#080A08` | Text, icons, and progress on signal-filled controls |

### Light

| Token | Value | Use |
| --- | --- | --- |
| `color.bg` | `#F3F3ED` | App background |
| `color.surface` | `#FFFFFF` | Cards and sheets |
| `color.raised` | `#E9EBE4` | Selected neutral controls |
| `color.separator` | `#DADDD6` | Hairlines and quiet borders |
| `color.ink` | `#141614` | Primary text |
| `color.muted` | `#69706A` | Supporting copy |
| `color.faint` | `#7A817B` | Eyebrows and placeholders |
| `color.signalText` | `#597500` | Signal text and icons on light surfaces |
| `color.signalFill` | `#A8D522` | Primary filled controls |
| `color.buttonInk` | `#11140A` | Text, icons, and progress on signal-filled controls |

When Increase Contrast is enabled, separators strengthen from `#DADDD6` to `#AEB4AA` in Light and from `#2D3135` to `#596065` in Dark. Muted and faint ink strengthen at the same time. Screens keep using the semantic tokens rather than branching on accessibility settings themselves.

### Semantic colors

Semantic colors explain money or risk. They do not replace the brand signal.

- Expense and destructive: `#D26462` dark, `#A44340` light.
- Income and funded: use signal lime in dark and signal olive in light.
- Warning: `#E4B65C` dark, `#815E00` light.
- Error copy must meet WCAG contrast against its surface.

Do not rely on color alone. Pair it with a sign, icon, label, or status text.

## Typography

Use the SwiftUI system font. Apply `.monospacedDigit()` to money, percentages, dates that update in place, and settlement progress.

| Role | Reference size | Weight | Notes |
| --- | ---: | --- | --- |
| Display amount | 38–52 pt | Semibold/Bold | Tabular, scales down for long values |
| Screen title | 28–34 pt | Bold | Tight optical tracking where supported |
| Section title | 17–20 pt | Semibold | Sentence case |
| Body | 15–17 pt | Regular/Medium | Default reading copy |
| Supporting | 12–14 pt | Regular | Metadata and explanations |
| Eyebrow/status | 10–11 pt | Semibold | Tracked uppercase, short phrases only |

Dynamic Type wins over the reference sizes. Do not cap body text below the user's requested size. Reflow layouts before reducing type.

Use semantic text styles for labels and reading copy. Display money may use `@ScaledMetric` relative to `.largeTitle`, with one-line scaling as a final guard for unusually long amounts. Fixed sizes are reserved for icons and small geometry, not text.

## Spacing and shape

The base unit is 4 pt. Prefer 8, 12, 16, 20, 24, and 32 pt gaps.

| Component | Shape |
| --- | --- |
| Global launcher | 52 pt circle in a 58 pt hit target |
| Tab bar | Continuous capsule |
| Content card | 18 pt continuous radius |
| Sheet | Native presentation with 24–28 pt top corners where custom |
| Field/control | 12–14 pt continuous radius |
| Icon container | 10–12 pt radius or true circle |
| QR logo plate | Rounded square with required scan quiet zone |

Every interactive element has a minimum 44 by 44 pt target, even when its visible shape is smaller.

## Elevation and borders

Settlr uses contrast before shadow. A surface can be distinguished by its fill, a one-pixel separator, or both. Use shadow only for floating navigation, the satellite launcher, and an actively presented sheet.

Do not nest bordered cards unless the inner object is genuinely independent, such as a credit card inside a management sheet.

## Components

### Settlr mark

Use `SettlrLogo` from the asset catalog. The mark may appear in lime on charcoal or charcoal on lime. Keep clear space equal to at least one bar height around it.

### Hero amount field

This component is retained from the current app and is part of the product identity.

- Center the currency code above the value.
- Center the currency symbol and tabular amount as one baseline group.
- Keep open background around the amount. Never place it inside a card.
- Use a thin neutral underline at rest and signal underline on focus.
- Use semantic color on the currency symbol. Entered digits use primary ink.
- The entire hero region activates the decimal keyboard.
- Place specific validation below the underline.

Use it for expenses, income, savings entries, card payments, and manual split totals.

### Signal rows

Signal rows are the default detail treatment below a hero amount.

- No outer container.
- Full-width hairline separators.
- Leading label, trailing value, optional disclosure indicator.
- The whole row is tappable.
- Use native pickers and navigation destinations after selection.
- Put the submit button outside the rows.

### Primary button

A filled signal control with dark text. Default height is 50 to 52 pt with a 14 pt continuous radius. Use one primary button per visible task area.

Disabled state lowers contrast without removing the label. Loading keeps the button width stable and replaces or accompanies the label with a native progress indicator.

### Secondary button

Use a neutral surface with a separator border. Text remains primary ink. Secondary buttons can sit beside one another when their importance is equal, such as Copy link and Share.

### Destructive button

Use semantic red text on a neutral background or native destructive role. Do not use a filled red button unless the screen is solely a destructive confirmation.

### Floating tab bar

Show the feature-aware subset of Home, Activity, Savings, and Cards. Every destination keeps its SF Symbol and short label visible in a stable vertical stack. The current item is lime; selection never changes item width or adds a pill. Reserve clear space between the capsule and the separate C6 launcher.

### C6 launcher

The visible control is a 52 pt lime circle with a standard plus. Keep its outer ring subtle. Pressing compresses the full control to 94% for 120 ms. On expansion, the plus rotates 45 degrees with a restrained 280 ms spring while the control becomes charcoal and the satellite menu opens above it. Never pulse the launcher while idle. With Reduce Motion, keep the control at full scale and swap directly between plus and close symbols without rotation.

### Signature Scanner menu

Every action uses the same row and column geometry: one 30 pt icon column and one shared text column. `Scan and split` remains the signature action through its filled lime icon and stronger title weight, not a wider or taller row. Expense, Income, and Savings use neutral icon circles. Hide actions whose feature is unavailable.

### Segmented control

Use the native segmented pattern for mutually exclusive, closely related options such as By item and Evenly. For payer mode, use two explicit selectable rows because the accounting consequence needs supporting copy.

Every segment announces its label and `Selected` or `Not selected` value. The current option carries the selected accessibility trait. Reduce Motion changes selection without a spring.

### Content cards

Use cards for objects with their own identity or state: savings accounts, credit cards, goal summaries, and result summaries. Do not use a card as a universal section wrapper.

### Activity timeline item

- Align a neutral node to a thin vertical spine.
- Use one lime pulse for the newest event.
- Keep the amount in the event context line.
- Do not add a surrounding row card or a detached amount column.
- Show compact semantic markers only when they prevent ambiguity.

### Fortnight navigator

The approved Cards control is borderless. It has previous and next arrows, a centered exact date range, and a short signal underline. `All cards` belongs in overflow.

### QR sheet

Use a native sheet. Place the Settlr mark in the QR center only when the QR library supports an error-correction level and reserved quiet zone that remains reliably scannable. Keep merchant, amount, and privacy copy outside the code. Encode a join URL, not account or payment details.

### Empty state

Use one compact glyph, a direct title, one short explanation, and one action that resolves the state. Avoid large illustrations.

### Loading state

Choose the loader by context:

- Signal trace for background refresh. Keep cached content visible and show its last update time when useful.
- Settlr pulse for a cold start or workspace change with no content to show. Stack three 31 × 5 pt horizontal bars inside a 65 pt raised tile, offset the middle bar by 5 pt, and light them in sequence. Pair a specific headline such as `Getting your workspace` with one short detail line. Do not place a second logo above the pulse mark.
- Screen-shaped skeleton only when the incoming geometry helps orientation, such as the first Activity timeline load.

After a delay, expose Retry or a specific recovery path. Reduce Motion holds one signal bar or the mark static. Do not shimmer every screen by default.

### Error state

Explain what failed and what remains safe. Keep the relevant retry action nearby. Field validation belongs beneath the field. A network error must not erase valid cached information.

Home uses the exact recovery promise `Saved Home data is still visible and may be out of date.` Categories, Cards, Activity, and Savings use the same honest pattern with screen-specific copy. A failed month change keeps the current and comparison summaries from the same successful snapshot.

## Navigation patterns

- Tabs own their navigation stacks.
- Detail screens push.
- Creation and editing use native sheets when they are bounded tasks.
- Signature Scanner uses a full-screen modal stack.
- Settings and workspace selection belong to the profile modal.
- Completion returns to the originating context. It does not switch tabs or reset a stack.

## Screen recipes

### Home

Workspace/profile, available amount, three-part summary, preserved insight ticker, recent activity.

### Activity

Title, compact filter row, attention item for open splits when needed, Signal timeline.

A closed split enters the financial timeline only through its persisted owned Expense. Never infer an organizer debit from the split total: each-own splits and a partial expenses-route failure make that amount categorically unsafe. The owned Expense appears exactly once and carries the Split marker.

### Savings

Total saved, month movement, account objects, target progress when provided, recent entries.

### Cards

Due summary, approved fortnight navigator, swipeable cards, payment status and action.

### Signature Scanner

Capture, Review, payer/division choice, assignment, Result, QR sheet.

While `Scan again` is reading OCR or waiting on parsing, the editor fields and save action stay locked. The scan button shows the in-flight state so a late response cannot overwrite edits made during the request.

### Authentication and workspace

Authentication uses the existing logo, adaptive compact fields, one filled primary action, and inline service errors. The layouts scroll for the keyboard and accessibility text sizes. Apple controls switch to their readable system style for the active appearance.

Workspace bootstrap uses `Getting your workspace` with the Settlr pulse. Workspace selection reserves cards for real workspace objects. Create workspace is a separate primary action, and a load failure keeps sign-out available while offering Retry.

## Bill-split language

Use the current accounting language consistently:

- `I paid it all`
- `Each paid their own`
- `By item`
- `Evenly`
- `Paid the bill`
- `Owes you`
- `Paid you back`
- `Everyone paid their own share`
- `Everyone has settled up`

Do not describe an `each_own` split as collecting. Do not show mark-paid controls when nobody owes the organizer.

A closed split with recorded settlements cannot reopen claiming or editing. Its action routes to `Undo settlements to reopen`, and the explanation tells the organizer to undo every settlement first.

## Feature gates

Build tabs, launcher actions, filters, and subviews from the current availability helpers. A hidden feature must not leave behind a picker value, empty tab, or request to a gated route.

When access, user, or workspace changes, dismiss every affected presenter and cancel delayed launcher work. A delayed action rechecks the captured user, workspace, and feature immediately before presentation.

Home is always present. Activity appears when any of expenses, income, or bill splits is available. It includes savings events only when Savings is enabled. Savings requires `savings`. Cards and card management require `credit_cards`. Payment summaries require `credit_cards` and `card_payments`. Bill splitting requires `bill_splits`.

## Accessibility checklist

- 44 pt minimum targets.
- Dynamic Type at accessibility sizes.
- VoiceOver label, value, hint, and trait where useful.
- Currency-aware amount speech.
- Selected traits and values for filters, segmented choices, account chips, and selectable cards.
- Color-independent status.
- Reduce Motion alternatives for ticker, scanner, and launcher.
- Increase Contrast support for separators and muted ink.
- Keyboard focus and dismissal for every form.
- QR action has a visible text label.
- Haptics supplement visual feedback and never replace it.
- Editors that can receive a late network or OCR response lock conflicting fields while the request is in flight.

## Motion

Use motion to explain cause and effect. Standard durations should feel native rather than branded for their own sake.

- Tap response: immediate.
- Small selection transition: about 150 to 220 ms.
- Launcher: restrained spring, no bounce loop.
- Ticker: about 30 pt per second with touch pause and 2.5 second resume.
- Scanner: movement only during actual processing.
- Reduce Motion: fade or static content.

## Content rules

- Use sentence case.
- Prefer exact dates and amounts over vague labels.
- Put status in plain language.
- Avoid congratulatory copy for ordinary bookkeeping.
- Error messages say what happened and what the user can do.
- Keep currency visible whenever an amount could be ambiguous.

## Engineering rules

- SwiftUI native controls first.
- SF Symbols first.
- Server values remain authoritative for financial state.
- Detail GET responses use request generations and cannot overwrite a newer split mutation or refresh.
- Decode new optional response fields safely.
- Preserve the existing pending split queue and `409` conflict behavior.
- Do not introduce an endpoint when existing route data can support the design.
- Test the production QR, not the styled HTML stand-in.
- Keep visual tokens centralized and semantic. Screens do not hard-code duplicate hex values.

## Review checklist

Before a screen is complete, confirm:

1. The primary amount or status is obvious in one glance.
2. There is only one strongest action.
3. Lime has a job.
4. Cards group real objects rather than arbitrary rows.
5. The screen works when optional features are absent.
6. Loading, empty, error, offline, and stale states exist.
7. Dark, light, Dynamic Type, VoiceOver, Reduce Motion, and Increase Contrast are checked.
8. Saving or dismissing returns to the right context.
9. The screen uses current server fields and does not invent money state.
