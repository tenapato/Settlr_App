# Final App Fix Report

## Scope

- Removed destructive `clearClaims` mutations from quantity, price, and allocation-mode field bindings.
- Added `SplitDraft.claimImpact(comparedTo:)` to compare the edited draft with the original server snapshot and identify only changed or removed items that already have claims.
- Added an explicit save confirmation listing affected item names. Cancel leaves the draft and claims untouched; confirmation sends `clearClaims` only for the confirmed affected IDs.
- Changed pass-the-phone remainder copy to “of the bill is still unassigned” so tax, tip, fees, and other unallocated remainder are not described as item claims.

## Focused source tests added

- Changed versus unchanged/unclaimed item claim-impact coverage.
- Removed claimed item claim-impact coverage.
- Edit-body coverage proving only explicitly confirmed IDs receive `clearClaims`.

## Verification

- `swiftc -parse` on the changed Swift sources and focused test source: passed.
- `git diff --check`: passed.
- Confirmed no App source still assigns `clearClaims` from an editing field binding.
- No app build run, per request; manual testing remains with the requester.
