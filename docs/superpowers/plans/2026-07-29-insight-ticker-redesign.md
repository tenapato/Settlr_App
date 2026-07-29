# Dashboard Insight Ticker Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the swipeable row of bordered `InsightTile` cards in the dashboard's Spending Insights Strip with a self-driving, seamlessly-looping ticker tape that the user can still touch to pause, drag, and tap-through to the Categories tab.

**Architecture:** A single new SwiftUI view, `InsightTicker`, replaces `tilesRow`/`InsightTile` inside the existing `SpendingInsightsStrip.swift`. It renders one simplified text line per `SpendingInsight` (dot/nothing + short label + colored value), duplicates that sequence 8× in an `HStack`, and drives a continuously-wrapping `.offset(x:)` from a `TimelineView(.animation)` using elapsed wall-clock time. A single combined `DragGesture(minimumDistance: 0)` freezes the offset on touch-down, follows the finger while dragging, and schedules an auto-resume 2.5s after release; a near-zero-translation release is treated as a tap and fires the existing `onOpenCategories` navigation. `@Environment(\.accessibilityReduceMotion)` swaps the whole thing for a plain static, manually-swipeable row.

**Tech Stack:** SwiftUI only (`TimelineView`, `DragGesture`, `PreferenceKey`, `@Environment(\.accessibilityReduceMotion)`) — no third-party dependencies, no Swift Charts, matching the rest of the app.

## Global Constraints

- iOS 17.0 deployment target, Swift 5.0, dark-mode only (`.preferredColorScheme(.dark)` app-wide) — verified against `Settlr.xcodeproj/project.pbxproj`.
- No third-party dependencies. No Swift Charts anywhere in this app — all charts/animations are hand-rolled with SwiftUI primitives.
- Use `Theme.*` tokens (from `Settlr/Views/Components/DesignSystem.swift`) for all new UI, per that file's own header comment.
- **This project has no XCTest target** (confirmed: no `Tests` group in `project.pbxproj`, no `*Tests*` files anywhere). Every task's "test cycle" below is therefore: (a) `xcodebuild` as the correctness gate (catches type errors and wiring mistakes — SourceKit/editor diagnostics are known to be unreliable for files not freshly indexed, so `xcodebuild` is the only trusted signal), plus (b) a specific, concrete manual check in the iPhone 17 Pro simulator. This mirrors how the rest of the dashboard work in this session was verified — there is no automated test infrastructure to add without a large, unrelated scope expansion.
- Build command (used after every task):
  ```
  cd /Users/pato/Documents/Daemon/Projects/settlr_v2/App && xcodebuild -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath build build
  ```
- Only one file changes in this whole plan: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift`. No new file, so **no `project.pbxproj` edit is needed**.
- Do not create git commits without the user's explicit go-ahead for this session — write out the `git commit` step as documentation of the repo's convention, but pause and ask before actually running it if it hasn't been pre-authorized.

---

## Current state (for context — do not re-derive, this is accurate as of this plan)

`Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift` currently contains, in order: `SpendingInsight` (model, lines 1-25), `SpendingInsights` (engine, lines 27-252), `SpendingCompositionBar` (lines 254-375, **untouched by this plan**), `InsightTile` (lines 377-434, **deleted by this plan**), and `SpendingInsightsStrip` (lines 436-503, whose `tilesRow` property at lines 486-502 is **replaced** by this plan). `SpendingInsight` already has everything the ticker needs: `id: String`, `title: String`, `value: String`, `tone: Tone` (with `.color: Color`), `swatch: Color?`. No changes to the model or engine are required — the "simplified format" from the spec is achieved purely by which fields the new ticker view chooses to render.

---

### Task 1: Ticker building blocks (`TickerWidthKey`, `TickerDot`, `TickerLineView`)

**Files:**
- Modify: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift` (add new code; do not remove anything yet)

**Interfaces:**
- Produces: `private struct TickerWidthKey: PreferenceKey` (`CGFloat`, default `0`), `private struct TickerDot: View`, `private struct TickerLineView: View` (`let insight: SpendingInsight`) — all consumed by Task 2.

- [ ] **Step 1: Add `import Foundation` and the three building-block types**

