import os
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

from openpyxl import Workbook, load_workbook

from traveler_assistant.core import Config, RuleError, parse_fittings_groups
from traveler_assistant.inventory import InventoryMappings, set_ignored_mapping
from traveler_assistant.order_workflow import (
    _choose_fittings,
    find_existing_traveler,
    generate_order_traveler,
    parse_order_materials,
    preview_payload,
    preview_order,
    set_ignored,
    update_order_traveler,
)


def make_materials(path: Path, order_id: str = "PP9999", fractional: bool = False, edge: float = 12.5):
    wb = Workbook()
    ws = wb.active
    ws.title = "Sheet1"
    ws["A1"], ws["B1"] = "Job:", order_id
    headers = [
        "Room/section", "", "3/4 Plywood", "5/8 Plywood", "1/4 Plywood",
        "3/4 Finish Panel", "1/4 Finish Panel", "Edge Banding (m)", "Color",
    ]
    for col, value in enumerate(headers, 1):
        ws.cell(2, col).value = value
    ws.append(["Kitchen", "", 2.5 if fractional else 2, 1, 3, 4, 1, edge, "Basalto SM"])
    for col, value in enumerate(["Total Qty:", "", 2.5 if fractional else 2, 1, 3, 4, 1, edge, "Basalto SM"], 1):
        ws.cell(14, col).value = value
    ws["A15"] = "Color Table"
    ws["A16"] = "Color:"
    ws["A17"] = "Sheets (3/4):"
    ws["A18"] = "Sheets (1/4):"
    ws["A19"] = "Edge Banding (m):"
    wb.save(path)


def make_board(path: Path, factory: str, name: str):
    wb = Workbook()
    ws = wb.active
    ws.title = "Page1"
    ws["A2"], ws["B2"] = "订 单 号", factory
    ws["F2"], ws["G2"] = "订单名称", name
    wb.save(path)


def make_fittings(path: Path, groups: list[tuple[str, float]]):
    wb = Workbook()
    ws = wb.active
    ws.title = "Page1"
    cursor = 1
    for factory, hinge_qty in groups:
        ws.cell(cursor, 1).value = "Order No."
        ws.cell(cursor, 3).value = factory
        header = cursor + 5
        ws.cell(header, 3).value = "Name"
        ws.cell(header, 5).value = "Code"
        ws.cell(header, 6).value = "Size"
        ws.cell(header, 11).value = "Quantity"
        ws.cell(header + 1, 3).value = "TestFullHinge"
        ws.cell(header + 1, 5).value = "71T950A"
        ws.cell(header + 1, 9).value = "Piece"
        ws.cell(header + 1, 11).value = hinge_qty
        cursor = header + 3
    wb.save(path)


def make_template(path: Path):
    wb = Workbook()
    main = wb.active
    main.title = "WorkOrderTraveler"
    main["B5"] = ""
    pick = wb.create_sheet("Pickinglist")
    pick["A1"] = "Picking List领料单"
    pick["A3"] = "Name/工厂单名称"
    pick.merge_cells("A3:C3")
    pick.merge_cells("D3:G3")
    pick["D3"] = "=WorkOrderTraveler!B5"
    pick["A4"] = "Panel板材"
    pick.merge_cells("A4:G4")
    pick["A5"] = "No."
    pick["B5"] = "SKU NO."
    pick["C5"] = "Name名字"
    pick.merge_cells("C5:D5")
    pick["E5"] = "Spec规格"
    pick.merge_cells("E5:F5")
    pick["G5"] = "QTY数量"
    for row in range(6, 11):
        pick["A" + str(row)] = row - 5
        pick.merge_cells(start_row=row, start_column=3, end_row=row, end_column=4)
        pick.merge_cells(start_row=row, start_column=5, end_row=row, end_column=6)
    pick["A11"] = "Fitting配件"
    pick.merge_cells("A11:G11")
    pick["A12"], pick["B12"], pick["C12"], pick["E12"], pick["G12"] = "No.", "SKU NO.", "Name名字", "Unit单位", "QTY数量"
    pick.merge_cells("C12:D12")
    pick.merge_cells("E12:F12")
    for row, name in zip(range(13, 17), ("Hinge", "Adjustable shelf holder", "H-Rail", "L-Rail")):
        pick["A" + str(row)] = row - 12
        pick["C" + str(row)] = name
        pick.merge_cells(start_row=row, start_column=3, end_row=row, end_column=4)
        pick.merge_cells(start_row=row, start_column=5, end_row=row, end_column=6)
    pick["A17"] = "Hardware Accessory五金功能件"
    pick.merge_cells("A17:G17")
    pick["A18"], pick["C18"], pick["E18"], pick["G18"] = "No.", "Name名字", "Spec规格", "QTY数量"
    pick.merge_cells("C18:D18")
    pick.merge_cells("E18:F18")
    for row in (19, 20):
        pick.merge_cells(start_row=row, start_column=3, end_row=row, end_column=4)
        pick.merge_cells(start_row=row, start_column=5, end_row=row, end_column=6)
    wb.create_sheet("Purchase List")
    wb.save(path)


