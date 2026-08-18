# Order discovery

- Sources: `Optimized Orders` for owned orders and `CUT TO SIZE` for supplied-material orders.
- Track whether the order folder exists and read the required material, board-list, and fittings-list Excel modification times; do not treat order-folder mtime alone as a business change.
- A folder without a generated Traveler does not need change tracking.
- A generated Traveler whose relevant source times changed is `changed` and may be updated after preview.
- Stop scanning folders older than the shared adjustable cutoff date.
- Keep a small SQLite index under the project-local ignored data directory; do not create migration code.
- If a new folder name is abnormal, notify the user. Once ignored, retain the decision and show the row in gray.