At the top of the file, change:
```swift
import SwiftUI
```
to:
```swift
import SwiftUI
import Foundation
```

Then add this new section directly above `// MARK: - Insight tile` (i.e., right before the existing `InsightTile` struct at line 377):

```swift
// MARK: - Insight Ticker building blocks

private struct TickerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TickerDot: View {
    var body: some View {
        Text("·")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.faint)
    }
}

private struct TickerLineView: View {
    let insight: SpendingInsight

    var body: some View {
        HStack(spacing: 6) {
            if let swatch = insight.swatch {
                Circle().fill(swatch).frame(width: 6, height: 6)
            }
            Text(insight.title)
                .foregroundStyle(Theme.ink)
            Text(insight.value)
                .foregroundStyle(insight.tone.color)
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```
cd /Users/pato/Documents/Daemon/Projects/settlr_v2/App && xcodebuild -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`. These three types aren't referenced anywhere yet, so this only proves they're syntactically and semantically valid (correct property/protocol conformance) — no visual change occurs.

- [ ] **Step 3: Commit**

```bash
git add Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
git commit -m "Add ticker building blocks for insight strip redesign"
```

---

### Task 2: `InsightTicker` — static layout for both display modes (no interaction yet)

**Files:**
- Modify: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift` (add new `InsightTicker` struct; do not wire it in yet)

**Interfaces:**
- Consumes: `TickerWidthKey`, `TickerDot`, `TickerLineView` from Task 1; `SpendingInsight` (existing model: `id`, `title`, `value`, `tone`, `swatch`).
- Produces: `struct InsightTicker: View` with `init(insights: [SpendingInsight], onTap: @escaping () -> Void = {})`, consumed by Task 4.

