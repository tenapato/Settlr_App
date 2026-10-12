# Settlr Signal Black app redesign

## Purpose

Redesign the signed-in iOS app without changing the accounting rules that users already rely on. The current app has enough information and working authentication and workspace flows, but its screens do not share a clear hierarchy or recognizable product identity. Navigation also makes related features hard to find.

The redesign gives Settlr one visual system, a stable four-tab structure, and a signature receipt-to-split journey. Existing data, endpoints, feature gates, and ledger behavior remain authoritative.

## Scope

This spec covers:

- Home and its existing insight carousel.
- A unified Activity ledger for expenses, income, savings, and bill-split events.
- Savings accounts, entries, recurring rules, and optional goal targets.
- Credit cards and fortnight-based payment tracking.
- Receipt scanning, bill creation, public joining, item claims, settlement, QR sharing, and offline behavior.
- The global quick-action launcher.
- Common forms, sheets, loading states, empty states, errors, appearance, and accessibility.
- Visual alignment of authentication, workspace selection, and settings.

Authentication and workspace behavior are not being reworked. Their layouts adopt the new tokens and components while preserving their current navigation and API contracts.

The public web Panel is outside this app redesign except where an existing public split link opens it.

## Product principles

1. Money gets the strongest hierarchy. Decoration never competes with amounts or status.
2. Lime marks action, selection, and live progress. It is not a background treatment for every card.
3. Forms and lists stay open and border-light. Rounded containers group real objects, not arbitrary sections.
4. The app uses native SwiftUI navigation, sheets, controls, keyboard behavior, haptics, and accessibility semantics.
5. The server remains the source of truth for balances, split versions, settlements, card payment state, and savings goal calculations.
6. Existing capabilities do not disappear in the redesign. If a feature is unavailable for a user, the related UI is removed before any gated endpoint can be called.

## Identity: Signal Black

Signal Black is sharp, high-contrast, and quiet around the data. The visual reference mix is Phantom's energy, Bitso's compact financial navigation, and the reading clarity of modern personal-finance tools. Settlr does not copy their layouts or branding.

The product signature is a lime signal on a near-black field. The existing three-bar Settlr mark remains the brand mark. Circles identify actions. Capsules are reserved for the floating tab bar and segmented selection. Continuous rounded rectangles represent cards, sheets, and controls.

### Core colors

Dark appearance:

- Background: `#090A0B`
- Surface: `#15181B`
- Raised surface: `#1D2124`
- Separator: `#2D3135`
- Primary ink: `#F4F5EF`
- Muted ink: `#898F92`
- Signal lime: `#CAFF3A`

Light appearance:

- Background: `#F3F3ED`
- Surface: `#FFFFFF`
- Raised surface: `#E9EBE4`
- Separator: `#DADDD6`
- Primary ink: `#141614`
- Muted ink: `#69706A`
- Readable signal text: `#597500`
- Signal control fill: `#A8D522`

Semantic expense, warning, and destructive colors may appear where their meaning is required. They do not become competing brand accents. Lime text on a light surface uses the deeper olive token.

### Type

Use SF Pro through SwiftUI system fonts. Large money uses tabular digits and an optical size that can shrink for long values before truncating. Supporting labels use sentence case except for small status eyebrows, which may use tracked uppercase.

Recommended roles:

- Display amount: 38 to 52 pt, semibold or bold, tabular digits.
- Screen title: 28 to 34 pt, bold.
- Section title: 17 to 20 pt, semibold.
- Body: 15 to 17 pt.
- Supporting text: 12 to 14 pt.
- Eyebrow and status: 10 to 11 pt, semibold, tracked.

Dynamic Type takes priority over fixed mockup sizes. Amounts may scale within a bounded range to protect layout.

### Shape and spacing

