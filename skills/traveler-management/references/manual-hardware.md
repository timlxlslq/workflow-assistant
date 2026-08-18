# Manual hardware

- Add manual hardware only after Traveler generation or update.
- Require one target factory-order name at write time.
- Resolve the SKU, name, and specification from the local product catalog; do not query live stock.
- Require a positive integer quantity. Aggregate an existing row only when factory-order name, SKU, and specification all match.
- Show the full item preview and require local approval before writing.
- Back up the Traveler immediately before an atomic replacement, then reopen it to verify the saved row.
- Keep factory orders separate in `Picking List`; do not display an order-level hardware total.
- Do not query inventory when hardware is added. Include it only in a later requested stock check or outbound preview.
