# Create Traveler

- Refuse to overwrite an existing canonical Traveler.
- Fill `WorkOrderTraveler`, populate the template's existing `Usage List`, and build `Picking List` blocks per factory order.
- CUT TO SIZE creates a materials-only Traveler and ignores fittings files. Its `Picking List` keeps a formatted empty-state message that directs the user to `Usage List`; it must never collapse to a title-only sheet.
- Preview inventory availability only when the user requests it; query the server folder's aggregate materials for mixed folders.
