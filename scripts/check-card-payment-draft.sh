#!/bin/sh
set -eu

binary="/tmp/settlr-card-payment-draft-test.$$"
module_cache="/tmp/settlr-card-payment-draft-cache.$$"
trap 'rm -f "$binary"; rm -rf "$module_cache"' EXIT
mkdir -p "$module_cache"

swiftc -module-cache-path "$module_cache" \
  Settlr/Models/CardPaymentsSummary.swift \
  scripts/card-payment-draft-regression.swift \
  -o "$binary"
"$binary"
