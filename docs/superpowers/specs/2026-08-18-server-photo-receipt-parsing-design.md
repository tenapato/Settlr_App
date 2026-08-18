# Server Photo Receipt Parsing Design

## Purpose

Add an explicit receipt-parsing option that sends the receipt photo and the phone's recognized text to the server for higher-accuracy parsing. The existing `Automatic`, `On device`, and `On server` modes remain unchanged. Automatic mode never uploads a photo.

The feature spans:

- `App/`: preference, disclosure, image preparation, multipart upload, scan status, and response decoding.
- `Server/`: bounded multipart handling, vision transcription, text-model structuring, deterministic reconciliation, quota accounting, and parser metadata.

## Success Criteria

1. Settings contains four choices: `Automatic`, `On device`, `On server`, and `On server + photo`.
2. A photo is uploaded only when the user explicitly selected `On server + photo`.
3. The new mode sends a resized receipt image and local OCR text together.
4. The server uses the photo to improve row recognition, then applies the existing deterministic quantity and money rules.
5. The image is never written to D1, R2, KV, logs, analytics, or another persistent store.
6. A scan response identifies whether photo parsing succeeded or fell back to text-only parsing.
7. A model cannot silently make a mismatched receipt appear reconciled; uncertain rows and total differences remain visible in review.
8. One user-initiated scan consumes one monthly receipt-parse quota unit even though photo mode makes two internal inference calls.
9. Existing clients and the existing JSON text-only request remain compatible.

## User Experience

### Preferences

Keep the existing preference values and add a fourth stored value, `serverPhoto`.

The picker labels are:

- `Automatic`
- `On device`
- `On server`
- `On server + photo`

Automatic continues to prefer on-device parsing and may fall back only to the existing text-only server route. It never falls back to photo upload because that would bypass explicit consent.

The disclosure for `On server + photo` is:

> The receipt photo and recognized text are sent securely to the server for AI parsing. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library. The AI provider does not use it to train its models.

The existing text-only disclosure remains:

> Only recognized receipt text is sent for parsing. The photo stays on this phone.

### Scan status

While photo mode is active, the scanner displays:

> Sending the photo and recognized text to the server. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library.

The response metadata controls the final parser banner. A successful photo parse displays `On server + photo`. A text fallback displays `On server` and a review warning explaining that the server could not use the image.

## App Data Flow

The app still runs local Vision OCR for every captured receipt. Local OCR is useful evidence and preserves compatibility with the existing parsing paths.

When `serverPhoto` is selected:

1. Normalize the image orientation.
2. Resize it so its longest edge is at most 2048 pixels.
3. Encode it as JPEG with a target quality of 0.8.
4. Reject the upload locally if the encoded image exceeds 6 MiB and offer text-only parsing or manual entry.
5. Send `multipart/form-data` to the existing authenticated scan endpoint with:
   - `photo`: JPEG bytes with a filename and `image/jpeg` content type;
   - `text`: locally recognized OCR text.
6. Keep the image only for the duration of the active scan request. Do not add it to the durable offline queue.

The other three preferences continue sending the existing JSON `{ "text": string }` body.

The networking layer gains a bounded multipart request helper rather than base64-encoding the photo inside JSON. Multipart avoids base64 size overhead and preserves explicit file metadata.

## Server Request Handling

The existing receipt-scan endpoint remains backward compatible:

- `application/json`: existing text-only behavior.
- `multipart/form-data`: new photo-assisted behavior.

Before reading multipart content, the Worker:

1. Rejects a declared body larger than 7 MiB.
2. Parses the form once.
3. Requires a non-empty `text` field.
4. Requires exactly one `photo` file.
5. Accepts only JPEG or PNG input.
6. Rejects image bytes larger than 6 MiB after parsing, regardless of the declared length.

The Worker holds the image only in request memory. It does not log the form, filename, image bytes, base64 representation, OCR text, or model prompt.

## Two-Pass Parsing

### Pass 1: visual transcription

Use `@cf/google/gemma-4-26b-a4b-it` as the photo model. It is a vision-capable model intended for document parsing and multilingual OCR.

The prompt asks for a layout-preserving receipt transcription rather than final financial calculations. It must:

- preserve one printed row per output line;
- preserve the leading quantity column;
- preserve the full item label, including numbers inside names;
- copy the rightmost printed money token character-for-character;
- include subtotal, tax, tip, fee, and total lines;
- avoid translating, expanding, correcting, or computing values.

