#!/bin/sh
set -eu

binary="/tmp/settlr-dashboard-month-state-test.$$"
module_cache="/tmp/settlr-dashboard-month-state-cache.$$"
trap 'rm -f "$binary"; rm -rf "$module_cache"' EXIT
mkdir -p "$module_cache"

swiftc -module-cache-path "$module_cache" Settlr/Models/DashboardMonthState.swift scripts/dashboard-month-state-regression.swift -o "$binary"
"$binary"