class OrderWorkflowTests(unittest.TestCase):
    def test_invalid_empty_dimension_returns_one_business_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.xlsx"
            broken = root / "Fittingslist-broken.xlsx"
            Workbook().save(source)
            with zipfile.ZipFile(source, "r") as src, zipfile.ZipFile(broken, "w") as dst:
                for item in src.infolist():
                    payload = src.read(item.filename)
                    if item.filename == "xl/worksheets/sheet1.xml":
                        payload = payload.replace(b'<dimension ref="A1:A1"/>', b'<dimension ref="A1:?0"/>')
                    dst.writestr(item, payload)
            with self.assertRaises(RuleError) as raised:
                parse_fittings_groups(broken)
            self.assertEqual(raised.exception.code, "fittings_schema")

    def test_single_color_materials_and_integer_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / "PP9999 materials.xlsx"
            make_materials(path)
            _, materials, edge = parse_order_materials("PP9999", path)
            self.assertIn(("panel", 19.1, "Basalto SM", 4), [(x.kind, x.thickness, x.color, x.quantity) for x in materials])
            self.assertEqual(edge, {"Basalto SM": 12.5})
            make_materials(path, fractional=True)
            with self.assertRaises(RuleError) as raised:
                parse_order_materials("PP9999", path)
            self.assertEqual(raised.exception.code, "fractional_material")

    def test_integer_display_format_uses_the_total_qty_values_excel_shows(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "PP0068 materials.xlsx"
            make_materials(path)
            wb = load_workbook(path)
            ws = wb.active
            for coordinate, value in {"C14": 10.25, "D14": 0.75, "E14": 3.25, "F14": 6.25}.items():
                ws[coordinate] = value
                ws[coordinate].number_format = "0;\\-0;;@"
            wb.save(path)
            _, materials, _ = parse_order_materials("PP0068", path)
            quantities = {(item.kind, item.thickness): item.quantity for item in materials}
            self.assertEqual(quantities[("plywood", 18.0)], 10)
            self.assertEqual(quantities[("plywood", 14.5)], 1)
            self.assertEqual(quantities[("plywood", 5.4)], 3)
            self.assertEqual(quantities[("panel", 19.1)], 6)

    def test_duplicate_fittings_use_newest_and_tied_conflict_stops(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            older = root / "A" / "Fittingslist-old.xlsx"
            newer = root / "B" / "Fittingslist-new.xlsx"
            older.parent.mkdir()
            newer.parent.mkdir()
            make_fittings(older, [("F999", 2)])
            make_fittings(newer, [("F999", 5)])
            now = time.time()
            os.utime(older, (now - 30, now - 30))
            os.utime(newer, (now, now))
            selected, warnings = _choose_fittings(root)
            self.assertEqual(selected["F999"][0].quantity, 5)
            self.assertTrue(any("修改时间最新" in warning for warning in warnings))
            os.utime(older, (now, now))
            with self.assertRaises(RuleError) as raised:
                _choose_fittings(root)
            self.assertEqual(raised.exception.code, "fittings_timestamp_tie")

    def test_global_ignore_and_generate_one_order_workbook(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            order = root / "PP9999"
            report_a = order / "A" / "Report"
            report_b = order / "B" / "Report"
            report_a.mkdir(parents=True)
            report_b.mkdir(parents=True)
            make_materials(order / "anything materials final.xlsx")
            make_board(report_a / "板材清单-a.xlsx", "F100", "PP9999-KITCHEN")
            make_board(report_b / "板材清单-b.xlsx", "F200", "PP9999-LAUNDRY")
            make_fittings(report_a / "Fittingslist-a.xlsx", [("F100", 4), ("F200", 7)])
            make_fittings(report_b / "Fittingslist-b.xlsx", [("F100", 4), ("F200", 7)])
            template = root / "template.xlsx"
            make_template(template)
            config = Config(
                source_root=root,
                order_root=root / "orders",
                template=template,
                backup_root=root / "backups",
                state_dir=root / "state",
            )
            preview = preview_order(config, order)
            first_key = preview.factories[0].fittings[0].key
            set_ignored(config, first_key, True)
            preview = preview_order(config, order)
            self.assertTrue(preview.factories[0].fittings[0].ignored)
            ignored_name = preview.factories[0].fittings[0].name
            mapping_path = config.state_dir / "inventory" / "mappings.json"
            self.assertIsNotNone(InventoryMappings(mapping_path).ignored_reason(ignored_name))
            set_ignored_mapping(config, ignored_name, False)
            preview = preview_order(config, order)
            self.assertFalse(preview.factories[0].fittings[0].ignored)
            set_ignored(
                config,
                preview.factories[0].fittings[0].key,
                True,
                preview.factories[0].fittings[0].name,
            )
            preview = preview_order(config, order)
            self.assertTrue(preview.factories[0].fittings[0].ignored)
            output = generate_order_traveler(config, preview)
            wb = load_workbook(output, data_only=False)
            self.assertEqual(wb.sheetnames[:3], ["WorkOrderTraveler", "Usage List", "Pickinglist"])
            self.assertEqual(wb["WorkOrderTraveler"]["B5"].value, "PP9999")
            picking = wb["Pickinglist"]
            values = [picking.cell(row, 1).value for row in range(1, picking.max_row + 1)]
            self.assertEqual(values.count("Name/工厂单名称"), 2)
            self.assertEqual(picking["A1"].value, "Picking List领料单")
            self.assertEqual(picking["A1"].alignment.horizontal, "center")
            self.assertEqual(picking["A1"].alignment.vertical, "center")
            self.assertIn("A1:G1", {str(item) for item in picking.merged_cells.ranges})
            name_rows = [
                row for row in range(1, picking.max_row + 1)
                if picking.cell(row, 1).value == "Name/工厂单名称"
            ]
            self.assertNotEqual(
                picking.cell(name_rows[0], 1).fill.fgColor.rgb,
                picking.cell(name_rows[1], 1).fill.fgColor.rgb,
            )
            self.assertTrue(
                any(
                    all(picking.cell(row, col).value is None for col in range(1, 8))
                    for row in range(name_rows[0] + 1, name_rows[1])
                )
            )
            self.assertEqual(find_existing_traveler(config, "PP9999"), output)
            self.assertEqual(preview_payload(config, preview)["existing_traveler"], str(output))

            wb["WorkOrderTraveler"]["C5"] = "人工填写内容"
            wb.save(output)
            materials_wb = load_workbook(order / "anything materials final.xlsx")
            materials_wb.active["C14"] = 8
            materials_wb.save(order / "anything materials final.xlsx")
            refreshed = preview_order(config, order)
            updated, backup = update_order_traveler(config, refreshed)
            self.assertEqual(updated, output)
            self.assertTrue(backup.is_file())
            updated_wb = load_workbook(updated, data_only=False)
            self.assertEqual(updated_wb["WorkOrderTraveler"]["C5"].value, "人工填写内容")
            self.assertEqual(updated_wb["Usage List"]["C14"].value, 8)
            self.assertEqual(updated_wb.sheetnames.count("Usage List"), 1)


if __name__ == "__main__":
    unittest.main()