The local OCR text is included as secondary evidence. The model is told to resolve unclear glyphs from the photo and never invent a row merely because it appears in local OCR.

### Pass 2: semantic structuring

Feed the visual transcript to the existing `@cf/meta/llama-3.3-70b-instruct-fp8-fast` receipt parser. The current semantic-row prompt and output validation remain in use.

The server then applies deterministic evidence reconstruction:

- visual transcript is the primary row evidence;
- local OCR is secondary evidence for rows that the visual transcript cannot confidently preserve;
- quantities come only from a leading quantity column;
- prices come only from the rightmost money token on the same row;
- repeated names consume distinct rows in order;
- short labels are not fuzzy matched;
- totals and components are copied, not inferred;
- rows that cannot be reconciled remain unverified.

The evidence merger must not concatenate both transcripts and accidentally create duplicates. It selects or reconciles corresponding rows before semantic parsing.

### Failure behavior

If the photo is invalid, the vision model times out, returns no usable transcript, or is unavailable, the server runs the existing text-only parser with the supplied local OCR. The response:

- reports the text parser as the parser used;
- includes a warning that photo parsing was unavailable and text-only parsing was used;
- preserves all normal unverified-row and total-mismatch warnings.

The server never silently labels a fallback as photo parsing.

## Response Contract

Extend parser metadata additively:

```ts
type ReceiptParser = "on_device" | "server" | "server_photo";

type ReceiptParseMetadata = {
  parser: ReceiptParser;
  requestedParser?: "server_photo";
  fallback?: "server";
};
```

Existing clients continue decoding `on_device` and `server`. The iOS decoder also accepts legacy `cloudflare` as text-only `server`.

For a photo request that falls back, the response uses `parser: "server"`, `requestedParser: "server_photo"`, and `fallback: "server"`.

## Quotas and Usage

Perform the existing quota check once before either model runs. A successful user request records one `receipt` usage event.

For photo mode, combine the token usage from both inference calls into that event. A failed vision pass followed by a successful text fallback still records one successful scan with the tokens actually consumed. A request that returns no usable receipt does not consume the monthly scan count, matching existing behavior.

## Privacy and Security

- Photo upload requires explicit preference selection.
- Automatic mode cannot upload photos.
- Transport uses the existing authenticated HTTPS API.
- The endpoint enforces content type and byte limits before inference.
- Image content and OCR text are never included in structured logs or error messages.
- No image storage binding is introduced.
- The server does not persist the photo. If the user enables Save captures to Photos, the app saves a local copy to the user's photo library.
- Workers AI customer content is not used for model training without explicit consent.

## Error Handling

- `400`: missing text/photo or malformed multipart form.
- `413`: request or image exceeds the configured size limit.
- `415`: unsupported image media type.
- `422`: neither photo-assisted nor text-only parsing produced usable receipt rows.
- `403`: existing monthly AI quota reached.
- `503`: AI binding unavailable.

The app preserves the captured image during the active editor session so the user can retry immediately. It does not persist the image to the offline queue. Network failure offers retry, `On server`, or manual entry.

## Testing

### App

- preference decoding preserves all four options and legacy values;
- Automatic and text-only server modes never attach image data;
- photo mode creates multipart data with JPEG and OCR fields;
- image resizing and size rejection are deterministic;
- parser metadata renders the correct final legend;
- photo fallback displays a visible warning;
- the disclosure appears only for the photo mode;
- the image is released when the scan/editor session ends.

### Server

- existing JSON request remains unchanged;
- valid multipart request reaches photo parsing;
- missing, duplicate, unsupported, and oversized files are rejected;
- request size is checked before buffering;
- visual transcript and local OCR rows reconcile without duplication;
- quantity and price reconstruction uses same-row evidence;
- vision failure invokes text fallback with accurate metadata and warning;
- successful photo mode combines token usage and consumes one quota unit;
- no request content appears in logs or persisted usage data.

### Manual verification

Use the supplied problematic receipt in all four modes. In photo mode, verify the leading quantity remains separate from numbers inside the item name, repeated rows retain their own prices, totals reconcile or remain explicitly flagged, and the UI accurately identifies photo parsing or fallback.

Do not deploy, migrate, stage, commit, or build the iOS app as part of implementation. The user will build and manually test at the end.

## Rollout

1. Release the backward-compatible Worker endpoint and photo parser.
2. Release the iOS fourth preference and multipart client.
3. Observe parse failures, latency, quota consumption, and fallback rates without logging receipt content.

The old text-only request remains supported throughout rollout.
