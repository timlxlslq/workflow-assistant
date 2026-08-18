---
name: inventory-management
description: Query inventory, map Traveler materials to products, preview stock sufficiency, and prepare or adjust confirmed inventory outbound documents. Use for panel and edge stock checks, optional hardware checks, order-level material outbound, factory-order hardware outbound, shortages, document reconciliation, and quantity changes after outbound.
---

# Inventory Management

Use the local inventory tools and a reused authenticated inventory Chrome session opened by the App when available; the existing Playwright login path remains the fallback. Never send credentials, browser state, or raw production files to the Agent.

## Workflow

1. Parse the canonical Traveler and local product mappings.
2. For stock checks, query panels and edge by default; include hardware only when the persisted or one-time option requests it.
3. For outbound, group panels and edge under the order number and hardware under selected factory-order names.
4. Show SKU, product name, requested quantity, order/factory-order remarks, shortages, and mapping errors.
5. Pause at the local approval state before any real inventory write.
6. Re-read the created or edited document and store its number, result, and audit record locally.

Read [references/stock-check.md](references/stock-check.md) for queries and [references/outbound.md](references/outbound.md) for writes.

## Boundaries

- Do not compare units across systems.
- Leave warehouse blank; the current account has only Corporation.
- An empty result table means zero stock; do not perform extra display-option steps.
- Allow outbound despite insufficient stock, but show a warning.
- Round edge banding to an integer half-up for outbound; other material quantities must already be integers.
