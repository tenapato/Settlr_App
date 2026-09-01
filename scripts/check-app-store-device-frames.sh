#!/bin/sh

set -eu

html="docs/app-store-assets/app-store-screenshots.html"

test "$(rg -o 'class="screen iphone-device"' "$html" | wc -l | tr -d ' ')" = "5"
test "$(rg -o 'class="app-capture"' "$html" | wc -l | tr -d ' ')" = "5"
test "$(rg -o 'src="\./captures/[^"]*\.png"' "$html" | wc -l | tr -d ' ')" = "5"
rg -q '\.iphone-device::before' "$html"
rg -q '\.iphone-device::after' "$html"
rg -q '\.device-viewport' "$html"
rg -q 'object-fit: cover' "$html"
rg -q '\.device-viewport\.capture-loaded \.app-capture' "$html"
rg -q 'aria-label="iPhone frame"' "$html"

if rg -q 'dashboard-screen|activity-screen|split-flow|savings-screen|cards-screen|device-status|dynamic-island' "$html"; then
  echo "Synthetic app UI remains in the App Store compositor." >&2
  exit 1
fi

echo "App Store device-frame checks passed."