- Global action: true 52 pt circle inside a minimum 58 pt hit area.
- Tab bar: compact capsule with continuous corners.
- Content card: 18 pt continuous corner radius.
- Field or compact control: 12 to 14 pt continuous corner radius.
- Icon container: 10 to 12 pt radius unless the icon is inside a circle.
- Minimum interactive target: 44 by 44 pt.
- Base spacing unit: 4 pt. Common gaps are 8, 12, 16, 20, 24, and 32 pt.

### Icons and motion

Use SF Symbols wherever a system symbol exists. Custom marks are limited to the Settlr logo and scanner framing.

Navigation uses native push and sheet transitions. The launcher uses a restrained spring and a light selection haptic. Continuous data such as the dashboard ticker moves only because motion explains its behavior. Reduce Motion replaces perpetual movement and spatial transitions with static scrolling or fades.

## Information architecture

The signed-in root has four possible tabs:

1. Home
2. Activity
3. Savings
4. Cards

Each tab owns a `NavigationStack`. Returning to a tab preserves its stack. Dismissing a global form returns to the tab and position where it was opened. Forms never switch tabs after saving.

Card payments live inside Cards. Categories live under Activity. Workspace and settings live behind the profile control. Bill splits can be opened from Activity and from the global launcher.

### Feature-aware tab rules

The app builds navigation from `MeUser.disabledFeatures` through the existing `AppFeature` and availability helpers.

- Home is always available because the summary endpoint is not feature-gated.
- Activity appears when at least one of expenses, income, or bill splits is available. Savings events join its timeline only when Savings is also enabled.
- Savings appears only when `savings` is enabled.
- Cards appears only when `credit_cards` is enabled.
- Credit-card management requires `credit_cards`.
- Payment summaries and paid-state mutations require both `credit_cards` and `card_payments`.
- Bill-split actions require `bill_splits`.

Unavailable tabs, filters, launcher actions, and form rows are removed rather than disabled. This prevents avoidable `403` responses.

## Floating navigation and launcher

The floating tab bar remains a compact dark capsule. It shows the available subset of Home, Activity, Savings, and Cards with an SF Symbol and short label. The selected tab uses lime. Unselected items use muted ink. A separate circular launcher floats at the lower right.

### Resting launcher

The approved C6 launcher is a 52 pt lime circle in a 58 pt hit target. It contains a standard-weight plus and a subtle outer ring. It is not fused to the tab-bar capsule.

### Expanded launcher

Opening the launcher dims the full app and changes the plus into a charcoal close control. The approved satellite menu contains:

- A lime `Scan and split` hero action.
- Expense.
- Income.
- Savings, when available.

The menu stays anchored to the launcher and expands upward. It does not reflow the tab bar. VoiceOver focus moves into the menu. Escape, tapping the dimmed background, or selecting an action closes it.

## Home

Home answers one question first: what is available this month?

The primary amount is computed on the client as `summary.netCents - savingsNetCents`. This is presentation arithmetic over server totals, not a new endpoint or stored balance.

The screen order is:

1. Workspace and profile header.
2. Available-this-month hero.
3. Income, spending, and saved summary.
4. Existing insight carousel and composition strip.
5. Compact recent activity.

### Existing carousel

Preserve the current `SpendingInsights.build` selection and the approved ticker behavior:

- At most five insights.
- About 30 pt per second.
- Seamless looping.
- Touch pauses immediately.
- Drag moves one-to-one.
- Auto-resume after about 2.5 seconds of inactivity.
- Tap opens the related insight destination.
- Reduce Motion shows a static horizontal row.

The redesign may restyle the surrounding header and spacing. It must not replace the carousel with static cards or change its ranking logic.

## Activity

Activity is one chronological ledger, not separate expense and income tables. Available filters adapt to enabled features.

### Signal timeline

Events are grouped by day and placed on a thin vertical spine. The newest event has one lime pulse. Other events use neutral nodes. There are no row cards and no full-width dividers.

Each event shows:

- Description or merchant.
- Category, payment source, or event context.
- Time.
- Amount with a semantic sign.
- Compact markers such as `Split`, `Savings`, or `Card` only when needed.

