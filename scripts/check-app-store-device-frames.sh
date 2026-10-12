#!/bin/sh

set -eu

html="docs/app-store-assets/app-store-screenshots.html"
expected_width=1284
expected_height=2778

rg -q 'content="width=1284,height=2778,initial-scale=1"' "$html"
rg -q 'html, body \{ width: 1284px; height: 2778px;' "$html"
rg -q '\.canvas \{ position: relative; width: 1284px; height: 2778px;' "$html"

test "$(rg -o 'class="screen iphone-device"' "$html" | wc -l | tr -d ' ')" = "5"
test "$(rg -o 'class="app-screen' "$html" | wc -l | tr -d ' ')" = "5"
for screen in dashboard activity bill-split savings cards; do
  rg -q "data-ui=\"$screen\"" "$html"
done
rg -q '\.iphone-device::before' "$html"
rg -q '\.iphone-device::after' "$html"
rg -q '\.device-viewport' "$html"
rg -q 'aria-label="iPhone frame"' "$html"
rg -q "THIS MONTH'S SIGNAL" "$html"
rg -q 'ACTIVITY TYPE' "$html"
rg -q 'Check total' "$html"
rg -q '2 items · 2 people · \$283\.00' "$html"
rg -q 'YOUR GOALS' "$html"
rg -q 'PAYMENT DUE' "$html"
rg -q 'Any time' "$html"
rg -q '>Splits<' "$html"
rg -q 'Monday, Aug 31' "$html"
rg -q 'Sunday, Aug 30' "$html"
rg -q '<b>Review Items</b><span>Cancel</span>' "$html"
rg -q '<span class="review-pill">Needs review</span><span class="review-pill selected">All</span>' "$html"
rg -q '<b>Soda</b><span>Shared</span>' "$html"
rg -q 'class="warning-icon"' "$html"
rg -q 'class="plus-icon"' "$html"
rg -q '\.sticky-action.*background: var\(--bg\)' "$html"
rg -q '<span class="goal-status">IN PROGRESS</span><span class="row-chevron"' "$html"
rg -q '<b>Daily buffer</b></div><span class="row-chevron"' "$html"
rg -q '<span>Emergency fund</span>' "$html"
rg -q '<span>Daily buffer</span>' "$html"
rg -q '•••• •••• •••• 4821' "$html"
rg -q '<b>BBVA Gold</b><small>•••• 4821</small>' "$html"
rg -q '>Mark as paid<' "$html"
rg -q '\.tab-icon\.activity::before.*border-left' "$html"
rg -q '\.tab-icon\.activity::after.*border-right' "$html"
rg -q '\.workspace-copy > span' "$html"
rg -q 'class="icon-button add-plain"' "$html"
rg -q 'class="calendar-icon"' "$html"
rg -q '<span class="goal-dot"></span><b>Daily buffer</b>' "$html"
rg -q '<strong class="money mxn">\$1,450\.00</strong><span>Flexible</span>' "$html"
rg -q 'MXN \$8,650\.00' "$html"
rg -q 'MXN \$7,200\.00' "$html"
rg -q 'MXN \$1,450\.00' "$html"
rg -q 'by 2026-12-31' "$html"
rg -q 'linear-gradient\(145deg, #0b1a3d, #142d6b\)' "$html"
rg -q 'left: -55px; top: -55px' "$html"
rg -q '\.item-row \+ \.item-row::before.*left: 16px' "$html"
rg -q '\.card-chip.*#4db8ff' "$html"
rg -q '\.card-chip.*rgba\(77,184,255,.18\)' "$html"
rg -q '\[data-ui="savings"\] \.toolbar button:first-child::before' "$html"
rg -q '\[data-ui="savings"\] \.symbol\.filter' "$html"
rg -q '\.fortnight-label.*display: none' "$html"
rg -q '\.flex-card strong.*font-size: 25px' "$html"
rg -q '\.flex-balance > span.*font-size: 12px' "$html"
rg -q '\.flex-card b.*font-size: 16px' "$html"
rg -q '\.flex-balance > span.*color: var\(--muted\).*font-size: 12px' "$html"

if rg -q 'app-capture|captures/|Real app capture required|Table service|>Reset<|>This month⌄<|>Today<|>Yesterday<|Qty 1|IN PROGRESS ›|Emergency fund · Today|Daily buffer · Aug 29|△|＋ Add item|min-height: 82px|\.flex-card span|background: linear-gradient\(135deg,#d9c17b,#7b6944\)|content: "↕"|linear-gradient\(180deg, rgba\(9,10,11,.68\)' "$html"; then
  echo "Generated preview parity regression detected." >&2
  exit 1
fi

test ! -e scripts/validate-app-store-captures.sh
if rg -q 'captures/|validate-app-store-captures' docs/app-store-assets/README.md; then
  echo "Screenshot-input instructions remain in the App Store asset README." >&2
  exit 1
fi

if rg -q '1320|2868' "$html" docs/app-store-assets/README.md; then
  echo "Obsolete 6.9-inch dimensions remain in the export pipeline." >&2
  exit 1
fi

for image in docs/app-store-assets/0[1-5]-*.jpg docs/app-store-assets/0[1-5]-*.png; do
  width="$(sips -g pixelWidth "$image" | awk '/pixelWidth/{print $2}')"
  height="$(sips -g pixelHeight "$image" | awk '/pixelHeight/{print $2}')"
  test "$width" = "$expected_width"
  test "$height" = "$expected_height"
done

echo "App Store device-frame checks passed."
