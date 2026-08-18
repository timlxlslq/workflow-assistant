---
name: traveler-management
description: Preview, create, update, and validate Work Order Traveler workbooks from production Excel files. Use for new Travelers, changed source files, temporary production, mixed-order allocations, Usage List population, Picking List hardware, manual hardware, backups, and update differences.
---

# Traveler Management

Use the typed local Traveler tools. The Agent chooses an operation and explains results; Python performs every Excel read and write.

## Workflow

1. Require an order preview from order-management.
2. Parse and validate all source files before showing a write action.
3. Show material, factory-order, fitting, warning, and difference previews.
4. Create a new Traveler only after validation. For updates, require confirmation and make one backup immediately before replacement.
5. Verify the saved workbook by reopening it.
6. Never trigger inventory outbound automatically.

Read only the relevant branch reference:

- [references/create.md](references/create.md)
- [references/update.md](references/update.md)
- [references/manual-hardware.md](references/manual-hardware.md)
- [references/workbook-contract.md](references/workbook-contract.md)

## Boundaries

- Use only the bundled project template.
- Accept only canonical sheet names; reject malformed workbooks.
- Preserve user-entered hardware only inside the `Hardware Accessory五金功能件` area and associate it with one factory order.
- Do not contain Excel-writing code in this Skill.
