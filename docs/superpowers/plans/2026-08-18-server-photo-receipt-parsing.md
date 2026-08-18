# Server Photo Receipt Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicitly selected `On server + photo` receipt mode that combines server vision, local OCR, the existing text parser, and deterministic receipt reconciliation without server-side photo storage. The existing user-controlled Save captures to Photos option may save a local library copy.

**Architecture:** The iOS app always performs local OCR, but only the new explicit preference prepares a bounded JPEG and sends multipart data. The Worker transcribes the image with Gemma 4, structures the transcript with the existing Llama 3.3 parser, reconciles it with local OCR evidence, and falls back visibly to text-only parsing if vision fails.

**Tech Stack:** SwiftUI, UIKit image encoding, XCTest, Cloudflare Workers, Workers AI, TypeScript, Bun tests.

**Spec:** `docs/superpowers/specs/2026-08-18-server-photo-receipt-parsing-design.md`

## Global Constraints

- Preserve `Automatic`, `On device`, and `On server`; add `On server + photo`.
- Automatic must never upload a photo.
- Send photo bytes only after explicit selection of `On server + photo`.
- Maximum prepared image: JPEG, 2048-pixel longest edge, quality 0.8, 6 MiB.
- The Worker must not persist or log image bytes, OCR text, prompts, or transcripts.
- Keep the existing JSON text-only request backward compatible.
- One user action consumes one receipt-parse quota unit.
- Apply deterministic quantity, same-row price, and total reconciliation after model output.
- Keep every App and Server edit unstaged and uncommitted.
- Do not deploy, migrate, or run `xcodebuild`; the user will build and test the app.

---

### Task 1: Vision Transcript Boundary

**Files:**
- Create: `Server/src/lib/receiptPhotoParser.ts`
- Create: `Server/src/lib/receiptPhotoParser.test.ts`
- Read: `Server/src/lib/receiptParser.ts`
- Read: `Server/src/lib/statement-parsers/ai-statement-parser.ts`

**Interfaces:**
- Consumes: `Ai`, `normalizeTokenUsage`, `extractAiResponseText`, and `AiStatementTokenUsage`.
- Produces:

```ts
export const RECEIPT_VISION_MODEL = "@cf/google/gemma-4-26b-a4b-it";
export const MAX_RECEIPT_IMAGE_BYTES = 6 * 1024 * 1024;

export type ReceiptPhotoTranscript = {
  text: string;
  tokenUsage: AiStatementTokenUsage;
};

export async function transcribeReceiptPhoto(
  ai: Ai,
  imageBytes: Uint8Array,
  mediaType: "image/jpeg" | "image/png",
  localOcrText: string,
): Promise<ReceiptPhotoTranscript>;
```

- [ ] **Step 1: Write failing model-request tests**

Create Bun tests with a fake `Ai.run` that capture the model and options. Assert the function selects Gemma 4, includes one bounded image payload, includes the local OCR as secondary evidence, requests a layout-preserving transcript, rejects empty/oversized images, and returns normalized token usage.

```ts
expect(request.model).toBe("@cf/google/gemma-4-26b-a4b-it");
expect(request.options.messages).toEqual(expect.arrayContaining([
  expect.objectContaining({ role: "user" }),
]));
expect(request.options.image).toStartWith("data:image/jpeg;base64,");
expect(result.text).toContain("2   RUTA KAKUNI SHOYU RAMEN   100.00");
expect(result.tokenUsage.totalTokens).toBe(35);
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `cd Server && bun test src/lib/receiptPhotoParser.test.ts`

Expected: FAIL because `receiptPhotoParser.ts` and its exports do not exist.

- [ ] **Step 3: Implement bounded photo transcription**

Build the data URI from the validated `Uint8Array`, call `env.AI.run` through the passed binding, and use a fixed prompt that requires one visual receipt row per output line. The prompt must explicitly preserve leading quantities, names containing numbers, the rightmost printed amount, and subtotal/tax/tip/fee/total rows without computation.

Use a 45-second timeout and reject an empty response with a user-safe error. Do not log request content or model output.

- [ ] **Step 4: Run focused tests and typecheck**

Run:

```bash
cd Server
bun test src/lib/receiptPhotoParser.test.ts
npm run typecheck
```

Expected: all focused tests pass and TypeScript exits 0.

- [ ] **Step 5: Leave an unstaged review checkpoint**

Run: `git diff --check && git status --short`

Expected: the new files and any prior user work remain unstaged; the index remains unchanged.

---

### Task 2: Evidence Selection and Two-Pass Receipt Parsing

**Files:**
- Modify: `Server/src/lib/receiptParser.ts`
- Modify: `Server/src/lib/receiptParser.test.ts`
- Create: `Server/src/lib/receiptPhotoPipeline.ts`
- Create: `Server/src/lib/receiptPhotoPipeline.test.ts`

**Interfaces:**
- Consumes: `transcribeReceiptPhoto`, `parseReceiptText`, and the existing `ParsedReceipt` type.
- Produces:

```ts
export type PhotoReceiptParseResult = {
  receipt: ParsedReceipt;
  parser: "server_photo" | "server";
  requestedParser: "server_photo";
  fallback: "server" | null;
};

