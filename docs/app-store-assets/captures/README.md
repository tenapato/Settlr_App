# Real app captures

Place five untouched, full-screen PNG captures from the current iOS build in this directory:

- `01-dashboard.png`: Dashboard with the live carousel visible.
- `02-activity.png`: Activity timeline with the Type and Time filters collapsed.
- `03-bill-split.png`: The Items step in the guided Setup, Items, Confirm flow.
- `04-savings.png`: Savings with a goal target and recent entries visible.
- `05-cards.png`: Cards with one open payment and one paid card visible.

Use the same iPhone model, appearance, text size, workspace, and status-bar state for every capture. Remove personal data. Do not crop, retouch, add a frame, or resize the PNGs.

The files must be at least 1179 by 2556 pixels. Run this check from the App directory:

```sh
./scripts/validate-app-store-captures.sh
```

The compositor adds the campaign copy and the outer iPhone frame. It does not redraw or modify the app interface.
