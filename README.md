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

### CI/CD (optional)

Use `xcodebuild` in GitHub Actions or similar:
```bash
xcodebuild archive \
  -project App/Settlr.xcodeproj \
  -scheme Settlr \
  -archivePath build/Settlr.xcarchive \
  -configuration Release \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```