The amount belongs to the event's context line instead of forming a detached table column. Tapping an event opens a transaction detail sheet or the relevant split, savings, or card detail.

Open bill splits may appear as a separate attention item above the timeline. Completed splits appear once as the owned expense with a `Split` marker. The ledger must not duplicate the same bill as an expense and a second completed event.

### Filters

Keep filters compact and immediately understandable. Use a horizontal row of content-sized chips for event type and period, with the current selection stated in plain language. The filter sheet handles longer lists such as categories and payment sources. Active filters show a count and expose a one-tap reset.

## Savings

Savings opens with total saved, this-month movement, and account objects. Accounts may be flexible or target-based.

### Target accounts

A target account may show:

- Target amount.
- Target date.
- Current funded amount.
- Remaining amount.
- Progress percentage.
- Funded state.

These values depend on the approved Server branch `feat/savings-goal-targets`, commits `28574a2` and `a2c8d31`. That work adds `targetAmountCents`, `targetDate`, `goalStatus`, `progressPct`, and `remainingCents` while preserving flexible accounts with no target.

The app must treat server-provided goal status and progress as authoritative. It may animate from the old displayed progress to the new one, but it must not independently decide whether an account is funded.

### Savings navigation

- Root to account detail.
- Account detail to add or withdraw entry sheet.
- Root overflow to account management modal.
- Recurring savings remains available from the account or management context.

## Cards

Cards combines card objects with payment status. The screen starts with the due summary, followed by horizontally swipeable card faces and their current payment details.

### Fortnight navigator

Use the approved B finish:

- No enclosing container.
- Borderless previous and next arrow buttons with 44 pt hit targets.
- Exact date range centered, such as `16–31 Aug`.
- Short lime underline under the selected range.
- `All cards` moves into the overflow menu.

The control supports previous, current, next, and all-card views. Cross-month fortnights merge the correct server month summaries. Mark-paid and unmark-paid calls continue sending the resolved due month. The selection gives light haptic feedback.

### Card payment behavior

The redesign preserves:

- Card summary from `/card-payments/summary`.
- `Mark as paid` and `Undo paid status`.
- Paid and open states.
- Outstanding amount.
- Card management and archived-card behavior.

The app does not infer paid state from a zero amount. It uses the server's `paidInFull` state.

## Signature scanner and bill splitting

`Scan and split` opens a full-screen modal with its own navigation stack. The tab bar and launcher do not appear over this flow.

### 1. Capture

- Native camera preview and photo picker.
- Simple receipt frame with four lime corners.
- A scan line only while actual analysis is running.
- Capture, flash, close, and choose-photo targets meet the 44 pt minimum.
- Reduce Motion holds the scanner cue static.

### 2. Review

- Merchant, date, total, payment method, and category summary.
- Parsed line items.
- Confidence shown as calm status copy.
- Only uncertain fields request attention.
- Retake and edit remain available.

The current receipt parser and `/bill-splits/scan-receipt` response remain authoritative. The app keeps a printed total that does not exactly reconstruct from line items and shows the existing reconciliation warning.

### 3. Payment and division rules

The app asks who paid before asking how the bill is divided because payer mode changes ledger accounting.

Payer choices:

- `I paid it all` maps to `payer = me`. The full bill is the organizer's expense. Guest repayments are recorded as income.
- `Each paid their own` maps to `payer = each_own`. Only the organizer's share becomes their expense. No reimbursement debt is created.

Division choices:

- `By item` maps to `splitMode = by_item`.
- `Evenly` maps to `splitMode = even`.

The flow preserves headcount, optional guest names, payment method, card selection, tips, tax, unclaimed amounts, shared quantities, manual editing, and pass-the-phone claiming.

### 4. Result and settlement

For `me`, result and detail screens show who owes what, collection progress, `Mark paid`, and Undo. Editing money stays locked while settlements exist. The organizer must undo settlements before changing frozen amounts.

