import json
import tempfile
import unittest
from pathlib import Path

from openpyxl import Workbook, load_workbook

from traveler_assistant.inventory import (
    InventoryMappings,
    InventorySyncStore,
    ProductCatalog,
    _jdy_error_detail,
    build_preview,
    parse_traveler,
)


def make_traveler(path: Path, items):
    workbook = Workbook()
    main = workbook.active
    main.title = "WorkOrderTraveler"
    main.append(["Name/工厂单名称", "PP0099-KITCHEN"])
    picking = workbook.create_sheet("Pickinglist")
    picking.append(["Picking List领料单"])
    picking.append(["Name/工厂单名称", "PP0099-KITCHEN"])
    picking.append(["Panel板材"])
    picking.append(["No.", "Name名字", "QTY数量"])
    for number, (name, quantity) in enumerate(items, 1):
        picking.append([number, name, quantity])
    workbook.save(path)


def make_catalog(path: Path):
    workbook = Workbook()
    sheet = workbook.active
    sheet.append(["商品类别", "*商品编号", "商品名称", "规格型号", "状态"])
    rows = [
        ("Plywood", "M0004", "3/4 Finished UV2S", "18mm", "启用"),
        ("Hardware", "M1001", "Unihopper Hinge", "", "启用"),
        ("Hardware", "M1068", "Push Open A", "", "启用"),
        ("Hardware", "M1069", "Push Open B", "", "启用"),
        ("Edge band", "M0020", "Woodline 4 Edge Banding", "22mm", "启用"),
    ]
    for row in rows:
        sheet.append(row)
    workbook.save(path)