- [ ] **Step 1: Add the `InsightTicker` view with both branches, but auto-scroll only runs on a simple always-advancing timeline (no pause/drag/resume yet — that's Task 3)**

Add this directly after the three types from Task 1 (still above `// MARK: - Insight tile`):

```swift
// MARK: - Insight Ticker

struct InsightTicker: View {
    let insights: [SpendingInsight]
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentWidth: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var baseTime: Date?

    private let speed: CGFloat = 30
    private let itemSpacing: CGFloat = 16
    private let repeatCount = 8

    var body: some View {
        Group {
            if reduceMotion {
                staticRow
            } else {
                animatedRow
            }
        }
    }

    private var oneCycle: some View {
        HStack(spacing: itemSpacing) {
            ForEach(insights) { insight in
                TickerLineView(insight: insight)
                TickerDot()
            }
        }
    }

    private var staticRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: itemSpacing) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { i, insight in
                    Button(action: onTap) {
                        TickerLineView(insight: insight)
                    }
                    .buttonStyle(.plain)
                    if i < insights.count - 1 { TickerDot() }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var animatedRow: some View {
        TimelineView(.animation) { timeline in
            HStack(spacing: itemSpacing) {
                ForEach(0..<repeatCount, id: \.self) { _ in oneCycle }
            }
            .offset(x: contentWidth > 0 ? currentOffset(at: timeline.date) : 0)
        }
        .frame(height: 20)
        .clipped()
        .background(
            oneCycle
                .opacity(0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TickerWidthKey.self, value: geo.size.width)
                    }
                )
        )
        .onPreferenceChange(TickerWidthKey.self) { contentWidth = $0 + itemSpacing }
        .onAppear {
            baseOffset = 0
            baseTime = Date()
        }
    }

    private func currentOffset(at date: Date) -> CGFloat {
        guard contentWidth > 0 else { return 0 }
        let elapsed: CGFloat
        if let baseTime {
            elapsed = CGFloat(date.timeIntervalSince(baseTime))
        } else {
            elapsed = 0
        }
        let raw = baseOffset - elapsed * speed
        var wrapped = raw.truncatingRemainder(dividingBy: contentWidth)
        if wrapped > 0 { wrapped -= contentWidth }
        return wrapped
    }
}
```

Note: `oneCycle` puts a `TickerDot()` after every insight, including the last one in the sequence — this is deliberate. When `repeatCount` copies of `oneCycle` sit back-to-back in the outer `HStack`, that trailing dot becomes the separator between the last item of one copy and the first item of the next, so the loop seam gets a dot too, indistinguishable from every other gap.

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`. `InsightTicker` isn't wired into the dashboard yet, so there's still no visual change — this only proves the view itself is valid Swift/SwiftUI (in particular, that `TimelineView`, the `PreferenceKey` plumbing, and the `Date`/`CGFloat` arithmetic all type-check).

- [ ] **Step 3: Commit**

```bash
git add Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
git commit -m "Add InsightTicker view (auto-scroll only, not yet wired in)"
```

---

### Task 3: Add pause-on-touch, drag-to-follow, resume-after-idle, and tap-to-navigate

**Files:**
- Modify: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift` (extend `InsightTicker` from Task 2)

**Interfaces:**
- Consumes: `InsightTicker`'s existing `contentWidth`, `baseOffset`, `baseTime`, `currentOffset(at:)` from Task 2.
- Produces: `InsightTicker` gains full interaction; no new public interface — still just `InsightTicker(insights:onTap:)`.

- [ ] **Step 1: Add drag state, the gesture, and the resume timer to `InsightTicker`**

In the `@State` block, add two more properties (right after `@State private var baseTime: Date?`):

```swift
    @State private var isDragging = false
    @State private var dragTranslation: CGFloat = 0
    @State private var resumeTask: DispatchWorkItem?
```

Update `currentOffset(at:)` to account for dragging — replace the whole method with:

```swift
    private func currentOffset(at date: Date) -> CGFloat {
        guard contentWidth > 0 else { return 0 }
        let raw: CGFloat
        if isDragging {
            raw = baseOffset + dragTranslation
        } else if let baseTime {
            raw = baseOffset - CGFloat(date.timeIntervalSince(baseTime)) * speed
        } else {
            raw = baseOffset
        }
        var wrapped = raw.truncatingRemainder(dividingBy: contentWidth)
        if wrapped > 0 { wrapped -= contentWidth }
        return wrapped
    }
```

Add the gesture and the resume-scheduling helper as new methods on `InsightTicker`, right after `currentOffset(at:)`:

```swift
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    let frozen = currentOffset(at: Date())
                    resumeTask?.cancel()
                    baseOffset = frozen
                    baseTime = nil
                    isDragging = true
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                baseOffset += value.translation.width
                dragTranslation = 0
                isDragging = false
                scheduleResume()
                if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                    onTap()
                }
            }
    }

    private func scheduleResume() {
        let task = DispatchWorkItem { baseTime = Date() }
        resumeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }
```

Finally, attach the gesture and a content-shape (so touches anywhere in the row's frame, not just on the text glyphs, are caught) to `animatedRow` — change:
```swift
        .onPreferenceChange(TickerWidthKey.self) { contentWidth = $0 + itemSpacing }
        .onAppear {
            baseOffset = 0
            baseTime = Date()
        }
    }
```
to:
```swift
        .onPreferenceChange(TickerWidthKey.self) { contentWidth = $0 + itemSpacing }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear {
            baseOffset = 0
            baseTime = Date()
        }
        .onChange(of: insights.map(\.id)) { _, _ in
            resumeTask?.cancel()
            isDragging = false
            dragTranslation = 0
            baseOffset = 0
            baseTime = Date()
        }
    }
```

The `onChange` resets the ticker to a clean auto-scrolling state whenever the insight set changes (e.g., the user switches months) — without it, a stale `baseOffset`/paused `resumeTask` from the previous month's insights could carry over.

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
git commit -m "Add pause/drag/resume/tap interaction to InsightTicker"
```

---

### Task 4: Wire `InsightTicker` into the dashboard, delete `InsightTile`

**Files:**
- Modify: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift`

**Interfaces:**
- Consumes: `InsightTicker(insights:onTap:)` from Tasks 2-3.
- Produces: `SpendingInsightsStrip` (public view, unchanged signature) now renders the ticker instead of the old card row.

- [ ] **Step 1: Delete the entire `InsightTile` struct and its section comment**

Remove the whole block from `// MARK: - Insight tile` (originally line 377) through the end of the `InsightTile` struct (originally line 434) — i.e., delete both this comment line:
```swift
// MARK: - Insight tile
```
and the entire struct below it:

```swift
struct InsightTile: View {
    let insight: SpendingInsight
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.eyebrow)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let swatch = insight.swatch {
                        Circle().fill(swatch).frame(width: 6, height: 6)
                    }
                    Text(insight.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(insight.value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(insight.tone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let detail = insight.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 148, height: 84, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Replace `tilesRow` to use `InsightTicker` instead of the `ScrollView`/`InsightTile` row**

Find this existing property on `SpendingInsightsStrip`:
```swift
    private var tilesRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { i, insight in
                    InsightTile(insight: insight, onTap: onTap)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.8).delay(0.15 + Double(i) * 0.07),
                            value: appeared
                        )
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 24, for: .scrollContent)
    }