export async function parseReceiptPhotoWithFallback(
  ai: Ai,
  imageBytes: Uint8Array,
  mediaType: "image/jpeg" | "image/png",
  localOcrText: string,
  maxItems: number,
): Promise<PhotoReceiptParseResult>;
```

- [ ] **Step 1: Write failing evidence-merger tests**

Export a pure helper with this interface:

```ts
export function chooseReceiptEvidence(
  visualText: string,
  localText: string,
): { text: string; warnings: string[] };
```

Test that corresponding rows appear once, a visually recovered priced row missing from local OCR is retained, a local row missing from vision is retained only as unverified secondary evidence, repeated item names preserve receipt order, and `1 XX AMB 23 105.00` cannot become quantity 23.

- [ ] **Step 2: Run the focused pipeline tests and confirm RED**

Run: `cd Server && bun test src/lib/receiptPhotoPipeline.test.ts`

Expected: FAIL because the pipeline and evidence helper do not exist.

- [ ] **Step 3: Implement conservative evidence selection**

Normalize rows for comparison without removing internal digits. Match exact normalized rows first, then conservative same-name/rightmost-money matches. Preserve visual rows as primary, append unmatched local rows with an internal unverified marker understood by the parser, and never concatenate both complete transcripts.

Update `parseReceiptText` only as needed to propagate evidence warnings and combine `AiStatementTokenUsage` values without weakening current deterministic `applyPrintedAmounts` rules.

- [ ] **Step 4: Implement the two-pass pipeline and visible fallback**

Call `transcribeReceiptPhoto`, select evidence, then call `parseReceiptText`. If transcription throws or yields no usable priced row, call `parseReceiptText` with local OCR and append:

```text
Photo parsing was unavailable. The receipt was parsed from recognized text and needs review.
```

Return `parser: "server"`, `requestedParser: "server_photo"`, and `fallback: "server"` on fallback. Combine tokens actually consumed by both attempts.

- [ ] **Step 5: Run parser and pipeline tests**

Run:

```bash
cd Server
bun test src/lib/receiptParser.test.ts src/lib/receiptPhotoParser.test.ts src/lib/receiptPhotoPipeline.test.ts
npm run typecheck
```

Expected: all tests pass and TypeScript exits 0.

---

### Task 3: Backward-Compatible Multipart Receipt Endpoint

**Files:**
- Modify: `Server/src/routes/billSplits.ts`
- Create: `Server/src/routes/receiptScanRequest.ts`
- Create: `Server/src/routes/receiptScanRequest.test.ts`

**Interfaces:**
- Consumes: `parseReceiptText`, `parseReceiptPhotoWithFallback`, quota helpers, and `WorkspaceRequest`.
- Produces:

```ts
export type ReceiptScanInput =
  | { mode: "text"; text: string }
  | {
      mode: "photo";
      text: string;
      bytes: Uint8Array;
      mediaType: "image/jpeg" | "image/png";
    };

export async function readReceiptScanInput(request: Request): Promise<ReceiptScanInput>;
```

- [ ] **Step 1: Write failing request-boundary tests**

Cover existing JSON, valid JPEG multipart, missing text, missing photo, duplicate photo fields, unsupported media type, declared body above 7 MiB, and actual file above 6 MiB. Assert errors map to 400, 413, or 415 without echoing OCR or filenames.

- [ ] **Step 2: Run request tests and confirm RED**

Run: `cd Server && bun test src/routes/receiptScanRequest.test.ts`

Expected: FAIL because `readReceiptScanInput` does not exist.

- [ ] **Step 3: Implement request parsing with pre-buffer limits**

For JSON, retain `{ text }`. For multipart, reject an oversized numeric `Content-Length` before calling `formData()`, then validate the parsed `File`, MIME type, and actual bytes. Return typed input only; do not log body content.

- [ ] **Step 4: Route both modes through one quota transaction**

Refactor `handleScanReceipt` to:

```ts
const input = await readReceiptScanInput(req);
const parsed = input.mode === "photo"
  ? await parseReceiptPhotoWithFallback(env.AI, input.bytes, input.mediaType, input.text, maxItems)
  : { receipt: await parseReceiptText(env.AI, input.text, maxItems), parser: "server" as const };
