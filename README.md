# Settlr iOS App

Native SwiftUI app for Settlr — track expenses and income from your phone, backed by the same `Server/` Cloudflare Worker API.

## Features

- Login / signup (email + password)
- Workspace picker + create workspace
- Dashboard: monthly net balance, income vs. expenses, top categories
- Expenses: list, add, delete (with category and payment channel)
- Income: list, add, delete (with category)
- Settings: account info, workspace info, switch workspace, sign out

## Tech

- Swift 5.10 + SwiftUI (iOS 17+)
- URLSession for networking — no third-party dependencies
- Keychain for secure Bearer token storage
- `@Observable` macro for state management

---

## Test locally

### Prerequisites

- Xcode 16 or later
- iOS 17+ simulator (or a physical device)
- The `Server/` worker running locally via `wrangler dev`

### Steps

1. **Start the backend**
   ```bash
   cd ../Server
   bun run dev          # or: npx wrangler dev
   # Server listens on http://127.0.0.1:8787
   ```

2. **Update the dev base URL** (first time only)

   Open `Settlr/Network/APIClient.swift` and update the `#if DEBUG` URL to point to your local worker or deployed dev worker:
   ```swift
   #if DEBUG
   return "http://localhost:8787"   // local wrangler dev
   // return "https://settlr-api-dev.<account>.workers.dev"  // deployed dev
   #else
   return "https://settlr.tenapatricio.com"
   #endif
   ```
   > The local simulator uses the host machine's `localhost` by default. If using a physical device on the same Wi-Fi, replace `localhost` with your Mac's local IP.

3. **Open the project**
   ```bash
   open App/Settlr.xcodeproj
   ```

4. **Select a simulator target** — e.g. iPhone 16 (iOS 17+)

5. **Build and run** — press `Cmd + R` or click the ▶ button.

---

## Deploy to production (App Store / TestFlight)

### One-time setup

1. In Xcode, open **Signing & Capabilities** for the Settlr target.
2. Set your **Team** (Apple Developer account).
3. The bundle ID is `com.settlr.app` — change it if it conflicts.

### Archive and distribute

1. Set the scheme to **Release**:
   - Product → Scheme → Edit Scheme → Run → Build Configuration: **Release**
   - Or just choose `Any iOS Device (arm64)` as the build destination.

2. **Archive**:
   ```
   Product → Archive
   ```
   Xcode builds the app and opens the Organizer when done.

3. **Distribute**:
   - Click **Distribute App** in the Organizer.
   - Choose **TestFlight & App Store** (or **TestFlight Internal Only** for quick testing).
   - Follow the prompts — Xcode handles signing and uploading.

4. The `Release` build flag switches the API client to:
   ```
   https://settlr.tenapatricio.com
   ```
   Make sure the prod worker is deployed before distributing.

### Automatic TestFlight deployment

The workflow in `.github/workflows/testflight.yml` runs the tests and uploads a
new build to TestFlight on every push to `main`. You can also run it manually
from the repository's **Actions** tab.

The GitHub repository needs these Actions secrets:

- `APP_STORE_CONNECT_API_KEY_ID`: the Key ID shown in App Store Connect
- `APP_STORE_CONNECT_ISSUER_ID`: the Issuer ID shown in App Store Connect
- `APP_STORE_CONNECT_API_KEY_BASE64`: the downloaded `AuthKey_*.p8` file
- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`: an exported Apple Distribution `.p12`
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`: the password used when exporting the `.p12`
- `APPLE_PROVISIONING_PROFILE_BASE64`: the App Store Connect `.mobileprovision` profile for `cash.settlr.app`

To prepare the signing files, open **Xcode → Settings → Accounts**, select team
`49T6266TLB`, and choose **Manage Certificates → + → Apple Distribution**.
Export that certificate and its private key as a password-protected `.p12` from
the **My Certificates** section of Keychain Access. Then create an **App Store
Connect** distribution profile for `cash.settlr.app` in the Apple Developer
portal, select the same distribution certificate, and download the generated
`.mobileprovision` file.

Open **Settings → Secrets and variables → Actions** in the GitHub repository,
then create each secret. Convert the three files to single-line Base64 strings
without printing their contents in your terminal:

```bash
/usr/bin/base64 -i AuthKey_YOUR_KEY_ID.p8 | pbcopy
/usr/bin/base64 -i SettlrDistribution.p12 | pbcopy
/usr/bin/base64 -i Settlr_App_Store_CI.mobileprovision | pbcopy
```

Run one command at a time and paste the clipboard into the matching GitHub
secret. Keep the original `.p8` and `.p12` files somewhere secure. Apple only
lets you download an App Store Connect API private key once.

The workflow creates the build number as `YYYYMMDD.GITHUB_RUN_NUMBER`, so each
upload has a newer build number without changing the Xcode project file.

## Expense Shortcuts (Wallet and Back Tap)

Settings → **Expense Shortcuts** contains setup instructions for both methods.
The app exposes **Wallet Payment → Settlr** (Amount, Merchant, optional Card or
Pass and Name) and **Quick Expense** (blank draft) through App Intents.
Connect Wallet transaction variables directly to the Wallet action; no
Dictionary or separate URL-building action is required. Apple documents the
[transaction trigger](https://support.apple.com/guide/shortcuts/apd65c67538a/ios).

Both actions open Settlr for review. Requests wait in memory during login and
workspace selection; multiple requests are queued separately. An existing
expense or split form is preserved and must be closed before the next draft
opens. Settings closes automatically for an incoming request. Signing out
clears queued requests. Force-quitting
loses unsaved drafts. The review shows the destination workspace and Wallet
card label, and requires an explicit payment-method choice. Wallet card names
are not automatically matched to Settlr cards. The existing ledger supports
cash and credit cards; choose the appropriate method in that ledger. Amounts
use the existing ledger currency and are not converted. A failed save keeps the
editable form and displays the server error. Nothing is saved until confirmed.

### Validation on macOS / iPhone

Run `ExpenseAutomationTests` along with the existing Xcode test suite. Then:

1. Find both Settlr actions in Shortcuts after installing the build.
2. Run Wallet Payment with Amount `12.34`, Merchant `Coffee Shop`, and a card
   label. Check the draft, category/card selection, and destination workspace.
3. Test a cold launch, logged-out launch, missing workspace, blank fields,
   disabled expenses, two queued requests, cancellation, and a failed save.
4. Confirm a successful save appears on Activity and the Dashboard.
5. Follow the in-app Wallet guide on an iPhone with a real payment card. Verify
   transaction variables with an actual tap; the simulator cannot validate the
   Wallet transaction trigger. Check foregrounding with the phone locked too.
6. Assign Quick Expense to Back Tap and verify it opens a blank draft.
7. Run an action while Settings or another form is already presented to verify
   presentation behavior on the supported iOS versions.

The Linux development host cannot build SwiftUI/App Intents or run iOS tests;
Xcode and device validation are required before release.