For `each_own`, result and detail screens say that everyone paid their own share. They show individual shares and never show collection or mark-paid controls.

Open and closed claiming, safe reopening, split deletion, status copy, and existing participant permissions remain unchanged.

### QR handoff

The result keeps `Share split` as the primary action and a persistent `Show QR` secondary action. `Show QR` opens a native sheet with:

- The existing three-bar Settlr mark inside the QR's protected center area.
- Merchant and split context outside the code.
- Copy-link and system-share actions.
- A join URL rather than sensitive amount or account data encoded directly.

The production QR generator must reserve enough quiet space around the logo and be scan-tested at supported display sizes, brightness levels, and both appearances.

### Concurrency and offline behavior

Bill-split version conflicts remain server-authoritative. A `409` refreshes the split, retains safe local intent where possible, and explains what changed before retrying.

The existing durable queue remains limited to supported split creation work. The app exposes queued state without presenting it as completed. Card identifiers and payment-method edits are not queued when they require fresh server validation.

## Forms and sheets

The current large `HeroAmountField` is retained as a signature component. It is used for expense, income, savings entry, card payment, and manual split total entry where applicable.

### Hero amount field

- Currency code centered above the amount.
- Large centered tabular number.
- Semantic currency symbol.
- Thin underline.
- No surrounding card.
- The whole hero area focuses the decimal keyboard.
- Long amounts shrink within a safe range before truncation.
- Focus may brighten the amount and signal underline.
- Invalid state uses specific copy beneath the underline.

### Signal rows

The approved A treatment replaces the heavy grouped form card beneath the hero:

- Borderless full-width rows.
- Hairline separators.
- Label on the leading edge and current value on the trailing edge.
- Native picker or pushed selection when tapped.
- The primary submit button sits separately at the bottom.

Compact rounded fields remain valid for focused text editing, authentication, or a sheet where the field itself needs a visible boundary. They are not the default wrapper for every form row.

## System states

### Loading

Loading uses three approved treatments according to context:

- Signal trace for background refresh. A thin lime trace appears beneath the relevant header while cached content remains readable. Show the last successful update time when it helps.
- Settlr pulse for a cold start or workspace change with no useful content yet. The existing three-bar mark lights one bar at a time beside specific loading copy.
- Screen-shaped skeleton only when its geometry helps the user understand what is coming, such as the first Activity timeline load. It is not the universal loader.

After a reasonable delay, replace indefinite reassurance with a specific retry or recovery action. Reduce Motion shows a static lime bar or mark instead of repeated motion.

### Empty

Use one compact symbol, a direct explanation, and one resolving action. Avoid large decorative illustrations and generic encouragement.

### Error

Keep the last valid data on screen when possible. Say what failed, what remains safe, and what the user can do next. Inline validation stays next to the field. Network and synchronization states are not presented as successful completion.

### Appearance

Settings offers Dark, Light, and System. The default is Dark. System follows the iPhone appearance when the user chooses it. Light mode uses warm off-white and deeper olive accent text to maintain contrast.

Authentication and workspace screens use the chosen appearance but keep their existing behavior.

## Accessibility

- Every action has a minimum 44 by 44 pt target.
- All controls have meaningful VoiceOver labels, values, and traits.
- Amounts are spoken with their currency and sign, not as unrelated digits.
- Dynamic Type is supported without hiding primary actions.
- Color never carries status alone.
- Reduce Motion stops the dashboard ticker, scanner motion, and nonessential springs.
- Increase Contrast strengthens separators and muted text.
- QR actions have text labels in addition to the symbol.
- Focus order follows the visual task order in the launcher, scanner, forms, and result sheets.

## Endpoint compatibility

The redesign uses the existing `Endpoints` definitions:

