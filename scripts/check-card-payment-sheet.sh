#!/bin/sh
set -eu

endpoints="Settlr/Network/Endpoints.swift"
root="Settlr/Views/Main/CardsRootView.swift"
payments="Settlr/Views/Main/CardPaymentsView.swift"

if ! rg -q 'static func monthlyCardPayments' "$endpoints" ||
   ! rg -q '/card-payments/monthly-payments' "$endpoints"; then
  echo "Endpoints must expose the monthly card-payment route." >&2
  exit 1
fi

if ! rg -q 'CardPaymentRecordSheet' "$root" ||
   ! rg -q 'onRecordPayment' "$root" ||
   ! rg -q 'canUsePayments' "$root" ||
   ! rg -q 'invalidateRecordPresentation' "$root" ||
   ! rg -q '\.onDisappear \{ invalidateRecordPresentation\(\) \}' "$root"; then
  echo "Cards root must gate and present the record-payment sheet." >&2
  exit 1
fi

if rg -q 'guard canUsePayments, isCurrentWorkspace, let paymentVM else' "$root"; then
  echo "An already-unwrapped CardPaymentsVM must not be conditionally bound again." >&2
  exit 1
fi

if ! rg -q 'struct CardPaymentRecordSheet: View' "$payments" ||
   ! rg -q 'Endpoints\.monthlyCardPayments' "$payments" ||
   ! rg -q 'HeroAmountField' "$payments" ||
   ! rg -q 'interactiveDismissDisabled' "$payments" ||
   ! rg -q 'month: card\.resolvedDueMonthKey' "$payments" ||
   ! rg -q 'Retry refresh' "$payments" ||
   ! rg -q 'recordPaymentRefreshFailed' "$payments" ||
   ! rg -q 'isPresentationCurrent' "$payments" ||
   ! rg -q 'guard !Task\.isCancelled, isPresentationCurrent\(\)' "$payments" ||
   rg -U -q 'FormCard \{[[:space:]]*SignalNativeFormRow' "$payments"; then
  echo "Record-payment sheet must use the monthly endpoint and protect an in-flight save." >&2
  exit 1
fi

echo "Card payment sheet source checks passed."