```

Replace it with:
```swift
    private var tilesRow: some View {
        InsightTicker(insights: insights, onTap: onTap)
            .padding(.horizontal, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: appeared)
    }
```

Note: the old row used `.contentMargins(.horizontal, 24, for: .scrollContent)` so individual cards could bleed past the screen edge during a swipe. The ticker has no such edge-bleed need (it's a continuous strip, not discrete peeking cards), so it just uses the same `.padding(.horizontal, 24)` every other section of the dashboard uses.

- [ ] **Step 3: Build to verify it compiles and nothing else references the deleted `InsightTile`**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`. If it fails with "cannot find 'InsightTile' in scope", search for any other reference:
```bash
grep -rn "InsightTile" /Users/pato/Documents/Daemon/Projects/settlr_v2/App/Settlr
```
Expected: no matches (the type was only ever used inside this one file, in the code just replaced).

- [ ] **Step 4: Commit**

```bash
git add Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
git commit -m "Replace insight card row with auto-scrolling ticker"
```

---

### Task 5: Full manual verification pass

**Files:** none (verification only)

- [ ] **Step 1: Launch in the simulator**

```bash
cd /Users/pato/Documents/Daemon/Projects/settlr_v2/App && ./run-sim.sh
```
Sign in (test account: `test@test.com` / `panoda13`) and land on the Home tab.

- [ ] **Step 2: Confirm seamless auto-scroll**

Watch the ticker row below the composition bar for at least 10 seconds. Expected: it continuously scrolls right-to-left at a calm, readable pace, and you cannot spot the point where it "loops" — no jump, no blank gap, no visible seam.

- [ ] **Step 3: Confirm touch-to-pause and drag-to-follow**

Press and hold a finger on the ticker. Expected: it stops instantly. Drag left/right while still holding. Expected: it follows your finger 1:1, in both directions, wrapping smoothly past the loop point same as the auto-scroll did.

- [ ] **Step 4: Confirm resume-after-idle**

Release your finger after a drag. Expected: the ticker stays exactly where you left it for a couple of seconds, then quietly resumes auto-scrolling on its own around 2.5s later — no visible jump when it resumes.

- [ ] **Step 5: Confirm tap-to-navigate still works**

Tap (don't drag) anywhere on the ticker. Expected: the tab bar switches to the Categories tab, same as the old `InsightTile` cards did.

- [ ] **Step 6: Confirm the degenerate 1-insight case**

Switch to a month with only one category (or use the existing test account's sparse month from the original bug report). Expected: the ticker still fills the screen width with repeated copies of the single insight, auto-scrolling normally — no dead space, no crash.

- [ ] **Step 7: Confirm the 5-insight case**

Switch to a month with plenty of category/delta data so all ~5 insight tiles qualify. Expected: all of them appear in the loop, each fully readable as it passes, still seamless.

- [ ] **Step 8: Confirm Reduce Motion fallback**

In the Simulator: **Settings → Accessibility → Motion → Reduce Motion → On**. Return to Settlr's dashboard (or relaunch). Expected: the ticker is now a static, manually-swipeable single-line row (no auto-scroll animation) — swipe it manually and confirm items are still tappable to navigate to Categories. Turn Reduce Motion back off when done.

- [ ] **Step 9: Final commit (if not already committed per-task)**

```bash
git add -A
git status
```
Confirm only the expected file(s) are staged, then commit if the user has authorized it for this session.