- Session and workspace: `/api/me`, `/api/workspaces`, `/api/me/workspaces/bootstrap`, and existing email authentication routes.
- Dashboard: `/summary` and `/annual-summary`.
- Activity: the enabled subset of `/expenses`, `/income`, `/savings/entries`, `/bill-splits`, categories, and their existing item routes.
- Savings: `/savings/accounts`, `/savings/entries`, and `/savings/recurring` plus their item routes.
- Cards: `/credit-cards`, `/card-payments/summary`, `/mark-paid`, and `/unmark-paid`.
- Bill splitting: organizer split, draft, item, claim, participant, settlement, payment-method, and scan-receipt routes.
- Public splitting: `/api/split/:shareToken`, `/join`, and `/claims`.

No new endpoint is required for Home, Activity, Cards, the launcher, QR presentation, or the scanner layout. Savings target presentation requires the approved goal fields on the existing savings-account create, update, and response routes. It does not require a second goal resource.

## Data ownership and derived values

- The server owns transaction totals, savings balances, bill shares, versions, settlements, card paid state, and savings goal status.
- The client may compose the Activity timeline from enabled endpoint responses.
- The client may display available-this-month as `netCents - savingsNetCents` using the matching period.
- The client may derive presentation grouping and date labels.
- The client does not invent reimbursement debt for `each_own` or funded state for a goal.
- Cached responses decode older optional fields safely. Missing payer mode remains unavailable rather than defaulting to `me`.

## Navigation and dismissal

- Home opens insight details or all insights.
- Activity opens transaction detail sheets, split detail, and categories.
- Savings opens account detail, entry sheets, and account management.
- Cards opens card detail, record-payment sheets, and card management.
- Signature Scanner owns Capture, Review, Split, and Result in a full-screen stack.
- Settings and workspace selection are profile-owned modals.
- Saving or cancelling a global form returns to its originating tab.
- Deep links to public splits preserve their existing authentication and handoff rules.

## Delivery sequence

Implement the redesign in reviewable phases:

1. Tokens, typography, shapes, controls, appearance, and accessibility helpers.
2. Tab shell, C6 launcher, and expanded satellite menu.
3. Shared amount forms and Signal rows.
4. Home while preserving the existing insight ticker.
5. Activity timeline and filters.
6. Savings, including server-backed goal targets after its Server branch is available.
7. Cards and the approved fortnight navigator.
8. Signature Scanner, payer modes, result, and QR sheet.
9. Authentication, workspace, settings, empty/loading/error polish.
10. Visual regression, accessibility, feature-gate, and endpoint compatibility verification.

Each phase should preserve a runnable app and existing business behavior. Do not bundle unrelated Server changes into the App branch.

## Verification

### Automated

- Existing App model and view-model tests remain green.
- Add pure tests for availability computation, Activity composition, Cards fortnight selection, and appearance token mapping where logic changes.
- Keep bill-split request, decode, conflict, and queue tests green.
- Keep the Server savings-goal suite and typecheck green before App integration.
- Run the App's established static Swift, source, and project checks.
- Do not run `xcodebuild` until the user's agreed manual-build stage.

### Manual

Test at least one compact iPhone and one large iPhone in Dark, Light, and System appearances. Cover Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast, offline mode, stale bill-split versions, and feature combinations.

For bill splits, cover all four accounting combinations:

- I paid it all, by item.
- I paid it all, evenly.
- Each paid their own, by item.
- Each paid their own, evenly.

Verify open claiming, close, reopen, mark paid, undo, settled editing protection, share link, QR scan, public join, pass-the-phone, and queued creation.

For Cards, verify previous, current, next, cross-month, and all-card ranges. Confirm mark-paid writes the resolved due month.

For Savings, verify flexible accounts, partial targets, funded targets, past-due targets, target edits, and accounts decoded from an older response with no target fields.

## Non-goals

- Replacing authentication providers or workspace membership rules.
- Changing ledger accounting semantics.
- Replacing the dashboard insight ranking engine.
- Creating a separate savings-goal resource.
- Redesigning the public Panel.
- Deploying the Server branch or running production migrations.
- Adding ornamental illustration, gradients, or a second brand accent.
