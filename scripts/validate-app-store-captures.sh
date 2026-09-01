#!/bin/sh

set -eu

capture_dir="docs/app-store-assets/captures"
captures="01-dashboard.png 02-activity.png 03-bill-split.png 04-savings.png 05-cards.png"
missing=0

for name in $captures; do
  path="$capture_dir/$name"
  if ! test -f "$path"; then
    echo "Missing real app capture: $path" >&2
    missing=1
  fi
done

if test "$missing" -ne 0; then
  echo "Capture the five screens from the current iOS build before exporting App Store images." >&2
  exit 1
fi

for name in $captures; do
  path="$capture_dir/$name"
  width=$(sips -g pixelWidth "$path" | awk '/pixelWidth/{print $2}')
  height=$(sips -g pixelHeight "$path" | awk '/pixelHeight/{print $2}')
  format=$(sips -g format "$path" | awk '/format:/{print $2}')

  test "$format" = png || { echo "$path must be PNG." >&2; exit 1; }
  test "$width" -ge 1179 || { echo "$path is too narrow ($width px)." >&2; exit 1; }
  test "$height" -ge 2556 || { echo "$path is too short ($height px)." >&2; exit 1; }
  awk -v width="$width" -v height="$height" 'BEGIN { ratio = width / height; exit !(ratio >= 0.44 && ratio <= 0.48) }' || {
    echo "$path is not a full-screen portrait iPhone capture (${width}x${height})." >&2
    exit 1
  }
done

echo "All five real app captures are ready."
