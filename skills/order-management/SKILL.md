---
name: order-management
description: Discover, index, classify, and inspect production-order folders from Optimized Orders and CUT TO SIZE. Use for order-list refreshes, changed-folder checks, abnormal folder names, PC batch relationships, temporary production folders, and mixed-order allocation preparation.
---

# Order Management

Use the typed local tools for all filesystem reads. Never inspect or mutate the server directly from model-generated code.

## Workflow

1. Identify whether the request targets Optimized Orders or CUT TO SIZE.
2. Read the local order index first; refresh only folder and required Excel modification times when requested.
3. Apply the configured cutoff date. Do not scan older folders.
4. Classify each folder as unprocessed, Traveler generated, changed, ignored, abnormal, temporary, or mixed-order.
5. Return a structured preview. Do not generate a Traveler or write inventory from this skill.
6. Pause for user input when an abnormal or mixed folder cannot be classified deterministically.

Read [references/discovery.md](references/discovery.md) for scan and status rules. Read [references/mixed-orders.md](references/mixed-orders.md) only for mixed-order or temporary-production work.

## Boundaries

- Treat exact local commands as zero-token operations; use an Agent only after local parsing fails.
- Do not query AIMES for recent PC detection or missing factory names.
- Do not hide folders. Show completed and ignored folders in gray.
- Do not add compatibility rules for old folder formats.
