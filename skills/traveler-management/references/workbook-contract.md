# Workbook contract

The first three sheets, in order, are:

1. `WorkOrderTraveler`
2. `Usage List`
3. `Picking List`

`Usage List` rules:

- Write detail rows starting at row 3. Do not vertically merge repeated room names; blank names inherit the preceding room for room-level reporting.
- Keep plywood totals only on `Total Qty:`.
- Group panel and edge totals by color in `Color Table`.
- When detail rows exceed the template capacity, insert rows before `Total Qty:` and extend all formulas to the new last detail row.

`Picking List` rules:

- Create one separate block per factory-order name.
- For a CUT TO SIZE order with no factory orders, keep a full-width formatted empty state that points to `Usage List` and states that no hardware picking is required.
- Keep automatic fittings and manual hardware in their defined sections.
- A factory-order name starts with its owning order number and is treated as stable.
