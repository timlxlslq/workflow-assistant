# Mixed and temporary orders

- Recognize a PC batch from report filenames. In `PC124429962607280001`, `260728` means 2026-07-28 and `0001` is that day's sequence.
- One PC batch can contain rooms from multiple orders; the same order can have several PC batches.
- For mixed folders, allocate panel and edge quantities by identifiable order data when possible.
- If exact allocation is unavailable, present area-share guidance, propose rounded quantities, and require user confirmation.
- Persist confirmed allocation into each order's Traveler.
- For a temporary production folder, generate from available report/material files and let the user record the owning order in remarks.
