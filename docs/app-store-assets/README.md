# Settlr App Store screenshots

The compositor is [app-store-screenshots.html](./app-store-screenshots.html). It renders one opaque portrait canvas at **1284 × 2778 px**, with `?slide=1` through `?slide=5` selecting the campaign frame. The five phone screens are generated in HTML from the current SwiftUI hierarchy and Signal Black design tokens. No screenshot inputs are required.

Apple source note: this set targets the accepted **6.5-inch** iPhone screenshot size (**1284 × 2778**). App Store screenshot sets allow **1–10** images; export as **JPG or PNG with no alpha channel**.

Final export filenames:

- `01-dashboard.jpg`
- `02-activity.jpg`
- `03-bill-split.jpg`
- `04-savings.jpg`
- `05-cards.jpg`

Use the JPEGs for App Store Connect. Each final export must be 1284 × 2778 and have no alpha channel. Apple’s live specification is: <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>.

Generation command used for each frame:

```sh
# Repeat with slide=1…5 and the matching output filename.
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1284,2778 \
  --screenshot=01-dashboard.png \
  "file:///absolute/path/app-store-screenshots.html?slide=1"

sips -s format jpeg -s formatOptions 95 \
  01-dashboard.png --out 01-dashboard.jpg
```

The only visual asset referenced by the HTML is `signal-black-background.png`; fonts are system fonts and there are no network dependencies.

Run the parity check from the App directory before exporting:

```sh
./scripts/check-app-store-device-frames.sh
```