class InventoryTests(unittest.TestCase):
    def test_browser_error_preserves_specific_reason(self):
        stderr = (
            '{"event":"progress","message":"正在保存"}\n'
            "库存系统自动操作失败：保存需要人工确认：库存不足\n"
        )
        self.assertEqual(_jdy_error_detail(stderr), "保存需要人工确认：库存不足")

    def test_multiline_browser_error_keeps_first_specific_reason(self):
        stderr = (
            "库存系统自动操作失败：locator.hover: Timeout 30000ms exceeded.\n"
            "Call log:\n"
            "；当前页面：https://example.invalid/\n"
        )
        self.assertEqual(_jdy_error_detail(stderr), "locator.hover: Timeout 30000ms exceeded.")

    def test_parse_dynamic_regions_and_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Work Order Traveler(PP0099-KITCHEN).xlsx"
            make_traveler(path, [("18mm--Plywood", 2), ("Hinge", 0)])
            traveler = parse_traveler(path)
            self.assertEqual(traveler.order_name, "PP0099-KITCHEN")
            self.assertEqual(traveler.items[0].quantity, 2)
            self.assertEqual(traveler.zero_items[0].quantity, 0)

    def test_fixed_mapping_and_push_open_expansion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traveler = root / "Work Order Traveler(PP0099-KITCHEN).xlsx"
            catalog = root / "products.xlsx"
            mappings = root / "mappings.json"
            make_traveler(traveler, [("18mm--Plywood", 2), ("Push Open", 3), ("Adjustable shelf holder", 4)])
            make_catalog(catalog)
            workbook = Workbook()
            sheet = workbook.active
            sheet.append(["商品类别", "*商品编号", "商品名称", "规格型号", "状态"])
            for product in ProductCatalog(catalog).products:
                sheet.append([product.category, product.code, product.name, product.spec, product.status])
            sheet.append(["Hardware", "M1013", "Adjustable Shelf Holder", "", "启用"])
            workbook.save(catalog)
            mappings.write_text('{"manual": {}, "ignored": {}}', encoding="utf-8")
            preview = build_preview(traveler, catalog, mappings)
            self.assertTrue(preview.ready)
            self.assertEqual([item.product_code for item in preview.outbound_items], ["M0004", "M1068", "M1069", "M1013"])
            self.assertEqual([item.quantity for item in preview.outbound_items], [2, 3, 3, 4])

    def test_unique_exact_inventory_name_maps_bls36(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traveler = root / "Work Order Traveler(PP0099-PANTRY).xlsx"
            catalog = root / "products.xlsx"
            mappings = root / "mappings.json"
            make_traveler(traveler, [("BLS36", 2)])
            make_catalog(catalog)
            workbook = load_workbook(catalog)
            workbook.active.append(["Hardware", "M1093", "BLS36", "TR-270B", "启用"])
            workbook.save(catalog)
            mappings.write_text('{"manual": {}, "ignored": {}}', encoding="utf-8")
            preview = build_preview(traveler, catalog, mappings)
            self.assertTrue(preview.ready)
            self.assertEqual(preview.outbound_items[0].product_code, "M1093")
            self.assertEqual(preview.outbound_items[0].match_source, "库存商品名称精确匹配")

    def test_ignored_material_requires_reason_and_is_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traveler = root / "Work Order Traveler(PP0099-KITCHEN).xlsx"
            catalog = root / "products.xlsx"
            mappings = root / "mappings.json"
            make_traveler(traveler, [("Old Brand", 1)])
            make_catalog(catalog)
            mappings.write_text(json.dumps({"manual": {}, "ignored": {"Old Brand": "不再采购"}}), encoding="utf-8")
            preview = build_preview(traveler, catalog, mappings)
            self.assertTrue(preview.ready)
            self.assertEqual(preview.ignored_items[0]["reason"], "不再采购")

    def test_edge_quantity_is_rounded_half_up_for_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traveler = root / "Work Order Traveler(PP0099-KITCHEN).xlsx"
            catalog = root / "products.xlsx"
            mappings = root / "mappings.json"
            make_traveler(traveler, [("Edge banding--Woodline 4", 37.75)])
            make_catalog(catalog)
            mappings.write_text('{"manual": {}, "ignored": {}}', encoding="utf-8")
            preview = build_preview(traveler, catalog, mappings)
            self.assertEqual(preview.outbound_items[0].quantity, 38)
            self.assertIn("37.75m→38m", preview.outbound_items[0].match_source)

    def test_edge_prefers_matching_color_abs_banding_with_24mm_suffix(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traveler = root / "Work Order Traveler(PP0099-KITCHEN).xlsx"
            catalog = root / "products.xlsx"
            mappings = root / "mappings.json"
            make_traveler(traveler, [("Edge banding--Ivory Oak", 20.43)])
            make_catalog(catalog)
            workbook = load_workbook(catalog)
            sheet = workbook.active
            sheet.append(["Edge band", "M0145", "Ivory Oak ABS banding 24mm", "1mm*24mm*50M", "启用"])
            sheet.append(["Edge band", "M0146", "Ivory Oak ABS banding 48mm", "1mm*48mm*50M", "启用"])
            sheet.append(["Edge band", "M0147", "Ivory Oak Wood veneer banding 24mm", "0.6mm*24mm*50M", "启用"])
            workbook.save(catalog)
            mappings.write_text('{"manual": {}, "ignored": {}}', encoding="utf-8")
            preview = build_preview(traveler, catalog, mappings)
            self.assertTrue(preview.ready)
            self.assertEqual(preview.outbound_items[0].product_code, "M0145")
            self.assertEqual(preview.outbound_items[0].quantity, 20)
            self.assertIn("ABS banding + 24mm", preview.outbound_items[0].match_source)

    def test_back_panel_8mm_and_9mm_are_bidirectional_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog = root / "products.xlsx"
            mappings = root / "mappings.json"
            make_catalog(catalog)
            workbook = load_workbook(catalog)
            workbook.active.append(["Panel", "M1134", "Rosales 3", "8*1220*2745mm", "启用"])
            workbook.save(catalog)
            mappings.write_text('{"manual": {}, "ignored": {}}', encoding="utf-8")
            for thickness in ("8", "9"):
                traveler = root / f"Work Order Traveler(PP0099-{thickness}MM).xlsx"
                make_traveler(traveler, [(f"{thickness}mm--Rosales 3", 2)])
                preview = build_preview(traveler, catalog, mappings)
                self.assertTrue(preview.ready)
                self.assertEqual(preview.outbound_items[0].product_code, "M1134")

    def test_ignored_mapping_can_be_saved_and_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mappings.json"
            mappings = InventoryMappings(path)
            mappings.save_ignored("Special Material", "不再采购")
            self.assertEqual(
                InventoryMappings(path).ignored_reason("special material"),
                "不再采购",
            )
            InventoryMappings(path).remove_ignored("SPECIAL MATERIAL")
            self.assertIsNone(InventoryMappings(path).ignored_reason("Special Material"))

    def test_manual_mapping_can_be_saved_and_replaces_ignore(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mappings.json"
            mappings = InventoryMappings(path)
            mappings.save_ignored("Special Material", "旧品牌")
            InventoryMappings(path).save_manual("Special Material", "m1093")
            reloaded = InventoryMappings(path)
            self.assertEqual(reloaded.manual_code("special material"), "M1093")
            self.assertIsNone(reloaded.ignored_reason("Special Material"))

    def test_sync_status_changes_with_traveler_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "Work Order Traveler(PP0099-KITCHEN).xlsx"
            catalog_path = root / "products.xlsx"
            mapping_path = root / "mappings.json"
            make_traveler(path, [("18mm--Plywood", 2)])
            make_catalog(catalog_path)
            mapping_path.write_text('{"manual": {}, "ignored": {}}', encoding="utf-8")
            preview = build_preview(path, catalog_path, mapping_path)
            store = InventorySyncStore(root / "sync.json", root / "backups")
            store.save_success(preview, "CK-001")
            self.assertEqual(store.status_for(parse_traveler(path))[0], "已出库")
            make_traveler(path, [("18mm--Plywood", 3)])
            reloaded = InventorySyncStore(root / "sync.json", root / "backups")
            self.assertEqual(reloaded.status_for(parse_traveler(path))[0], "需要更新")


if __name__ == "__main__":
    unittest.main()
