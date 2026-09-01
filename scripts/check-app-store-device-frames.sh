#!/bin/sh

set -eu

html="docs/app-store-assets/app-store-screenshots.html"

test "$(rg -o 'class="screen iphone-device"' "$html" | wc -l | tr -d ' ')" = "5"
rg -q '\.iphone-device::before' "$html"
rg -q '\.iphone-device::after' "$html"
rg -q '\.dynamic-island' "$html"
rg -q '\.device-status' "$html"
rg -q 'aria-label="iPhone frame"' "$html"
rg -Fq 'background-image: linear-gradient(90deg, #f5f5f1, #f5f5f1)' "$html"

echo "App Store device-frame checks passed."