```

Record one successful `receipt` usage event with combined token totals and return additive parser/fallback metadata. Preserve the existing quota check and JSON response fields.

- [ ] **Step 5: Run the complete Server suite**

Run:

```bash
cd Server
bun test
npm run typecheck
git diff --check
```

Expected: all tests pass, typecheck exits 0, and no staged files exist.

---

### Task 4: iOS Preference and Parser Metadata

**Files:**
- Modify: `App/Settlr/Models/BillSplit.swift`
- Modify: `App/SettlrTests/ParserPreferenceTests.swift`
- Modify: `App/Settlr/Views/Main/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: existing `ReceiptParserPreference`, `ReceiptParserKind`, and `ScannedReceipt` decoding.
- Produces:

```swift
enum ReceiptParserPreference: String, CaseIterable, Identifiable {
    case automatic, onDevice, server, serverPhoto
}

enum ReceiptParserKind: String, Codable {
    case onDevice = "on_device"
    case server
    case serverPhoto = "server_photo"
}

struct ReceiptParseMetadata: Decodable {
    let requestedParser: ReceiptParserKind?
    let fallback: ReceiptParserKind?
}
```

- [ ] **Step 1: Add failing parser-preference tests**

Assert four display names in order, `server_photo` decoding, legacy `cloudflare` decoding to `.server`, photo and text privacy legends, and fallback metadata decoding.

- [ ] **Step 2: Run the focused XCTest source/typecheck path and confirm RED**

Do not run `xcodebuild`. Use the repository's static Swift test/typecheck command or, if unavailable, run `swiftc -parse` plus the source regression script. Expected: failure from the missing fourth cases before implementation.

- [ ] **Step 3: Implement model cases and disclosures**

Add the exact picker label `On server + photo` and exact disclosure:

```text
The receipt photo and recognized text are sent securely to the server for AI parsing. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library. The AI provider does not use it to train its models.
```

Keep existing disclosures unchanged. Automatic must retain text-only fallback semantics.

- [ ] **Step 4: Run focused static verification**

Run:

```bash
cd App
swiftc -parse Settlr/Models/BillSplit.swift Settlr/Views/Main/Settings/SettingsView.swift SettlrTests/ParserPreferenceTests.swift
./scripts/check-app-source-regressions.sh
```

Expected: both commands exit 0.

---

### Task 5: iOS Image Preparation and Multipart Transport

**Files:**
- Create: `App/Settlr/Network/ReceiptPhotoUpload.swift`
- Create: `App/SettlrTests/ReceiptPhotoUploadTests.swift`
- Modify: `App/Settlr/Network/APIClient.swift`
- Modify: `App/Settlr.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:

```swift
enum ReceiptPhotoUploadError: LocalizedError, Equatable {
    case couldNotEncode
    case imageTooLarge
}

struct PreparedReceiptPhoto: Equatable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ReceiptPhotoUpload {
    static let maxLongestEdge = 2048
    static let jpegQuality: CGFloat = 0.8
    static let maxBytes = 6 * 1024 * 1024

    static func prepare(_ image: UIImage) throws -> PreparedReceiptPhoto
    static func multipartBody(
        boundary: String,
        photo: PreparedReceiptPhoto,
        ocrText: String
    ) -> Data
}
```

- [ ] **Step 1: Add failing pure-helper tests**

Test landscape and portrait resizing, no upscaling, JPEG media headers, exact `photo` and `text` field names, UTF-8 OCR, closing boundary, and deterministic oversized rejection using injected encoding data where necessary.

- [ ] **Step 2: Verify RED without building the app**

Run the repository's static XCTest source/typecheck command. If the environment cannot load iOS macros without a build, use `swiftc -parse` and add source-regression assertions for the constants and multipart field names. Expected: failure because the helper does not exist.

- [ ] **Step 3: Implement image preparation and multipart encoding**

Normalize orientation through a renderer, preserve aspect ratio, cap the longest edge, encode once at quality 0.8, and enforce the final byte limit. Multipart must contain only the two required parts and must not base64-encode the image.

- [ ] **Step 4: Add a bounded APIClient upload method**

Add:

```swift
func uploadReceiptPhoto<Response: Decodable>(
    _ path: String,
    photo: PreparedReceiptPhoto,
    ocrText: String,
    timeout: TimeInterval = 75
) async throws -> Response
```

Use the existing authorization, error decoding, deactivation handling, and offline classification. Set `Content-Type: multipart/form-data; boundary=...` and `Content-Length`; do not add the request to `PendingSplitQueue`.

- [ ] **Step 5: Register files and run static checks**

Run:

```bash
cd App
git diff --name-only -- '*.swift' | xargs swiftc -parse
plutil -lint Settlr.xcodeproj/project.pbxproj
./scripts/check-app-source-regressions.sh
git diff --check
```

Expected: all commands exit 0 and the index remains empty.

---

### Task 6: Connect Photo Mode to Both Scan Entry Points

**Files:**
- Modify: `App/Settlr/ViewModels/BillSplitVM.swift`
- Modify: `App/Settlr/Views/Main/Split/SplitScanFlow.swift`
- Modify: `App/Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `App/Settlr/Views/Main/Split/ScanningOverlay.swift`
- Modify: `App/Settlr/Views/Main/Split/ReceiptCaptureView.swift`
- Modify: `App/SettlrTests/ParserPreferenceTests.swift`

**Interfaces:**
- Consumes: `ReceiptPhotoUpload.prepare`, `APIClient.uploadReceiptPhoto`, parser metadata, and current local OCR.
- Produces:

```swift
@MainActor
func scanReceipt(
    workspaceId: String,
    text: String,
    image: UIImage?
) async throws -> ScannedReceipt
```

- [ ] **Step 1: Add failing routing tests**

Extend the pure router tests so `Automatic`, `On device`, and `On server` never call the photo closure. Assert `serverPhoto` requires an image, calls only the photo closure, reports `.serverPhoto` on success, and preserves `.server` plus the fallback warning from the response.

- [ ] **Step 2: Verify RED**

Run the focused static XCTest source/typecheck path. Expected: failure because the router has no photo closure or preference case.

- [ ] **Step 3: Add the explicit photo route**

Extend `ReceiptParserRouter` with:

```swift
let serverPhoto: (_ ocrText: String, _ image: UIImage) async throws -> ScannedReceipt
```

Only `.serverPhoto` may invoke it. Pass the captured image from both `SplitScanFlow.handleCapture` and `SplitCreateSheet.handleCapture`; all other modes ignore it after local OCR.

- [ ] **Step 4: Make scanner copy reflect the actual attempt**

During the request show:

```text
Sending the photo and recognized text to the server. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library.
```

After response, use returned parser/fallback metadata rather than the selected preference. Preserve the existing reset before OCR so a previous scan cannot leak stale privacy copy.

- [ ] **Step 5: Verify App sources without building**

Run:

```bash
cd App
git diff --name-only -- '*.swift' | xargs swiftc -parse
./scripts/check-app-source-regressions.sh
plutil -lint Settlr.xcodeproj/project.pbxproj
git diff --check
git diff --cached --quiet
```

Expected: all commands exit 0; no app build runs and nothing is staged.

---

### Task 7: Final Cross-Repository Review

**Files:**
- Review all files changed by Tasks 1–6.
- Modify only files required to resolve review findings.

**Interfaces:**
- Consumes: the completed App/Server feature.
- Produces: a clean, backward-compatible, privacy-reviewed unstaged diff.

- [ ] **Step 1: Run the full Server verification**

Run:

```bash
cd Server
bun test
npm run typecheck
git diff --check
git diff --cached --quiet
```

Expected: all commands exit 0.

- [ ] **Step 2: Run the allowed App verification**

Run:

```bash
cd App
git diff --name-only -- '*.swift' | xargs swiftc -parse
./scripts/check-app-source-regressions.sh
plutil -lint Settlr.xcodeproj/project.pbxproj
git diff --check
git diff --cached --quiet
```

Expected: all commands exit 0. Do not run `xcodebuild`.

- [ ] **Step 3: Review privacy and compatibility invariants**

Confirm from the diff that:

- JSON text-only scans still work;
- Automatic cannot reach multipart upload;
- photo bytes/OCR/transcripts are absent from logs and persistence;
- both declared and actual byte limits are enforced;
- fallback parser metadata and warning are truthful;
- one scan records one quota event with combined usage;
- no App or Server changes are staged or committed.

- [ ] **Step 4: Hand off manual tests**

Report the exact modified files, tests executed, deferred `xcodebuild`, and the four-mode manual test sequence from the spec. Do not deploy or commit.
